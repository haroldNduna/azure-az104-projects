# Project 05 – Virtual Machines, Application Security Groups & Extensions (Security+ Aligned)

## Overview

Projects 03 and 04 built a segmented network. This project puts **servers** on it and secures them the way a production workload should be secured:

- **No public IPs** – VMs are managed through the Azure control plane (Run command, serial console), not through open ports
- **Application Security Groups (ASGs)** – firewall rules based on a server's **role**, not its IP address or subnet
- **Two layers of NSG** – a subnet NSG plus a NIC-level NSG, both of which must allow traffic
- **NAT Gateway** – controlled, auditable outbound internet for one subnet only
- **Managed data disk** – partitioned, formatted and mounted by a **Custom Script Extension**
- **cloud-init** – first-boot configuration of the app server
- **Trusted Launch**, encryption at rest, boot diagnostics and auto-shutdown on every VM

The key result: two VMs in the **same subnet** get **different access** – only the one wearing the `asg-web` badge can reach the app server.

```
vm-web1 (asg-web)          ──8080──▶ vm-app (asg-app)   ✔ ALLOWED
vm-web2 (no ASG, same subnet) ──8080──▶ vm-app (asg-app)   ✖ BLOCKED
```

## Project Objectives

- Deploy Linux VMs with Trusted Launch, managed disks and no public IPs
- Create ASGs and use them as **source and destination** in NSG rules
- Apply a NIC-level NSG on top of a subnet NSG and prove both are evaluated
- Provide outbound internet to one subnet with a NAT Gateway and prove the other subnet has none
- Attach, partition, format and mount a data disk using a Custom Script Extension
- Configure a VM at first boot with cloud-init (custom data)
- Compare power states: **Stopped** vs **Stopped (deallocated)**
- Build it four ways: Azure Portal, Azure CLI, PowerShell and Bicep/ARM

## How It Works – The Office Building Analogy

| Azure | Office building |
|---|---|
| Virtual machine | A rented office. The landlord (Microsoft) runs the building; the tenant (me) secures the office – the **shared responsibility model** |
| VM size | Office size – CPU and memory |
| Trusted Launch | A tamper-evident seal checked before anyone enters (Secure Boot + vTPM) |
| OS disk / data disk / temp disk | Desk drawer / separate filing cabinet / whiteboard that is wiped when you move offices |
| Encryption at rest | Every filing cabinet is locked automatically |
| No public IP | No street entrance |
| Run command / serial console | Building management's intercom / CCTV |
| Subnet NSG | The guard at the floor entrance |
| NIC NSG | A lock on one office door – both guard and lock must let you in |
| ASG | A staff ID badge – the guard checks the badge, not which floor you came from |
| NAT Gateway | The mailroom – parcels go out with the building's return address; nothing comes in |
| Custom Script Extension | A contractor who fits out the office after move-in |
| cloud-init | The move-in-day checklist – done once, on day one |

## Architecture

![Architecture diagram](architecture-diagram.png)

| Component | Name | Details |
|---|---|---|
| Region | East US 2 | See *Lessons Learned* for why |
| Resource group | `rg-az104-project05` | Tagged: Environment, CostCenter, Owner, Project |
| VNet | `vnet-az104-project05` | 10.10.0.0/16 |
| Web subnet | `snet-web` | 10.10.1.0/24 · private · `nsg-web` · NAT Gateway |
| App subnet | `snet-app` | 10.10.2.0/24 · private · `nsg-app` · no NAT |
| Management subnet | `AzureBastionSubnet` | 10.10.254.0/26 · reserved for Project 07 |
| ASGs | `asg-web`, `asg-app` | Role "badges" attached to NICs |
| NIC NSG | `nsg-vm-web1` | On vm-web1's network interface only |
| NAT Gateway | `nat-az104-project05` | + Standard static public IP `pip-nat-az104-project05` |
| Storage account | `st…p05` | Private `scripts` container holding `configure-web.sh` |
| **vm-web1** | 10.10.1.4 | Ubuntu 24.04 · Standard_D2s_v3 · **asg-web** · NIC NSG · 4 GB data disk · Custom Script Extension |
| **vm-web2** | 10.10.1.5 | Ubuntu 24.04 · Standard_D2s_v3 · **no ASG** |
| **vm-app** | 10.10.2.4 | Ubuntu 24.04 · Standard_D2s_v3 · **asg-app** · cloud-init listener on TCP 8080 |

