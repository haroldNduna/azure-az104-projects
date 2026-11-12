#!/usr/bin/env bash
# =============================================================================
# Project 05 – Tests (run AFTER ./deploy.sh)
#
#   1. ASG test        : vm-web1 (asg-web) -> vm-app:8080 ALLOWED
#                        vm-web2 (no ASG, same subnet) -> vm-app:8080 BLOCKED
#   2. Extension test  : data disk mounted at /data, Nginx serving a page from it
#   3. NAT test        : vm-web1 reaches the internet via the NAT public IP
#                        vm-app (no NAT) has no internet
#   4. IP flow verify  : Bastion subnet -> vm-web1 :22 allowed, :3389 denied by NIC NSG
#   5. Effective rules : subnet NSG + NIC NSG on vm-web1
#   6. Power states    : vm-web2 deallocated (no compute charges)
#
# Tests 1-3 use 'az vm run-command' (the "intercom") – no SSH or public IPs.
# Output is saved to test-results.txt.
# =============================================================================
set -euo pipefail

RG="rg-az104-project05"
PIP="pip-nat-az104-project05"
WEB1_IP="10.10.1.4"
APP_IP="10.10.2.4"
BASTION_TEST_IP="10.10.254.4"

exec > >(tee test-results.txt) 2>&1

if ! az account get-access-token --output none 2>/dev/null; then az login --output none; fi
[[ "$(az group exists --name "$RG")" == "true" ]] || { echo "Run ./deploy.sh first."; exit 1; }

# Make sure all VMs are running (auto-shutdown may have deallocated them)
for VM in vm-web1 vm-web2 vm-app; do
  STATE=$(az vm get-instance-view -g "$RG" -n "$VM" --query "instanceView.statuses[?starts_with(code,'PowerState/')].displayStatus | [0]" -o tsv)
  if [[ "$STATE" != "VM running" ]]; then
    echo ">> Starting $VM (was: $STATE)..."
    az vm start -g "$RG" -n "$VM" --output none
  fi
done

run_on() {  # run_on <vm> <script>  -> prints the [stdout] part
  local out
  if ! out=$(az vm run-command invoke -g "$RG" -n "$1" --command-id RunShellScript \
      --scripts "$2" --query "value[0].message" -o tsv 2>&1); then
    echo "RUNCOMMAND_FAILED"; return 0
  fi
  sed -n '/\[stdout\]/,/\[stderr\]/p' <<<"$out" | sed '/\[stdout\]/d;/\[stderr\]/d'
}

declare -a RESULTS
PASS=0; TOTAL=0
record() {  # record <label> <expected> <actual>
  local status="CHECK"
  TOTAL=$((TOTAL+1))
  if [[ "$3" == "$2" ]]; then status="PASS"; PASS=$((PASS+1)); fi
  RESULTS+=("$(printf '%-52s %-14s %-14s %s' "$1" "$2" "$3" "$status")")
}

# ----------------------------- Pre-check: listener ---------------------------
echo ">> Pre-check: is vm-app listening on TCP 8080 (cloud-init)?"
OUT=$(run_on vm-app "cloud-init status --wait >/dev/null 2>&1; ss -ltn | grep -q ':8080 ' && echo LISTENER-UP || echo LISTENER-DOWN")
if grep -q LISTENER-UP <<<"$OUT"; then
  echo "   ✔ LISTENER-UP"
else
  echo "   ⚠ LISTENER-DOWN – cloud-init didn't start it. Repairing with Run command..."
  run_on vm-app "printf '[Unit]\nDescription=AZ-104 Project 05 test application on TCP 8080\nAfter=network-online.target\n[Service]\nExecStart=/usr/bin/python3 -m http.server 8080 --directory /tmp\nRestart=always\n[Install]\nWantedBy=multi-user.target\n' > /etc/systemd/system/app-listener.service; systemctl daemon-reload; systemctl enable --now app-listener.service >/dev/null 2>&1; sleep 3; ss -ltn | grep -q ':8080 ' && echo LISTENER-UP || echo LISTENER-DOWN"
fi

# ----------------------------- Test 1: ASG -----------------------------------
CURL_APP="curl -s -m 5 -o /dev/null http://$APP_IP:8080 && echo ALLOWED || echo BLOCKED"
echo ""
echo "================ TEST 1 – Application Security Groups ================"
A=$(run_on vm-web1 "$CURL_APP" | grep -oE 'ALLOWED|BLOCKED' | head -1 || true)
echo "   vm-web1 (asg-web)            -> vm-app:8080 : ${A:-ERROR}"
record "1a vm-web1 (asg-web) -> vm-app:8080" ALLOWED "${A:-ERROR}"
B=$(run_on vm-web2 "$CURL_APP" | grep -oE 'ALLOWED|BLOCKED' | head -1 || true)
echo "   vm-web2 (no ASG, same subnet) -> vm-app:8080 : ${B:-ERROR}"
record "1b vm-web2 (no ASG, same subnet) -> vm-app:8080" BLOCKED "${B:-ERROR}"

