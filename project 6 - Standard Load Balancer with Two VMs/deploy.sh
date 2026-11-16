#!/usr/bin/env bash
# =============================================================================
# Project 06 - Standard Load Balancer with Two VMs
# Primary deployment method: Azure CLI (Bash)
#
# Builds (region East US 2):
#   - Resource group rg-az104-project06 (tagged)
#   - NSG nsg-web: management from Bastion subnet + Deny-VNet-Inbound
#     (NO port 80 rule yet - test-lb.sh proves "secure by default", then adds it)
#   - VNet 10.10.0.0/16: snet-web (private, nsg-web) + AzureBastionSubnet
#   - Zone-redundant Standard public IP  pip-lb-az104-project06
#   - Standard public load balancer lb-az104-project06:
#       frontend fe-web, backend pool bepool-web, probe probe-http (HTTP 80 /),
#       rule rule-http (TCP 80 -> 80), outbound rule rule-outbound
#   - vm-lb1 (zone 1) and vm-lb2 (zone 3): Ubuntu 24.04, Standard_D2als_v6,
#     no public IPs, NICs in bepool-web, Nginx installed by cloud-init
#
# COST while it exists: ~$0.19/hour. Run ./cleanup.sh when done.
# Overrides:  VM_SIZE=Standard_D2s_v3 ZONES="1 2 3" ./deploy.sh
# Safe to re-run: existing resources are reused.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ----------------------------- Variables -------------------------------------
RG="rg-az104-project06"
LOCATION="eastus2"
VNET="vnet-az104-project06"
NSG="nsg-web"
PIP="pip-lb-az104-project06"
LB="lb-az104-project06"
FE="fe-web"
POOL="bepool-web"
PROBE="probe-http"
IMAGE="Ubuntu2404"
ADMIN_USER="azureuser"

# D2als_v6 was the only small size allowed in availability zones for this
# subscription in East US 2 (zones 1 and 3). See README - Lessons Learned.
VM_SIZE="${VM_SIZE:-Standard_D2als_v6}"
read -r -a ZONE_CANDIDATES <<< "${ZONES:-1 3 2}"

WEB_PREFIX="10.10.1.0/24"
BASTION_PREFIX="10.10.254.0/26"
TAGS=(Environment=Lab CostCenter=IT-Services "Owner=Harold Nduna" Project=AZ104-Project06)

CLOUD_INIT="$SCRIPT_DIR/scripts/cloud-init-web.yaml"
[[ -f "$CLOUD_INIT" ]] || { echo "Missing file: $CLOUD_INIT"; exit 1; }
if LC_ALL=C grep -q '[^ -~[:space:]]' "$CLOUD_INIT"; then
  echo "ERROR: $CLOUD_INIT contains non-ASCII characters (the Azure CLI rejects them)."; exit 1
fi

# v6 sizes use the NVMe disk controller
DISK_CONTROLLER=()
if [[ "$VM_SIZE" == *_v6 ]]; then DISK_CONTROLLER=(--disk-controller-type NVMe); fi

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

# ----------------------------- Pre-flight ------------------------------------
echo ">> Checking your Azure login..."
if ! az account get-access-token --output none 2>/dev/null; then
  echo "   Not logged in, or the session has expired. Running 'az login'..."
  az login --output none
fi
echo "   Using subscription: $(az account show --query name --output tsv)"

# ----------------------------- 1. Resource group -----------------------------
echo ">> [1/7] Resource group $RG ($LOCATION)"
az group create --name "$RG" --location "$LOCATION" --tags "${TAGS[@]}" --output none

# ----------------------------- 2. NSG ----------------------------------------
echo ">> [2/7] NSG $NSG (no HTTP rule yet - secure by default)"
az network nsg create --resource-group "$RG" --name "$NSG" --location "$LOCATION" \
  --tags "${TAGS[@]}" --output none
az network nsg rule create --resource-group "$RG" --nsg-name "$NSG" --name Allow-Mgmt-Bastion \
  --priority 110 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes "$BASTION_PREFIX" --source-port-ranges '*' \
  --destination-address-prefixes "$WEB_PREFIX" --destination-port-ranges 22 3389 --output none
az network nsg rule create --resource-group "$RG" --nsg-name "$NSG" --name Deny-VNet-Inbound \
  --priority 4000 --direction Inbound --access Deny --protocol '*' \
  --source-address-prefixes VirtualNetwork --source-port-ranges '*' \
  --destination-address-prefixes '*' --destination-port-ranges '*' --output none
echo "   + [110] Allow TCP 22,3389 from $BASTION_PREFIX"
echo "   + [4000] Deny VirtualNetwork"
echo "   (health probes are allowed by default rule AllowAzureLoadBalancerInBound 65001)"

