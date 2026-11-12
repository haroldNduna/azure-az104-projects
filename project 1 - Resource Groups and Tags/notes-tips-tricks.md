# Project 01 – Notes, Tips & Exam Tricks

##  AZ-104 Exam Focus

| Exam Skill | How It Appears |
|------------|----------------|
| **Resource Group location** | Resource Groups can only be in one region – this is the **metadata location**, NOT where resources are deployed |
| **Tag inheritance** | Tags applied to Resource Groups do NOT automatically inherit to child resources (they must applied separately or use Azure Policy) |

---

##  Common Exam Tricks

| Trick Question | Answer |
|----------------|--------|
| "Can a Resource Group contain resources from different regions?" | YES – Resource Group location is metadata only |
| "Do tags automatically apply to resources inside a Resource Group?" | NO – you must use Azure Policy to enforce inheritance |

---

##  Security+ Integration Notes

| Security+ Concept | Azure Implementation |
|-------------------|----------------------|
| **Asset Classification** | Tags like Environment=Lab classify data sensitivity |
| **Accountability** | Tags like Owner=Harold Nduna establish responsibility |

---

##  Lessons Learned from Project 01

### 1. Tagging Mistake – Using "Administrator" as Owner

**What I did wrong**: Initially, I used `Owner = Administrator` as a generic tag.

**Why it's wrong**: 
- No individual accountability (Security+ non-repudiation failure)
- During an incident, security teams can't contact a specific person
- Compliance audits require specific ownership

**What I learned**: Always use a **specific name or email** for Owner tags. I updated mine to `Owner = Harold Nduna` to ensure clear accountability.

**Security+ Alignment**: This aligns with **Domain 5.0 (Governance & Compliance)** – proper tagging ensures clear ownership and supports audit readiness.

### 2. Git Mistake – Running `git init` in Wrong Folder

**What I did wrong**: I initialized Git in `~/azure/projects/` instead of `~/azure-az104-projects/`.

**How I fixed it**: Deleted the `.git` folder from the wrong location and re-initialized in the correct folder.

**What I learned**: Always run `pwd` before `git init` to confirm directory.

---

## 🛠️ CLI vs PowerShell – Exam Comparison

| Task | CLI (Bash) | PowerShell |
|------|------------|------------|
| Login | `az login` | `Connect-AzAccount` |
| Create RG | `az group create` | `New-AzResourceGroup` |

> **Exam Tip**: The AZ-104 exam often asks to choose the correct CLI or PowerShell command. Knowing both syntaxes is the best.

---

##  Screenshot Checklist

| # | File Name | What to Capture |
|---|-----------|-----------------|
| 1 | `01-resource-group-created.png` | Resource Group in Portal |
| 2 | `02-tags-applied.png` | Tags section with values |

---

##  Common Mistakes to Avoid

1. **Forgetting to set subscription** – if there are multiple subscriptions, `az account set` must be used
2. **Not including `--no-wait`** – cleanup can take time
3. **Typos in tag names** – tags are case-sensitive!
4. **Using generic Owner tags** – always use specific names or emails!

---

##  Real-World Application

**Enterprise tagging best practices:**
- **Owner tags** should be full names or emails (not "Administrator" or "Self")
- **Cost Center tags** should align with finance department codes
- **Environment tags** should include Dev/Test/Prod/Staging
- **Data Classification tags** should indicate sensitivity (Public/Internal/Confidential/Restricted)

This structure is what enterprise recruiters want to see!
