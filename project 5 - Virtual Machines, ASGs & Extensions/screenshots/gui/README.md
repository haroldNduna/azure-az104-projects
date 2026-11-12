# Azure Secure Static Website — Portfolio Project 1 of 3

> **Certification track:** AZ-104 Azure Administrator · CompTIA Security+ SY0-701  
> This project is part of a three-project series built to demonstrate hands-on Azure
> competence and security-first infrastructure thinking ahead of my AZ-104 exam.

---

## What I built

A static website hosted on Azure Blob Storage, deployed entirely through
**Bicep (Infrastructure as Code)** with a security-hardened configuration.
Every design decision maps to a real security principle — not just a checkbox.

**Live endpoint:** `https://ststaticsite4x7z.z13.web.core.windows.net`

---

## Architecture

![Architecture diagram](screenshots/architecture.png)

| Layer | Resource | Purpose |
|---|---|---|
| Governance | Resource group + tags | Logical isolation, cost tracking |
| Storage | Azure Blob Storage (StorageV2, LRS) | Hosts static website files |
| Security | TLS 1.2 minimum enforced | Encrypted transport only |
| Resilience | Blob versioning + soft delete (7 days) | Recovery from accidental deletion |
| Access | Public blob access disabled | Principle of least privilege |
| IaC | Bicep template | Reproducible, auditable deployments |

---

## Security controls and the reasoning behind them

This is the section I care most about. Anyone can click through the Azure portal.
Understanding *why* each control exists is what separates a practitioner from
someone following a tutorial.

### TLS 1.2 minimum (`minimumTlsVersion: 'TLS1_2'`)

TLS 1.0 and 1.1 are vulnerable to protocol downgrade attacks such as POODLE and
BEAST. Enforcing TLS 1.2 as the floor ensures all data in transit is encrypted
using a protocol without known practical exploits. This maps directly to
**Security+ domain 3.2 — secure protocols** and the broader principle of
**defence in depth**: even if network-layer controls fail, the transport layer
remains hardened.

### Public blob access disabled (`allowBlobPublicAccess: false`)

By default, Azure allows storage containers to be made publicly readable. Disabling
this at the account level means no container in this account can ever be accidentally
exposed — even if someone misconfigures a container later. This is **implicit deny**
at the account scope, a **Security+ 3.1 zero-trust** pattern: deny everything,
then explicitly permit only what is needed.

### Blob versioning + soft delete (`isVersioningEnabled: true`, 7-day retention)

Versioning keeps a full history of every object. Soft delete protects against
accidental or malicious deletion for seven days. Together these implement
**non-repudiation** (Security+ 1.2) — changes cannot be silently overwritten —
and act as a compensating control against ransomware, which is a **Security+ 2.4
threat mitigation** pattern. The seven-day window defines an informal
**Recovery Point Objective (RPO)** of one week, a concept central to
**Security+ 3.3 business continuity planning**.

### HTTPS-only traffic (`supportsHttpsTrafficOnly: true`)

Any HTTP request is automatically rejected. Combined with the TLS floor, this
eliminates the possibility of plaintext data transmission — reinforcing
**confidentiality** from the CIA triad (Security+ 1.2).

### Resource tags (`environment=dev`, `project=portfolio`)

Tags enforce **governance** and support cost accountability. In an enterprise
context, Azure Policy can block resource creation without mandatory tags — a
**Security+ 5.4 compliance control**. This project demonstrates that habit
from the start.

### Infrastructure as Code via Bicep

Deploying via a version-controlled Bicep template rather than manual portal
clicks creates an **auditable change trail** (Security+ 5.5 change management).
The template is the single source of truth — if the environment drifts from the
template, that drift is detectable. This prevents **configuration sprawl**, a
common source of security vulnerabilities in cloud environments
(Security+ 4.1 configuration management).

---

## Security+ alignment table

