<#
=============================================================================
 Project 05 – Virtual Machines, ASGs & Extensions
 Reference deployment method: Azure PowerShell (Az module)

 Same design as deploy.sh, in East US 2. The extension script and cloud-init
 file are passed inline (no storage account), like the Bicep version.

 Run from Azure Cloud Shell (PowerShell) or PowerShell 7 with the Az module:
   ./deploy.ps1
 Needs an SSH public key at ~/.ssh/id_rsa.pub (create one with ssh-keygen).
=============================================================================
#>
$ErrorActionPreference = 'Stop'

# ----------------------------- Variables -------------------------------------
$rg        = 'rg-az104-project05'
$location  = 'eastus2'
$vmSize    = 'Standard_D2s_v3'
$adminUser = 'azureuser'
$sshKey    = Get-Content -Raw (Join-Path $HOME '.ssh/id_rsa.pub')
$scriptDir = $PSScriptRoot
$tags      = @{ Environment='Lab'; CostCenter='IT-Services'; Owner='Harold Nduna'; Project='AZ104-Project05' }

if (-not (Get-AzContext)) { Connect-AzAccount | Out-Null }
Write-Host ">> Using subscription: $((Get-AzContext).Subscription.Name)"
New-AzResourceGroup -Name $rg -Location $location -Tag $tags -Force | Out-Null

# ----------------------------- ASGs ------------------------------------------
$asgWeb = New-AzApplicationSecurityGroup -Name 'asg-web' -ResourceGroupName $rg -Location $location -Tag $tags -Force
$asgApp = New-AzApplicationSecurityGroup -Name 'asg-app' -ResourceGroupName $rg -Location $location -Tag $tags -Force

# ----------------------------- NSGs ------------------------------------------
$denyVnet = New-AzNetworkSecurityRuleConfig -Name 'Deny-VNet-Inbound' -Priority 4000 -Direction Inbound `
    -Access Deny -Protocol '*' -SourceAddressPrefix 'VirtualNetwork' -SourcePortRange '*' `
    -DestinationAddressPrefix '*' -DestinationPortRange '*'

$nsgWeb = New-AzNetworkSecurityGroup -Name 'nsg-web' -ResourceGroupName $rg -Location $location -Tag $tags -Force -SecurityRules @(
    New-AzNetworkSecurityRuleConfig -Name 'Allow-HTTPS-Internet' -Priority 100 -Direction Inbound -Access Allow -Protocol Tcp `
        -SourceAddressPrefix 'Internet' -SourcePortRange '*' -DestinationAddressPrefix '10.10.1.0/24' -DestinationPortRange 443
    New-AzNetworkSecurityRuleConfig -Name 'Allow-Mgmt-Bastion' -Priority 110 -Direction Inbound -Access Allow -Protocol Tcp `
        -SourceAddressPrefix '10.10.254.0/26' -SourcePortRange '*' -DestinationAddressPrefix '10.10.1.0/24' -DestinationPortRange 22,3389
    $denyVnet
)

# The ASG rule: badges instead of IP ranges
$nsgApp = New-AzNetworkSecurityGroup -Name 'nsg-app' -ResourceGroupName $rg -Location $location -Tag $tags -Force -SecurityRules @(
    New-AzNetworkSecurityRuleConfig -Name 'Allow-App-From-ASG-Web' -Priority 100 -Direction Inbound -Access Allow -Protocol Tcp `
        -SourceApplicationSecurityGroup $asgWeb -SourcePortRange '*' `
        -DestinationApplicationSecurityGroup $asgApp -DestinationPortRange 8080
    New-AzNetworkSecurityRuleConfig -Name 'Allow-Mgmt-Bastion' -Priority 110 -Direction Inbound -Access Allow -Protocol Tcp `
        -SourceAddressPrefix '10.10.254.0/26' -SourcePortRange '*' -DestinationAddressPrefix '10.10.2.0/24' -DestinationPortRange 22,3389
    $denyVnet
)

$nsgVmWeb1 = New-AzNetworkSecurityGroup -Name 'nsg-vm-web1' -ResourceGroupName $rg -Location $location -Tag $tags -Force -SecurityRules @(
    New-AzNetworkSecurityRuleConfig -Name 'Deny-RDP-Host' -Priority 100 -Direction Inbound -Access Deny -Protocol Tcp `
        -SourceAddressPrefix '*' -SourcePortRange '*' -DestinationAddressPrefix '*' -DestinationPortRange 3389
)

# ----------------------------- NAT Gateway -----------------------------------
$pip = New-AzPublicIpAddress -Name 'pip-nat-az104-project05' -ResourceGroupName $rg -Location $location `
    -Sku Standard -AllocationMethod Static -IpAddressVersion IPv4 -Tag $tags -Force
$nat = New-AzNatGateway -Name 'nat-az104-project05' -ResourceGroupName $rg -Location $location `
    -Sku Standard -IdleTimeoutInMinutes 4 -PublicIpAddress $pip -Tag $tags -Force

