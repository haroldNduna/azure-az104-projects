#!/usr/bin/env bash
# =============================================================================
# Project 05 – Virtual Machines, Application Security Groups & Extensions
# Primary deployment method: Azure CLI (Bash)
#
# Builds (region East US 2):
#   - Resource group rg-az104-project05 (tagged)
#   - ASGs: asg-web, asg-app                      (the "ID badges")
#   - NSGs: nsg-web, nsg-app (subnet)             (the "floor guards")
#           nsg-vm-web1 (NIC)                     (the "door lock")
#   - NAT Gateway + Standard public IP on snet-web (the "mailroom")
#   - VNet 10.10.0.0/16: snet-web, snet-app, AzureBastionSubnet
#   - Storage account + private 'scripts' container holding configure-web.sh
#   - VMs (Ubuntu 24.04, Trusted launch, no public IPs):
#       vm-web1 10.10.1.4  asg-web + NIC NSG + 4 GB data disk + Custom Script Extension
#       vm-web2 10.10.1.5  no ASG (the "intruder")
#       vm-app  10.10.2.4  asg-app + cloud-init listener on TCP 8080
#
# COST while it exists: ~$0.35/hour (3 x D2s_v3 + NAT Gateway). Run ./cleanup.sh when done.
# Force a VM size with:  VM_SIZE=Standard_DS1_v2 ./deploy.sh
# Run it again safely: existing VMs are reused.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ----------------------------- Variables -------------------------------------
RG="rg-az104-project05"
LOCATION="eastus2"
VNET="vnet-az104-project05"
NAT="nat-az104-project05"
PIP="pip-nat-az104-project05"
IMAGE="Ubuntu2404"
ADMIN_USER="azureuser"

WEB_PREFIX="10.10.1.0/24"
APP_PREFIX="10.10.2.0/24"
BASTION_PREFIX="10.10.254.0/26"

# B-series was unavailable to this subscription in East US and East US 2,
# so D2s_v3 is tried first. Override with VM_SIZE=...
if [[ -n "${VM_SIZE:-}" ]]; then
  SIZE_CANDIDATES=("$VM_SIZE")
else
  SIZE_CANDIDATES=(Standard_D2s_v3 Standard_B2ats_v2 Standard_B1s Standard_DS1_v2 Standard_D2as_v5)
fi

TAGS=(Environment=Lab CostCenter=IT-Services "Owner=Harold Nduna" Project=AZ104-Project05)

# Absolute paths – so the script works from any folder.
# (Lesson learned: a wrong relative path made cloud-init silently do nothing.)
CONFIGURE_SCRIPT="$SCRIPT_DIR/scripts/configure-web.sh"
CLOUD_INIT="$SCRIPT_DIR/scripts/cloud-init-app.yaml"
for F in "$CONFIGURE_SCRIPT" "$CLOUD_INIT"; do
  [[ -f "$F" ]] || { echo "Missing file: $F"; exit 1; }
done

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

# ----------------------------- Pre-flight ------------------------------------
echo ">> Checking your Azure login..."
if ! az account get-access-token --output none 2>/dev/null; then
  echo "   Not logged in, or the session has expired. Running 'az login'..."
  az login --output none
fi
SUB_ID=$(az account show --query id --output tsv)
echo "   Using subscription: $(az account show --query name --output tsv)"

# Globally unique, repeatable storage account name derived from the subscription
STORAGE="stp05$(echo -n "$SUB_ID" | md5sum | cut -c1-10)"

# ----------------------------- 1. Resource group -----------------------------
echo ">> [1/9] Resource group $RG ($LOCATION)"
az group create --name "$RG" --location "$LOCATION" --tags "${TAGS[@]}" --output none

# ----------------------------- 2. ASGs ---------------------------------------
echo ">> [2/9] Application security groups (ID badges)"
for ASG in asg-web asg-app; do
  az network asg create --resource-group "$RG" --name "$ASG" --location "$LOCATION" \
    --tags "${TAGS[@]}" --output none
  echo "   + $ASG"
done

# ----------------------------- 3. NSGs ---------------------------------------
echo ">> [3/9] Network security groups"
for NSG in nsg-web nsg-app nsg-vm-web1; do
  az network nsg create --resource-group "$RG" --name "$NSG" --location "$LOCATION" \
    --tags "${TAGS[@]}" --output none
