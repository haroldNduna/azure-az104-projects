// ==============================================
// Project 02 - Azure Storage Account
// Security+ Aligned: Data Security & Access Control
// ==============================================

// Parameters
param storageAccountName string
param location string = 'eastus'
param skuName string = 'Standard_RAGRS'
param kind string = 'StorageV2'
param httpsOnly bool = true
param minTlsVersion string = 'TLS1_2'

// Tags
var tags = {
  Environment: 'Lab'
  CostCenter: 'IT-Services'
  Owner: 'Harold Nduna'
  Project: 'AZ-104-Storage'
}

// Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: skuName
  }
  kind: kind
  tags: tags
  properties: {
    supportsHttpsTrafficOnly: httpsOnly
    minimumTlsVersion: minTlsVersion
    accessTier: 'Hot'
    encryption: {
      services: {
        blob: {
          enabled: true
        }
        file: {
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

// Blob Container
resource blobContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/project-documents'
  properties: {
    publicAccess: 'None'
  }
}

// File Share
resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  name: '${storageAccount.name}/default/project-files'
  properties: {
    shareQuota: 5
  }
}

// Outputs
output storageAccountName string = storageAccount.name
output storageAccountLocation string = storageAccount.location
output storageAccountTier string = storageAccount.properties.accessTier
output blobContainerName string = blobContainer.name
output fileShareName string = fileShare.name
