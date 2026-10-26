// =============================================================================
// Project 03 – Virtual Network (VNet) with Subnets  (Bicep)
// Deploys into an EXISTING resource group:
//   az group create --name rg-az104-project03 --location eastus
//   az deployment group create --resource-group rg-az104-project03 --template-file main.bicep
// =============================================================================

@description('Azure region for all resources. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Name of the virtual network.')
param vnetName string = 'vnet-az104-project03'

@description('VNet address space. Must not overlap with any network you plan to peer with.')
param vnetAddressPrefix string = '10.10.0.0/16'

@description('Tags applied to every resource (asset classification and accountability).')
param tags object = {
  Environment: 'Lab'
  CostCenter: 'IT-Services'
  Owner: 'Harold Nduna'
  Project: 'AZ104-Project03'
}

// Each entry becomes one subnet. Workload subnets are private (no implicit internet egress).
var subnets = [
  {
    name: 'snet-web'
    prefix: '10.10.1.0/24'
    serviceEndpoints: []
    private: true
  }
  {
    name: 'snet-app'
    prefix: '10.10.2.0/24'
    serviceEndpoints: []
    private: true
  }
  {
    name: 'snet-data'
    prefix: '10.10.3.0/24'
    serviceEndpoints: [
      {
        service: 'Microsoft.Storage'
      }
    ]
    private: true
  }
  {
    name: 'AzureBastionSubnet' // exact name required by Azure Bastion, minimum /26
    prefix: '10.10.254.0/26'
    serviceEndpoints: []
    private: false
  }
]

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [for s in subnets: {
      name: s.name
      properties: {
        addressPrefix: s.prefix
        serviceEndpoints: s.serviceEndpoints
        defaultOutboundAccess: s.private ? false : null
      }
    }]
  }
}

output vnetId string = vnet.id
output subnetNames array = [for s in subnets: s.name]
