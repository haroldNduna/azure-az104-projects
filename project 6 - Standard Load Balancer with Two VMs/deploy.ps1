<#
=============================================================================
 Project 06 - Standard Load Balancer with Two VMs
 Reference deployment method: Azure PowerShell (Az module)

 Same design as deploy.sh (East US 2, D2als_v6 in zones 1 and 3), but the
 NSG includes the HTTP rule from the start (final state).
 Needs an SSH public key at ~/.ssh/id_rsa.pub.
   ./deploy.ps1
=============================================================================
#>
$ErrorActionPreference = 'Stop'

$rg        = 'rg-az104-project06'
$location  = 'eastus2'
$vmSize    = 'Standard_D2als_v6'
$zones     = @('1', '3')
$adminUser = 'azureuser'
$sshKey    = Get-Content -Raw (Join-Path $HOME '.ssh/id_rsa.pub')
$cloudInit = Get-Content -Raw (Join-Path $PSScriptRoot 'scripts/cloud-init-web.yaml')
$tags      = @{ Environment='Lab'; CostCenter='IT-Services'; Owner='Harold Nduna'; Project='AZ104-Project06' }

if (-not (Get-AzContext)) { Connect-AzAccount | Out-Null }
New-AzResourceGroup -Name $rg -Location $location -Tag $tags -Force | Out-Null

# ----------------------------- NSG -------------------------------------------
$nsg = New-AzNetworkSecurityGroup -Name 'nsg-web' -ResourceGroupName $rg -Location $location -Tag $tags -Force -SecurityRules @(
    New-AzNetworkSecurityRuleConfig -Name 'Allow-HTTP-Internet' -Priority 100 -Direction Inbound -Access Allow -Protocol Tcp `
        -SourceAddressPrefix 'Internet' -SourcePortRange '*' -DestinationAddressPrefix '10.10.1.0/24' -DestinationPortRange 80
    New-AzNetworkSecurityRuleConfig -Name 'Allow-Mgmt-Bastion' -Priority 110 -Direction Inbound -Access Allow -Protocol Tcp `
        -SourceAddressPrefix '10.10.254.0/26' -SourcePortRange '*' -DestinationAddressPrefix '10.10.1.0/24' -DestinationPortRange 22,3389
    New-AzNetworkSecurityRuleConfig -Name 'Deny-VNet-Inbound' -Priority 4000 -Direction Inbound -Access Deny -Protocol '*' `
        -SourceAddressPrefix 'VirtualNetwork' -SourcePortRange '*' -DestinationAddressPrefix '*' -DestinationPortRange '*'
)

# ----------------------------- VNet ------------------------------------------
$vnet = New-AzVirtualNetwork -Name 'vnet-az104-project06' -ResourceGroupName $rg -Location $location `
    -AddressPrefix '10.10.0.0/16' -Tag $tags -Force -Subnet @(
        New-AzVirtualNetworkSubnetConfig -Name 'snet-web' -AddressPrefix '10.10.1.0/24' -NetworkSecurityGroup $nsg -DefaultOutboundAccess $false
        New-AzVirtualNetworkSubnetConfig -Name 'AzureBastionSubnet' -AddressPrefix '10.10.254.0/26'
    )
$subnet = $vnet.Subnets | Where-Object Name -eq 'snet-web'

# ----------------------------- Public IP + load balancer ---------------------
$pip = New-AzPublicIpAddress -Name 'pip-lb-az104-project06' -ResourceGroupName $rg -Location $location `
    -Sku Standard -AllocationMethod Static -IpAddressVersion IPv4 -Zone 1,2,3 -Tag $tags -Force

$fe    = New-AzLoadBalancerFrontendIpConfig -Name 'fe-web' -PublicIpAddress $pip
$pool  = New-AzLoadBalancerBackendAddressPoolConfig -Name 'bepool-web'
$probe = New-AzLoadBalancerProbeConfig -Name 'probe-http' -Protocol Http -Port 80 -RequestPath '/' -IntervalInSeconds 5 -ProbeCount 1
$rule  = New-AzLoadBalancerRuleConfig -Name 'rule-http' -FrontendIpConfiguration $fe -BackendAddressPool $pool `
    -Probe $probe -Protocol Tcp -FrontendPort 80 -BackendPort 80 -IdleTimeoutInMinutes 4 `
    -EnableTcpReset -DisableOutboundSNAT -LoadDistribution Default
$out   = New-AzLoadBalancerOutboundRuleConfig -Name 'rule-outbound' -FrontendIPConfiguration $fe `
    -BackendAddressPool $pool -Protocol All -IdleTimeoutInMinutes 4 -EnableTcpReset -AllocatedOutboundPort 10000

$lb = New-AzLoadBalancer -Name 'lb-az104-project06' -ResourceGroupName $rg -Location $location -Sku Standard `
    -FrontendIpConfiguration $fe -BackendAddressPool $pool -Probe $probe -LoadBalancingRule $rule `
    -OutboundRule $out -Tag $tags -Force
$poolId = $lb.BackendAddressPools[0].Id

# ----------------------------- VMs in different zones ------------------------
$cred = New-Object PSCredential($adminUser, (ConvertTo-SecureString ' ' -AsPlainText -Force))
$specs = @(
    @{ Name = 'vm-lb1'; Ip = '10.10.1.4'; Zone = $zones[0] },
    @{ Name = 'vm-lb2'; Ip = '10.10.1.5'; Zone = $zones[1] }
)
foreach ($s in $specs) {
    $nic = New-AzNetworkInterface -Name "nic-$($s.Name)" -ResourceGroupName $rg -Location $location `
        -SubnetId $subnet.Id -PrivateIpAddress $s.Ip -LoadBalancerBackendAddressPoolId $poolId -Tag $tags -Force

    $vm = New-AzVMConfig -VMName $s.Name -VMSize $vmSize -Zone $s.Zone -SecurityType TrustedLaunch -Tags $tags
    $vm = Set-AzVMOperatingSystem -VM $vm -Linux -ComputerName $s.Name -Credential $cred `
            -DisablePasswordAuthentication -CustomData $cloudInit
    $vm = Add-AzVMSshPublicKey -VM $vm -KeyData $sshKey -Path "/home/$adminUser/.ssh/authorized_keys"
    $vm = Set-AzVMSourceImage -VM $vm -PublisherName 'Canonical' -Offer 'ubuntu-24_04-lts' -Skus 'server' -Version 'latest'
    $vm = Set-AzVMOSDisk -VM $vm -CreateOption FromImage -StorageAccountType Standard_LRS -DeleteOption Delete
    $vm.StorageProfile.DiskControllerType = 'NVMe'
    $vm = Set-AzVMUefi -VM $vm -EnableSecureBoot $true -EnableVtpm $true
    $vm = Add-AzVMNetworkInterface -VM $vm -Id $nic.Id -DeleteOption Delete
    $vm = Set-AzVMBootDiagnostic -VM $vm -Enable
    New-AzVM -ResourceGroupName $rg -Location $location -VM $vm | Out-Null
    Write-Host "   + $($s.Name) in zone $($s.Zone)"
}

Write-Host "Website: http://$((Get-AzPublicIpAddress -Name 'pip-lb-az104-project06' -ResourceGroupName $rg).IpAddress)"
Write-Host "Clean up with: Remove-AzResourceGroup -Name $rg -Force"