### Rule Audit

**`nsg-web` (subnet – floor guard)**

| Priority | Name | Source | Destination | Port | Action |
|---|---|---|---|---|---|
| 100 | Allow-HTTPS-Internet | Internet | 10.10.1.0/24 | TCP 443 | Allow |
| 110 | Allow-Mgmt-Bastion | 10.10.254.0/26 | 10.10.1.0/24 | TCP 22, 3389 | Allow |
| 4000 | Deny-VNet-Inbound | VirtualNetwork | Any | Any | **Deny** |

**`nsg-app` (subnet – floor guard that checks badges)**

| Priority | Name | Source | Destination | Port | Action |
|---|---|---|---|---|---|
| 100 | Allow-App-From-ASG-Web | **ASG: asg-web** | **ASG: asg-app** | TCP 8080 | Allow |
| 110 | Allow-Mgmt-Bastion | 10.10.254.0/26 | 10.10.2.0/24 | TCP 22, 3389 | Allow |
| 4000 | Deny-VNet-Inbound | VirtualNetwork | Any | Any | **Deny** |

**`nsg-vm-web1` (NIC – door lock)**

| Priority | Name | Source | Destination | Port | Action |
|---|---|---|---|---|---|
| 100 | Deny-RDP-Host | Any | Any | TCP 3389 | **Deny** |

`nsg-web` allows 22 **and** 3389 from the Bastion subnet; `nsg-vm-web1` blocks 3389 on vm-web1. Net result: only SSH reaches vm-web1.

## Security+ Alignment

| Security+ concept | How this project demonstrates it |
|---|---|
| **Role-based access control (network)** | ASGs grant access by server role. A VM on the right subnet but without the badge is denied. |
| **Least privilege** | One port (8080) from one role (asg-web) to one role (asg-app). |
| **Defense in depth** | Private subnet + subnet NSG + NIC NSG + ASG membership – four independent controls. |
| **Host-based firewall** | The NIC NSG is enforced by the hypervisor, so it can't be disabled from inside the VM. |
| **Attack surface reduction** | No public IPs; no management ports open to the internet; RDP blocked on a Linux host. |
| **Secure baseline / hardening** | Trusted Launch (Secure Boot + vTPM), SSH keys only, password login disabled. |
| **Encryption at rest** | Managed disks encrypted with platform-managed keys by default. |
| **Encryption in transit** | Storage account requires HTTPS and TLS 1.2; the extension downloads its script over HTTPS. |
| **Controlled egress / data exfiltration prevention** | Only snet-web can reach the internet, through one known public IP. snet-app has no outbound path. |
| **Secrets management** | The storage key is passed to the extension in **protected settings** (encrypted). The `scripts` container is private. |
| **Configuration management** | Extensions and cloud-init give repeatable, documented server builds. |
| **Shared responsibility model** | Microsoft secures the hypervisor and hardware; I secure the guest OS, network rules and access. |
| **Audit trail / accountability** | The Activity log records every create, change, deallocate and delete with time stamp and initiator. |
| **Asset management** | Every resource is tagged with Environment, CostCenter, Owner and Project. |

## Tools Used

| Tool | Purpose |
|---|---|
| Azure Portal | Manual build (`portal-walkthrough.md`), tests and screenshots |
| Azure CLI (Bash) | `deploy.sh`, `test-vm.sh`, `cleanup.sh` |
| Azure PowerShell | `deploy.ps1` (reference) |
| Bicep / ARM | `main.bicep`, `azuredeploy.json` |
| Run command | Configuring and testing VMs without SSH |
| Network Watcher | IP flow verify, effective security rules |
| draw.io | Architecture diagram |
| Git / GitHub | Version control and portfolio |

## Repository Contents

