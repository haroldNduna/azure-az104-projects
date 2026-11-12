# Project 05 – AZ-104 Notes, Tips & Tricks: VMs, Disks, ASGs, Extensions & NAT Gateway

## VM sizes – reading the name

`Standard_D2s_v3` →
| Part | Meaning |
|---|---|
| `D` | Family: general purpose |
| `2` | vCPUs |
| `s` | Supports Premium SSD |
| `v3` | Generation of the size |

Other letters you'll see: `a` = AMD, `p` = Arm, `l` = low memory, `d` = **local temp disk**, `t` = tiny memory.

| Family | Use |
|---|---|
| **B** (burstable) | Dev/test, low average CPU – builds up CPU credits while idle |
| **D** | General purpose |
| **E** | Memory optimised |
| **F** | Compute optimised |
| **L** | Storage optimised |
| **N** | GPU |
| **M** | Very large memory (SAP HANA) |

## Quotas

- Two limits apply: **Total Regional vCPUs** and **per-family vCPUs** (e.g. *Standard DSv3 Family vCPUs*).
- Check: `az vm list-usage --location eastus2 -o table` or portal → **Quotas → Compute**.
- Deallocated VMs don't count towards vCPU quota.
- `SkuNotAvailable` = **capacity/availability** problem (try another zone, size or region). `QuotaExceeded` = **your limit** (request an increase or use another family).

## Resizing

- Resizing **restarts** the VM.
- If the new size isn't available on the current hardware cluster, it won't be listed until you **deallocate** the VM first.
- Resizing wipes the **temporary disk**.

## Disks

| Disk | Purpose | Persistent? |
|---|---|---|
| OS disk | Operating system | Yes |
| Data disk | Application data – attached at a **LUN** (0, 1, 2…) | Yes |
| Temporary disk | Page/swap file, scratch | **No** – lost on deallocate, resize, redeploy, host move |

| Type | Notes |
|---|---|
| Standard HDD | Cheapest; dev/test, backups |
| Standard SSD | Light production, web servers |
| Premium SSD | Production; needed for the single-VM SLA |
| Premium SSD v2 | High performance, adjustable IOPS/throughput; **data disks only** |
| Ultra Disk | Highest performance; **data disks only** |

- **Host caching:** None / ReadOnly / ReadWrite. ReadOnly is the default for data disks on Premium; **don't use ReadWrite for database log disks**.
- A new data disk is **raw** – partition, format and mount (Linux) or initialise in Disk Management (Windows).
- Disks can be **expanded** (not shrunk); expanding an attached disk may need the VM deallocated.
- **Shared disks** let several VMs attach the same managed disk (clusters).
- **Snapshots** = point-in-time copy of a disk; **images** = template for new VMs.

## Encryption

| Option | What it covers |
|---|---|
| **Server-side encryption (SSE) with platform-managed keys** | Default, always on, every managed disk |
| SSE with **customer-managed keys** (Key Vault + disk encryption set) | Same, but you control the key |
| **Encryption at host** | Also encrypts the **temp disk** and **disk caches** on the host. Needs a one-off feature registration (`az feature register --namespace Microsoft.Compute --name EncryptionAtHost`). |
| Azure Disk Encryption (ADE) | BitLocker/dm-crypt inside the guest. Being retired – Microsoft recommends encryption at host instead |
| Confidential disk encryption | For confidential VMs |

## Trusted Launch

- **Secure Boot** (only signed boot loaders/kernels), **vTPM** (measured boot, key storage) and **integrity monitoring**.
- Needs a **Gen2** image and a supported size.
- Default security type for new VMs in the portal.

## Availability (preview of Project 06)

| Option | Protects against | SLA |
|---|---|---|
| Single VM with Premium SSD/Ultra on all disks | – | 99.9% |
| **Availability set** (fault + update domains) | Rack / host failure, planned maintenance | 99.95% |
| **Availability zones** | Datacenter failure | 99.99% |

- Availability set: up to **3 fault domains** and **20 update domains**. A VM can only be added to a set **at creation**.

## Power states

| State | Compute billed? | How |
|---|---|---|
| Running | Yes | – |
| **Stopped** | **Yes** | `az vm stop`, or shutdown inside the OS |
| **Stopped (deallocated)** | No | Portal **Stop**, `az vm deallocate`, PowerShell `Stop-AzVM` (default) |

Disks are always billed until deleted. Deallocating may change a **dynamic** public IP.

## Managing VMs without opening ports

| Tool | Use |
|---|---|
| **Run command** | Run a script inside the VM via the VM agent (`az vm run-command invoke`). Not for long-running jobs. |
| **Serial console** | Text console even with no network – needs **boot diagnostics** enabled (and a local password to log in) |
| **Boot diagnostics** | Screenshot + serial log of boot – use a **managed storage account** |
| **Azure Bastion** | Browser-based RDP/SSH over TLS (Project 07) |
| **Redeploy** | Moves the VM to a new host – fixes host-level problems; wipes the temp disk |
| **Reapply** | Re-applies the VM's state – fixes stuck provisioning |
| **Reset password / SSH key** | VMAccess extension (portal: *Help → Reset password*) |

