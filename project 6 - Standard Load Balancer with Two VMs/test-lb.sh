#!/usr/bin/env bash
# Single-quoted commands below are meant to expand INSIDE the VM, not here.
# shellcheck disable=SC2016
# =============================================================================
# Project 06 - Load balancer tests (run AFTER ./deploy.sh)
#
#   0. Pre-check : both VMs running, cloud-init done, Nginx active
#   1. Secure by default : website BLOCKED with no NSG HTTP rule
#   2. Allow HTTP        : add Allow-HTTP-Internet -> website WORKS
#   3. Distribution      : 10 requests are spread across vm-lb1 and vm-lb2
#   4. Failover          : stop Nginx on vm-lb1 -> only vm-lb2 answers
#      + health probe metric (Health Probe Status per backend IP)
#   5. Recovery          : start Nginx -> both servers answer again
#   6. Session persistence (Client IP) -> one server only, then reverted
#   7. Outbound rule     : vm-lb1's outbound IP = the load balancer's IP
#
# Requests in tests 1-6 come from THIS computer over the internet.
# Output is saved to test-results.txt.
# =============================================================================
set -euo pipefail

RG="rg-az104-project06"
LB="lb-az104-project06"
PIP="pip-lb-az104-project06"
NSG="nsg-web"

exec > >(tee test-results.txt) 2>&1

if ! az account get-access-token --output none 2>/dev/null; then az login --output none; fi
[[ "$(az group exists --name "$RG")" == "true" ]] || { echo "Run ./deploy.sh first."; exit 1; }

LB_IP=$(az network public-ip show -g "$RG" -n "$PIP" --query ipAddress -o tsv)
LB_ID=$(az network lb show -g "$RG" -n "$LB" --query id -o tsv)
echo "Load balancer public IP: $LB_IP"

run_on() {  # run_on <vm> <script> -> prints [stdout]
  local out
  if ! out=$(az vm run-command invoke -g "$RG" -n "$1" --command-id RunShellScript \
      --scripts "$2" --query "value[0].message" -o tsv 2>&1); then
    echo "RUNCOMMAND_FAILED"; return 0
  fi
  sed -n '/\[stdout\]/,/\[stderr\]/p' <<<"$out" | sed '/\[stdout\]/d;/\[stderr\]/d'
}

# 10 requests from this computer; prints the server name for each (or "-")
sample() {
  local name
  for _ in $(seq 1 10); do
    name=$(curl -s -m 5 "http://$LB_IP/" | grep -o "vm-lb[12]" | head -1 || true)
    echo "${name:--}"
  done
}
summarise() {  # summarise <label> <samples>
  local n1 n2 nf
  n1=$(grep -c '^vm-lb1$' <<<"$2" || true); n2=$(grep -c '^vm-lb2$' <<<"$2" || true)
  nf=$(grep -c '^-$' <<<"$2" || true)
  echo "   $1: vm-lb1=$n1  vm-lb2=$n2  no answer=$nf"
  echo "     $(tr '\n' ' ' <<<"$2")"
  N1=$n1; N2=$n2
}

declare -a RESULTS
PASS=0; TOTAL=0
record() {  # record <label> <expected> <actual>
  local status="CHECK"; TOTAL=$((TOTAL+1))
  if [[ "$3" == "$2" ]]; then status="PASS"; PASS=$((PASS+1)); fi
  RESULTS+=("$(printf '%-46s %-18s %-18s %s' "$1" "$2" "$3" "$status")")
}

# ----------------------------- 0. Pre-check ----------------------------------
echo ""
echo "================ PRE-CHECK - VMs, cloud-init, Nginx ================"
for VM in vm-lb1 vm-lb2; do
  STATE=$(az vm get-instance-view -g "$RG" -n "$VM" \
    --query "instanceView.statuses[?starts_with(code,'PowerState/')].displayStatus | [0]" -o tsv)
  if [[ "$STATE" != "VM running" ]]; then
    echo ">> Starting $VM (was: $STATE - auto-shutdown runs at 19:00)..."
    az vm start -g "$RG" -n "$VM" --output none
  fi
