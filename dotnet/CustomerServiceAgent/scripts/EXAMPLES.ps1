# Example: Using Setup-EntraIdApps.ps1
# This script demonstrates common usage patterns

# ============================================
# Example 1: Basic Interactive Setup
# ============================================
Write-Host "`n=== Example 1: Basic Interactive Setup ===" -ForegroundColor Cyan
Write-Host "Connect to your tenant and run the setup script:`n"
Write-Host "  Connect-MgGraph -Scopes 'Application.ReadWrite.All','Directory.ReadWrite.All','AppRoleAssignment.ReadWrite.All'"
Write-Host "  .\Setup-EntraIdApps.ps1 -SkipAgentIdentities`n"

# ============================================
# Example 2: Automated Setup with Config Update
# ============================================
Write-Host "`n=== Example 2: Automated Setup with Config Update ===" -ForegroundColor Cyan
Write-Host "Automatically update all appsettings.json files:`n"
Write-Host "  .\Setup-EntraIdApps.ps1 -SkipAgentIdentities -OutputFormat UpdateConfig`n"

# ============================================
# Example 3: CI/CD Pipeline Integration
# ============================================
Write-Host "`n=== Example 3: CI/CD Pipeline Integration ===" -ForegroundColor Cyan
Write-Host @"
# In your CI/CD pipeline (e.g., GitHub Actions, Azure DevOps)

# Authenticate with service principal
`$clientId = `$env:AZURE_CLIENT_ID
`$clientSecret = `$env:AZURE_CLIENT_SECRET | ConvertTo-SecureString -AsPlainText -Force
`$tenantId = `$env:AZURE_TENANT_ID

`$credential = New-Object System.Management.Automation.PSCredential(`$clientId, `$clientSecret)
Connect-MgGraph -TenantId `$tenantId -ClientSecretCredential `$credential

# Run setup and export to file
.\Setup-EntraIdApps.ps1 -TenantId `$tenantId -OutputFormat Json -SkipAgentIdentities | Out-File config.json

# Use the configuration
`$config = Get-Content config.json | ConvertFrom-Json
Write-Host "Tenant ID: `$(`$config.TenantId)"
Write-Host "Orchestrator Client ID: `$(`$config.Orchestrator.ClientId)"

"@

# ============================================
# Example 4: Export Configuration Only
# ============================================
Write-Host "`n=== Example 4: Export Configuration Only ===" -ForegroundColor Cyan
Write-Host @"
# Export configuration in different formats for documentation

# PowerShell variables (for local dev)
.\Setup-EntraIdApps.ps1 -SkipAgentIdentities > setup-variables.ps1

# JSON format (for tooling)
.\Setup-EntraIdApps.ps1 -SkipAgentIdentities -OutputFormat Json > setup-config.json

# Environment variables (for containers)
.\Setup-EntraIdApps.ps1 -SkipAgentIdentities -OutputFormat EnvVars > setup-env.ps1

"@

# ============================================
# Example 5: Verify Existing Setup
# ============================================
Write-Host "`n=== Example 5: Verify Existing Setup ===" -ForegroundColor Cyan
Write-Host @"
# Run the script to verify existing configuration (idempotent)
.\Setup-EntraIdApps.ps1 -SkipAgentIdentities

# The script will:
# - Find existing applications
# - Verify they're configured correctly
# - Output current configuration values
# - Add a new secret to orchestrator (if needed)

"@

# ============================================
# Example 6: Specific Tenant Setup
# ============================================
Write-Host "`n=== Example 6: Specific Tenant Setup ===" -ForegroundColor Cyan
Write-Host @"
# Target a specific tenant

`$tenantId = "your-tenant-id-here"

# Option 1: Let script connect
.\Setup-EntraIdApps.ps1 -TenantId `$tenantId -SkipAgentIdentities

# Option 2: Connect first, then run
Connect-MgGraph -TenantId `$tenantId -Scopes "Application.ReadWrite.All","Directory.ReadWrite.All"
.\Setup-EntraIdApps.ps1 -SkipAgentIdentities

"@

# ============================================
# Example 7: Using with Docker Compose
# ============================================
Write-Host "`n=== Example 7: Using with Docker Compose ===" -ForegroundColor Cyan
Write-Host @"
# Generate .env file for Docker Compose

# Run setup and export to .env format
.\Setup-EntraIdApps.ps1 -SkipAgentIdentities -OutputFormat EnvVars | Out-File .env

# Your docker-compose.yml can now use:
# environment:
#   - TENANT_ID=`${TENANT_ID}
#   - ORCHESTRATOR_CLIENT_ID=`${ORCHESTRATOR_CLIENT_ID}
#   - ORCHESTRATOR_CLIENT_SECRET=`${ORCHESTRATOR_CLIENT_SECRET}

"@

# ============================================
# Example 8: Regenerate Secret Only
# ============================================
Write-Host "`n=== Example 8: Regenerate Secret Only ===" -ForegroundColor Cyan
Write-Host @"
# If you need to rotate/regenerate the orchestrator secret:

# Simply re-run the script (idempotent)
.\Setup-EntraIdApps.ps1 -SkipAgentIdentities

# This will:
# - Reuse existing applications
# - Add a new secret (old one remains valid)
# - Output the new secret value
# - Not duplicate any other resources

"@

# ============================================
# Example 9: Capture and Use Output
# ============================================
Write-Host "`n=== Example 9: Capture and Use Output ===" -ForegroundColor Cyan
Write-Host @"
# Capture JSON output and use it in your automation

`$setupOutput = .\Setup-EntraIdApps.ps1 -SkipAgentIdentities -OutputFormat Json | ConvertFrom-Json

# Access values
`$tenantId = `$setupOutput.TenantId
`$orchestratorClientId = `$setupOutput.Orchestrator.ClientId
`$orchestratorSecret = `$setupOutput.Orchestrator.ClientSecret
`$orderClientId = `$setupOutput.Services.OrderAPI.ClientId

# Use in your application
Write-Host "Tenant: `$tenantId"
Write-Host "Orchestrator: `$orchestratorClientId"

# Or save to custom config file
`$customConfig = @{
    Azure = @{
        TenantId = `$tenantId
        ClientId = `$orchestratorClientId
        ClientSecret = `$orchestratorSecret
    }
}
`$customConfig | ConvertTo-Json -Depth 10 | Out-File custom-config.json

"@

# ============================================
# Example 10: Full Setup with Agent Identities
# ============================================
Write-Host "`n=== Example 10: Full Setup with Agent Identities ===" -ForegroundColor Cyan
Write-Host @"
# If your tenant has Agent Identities preview feature:

# Run without SkipAgentIdentities flag
.\Setup-EntraIdApps.ps1 -ServiceAccountUpn "csr-agent@yourdomain.com"

# Note: Currently, Agent Identity API may not be available via PowerShell
# The script will guide you to create them manually in Azure Portal
# and output the configuration structure for you to fill in

"@

Write-Host "`n=== End of Examples ===" -ForegroundColor Cyan
Write-Host "`nFor more information, see README.md`n" -ForegroundColor Gray
