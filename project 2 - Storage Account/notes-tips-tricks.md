# Project 02 – Notes, Tips & Exam Tricks

## 🔍 AZ-104 Exam Focus

| Skill | How It Appears |
|-------|----------------|
| **Storage Account naming** | Must be 3-24 chars, lowercase, globally unique |
| **Redundancy options** | LRS, ZRS, GRS, GZRS, RA-GRS |
| **Blob vs File vs Queue vs Table** | Know the differences for the exam |
| **Encryption at rest** | Enabled by default, cannot disable |
| **Secure Transfer Required** | HTTPS only (enforced by `--https-only true`) |
| **Public access levels** | Private (default), Blob, Container |
| **Deployment scopes** | Resource Group vs Subscription scope |

---

##  Common Exam Tricks

| Trick Question | Answer |
|----------------|--------|
| "Can you rename a storage account?" | NO – must create a new one |
| "Is encryption at rest optional?" | NO – enabled by default |
| "Does Secure Transfer Required allow HTTP?" | NO – HTTPS only |
| "Can a storage account be moved between regions?" | NO |
| "Can a storage account be moved to another resource group?" | YES (with some limitations) |
| "Does the storage account name need to be unique globally?" | YES |

---

##  Security+ Integration Notes

| Security+ Concept | Azure Implementation |
|-------------------|----------------------|
| **Encryption at rest** | Azure Storage SSE (Server-Side Encryption) |
| **Data in transit** | HTTPS only (TLS 1.2) |
| **Least privilege** | Private containers, SAS tokens |
| **Data classification** | Tags: Environment = Lab |
| **Access control** | RBAC roles (Storage Blob Data Contributor) |
| **Accountability** | Owner tag with specific name (not generic) |

---

##  Lessons Learned from Project 02

### 1. Bicep Deployment Scopes

**Issue**: The deployment kept failing with `BCP135: Scope "resourceGroup" is not valid for this resource type`.

**What I tried**: I had a `scope: resourceGroup()` line in my Bicep file when trying to create a Resource Group.

**Why it failed**: Resource Groups are **subscription-level** resources. You cannot create them using `az deployment group create` (which targets a resource group). The correct approach is:
- **Resource Groups** → Deploy with `az deployment sub create`
- **Resources inside RG** (Storage, VMs) → Deploy with `az deployment group create`

**How I fixed it**: Removed the Resource Group from my Bicep file entirely since it already existed, and only deployed the Storage Account (which is a resource group-level resource).

**Security+ Alignment**: Understanding deployment scopes is crucial for **least privilege** – you should only grant permissions at the scope where resources are deployed.

### 2. Bicep Syntax – Tags Object

**Issue**: Errors `BCP018` and `BCP009` pointed to missing colons in the tags object.

**Incorrect syntax** (what caused the errors):
```bicep
var tags = {
  Environment 'Lab'   // ❌ Missing colon
  CostCenter 'IT-Services'  // ❌ Missing colon
}