done

# rule <nsg> <name> <priority> <access> <protocol> <source> <destination> <port...>
rule() {
  local nsg=$1 name=$2 priority=$3 access=$4 protocol=$5 src=$6 dst=$7
  shift 7
  az network nsg rule create --resource-group "$RG" --nsg-name "$nsg" --name "$name" \
    --priority "$priority" --direction Inbound --access "$access" --protocol "$protocol" \
    --source-address-prefixes "$src" --source-port-ranges '*' \
    --destination-address-prefixes "$dst" --destination-port-ranges "$@" --output none
  echo "   + $nsg [$priority] $access $protocol $src -> $dst port(s) $*"
}

# nsg-web – floor guard for the web subnet
rule nsg-web Allow-HTTPS-Internet 100  Allow Tcp Internet          "$WEB_PREFIX" 443
rule nsg-web Allow-Mgmt-Bastion   110  Allow Tcp "$BASTION_PREFIX" "$WEB_PREFIX" 22 3389
rule nsg-web Deny-VNet-Inbound    4000 Deny  '*' VirtualNetwork    '*'           '*'

# nsg-app – floor guard that checks BADGES (ASGs) instead of IP ranges
az network nsg rule create --resource-group "$RG" --nsg-name nsg-app \
  --name Allow-App-From-ASG-Web --priority 100 --direction Inbound --access Allow \
  --protocol Tcp --source-asgs asg-web --source-port-ranges '*' \
  --destination-asgs asg-app --destination-port-ranges 8080 --output none
echo "   + nsg-app [100] Allow Tcp asg-web -> asg-app port(s) 8080"
rule nsg-app Allow-Mgmt-Bastion   110  Allow Tcp "$BASTION_PREFIX" "$APP_PREFIX" 22 3389
rule nsg-app Deny-VNet-Inbound    4000 Deny  '*' VirtualNetwork    '*'           '*'

# nsg-vm-web1 – door lock on vm-web1's NIC (Linux never needs RDP)
rule nsg-vm-web1 Deny-RDP-Host    100  Deny  Tcp '*'               '*'           3389

# ----------------------------- 4. NAT Gateway --------------------------------
echo ">> [4/9] NAT Gateway (mailroom) + Standard static public IP"
az network public-ip create --resource-group "$RG" --name "$PIP" --location "$LOCATION" \
  --sku Standard --allocation-method Static --version IPv4 --tags "${TAGS[@]}" --output none
az network nat gateway create --resource-group "$RG" --name "$NAT" --location "$LOCATION" \
  --public-ip-addresses "$PIP" --idle-timeout 4 --tags "${TAGS[@]}" --output none

# ----------------------------- 5. VNet + subnets -----------------------------
echo ">> [5/9] Virtual network and subnets"
az network vnet create --resource-group "$RG" --name "$VNET" --location "$LOCATION" \
  --address-prefixes 10.10.0.0/16 --tags "${TAGS[@]}" --output none
az network vnet subnet create --resource-group "$RG" --vnet-name "$VNET" --name snet-web \
  --address-prefixes "$WEB_PREFIX" --network-security-group nsg-web --nat-gateway "$NAT" \
  --default-outbound-access false --output none
az network vnet subnet create --resource-group "$RG" --vnet-name "$VNET" --name snet-app \
  --address-prefixes "$APP_PREFIX" --network-security-group nsg-app \
  --default-outbound-access false --output none
az network vnet subnet create --resource-group "$RG" --vnet-name "$VNET" --name AzureBastionSubnet \
  --address-prefixes "$BASTION_PREFIX" --output none
echo "   + snet-web (nsg-web, NAT), snet-app (nsg-app, no NAT), AzureBastionSubnet"

# ----------------------------- 6. Storage for the extension script -----------
echo ">> [6/9] Storage account $STORAGE + private 'scripts' container"
az storage account create --resource-group "$RG" --name "$STORAGE" --location "$LOCATION" \
  --sku Standard_LRS --kind StorageV2 --access-tier Hot \
  --https-only true --min-tls-version TLS1_2 --allow-blob-public-access false \
  --tags "${TAGS[@]}" --output none
