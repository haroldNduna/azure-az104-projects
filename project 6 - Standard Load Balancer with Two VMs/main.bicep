// =============================================================================
// Project 06 - Standard Load Balancer with Two VMs (Bicep)
//
// Deploys the FINISHED design into an existing resource group in East US 2:
//   az group create --name rg-az104-project06 --location eastus2
//   az deployment group create --resource-group rg-az104-project06 \
//     --template-file main.bicep --parameters parameters.json \
//     --parameters adminPublicKey="$(cat ~/.ssh/id_rsa.pub)"
//
// Unlike deploy.sh, the NSG already includes Allow-HTTP-Internet (port 80),
// because a template describes the final state. cloud-init is embedded with
// loadFileAsBase64(), so no extra files are needed at deploy time.
// =============================================================================

@description('Azure region.')
param location string = resourceGroup().location

@description('VM size. D2als_v6 was the only small size allowed in zones for this subscription.')
param vmSize string = 'Standard_D2als_v6'

@description('Availability zones for vm-lb1 and vm-lb2 (must be different).')
param vmZones array = [
  '1'
  '3'
]

@description('Admin username.')
param adminUsername string = 'azureuser'

@description('SSH public key (contents of ~/.ssh/id_rsa.pub).')
@secure()
param adminPublicKey string

@description('Daily auto-shutdown time (24h).')
param shutdownTime string = '1900'

@description('Time zone for auto-shutdown.')
param timeZoneId string = 'Central European Standard Time'

@description('Tags applied to every resource.')
param tags object = {
  Environment: 'Lab'
  CostCenter: 'IT-Services'
  Owner: 'Harold Nduna'
  Project: 'AZ104-Project06'
}

var lbName = 'lb-az104-project06'
var feName = 'fe-web'
var poolName = 'bepool-web'
var probeName = 'probe-http'
var webPrefix = '10.10.1.0/24'
var bastionPrefix = '10.10.254.0/26'
var feId = resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', lbName, feName)
var poolId = resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lbName, poolName)
var probeId = resourceId('Microsoft.Network/loadBalancers/probes', lbName, probeName)

// ----------------------------- NSG -------------------------------------------
resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-web'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTP-Internet'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: webPrefix
          destinationPortRange: '80'
          description: 'Standard LB is secure by default - this rule lets web traffic in'
        }
      }
      {
        name: 'Allow-Mgmt-Bastion'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: bastionPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: webPrefix
          destinationPortRanges: [
            '22'
            '3389'
          ]
        }
      }
      {
        name: 'Deny-VNet-Inbound'
        properties: {
          priority: 4000
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// ----------------------------- VNet ------------------------------------------
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-az104-project06'
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
          networkSecurityGroup: { id: nsg.id }
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

// ----------------------------- Public IP (zone-redundant) --------------------
resource pip 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'pip-lb-az104-project06'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  zones: [
    '1'
    '2'
    '3'
  ]
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

// ----------------------------- Standard load balancer ------------------------
resource lb 'Microsoft.Network/loadBalancers@2024-05-01' = {
  name: lbName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: feName
        properties: {
          publicIPAddress: { id: pip.id }
        }
      }
    ]
    backendAddressPools: [
      {
        name: poolName
      }
    ]
    probes: [
      {
        name: probeName
        properties: {
          protocol: 'Http'
          port: 80
          requestPath: '/'
          intervalInSeconds: 5
          probeThreshold: 1
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'rule-http'
        properties: {
          frontendIPConfiguration: { id: feId }
          backendAddressPool: { id: poolId }
          probe: { id: probeId }
          protocol: 'Tcp'
          frontendPort: 80
          backendPort: 80
          idleTimeoutInMinutes: 4
          enableTcpReset: true
          disableOutboundSnat: true // outbound comes from the outbound rule
          loadDistribution: 'Default' // 5-tuple hash
        }
      }
    ]
    outboundRules: [
      {
        name: 'rule-outbound'
        properties: {
          frontendIPConfigurations: [
            { id: feId }
          ]
          backendAddressPool: { id: poolId }
          protocol: 'All'
          idleTimeoutInMinutes: 4
          enableTcpReset: true
          allocatedOutboundPorts: 10000
        }
      }
    ]
  }
}

// ----------------------------- NICs + VMs ------------------------------------
var vms = [
  {
    name: 'vm-lb1'
    ip: '10.10.1.4'
    zone: vmZones[0]
  }
  {
    name: 'vm-lb2'
    ip: '10.10.1.5'
    zone: vmZones[1]
  }
]

resource nics 'Microsoft.Network/networkInterfaces@2024-05-01' = [for vm in vms: {
  name: 'nic-${vm.name}'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'snet-web')
          }
          privateIPAllocationMethod: 'Static'
          privateIPAddress: vm.ip
          loadBalancerBackendAddressPools: [
            { id: lb.properties.backendAddressPools[0].id }
          ]
        }
      }
    ]
  }
}]

resource virtualMachines 'Microsoft.Compute/virtualMachines@2024-07-01' = [for (vm, i) in vms: {
  name: vm.name
  location: location
  tags: tags
  zones: [
    vm.zone
  ]
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
      diskControllerType: 'NVMe'
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
    }
    osProfile: {
      computerName: vm.name
      adminUsername: adminUsername
      customData: loadFileAsBase64('scripts/cloud-init-web.yaml')
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
        enabled: true
      }
    }
  }
}]

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

output websiteUrl string = 'http://${pip.properties.ipAddress}'
