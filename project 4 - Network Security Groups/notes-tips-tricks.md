# Project 04 – AZ-104 Notes, Tips & Tricks: Network Security Groups

## Core facts

| Fact | Detail |
|---|---|
| **What an NSG filters** | Layer 3/4 only: source IP, source port, destination IP, destination port, protocol (the 5-tuple) |
| **Where it attaches** | A **subnet** and/or a **NIC**. Not to a VNet, not to a VM directly. |
| **How many** | Each subnet or NIC can have **one** NSG. One NSG can be attached to **many** subnets/NICs. |
| **Region** | An NSG must be in the **same region** as the subnet/NIC it's attached to (it can be in a different resource group). |
| **Priority** | **100 – 4096**. Lower number = processed first. First match wins; processing stops. |
| **Stateful** | Return traffic for an allowed flow is allowed automatically. |
| **Existing connections** | Changing a rule doesn't always cut flows that are already established. |
| **Cost** | NSGs are free. |
| **Limits** | 1,000 rules per NSG (default limits apply per subscription). |

## The six default rules (can't be deleted, can be overridden)

| Direction | Priority | Name | Source → Destination | Action |
|---|---|---|---|---|
| In | 65000 | AllowVnetInBound | VirtualNetwork → VirtualNetwork | Allow |
| In | 65001 | AllowAzureLoadBalancerInBound | AzureLoadBalancer → Any | Allow |
| In | 65500 | DenyAllInBound | Any → Any | Deny |
| Out | 65000 | AllowVnetOutBound | VirtualNetwork → VirtualNetwork | Allow |
| Out | 65001 | AllowInternetOutBound | Any → Internet | Allow |
| Out | 65500 | DenyAllOutBound | Any → Any | Deny |

**Exam trap:** "Which traffic is allowed by default?" → anything inside the VNet (including peered VNets and on-premises over VPN/ExpressRoute), load balancer probes, and **all outbound internet traffic**. Inbound from the internet is denied.

## Evaluation order: subnet + NIC

```
Inbound:   Internet/VNet ──▶ [Subnet NSG] ──▶ [NIC NSG] ──▶ VM
Outbound:  VM ──▶ [NIC NSG] ──▶ [Subnet NSG] ──▶ destination
```

