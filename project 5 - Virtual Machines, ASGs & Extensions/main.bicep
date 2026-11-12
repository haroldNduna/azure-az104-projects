// =============================================================================
// Project 05 – Virtual Machines, ASGs & Extensions (Bicep)
//
// Deploys everything into an EXISTING resource group in East US 2:
//   az group create --name rg-az104-project05 --location eastus2
//   az deployment group create --resource-group rg-az104-project05 \
//     --template-file main.bicep --parameters parameters.json \
//     --parameters adminPublicKey="$(cat ~/.ssh/id_rsa.pub)"
//
// Differences from the CLI/portal build (both valid, both exam topics):
//   - The extension script and cloud-init file are EMBEDDED (loadFileAsBase64),
//     so no storage account is needed. The script is passed in protectedSettings
//     (encrypted, never shown in deployment history).
//   - Private IPs are set statically (.4 / .5) on the NICs.
// =============================================================================

@description('Azure region. East US 2 was used because B-series capacity was unavailable in East US.')
param location string = resourceGroup().location

@description('VM size for all three VMs.')
param vmSize string = 'Standard_D2s_v3'

@description('Admin username for the Linux VMs.')
param adminUsername string = 'azureuser'

@description('SSH public key (contents of ~/.ssh/id_rsa.pub). Password login is disabled.')
@secure()
param adminPublicKey string

@description('Daily auto-shutdown time (24h, local to timeZoneId).')
param shutdownTime string = '1900'

@description('Time zone for auto-shutdown.')
param timeZoneId string = 'Central European Standard Time'

@description('Tags applied to every resource.')
param tags object = {
  Environment: 'Lab'
  CostCenter: 'IT-Services'
  Owner: 'Harold Nduna'
  Project: 'AZ104-Project05'
}

var vnetName = 'vnet-az104-project05'
var webPrefix = '10.10.1.0/24'
var appPrefix = '10.10.2.0/24'
var bastionPrefix = '10.10.254.0/26'

// ----------------------------- ASGs (badges) ---------------------------------
resource asgWeb 'Microsoft.Network/applicationSecurityGroups@2024-05-01' = {
  name: 'asg-web'
  location: location
  tags: tags
}

resource asgApp 'Microsoft.Network/applicationSecurityGroups@2024-05-01' = {
  name: 'asg-app'
  location: location
  tags: tags
}

// ----------------------------- NSGs ------------------------------------------
var mgmtFromBastion = {
  priority: 110
  direction: 'Inbound'
  access: 'Allow'
  protocol: 'Tcp'
  sourceAddressPrefix: bastionPrefix
  sourcePortRange: '*'
  destinationPortRanges: [
    '22'
    '3389'
  ]
}

var denyVnetInbound = {
  priority: 4000
  direction: 'Inbound'
  access: 'Deny'
  protocol: '*'
  sourceAddressPrefix: 'VirtualNetwork'
  sourcePortRange: '*'
  destinationAddressPrefix: '*'
  destinationPortRange: '*'
}

resource nsgWeb 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-web'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTPS-Internet'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: webPrefix
          destinationPortRange: '443'
        }
      }
      {
        name: 'Allow-Mgmt-Bastion'
        properties: union(mgmtFromBastion, { destinationAddressPrefix: webPrefix })
      }
      {
        name: 'Deny-VNet-Inbound'
        properties: denyVnetInbound
      }
    ]
  }
}

resource nsgApp 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-app'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-App-From-ASG-Web'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceApplicationSecurityGroups: [
            { id: asgWeb.id }
          ]
          sourcePortRange: '*'
          destinationApplicationSecurityGroups: [
            { id: asgApp.id }
          ]
          destinationPortRange: '8080'
          description: 'Only VMs with the asg-web badge may reach asg-app on 8080'
        }
      }
      {
        name: 'Allow-Mgmt-Bastion'
        properties: union(mgmtFromBastion, { destinationAddressPrefix: appPrefix })
      }
      {
        name: 'Deny-VNet-Inbound'
        properties: denyVnetInbound
      }
    ]
  }
}

