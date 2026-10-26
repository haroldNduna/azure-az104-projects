# Project 03 – Azure Virtual Network (VNet) with Subnets (Security+ Aligned)

## Overview

This project builds a segmented Azure Virtual Network using a classic **three-tier design** (web, app, data) plus a reserved subnet for Azure Bastion. It is the network foundation that later projects build on: NSGs (Project 04), Virtual Machines (Project 05), the Load Balancer (Project 06) and VNet Peering (Project 07).

The design follows a **secure-by-default** approach: every workload subnet is a *private subnet*, so nothing placed in it can reach the internet unless an explicit, auditable outbound path is added later.

As a security-conscious cloud professional, I've aligned this project with CompTIA Security+ (SY0-701) concepts.

## Project Objectives

- Create a VNet with a planned, non-overlapping address space (`10.10.0.0/16`)
- Segment the network into purpose-built subnets (web, app, data)
- Disable implicit default outbound internet access on workload subnets
- Add a **service endpoint** for Azure Storage on the data subnet (connects to Project 02)
- Reserve `AzureBastionSubnet` for secure, public-IP-free admin access in later projects
- Deploy the same network four ways: Azure CLI, PowerShell, Bicep and ARM JSON

## Architecture

![Architecture diagram](architecture-diagram.png)

| Component | Name | Address range | Purpose |
|---|---|---|---|
| Resource Group | `rg-az104-project03` | – | Logical container, East US |
| Virtual Network | `vnet-az104-project03` | `10.10.0.0/16` | 65,536 addresses for future growth |
| Subnet (web tier) | `snet-web` | `10.10.1.0/24` | Internet-facing workloads (later behind a load balancer) |
| Subnet (app tier) | `snet-app` | `10.10.2.0/24` | Business logic, no direct internet exposure |
| Subnet (data tier) | `snet-data` | `10.10.3.0/24` | Databases/storage access, `Microsoft.Storage` service endpoint |
| Subnet (management) | `AzureBastionSubnet` | `10.10.254.0/26` | Reserved for Azure Bastion (name and /26 minimum are mandatory) |

**Address planning:** each `/24` gives 256 addresses, of which **251 are usable** because Azure reserves 5 per subnet. The `/16` leaves plenty of room for new subnets without re-addressing. The range was chosen so it will not overlap with the second VNet in Project 07 (overlapping ranges cannot be peered).

## Security+ Alignment

| Security+ concept | How this project demonstrates it |
|---|---|
| **Network segmentation** | Separate web, app and data subnets create distinct security zones. A compromise in the web tier does not automatically give access to the data tier. |
| **Defense in depth** | Subnets are the first network layer. Project 04 adds NSGs on top, and later projects add load balancers, WAF and monitoring, each a separate control layer. |
| **Secure by default / secure baseline** | Workload subnets are private (`defaultOutboundAccess = false`). Outbound internet access must be added deliberately, never assumed. |
| **Least privilege (network)** | Resources only get the connectivity they need. The data tier has a private route to Azure Storage via a service endpoint instead of general internet access. |
| **Attack surface reduction** | `AzureBastionSubnet` is reserved so admins can later reach VMs over the Azure backbone without exposing RDP/SSH ports or public IPs. |
| **Data exfiltration prevention** | Without implicit outbound access, a compromised VM cannot quietly send data to the internet. All egress must flow through an explicit, monitorable path. |
| **Confidentiality (CIA triad)** | Service endpoint traffic to Storage stays on the Microsoft backbone and can be locked to this subnet with storage firewall rules. |
| **Availability (CIA triad)** | A generous address space and planned subnet sizes avoid the outage-prone work of re-addressing a live network. |
| **Asset management & accountability** | Tags (`Environment`, `CostCenter`, `Owner`, `Project`) classify every resource and identify who is responsible for it. |
| **Infrastructure as Code / change management** | Bicep and ARM templates make the network repeatable, reviewable in Git and auditable, which reduces configuration drift and human error. |

## Tools Used

| Tool | Purpose |
|---|---|
| Azure CLI (Bash) | Primary deployment (`deploy.sh`) |
| Azure PowerShell | Alternative deployment (`deploy.ps1`) |
| Bicep | Infrastructure as Code (`main.bicep`) |
| ARM Templates (JSON) | Reference IaC (`azuredeploy.json` + `parameters.json`) |
| Azure Portal | Visual verification |
| draw.io (diagrams.net) | Architecture diagram |
| Git / GitHub | Version control and portfolio |

## Repository Contents

| File | Description |
|---|---|
| `deploy.sh` | Azure CLI deployment with built-in verification output |
| `deploy.ps1` | Azure PowerShell equivalent |
| `main.bicep` | Bicep template (deploys into an existing resource group) |
| `azuredeploy.json` | ARM template compiled from `main.bicep` |
| `parameters.json` | Parameter file for the ARM/Bicep deployment |
| `cleanup.sh` | Safe teardown script with typed confirmation |
| `notes-tips-tricks.md` | AZ-104 exam notes for virtual networking |
| `architecture-diagram.drawio` / `.png` | Architecture diagram |
| `screenshots/` | Portal evidence of the deployment |

## Deployment Instructions

### Prerequisites

- Azure subscription (free trial is fine – **VNets and subnets cost nothing**)
- Azure CLI installed (or Azure Cloud Shell)
- Git installed
- GitHub account

### Method 1: Azure CLI (Bash) – Primary

```bash
chmod +x deploy.sh cleanup.sh
./deploy.sh
```

Key commands inside the script:

