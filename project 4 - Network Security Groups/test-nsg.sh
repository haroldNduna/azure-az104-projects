#!/usr/bin/env bash
# =============================================================================
# Project 04 – Live NSG test
#
# Run AFTER ./deploy.sh. This script:
#   1. Deploys 3 small Ubuntu VMs (one per tier) with NO public IPs and NO
#      NIC-level NSGs, so only the subnet NSGs are being tested.
#   2. Starts tiny test listeners: app VM on TCP 8080, data VM on TCP 1433.
#   3. Runs real connection tests FROM INSIDE the VMs using 'az vm run-command'
#      (like running a script via SCCM/PsExec – no SSH or open ports needed).
#   4. Runs Network Watcher IP flow verify (like Cisco 'packet-tracer'),
#      which names the exact rule that allowed or denied each flow.
#   5. Saves everything to test-results.txt.
#
# COST: 3 x Standard_B1s VMs = a few cents per hour. Run ./cleanup.sh when done.
# Override the VM size if B1s is unavailable:  VM_SIZE=Standard_B1ms ./test-nsg.sh
# Free trial quota is usually 4 vCPUs per region, so keep to 1-vCPU sizes.
# =============================================================================
set -euo pipefail

RG="rg-az104-project04"
VNET="vnet-az104-project04"
VM_SIZE="${VM_SIZE:-Standard_B1s}"
IMAGE="Ubuntu2204"
ADMIN_USER="azureuser"
TAGS=(Environment=Lab CostCenter=IT-Services "Owner=Harold Nduna" Project=AZ104-Project04 Purpose=NSG-Test)

WEB_IP="10.10.1.4"
APP_IP="10.10.2.4"
DATA_IP="10.10.3.4"
BASTION_TEST_IP="10.10.254.4"   # a pretend admin source in the Bastion subnet
INTERNET_TEST_IP="13.107.21.200" # any public IP, used only by IP flow verify

# Copy all output to test-results.txt as evidence for the repo
exec > >(tee test-results.txt) 2>&1

# ----------------------------- Pre-flight ------------------------------------
if ! az account get-access-token --output none 2>/dev/null; then
  echo "Not logged in or session expired. Running 'az login'..."
  az login --output none
fi

if [[ "$(az group exists --name "$RG")" != "true" ]]; then
  echo "Resource group $RG not found. Run ./deploy.sh first."
  exit 1
fi

# Network Watcher must be enabled in the region for IP flow verify.
# Azure normally enables it automatically; this makes sure.
LOCATION=$(az group show --name "$RG" --query location --output tsv)
if [[ "$(az group exists --name NetworkWatcherRG)" != "true" ]]; then
  az group create --name NetworkWatcherRG --location "$LOCATION" --output none
fi
az network watcher configure --resource-group NetworkWatcherRG --locations "$LOCATION" --enabled true --output none

# ----------------------------- cloud-init listeners --------------------------
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

# Writes a cloud-init file that runs a tiny Python web server on <port> as a
# systemd service – a stand-in for a real app server / database listener.
make_cloud_init() {
  local port=$1 file=$2
  cat > "$file" <<EOF
#cloud-config
package_update: false
package_upgrade: false
write_files:
  - path: /etc/systemd/system/lab-listener.service
    content: |
      [Unit]
      Description=AZ-104 lab test listener on TCP ${port}
      After=network-online.target
      [Service]
      ExecStart=/usr/bin/python3 -m http.server ${port} --directory /tmp
      Restart=always
      [Install]
      WantedBy=multi-user.target
runcmd:
  - systemctl daemon-reload
  - systemctl enable --now lab-listener.service
EOF
}
make_cloud_init 8080 "$WORKDIR/app.yaml"
make_cloud_init 1433 "$WORKDIR/data.yaml"

# ----------------------------- Create VMs (in parallel) ----------------------
# --public-ip-address ""  -> no public IP (not reachable from the internet)
# --nsg ""                -> no NIC-level NSG (az vm create adds one by default!)
create_vm() {
  local name=$1 subnet=$2 ip=$3 cloudinit=${4:-}
  local extra=()
  [[ -n "$cloudinit" ]] && extra=(--custom-data "$cloudinit")
  az vm create \
    --resource-group "$RG" \
    --name "$name" \
    --image "$IMAGE" \
    --size "$VM_SIZE" \
    --vnet-name "$VNET" \
    --subnet "$subnet" \
    --private-ip-address "$ip" \
    --public-ip-address "" \
    --nsg "" \
    --admin-username "$ADMIN_USER" \
    --generate-ssh-keys \
    --storage-sku Standard_LRS \
    --os-disk-delete-option Delete \
    --nic-delete-option Delete \
    --tags "${TAGS[@]}" \
    "${extra[@]}" \
    --output none
}