done
FIX='apt-get update -q >/dev/null && apt-get install -y -q nginx >/dev/null; ZONE=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/zone?api-version=2021-02-01&format=text"); echo "<h1>Served by: $(hostname)</h1><p>Availability zone: ${ZONE:-none}</p>" > /var/www/html/index.html; systemctl enable --now nginx >/dev/null 2>&1'
for VM in vm-lb1 vm-lb2; do
  OUT=$(run_on "$VM" "cloud-init status --wait >/dev/null 2>&1; echo NGINX=\$(systemctl is-active nginx); curl -s http://localhost | grep -oE 'Served by: [a-z0-9-]+|Availability zone: [0-9a-z]+' | tr '\n' ' '")
  if grep -q "NGINX=active" <<<"$OUT"; then
    echo "   OK  $VM: $(grep -oE 'Served by.*' <<<"$OUT")"
  else
    echo "   !!  $VM: Nginx not active - installing it with Run command..."
    run_on "$VM" "$FIX; echo NGINX=\$(systemctl is-active nginx)" | sed 's/^/       /'
  fi
done
# Make sure nginx is running on vm-lb1 (a previous run may have stopped it)
run_on vm-lb1 "systemctl start nginx" >/dev/null

# ----------------------------- 1. Secure by default --------------------------
echo ""
echo "================ TEST 1 - Secure by default ================"
if az network nsg rule show -g "$RG" --nsg-name "$NSG" -n Allow-HTTP-Internet --output none 2>/dev/null; then
  echo "   Removing Allow-HTTP-Internet so the test starts from the secure default..."
  az network nsg rule delete -g "$RG" --nsg-name "$NSG" -n Allow-HTTP-Internet
  sleep 30
fi
if curl -s -m 8 -o /dev/null "http://$LB_IP/"; then T1="REACHABLE"; else T1="BLOCKED"; fi
echo "   http://$LB_IP with no HTTP rule in $NSG: $T1"
record "1 No NSG HTTP rule -> website" BLOCKED "$T1"

# ----------------------------- 2. Allow HTTP ---------------------------------
echo ""
echo "================ TEST 2 - Add the NSG HTTP rule ================"
az network nsg rule create -g "$RG" --nsg-name "$NSG" -n Allow-HTTP-Internet \
  --priority 100 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes Internet --source-port-ranges '*' \
  --destination-address-prefixes 10.10.1.0/24 --destination-port-ranges 80 --output none
echo "   + [100] Allow TCP 80 from Internet to 10.10.1.0/24"
T2="BLOCKED"
for _ in $(seq 1 12); do
  if PAGE=$(curl -s -m 5 "http://$LB_IP/") && grep -q "Served by" <<<"$PAGE"; then T2="WORKS"; break; fi
  sleep 10
done
echo "   http://$LB_IP after adding the rule: $T2"
[[ $T2 == WORKS ]] && grep -oE 'Served by: [a-z0-9-]+|Availability zone: [0-9a-z]+' <<<"$PAGE" | sed 's/^/     /'
record "2 With HTTP rule -> website" WORKS "$T2"

# ----------------------------- 3. Distribution -------------------------------
echo ""
echo "================ TEST 3 - Distribution (5-tuple hash) ================"
S=$(sample); summarise "10 requests" "$S"
if (( N1 > 0 && N2 > 0 )); then T3="BOTH"; else T3="ONE-ONLY"; fi
record "3 Requests spread across both VMs" BOTH "$T3"

