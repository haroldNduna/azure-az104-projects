#!/usr/bin/env bash
# =============================================================================
# Project 05 – Cleanup / teardown
# Deletes the resource group: VMs, disks, NICs, NSGs, ASGs, VNet, NAT Gateway,
# public IP and storage account.
#
# Security+: decommissioning removes unmonitored assets and shrinks the attack
# surface. It also stops all charges (the NAT Gateway bills even with VMs off).
# =============================================================================
set -euo pipefail

RG="rg-az104-project05"

if [[ "$(az group exists --name "$RG")" != "true" ]]; then
  echo "Resource group $RG does not exist. Nothing to delete."
  exit 0
fi

echo "Resources that will be DELETED:"
az resource list --resource-group "$RG" --query "[].{Name:name, Type:type}" --output table

read -r -p "Type the resource group name ($RG) to confirm deletion: " CONFIRM
if [[ "$CONFIRM" != "$RG" ]]; then
  echo "Confirmation did not match. Aborting – nothing was deleted."
  exit 1
fi

# --force-deletion-types speeds up VM deletion (like the portal's 'force delete')
az group delete --name "$RG" --yes --no-wait \
  --force-deletion-types Microsoft.Compute/virtualMachines
echo "Deletion started (5-10 minutes with VMs). Check progress with:"
echo "  az group exists --name $RG     # prints 'false' when it's gone"
echo ""
echo "Also delete any downloaded .pem SSH key for these VMs from your computer."
# NetworkWatcherRG is left in place: it's free and Project 13 uses it.