echo ">> Creating 3 test VMs ($VM_SIZE) in parallel – this takes 2-4 minutes..."
declare -A PIDS
create_vm vm-web  snet-web  "$WEB_IP"                       > "$WORKDIR/vm-web.log"  2>&1 & PIDS[vm-web]=$!
create_vm vm-app  snet-app  "$APP_IP"  "$WORKDIR/app.yaml"  > "$WORKDIR/vm-app.log"  2>&1 & PIDS[vm-app]=$!
create_vm vm-data snet-data "$DATA_IP" "$WORKDIR/data.yaml" > "$WORKDIR/vm-data.log" 2>&1 & PIDS[vm-data]=$!

FAILED=0
for VM in vm-web vm-app vm-data; do
  if wait "${PIDS[$VM]}"; then
    echo "   ✔ $VM created"
  else
    echo "   ✖ $VM failed:"; sed 's/^/     /' "$WORKDIR/$VM.log"; FAILED=1
  fi
done
if [[ $FAILED -eq 1 ]]; then
  echo ""
  echo "One or more VMs failed. Common causes on a free trial:"
  echo "  - SkuNotAvailable: try another size, e.g.  VM_SIZE=Standard_B1ms ./test-nsg.sh"
  echo "  - QuotaExceeded:   the trial allows ~4 vCPUs per region – use 1-vCPU sizes"
  echo "VMs that did succeed are still running – run ./cleanup.sh if you stop here."
  exit 1
fi

# ----------------------------- run-command helper ----------------------------
run_on() {  # run_on <vm> <script>  -> prints the script's stdout
  local out
  if ! out=$(az vm run-command invoke \
      --resource-group "$RG" --name "$1" \
      --command-id RunShellScript --scripts "$2" \
      --query "value[0].message" --output tsv 2>&1); then
    echo "RUNCOMMAND_FAILED"
    return 0
  fi
  echo "$out"
}

