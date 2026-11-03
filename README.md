# Azure AZ-104 Projects – Security+ Aligned

##  Purpose

This repository contains **modular hands-on projects** for the **Microsoft Azure Administrator (AZ-104)** certification exam. Each project is designed to be self-contained, progressively challenging, and aligned with **CompTIA Security+ (SY0-701)** principles to demonstrate security-conscious cloud administration.

---

##  Why This Portfolio Is Different

| Aspect | What It Shows Recruiters |
|--------|--------------------------|
| **Azure Proficiency** | Hands-on experience with core AZ-104 services |
| **Infrastructure as Code** | Bicep and ARM template skills (modern cloud practices) |
| **Security Awareness** | Security+ concepts applied in Azure (least privilege, defense-in-depth, governance) |
| **Version Control** | Professional Git practices with proper documentation |
| **Cost Awareness** | Each project includes a `cleanup.sh` teardown script |
| **Portal + Code** | Each project is built in the Azure Portal first, then automated with CLI, PowerShell and Bicep |

---

##  Project Index

Projects are numbered in the order they are built. From Project 04 onwards they follow the study schedule below, grouped by AZ-104 exam domain.

| # | Project | Difficulty | AZ-104 Domain | Security+ Domains | Status |
|---|---------|------------|---------------|-------------------|--------|
| 01 | [Resource Groups & Tags](./project-01-resource-groups-tags/) | ⭐ | Manage subscriptions & resources | 3.0, 5.0 | ✅ Complete |
| 02 | [Azure Storage Account](./project-02-storage-account/) | ⭐⭐ | Manage storage | 2.0, 4.0, 5.0 | ✅ Complete |
| 03 | [Virtual Network & Subnets](./project-03-virtual-network/) | ⭐⭐ | Manage networking | 2.0 | ✅ Complete |
| 04 | [Network Security Groups](./project-04-nsg/) | ⭐⭐⭐ | Implement and manage virtual networking | 2.0, 3.0 | ✅ Complete |
| 05 | [Virtual Machines, ASGs & Extensions](./project-05-vm-asg-extensions/) | ⭐⭐⭐ | Deploy and manage compute resources | 2.0, 4.0 | ⏳ Planned |
| 06 | [Standard Load Balancer with Two VMs](./project-06-load-balancer/) | ⭐⭐⭐⭐ | Implement and manage virtual networking | 3.0 | ⏳ Planned |
| 07 | [Hub-Spoke Peering, Route Table & Bastion](./project-07-hub-spoke/) | ⭐⭐⭐⭐ | Implement and manage virtual networking | 2.0, 3.0 | ⏳ Planned |
| 08 | [Azure DNS (Private & Public Zones)](./project-08-azure-dns/) | ⭐⭐⭐⭐ | Implement and manage virtual networking | 3.0, 4.0 | ⏳ Planned |
| 09 | [Identity & Governance](./project-09-identity-governance/) | ⭐⭐⭐⭐⭐ | Manage Azure identities and governance | 4.0, 5.0 | ⏳ Planned |
| 10 | [Scale Sets, App Service & Container Apps](./project-10-compute-services/) | ⭐⭐⭐⭐ | Deploy and manage compute resources | 3.0 | ⏳ Planned |
| 11 | [Storage Security](./project-11-storage-security/) | ⭐⭐⭐ | Implement and manage storage | 1.0, 3.0, 4.0 | ⏳ Planned |
| 12 | [VM Backup & Restore](./project-12-backup-restore/) | ⭐⭐⭐⭐ | Monitor and maintain Azure resources | 3.0, 4.0 | ⏳ Planned |
| 13 | [Azure Monitor & Log Analytics](./project-13-monitor/) | ⭐⭐⭐⭐⭐ | Monitor and maintain Azure resources | 4.0 | ⏳ Planned |
| 14 | [Application Gateway with WAF](./project-14-app-gateway-waf/) *(optional)* | ⭐⭐⭐⭐⭐ | Implement and manage virtual networking | 3.0, 4.0 | ⏳ Planned |
| 15 | [Capstone: Secure Web App on Hub-Spoke](./project-15-capstone/) | ⭐⭐⭐⭐⭐ | All domains | 2.0, 3.0, 4.0, 5.0 | ⏳ Planned |

### What Each Project Covers (04 onwards)

