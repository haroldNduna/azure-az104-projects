#!/usr/bin/env bash
# =============================================================================
# Project 04 – Network Security Groups (NSGs)
# Primary deployment method: Azure CLI (Bash)
#
# What this script builds (all FREE – NSGs, VNets and subnets cost nothing):
#   - Resource Group  : rg-az104-project04 (tagged)
#   - 3 NSGs          : nsg-web, nsg-app, nsg-data (one per tier)
#   - Virtual Network : vnet-az104-project04 (10.10.0.0/16)
#   - Subnets         : snet-web, snet-app, snet-data (private, NSG attached)
#                       AzureBastionSubnet (reserved, no NSG)
#
# Traffic flow enforced:
#   Internet -443-> WEB -8080-> APP -1433-> DATA -443-> Azure Storage only
#   SSH/RDP to every tier only from the Bastion subnet (jump-box network)
#
# Usage:
#   ./deploy.sh            then optionally ./test-nsg.sh to prove the rules work
# =============================================================================
set -euo pipefail

# ----------------------------- Variables -------------------------------------
RG="rg-az104-project04"
LOCATION="eastus"
VNET="vnet-az104-project04"
VNET_PREFIX="10.10.0.0/16"

WEB_PREFIX="10.10.1.0/24"
APP_PREFIX="10.10.2.0/24"
DATA_PREFIX="10.10.3.0/24"
BASTION_PREFIX="10.10.254.0/26"

TAGS=(Environment=Lab CostCenter=IT-Services "Owner=Harold Nduna" Project=AZ104-Project04)

# ----------------------------- Pre-flight ------------------------------------
echo ">> Checking your Azure login..."
# get-access-token contacts Azure, so it catches expired sessions too
if ! az account get-access-token --output none 2>/dev/null; then
  echo "   Not logged in, or the session has expired. Running 'az login'..."
  az login --output none
fi
echo "   Using subscription: $(az account show --query name --output tsv)"

# ----------------------------- Helper ----------------------------------------
# add_rule <nsg> <name> <priority> <direction> <access> <protocol> <source> <destination> <description> <port> [port...]
# Equivalent to one line of a Cisco extended ACL:
#   <priority> <access> <protocol> <source> <destination> eq <port>
add_rule() {
  local nsg=$1 name=$2 priority=$3 direction=$4 access=$5 protocol=$6 src=$7 dst=$8 desc=$9
  shift 9
  echo "   + $nsg: [$priority] $direction $access $protocol $src -> $dst port(s) $*"
  az network nsg rule create \
    --resource-group "$RG" \
    --nsg-name "$nsg" \
    --name "$name" \
    --priority "$priority" \
    --direction "$direction" \
    --access "$access" \
    --protocol "$protocol" \
    --source-address-prefixes "$src" \
    --source-port-ranges '*' \
    --destination-address-prefixes "$dst" \
    --destination-port-ranges "$@" \
    --description "$desc" \
    --output none
}

# ----------------------------- Resource Group --------------------------------
echo ">> Creating resource group $RG in $LOCATION..."
az group create --name "$RG" --location "$LOCATION" --tags "${TAGS[@]}" --output none

# ----------------------------- NSGs ------------------------------------------
# An NSG is created empty except for the 6 hidden default rules (priority 65000+).
for NSG in nsg-web nsg-app nsg-data; do
  echo ">> Creating $NSG..."
  az network nsg create \
    --resource-group "$RG" \
    --name "$NSG" \
    --location "$LOCATION" \
    --tags "${TAGS[@]}" \
    --output none
done

# ----------------------------- nsg-web (DMZ) ---------------------------------
echo ">> Adding rules to nsg-web (web tier / DMZ)..."
add_rule nsg-web Allow-HTTPS-Internet 100 Inbound Allow Tcp \
  Internet "$WEB_PREFIX" "Public HTTPS to the web tier only" 443
add_rule nsg-web Allow-Mgmt-Bastion 110 Inbound Allow Tcp \
  "$BASTION_PREFIX" "$WEB_PREFIX" "Admin access only from the Bastion (jump-box) subnet" 22 3389
add_rule nsg-web Deny-VNet-Inbound 4000 Inbound Deny '*' \
  VirtualNetwork '*' "Overrides default AllowVnetInBound (65000) - blocks lateral movement" '*'

# ----------------------------- nsg-app ---------------------------------------
echo ">> Adding rules to nsg-app (application tier)..."
add_rule nsg-app Allow-App-From-Web 100 Inbound Allow Tcp \
  "$WEB_PREFIX" "$APP_PREFIX" "Only the web tier may call the app tier" 8080
add_rule nsg-app Allow-Mgmt-Bastion 110 Inbound Allow Tcp \
  "$BASTION_PREFIX" "$APP_PREFIX" "Admin access only from the Bastion (jump-box) subnet" 22 3389