| Security+ objective | Control implemented | Where |
|---|---|---|
| 1.2 — Confidentiality (CIA triad) | HTTPS-only, TLS 1.2 minimum | Storage account properties |
| 1.2 — Non-repudiation | Blob versioning — full object history | Blob service properties |
| 2.4 — Threat mitigation (ransomware) | Soft delete, 7-day retention | Blob service properties |
| 3.1 — Zero trust / implicit deny | Public blob access disabled at account level | Storage account properties |
| 3.2 — Secure protocols | TLS 1.2 floor, HTTP rejected | Storage account properties |
| 3.3 — RPO / business continuity | 7-day soft delete window defines recovery point | Blob service properties |
| 4.1 — Configuration management | Bicep IaC, version-controlled template | bicep/main.bicep |
| 5.4 — Compliance controls | Mandatory tags enforced on all resources | Resource group + Bicep |
| 5.5 — Change management | Git history of every infrastructure change | This repository |

---

## How to deploy

### Prerequisites

- Azure CLI installed and authenticated (`az login`)
- An active Azure subscription
- Git

### Steps

```bash
# 1. Clone the repo
git clone https://github.com/YOUR_USERNAME/azure-staticsite-portfolio
cd azure-staticsite-portfolio

# 2. Create the resource group
az group create \
  --name rg-staticsite-dev-eastus \
  --location eastus \
  --tags environment=dev project=portfolio

# 3. Deploy the Bicep template (storage account + all security controls)
az deployment group create \
  --resource-group rg-staticsite-dev-eastus \
  --template-file bicep/main.bicep \
  --parameters storageAccountName=ststaticsite4x7z

# 4. Enable static website hosting
#    (data-plane operation — not yet available in Bicep resource provider)
az storage blob service-properties update \
  --account-name ststaticsite4x7z \
  --static-website \
  --index-document index.html \
  --404-document 404.html

# 5. Upload the website
az storage blob upload \
  --account-name ststaticsite4x7z \
  --container-name '$web' \
  --file website/index.html \
  --name index.html \
  --content-type text/html \
  --auth-mode login

# 6. Get the public URL
az storage account show \
  --name ststaticsite4x7z \
  --resource-group rg-staticsite-dev-eastus \
  --query "primaryEndpoints.web" \
  --output tsv
```

### Teardown (to avoid costs)

```bash
az group delete --name rg-staticsite-dev-eastus --yes
```

---

## Azure services used

- **Azure Blob Storage** — static website hosting, object storage
- **Azure Resource Groups** — logical resource isolation
- **Azure Resource Tags** — governance and cost attribution
- **Bicep** — Infrastructure as Code deployment

---

## What I learned

Beyond the technical steps, this project reinforced the habit of asking *why*
before *how*. Disabling public blob access is one checkbox in the portal — but
understanding that it implements implicit deny at the account scope (rather than
relying on per-container settings that could be misconfigured) changes how you
think about every future resource you create.

It also surfaced a real limitation worth documenting: static website hosting is
a data-plane operation that Azure's Bicep resource provider does not yet expose,
requiring one CLI command alongside the Bicep deployment. Knowing where IaC
stops and imperative commands begin is a practical skill that matters in real
engineering teams.

---

## Project series

| Project | Focus | Status |
|---|---|---|
| 1 — Azure secure static website | Blob storage, IaC, governance basics | ✅ Complete |
| 2 — VNet, NSG, VM, Bastion | Networking, segmentation, secure access | 🔄 In progress |
| 3 — App Service, Entra ID, RBAC | Identity, least privilege, PaaS deployment | 📋 Planned |
| Final — Secure multi-tier web app | All AZ-104 domains, full Security+ alignment | 📋 Planned |

---

## About me

Currently studying for **AZ-104 Microsoft Azure Administrator** and
**CompTIA Security+**, building these projects to demonstrate practical
cloud infrastructure and security skills to employers.

I approach cloud work with a security-first mindset: governance before
resources, least privilege before functionality, IaC before manual clicks.
