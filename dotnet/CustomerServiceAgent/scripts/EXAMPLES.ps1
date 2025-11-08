# Example: Using Setup-EntraIdApps.ps1
# This script demonstrates common usage patterns

# ============================================
# Example 1: Basic Interactive Setup with Agent Identities
# ============================================
Write-Host "`n=== Example 1: Basic Interactive Setup with Agent Identities ===" -ForegroundColor Cyan
Write-Host "Connect to your tenant and run the setup script:`n"
Write-Host "  Connect-MgGraph -Scopes 'Application.ReadWrite.All','Directory.ReadWrite.All','AppRoleAssignment.ReadWrite.All'"
Write-Host "  .\Setup-EntraIdApps.ps1 -ServiceAccountUpn 'csr-agent@yourdomain.com'`n"
Write-Host "Note: Creates Agent Identity Blueprint application with inheritable permissions."
Write-Host "      Provides guidance for manual Agent Identity creation in Azure Portal.`n"

# ============================================
# Example 2: Skip Agent Identities (for tenants without preview feature)
# ============================================
Write-Host "`n=== Example 2: Skip Agent Identities ===" -ForegroundColor Cyan
Write-Host "For tenants without Agent Identity Blueprints preview feature:`n"
Write-Host "  .\Setup-EntraIdApps.ps1 -SkipAgentIdentities`n"

# ============================================
# Example 3: Automated Setup with Config Update
# ============================================
Write-Host "`n=== Example 3: Automated Setup with Config Update ===" -ForegroundColor Cyan
Write-Host "Automatically update all appsettings.json files:`n"
Write-Host "  .\Setup-EntraIdApps.ps1 -OutputFormat UpdateConfig`n"

# ============================================
# Example 4: Create Multiple Instances with Custom Prefix
# ============================================
Write-Host "`n=== Example 4: Create Multiple Instances ===" -ForegroundColor Cyan
Write-Host @"
# Create development instance
.\Setup-EntraIdApps.ps1 -SampleInstancePrefix "Dev-" -OutputFormat UpdateConfig

# Create test instance
.\Setup-EntraIdApps.ps1 -SampleInstancePrefix "Test-" -OutputFormat UpdateConfig

# Create production instance
.\Setup-EntraIdApps.ps1 -SampleInstancePrefix "Prod-" -OutputFormat UpdateConfig

# Each instance creates isolated app registrations:
# - Dev-Orchestrator, Dev-OrderAPI, Dev-ShippingAPI, Dev-EmailAPI
# - Test-Orchestrator, Test-OrderAPI, Test-ShippingAPI, Test-EmailAPI
# - Prod-Orchestrator, Prod-OrderAPI, Prod-ShippingAPI, Prod-EmailAPI

"@

# ============================================
# Example 5: CI/CD Pipeline Integration
# ============================================
Write-Host "`n=== Example 5: CI/CD Pipeline Integration ===" -ForegroundColor Cyan
Write-Host @"
# In your CI/CD pipeline (e.g., GitHub Actions, Azure DevOps)

# Authenticate with service principal
`$clientId = `$env:AZURE_CLIENT_ID
`$clientSecret = `$env:AZURE_CLIENT_SECRET | ConvertTo-SecureString -AsPlainText -Force
`$tenantId = `$env:AZURE_TENANT_ID

`$credential = New-Object System.Management.Automation.PSCredential(`$clientId, `$clientSecret)
Connect-MgGraph -TenantId `$tenantId -ClientSecretCredential `$credential

# Run setup and export to file
.\Setup-EntraIdApps.ps1 -TenantId `$tenantId -SampleInstancePrefix "CI-" -OutputFormat Json | Out-File config.json