| # | Project | Hands-on scope | Key Security+ concepts |
|---|---------|----------------|------------------------|
| 04 | **Network Security Groups** | One NSG per tier (web, app, data); priority-based allow/deny rules; overriding the default `AllowVnetInBound` rule; service tags; outbound deny on the data tier; rules verified with a live test VM, **IP flow verify** and **effective security rules** | Segmentation, ACLs, implicit deny, least privilege, stateful filtering, defense in depth |
| 05 | **Virtual Machines, ASGs & Extensions** | Linux/Windows VM with managed disks and no public IP; **Application Security Groups** in NSG rules; NIC-level vs subnet-level NSGs; **VM extensions** (Custom Script) | Host hardening, secure baselines, encryption at rest, attack surface reduction |
| 06 | **Standard Load Balancer with Two VMs** | Standard SKU public load balancer; backend pool of two small VMs; health probe; load-balancing rule; outbound rule | Availability (CIA triad), redundancy, secure by default (Standard LB is closed until allowed) |
| 07 | **Hub-Spoke Peering, Route Table & Bastion** | Hub VNet and two spoke VNets; hub-spoke peering and why peering is **not transitive**; **route table (UDR)** to steer spoke traffic via the hub; **Azure Bastion** in the hub for VMs in both spokes | Network architecture, segmentation, secure remote access, no exposed RDP/SSH |
| 08 | **Azure DNS (Private & Public Zones)** | Private DNS zone linked to the hub and spokes with **auto-registration**; public zone records (A, CNAME, TXT) | Name resolution integrity, internal vs external zones, DNS as a security control |
| 09 | **Identity & Governance** | Entra ID users and groups (assigned and dynamic); **custom RBAC role**; **management groups**; **Azure Policy** (deny and audit); **resource locks**; **budget** with alerts | Identity and access management, least privilege, governance, policy enforcement, cost control |
| 10 | **Scale Sets, App Service & Container Apps** | **VM Scale Set with autoscale** rules; Bicep deployment; **App Service with a deployment slot** and slot swap; **Container App** | Availability and elasticity, change management (staging slots), secure deployment |
| 11 | **Storage Security** | **Lifecycle management** rules (Hot → Cool → Archive); **user delegation SAS**; Azure Files; **private endpoint** with private DNS | Data protection, encryption in transit, least-privilege access tokens, data lifecycle |
| 12 | **VM Backup & Restore** | Recovery Services vault; backup policy; on-demand backup; **file-level and full VM restore**; soft delete; Site Recovery concepts | Availability, RPO/RTO, business continuity, ransomware resilience |
| 13 | **Azure Monitor & Log Analytics** | Log Analytics workspace; **diagnostic settings**; metric and log **alerts** with action groups; **saved KQL queries**; Activity Log auditing; IP flow verify | Monitoring, auditing, log aggregation, incident detection and response |
| 14 | **Application Gateway with WAF** *(optional)* | Layer 7 load balancing; path-based routing; **Web Application Firewall** in prevention mode. Kept short because App Gateway is expensive on a free trial. | Web application security, OWASP protection, defense in depth |
| 15 | **Capstone: Secure Web App on Hub-Spoke** | End-to-end build: a web app behind a load balancer on the hub-spoke network, with NSGs/ASGs, Bastion, private DNS, monitoring and backup. README with diagram and design choices. | All of the above, combined in one secure architecture |


---

##  Security+ (SY0-701) Domain Reference

| Domain | Name |
|--------|------|
| 1.0 | General Security Concepts |
| 2.0 | Threats, Vulnerabilities, and Mitigations |
| 3.0 | Security Architecture |
| 4.0 | Security Operations |
| 5.0 | Security Program Management and Oversight |

---

##  Project Folder Structure

Every project folder follows the same layout:

| File | Purpose |
|------|---------|
| `README.md` | Overview, architecture, Security+ alignment, deployment steps, screenshots, key takeaways |
| `deploy.sh` | Azure CLI (Bash) deployment – primary method |
| `deploy.ps1` | Azure PowerShell deployment – reference |
| `main.bicep` | Bicep template |
| `azuredeploy.json` | ARM template (compiled from Bicep) |
| `parameters.json` | Deployment parameters |
| `cleanup.sh` | Teardown script with typed confirmation |
| `notes-tips-tricks.md` | AZ-104 exam notes and traps |
| `portal-walkthrough.md` | Step-by-step Azure Portal build (from Project 04 onwards) |
| `architecture-diagram.png` | Architecture diagram |
| `screenshots/` | Portal and terminal evidence |

---

##  Technologies Used

| Technology | Purpose |
|------------|---------|
| **Azure Portal** | Visual management and verification |
| **Azure CLI (Bash)** | Primary deployment method (exam-relevant) |
| **Azure PowerShell** | Alternative deployment method  |
| **Bicep** | Primary Infrastructure as Code |
| **ARM Templates (JSON)** | Reference Infrastructure as Code |
| **Git / GitHub** | Version control and portfolio hosting |
| **Draw.io** | Architecture diagram creation |

---

##  Getting Started

### Prerequisites

- Azure subscription
- Azure CLI installed
- Git installed locally
- GitHub account

### Cost Management

Every project ends with a `cleanup.sh` script that deletes its resource group. Run it as soon as you have taken your screenshots. Removing unused resources avoids charges and reduces the attack surface: no orphaned, unmonitored resources are left behind.
