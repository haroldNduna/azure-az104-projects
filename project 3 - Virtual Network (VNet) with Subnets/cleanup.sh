#!/usr/bin/env bash
# =============================================================================
# Project 03 – Cleanup / teardown
# Deletes the whole resource group (and everything inside it).
#
# Why this matters (Security+): decommissioning unused resources reduces the
# attack surface and avoids orphaned assets nobody is monitoring.
# =============================================================================
set -euo pipefail

RG="rg-az104-project03"

if ! az group exists --name "$RG" | grep -q true; then
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

# --yes skips Azure's own prompt (we already confirmed); --no-wait returns immediately
az group delete --name "$RG" --yes --no-wait
echo "Deletion started. Check progress with:"
echo "  az group exists --name $RG     # prints 'false' when it's gone"

# NOTE: Azure auto-creates a 'NetworkWatcherRG' resource group the first time
# you create a VNet in a region. It is free and is reused by later projects
# (Project 12 uses Network Watcher), so we leave it in place.
