# Test Suite for Setup-EntraIdApps.ps1

## Purpose
This document describes how to test the Setup-EntraIdApps.ps1 script for correctness and idempotency.

## Prerequisites for Testing

1. **Test Tenant**: Use a dedicated test/dev tenant, not production
2. **Permissions**: Global Administrator or Application Administrator role
3. **PowerShell 7.x**: For consistent testing
4. **Microsoft.Graph Module**: Latest version installed

## Test Scenarios

### Test 1: Basic Syntax and Structure Validation

**Purpose**: Verify script has valid PowerShell syntax and all required functions.

**Steps**:
```powershell
# From scripts directory
cd dotnet/CustomerServiceAgent/scripts

# Test syntax
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    'Setup-EntraIdApps.ps1', 
    [ref]$null, 
    [ref]$null
)
if ($ast) { 
    Write-Host "✓ Syntax valid" -ForegroundColor Green 
}

# Test help
$help = Get-Help .\Setup-EntraIdApps.ps1
if ($help.Synopsis -and $help.Examples) {
    Write-Host "✓ Help documentation complete" -ForegroundColor Green
}
```

**Expected**: No syntax errors, help documentation present.

---

### Test 2: Parameter Validation

**Purpose**: Ensure all parameters work correctly.

**Steps**:
```powershell
# Test valid OutputFormat values
.\Setup-EntraIdApps.ps1 -OutputFormat PowerShell -WhatIf   # Should work
.\Setup-EntraIdApps.ps1 -OutputFormat Json -WhatIf         # Should work
.\Setup-EntraIdApps.ps1 -OutputFormat EnvVars -WhatIf      # Should work
.\Setup-EntraIdApps.ps1 -OutputFormat UpdateConfig -WhatIf # Should work

# Test invalid OutputFormat
.\Setup-EntraIdApps.ps1 -OutputFormat Invalid -WhatIf      # Should fail with validation error
```

**Expected**: Valid values work, invalid value produces clear error message.

---

### Test 3: Clean Tenant Setup (First Run)

**Purpose**: Verify script creates all resources correctly in a clean tenant.

**Prerequisites**:
- Clean tenant with NO existing CustomerServiceSample-* applications
- Signed in to Graph PowerShell with required permissions

**Steps**:
```powershell
# Connect to test tenant
Connect-MgGraph -Scopes "Application.ReadWrite.All","Directory.ReadWrite.All","AppRoleAssignment.ReadWrite.All"

# Run setup
.\Setup-EntraIdApps.ps1 -SkipAgentIdentities

# Verify applications were created
Get-MgApplication -Filter "startswith(displayName, 'CustomerServiceSample-')"
```

**Expected Results**:
- ✅ 4 applications created:
  - CustomerServiceSample-Orchestrator (blueprint application)
  - CustomerServiceSample-OrderAPI
  - CustomerServiceSample-ShippingAPI
  - CustomerServiceSample-EmailAPI
- ✅ Each service has correct scopes configured
- ✅ Blueprint has client secret
- ✅ Blueprint has inheritable permissions to all downstream services
- ✅ Admin consent granted
- ✅ Configuration values displayed
- ✅ Guidance provided for manual Agent Identity Blueprint and agent identity creation

**Verification Commands**:
```powershell
# Check applications
$apps = Get-MgApplication -Filter "startswith(displayName, 'CustomerServiceSample-')"
Write-Host "Applications created: $($apps.Count)" -ForegroundColor Cyan

# Check orchestrator secret
$orchestrator = $apps | Where-Object { $_.DisplayName -eq 'CustomerServiceSample-Orchestrator' }
Write-Host "Orchestrator has $($orchestrator.PasswordCredentials.Count) secrets" -ForegroundColor Cyan

# Check service scopes
$orderService = $apps | Where-Object { $_.DisplayName -eq 'CustomerServiceSample-OrderAPI' }
Write-Host "Order service scopes: $($orderService.Api.Oauth2PermissionScopes.Value -join ', ')" -ForegroundColor Cyan

# Check permissions
Write-Host "Orchestrator permissions: $($orchestrator.RequiredResourceAccess.Count) resources" -ForegroundColor Cyan
```