| File | Description |
|---|---|
| `portal-walkthrough.md` | Step-by-step portal build, tests and cleanup |
| `deploy.sh` | Azure CLI deployment with verification output |
| `test-vm.sh` | Runs all tests and saves `test-results.txt` |
| `cleanup.sh` | Safe teardown with typed confirmation |
| `deploy.ps1` | Azure PowerShell equivalent |
| `main.bicep` / `azuredeploy.json` | Bicep and compiled ARM template (script and cloud-init embedded) |
| `parameters.json` | Parameters (the SSH public key is passed at deploy time) |
| `scripts/configure-web.sh` | Custom Script Extension: data disk + Nginx |
| `scripts/cloud-init-app.yaml` | cloud-init for vm-app: test listener on TCP 8080 |
| `notes-tips-tricks.md` | AZ-104 exam notes for VMs, disks, ASGs, extensions and NAT Gateway |
| `architecture-diagram.drawio` / `.png` | Architecture diagram |
| `test-results.txt` | Output of `test-vm.sh` |
| `screenshots/` | Portal and CLI evidence |

## Deployment Instructions

### Prerequisites

- Azure subscription, logged in: `az login --tenant <tenant-id>`
- Azure CLI and Git (Ubuntu or Azure Cloud Shell)
- An SSH key pair at `~/.ssh/id_rsa` (`az vm create --generate-ssh-keys` creates one if missing)

### Cost

| Item | Approx. cost |
|---|---|
| 3 × Standard_D2s_v3 | ~$0.10/hour each |
| NAT Gateway + public IP | ~$0.05/hour – charged even when VMs are off |
| Disks, storage, ASGs, NSGs, VNet | Pennies / free |
| **Total while running** | **~$0.35/hour** – run `cleanup.sh` straight after testing |

### Method 1: Azure Portal

See [`portal-walkthrough.md`](portal-walkthrough.md).

### Method 2: Azure CLI (Bash) – Primary

```bash
chmod +x deploy.sh test-vm.sh cleanup.sh scripts/configure-web.sh
./deploy.sh      # ~10-15 minutes
./test-vm.sh     # ~10 minutes, saves test-results.txt
./cleanup.sh
```

Key commands inside `deploy.sh`:

```bash
# ASG – an empty "badge" until a NIC is added to it
az network asg create --resource-group rg-az104-project05 --name asg-web --location eastus2

# NSG rule that uses ASGs instead of IP ranges
az network nsg rule create --resource-group rg-az104-project05 --nsg-name nsg-app \
  --name Allow-App-From-ASG-Web --priority 100 --direction Inbound --access Allow \
  --protocol Tcp --source-asgs asg-web --destination-asgs asg-app --destination-port-ranges 8080

# NAT Gateway on one subnet only
az network nat gateway create --resource-group rg-az104-project05 --name nat-az104-project05 \
  --public-ip-addresses pip-nat-az104-project05 --idle-timeout 4
az network vnet subnet update --resource-group rg-az104-project05 --vnet-name vnet-az104-project05 \
  --name snet-web --nat-gateway nat-az104-project05

# VM: no public IP, NIC NSG, ASG badge, data disk, Trusted Launch
az vm create --resource-group rg-az104-project05 --name vm-web1 --location eastus2 \
  --image Ubuntu2404 --size Standard_D2s_v3 \
  --security-type TrustedLaunch --enable-secure-boot true --enable-vtpm true \
  --vnet-name vnet-az104-project05 --subnet snet-web --private-ip-address 10.10.1.4 \
  --public-ip-address "" --nsg nsg-vm-web1 --asgs asg-web \
  --admin-username azureuser --generate-ssh-keys \
  --data-disk-sizes-gb 4 --storage-sku Standard_LRS

# cloud-init (custom data) – use an ABSOLUTE path
az vm create ... --name vm-app --asgs asg-app --custom-data "$PWD/scripts/cloud-init-app.yaml"

# Custom Script Extension – the storage key goes in PROTECTED settings
az vm extension set --resource-group rg-az104-project05 --vm-name vm-web1 \
  --name CustomScript --publisher Microsoft.Azure.Extensions --version 2.1 \
  --settings '{"fileUris":["https://<storage>.blob.core.windows.net/scripts/configure-web.sh"]}' \
  --protected-settings @protected.json

# Power states
az vm deallocate --resource-group rg-az104-project05 --name vm-web2   # no compute charges
az vm stop       --resource-group rg-az104-project05 --name vm-web2   # still billed!
```