# The key is kept in a variable and a 600-permission temp file – never printed
STORAGE_KEY=$(az storage account keys list --resource-group "$RG" --account-name "$STORAGE" \
  --query "[0].value" --output tsv)
az storage container create --name scripts --account-name "$STORAGE" \
  --account-key "$STORAGE_KEY" --output none
az storage blob upload --account-name "$STORAGE" --account-key "$STORAGE_KEY" \
  --container-name scripts --name configure-web.sh --file "$CONFIGURE_SCRIPT" \
  --overwrite --output none
SCRIPT_URL="https://${STORAGE}.blob.core.windows.net/scripts/configure-web.sh"
echo "   + uploaded configure-web.sh"

# ----------------------------- 7. VMs ----------------------------------------
create_vm() {  # create_vm <name> <subnet> <ip> <size> <nic-nsg or ""> <asg or ""> [extra args...]
  local name=$1 subnet=$2 ip=$3 size=$4 nsg=$5 asg=$6
  shift 6
  local extra=("$@")
  if [[ -n "$asg" ]]; then extra+=(--asgs "$asg"); fi
  az vm create \
    --resource-group "$RG" --name "$name" --location "$LOCATION" \
    --image "$IMAGE" --size "$size" \
    --security-type TrustedLaunch --enable-secure-boot true --enable-vtpm true \
    --vnet-name "$VNET" --subnet "$subnet" --private-ip-address "$ip" \
    --public-ip-address "" --nsg "$nsg" \
    --admin-username "$ADMIN_USER" --generate-ssh-keys \
    --storage-sku Standard_LRS \
    --os-disk-delete-option Delete --nic-delete-option Delete \
    --tags "${TAGS[@]}" \
    "${extra[@]}" \
    --output none
}
vm_exists() { az vm show --resource-group "$RG" --name "$1" --output none 2>/dev/null; }
# Shows the useful part of an Azure CLI error (handles both text and JSON styles)
show_error() {
  local found
  echo "     ---- error ----"
  found=$(grep -oE '"code": ?"[A-Za-z]+"|"message": ?"[^"]{0,300}|Message: .{0,300}' "$1" \
    | grep -v 'DeploymentFailed\|At least one resource deployment' | sort -u | head -8 || true)
  # shellcheck disable=SC2001
  if [[ -n "$found" ]]; then sed 's/^/     /' <<<"$found"; else tail -n 10 "$1" | sed 's/^/     /'; fi
  echo "     ---------------"
}

# create_vm_with_fallback <name> <subnet> <ip> <nic-nsg> <asg> [extra args...]
# Tries the preferred size first, then the other candidates – so a VM-family
# quota or capacity limit on one size doesn't stop the build.
create_vm_with_fallback() {
  local name=$1 subnet=$2 ip=$3 nsg=$4 asg=$5
  shift 5
  local try
  if vm_exists "$name"; then
    echo "   $name already exists ($(az vm show -g "$RG" -n "$name" --query hardwareProfile.vmSize -o tsv)) – reusing it"
    return 0
  fi
  for try in "${SIZE_CANDIDATES[@]}"; do
    echo "   creating $name with $try..."
    if create_vm "$name" "$subnet" "$ip" "$try" "$nsg" "$asg" "$@" > "$WORKDIR/$name.log" 2>&1; then
      echo "   ✔ $name ($try)"
      return 0
    fi
    if grep -qiE "SkuNotAvailable|QuotaExceeded|OperationNotAllowed|exceeding approved|Capacity" "$WORKDIR/$name.log"; then
      echo "     $try not available or over quota – trying the next size"
      # Remove any half-created NIC so the next attempt can reuse the IP
      az network nic delete -g "$RG" -n "${name}VMNic" --output none 2>/dev/null || true
      continue
    fi
    echo "   ✖ $name failed:"; show_error "$WORKDIR/$name.log"
    echo "   Fix the problem above, then re-run ./deploy.sh – existing resources are reused."
    exit 1
  done
  echo "   ✖ $name: none of these sizes worked: ${SIZE_CANDIDATES[*]}"
  show_error "$WORKDIR/$name.log"
  exit 1
}

echo ">> [7/9] Virtual machines (one at a time – about 2-3 minutes each)"
create_vm_with_fallback vm-web1 snet-web 10.10.1.4 nsg-vm-web1 asg-web \
  --data-disk-sizes-gb 4 --data-disk-delete-option Delete
