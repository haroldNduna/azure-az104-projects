# Project 04 – Network Security Groups (NSGs) (Security+ Aligned)

## Overview

This project turns a three-tier Azure network into a **properly segmented** one. Subnets on their own do not isolate anything: by default every subnet in a VNet can reach every other. Here, each tier gets its own **Network Security Group (NSG)** so that traffic can only flow along the intended path:

```
Internet ──443──▶ WEB ──8080──▶ APP ──1433──▶ DATA ──443──▶ Azure Storage only
                   ▲             ▲              ▲
                   └──── SSH/RDP only from the Bastion (jump-box) subnet ────┘
```

Everything else is denied, including lateral movement between tiers and internet access from the data tier. The rules are then **proven with live traffic** from three test VMs and with **Network Watcher IP flow verify**.

As a security-conscious cloud professional with an on-premises systems administration background, I've aligned this project with CompTIA Security+ (SY0-701) concepts and mapped each Azure feature to its on-premises equivalent.

## Project Objectives

- Create one NSG per tier with least-privilege inbound rules
- Override the hidden default rule **AllowVnetInBound** to stop lateral movement between tiers
- Add **egress filtering** on the data tier (allow Azure Storage, deny the internet)
- Restrict management access (SSH/RDP) to the Bastion subnet only
- Associate the NSGs with their subnets
- Prove the rules with real connection tests and **IP flow verify**
- Deploy the same configuration with Azure CLI, PowerShell, Bicep and ARM, and build it by hand in the portal

## On-Premises Equivalents

| Azure | On-premises equivalent |
|---|---|
| Network Security Group (NSG) | ACL on a router / Layer 3 switch, or a stateful firewall rule set (e.g. Cisco ASA) |
| NSG on a subnet | ACL applied to a VLAN interface (SVI) |
| NSG on a NIC | Host firewall (Windows Defender Firewall / iptables), but enforced by the hypervisor so it can't be disabled from inside the VM |
| Rule priority (100–4096, lowest first, first match wins) | ACL sequence numbers, top-down evaluation |
| Default rules (65000+) | The implicit `deny any` at the end of an ACL, plus Azure's implicit allows above it |
| Service tags (`Internet`, `VirtualNetwork`, `Storage`) | Firewall object groups, maintained by Microsoft |
| Application Security Groups | Firewall object groups defined by server role |
| Stateful filtering | Stateful firewall connection table (no return rules needed) |
| IP flow verify | Cisco ASA `packet-tracer` |
| Effective security rules | `show access-list`, merged across every ACL applied to a server |
| `az vm run-command` | Running a script remotely via SCCM / Intune / PsExec |

## Architecture

![Architecture diagram](architecture-diagram.png)

| Component | Name | Address range | On-premises equivalent |
|---|---|---|---|
| Resource Group | `rg-az104-project04` | – | – |
| Virtual Network | `vnet-az104-project04` | `10.10.0.0/16` | Site network |
| Web subnet | `snet-web` + `nsg-web` | `10.10.1.0/24` | DMZ |
| App subnet | `snet-app` + `nsg-app` | `10.10.2.0/24` | Internal application VLAN |
| Data subnet | `snet-data` + `nsg-data` | `10.10.3.0/24` | Database VLAN |
| Management subnet | `AzureBastionSubnet` (no NSG) | `10.10.254.0/26` | Management / jump-box VLAN |
| Test VMs (optional) | `vm-web`, `vm-app`, `vm-data` | `.4` in each tier | Test servers |

All workload subnets are **private** (no default outbound internet access) and the data subnet keeps its **Microsoft.Storage service endpoint** from Project 03.

### Rule Audit

**`nsg-web` (DMZ)**