If a VM size is unavailable, `deploy.sh` tries other sizes automatically, or force one with `VM_SIZE=Standard_DS1_v2 ./deploy.sh`.

### Method 3: Bicep / ARM

```bash
az group create --name rg-az104-project05 --location eastus2

az deployment group what-if --resource-group rg-az104-project05 \
  --template-file main.bicep --parameters parameters.json \
  --parameters adminPublicKey="$(cat ~/.ssh/id_rsa.pub)"

az deployment group create --resource-group rg-az104-project05 \
  --template-file main.bicep --parameters parameters.json \
  --parameters adminPublicKey="$(cat ~/.ssh/id_rsa.pub)"
```

The Bicep version embeds `configure-web.sh` and the cloud-init file with `loadFileAsBase64()`, so it needs no storage account. Use `azuredeploy.json` in place of `main.bicep` for the ARM version.

### Method 4: Azure PowerShell

```powershell
./deploy.ps1
```

## Test Results

| # | Test | Expected | Result |
|---|---|---|---|
| 1a | vm-web1 (asg-web) → vm-app:8080 | ALLOWED | ✅ |
| 1b | vm-web2 (no ASG, same subnet) → vm-app:8080 | BLOCKED | ✅ |
| 2 | Data disk mounted at /data; Nginx serving a page from it | Mounted, serving | ✅ |
| 3a | vm-web1 outbound IP | NAT Gateway public IP | ✅ |
| 3b | vm-app outbound | No internet | ✅ |
| 4a | Bastion subnet → vm-web1:22 | Allowed (nsg-web) | ✅ |
| 4b | Bastion subnet → vm-web1:3389 | Denied (nsg-vm-web1) | ✅ |
| 5 | Effective rules on vm-web1 | Subnet NSG + NIC NSG | ✅ |
| 6 | vm-web2 after portal **Stop** | Stopped (deallocated) | ✅ |

## Screenshots

Blur subscription IDs, tenant IDs and email addresses before committing.

### Portal

| File | Shows |
|---|---|
| `00 Resource Group Created.png` | Resource group rg-az104-project05 created in East US 2 with tags |
| `01 Application Security Groups Created.png` | ASGs asg-web and asg-app (the role "badges") |
| `02 NSG Web + Inbound Security Rules.png` | nsg-web inbound rules: HTTPS from Internet, management from Bastion subnet, Deny-VNet-Inbound |
| `03 NSG App + Inbound Security Rules.png` | nsg-app rule 100: **asg-web → asg-app on TCP 8080** |
| `04 NIC NSG vm-web1 + Inbound Security Rules.png` | NIC NSG nsg-vm-web1: Deny-RDP-Host (3389) |
| `05 VNet + Subnets Creation.png` | VNet 10.10.0.0/16 with snet-web, snet-app and AzureBastionSubnet |
| `06 NAT Gateway Created.png` | NAT Gateway and Standard public IP, attached to snet-web only |
| `07 Storage Account Created.png` | Storage account for the extension script (HTTPS only, TLS 1.2, no anonymous access) |
| `08 Container with Scripts File.png` | Private `scripts` container holding configure-web.sh |
| `09 VM App Creation.png` | vm-app created in snet-app (no public IP) |
| `10 VM Web 1 Creation.png` | vm-web1 created in snet-web with NIC NSG and data disk |
| `11 VM Web 2 Creation.png` | vm-web2 created in snet-web (no ASG, no NIC NSG) |
| `12 VM Web 1 Application Security Group.png` | vm-web1 network interface assigned to **asg-web** |
| `13 VM App Application Security Group.png` | vm-app network interface assigned to **asg-app** |
| `14 Custom Script Added To Web Vm 1.png` | Custom Script Extension on vm-web1: provisioning succeeded |
| `15 VM Web 1 ASG Test.png` | ASG test – vm-web1 (asg-web) → vm-app:8080: **ALLOWED** |
| `16 VM Web 2 ASG Test.png` | ASG test – vm-web2 (same subnet, no ASG) → vm-app:8080: **BLOCKED** |
| `17 VM Web 1 Extensions and Disk Test.png` | Data disk mounted at /data, temp disk at /mnt, Nginx serving the page |
| `18 VM Web 1 NAT Gateway Test.png` | vm-web1 reaches the internet via the NAT Gateway's public IP |
| `19 VM App NAT Gateway Test.png` | vm-app (private subnet, no NAT) has no internet access |
| `20 VM Web 1 Security Rules.png` | Effective security rules on vm-web1: subnet NSG + NIC NSG |
| `21 VM Web 1 NSG IP Flow Verify Port 22.png` | IP flow verify: SSH (22) from Bastion subnet **allowed** by nsg-web |
| `22 VM Web 1 NSG IP Flow Verify Port 3389.png` | IP flow verify: RDP (3389) from Bastion subnet **denied** by NIC NSG nsg-vm-web1 |
| `23 Web VM 2 Deallocated.png` | vm-web2 stopped from the portal: **Stopped (deallocated)** |
| `24 Resource Group Clean Up.png` | Resource group deleted – no orphaned resources |

