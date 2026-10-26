# Project 03 – AZ-104 Notes, Tips & Tricks: Virtual Networks

## Core facts the exam loves

| Fact | Detail |
|---|---|
| **Scope** | A VNet belongs to **one region** and **one subscription**. Subnets can't span VNets. |
| **Reserved IPs** | Azure reserves **5 IPs in every subnet**: `.0` network, `.1` default gateway, `.2` and `.3` Azure DNS mapping, `.255` (last) broadcast. |
| **Usable IP math** | Usable = 2^(32 − prefix) − 5. `/24` → 251, `/26` → 59, `/27` → 27, `/28` → 11, `/29` → 3. |
| **Smallest subnet** | `/29` for IPv4 (3 usable addresses). |
| **Private ranges (RFC 1918)** | `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`. Azure also accepts public ranges, but that is bad practice. |
| **Ranges Azure won't accept** | `224.0.0.0/4` (multicast), `255.255.255.255/32`, `127.0.0.0/8` (loopback), `169.254.0.0/16` (link-local), `168.63.129.16/32` (Azure internal DNS/health probes). |
| **Cost** | VNets and subnets are **free**. You pay for what's inside or attached (peering traffic, gateways, public IPs, NAT Gateway). |
| **Default communication** | All subnets in the same VNet can talk to each other by default (system routes). NSGs (Project 04) are what restrict that. |
| **Default DNS** | Azure-provided DNS at `168.63.129.16` unless you set custom DNS servers on the VNet. |

## Special subnets – exact names required

| Subnet name | Used by | Minimum size |
|---|---|---|
| `GatewaySubnet` | VPN Gateway / ExpressRoute Gateway | `/29` (Microsoft recommends `/27`) |
| `AzureBastionSubnet` | Azure Bastion | `/26` |
| `AzureFirewallSubnet` | Azure Firewall | `/26` |
| `AzureFirewallManagementSubnet` | Azure Firewall (forced tunnelling / Basic SKU) | `/26` |
| *(any name)* | Application Gateway | Dedicated subnet, `/24` recommended, no other resource types inside |

**Exam trap:** If an answer uses `BastionSubnet` or `bastion-subnet`, it's wrong. The name is case-sensitive and must be exact.

## Changing things after deployment

- ✅ **You can** add address spaces to an existing VNet.
- ✅ **You can** add subnets at any time if there's free space.
- ❌ **You can't** resize a subnet that has resources (NICs) in it. Move or delete them first.
- ❌ **You can't** move a VNet to another region. Recreate it.
- ⚠️ If a VNet is peered, you can change its address space, but you must **sync the peering** afterwards.
- ✅ A VNet **can** be moved to another resource group or subscription (along with dependent resources).

## Service endpoints vs private endpoints (very commonly tested)

| | Service endpoint | Private endpoint (Private Link) |
|---|---|---|
| What it does | Extends the subnet's identity to the PaaS service over the Azure backbone | Gives the PaaS service a **private IP inside your subnet** |
| Service's public endpoint | Still exists (locked down via service firewall) | Can be disabled entirely |
| Reachable from on-premises / peered VNets | ❌ No | ✅ Yes |
| Cost | Free | Paid (per hour + per GB) |
| Configured on | **The subnet** | A NIC created in the subnet |
| DNS changes needed | No | Yes (private DNS zone, covered in Project 08) |

**Tip:** If the question says "from on-premises" or "without exposing a public endpoint," the answer is **private endpoint**. If it says "free" or "simplest," the answer is **service endpoint**.

To finish the service endpoint setup, add a network rule on the storage account:

```bash
az storage account network-rule add \
  --resource-group rg-az104-project02 \
  --account-name staz104proj02 \
  --vnet-name vnet-az104-project03 \
  --subnet snet-data
```

(The VNet and storage account must be in the same region, and you'd pass the subnet's resource ID if they are in different resource groups.)

## Default outbound access & private subnets (current behaviour)

- Historically, VMs without a public IP still got internet access through a hidden, Microsoft-owned SNAT IP. This is called **default outbound access**.
- Microsoft is retiring it. VNets created with API versions released after **31 March 2026** default to **private subnets**. Existing VNets are not changed.
- Explicit outbound options: **NAT Gateway** (preferred), **Load Balancer outbound rules**, **public IP on the NIC**, or **Azure Firewall/NVA** via a route table (UDR).
- CLI flag: `az network vnet subnet create ... --default-outbound-access false`
- Bicep/ARM property: `defaultOutboundAccess: false`

## CLI vs PowerShell cheat sheet

| Task | Azure CLI | PowerShell |
|---|---|---|
| Create VNet | `az network vnet create` | `New-AzVirtualNetwork` |
| Create subnet | `az network vnet subnet create` | `Add-AzVirtualNetworkSubnetConfig` + `Set-AzVirtualNetwork` |
| List subnets | `az network vnet subnet list` | `(Get-AzVirtualNetwork).Subnets` |
| Add address space | `az network vnet update --address-prefixes ...` | `$vnet.AddressSpace.AddressPrefixes.Add()` + `Set-AzVirtualNetwork` |
| Check an IP is free | `az network vnet check-ip-address --ip-address 10.10.1.10` | `Test-AzPrivateIPAddressAvailability` |

**PowerShell gotcha:** `Add-AzVirtualNetworkSubnetConfig` only changes the object **in memory**. Nothing happens in Azure until you pipe it to `Set-AzVirtualNetwork`. The exam tests this.

## Portfolio hygiene (security)

- Blur your **subscription ID, tenant ID and email** in screenshots before pushing to GitHub.
- Never commit secrets (connection strings, SAS tokens, keys). Add a `.gitignore` at the repo root.
- Always run `cleanup.sh`. Orphaned resources are an unmonitored attack surface (and a bill on a free trial).
