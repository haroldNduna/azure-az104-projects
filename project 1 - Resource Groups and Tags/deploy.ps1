# ==============================================
# Project 01 - Azure Resource Groups & Tags
# Deployment Script (Azure PowerShell)
# Security+ Aligned: Governance & Accountability
# ==============================================

# Set variables
$resourceGroup = "rg-az104-project01"
$location = "eastus"
$environment = "Lab"
$costCenter = "IT-Services"
$owner = "Harold Nduna"

# Display start message
Write-Host "=================================================="
Write-Host " Starting Project 01 - Resource Groups & Tags"
Write-Host "   Security+ Governance & Compliance Alignment"
Write-Host "=================================================="

# Step 1: Login to Azure
Write-Host " Step 1: Logging into Azure..."
Connect-AzAccount

# Step 2: Set subscription (optional)
# Write-Host " Step 2: Setting subscription..."
# Set-AzContext -Subscription "Your-Subscription-Name"

# Step 3: Create Resource Group with tags
Write-Host " Step 3: Creating Resource Group with tags..."
$tags = @{
    Environment = $environment
    CostCenter = $costCenter
    Owner = $owner
}
New-AzResourceGroup -Name $resourceGroup -Location $location -Tag $tags

# Step 4: Verify Resource Group creation
Write-Host " Step 4: Verifying Resource Group creation..."
Get-AzResourceGroup -Name $resourceGroup

# Step 5: Display tags separately
Write-Host " Step 5: Displaying tags..."
(Get-AzResourceGroup -Name $resourceGroup).Tags

# Step 6: Summary
Write-Host "=================================================="
Write-Host " Project 01 Deployment Complete!"
Write-Host "   Resource Group: $resourceGroup"
Write-Host "   Location: $location"
Write-Host "   Tags: Environment=$environment, CostCenter=$costCenter, Owner=$owner"
Write-Host "=================================================="
Write-Host " Take Screenshots Now:"
Write-Host "   1. Resource Group in Portal (01-resource-group-created.png)"
Write-Host "   2. Tags section (02-tags-applied.png)"
Write-Host "   3. This terminal output (03-cli-deployment-success.png)"
Write-Host "=================================================="
Write-Host " To cleanup: Remove-AzResourceGroup -Name $resourceGroup -Force"