**00 Resource Group Created** – Resource group rg-az104-project05 created in East US 2 with tags

![00 Resource Group Created](screenshots/00%20Resource%20Group%20Created.png)

**01 Application Security Groups Created** – ASGs asg-web and asg-app (the role "badges")

![01 Application Security Groups Created](screenshots/01%20Application%20Security%20Groups%20Created.png)

**02 NSG Web + Inbound Security Rules** – nsg-web inbound rules: HTTPS from Internet, management from Bastion subnet, Deny-VNet-Inbound

![02 NSG Web + Inbound Security Rules](screenshots/02%20NSG%20Web%20%2B%20Inbound%20Security%20Rules.png)

**03 NSG App + Inbound Security Rules** – nsg-app rule 100: **asg-web → asg-app on TCP 8080**

![03 NSG App + Inbound Security Rules](screenshots/03%20NSG%20App%20%2B%20Inbound%20Security%20Rules.png)

**04 NIC NSG vm-web1 + Inbound Security Rules** – NIC NSG nsg-vm-web1: Deny-RDP-Host (3389)

![04 NIC NSG vm-web1 + Inbound Security Rules](screenshots/04%20NIC%20NSG%20vm-web1%20%2B%20Inbound%20Security%20Rules.png)

**05 VNet + Subnets Creation** – VNet 10.10.0.0/16 with snet-web, snet-app and AzureBastionSubnet

![05 VNet + Subnets Creation](screenshots/05%20VNet%20%2B%20Subnets%20Creation.png)

**06 NAT Gateway Created** – NAT Gateway and Standard public IP, attached to snet-web only

![06 NAT Gateway Created](screenshots/06%20NAT%20Gateway%20Created.png)

**07 Storage Account Created** – Storage account for the extension script (HTTPS only, TLS 1.2, no anonymous access)

![07 Storage Account Created](screenshots/07%20Storage%20Account%20Created.png)

**08 Container with Scripts File** – Private `scripts` container holding configure-web.sh

![08 Container with Scripts File](screenshots/08%20Container%20with%20Scripts%20File.png)

**09 VM App Creation** – vm-app created in snet-app (no public IP)

![09 VM App Creation](screenshots/09%20VM%20App%20Creation.png)

**10 VM Web 1 Creation** – vm-web1 created in snet-web with NIC NSG and data disk

![10 VM Web 1 Creation](screenshots/10%20VM%20Web%201%20Creation.png)

**11 VM Web 2 Creation** – vm-web2 created in snet-web (no ASG, no NIC NSG)

![11 VM Web 2 Creation](screenshots/11%20VM%20Web%202%20Creation.png)

**12 VM Web 1 Application Security Group** – vm-web1 network interface assigned to **asg-web**

![12 VM Web 1 Application Security Group](screenshots/12%20VM%20Web%201%20Application%20Security%20Group.png)

**13 VM App Application Security Group** – vm-app network interface assigned to **asg-app**

![13 VM App Application Security Group](screenshots/13%20VM%20App%20Application%20Security%20Group.png)