# ----------------------------- 4. Failover -----------------------------------
echo ""
echo "================ TEST 4 - Failover (stop Nginx on vm-lb1) ================"
run_on vm-lb1 'systemctl stop nginx && echo "nginx stopped on $(hostname)"' | sed 's/^/   /'
echo "   waiting 30 s for the health probe to mark vm-lb1 unhealthy..."
sleep 30
S=$(sample); summarise "10 requests" "$S"
if (( N1 == 0 && N2 == 10 )); then T4="VM-LB2-ONLY"; else T4="lb1=$N1,lb2=$N2"; fi
record "4 vm-lb1 down -> traffic to" VM-LB2-ONLY "$T4"

echo ""
echo "   Health Probe Status (metric DipAvailability, last 5 min, per backend IP):"
START=$(date -u -d '-6 min' +%Y-%m-%dT%H:%M:%SZ)
az monitor metrics list --resource "$LB_ID" --metric DipAvailability \
  --interval PT1M --aggregation Average --start-time "$START" \
  --filter "BackendIPAddress eq '*'" \
  --query "value[0].timeseries[].{Backend:metadatavalues[?name.value=='backendipaddress'].value | [0], LatestAvg:data[-2].average}" \
  -o table 2>/dev/null || echo "     (metric not available yet - check Monitoring -> Metrics in the portal)"
echo "     100 = healthy, 0 = unhealthy (metrics can lag 1-3 minutes)"

# ----------------------------- 5. Recovery -----------------------------------
echo ""
echo "================ TEST 5 - Recovery (start Nginx on vm-lb1) ================"
run_on vm-lb1 'systemctl start nginx && echo "nginx started on $(hostname)"' | sed 's/^/   /'
echo "   waiting 30 s for the probe to mark vm-lb1 healthy..."
sleep 30
S=$(sample); summarise "10 requests" "$S"
if (( N1 > 0 && N2 > 0 )); then T5="BOTH"; else T5="lb1=$N1,lb2=$N2"; fi
record "5 vm-lb1 back -> traffic to" BOTH "$T5"

# ----------------------------- 6. Session persistence ------------------------
echo ""
echo "================ TEST 6 - Session persistence: Client IP ================"
az network lb rule update -g "$RG" --lb-name "$LB" -n rule-http --load-distribution SourceIP --output none
echo "   rule-http load distribution = SourceIP (Client IP). Waiting 60 s..."
sleep 60
S=$(sample); summarise "10 requests" "$S"
if (( (N1 == 10 && N2 == 0) || (N1 == 0 && N2 == 10) )); then T6="ONE-SERVER"; else T6="lb1=$N1,lb2=$N2"; fi
record "6 Client IP persistence -> traffic to" ONE-SERVER "$T6"
az network lb rule update -g "$RG" --lb-name "$LB" -n rule-http --load-distribution Default --output none
echo "   reverted rule-http to Default (5-tuple)"

# ----------------------------- 7. Outbound rule ------------------------------
echo ""
echo "================ TEST 7 - Outbound rule ================"
OUTIP=$(run_on vm-lb1 "curl -s -m 10 https://api.ipify.org || echo NO-INTERNET" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}|NO-INTERNET' | head -1 || true)
echo "   vm-lb1 outbound IP: ${OUTIP:-ERROR}   load balancer IP: $LB_IP"
if [[ "$OUTIP" == "$LB_IP" ]]; then T7="LB-IP"; else T7="${OUTIP:-ERROR}"; fi
record "7 vm-lb1 egress via LB outbound rule" LB-IP "$T7"

# ----------------------------- Summary ---------------------------------------
echo ""
echo "============================== SUMMARY =============================="
printf '%-46s %-18s %-18s %s\n' "Test" "Expected" "Actual" "Result"
printf '%s\n' "${RESULTS[@]}"
echo "Passed: $PASS / $TOTAL"
echo ""
echo "Note: Test 3 can occasionally show one server only - the 5-tuple hash is"
echo "per connection, not round-robin. Re-run the loop and it will mix."
echo ""
echo "Results saved to test-results.txt"
echo "The VMs and load balancer are still running (~\$0.19/hour). Run ./cleanup.sh when done."
