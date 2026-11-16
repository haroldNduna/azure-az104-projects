#!/usr/bin/env bash
# =============================================================================
# Project 06 - Cleanup / teardown
# Deletes the resource group: VMs, disks, NICs, load balancer, public IP,
# NSG and VNet.
#
# Security+: decommissioning removes unmonitored assets and the public entry
# point. It also stops charges - the load balancer and public IP bill even
# when the VMs are off.
# =============================================================================
set -euo pipefail

RG="rg-az104-project06"

if [[ "$(az group exists --name "$RG")" != "true" ]]; then
  echo "Resource group $RG does not exist. Nothing to delete."
  exit 0
fi

echo "Resources that will be DELETED:"
az resource list --resource-group "$RG" --query "[].{Name:name, Type:type}" --output table

read -r -p "Type the resource group name ($RG) to confirm deletion: " CONFIRM
if [[ "$CONFIRM" != "$RG" ]]; then
  echo "Confirmation did not match. Aborting - nothing was deleted."
  exit 1
fi

az group delete --name "$RG" --yes --no-wait \
  --force-deletion-types Microsoft.Compute/virtualMachines
echo "Deletion started (5-10 minutes with VMs). Check progress with:"
echo "  az group exists --name $RG     # prints 'false' when it's gone"
echo ""
echo "Also delete ~/Downloads/az104-p06-key.pem if you downloaded it from the portal."