```bash
# Create the Resource Group with tags
az group create \
  --name rg-az104-project03 \
  --location eastus \
  --tags Environment=Lab CostCenter=IT-Services "Owner=Harold Nduna" Project=AZ104-Project03

# Create the VNet (address space only)
az network vnet create \
  --resource-group rg-az104-project03 \
  --name vnet-az104-project03 \
  --address-prefixes 10.10.0.0/16

# Create a private subnet (repeated for snet-app)
az network vnet subnet create \
  --resource-group rg-az104-project03 \
  --vnet-name vnet-az104-project03 \
  --name snet-web \
  --address-prefixes 10.10.1.0/24 \
  --default-outbound-access false

# Data subnet with a Storage service endpoint
az network vnet subnet create \
  --resource-group rg-az104-project03 \
  --vnet-name vnet-az104-project03 \
  --name snet-data \
  --address-prefixes 10.10.3.0/24 \
  --service-endpoints Microsoft.Storage \
  --default-outbound-access false

# Reserved subnet for Azure Bastion (exact name, minimum /26)
az network vnet subnet create \
  --resource-group rg-az104-project03 \
  --vnet-name vnet-az104-project03 \
  --name AzureBastionSubnet \
  --address-prefixes 10.10.254.0/26

# Verify
az network vnet subnet list \
  --resource-group rg-az104-project03 \
  --vnet-name vnet-az104-project03 \
  --output table
```

### Method 2: Azure PowerShell – Alternative

```powershell
./deploy.ps1
```

### Method 3: Bicep – Infrastructure as Code

```bash
az group create --name rg-az104-project03 --location eastus \
  --tags Environment=Lab CostCenter=IT-Services "Owner=Harold Nduna" Project=AZ104-Project03

# Preview the changes first (like a dry run)
az deployment group what-if \
  --resource-group rg-az104-project03 \
  --template-file main.bicep

# Deploy
az deployment group create \
  --resource-group rg-az104-project03 \
  --template-file main.bicep \
  --parameters parameters.json
```

### Method 4: ARM Template (JSON) – Reference

```bash
az deployment group create \
  --resource-group rg-az104-project03 \
  --template-file azuredeploy.json \
  --parameters parameters.json
```

> `azuredeploy.json` is compiled from the Bicep file with `az bicep build --file main.bicep --outfile azuredeploy.json`, so both always describe the same network.

### Cleanup

```bash
./cleanup.sh
```

The script lists what will be deleted and asks you to type the resource group name before deleting anything.

## Verification & Screenshots

| # | Screenshot | Where to find it in the portal | What must be visible |
|---|---|---|---|
| 1 | `01-cli-deploy-output.png` | Your terminal after `./deploy.sh` | The verification tables: VNet `Succeeded`, 4 subnets with prefixes, `PrivateSubnet = True`, the Storage service endpoint |
| 2 | `02-resource-group-overview.png` | Resource groups → `rg-az104-project03` → Overview | The VNet listed as a resource, location East US |
| 3 | `03-resource-group-tags.png` | `rg-az104-project03` → Tags | All four tags, with `Owner = Harold Nduna` as **one** value |
| 4 | `04-vnet-overview.png` | `vnet-az104-project03` → Overview | Address space `10.10.0.0/16`, location, resource group |
| 5 | `05-vnet-subnets.png` | `vnet-az104-project03` → Settings → Subnets | All 4 subnets with their IPv4 ranges and **available IPs (251 for each /24)** |
| 6 | `06-subnet-private-setting.png` | Subnets → click `snet-web` | The **Private subnet** box ticked (no default outbound access) |
| 7 | `07-data-subnet-service-endpoint.png` | Subnets → click `snet-data` → Service endpoints | `Microsoft.Storage` listed, status Succeeded |
| 8 | `08-vnet-diagram.png` | `vnet-az104-project03` → Monitoring → Diagram (or Network Watcher → Topology) | Azure's own auto-generated topology view |
| 9 | `09-bicep-whatif.png` | Your terminal after `az deployment group what-if` | The green `+ Create` preview (or `= NoChange` if already deployed) |
| 10 | `10-cleanup.png` | Your terminal after `./cleanup.sh`, then `az group exists` | Confirmation prompt and the final `false` |

Before uploading, **blur or crop** your subscription ID, tenant ID and email address from every screenshot (see `notes-tips-tricks.md`).

### Screenshots

![CLI deployment output](screenshots/01-cli-deploy-output.png)
![Resource group overview](screenshots/02-resource-group-overview.png)
![Resource group tags](screenshots/03-resource-group-tags.png)
![VNet overview](screenshots/04-vnet-overview.png)
![VNet subnets](screenshots/05-vnet-subnets.png)
![Private subnet setting](screenshots/06-subnet-private-setting.png)
![Data subnet service endpoint](screenshots/07-data-subnet-service-endpoint.png)
![VNet diagram](screenshots/08-vnet-diagram.png)
![Bicep what-if](screenshots/09-bicep-whatif.png)
![Cleanup](screenshots/10-cleanup.png)

## Lessons Learned

- **Plan the address space before deploying.** A subnet's range cannot be changed while resources are in it, and overlapping ranges block peering later.
- **Private subnets are now the default direction for Azure.** New VNets created on newer API versions after 31 March 2026 default to private subnets, so explicit outbound connectivity (NAT Gateway, load balancer outbound rules or a public IP) is the modern pattern.
- **Some subnet names are reserved.** `AzureBastionSubnet`, `GatewaySubnet` and `AzureFirewallSubnet` must be named exactly that way.
- **Quote tag values that contain spaces** in Bash (`"Owner=Harold Nduna"`). Otherwise the shell splits them into separate arguments.

## Next Project

**Project 04 – Network Security Groups (NSGs):** apply allow/deny rules to these subnets so each tier only accepts the traffic it needs.