echo ""
echo ">> Waiting for the test listeners to start (cloud-init)..."
for PAIR in "vm-app:8080" "vm-data:1433"; do
  VM=${PAIR%%:*}; PORT=${PAIR##*:}
  OUT=$(run_on "$VM" "cloud-init status --wait >/dev/null 2>&1; if ss -ltn | grep -q ':$PORT '; then echo LISTENER=UP; else echo LISTENER=DOWN; fi")
  if grep -q "LISTENER=UP" <<<"$OUT"; then
    echo "   ✔ $VM is listening on TCP $PORT"
  else
    echo "   ⚠ Could not confirm the listener on $VM:$PORT ($(grep -o 'LISTENER=DOWN\|RUNCOMMAND_FAILED' <<<"$OUT" || echo unknown))"
  fi
done

# ----------------------------- Live connection tests -------------------------
# Inside the VM, bash's /dev/tcp opens a TCP connection:
#   exit 0   -> OPEN      : the NSG allowed it and something answered
#   exit 124 -> TIMEOUT   : packets silently dropped = blocked by an NSG
#   other    -> REFUSED   : reached the host but nothing listening (NSG allowed it)
# (On-site: a firewall 'drop' gives a timeout, a closed port gives a 'reset'.)
declare -a RESULTS
PASS=0; TOTAL=0

conn_test() {  # conn_test <label> <source-vm> <dest-host> <port> <expected>
  local label=$1 vm=$2 host=$3 port=$4 expected=$5 out actual status
  local script="timeout 5 bash -c '</dev/tcp/$host/$port' 2>/dev/null; rc=\$?; case \$rc in 0) echo RESULT=OPEN;; 124) echo RESULT=TIMEOUT;; *) echo RESULT=REFUSED;; esac"
  echo "   testing: $label ..."
  out=$(run_on "$vm" "$script")
  actual=$(grep -o 'RESULT=[A-Z]*' <<<"$out" | head -1 | cut -d= -f2)
  [[ -z "$actual" ]] && actual="ERROR"
  TOTAL=$((TOTAL+1))
  if [[ "$actual" == "$expected" ]]; then status="PASS"; PASS=$((PASS+1)); else status="CHECK"; fi
  RESULTS+=("$(printf '%-34s %-9s %-9s %s' "$label" "$expected" "$actual" "$status")")
}

echo ""
echo ">> Running live connection tests from inside the VMs (about 30-60 s each)..."
conn_test "web  -> app  TCP 8080"            vm-web  "$APP_IP"          8080 OPEN
conn_test "app  -> data TCP 1433"            vm-app  "$DATA_IP"         1433 OPEN
conn_test "web  -> data TCP 1433 (skip tier)" vm-web  "$DATA_IP"         1433 TIMEOUT
conn_test "data -> app  TCP 8080 (backwards)" vm-data "$APP_IP"          8080 TIMEOUT
conn_test "app  -> web  TCP 443 (not Internet)" vm-app "$WEB_IP"         443  TIMEOUT
conn_test "data -> internet TCP 443"         vm-data "www.microsoft.com" 443  TIMEOUT

# ----------------------------- IP flow verify --------------------------------
# Asks Azure: "would this packet be allowed, and by which rule?"
# It evaluates NSG rules only – it does not send real traffic.
declare -a FLOWS
FPASS=0; FTOTAL=0

flow_test() {  # flow_test <label> <vm> <direction> <local ip:port> <remote ip:port> <expected Allow|Deny>
  local label=$1 vm=$2 dir=$3 local_ep=$4 remote_ep=$5 expected=$6 out access rule status
  out=$(az network watcher test-ip-flow \
          --resource-group "$RG" --vm "$vm" \
          --direction "$dir" --protocol TCP \
          --local "$local_ep" --remote "$remote_ep" \
          --query "[access, ruleName]" --output tsv 2>/dev/null | tr '\n' ' ') || out="ERROR ERROR"
  read -r access rule <<<"$out"
  FTOTAL=$((FTOTAL+1))
  if [[ "$access" == "$expected" ]]; then status="PASS"; FPASS=$((FPASS+1)); else status="CHECK"; fi
  FLOWS+=("$(printf '%-34s %-7s %-7s %-6s %s' "$label" "$expected" "${access:-?}" "$status" "${rule##*/}")")
}

echo ""
echo ">> Running Network Watcher IP flow verify..."
flow_test "internet -> web  TCP 443"   vm-web  Inbound  "$WEB_IP:443"    "$INTERNET_TEST_IP:50000" Allow
flow_test "web  -> app  TCP 8080"      vm-app  Inbound  "$APP_IP:8080"   "$WEB_IP:50000"           Allow
flow_test "app  -> data TCP 1433"      vm-data Inbound  "$DATA_IP:1433"  "$APP_IP:50000"           Allow
flow_test "bastion -> data TCP 22"     vm-data Inbound  "$DATA_IP:22"    "$BASTION_TEST_IP:50000"  Allow
flow_test "web  -> data TCP 1433"      vm-data Inbound  "$DATA_IP:1433"  "$WEB_IP:50000"           Deny
flow_test "web  -> app  TCP 22"        vm-app  Inbound  "$APP_IP:22"     "$WEB_IP:50000"           Deny
flow_test "data -> internet TCP 443"   vm-data Outbound "$DATA_IP:50000" "$INTERNET_TEST_IP:443"   Deny

# ----------------------------- Report ----------------------------------------
echo ""
echo "======================= LIVE CONNECTION TESTS ======================="
printf '%-34s %-9s %-9s %s\n' "Test" "Expected" "Actual" "Result"
printf '%s\n' "${RESULTS[@]}"
echo "OPEN = allowed and answered | TIMEOUT = dropped by NSG | REFUSED = allowed, nothing listening"
echo "Passed: $PASS / $TOTAL"

echo ""
echo "======================= IP FLOW VERIFY =============================="
printf '%-34s %-7s %-7s %-6s %s\n' "Flow" "Expect" "Actual" "Result" "Deciding rule"
printf '%s\n' "${FLOWS[@]}"
echo "Passed: $FPASS / $FTOTAL"

echo ""
echo "Notes:"
echo " - 'internet -> web' is ALLOWED by the NSG, but vm-web has no public IP, so the"
echo "   internet still can't reach it. IP flow verify only evaluates NSG rules."
echo " - 'data -> internet' is blocked twice: by Deny-Internet-Out AND by the private subnet."
echo " - If a live test shows ERROR/RUNCOMMAND_FAILED, rely on the IP flow verify table."
echo ""
echo "Results saved to test-results.txt"
echo "⚠ The 3 VMs are now running and costing a few cents per hour."
echo "  Take your portal screenshots (effective rules, IP flow verify), then run ./cleanup.sh"
