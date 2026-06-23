// Project 01 - Resource Groups & Tags
// Security+ Aligned: Governance & Accountability

param resourceGroupName string = 'rg-az104-project01'
param location string = 'eastus'
param environment string = 'Lab'
param costCenter string = 'IT-Services'
param owner string = 'Harold Nduna'

var tags = {
  Environment: environment
  CostCenter: costCenter
  Owner: owner
}

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

output rgName string = rg.name
output rgLocation string = rg.location
output rgTags object = rg.tags