# Use the configuration
`$config = Get-Content config.json | ConvertFrom-Json
Write-Host "Tenant ID: `$(`$config.TenantId)"
Write-Host "Blueprint Client ID: `$(`$config.Blueprint.ClientId)"

"@

# ============================================
# Example 6: Export Configuration Only
# ============================================
Write-Host "`n=== Example 6: Export Configuration Only ===" -ForegroundColor Cyan
Write-Host @"
# Export configuration in different formats for documentation

# PowerShell variables (for local dev)
.\Setup-EntraIdApps.ps1 > setup-variables.ps1

# JSON format (for tooling)
.\Setup-EntraIdApps.ps1 -OutputFormat Json > setup-config.json

# Environment variables (for containers)
.\Setup-EntraIdApps.ps1 -OutputFormat EnvVars > setup-env.ps1

# ============================================
# Example 7: Verify Existing Setup (Idempotency)
# ============================================
Write-Host "`n=== Example 7: Verify Existing Setup ===" -ForegroundColor Cyan
Write-Host @"
# Run the script to verify existing configuration (idempotent)
.\Setup-EntraIdApps.ps1

# The script will:
# - Find existing applications
# - Verify they're configured correctly
# - Output current configuration values
# - Add a new secret to blueprint (old ones stay valid)

"@

# ============================================
# Example 8: Specific Tenant Setup
# ============================================
Write-Host "`n=== Example 8: Specific Tenant Setup ===" -ForegroundColor Cyan
Write-Host @"
# Target a specific tenant

`$tenantId = "your-tenant-id-here"

# Option 1: Let script connect
.\Setup-EntraIdApps.ps1 -TenantId `$tenantId

# Option 2: Connect first, then run
Connect-MgGraph -TenantId `$tenantId -Scopes "Application.ReadWrite.All","Directory.ReadWrite.All"
.\Setup-EntraIdApps.ps1

"@

# ============================================
# Example 9: Using with Docker Compose
# ============================================
Write-Host "`n=== Example 9: Using with Docker Compose ===" -ForegroundColor Cyan
Write-Host @"
# Generate .env file for Docker Compose

# Run setup and export to .env format
.\Setup-EntraIdApps.ps1 -OutputFormat EnvVars | Out-File .env

# Your docker-compose.yml can now use:
# environment:
#   - TENANT_ID=`${TENANT_ID}
#   - BLUEPRINT_CLIENT_ID=`${BLUEPRINT_CLIENT_ID}
#   - BLUEPRINT_CLIENT_SECRET=`${BLUEPRINT_CLIENT_SECRET}

"@

# ============================================
# Example 10: Regenerate Secret Only
# ============================================
Write-Host "`n=== Example 10: Regenerate Secret Only ===" -ForegroundColor Cyan
Write-Host @"
# If you need to rotate/regenerate the blueprint secret:

# Simply re-run the script (idempotent)
.\Setup-EntraIdApps.ps1

# This will:
# - Reuse existing applications
# - Add a new secret (old one remains valid)
# - Output the new secret value
# - Not duplicate any other resources

"@

# ============================================
# Example 11: Capture and Use Output
# ============================================
Write-Host "`n=== Example 11: Capture and Use Output ===" -ForegroundColor Cyan
Write-Host @"
# Capture JSON output and use it in your automation

`$setupOutput = .\Setup-EntraIdApps.ps1 -OutputFormat Json | ConvertFrom-Json

# Access values
`$tenantId = `$setupOutput.TenantId
`$blueprintClientId = `$setupOutput.Blueprint.ClientId
`$blueprintSecret = `$setupOutput.Blueprint.ClientSecret
`$orderClientId = `$setupOutput.Services.OrderAPI.ClientId

# Use in your application
Write-Host "Tenant: `$tenantId"
Write-Host "Blueprint: `$blueprintClientId"

# Or save to custom config file
`$customConfig = @{
    Azure = @{
        TenantId = `$tenantId
        ClientId = `$blueprintClientId
        ClientSecret = `$blueprintSecret
    }
}
`$customConfig | ConvertTo-Json -Depth 10 | Out-File custom-config.json

"@

# ============================================
# Example 12: Full Setup with Agent Identities
# ============================================
Write-Host "`n=== Example 12: Full Setup with Agent Identities ===" -ForegroundColor Cyan
Write-Host @"
# If your tenant has Agent Identities preview feature:

# Provide service account UPN for agent user identity
.\Setup-EntraIdApps.ps1 -ServiceAccountUpn "csr-agent@yourdomain.com"

# The script will:
# - Create Agent Identity Blueprint application
# - Configure inheritable permissions to downstream APIs
# - Provide detailed guidance for creating:
#   * Agent Identity Blueprint in Azure Portal
#   * Autonomous Agent Identity (for OrderService)
#   * Agent User Identity (for Shipping/EmailService)
# - Output configuration structure for manual completion


Write-Host "`n=== End of Examples ===" -ForegroundColor Cyan
Write-Host "`nFor more information, see README.md`n" -ForegroundColor Gray
