# Project 02 – Azure Storage Account (Blob Containers & File Shares)

##  Overview

This project demonstrates creating and managing an **Azure Storage Account** with:
- **Blob Containers** for unstructured data (images, documents)
- **File Shares** for SMB-based file access
- **Encryption at rest**
- **Secure Transfer Required** (enforces HTTPS)
- **Network access controls** (firewall rules, IP restrictions)

---

##  Tools Used

| Tool | Purpose |
|------|---------|
| **Azure Portal** | Visual verification |
| **Azure CLI** | Primary deployment |
| **Azure PowerShell** | Alternative deployment |
| **Bicep** | Infrastructure as Code |
| **ARM Templates** | Reference IaC |

---

##  Deployment Instructions

### Prerequisites

- Azure subscription
- Azure CLI installed
- Git installed

### Method 1: Azure CLI (Bash) – Primary

```bash
# Login
az login

# Create Resource Group
az group create --name rg-az104-project02 --location eastus

# Create Storage Account
az storage account create \
  --name staz104proj02 \
  --resource-group rg-az104-project02 \
  --location eastus \
  --sku Standard_RAGRS \
  --kind StorageV2 \
  --https-only true \
  --min-tls-version TLS1_2

# Create Blob Container
az storage container create \
  --name project-documents \
  --account-name staz104proj02\
  --public-access off

# Create File Share
az storage share create \
  --name project-files \
  --account-name staz104proj02\
  --quota 5

# Get Connection String (for SAS token)
az storage account show-connection-string \
  --name staz104proj02\
  --resource-group rg-az104-project02 \
  --query connectionString --output tsv