# ----------------------------- Test 2: Extension + disks ---------------------
echo ""
echo "================ TEST 2 – Extension, data disk, temp disk ================"
DISKS=$(run_on vm-web1 "echo '--- Disks ---'; lsblk -o NAME,SIZE,TYPE,MOUNTPOINT; echo '--- Data disk ---'; df -h /data; echo '--- Temporary disk ---'; df -h /mnt 2>/dev/null || echo 'no temp disk mounted'; echo '--- Web page ---'; curl -s http://localhost")
echo "$DISKS"
if grep -q " /data" <<<"$DISKS"; then DATA=MOUNTED; else DATA=MISSING; fi
if grep -q "vm-web1" <<<"$DISKS"; then WEB=SERVING; else WEB=NOT-SERVING; fi
record "2a Data disk mounted at /data" MOUNTED "$DATA"
record "2b Nginx serving page from /data" SERVING "$WEB"

# ----------------------------- Test 3: NAT Gateway ---------------------------
NAT_IP=$(az network public-ip show -g "$RG" -n "$PIP" --query ipAddress -o tsv)
CURL_OUT="curl -s -m 10 https://api.ipify.org && echo || echo NO-INTERNET"
echo ""
echo "================ TEST 3 – NAT Gateway (controlled egress) ================"
echo "   NAT Gateway public IP: $NAT_IP"
W=$(run_on vm-web1 "$CURL_OUT" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}|NO-INTERNET' | head -1 || true)
echo "   vm-web1 outbound IP  : ${W:-ERROR}"
if [[ "$W" == "$NAT_IP" ]]; then record "3a vm-web1 egress via NAT public IP" NAT-IP NAT-IP
else record "3a vm-web1 egress via NAT public IP" NAT-IP "${W:-ERROR}"; fi
P=$(run_on vm-app "$CURL_OUT" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}|NO-INTERNET' | head -1 || true)
echo "   vm-app outbound      : ${P:-ERROR}"
record "3b vm-app (private subnet, no NAT) egress" NO-INTERNET "${P:-ERROR}"

# ----------------------------- Test 4: IP flow verify ------------------------
echo ""
echo "================ TEST 4 – IP flow verify (subnet NSG + NIC NSG) ================"
for PORT in 22 3389; do
  read -r ACCESS RULE < <(az network watcher test-ip-flow -g "$RG" --vm vm-web1 \
      --direction Inbound --protocol TCP \
      --local "$WEB1_IP:$PORT" --remote "$BASTION_TEST_IP:50000" \
      --query "[access, ruleName]" -o tsv | tr '\n' ' '; echo) || true
  echo "   Bastion subnet -> vm-web1:$PORT : ${ACCESS:-ERROR}  (rule: ${RULE##*/})"
  if [[ $PORT == 22 ]]; then record "4a Bastion subnet -> vm-web1:22 (SSH)" Allow "${ACCESS:-ERROR}"
  else record "4b Bastion subnet -> vm-web1:3389 (RDP)" Deny "${ACCESS:-ERROR}"; fi
done

# ----------------------------- Test 5: Effective rules -----------------------
echo ""
echo "================ TEST 5 – Effective security rules on vm-web1 ================"
NIC_ID=$(az vm show -g "$RG" -n vm-web1 --query "networkProfile.networkInterfaces[0].id" -o tsv)
EFF=$(mktemp)
az network nic list-effective-nsg --ids "$NIC_ID" -o json > "$EFF" 2>/dev/null || true
COUNT=$(python3 -I -c "import json,sys;print(len(json.load(open(sys.argv[1])).get('value',[])))" "$EFF" 2>/dev/null || echo 0)
python3 -I - "$EFF" <<'PY' 2>/dev/null || echo "   (could not read effective rules – check them in the portal)"
import json, sys
data = json.load(open(sys.argv[1]))
for entry in data.get('value', []):
    nsg = entry['networkSecurityGroup']['id'].split('/')[-1]
    assoc = entry.get('association', {})
    where = 'subnet' if assoc.get('subnet') else 'NIC'
    print(f"\n   {nsg} (applied to {where}) – inbound rules:")
    rules = [r for r in entry['effectiveSecurityRules'] if r['direction'] == 'Inbound']
    for r in sorted(rules, key=lambda r: r['priority']):
        ports = r.get('destinationPortRange') or ','.join(r.get('destinationPortRanges') or [])
        src = r.get('sourceAddressPrefix') or ','.join(r.get('sourceAddressPrefixes') or [])
        print(f"     {r['priority']:>6}  {r['access']:<5}  {r['name'][:38]:<38}  src={src[:30]:<30}  ports={ports}")
PY
rm -f "$EFF"
record "5 Effective NSGs on vm-web1 (subnet + NIC)" 2 "$COUNT"

# ----------------------------- Test 6: Power states --------------------------
echo ""
echo "================ TEST 6 – Power states ================"
echo "   Deallocating vm-web2 (its test is done)..."
az vm deallocate -g "$RG" -n vm-web2 --output none
az vm list -g "$RG" --show-details --query "[].{Name:name, State:powerState}" -o table
STATE=$(az vm show -g "$RG" -n vm-web2 -d --query powerState -o tsv)
record "6 vm-web2 deallocated (no compute billing)" "VM deallocated" "$STATE"

# ----------------------------- Summary ---------------------------------------
echo ""
echo "============================== SUMMARY =============================="
printf '%-52s %-14s %-14s %s\n' "Test" "Expected" "Actual" "Result"
printf '%s\n' "${RESULTS[@]}"
echo "Passed: $PASS / $TOTAL"
echo ""
echo "Results saved to test-results.txt"
echo "⚠ vm-web1, vm-app and the NAT Gateway are still running (~\$0.25/hour). Run ./cleanup.sh when done."
