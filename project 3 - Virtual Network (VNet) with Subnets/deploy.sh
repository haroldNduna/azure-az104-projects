#!/usr/bin/env bash
# =============================================================================
# Project 03 – Virtual Network (VNet) with Subnets
# Primary deployment method: Azure CLI (Bash)
#
# What this script builds:
#   - Resource Group  : rg-az104-project03 (tagged)
#   - Virtual Network : vnet-az104-project03 (10.10.0.0/16)
#   - Subnets         : snet-web, snet-app, snet-data, AzureBastionSubnet
#   - snet-data gets a Microsoft.Storage service endpoint (links to Project 02)
#   - All subnets are PRIVATE (no implicit default outbound internet access)
#
# Cost: VNets and subnets are FREE. Nothing in this project bills you.
#
# Usage:
#   chmod +x deploy.sh
#   ./deploy.sh
# =============================================================================

# Stop on errors (-e), unset variables (-u), and failures inside pipes (-o pipefail)
set -euo pipefail

# ----------------------------- Variables -------------------------------------
RG="rg-az104-project03"
LOCATION="eastus"
VNET="vnet-az104-project03"
VNET_PREFIX="10.10.0.0/16"

WEB_SUBNET="snet-web";   WEB_PREFIX="10.10.1.0/24"
APP_SUBNET="snet-app";   APP_PREFIX="10.10.2.0/24"
DATA_SUBNET="snet-data"; DATA_PREFIX="10.10.3.0/24"
BASTION_SUBNET="AzureBastionSubnet"; BASTION_PREFIX="10.10.254.0/26"  # name is mandatory, min size /26

# Tags – quoted so "Harold Nduna" stays ONE value (unquoted, the space splits it)
TAGS=(Environment=Lab CostCenter=IT-Services "Owner=Harold Nduna" Project=AZ104-Project03)

# ----------------------------- Pre-flight ------------------------------------
echo ">> Checking you are logged in to Azure..."
# 'az account get-access-token' actually contacts Azure, so it also catches
# expired sessions ('az account show' only reads the local cache).
if ! az account get-access-token --output none 2>/dev/null; then
  echo "   Not logged in, or your session has expired. Running 'az login'..."
  az login --output none
fi
echo "   Using subscription: $(az account show --query name --output tsv)"

# ----------------------------- Resource Group --------------------------------
echo ">> Creating resource group $RG in $LOCATION..."
az group create \
  --name "$RG" \
  --location "$LOCATION" \
  --tags "${TAGS[@]}" \
  --output none

# ----------------------------- Virtual Network -------------------------------
# The VNet is created WITHOUT subnets first, then each subnet is added
# separately so every subnet gets the same security settings.
echo ">> Creating virtual network $VNET ($VNET_PREFIX)..."
az network vnet create \
  --resource-group "$RG" \
  --name "$VNET" \
  --location "$LOCATION" \
  --address-prefixes "$VNET_PREFIX" \
  --tags "${TAGS[@]}" \
  --output none

# ----------------------------- Subnets ---------------------------------------
# --default-outbound-access false = private subnet. VMs placed here later
# cannot reach the internet unless we add an explicit method (NAT Gateway,
# Load Balancer outbound rule, or a public IP). Secure by default.

echo ">> Creating subnet $WEB_SUBNET ($WEB_PREFIX)..."
az network vnet subnet create \
  --resource-group "$RG" \
  --vnet-name "$VNET" \
  --name "$WEB_SUBNET" \
  --address-prefixes "$WEB_PREFIX" \
  --default-outbound-access false \
  --output none

echo ">> Creating subnet $APP_SUBNET ($APP_PREFIX)..."
az network vnet subnet create \
  --resource-group "$RG" \
  --vnet-name "$VNET" \
  --name "$APP_SUBNET" \
  --address-prefixes "$APP_PREFIX" \
  --default-outbound-access false \
  --output none

echo ">> Creating subnet $DATA_SUBNET ($DATA_PREFIX) with Microsoft.Storage service endpoint..."
az network vnet subnet create \
  --resource-group "$RG" \
  --vnet-name "$VNET" \
  --name "$DATA_SUBNET" \
  --address-prefixes "$DATA_PREFIX" \
  --service-endpoints Microsoft.Storage \
  --default-outbound-access false \
  --output none

echo ">> Creating subnet $BASTION_SUBNET ($BASTION_PREFIX) – reserved for Azure Bastion later..."
az network vnet subnet create \
  --resource-group "$RG" \
  --vnet-name "$VNET" \
  --name "$BASTION_SUBNET" \
  --address-prefixes "$BASTION_PREFIX" \
  --output none

# ----------------------------- Verification ----------------------------------
echo ""
echo "================ VERIFICATION ================"
echo ">> Virtual network:"
az network vnet show \
  --resource-group "$RG" \
  --name "$VNET" \
  --query "{Name:name, Location:location, AddressSpace:addressSpace.addressPrefixes[0], State:provisioningState}" \
  --output table

echo ""
echo ">> Subnets:"
az network vnet subnet list \
  --resource-group "$RG" \
  --vnet-name "$VNET" \
  --query "[].{Subnet:name, Prefix:addressPrefix, PrivateSubnet:defaultOutboundAccess==\`false\`, ServiceEndpoints:join(',', serviceEndpoints[].service || \`[]\`)}" \
  --output table

echo ""
echo ">> Tags on the resource group:"
az group show --name "$RG" --query tags --output json

echo ""
echo "Done. Take your screenshots, then run ./cleanup.sh when finished."