| Priority | Direction | Name | Source | Destination | Port | Action | Why |
|---|---|---|---|---|---|---|---|
| 100 | In | Allow-HTTPS-Internet | Internet | 10.10.1.0/24 | TCP 443 | Allow | Public website traffic only |
| 110 | In | Allow-Mgmt-Bastion | 10.10.254.0/26 | 10.10.1.0/24 | TCP 22, 3389 | Allow | Admin access via jump box only |
| 4000 | In | Deny-VNet-Inbound | VirtualNetwork | Any | Any | **Deny** | Overrides the default AllowVnetInBound |

**`nsg-app` (application tier)**

| Priority | Direction | Name | Source | Destination | Port | Action | Why |
|---|---|---|---|---|---|---|---|
| 100 | In | Allow-App-From-Web | 10.10.1.0/24 | 10.10.2.0/24 | TCP 8080 | Allow | Only the web tier calls the app |
| 110 | In | Allow-Mgmt-Bastion | 10.10.254.0/26 | 10.10.2.0/24 | TCP 22, 3389 | Allow | Admin access via jump box only |
| 4000 | In | Deny-VNet-Inbound | VirtualNetwork | Any | Any | **Deny** | Blocks lateral movement |

**`nsg-data` (data tier)**

| Priority | Direction | Name | Source | Destination | Port | Action | Why |
|---|---|---|---|---|---|---|---|
| 100 | In | Allow-SQL-From-App | 10.10.2.0/24 | 10.10.3.0/24 | TCP 1433 | Allow | Only the app tier reaches the database |
| 110 | In | Allow-Mgmt-Bastion | 10.10.254.0/26 | 10.10.3.0/24 | TCP 22, 3389 | Allow | Admin access via jump box only |
| 4000 | In | Deny-VNet-Inbound | VirtualNetwork | Any | Any | **Deny** | Blocks lateral movement |
| 100 | Out | Allow-Storage-Out | 10.10.3.0/24 | Storage (tag) | TCP 443 | Allow | Backups/data to Azure Storage |
| 4000 | Out | Deny-Internet-Out | 10.10.3.0/24 | Internet (tag) | Any | **Deny** | Egress filtering – prevents exfiltration |

Every NSG also contains the six built-in default rules (AllowVnetInBound, AllowAzureLoadBalancerInBound, DenyAllInBound, AllowVnetOutBound, AllowInternetOutBound, DenyAllOutBound) at priority 65000+. The custom rules above are evaluated first.

## Security+ Alignment

| Security+ concept | How this project demonstrates it |
|---|---|
| **Network segmentation** | Three tiers, each in its own filtered security zone. A compromised web server can't reach the database directly. |
| **Access control lists** | NSG rules are 5-tuple ACLs (source, source port, destination, destination port, protocol). |
| **Implicit deny** | Azure's DenyAllInBound/DenyAllOutBound, reinforced by an explicit Deny-VNet-Inbound because Azure's defaults allow all internal traffic. |
| **Least privilege** | Each tier accepts exactly one service port from exactly one source subnet. |
| **Lateral movement prevention** | Deny-VNet-Inbound at priority 4000 overrides AllowVnetInBound (65000). |
| **Egress filtering / data exfiltration prevention** | The data tier can only reach Azure Storage; all other outbound internet traffic is denied. |
| **Defense in depth** | Private subnet **and** an outbound NSG deny on the data tier, two independent controls. NIC NSGs and ASGs add a third layer in Project 05. |
| **Secure administration** | SSH/RDP only from the Bastion (jump-box) subnet. No management ports are exposed to the internet. |
| **Stateful firewalling** | NSGs track connections, so return traffic is allowed automatically. |
| **Validation and testing** | Rules are verified with live traffic and IP flow verify, not just assumed to work. |
| **Change management / IaC** | The whole rule set is code (Bicep/ARM) in Git, so every change is reviewable and repeatable. |
| **Asset management** | Every resource is tagged with Environment, CostCenter, Owner and Project. |

## Tools Used