add_rule nsg-app Deny-VNet-Inbound 4000 Inbound Deny '*' \
  VirtualNetwork '*' "Overrides default AllowVnetInBound (65000) - blocks lateral movement" '*'

# ----------------------------- nsg-data --------------------------------------
echo ">> Adding rules to nsg-data (data tier)..."
add_rule nsg-data Allow-SQL-From-App 100 Inbound Allow Tcp \
  "$APP_PREFIX" "$DATA_PREFIX" "Only the app tier may reach the database port" 1433
add_rule nsg-data Allow-Mgmt-Bastion 110 Inbound Allow Tcp \
  "$BASTION_PREFIX" "$DATA_PREFIX" "Admin access only from the Bastion (jump-box) subnet" 22 3389
add_rule nsg-data Deny-VNet-Inbound 4000 Inbound Deny '*' \
  VirtualNetwork '*' "Overrides default AllowVnetInBound (65000) - blocks lateral movement" '*'
# Egress filtering (defense in depth on top of the private subnet)
add_rule nsg-data Allow-Storage-Out 100 Outbound Allow Tcp \
  "$DATA_PREFIX" Storage "Data tier may reach Azure Storage (service tag) over HTTPS" 443
add_rule nsg-data Deny-Internet-Out 4000 Outbound Deny '*' \
  "$DATA_PREFIX" Internet "Overrides default AllowInternetOutBound - prevents data exfiltration" '*'

# ----------------------------- Virtual Network -------------------------------
echo ">> Creating virtual network $VNET ($VNET_PREFIX)..."
az network vnet create \
  --resource-group "$RG" \
  --name "$VNET" \
  --location "$LOCATION" \
  --address-prefixes "$VNET_PREFIX" \
  --tags "${TAGS[@]}" \
  --output none

# ----------------------------- Subnets + NSG association ---------------------
# --network-security-group attaches the NSG to the subnet
# (on-site: applying an ACL to a VLAN interface)
echo ">> Creating snet-web and attaching nsg-web..."
az network vnet subnet create \
  --resource-group "$RG" --vnet-name "$VNET" \
  --name snet-web --address-prefixes "$WEB_PREFIX" \
  --network-security-group nsg-web \
  --default-outbound-access false \
  --output none

echo ">> Creating snet-app and attaching nsg-app..."
az network vnet subnet create \
  --resource-group "$RG" --vnet-name "$VNET" \
  --name snet-app --address-prefixes "$APP_PREFIX" \
  --network-security-group nsg-app \
  --default-outbound-access false \
  --output none

echo ">> Creating snet-data and attaching nsg-data..."
az network vnet subnet create \
  --resource-group "$RG" --vnet-name "$VNET" \
  --name snet-data --address-prefixes "$DATA_PREFIX" \
  --network-security-group nsg-data \
  --service-endpoints Microsoft.Storage \
  --default-outbound-access false \
  --output none

echo ">> Creating AzureBastionSubnet (reserved, no NSG – Bastion NSGs need special mandatory rules)..."
az network vnet subnet create \
  --resource-group "$RG" --vnet-name "$VNET" \
  --name AzureBastionSubnet --address-prefixes "$BASTION_PREFIX" \
  --output none

# ----------------------------- Verification ----------------------------------
echo ""
echo "================ VERIFICATION ================"
for NSG in nsg-web nsg-app nsg-data; do
  echo ""
  echo ">> Custom rules in $NSG (default rules 65000+ are hidden here):"
  az network nsg rule list \
    --resource-group "$RG" \
    --nsg-name "$NSG" \
    --query "sort_by([], &priority)[].{Priority:priority, Name:name, Direction:direction, Access:access, Protocol:protocol, Source:sourceAddressPrefix || join(',', sourceAddressPrefixes), Destination:destinationAddressPrefix || join(',', destinationAddressPrefixes), Ports:destinationPortRange || join(',', destinationPortRanges)}" \
    --output table
done

echo ""
echo ">> Subnet -> NSG associations:"
printf "   %-20s %-16s %s\n" "Subnet" "Prefix" "NSG"
for SUBNET in snet-web snet-app snet-data AzureBastionSubnet; do
  PREFIX=$(az network vnet subnet show --resource-group "$RG" --vnet-name "$VNET" \
    --name "$SUBNET" --query addressPrefix --output tsv)
  NSG_ID=$(az network vnet subnet show --resource-group "$RG" --vnet-name "$VNET" \
    --name "$SUBNET" --query "networkSecurityGroup.id" --output tsv)
  NSG_NAME="${NSG_ID##*/}"
  printf "   %-20s %-16s %s\n" "$SUBNET" "$PREFIX" "${NSG_NAME:-(none)}"
done

echo ""
echo "Done. Next steps:"
echo "  ./test-nsg.sh   – deploy 3 small test VMs and prove the rules work (a few cents)"
echo "  ./cleanup.sh    – delete everything when finished"
