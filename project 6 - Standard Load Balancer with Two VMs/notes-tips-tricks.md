# Project 06 – AZ-104 Notes, Tips & Tricks: Azure Load Balancer

## Which load-balancing service?

| Service | Layer | Scope | Use when |
|---|---|---|---|
| **Azure Load Balancer** | 4 (TCP/UDP) | Regional (or global tier) | Any TCP/UDP app, VMs/VMSS, high throughput, low latency |
| **Application Gateway** | 7 (HTTP/HTTPS) | Regional | URL/path routing, host-based routing, TLS termination, **WAF**, cookie affinity |
| **Front Door** | 7 | Global | Global web apps, CDN, global WAF, fastest-region routing |
| **Traffic Manager** | DNS | Global | DNS-based routing between regions/endpoints (priority, weighted, performance, geographic) |

Exam cue words: *"path-based"*, *"WAF"*, *"SSL offload"* → Application Gateway. *"Global"* + *"HTTP"* → Front Door. *"DNS"* → Traffic Manager. *"TCP/UDP"*, *"any port"*, *"HA ports"* → Load Balancer.

## SKUs

| | **Standard** | Basic |
|---|---|---|
| Status | Current | **Retired 30 September 2025** |
| Backend pool | Up to 1,000 instances, any VMs/VMSS in one VNet | Single availability set or VMSS |
| Secure by default | **Yes – needs an NSG to allow traffic** | No (open by default) |
| Availability zones | Zone-redundant or zonal frontends | No |
| SLA | 99.99% | None |
| Outbound rules | Yes | No |
| HA ports | Yes (internal) | No |
| Diagnostics | Azure Monitor multi-dimensional metrics | Limited |

Standard LB needs a **Standard public IP** (Basic public IPs were also retired).

## Components

| Component | Purpose |
|---|---|
| **Frontend IP configuration** | Public IP (public LB) or private IP (internal LB) that clients connect to |
| **Backend pool** | NICs (or IP addresses) that receive traffic – must be in the **same VNet** |
| **Health probe** | TCP, HTTP or HTTPS check; unhealthy backends get no new flows |
| **Load-balancing rule** | Frontend IP:port + protocol → backend pool:port, using a probe |
| **Inbound NAT rule** | One frontend port → one backend VM's port (e.g. 50001 → VM1:22) |
| **Outbound rule** | Explicit SNAT for backend pool members to reach the internet |

## Health probes

- Source IP **168.63.129.16** (service tag **AzureLoadBalancer**). It must not be blocked by NSGs or the guest firewall.
- **TCP** probe: succeeds if a TCP connection is made. **HTTP/HTTPS** probe: needs an **HTTP 200** from the path.
- Default interval **5 seconds**. The probe threshold controls how many failures mark an instance down.
- If **all** backends fail the probe, Standard LB stops sending new flows (existing flows may continue).

## Distribution modes (session persistence)

| Setting (portal) | CLI `--load-distribution` | Hash |
|---|---|---|
| None | `Default` | 5-tuple: source IP, source port, destination IP, destination port, protocol |
| Client IP | `SourceIP` | 2-tuple: source IP, destination IP |
| Client IP and protocol | `SourceIPProtocol` | 3-tuple |

There is no round-robin – distribution is a hash **per connection**.

## Outbound connectivity – order of precedence

1. **NAT Gateway** on the subnet (preferred, scales best)
2. **Instance-level public IP** on the NIC
3. **Load balancer outbound rule** (or the LB rule's default outbound SNAT – not recommended)
4. Default outbound access – retired for new VNets after 31 March 2026 (private subnets)

When using outbound rules, set **`disableOutboundSnat: true`** on the load-balancing rule so outbound comes only from the outbound rule. **SNAT port exhaustion** is fixed by adding frontend IPs or switching to a NAT Gateway.

## Internal load balancer and HA ports

- **Internal (private) LB**: frontend is a private IP in a subnet – used for app/data tiers.
- **HA ports**: a rule with protocol **All** and port **0** that balances **every port** – used for network virtual appliances (firewalls) behind an internal Standard LB.

## Floating IP (Direct Server Return)

- The backend receives the **frontend IP** as destination instead of its own IP.
- Needed for **SQL Server Always On availability group listeners** and some clustering scenarios.

## Availability options and SLAs

| Option | Protects against | SLA |
|---|---|---|
| Single VM (Premium SSD) | – | 99.9% |
| **Availability set** | Rack (fault domain) and maintenance (update domain) failures | 99.95% |
| **Availability zones** | Whole datacenter failure | 99.99% |

- Availability sets: up to **3 fault domains** and **20 update domains**; VMs can only join **at creation**.
- Zonal VMs need a size that's **allowed in that zone** for your subscription.
- Public IPs can be **zonal** (one zone) or **zone-redundant** (all zones).

## CLI vs PowerShell cheat sheet

| Task | Azure CLI | PowerShell |
|---|---|---|
| Create LB | `az network lb create --sku Standard` | `New-AzLoadBalancer -Sku Standard` |
| Frontend | `az network lb frontend-ip create` | `New-AzLoadBalancerFrontendIpConfig` |
| Backend pool | `az network lb address-pool create` | `New-AzLoadBalancerBackendAddressPoolConfig` |
| Probe | `az network lb probe create` | `New-AzLoadBalancerProbeConfig` |
| LB rule | `az network lb rule create` | `New-AzLoadBalancerRuleConfig` |
| Inbound NAT rule | `az network lb inbound-nat-rule create` | `New-AzLoadBalancerInboundNatRuleConfig` |
| Outbound rule | `az network lb outbound-rule create` | `New-AzLoadBalancerOutboundRuleConfig` |
| NIC into pool | `az network nic ip-config address-pool add` | `$nic.IpConfigurations[0].LoadBalancerBackendAddressPools = $pool; Set-AzNetworkInterface` |
| Change persistence | `az network lb rule update --load-distribution SourceIP` | `Set-AzLoadBalancerRuleConfig -LoadDistribution SourceIP` |
| Probe health metric | `az monitor metrics list --metric DipAvailability` | `Get-AzMetric -MetricName DipAvailability` |

## Exam traps

| Trap | Truth |
|---|---|
| "Standard LB deployed, site unreachable, VMs healthy" | Add an **NSG rule** – Standard is secure by default |
| "All backends show unhealthy" | Something blocks **168.63.129.16 / AzureLoadBalancer**, or the probe path doesn't return 200 |
| "Route by URL path" with Load Balancer | Not possible – use **Application Gateway** |
| "Use Basic LB to save money" | Basic is **retired** |
| "Backend pool across two VNets" | Not supported – one VNet (use global/cross-region LB or other services) |
| "Load balancer round-robins" | It uses a **hash** per connection |
| "Outbound fails at scale" | **SNAT port exhaustion** – add frontend IPs or a NAT Gateway |
| "SQL AG listener behind LB" | Enable **Floating IP** |
| "Balance all ports for an NVA" | **HA ports** on an **internal Standard** LB |
| "Add an existing VM to an availability set" | Not possible – recreate it |