## Extensions vs cloud-init vs Run command

| | When it runs | Typical use |
|---|---|---|
| **cloud-init / custom data** | **Once**, at first boot | Linux first-boot config |
| **Custom Script Extension** | Any time; once per settings change | Install/configure software |
| **Run command** | On demand | Troubleshooting, one-off commands |
| **DSC / Azure Automanage / Machine Configuration** | Continuously | Keep config compliant |

- Linux CSE: publisher `Microsoft.Azure.Extensions`, type `CustomScript`, version `2.1`.
- Windows CSE: publisher `Microsoft.Compute`, type `CustomScriptExtension`, version `1.10`.
- Put **secrets** (storage keys, the command if it contains secrets) in **protectedSettings** – encrypted and never returned.
- Only **one** CSE per VM. To run it again, change its settings (e.g. a timestamp) or remove and re-add it.
- The extension needs network access to download its files (here: NAT Gateway → storage).
- Other common extensions: **Azure Monitor Agent**, **Microsoft Defender for Endpoint**, **VMAccess**, **Network Watcher Agent**, **Dependency agent**.

## Application Security Groups

- Group **NICs** (IP configurations) by role and use the group in NSG rules as **source and/or destination**.
- All NICs in an ASG must be in the **same VNet** as the first NIC added.
- In one rule, source and destination ASGs must be in the same VNet.
- A NIC can belong to several ASGs (limits apply).
- ASGs are free. They're a **logical** grouping – no traffic flows "through" them.
- Exam pattern: *"Allow web servers to reach database servers without managing IP addresses"* → **ASGs**.

## NIC NSG vs subnet NSG

```
Inbound:   source ─▶ subnet NSG ─▶ NIC NSG ─▶ VM
Outbound:  VM ─▶ NIC NSG ─▶ subnet NSG ─▶ destination
```

- **Both** must allow. Check the combined result with **Effective security rules** or **IP flow verify**.
- `az vm create` creates a **NIC NSG by default** (allowing SSH/RDP from anywhere). Use `--nsg ""` to avoid it.

## NAT Gateway

- Provides **outbound-only** internet (SNAT) for whole subnets. Inbound connections can't be started through it.
- Needs a **Standard** public IP (or prefix). Up to **16** public IPs → up to ~1 million SNAT ports.
- **One NAT Gateway per subnet**; one NAT Gateway can serve **several subnets in the same VNet** – but not across VNets.
- Takes **precedence** over other outbound methods (load balancer outbound rules, instance-level public IPs) for outbound traffic.
- Charged **per hour + per GB processed**, even with no VMs running.
- The modern replacement for "default outbound access" (retired for new VNets from 31 March 2026).

## CLI vs PowerShell cheat sheet

| Task | Azure CLI | PowerShell |
|---|---|---|
| Create VM | `az vm create` | `New-AzVM` |
| List sizes in region | `az vm list-sizes -l eastus2` | `Get-AzVMSize -Location eastus2` |
| Sizes this VM can resize to | `az vm list-vm-resize-options` | `Get-AzVMSize -ResourceGroupName -VMName` |
| Resize | `az vm resize --size` | `$vm.HardwareProfile.VmSize = ...; Update-AzVM` |
| Deallocate | `az vm deallocate` | `Stop-AzVM` |
| Stop (still billed) | `az vm stop` | `Stop-AzVM -StayProvisioned` |
| Attach new data disk | `az vm disk attach --new --size-gb 4` | `Add-AzVMDataDisk` + `Update-AzVM` |
| Run command | `az vm run-command invoke` | `Invoke-AzVMRunCommand` |
| Extension | `az vm extension set` | `Set-AzVMExtension` / `Set-AzVMCustomScriptExtension` |
| Create ASG | `az network asg create` | `New-AzApplicationSecurityGroup` |
| NIC into ASG | `az network nic ip-config update --application-security-groups` | `$nic.IpConfigurations[0].ApplicationSecurityGroups = $asg; Set-AzNetworkInterface` |
| NAT Gateway | `az network nat gateway create` | `New-AzNatGateway` |
| Effective NSG | `az network nic list-effective-nsg` | `Get-AzEffectiveNetworkSecurityGroup` |
| Quota | `az vm list-usage -l eastus2` | `Get-AzVMUsage -Location eastus2` |

## Exam traps

| Trap | Truth |
|---|---|
| "Store the app's data on the D: drive / /mnt" | Temp disk – data lost on deallocate/resize |
| "`az vm stop` to save money" | Still billed – use `az vm deallocate` |
| "Add an existing VM to an availability set" | Not possible – recreate the VM |
| "Move a VM to another VNet" | Not possible – recreate (you *can* change subnet within the same VNet) |
| "Change cloud-init on a running VM" | No effect – it only runs at first boot |
| "NAT Gateway allows inbound access" | Outbound only |
| "ASG with NICs from two VNets" | Not allowed |
| "Resize option missing from the list" | Deallocate first, then resize |
| "Serial console shows nothing" | Enable boot diagnostics |
| "Use Ultra Disk as OS disk" | Ultra and Premium SSD v2 are data disks only |