- Traffic must be **allowed by both** NSGs (if both exist).
- If only one exists, only that one is evaluated.
- Within the same subnet, VM-to-VM traffic is still evaluated by the subnet NSG (that's why Deny-VNet-Inbound also blocks web ↔ web).

## Service tags you must know

| Tag | Means |
|---|---|
| `VirtualNetwork` | The VNet address space, peered VNets, on-premises ranges via gateways, and UDR prefixes |
| `Internet` | Public IP space outside Azure's VNet (includes Azure public IPs) |
| `AzureLoadBalancer` | Azure's health probe source (168.63.129.16). **Not** user traffic through the load balancer. |
| `Storage`, `Sql`, `AzureMonitor`, `AzureKeyVault`… | Azure service ranges. Many can be regional, e.g. `Storage.EastUS`. |
| `AzureCloud` | All Azure datacenter public IPs |

Service tags can be used as **source or destination**, and Microsoft updates the IP ranges automatically.

## Application Security Groups (ASGs) – preview of Project 05

- Group **NICs** by role (`asg-web`, `asg-db`) and use the group in rules instead of IPs.
- All NICs in an ASG must be in the **same VNet**. In one rule, source and destination ASGs must be in the same VNet.
- A NIC can belong to several ASGs.
- Great for "web servers may talk to database servers on 1433" without listing IPs.

## Augmented rules

One rule can contain **multiple IPs, ranges and ports** (e.g. ports `22,3389` or several CIDRs), which keeps rule counts down. In the CLI use the plural flags: `--source-address-prefixes`, `--destination-port-ranges`.

## Troubleshooting tools (Network Watcher)

| Tool | Answers | On-premises equivalent |
|---|---|---|
| **IP flow verify** | "Is this 5-tuple allowed or denied, and by which rule?" | Cisco ASA `packet-tracer` |
| **Effective security rules** | "What is the combined rule set applied to this NIC?" | `show access-list` |
| **NSG diagnostics** | Like IP flow verify, but can test at subnet/NIC level for any resource | – |
| **Next hop** | "Where will this packet be routed?" (useful with route tables) | `show ip route` / `traceroute` |
| **Connection troubleshoot** | End-to-end reachability test from a VM | `telnet host port` / `Test-NetConnection` |
| **Flow logs** | Records of allowed/denied flows (Project 13) | NetFlow / firewall logs |

**Note:** NSG flow logs are being retired in favour of **VNet flow logs**. New NSG flow logs can no longer be created, so for new deployments use VNet flow logs.

## Special cases

- **AzureBastionSubnet:** if you attach an NSG, it must contain Bastion's required rules (e.g. inbound 443 from `Internet`, inbound from `GatewayManager`, outbound to `AzureCloud` and to the VNet on 22/3389). A wrong NSG here breaks Bastion.
- **GatewaySubnet:** NSGs are **not supported** on the VPN/ExpressRoute gateway subnet.
- **Application Gateway subnet:** NSGs are allowed but must permit GatewayManager ports (65200–65535 for v2) and AzureLoadBalancer.
- **Standard Load Balancer / Standard public IP:** closed by default; you **must** have an NSG allowing the traffic (Project 06).

## CLI vs PowerShell cheat sheet

| Task | Azure CLI | PowerShell |
|---|---|---|
| Create NSG | `az network nsg create` | `New-AzNetworkSecurityGroup` |
| Add rule | `az network nsg rule create` | `Add-AzNetworkSecurityRuleConfig` + `Set-AzNetworkSecurityGroup` |
| Build rule in memory | – | `New-AzNetworkSecurityRuleConfig` |
| List rules | `az network nsg rule list` | `(Get-AzNetworkSecurityGroup).SecurityRules` |
| Show defaults | `az network nsg rule list --include-default` | `.DefaultSecurityRules` |
| Attach to subnet | `az network vnet subnet update --network-security-group` | `Set-AzVirtualNetworkSubnetConfig -NetworkSecurityGroup` + `Set-AzVirtualNetwork` |
| Attach to NIC | `az network nic update --network-security-group` | `$nic.NetworkSecurityGroup = $nsg; Set-AzNetworkInterface` |
| Effective rules | `az network nic list-effective-nsg` | `Get-AzEffectiveNetworkSecurityGroup` |
| IP flow verify | `az network watcher test-ip-flow` | `Test-AzNetworkWatcherIPFlow` |

**PowerShell gotcha (again):** `Add-AzNetworkSecurityRuleConfig` only changes the object in memory. Nothing changes in Azure until `Set-AzNetworkSecurityGroup`.

## Exam scenario patterns

| Scenario | Answer |
|---|---|
| "Allow RDP only from the admin network" | Inbound rule, source = admin CIDR, port 3389, priority lower than any broader deny |
| "VM can't be reached even though the subnet NSG allows it" | Check the **NIC NSG** – both must allow |
| "Find which rule is blocking traffic" | **IP flow verify** |
| "See every rule applied to a VM, including defaults" | **Effective security rules** |
| "Rules for web servers without maintaining IPs" | **Application Security Groups** |
| "Block VMs from the internet" | Outbound deny to `Internet` at a priority below 65001 |
| "Allow load balancer health probes" | Already allowed by AllowAzureLoadBalancerInBound – unless you added a deny above it |
| "Minimum rules to allow HTTPS and SSH from one IP" | One augmented rule with ports `443,22` and that source IP |

## Common mistakes

- Expecting subnets to isolate traffic without an NSG.
- Allow rules only, forgetting AllowVnetInBound lets all internal traffic through.
- A broad deny at a **lower** number than the allow you need (the deny wins).
- Forgetting the NIC-level NSG that `az vm create` adds automatically.
- Allowing management ports (22/3389) from `Any` or `Internet`.
