<#
=============================================================================
 Project 04 – Network Security Groups (NSGs)
 Reference deployment method: Azure PowerShell (Az module)

 Run from Azure Cloud Shell (PowerShell) or locally with PowerShell 7 + Az:
   ./deploy.ps1
=============================================================================
#>
$ErrorActionPreference = 'Stop'

# ----------------------------- Variables -------------------------------------
$rg       = 'rg-az104-project04'
$location = 'eastus'
$vnetName = 'vnet-az104-project04'
$web      = '10.10.1.0/24'
$app      = '10.10.2.0/24'
$data     = '10.10.3.0/24'
$bastion  = '10.10.254.0/26'
$tags     = @{ Environment='Lab'; CostCenter='IT-Services'; Owner='Harold Nduna'; Project='AZ104-Project04' }

if (-not (Get-AzContext)) { Connect-AzAccount | Out-Null }
Write-Host ">> Using subscription: $((Get-AzContext).Subscription.Name)"

New-AzResourceGroup -Name $rg -Location $location -Tag $tags -Force | Out-Null

# ----------------------------- Helper ----------------------------------------
# Builds one rule in memory (like writing one ACL line before applying it)
function New-Rule($Name, $Priority, $Direction, $Access, $Protocol, $Source, $Destination, [string[]]$Ports, $Desc) {
    New-AzNetworkSecurityRuleConfig -Name $Name -Priority $Priority -Direction $Direction `
        -Access $Access -Protocol $Protocol `
        -SourceAddressPrefix $Source -SourcePortRange '*' `
        -DestinationAddressPrefix $Destination -DestinationPortRange $Ports `
        -Description $Desc
}

# ----------------------------- nsg-web ---------------------------------------
$webRules = @(
    New-Rule 'Allow-HTTPS-Internet' 100  Inbound Allow Tcp 'Internet'     $web @('443')         'Public HTTPS to the web tier only'
    New-Rule 'Allow-Mgmt-Bastion'   110  Inbound Allow Tcp $bastion       $web @('22','3389')   'Admin access only from the Bastion subnet'
    New-Rule 'Deny-VNet-Inbound'    4000 Inbound Deny  '*' 'VirtualNetwork' '*' @('*')          'Overrides default AllowVnetInBound'
)
$nsgWeb = New-AzNetworkSecurityGroup -Name 'nsg-web' -ResourceGroupName $rg -Location $location -SecurityRules $webRules -Tag $tags -Force

# ----------------------------- nsg-app ---------------------------------------
$appRules = @(
    New-Rule 'Allow-App-From-Web'   100  Inbound Allow Tcp $web           $app @('8080')        'Only the web tier may call the app tier'
    New-Rule 'Allow-Mgmt-Bastion'   110  Inbound Allow Tcp $bastion       $app @('22','3389')   'Admin access only from the Bastion subnet'
    New-Rule 'Deny-VNet-Inbound'    4000 Inbound Deny  '*' 'VirtualNetwork' '*' @('*')          'Overrides default AllowVnetInBound'
)
$nsgApp = New-AzNetworkSecurityGroup -Name 'nsg-app' -ResourceGroupName $rg -Location $location -SecurityRules $appRules -Tag $tags -Force

# ----------------------------- nsg-data --------------------------------------
$dataRules = @(
    New-Rule 'Allow-SQL-From-App'   100  Inbound  Allow Tcp $app          $data @('1433')       'Only the app tier may reach the database port'
    New-Rule 'Allow-Mgmt-Bastion'   110  Inbound  Allow Tcp $bastion      $data @('22','3389')  'Admin access only from the Bastion subnet'
    New-Rule 'Deny-VNet-Inbound'    4000 Inbound  Deny  '*' 'VirtualNetwork' '*' @('*')         'Overrides default AllowVnetInBound'
    New-Rule 'Allow-Storage-Out'    100  Outbound Allow Tcp $data         'Storage'  @('443')   'Data tier may reach Azure Storage over HTTPS'
    New-Rule 'Deny-Internet-Out'    4000 Outbound Deny  '*' $data         'Internet' @('*')     'Overrides default AllowInternetOutBound'
)
$nsgData = New-AzNetworkSecurityGroup -Name 'nsg-data' -ResourceGroupName $rg -Location $location -SecurityRules $dataRules -Tag $tags -Force

# ----------------------------- Subnets + VNet --------------------------------
$subnets = @(
    New-AzVirtualNetworkSubnetConfig -Name 'snet-web'  -AddressPrefix $web  -NetworkSecurityGroup $nsgWeb  -DefaultOutboundAccess $false
    New-AzVirtualNetworkSubnetConfig -Name 'snet-app'  -AddressPrefix $app  -NetworkSecurityGroup $nsgApp  -DefaultOutboundAccess $false
    New-AzVirtualNetworkSubnetConfig -Name 'snet-data' -AddressPrefix $data -NetworkSecurityGroup $nsgData -DefaultOutboundAccess $false -ServiceEndpoint 'Microsoft.Storage'
    New-AzVirtualNetworkSubnetConfig -Name 'AzureBastionSubnet' -AddressPrefix $bastion
)
New-AzVirtualNetwork -Name $vnetName -ResourceGroupName $rg -Location $location `
    -AddressPrefix '10.10.0.0/16' -Subnet $subnets -Tag $tags -Force | Out-Null

# ----------------------------- Verification ----------------------------------
Write-Host "`n================ VERIFICATION ================"
foreach ($n in 'nsg-web','nsg-app','nsg-data') {
    Write-Host "`n>> $n custom rules:"
    (Get-AzNetworkSecurityGroup -Name $n -ResourceGroupName $rg).SecurityRules |
        Sort-Object Priority |
        Select-Object Priority, Name, Direction, Access, Protocol,
            @{n='Source';e={$_.SourceAddressPrefix -join ','}},
            @{n='Destination';e={$_.DestinationAddressPrefix -join ','}},
            @{n='Ports';e={$_.DestinationPortRange -join ','}} |
        Format-Table -AutoSize
}
(Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $rg).Subnets |
    Select-Object Name, @{n='Prefix';e={$_.AddressPrefix -join ','}},
        @{n='NSG';e={ if ($_.NetworkSecurityGroup) { $_.NetworkSecurityGroup.Id.Split('/')[-1] } else { '(none)' } }} |
    Format-Table -AutoSize

Write-Host "Done. Clean up with: Remove-AzResourceGroup -Name $rg -Force"