**14 Custom Script Added To Web Vm 1** – Custom Script Extension on vm-web1: provisioning succeeded

![14 Custom Script Added To Web Vm 1](screenshots/14%20Custom%20Script%20Added%20To%20Web%20Vm%201.png)

**15 VM Web 1 ASG Test** – ASG test – vm-web1 (asg-web) → vm-app:8080: **ALLOWED**

![15 VM Web 1 ASG Test](screenshots/15%20VM%20Web%201%20ASG%20Test.png)

**16 VM Web 2 ASG Test** – ASG test – vm-web2 (same subnet, no ASG) → vm-app:8080: **BLOCKED**

![16 VM Web 2 ASG Test](screenshots/16%20VM%20Web%202%20ASG%20Test.png)

**17 VM Web 1 Extensions and Disk Test** – Data disk mounted at /data, temp disk at /mnt, Nginx serving the page

![17 VM Web 1 Extensions and Disk Test](screenshots/17%20VM%20Web%201%20Extensions%20and%20Disk%20Test.png)

**18 VM Web 1 NAT Gateway Test** – vm-web1 reaches the internet via the NAT Gateway's public IP

![18 VM Web 1 NAT Gateway Test](screenshots/18%20VM%20Web%201%20NAT%20Gateway%20Test.png)

**19 VM App NAT Gateway Test** – vm-app (private subnet, no NAT) has no internet access

![19 VM App NAT Gateway Test](screenshots/19%20VM%20App%20NAT%20Gateway%20Test.png)

**20 VM Web 1 Security Rules** – Effective security rules on vm-web1: subnet NSG + NIC NSG

![20 VM Web 1 Security Rules](screenshots/20%20VM%20Web%201%20Security%20Rules.png)

**21 VM Web 1 NSG IP Flow Verify Port 22** – IP flow verify: SSH (22) from Bastion subnet **allowed** by nsg-web

![21 VM Web 1 NSG IP Flow Verify Port 22](screenshots/21%20VM%20Web%201%20NSG%20IP%20Flow%20Verify%20Port%2022.png)

**22 VM Web 1 NSG IP Flow Verify Port 3389** – IP flow verify: RDP (3389) from Bastion subnet **denied** by NIC NSG nsg-vm-web1

![22 VM Web 1 NSG IP Flow Verify Port 3389](screenshots/22%20VM%20Web%201%20NSG%20IP%20Flow%20Verify%20Port%203389.png)

**23 Web VM 2 Deallocated** – vm-web2 stopped from the portal: **Stopped (deallocated)**

![23 Web VM 2 Deallocated](screenshots/23%20Web%20VM%202%20Deallocated.png)

**24 Resource Group Clean Up** – Resource group deleted – no orphaned resources

![24 Resource Group Clean Up](screenshots/24%20Resource%20Group%20Clean%20Up.png)

### CLI

| File | Shows |
|---|---|
| `25-cli-deploy-verification.png` | `deploy.sh` verification: resources, VMs, NIC → NSG/ASG table, nsg-app rules |
| `26-cli-extension-and-nat.png` | Data disk, extension state and NAT public IP from `deploy.sh` |
| `27-cli-test-summary.png` | `test-vm.sh` summary table with PASS results |
| `28-cli-effective-rules.png` | `test-vm.sh` Test 5: subnet and NIC NSG rules |
| `29-cli-power-states.png` | `test-vm.sh` Test 6: vm-web2 deallocated |
| `30-cli-cleanup.png` | `cleanup.sh` confirmation and `az group exists` → false |

**25-cli-deploy-verification** – `deploy.sh` verification: resources, VMs, NIC → NSG/ASG table, nsg-app rules

![25-cli-deploy-verification](screenshots/25-cli-deploy-verification.png)

**26-cli-extension-and-nat** – Data disk, extension state and NAT public IP from `deploy.sh`

![26-cli-extension-and-nat](screenshots/26-cli-extension-and-nat.png)

**27-cli-test-summary** – `test-vm.sh` summary table with PASS results

![27-cli-test-summary](screenshots/27-cli-test-summary.png)