create_vm_with_fallback vm-web2 snet-web 10.10.1.5 "" ""
create_vm_with_fallback vm-app  snet-app 10.10.2.4 "" asg-app --custom-data "$CLOUD_INIT"

# ----------------------------- 8. Boot diagnostics + auto-shutdown -----------
echo ">> [8/9] Boot diagnostics (serial console) and auto-shutdown 19:00 CET"
for VM in vm-web1 vm-web2 vm-app; do
  az vm boot-diagnostics enable --resource-group "$RG" --name "$VM" --output none
  # az vm auto-shutdown uses UTC: 1800 UTC = 19:00 Central European Time
  az vm auto-shutdown --resource-group "$RG" --name "$VM" --time 1800 --output none
done

# ----------------------------- 9. Custom Script Extension --------------------
echo ">> [9/9] Custom Script Extension on vm-web1 (data disk + Nginx) – 2-5 minutes"
printf '{"fileUris":["%s"]}' "$SCRIPT_URL" > "$WORKDIR/settings.json"
( umask 077
  printf '{"commandToExecute":"bash configure-web.sh","storageAccountName":"%s","storageAccountKey":"%s"}' \
    "$STORAGE" "$STORAGE_KEY" > "$WORKDIR/protected.json" )
az vm extension set --resource-group "$RG" --vm-name vm-web1 \
  --name CustomScript --publisher Microsoft.Azure.Extensions --version 2.1 \
  --settings "@$WORKDIR/settings.json" \
  --protected-settings "@$WORKDIR/protected.json" \
  --output none

# ----------------------------- Verification ----------------------------------
echo ""
echo "======================== VERIFICATION ========================"
echo ">> Resources:"
az resource list --resource-group "$RG" \
  --query "sort_by([], &type)[].{Name:name, Type:type, Location:location}" --output table

echo ""
echo ">> VMs:"
az vm list --resource-group "$RG" --show-details \
  --query "[].{Name:name, Size:hardwareProfile.vmSize, PrivateIP:privateIps, PublicIP:publicIps, Security:securityProfile.securityType, State:powerState}" \
  --output table

echo ""
echo ">> NIC -> NSG and ASG (badge):"
printf "   %-10s %-12s %-14s %s\n" "IP" "VM" "NIC NSG" "ASG"
while IFS=$'\t' read -r VMID IP NSGID ASGID; do
  printf "   %-10s %-12s %-14s %s\n" "$IP" "${VMID##*/}" "${NSGID:+${NSGID##*/}}" "${ASGID:+${ASGID##*/}}"
done < <(az network nic list --resource-group "$RG" \
  --query "[].[virtualMachine.id, ipConfigurations[0].privateIPAddress, networkSecurityGroup.id || '', ipConfigurations[0].applicationSecurityGroups[0].id || '']" \
  --output tsv)

echo ""
echo ">> nsg-app rules:"
az network nsg rule list --resource-group "$RG" --nsg-name nsg-app \
  --query "sort_by([], &priority)[].{Priority:priority, Name:name, Access:access, Source:sourceAddressPrefix || join(',', sourceApplicationSecurityGroups[].id), Ports:destinationPortRange || join(',', destinationPortRanges)}" \
  --output table | sed 's#/subscriptions/[^ ]*/applicationSecurityGroups/##'

echo ""
echo ">> Data disk on vm-web1:"
az vm show --resource-group "$RG" --name vm-web1 \
  --query "storageProfile.dataDisks[].{LUN:lun, Name:name, SizeGB:diskSizeGb, Type:managedDisk.storageAccountType}" \
  --output table

echo ""
echo ">> Extension on vm-web1:"
az vm extension list --resource-group "$RG" --vm-name vm-web1 \
  --query "[].{Name:name, Publisher:publisher, Version:typeHandlerVersion, State:provisioningState}" --output table

echo ""
echo ">> NAT Gateway public IP (vm-web1 should report this in the tests):"
az network public-ip show --resource-group "$RG" --name "$PIP" --query ipAddress --output tsv

echo ""
echo "Done. Next:"
echo "  ./test-vm.sh   – run the ASG, disk, NAT and NSG tests (saves test-results.txt)"
echo "  ./cleanup.sh   – delete everything (~\$0.35/hour while it exists)"