# ----------------------------- 3. VNet ---------------------------------------
echo ">> [3/7] Virtual network and subnets"
az network vnet create --resource-group "$RG" --name "$VNET" --location "$LOCATION" \
  --address-prefixes 10.10.0.0/16 --tags "${TAGS[@]}" --output none
az network vnet subnet create --resource-group "$RG" --vnet-name "$VNET" --name snet-web \
  --address-prefixes "$WEB_PREFIX" --network-security-group "$NSG" \
  --default-outbound-access false --output none
az network vnet subnet create --resource-group "$RG" --vnet-name "$VNET" --name AzureBastionSubnet \
  --address-prefixes "$BASTION_PREFIX" --output none
echo "   + snet-web (private, $NSG), AzureBastionSubnet"

# ----------------------------- 4. Public IP + load balancer ------------------
echo ">> [4/7] Zone-redundant Standard public IP + Standard load balancer"
az network public-ip create --resource-group "$RG" --name "$PIP" --location "$LOCATION" \
  --sku Standard --allocation-method Static --version IPv4 --zone 1 2 3 \
  --tags "${TAGS[@]}" --output none
az network lb create --resource-group "$RG" --name "$LB" --location "$LOCATION" \
  --sku Standard --public-ip-address "$PIP" \
  --frontend-ip-name "$FE" --backend-pool-name "$POOL" \
  --tags "${TAGS[@]}" --output none
az network lb probe create --resource-group "$RG" --lb-name "$LB" --name "$PROBE" \
  --protocol Http --port 80 --path / --interval 5 --output none
# --disable-outbound-snat: outbound internet comes from the outbound rule instead
az network lb rule create --resource-group "$RG" --lb-name "$LB" --name rule-http \
  --protocol Tcp --frontend-port 80 --backend-port 80 \
  --frontend-ip-name "$FE" --backend-pool-name "$POOL" --probe-name "$PROBE" \
  --idle-timeout 4 --enable-tcp-reset true --disable-outbound-snat true \
  --load-distribution Default --output none
az network lb outbound-rule create --resource-group "$RG" --lb-name "$LB" --name rule-outbound \
  --frontend-ip-configs "$FE" --address-pool "$POOL" --protocol All \
  --idle-timeout 4 --enable-tcp-reset true --outbound-ports 10000 --output none
echo "   + $LB: frontend $FE, pool $POOL, probe $PROBE (HTTP 80 /), rule-http (80->80), rule-outbound"

# ----------------------------- 5. NICs in the backend pool -------------------
echo ">> [5/7] Network interfaces (in the backend pool, no public IPs)"
for SPEC in "vm-lb1 10.10.1.4" "vm-lb2 10.10.1.5"; do
  read -r NAME IP <<< "$SPEC"
  az network nic create --resource-group "$RG" --name "nic-$NAME" --location "$LOCATION" \
    --vnet-name "$VNET" --subnet snet-web --private-ip-address "$IP" \
    --lb-name "$LB" --lb-address-pools "$POOL" \
    --tags "${TAGS[@]}" --output none
  echo "   + nic-$NAME ($IP) -> $POOL"
done

# ----------------------------- 6. VMs in different zones ---------------------
vm_exists() { az vm show --resource-group "$RG" --name "$1" --output none 2>/dev/null; }
show_error() {
  local found
  echo "     ---- error ----"
  found=$(grep -oE '"code": ?"[A-Za-z]+"|"message": ?"[^"]{0,300}|Message: .{0,300}' "$1" \
    | grep -v 'DeploymentFailed\|At least one resource deployment' | sort -u | head -8 || true)
  # shellcheck disable=SC2001
  if [[ -n "$found" ]]; then sed 's/^/     /' <<<"$found"; else tail -n 10 "$1" | sed 's/^/     /'; fi
  echo "     ---------------"
}