**28-cli-effective-rules** – `test-vm.sh` Test 5: subnet and NIC NSG rules

![28-cli-effective-rules](screenshots/28-cli-effective-rules.png)

**29-cli-power-states** – `test-vm.sh` Test 6: vm-web2 deallocated

![29-cli-power-states](screenshots/29-cli-power-states.png)

**30-cli-cleanup** – `cleanup.sh` confirmation and `az group exists` → false

![30-cli-cleanup](screenshots/30-cli-cleanup.png)

## Key Takeaways

1. **ASGs make rules follow the server's role, not its location.** Two VMs in the same subnet received different access.
2. **An ASG is attached to a NIC**, not a VM, and every NIC in an ASG must be in the **same VNet**.
3. **Subnet NSG and NIC NSG are both evaluated** – inbound: subnet first, then NIC. Both must allow.
4. **NAT Gateway gives outbound only.** Nothing can initiate a connection inward through it.
5. **A data disk arrives raw.** It still has to be partitioned, formatted and mounted inside the OS.
6. **The temporary disk is not persistent** – wiped on deallocate, resize or host move.
7. **cloud-init runs once at first boot; extensions and Run command can run any time.**
8. **The portal Stop button deallocates; `az vm stop` does not** (compute is still billed).
9. **Regions and VM families have separate capacity and quota** – plan for alternatives.

## Test Yourself

1. vm-web2 is in the same subnet as vm-web1. Why couldn't it reach vm-app on 8080?
2. You add a new web server. What's the only change needed for it to reach vm-app?
3. nsg-web allows TCP 3389 from the Bastion subnet. Why does IP flow verify say 3389 to vm-web1 is denied?
4. Can a NIC in `vnet-a` be added to an ASG whose other members are in `vnet-b`?
5. Which disk loses its data when a VM is resized?
6. You changed the custom data on a running VM. Why didn't anything change?
7. After `az vm stop`, are you still paying for compute?
8. Can anyone on the internet open a connection to vm-web1 through the NAT Gateway?

<details>
<summary>Answers</summary>

1. nsg-app rule 100 only allows sources in **asg-web**. vm-web2 has no ASG, so it falls through to **Deny-VNet-Inbound** (4000).
2. Add its NIC to **asg-web**. No NSG rule changes.
3. The **NIC NSG** `nsg-vm-web1` denies 3389 at priority 100. Traffic must be allowed by **both** the subnet NSG and the NIC NSG.
4. **No.** All NICs in an ASG must be in the same VNet.
5. The **temporary disk**.
6. **cloud-init runs only once, at first boot.** Use an extension or Run command to change a running VM.
7. **Yes.** `az vm stop` leaves the VM *Stopped* (allocated). Use `az vm deallocate` or the portal **Stop** button.
8. **No.** A NAT Gateway only handles **outbound** connections and their replies.
</details>

## Lessons Learned

- **Regional capacity is real.** The B-series was unavailable to this subscription in **East US** and then **East US 2**. Because a VM must be in the same region as its VNet, NSGs, ASGs and NAT Gateway – and a resource's region can't be changed – I deleted and rebuilt the network in East US 2 and switched to **Standard_D2s_v3**. `deploy.sh` now tries a list of sizes automatically.
- **Quotas exist at two levels:** total regional vCPUs **and** per-VM-family vCPUs. I checked both with `az vm list-usage` before choosing a size.
- **"Unable to validate" in the portal had a hidden cause:** the form was trying to **create** an SSH key with a name that already existed, and the vCPU count had been customised. Recreating the VM with the CLI gave clear output.
- **cloud-init failed silently.** `--custom-data` was given a relative path from the wrong folder, so the CLI sent the *path text* instead of the file. cloud-init reported `done` but did nothing. I fixed the running VM with **Run command** and changed the scripts to use absolute paths.
- **"Blocked" doesn't always mean the firewall.** The first ASG test failed because the app's listener wasn't running – the badges and rules were correct. Checking the service and the network separately found the real cause.

## Next Project

**Project 06 – Standard Load Balancer with Two VMs:** put two web servers behind a Standard Load Balancer with a health probe and load-balancing rules, and see why Standard is **secure by default**.