# ----------------------------- VNet ------------------------------------------
$subnets = @(
    New-AzVirtualNetworkSubnetConfig -Name 'snet-web' -AddressPrefix '10.10.1.0/24' -NetworkSecurityGroup $nsgWeb -NatGateway $nat -DefaultOutboundAccess $false
    New-AzVirtualNetworkSubnetConfig -Name 'snet-app' -AddressPrefix '10.10.2.0/24' -NetworkSecurityGroup $nsgApp -DefaultOutboundAccess $false
    New-AzVirtualNetworkSubnetConfig -Name 'AzureBastionSubnet' -AddressPrefix '10.10.254.0/26'
)
$vnet = New-AzVirtualNetwork -Name 'vnet-az104-project05' -ResourceGroupName $rg -Location $location `
    -AddressPrefix '10.10.0.0/16' -Subnet $subnets -Tag $tags -Force
$snetWeb = $vnet.Subnets | Where-Object Name -eq 'snet-web'
$snetApp = $vnet.Subnets | Where-Object Name -eq 'snet-app'

# ----------------------------- VMs -------------------------------------------
function New-LabVm {
    param($Name, $Subnet, $Ip, $Asg, $NicNsg, [int]$DataDiskGB = 0, [string]$CustomData)

    $nicParams = @{
        Name = "nic-$Name"; ResourceGroupName = $rg; Location = $location; Tag = $tags; Force = $true
        SubnetId = $Subnet.Id; PrivateIpAddress = $Ip
    }
    if ($Asg)    { $nicParams.ApplicationSecurityGroupId = $Asg.Id }
    if ($NicNsg) { $nicParams.NetworkSecurityGroupId     = $NicNsg.Id }
    $nic = New-AzNetworkInterface @nicParams

    $cred = New-Object PSCredential($adminUser, (ConvertTo-SecureString ' ' -AsPlainText -Force))
    $osParams = @{ Linux = $true; ComputerName = $Name; Credential = $cred; DisablePasswordAuthentication = $true }
    if ($CustomData) { $osParams.CustomData = $CustomData }

    $vm = New-AzVMConfig -VMName $Name -VMSize $vmSize -SecurityType TrustedLaunch -Tags $tags
    $vm = Set-AzVMOperatingSystem -VM $vm @osParams
    $vm = Add-AzVMSshPublicKey -VM $vm -KeyData $sshKey -Path "/home/$adminUser/.ssh/authorized_keys"
    $vm = Set-AzVMSourceImage -VM $vm -PublisherName 'Canonical' -Offer 'ubuntu-24_04-lts' -Skus 'server' -Version 'latest'
    $vm = Set-AzVMOSDisk -VM $vm -CreateOption FromImage -StorageAccountType Standard_LRS -DeleteOption Delete
    $vm = Set-AzVMUefi -VM $vm -EnableSecureBoot $true -EnableVtpm $true
    $vm = Add-AzVMNetworkInterface -VM $vm -Id $nic.Id -DeleteOption Delete
    $vm = Set-AzVMBootDiagnostic -VM $vm -Enable
    if ($DataDiskGB -gt 0) {
        $vm = Add-AzVMDataDisk -VM $vm -Name "$Name-datadisk" -Lun 0 -CreateOption Empty `
            -DiskSizeInGB $DataDiskGB -StorageAccountType Standard_LRS -DeleteOption Delete
    }
    New-AzVM -ResourceGroupName $rg -Location $location -VM $vm | Out-Null
    Write-Host "   + $Name ($Ip)"
}

Write-Host ">> Creating VMs (a few minutes each)..."
$cloudInit = Get-Content -Raw (Join-Path $scriptDir 'scripts/cloud-init-app.yaml')
New-LabVm -Name 'vm-web1' -Subnet $snetWeb -Ip '10.10.1.4' -Asg $asgWeb -NicNsg $nsgVmWeb1 -DataDiskGB 4
New-LabVm -Name 'vm-web2' -Subnet $snetWeb -Ip '10.10.1.5'
New-LabVm -Name 'vm-app'  -Subnet $snetApp -Ip '10.10.2.4' -Asg $asgApp -CustomData $cloudInit

# ----------------------------- Custom Script Extension -----------------------
Write-Host ">> Custom Script Extension on vm-web1..."
$scriptB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $scriptDir 'scripts/configure-web.sh')))
Set-AzVMExtension -ResourceGroupName $rg -VMName 'vm-web1' -Location $location `
    -Name 'CustomScript' -Publisher 'Microsoft.Azure.Extensions' -ExtensionType 'CustomScript' `
    -TypeHandlerVersion '2.1' -ProtectedSettings @{ script = $scriptB64 } | Out-Null

# ----------------------------- Verification ----------------------------------
Get-AzVM -ResourceGroupName $rg -Status |
    Select-Object Name, @{n='Size';e={$_.HardwareProfile.VmSize}}, PowerState |
    Format-Table -AutoSize
Write-Host "NAT public IP: $((Get-AzPublicIpAddress -Name 'pip-nat-az104-project05' -ResourceGroupName $rg).IpAddress)"
Write-Host "Auto-shutdown: set it in the portal, or deploy main.bicep (Microsoft.DevTestLab/schedules)."
Write-Host "Clean up with: Remove-AzResourceGroup -Name $rg -Force"