USED_ZONE=""
create_vm_in_zone() {  # create_vm_in_zone <name>  -> tries zones until one works
  local name=$1 zone
  if vm_exists "$name"; then
    USED_ZONE=$(az vm show -g "$RG" -n "$name" --query "zones[0]" -o tsv)
    echo "   $name already exists (zone $USED_ZONE) - reusing it"
    return 0
  fi
  for zone in "${ZONE_CANDIDATES[@]}"; do
    [[ "$zone" == "${SKIP_ZONE:-}" ]] && continue
    echo "   creating $name ($VM_SIZE) in zone $zone..."
    if az vm create \
        --resource-group "$RG" --name "$name" --location "$LOCATION" \
        --zone "$zone" --image "$IMAGE" --size "$VM_SIZE" "${DISK_CONTROLLER[@]}" \
        --security-type TrustedLaunch --enable-secure-boot true --enable-vtpm true \
        --nics "nic-$name" \
        --admin-username "$ADMIN_USER" --generate-ssh-keys \
        --storage-sku Standard_LRS --os-disk-delete-option Delete \
        --custom-data "$CLOUD_INIT" \
        --tags "${TAGS[@]}" --output none > "$WORKDIR/$name.log" 2>&1; then
      USED_ZONE=$zone
      echo "   + $name in zone $zone"
      return 0
    fi
    if grep -qiE "SkuNotAvailable|not available|restricted|Capacity|ZonalAllocationFailed" "$WORKDIR/$name.log"; then
      echo "     zone $zone not available for $VM_SIZE - trying the next zone"
      continue
    fi
    echo "   x $name failed:"; show_error "$WORKDIR/$name.log"
    echo "   Fix the problem above, then re-run ./deploy.sh - existing resources are reused."
    exit 1
  done
  echo "   x $name: no zone in (${ZONE_CANDIDATES[*]}) worked for $VM_SIZE."
  echo "     Check with: az vm list-skus --location $LOCATION --size $VM_SIZE --all -o table"
  exit 1
}

echo ">> [6/7] Virtual machines in different availability zones (2-3 minutes each)"
SKIP_ZONE=""
create_vm_in_zone vm-lb1
SKIP_ZONE="$USED_ZONE"          # vm-lb2 must be in a DIFFERENT zone
create_vm_in_zone vm-lb2

# ----------------------------- 7. Boot diagnostics + auto-shutdown -----------
echo ">> [7/7] Boot diagnostics and auto-shutdown 19:00 CET"
for VM in vm-lb1 vm-lb2; do
  az vm boot-diagnostics enable --resource-group "$RG" --name "$VM" --output none
  az vm auto-shutdown --resource-group "$RG" --name "$VM" --time 1800 --output none  # 1800 UTC = 19:00 CET
done

# ----------------------------- Verification ----------------------------------
LB_IP=$(az network public-ip show -g "$RG" -n "$PIP" --query ipAddress -o tsv)
echo ""
echo "======================== VERIFICATION ========================"
echo ">> Resources:"
az resource list --resource-group "$RG" \
  --query "sort_by([], &type)[].{Name:name, Type:type, Location:location}" --output table

echo ""
echo ">> VMs (zone, size, no public IP):"
az vm list --resource-group "$RG" --show-details \
  --query "[].{Name:name, Zone:zones[0], Size:hardwareProfile.vmSize, PrivateIP:privateIps, PublicIP:publicIps, State:powerState}" \
  --output table

echo ""
echo ">> Public IP (zone-redundant front door):"
az network public-ip show -g "$RG" -n "$PIP" \
  --query "{Name:name, IP:ipAddress, Sku:sku.name, Zones:join(',', zones)}" -o table

echo ""
echo ">> Load balancer:"
az network lb show -g "$RG" -n "$LB" --query "{Name:name, Sku:sku.name}" -o table
echo ""
echo "   Backend pool members:"
az network lb address-pool show -g "$RG" --lb-name "$LB" -n "$POOL" \
  --query "backendIPConfigurations[].id" -o tsv | sed 's#.*/networkInterfaces/#     #; s#/ipConfigurations/.*##'
echo ""
echo "   Health probe:"
az network lb probe list -g "$RG" --lb-name "$LB" \
  --query "[].{Name:name, Protocol:protocol, Port:port, Path:requestPath, IntervalSec:intervalInSeconds}" -o table
echo ""
echo "   Load-balancing rule:"
az network lb rule list -g "$RG" --lb-name "$LB" \
  --query "[].{Name:name, Protocol:protocol, FrontendPort:frontendPort, BackendPort:backendPort, Persistence:loadDistribution, OutboundSNAT:disableOutboundSnat}" -o table
echo ""
echo "   Outbound rule:"
az network lb outbound-rule list -g "$RG" --lb-name "$LB" \
  --query "[].{Name:name, Protocol:protocol, PortsPerInstance:allocatedOutboundPorts, IdleTimeout:idleTimeoutInMinutes}" -o table

echo ""
echo ">> NSG $NSG (custom rules):"
az network nsg rule list -g "$RG" --nsg-name "$NSG" \
  --query "sort_by([], &priority)[].{Priority:priority, Name:name, Access:access, Source:sourceAddressPrefix, Ports:destinationPortRange || join(',', destinationPortRanges)}" -o table

echo ""
echo "Website address: http://$LB_IP  (blocked until test-lb.sh adds the HTTP rule)"
echo "Next:"
echo "  ./test-lb.sh   - wait ~3 minutes for cloud-init first, then run all tests"
echo "  ./cleanup.sh   - delete everything (~\$0.19/hour while it exists)"