| Tool | Purpose |
|---|---|
| Azure CLI (Bash) | Primary deployment (`deploy.sh`) and testing (`test-nsg.sh`) |
| Azure PowerShell | Alternative deployment (`deploy.ps1`) |
| Bicep / ARM | Infrastructure as Code (`main.bicep`, `azuredeploy.json`) |
| Azure Portal | Manual build (`portal-walkthrough.md`) and verification |
| Network Watcher | IP flow verify, effective security rules |
| draw.io | Architecture diagram |
| Git / GitHub | Version control and portfolio |

## Repository Contents

| File | Description |
|---|---|
| `deploy.sh` | Azure CLI deployment with verification output |
| `test-nsg.sh` | Deploys 3 test VMs and proves the rules with live tests and IP flow verify |
| `deploy.ps1` | Azure PowerShell equivalent |
| `main.bicep` | Bicep template (deploys into an existing resource group) |
| `azuredeploy.json` | ARM template compiled from `main.bicep` |
| `parameters.json` | Parameter file |
| `cleanup.sh` | Safe teardown with typed confirmation |
| `portal-walkthrough.md` | Step-by-step portal build and cleanup |
| `notes-tips-tricks.md` | AZ-104 exam notes for NSGs |
| `test-results.txt` | Saved output from `test-nsg.sh` |
| `architecture-diagram.drawio` / `.png` | Architecture diagram |
| `screenshots/` | Evidence of the deployment |

## Deployment Instructions

### Prerequisites

- Azure subscription (free trial is fine)
- Azure CLI installed, logged in to the correct tenant (`az login --tenant <tenant-id>`)
- Git installed

### Cost

| Part | Cost |
|---|---|
| NSGs, VNet, subnets (`deploy.sh`) | Free |
| 3 × small 1-vCPU test VMs (`test-nsg.sh`) | A few cents per hour – run `cleanup.sh` straight after the screenshots |

### Method 1: Azure CLI (Bash) – Primary

```bash
chmod +x deploy.sh test-nsg.sh cleanup.sh
./deploy.sh
```

Key commands inside the script:

```bash
# Create an NSG (starts with only the 6 default rules)
az network nsg create --resource-group rg-az104-project04 --name nsg-app --location eastus

# Add a rule – equivalent to one line of an extended ACL
az network nsg rule create \
  --resource-group rg-az104-project04 \
  --nsg-name nsg-app \
  --name Allow-App-From-Web \
  --priority 100 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes 10.10.1.0/24 \
  --source-port-ranges '*' \
  --destination-address-prefixes 10.10.2.0/24 \
  --destination-port-ranges 8080

# The key segmentation rule – overrides AllowVnetInBound (65000)
az network nsg rule create \
  --resource-group rg-az104-project04 \
  --nsg-name nsg-app \
  --name Deny-VNet-Inbound \
  --priority 4000 \
  --direction Inbound \
  --access Deny \
  --protocol '*' \
  --source-address-prefixes VirtualNetwork \
  --destination-address-prefixes '*' \
  --destination-port-ranges '*'

# Attach the NSG to a subnet (like applying an ACL to a VLAN interface)
az network vnet subnet create \
  --resource-group rg-az104-project04 \
  --vnet-name vnet-az104-project04 \
  --name snet-app \
  --address-prefixes 10.10.2.0/24 \
  --network-security-group nsg-app \
  --default-outbound-access false

# Attach an NSG to an existing subnet
az network vnet subnet update \
  --resource-group rg-az104-project04 \
  --vnet-name vnet-az104-project04 \
  --name snet-app \
  --network-security-group nsg-app
```

### Method 2: Live test

```bash
./test-nsg.sh
```

The script creates `vm-web`, `vm-app` and `vm-data` (no public IPs, no NIC NSGs), starts test listeners on TCP 8080 (app) and TCP 1433 (data), then prints two result tables:

| Live test (from inside the VMs) | Expected |
|---|---|
| web → app TCP 8080 | OPEN |
| app → data TCP 1433 | OPEN |
| web → data TCP 1433 | TIMEOUT (blocked) |
| data → app TCP 8080 | TIMEOUT (blocked) |
| app → web TCP 443 | TIMEOUT (blocked – `VirtualNetwork` is not `Internet`) |
| data → internet TCP 443 | TIMEOUT (blocked) |

| IP flow verify | Expected | Deciding rule |
|---|---|---|
| internet → web TCP 443 | Allow | Allow-HTTPS-Internet |
| web → app TCP 8080 | Allow | Allow-App-From-Web |
| app → data TCP 1433 | Allow | Allow-SQL-From-App |
| bastion subnet → data TCP 22 | Allow | Allow-Mgmt-Bastion |
| web → data TCP 1433 | Deny | Deny-VNet-Inbound |
| web → app TCP 22 | Deny | Deny-VNet-Inbound |
| data → internet TCP 443 | Deny | Deny-Internet-Out |

VM sizes sometimes run out of capacity in a region (`SkuNotAvailable`). The script handles this automatically: it tries `Standard_B1s`, `Standard_B1ms` and `Standard_B1ls`, each with no zone and then in availability zones 1–3, and uses the first that works. To force a size, run `VM_SIZE=Standard_B1ms ./test-nsg.sh`. Re-running the script reuses any VMs that already exist.

### Method 3: Azure PowerShell

```powershell
./deploy.ps1
```

### Method 4: Bicep

```bash
az group create --name rg-az104-project04 --location eastus \
  --tags Environment=Lab CostCenter=IT-Services "Owner=Harold Nduna" Project=AZ104-Project04

az deployment group what-if --resource-group rg-az104-project04 --template-file main.bicep

az deployment group create \
  --resource-group rg-az104-project04 \
  --template-file main.bicep \
  --parameters parameters.json
```

### Method 5: ARM Template (JSON)

```bash
az deployment group create \
  --resource-group rg-az104-project04 \
  --template-file azuredeploy.json \
  --parameters parameters.json
```

### Method 6: Azure Portal

See [`portal-walkthrough.md`](portal-walkthrough.md).

### Cleanup

```bash
./cleanup.sh
az group exists --name rg-az104-project04   # wait for 'false'
```

## Verification & Screenshots

| # | Screenshot | Where | What must be visible |
|---|---|---|---|
| 1 | `01-cli-deploy-output.png` | Terminal after `./deploy.sh` | The rule tables for all 3 NSGs and the subnet → NSG associations |
| 2 | `02-resource-group.png` | `rg-az104-project04` → Overview | 3 NSGs and the VNet (and the 3 VMs if testing) |
| 3 | `03-nsg-web-inbound.png` | `nsg-web` → Settings → Inbound security rules | Custom rules **and** the default 65000+ rules underneath |
| 4 | `04-nsg-data-outbound.png` | `nsg-data` → Settings → Outbound security rules | Allow-Storage-Out (100), Deny-Internet-Out (4000), then the defaults |
| 5 | `05-subnet-associations.png` | `vnet-az104-project04` → Settings → Subnets | The **Security group** column showing each NSG |
| 6 | `10-activity-log.png` | `rg-az104-project04` → Activity log | "Create or Update Security Rule" events with your name as the initiator |
| 7 | `11-cleanup.png` | Terminal after `./cleanup.sh` and `az group exists` | Confirmation prompt and the final `false` |

Blur your subscription ID, tenant ID and email address before committing screenshots.

### Screenshots

![CLI deployment output](screenshots/01-cli-deploy-output.png)
![Resource group](screenshots/02-resource-group.png)
![nsg-web inbound rules](screenshots/03-nsg-web-inbound.png)
![nsg-data outbound rules](screenshots/04-nsg-data-outbound.png)
![Subnet associations](screenshots/05-subnet-associations.png)
![Test results](screenshots/06-test-results.png)
![Effective security rules](screenshots/07-effective-security-rules.png)
![IP flow verify – deny](screenshots/08-ip-flow-verify-deny.png)
![IP flow verify – allow](screenshots/09-ip-flow-verify-allow.png)
![Activity log](screenshots/10-activity-log.png)
![Cleanup](screenshots/11-cleanup.png)

