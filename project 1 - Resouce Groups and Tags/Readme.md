# Project 01 – Azure Resource Groups & Tags (Security+ Aligned)

##  Overview

This project demonstrates the foundational Azure skill of creating and managing **Resource Groups** with **tags** to support governance, cost management, and accountability. As a security-conscious cloud professional, I've aligned this project with **CompTIA Security+ (SY0-701)** domains:

| Security+ Domain | How This Project Addresses It |
|------------------|-------------------------------|
| **Domain 5.0 – Governance & Compliance** | Tags enable cost tracking, asset classification, and audit readiness |
| **Domain 3.0 – Access Control (Least Privilege)** | Resource Groups act as logical security boundaries for RBAC |
| **Domain 6.0 – Monitoring & Incident Response** | Tagging supports resource identification during incident investigation |

---

##  Project Objectives

1. Create a Resource Group with Azure CLI
2. Deploy the same Resource Group using Bicep (Infrastructure as Code)
3. Apply tags for:
   - **Environment classification** (Security+ asset classification)
   - **Cost center tracking** (financial accountability)
   - **Owner identification** (responsibility/accountability)
4. Understand how proper resource organization supports security controls

---

##  Security+ Alignment

This project demonstrates my understanding of:

- **Defense-in-Depth**: Resource Groups as logical containers that support layered security controls
- **Least Privilege**: RBAC applied at the Resource Group level ensures users only have necessary permissions
- **Asset Classification**: Tags (e.g., Environment=Lab) classify resources based on criticality
- **Audit Readiness**: Tagging supports tracking and reporting for compliance audits (ISO 27001)
- **Accountability**: Owner tags establish clear responsibility for resources

---

##  Tools Used

| Tool | Purpose |
|------|---------|
| **Azure Portal** | Visual verification and management |
| **Azure CLI** | Command-line deployment |
| **Azure PowerShell** | Alternative deployment |
| **Bicep** | Infrastructure as Code |
| **ARM Templates (JSON)** | Infrastructure as Code |
| **Git** | Version control and portfolio management |

---

##  Architecture Diagram


*Simple architecture showing Resource Group as a logical container with tags applied.*

---

##  Deployment Instructions

### Prerequisites

- Azure subscription
- Azure CLI installed or access to Azure Cloud Shell
- Git installed locally
- GitHub account (for portfolio)

### Method 1: Azure CLI (Bash) – Primary

```bash
# Login to Azure
az login

# Set subscription (optional – if you have multiple)
az account set --subscription "portfolio projects"

# Create Resource Group with tags
az group create \
  --name rg-az104-project01 \
  --location eastus \
  --tags Environment=Lab CostCenter=IT-Services Owner=Harold Nduna

# Verify the Resource Group was created
az group show --name rg-az104-project01

# View all tags on the Resource Group
az group show --name rg-az104-project01 --query tags