resource nsgVmWeb1 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-vm-web1'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Deny-RDP-Host'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Deny'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3389'
          description: 'Host-level control: Linux never needs RDP'
        }
      }
    ]
  }
}

// ----------------------------- NAT Gateway (mailroom) ------------------------
resource natPip 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'pip-nat-az104-project05'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

resource nat 'Microsoft.Network/natGateways@2024-05-01' = {
  name: 'nat-az104-project05'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    idleTimeoutInMinutes: 4
    publicIpAddresses: [
      { id: natPip.id }
    ]
  }
}

// ----------------------------- VNet ------------------------------------------
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.10.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'snet-web'
        properties: {
          addressPrefix: webPrefix
          networkSecurityGroup: { id: nsgWeb.id }
          natGateway: { id: nat.id }
          defaultOutboundAccess: false
        }
      }
      {
        name: 'snet-app'
        properties: {
          addressPrefix: appPrefix
          networkSecurityGroup: { id: nsgApp.id }
          defaultOutboundAccess: false
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: bastionPrefix
        }
      }
    ]
  }
}

// ----------------------------- VM definitions --------------------------------
var vms = [
  {
    name: 'vm-web1'
    subnet: 'snet-web'
    ip: '10.10.1.4'
    asgs: [
      { id: asgWeb.id }
    ]
    nicNsg: nsgVmWeb1.id
    dataDiskGB: 4
    customData: ''
  }
  {
    name: 'vm-web2'
    subnet: 'snet-web'
    ip: '10.10.1.5'
    asgs: []
    nicNsg: ''
    dataDiskGB: 0
    customData: ''
  }
  {
    name: 'vm-app'
    subnet: 'snet-app'
    ip: '10.10.2.4'
    asgs: [
      { id: asgApp.id }
    ]
    nicNsg: ''
    dataDiskGB: 0
    customData: loadFileAsBase64('scripts/cloud-init-app.yaml')
  }
]

resource nics 'Microsoft.Network/networkInterfaces@2024-05-01' = [for vm in vms: {
  name: 'nic-${vm.name}'
  location: location
  tags: tags
  properties: {
    networkSecurityGroup: empty(vm.nicNsg) ? null : { id: vm.nicNsg }
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, vm.subnet)
          }
          privateIPAllocationMethod: 'Static'
          privateIPAddress: vm.ip
          applicationSecurityGroups: vm.asgs
        }
      }
    ]
  }
}]

resource virtualMachines 'Microsoft.Compute/virtualMachines@2024-07-01' = [for (vm, i) in vms: {
  name: vm.name
  location: location
  tags: tags
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        deleteOption: 'Delete'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
      dataDisks: vm.dataDiskGB > 0 ? [
        {
          lun: 0
          name: '${vm.name}-datadisk'
          createOption: 'Empty'
          diskSizeGB: vm.dataDiskGB
          deleteOption: 'Delete'
          managedDisk: {
            storageAccountType: 'Standard_LRS'
          }
        }
      ] : []
    }
    osProfile: {
      computerName: vm.name
      adminUsername: adminUsername
      customData: empty(vm.customData) ? null : vm.customData
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: adminPublicKey
            }
          ]
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nics[i].id
          properties: {
            deleteOption: 'Delete'
          }
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true // managed storage account – powers the serial console
      }
    }
  }
}]

// ----------------------------- Auto-shutdown ---------------------------------
resource shutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = [for (vm, i) in vms: {
  name: 'shutdown-computevm-${vm.name}'
  location: location
  tags: tags
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: shutdownTime
    }
    timeZoneId: timeZoneId
    targetResourceId: virtualMachines[i].id
  }
}]

// ----------------------------- Custom Script Extension on vm-web1 ------------
resource cse 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = {
  parent: virtualMachines[0]
  name: 'CustomScript'
  location: location
  tags: tags
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    protectedSettings: {
      script: loadFileAsBase64('scripts/configure-web.sh')
    }
  }
}

output natPublicIp string = natPip.properties.ipAddress
output vmNames array = [for vm in vms: vm.name]
