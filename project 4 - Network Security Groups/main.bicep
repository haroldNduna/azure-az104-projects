// =============================================================================
// Project 04 – Network Security Groups (Bicep)
// Deploys 3 NSGs + a VNet whose subnets reference them, into an EXISTING RG:
//   az group create --name rg-az104-project04 --location eastus
//   az deployment group what-if --resource-group rg-az104-project04 --template-file main.bicep
//   az deployment group create  --resource-group rg-az104-project04 --template-file main.bicep --parameters parameters.json
// =============================================================================

@description('Azure region. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Name of the virtual network.')
param vnetName string = 'vnet-az104-project04'

@description('Tags applied to every resource.')
param tags object = {
  Environment: 'Lab'
  CostCenter: 'IT-Services'
  Owner: 'Harold Nduna'
  Project: 'AZ104-Project04'
}

var webPrefix = '10.10.1.0/24'
var appPrefix = '10.10.2.0/24'
var dataPrefix = '10.10.3.0/24'
var bastionPrefix = '10.10.254.0/26'

// Shared rules, reused by every tier
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
  description: 'Admin access only from the Bastion (jump-box) subnet'
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
  description: 'Overrides default AllowVnetInBound (65000) - blocks lateral movement'
}

// ----------------------------- nsg-web (DMZ) ---------------------------------
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
          description: 'Public HTTPS to the web tier only'
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

// ----------------------------- nsg-app ---------------------------------------
resource nsgApp 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-app'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-App-From-Web'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: webPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: appPrefix
          destinationPortRange: '8080'
          description: 'Only the web tier may call the app tier'
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

// ----------------------------- nsg-data --------------------------------------
resource nsgData 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-data'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-SQL-From-App'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: appPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: dataPrefix
          destinationPortRange: '1433'
          description: 'Only the app tier may reach the database port'
        }
      }
      {
        name: 'Allow-Mgmt-Bastion'
        properties: union(mgmtFromBastion, { destinationAddressPrefix: dataPrefix })
      }
      {
        name: 'Deny-VNet-Inbound'
        properties: denyVnetInbound
      }
      {
        name: 'Allow-Storage-Out'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: dataPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: 'Storage'
          destinationPortRange: '443'
          description: 'Data tier may reach Azure Storage (service tag) over HTTPS'
        }
      }
      {
        name: 'Deny-Internet-Out'
        properties: {
          priority: 4000
          direction: 'Outbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: dataPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRange: '*'
          description: 'Overrides default AllowInternetOutBound - prevents data exfiltration'
        }
      }
    ]
  }
}

// ----------------------------- VNet + subnets --------------------------------
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
        name: 'snet-data'
        properties: {
          addressPrefix: dataPrefix
          networkSecurityGroup: { id: nsgData.id }
          serviceEndpoints: [
            { service: 'Microsoft.Storage' }
          ]
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

output vnetId string = vnet.id
output nsgIds array = [
  nsgWeb.id
  nsgApp.id
  nsgData.id
]
