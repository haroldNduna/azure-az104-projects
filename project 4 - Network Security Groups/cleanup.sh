#!/usr/bin/env bash
# =============================================================================
# Project 04 – Cleanup / teardown
# Deletes the resource group: NSGs, VNet and the test VMs (with their disks/NICs).
#
# Security+: decommissioning unused resources reduces the attack surface and
# leaves no orphaned, unmonitored assets. It also stops VM charges.
# =============================================================================
set -euo pipefail

RG="rg-az104-project04"

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

az group delete --name "$RG" --yes --no-wait
echo "Deletion started (VMs make this take 3-8 minutes). Check progress with:"
echo "  az group exists --name $RG     # prints 'false' when it's gone"

# NetworkWatcherRG is left in place: it's free and Project 13 uses it.