## Key Takeaways

1. **Subnets don't isolate; NSGs do.** Without NSGs, every subnet in a VNet can talk to every other.
2. **Azure's defaults allow all internal traffic.** AllowVnetInBound (65000) means allow rules alone don't segment anything. You need an explicit deny such as Deny-VNet-Inbound at a lower priority number.
3. **Priority 100–4096, lowest number first, first match wins**, exactly like ACL sequence numbers.
4. **NSGs are stateful.** Allowing inbound 443 automatically allows the reply.
5. **Service tags beat IP lists.** `Internet`, `VirtualNetwork` and `Storage` are maintained by Microsoft.
6. **`VirtualNetwork` is not `Internet`.** A rule allowing 443 from `Internet` does not allow 443 from another subnet.
7. **A dropped packet times out; a closed port is refused.** NSGs drop silently, which is how the test script tells "blocked" from "nothing listening".
8. **IP flow verify only evaluates NSG rules.** An allowed flow can still fail if, for example, the VM has no public IP.
9. **`az vm create` adds a NIC-level NSG by default** (allowing SSH from anywhere). `--nsg ""` prevents it.
10. **Defense in depth works:** the data tier's internet access is blocked by both the private subnet and the NSG.

## Test Yourself

1. Without the Deny-VNet-Inbound rule, could `vm-web` reach `vm-data` on 1433? Why?
2. A rule at priority 300 allows TCP 22 from anywhere. A rule at priority 200 denies TCP 22 from anywhere. Is SSH allowed?
3. Inbound 443 is allowed to the web tier. Do you need an outbound rule for the replies?
4. A subnet NSG allows TCP 3389 from the internet, but the NIC NSG has no custom rules. Can you RDP to the VM from the internet?
5. Why did `app → web TCP 443` fail when nsg-web allows 443?
6. Which Network Watcher tool tells you *which rule* blocked a flow?
7. Why is there no NSG on `AzureBastionSubnet`?

<details>
<summary>Answers</summary>

1. **Yes.** The default rule AllowVnetInBound (65000) would allow it, because no earlier rule matches web → data 1433.
2. **No.** Priority 200 is processed first and denies it; processing stops there.
3. **No.** NSGs are stateful, so return traffic is allowed automatically.
4. **No.** Inbound traffic must be allowed by both NSGs. The NIC NSG only has its default rules, and DenyAllInBound (65500) blocks internet traffic. (From inside the VNet it *would* work, because the NIC NSG's default AllowVnetInBound allows it.)
5. The rule allows 443 from the **Internet** service tag. Traffic from another subnet is **VirtualNetwork**, so it falls through to Deny-VNet-Inbound.
6. **IP flow verify** (and effective security rules to see the whole merged list).
7. Azure Bastion requires a specific set of mandatory inbound and outbound rules on its subnet NSG. A generic NSG would break Bastion, so it's covered properly in Project 07.
</details>

## Lessons Learned

- Writing allow rules is the easy part; the real work is understanding what the **defaults** already allow.
- Testing rules with real traffic and IP flow verify catches mistakes that reading the rules doesn't.
- Separate "network allowed it" from "a service answered": OPEN, REFUSED and TIMEOUT mean different things.
- **Cloud capacity isn't infinite.** My first test run failed with `SkuNotAvailable`: East US had temporarily run out of `Standard_B1s` capacity. I changed the test script to fall back through other sizes and availability zones automatically, the same resilience thinking as having a second supplier on-premises.

## Next Project

**Project 05 – Virtual Machines, ASGs & Extensions:** deploy a hardened VM, add a NIC-level NSG, replace IP ranges in rules with **Application Security Groups**, and configure it with a VM extension.
