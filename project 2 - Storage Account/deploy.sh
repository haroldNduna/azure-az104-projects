
---

## 📄 FILE 2: deploy.sh (Azure CLI Bash Script)

```bash
#!/bin/bash
# ==============================================
# Project 02 - Azure Storage Account
# Security+ Aligned: Data Security & Access Control
# ==============================================

# Set variables
RESOURCE_GROUP="rg-az104-project02"
LOCATION="eastus"
STORAGE_ACCOUNT_NAME="staz104proj02"

# Display start message
echo "=================================================="
echo "🚀 Starting Project 02 - Azure Storage Account"
echo "   Security+ Data Security & Access Control"
echo "=================================================="

# Step 1: Login
echo "🔐 Logging into Azure..."
az login

# Step 2: Create Resource Group
echo "📦 Creating Resource Group: $RESOURCE_GROUP"
az group create --name $RESOURCE_GROUP --location $LOCATION

# Step 3: Deploy with Bicep
echo "📁 Deploying Storage Account with Bicep..."
az deployment group create \
  --resource-group $RESOURCE_GROUP \
  --template-file main.bicep \
  --parameters parameters.json

# Step 4: Get Storage Account Key
echo "🔑 Getting Storage Account Key..."
STORAGE_KEY=$(az storage account keys list \
  --account-name $STORAGE_ACCOUNT_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "[0].value" \
  --output tsv)

# Step 5: Create Blob Container
echo "📤 Creating Blob Container: project-documents"
az storage container create \
  --name project-documents \
  --account-name $STORAGE_ACCOUNT_NAME \
  --account-key $STORAGE_KEY \
  --public-access off

# Step 6: Create File Share
echo "📂 Creating File Share: project-files"
az storage share create \
  --name project-files \
  --account-name $STORAGE_ACCOUNT_NAME \
  --account-key $STORAGE_KEY \
  --quota 5

# Step 7: Upload a sample file to Blob
echo "📄 Uploading sample file to Blob container..."
echo "This is a sample document for the Azure Storage project." > sample-doc.txt
az storage blob upload \
  --account-name $STORAGE_ACCOUNT_NAME \
  --account-key $STORAGE_KEY \
  --container-name project-documents \
  --name sample-doc.txt \
  --file sample-doc.txt

# Step 8: Generate SAS token
echo "🔐 Generating SAS token (valid for 1 hour)..."
SAS_TOKEN=$(az storage container generate-sas \
  --account-name $STORAGE_ACCOUNT_NAME \
  --name project-documents \
  --account-key $STORAGE_KEY \
  --permissions r \
  --expiry $(date -u -d "1 hour" '+%Y-%m-%dT%H:%M:%SZ') \
  --output tsv)

echo "=================================================="
echo "✅ Deployment Complete!"
echo "   Resource Group: $RESOURCE_GROUP"
echo "   Storage Account: $STORAGE_ACCOUNT_NAME"
echo "   Blob Container: project-documents"
echo "   File Share: project-files"
echo "=================================================="
echo "📸 Take Screenshots Now:"
echo "   1. Storage Account in Portal (01-storage-account-created.png)"
echo "   2. Blob Container (02-blob-container-created.png)"
echo "   3. File Share (03-file-share-created.png)"
echo "   4. Encryption settings (04-encryption-settings.png)"
echo "   5. Network settings (05-network-access-controls.png)"
echo "   6. SAS token (06-sas-token-generated.png)"
echo "=================================================="
echo "🧹 Cleanup: az group delete --name $RESOURCE_GROUP --yes --no-wait"