---

### Test 4: Idempotency (Second Run)

**Purpose**: Verify script doesn't create duplicates when run multiple times.

**Prerequisites**:
- Completed Test 3 (applications already exist)
- Still connected to Graph PowerShell

**Steps**:
```powershell
# Count existing apps and secrets
$appsBefore = Get-MgApplication -Filter "startswith(displayName, 'CustomerServiceSample-')"
$orchestratorBefore = $appsBefore | Where-Object { $_.DisplayName -eq 'CustomerServiceSample-Orchestrator' }
$secretCountBefore = $orchestratorBefore.PasswordCredentials.Count

Write-Host "Before: $($appsBefore.Count) apps, $secretCountBefore secrets" -ForegroundColor Yellow

# Run setup again
.\Setup-EntraIdApps.ps1 -SkipAgentIdentities

# Count after
$appsAfter = Get-MgApplication -Filter "startswith(displayName, 'CustomerServiceSample-')"
$orchestratorAfter = $appsAfter | Where-Object { $_.DisplayName -eq 'CustomerServiceSample-Orchestrator' }
$secretCountAfter = $orchestratorAfter.PasswordCredentials.Count

Write-Host "After: $($appsAfter.Count) apps, $secretCountAfter secrets" -ForegroundColor Yellow
```

**Expected Results**:
- ✅ Application count stays at 5 (no duplicates)
- ✅ New secret added to orchestrator (count increases by 1)
- ✅ Scopes preserved on services
- ✅ Permissions preserved on orchestrator
- ✅ Script completes successfully with "Found existing app" messages

**Pass Criteria**:
```powershell
if ($appsBefore.Count -eq $appsAfter.Count -and 
    $secretCountAfter -eq ($secretCountBefore + 1)) {
    Write-Host "✓ Idempotency test PASSED" -ForegroundColor Green
} else {
    Write-Host "✗ Idempotency test FAILED" -ForegroundColor Red
}
```

---

### Test 5: Multiple Output Formats

**Purpose**: Verify all output formats work correctly.

**Steps**:
```powershell
# Test PowerShell output
.\Setup-EntraIdApps.ps1 -SkipAgentIdentities -OutputFormat PowerShell | Out-File output-ps.txt

# Test JSON output
.\Setup-EntraIdApps.ps1 -SkipAgentIdentities -OutputFormat Json | Out-File output-json.txt

# Test environment variables
.\Setup-EntraIdApps.ps1 -SkipAgentIdentities -OutputFormat EnvVars | Out-File output-env.txt

# Verify files contain expected content
Get-Content output-ps.txt | Select-String -Pattern '\$TenantId'
Get-Content output-json.txt | ConvertFrom-Json
Get-Content output-env.txt | Select-String -Pattern '\$env:'
```

**Expected Results**:
- ✅ PowerShell format: Contains variable assignments
- ✅ JSON format: Valid JSON with TenantId, Orchestrator, Services
- ✅ EnvVars format: Contains $env: variable assignments
- ✅ All formats contain same ClientId values

---

### Test 6: Config File Update

**Purpose**: Verify UpdateConfig mode correctly updates appsettings.json files.

**Prerequisites**:
- Backup existing appsettings.json files first!

**Steps**:
```powershell
# Backup configs
Copy-Item -Path "../src/AgentOrchestrator/appsettings.json" -Destination "../src/AgentOrchestrator/appsettings.json.backup"
Copy-Item -Path "../src/DownstreamServices/OrderService/appsettings.json" -Destination "../src/DownstreamServices/OrderService/appsettings.json.backup"

# Run with UpdateConfig
.\Setup-EntraIdApps.ps1 -SkipAgentIdentities -OutputFormat UpdateConfig

# Verify updates
$orchestratorConfig = Get-Content "../src/AgentOrchestrator/appsettings.json" | ConvertFrom-Json
Write-Host "Orchestrator TenantId: $($orchestratorConfig.AzureAd.TenantId)" -ForegroundColor Cyan
Write-Host "Orchestrator ClientId: $($orchestratorConfig.AzureAd.ClientId)" -ForegroundColor Cyan

# Restore backups after testing
Copy-Item -Path "../src/AgentOrchestrator/appsettings.json.backup" -Destination "../src/AgentOrchestrator/appsettings.json"
```

