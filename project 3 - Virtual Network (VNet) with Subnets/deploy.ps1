<#
=============================================================================
 Project 03 – Virtual Network (VNet) with Subnets
 Reference deployment method: Azure PowerShell (Az module)

 Run from Azure Cloud Shell (PowerShell) or locally with PowerShell 7 + Az:
   Install-Module Az -Scope CurrentUser    # one-time, local only
   ./deploy.ps1
=============================================================================
#>

$ErrorActionPreference = 'Stop'

# ----------------------------- Variables -------------------------------------
$rg         = 'rg-az104-project03'
$location   = 'eastus'
$vnetName   = 'vnet-az104-project03'
$vnetPrefix = '10.10.0.0/16'
$tags       = @{
    Environment = 'Lab'
    CostCenter  = 'IT-Services'
    Owner       = 'Harold Nduna'
    Project     = 'AZ104-Project03'
}

# ----------------------------- Pre-flight ------------------------------------
if (-not (Get-AzContext)) { Connect-AzAccount | Out-Null }
Write-Host ">> Using subscription: $((Get-AzContext).Subscription.Name)"

# ----------------------------- Resource Group --------------------------------
Write-Host ">> Creating resource group $rg..."
New-AzResourceGroup -Name $rg -Location $location -Tag $tags -Force | Out-Null

# ----------------------------- Subnet configs --------------------------------
# In PowerShell, subnets are built as in-memory config objects first,
# then passed to New-AzVirtualNetwork in one call.
# -DefaultOutboundAccess $false makes each workload subnet private.
$web = New-AzVirtualNetworkSubnetConfig -Name 'snet-web'  -AddressPrefix '10.10.1.0/24' -DefaultOutboundAccess $false
$app = New-AzVirtualNetworkSubnetConfig -Name 'snet-app'  -AddressPrefix '10.10.2.0/24' -DefaultOutboundAccess $false
$data = New-AzVirtualNetworkSubnetConfig -Name 'snet-data' -AddressPrefix '10.10.3.0/24' `
          -ServiceEndpoint 'Microsoft.Storage' -DefaultOutboundAccess $false
$bastion = New-AzVirtualNetworkSubnetConfig -Name 'AzureBastionSubnet' -AddressPrefix '10.10.254.0/26'

# ----------------------------- Virtual Network -------------------------------
Write-Host ">> Creating virtual network $vnetName with 4 subnets..."
New-AzVirtualNetwork `
    -Name $vnetName `
    -ResourceGroupName $rg `
    -Location $location `
    -AddressPrefix $vnetPrefix `
    -Subnet $web, $app, $data, $bastion `
    -Tag $tags | Out-Null

# ----------------------------- Verification ----------------------------------
$vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $rg
Write-Host "`n================ VERIFICATION ================"
$vnet | Select-Object Name, Location, @{n='AddressSpace';e={$_.AddressSpace.AddressPrefixes -join ','}}, ProvisioningState |
    Format-Table -AutoSize
$vnet.Subnets | Select-Object Name,
    @{n='Prefix';e={$_.AddressPrefix -join ','}},
    @{n='PrivateSubnet';e={$_.DefaultOutboundAccess -eq $false}},
    @{n='ServiceEndpoints';e={($_.ServiceEndpoints.Service) -join ','}} |
    Format-Table -AutoSize

Write-Host "Done. Clean up with: Remove-AzResourceGroup -Name $rg -Force"