**Expected Results**:
- ✅ TenantId updated in all config files
- ✅ ClientId values updated correctly
- ✅ ClientSecret updated in orchestrator config
- ✅ Scopes updated with correct format (api://[clientid]/.default)
- ✅ Files remain valid JSON

---

### Test 7: Error Handling

**Purpose**: Verify script handles errors gracefully.

**Test 7a: No Graph Connection**
```powershell
# Disconnect from Graph
Disconnect-MgGraph

# Try to run script - should prompt for connection
.\Setup-EntraIdApps.ps1 -SkipAgentIdentities
```
**Expected**: Script prompts to connect or connects automatically.

**Test 7b: Insufficient Permissions**
```powershell
# Connect with limited permissions
Connect-MgGraph -Scopes "User.Read"

# Try to run script - should fail with clear error
.\Setup-EntraIdApps.ps1 -SkipAgentIdentities
```
**Expected**: Clear error message about insufficient permissions.

**Test 7c: Invalid Tenant ID**
```powershell
# Try with invalid tenant ID
.\Setup-EntraIdApps.ps1 -TenantId "invalid-guid" -SkipAgentIdentities
```
**Expected**: Clear error message about invalid tenant.

---

### Test 8: Agent Identities Flag

**Purpose**: Verify SkipAgentIdentities flag works correctly.

**Steps**:
```powershell
# Run with flag
.\Setup-EntraIdApps.ps1 -SkipAgentIdentities

# Run without flag
.\Setup-EntraIdApps.ps1
```

**Expected Results**:
- ✅ With flag: No Agent Identity operations attempted
- ✅ Without flag: Warning message about Agent Identities being manual
- ✅ Both runs complete successfully

---

## Cleanup After Testing

After testing is complete, clean up test resources:

```powershell
# Get all CustomerServiceSample apps
$apps = Get-MgApplication -Filter "startswith(displayName, 'CustomerServiceSample-')"

# Remove each app
foreach ($app in $apps) {
    Write-Host "Removing: $($app.DisplayName)" -ForegroundColor Yellow
    Remove-MgApplication -ApplicationId $app.Id
}

# Verify cleanup
$remaining = Get-MgApplication -Filter "startswith(displayName, 'CustomerServiceSample-')"
if ($remaining.Count -eq 0) {
    Write-Host "✓ Cleanup complete" -ForegroundColor Green
} else {
    Write-Host "✗ $($remaining.Count) apps remaining" -ForegroundColor Red
}
```

## Success Criteria Summary

The script passes all tests if:

- ✅ Syntax is valid
- ✅ Help documentation is complete
- ✅ All parameters work correctly
- ✅ Creates all 5 apps on first run
- ✅ Configures scopes correctly
- ✅ Grants permissions and admin consent
- ✅ Is idempotent (no duplicates on second run)
- ✅ All output formats work
- ✅ UpdateConfig mode updates files correctly
- ✅ Error handling is graceful
- ✅ Can run with and without Agent Identities

## Automated Test Script

You can run all non-interactive tests with:

```powershell
# Run from scripts directory
.\Test-SetupScript.ps1
```

(Note: Create this script if you need automated testing)

## Manual Validation

After running the script, manually verify in Azure Portal:

1. Navigate to **Entra ID** → **App registrations**
2. Find all CustomerServiceSample-* applications
3. Check each service has:
   - Correct Application ID URI
   - Correct scopes exposed
4. Check orchestrator has:
   - Valid client secret
   - Permissions to all services
   - Admin consent granted

## Reporting Issues

If you find issues during testing:

1. Note the exact error message
2. Include PowerShell version: `$PSVersionTable`
3. Include Graph module version: `Get-Module Microsoft.Graph`
4. Include steps to reproduce
5. Create an issue on GitHub

---

**Last Updated**: 2025-10-15  
**Test Environment**: PowerShell 7.4+, Microsoft.Graph 2.0+
