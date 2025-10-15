# Entra ID Setup Automation Script

This directory contains PowerShell automation scripts to simplify the setup of Microsoft Entra ID (formerly Azure AD) resources for the Customer Service Agent sample application.

## Overview

The `Setup-EntraIdApps.ps1` script automates the manual steps described in [02-entra-id-setup.md](../docs/setup/02-entra-id-setup.md), creating all required Entra ID app registrations, API permissions, and scopes in a single run.

### Key Features

- ✅ **Idempotent**: Safe to run multiple times without creating duplicates
- ✅ **Automated**: Creates all 5 app registrations and configures permissions
- ✅ **Flexible Output**: Supports multiple output formats (PowerShell, JSON, environment variables, or direct config update)
- ✅ **Error Handling**: Graceful error handling with actionable messages
- ✅ **Interactive & Non-Interactive**: Works with Graph PowerShell sign-in or tenant ID parameter

## Prerequisites

### Required Software

1. **PowerShell 7.x or higher** (recommended)
   - Download from: https://github.com/PowerShell/PowerShell/releases
   - Or use Windows PowerShell 5.1

2. **Microsoft.Graph PowerShell Module**
   ```powershell
   Install-Module Microsoft.Graph -Scope CurrentUser
   ```

### Required Permissions

You need one of the following roles in your Azure AD tenant:
- **Global Administrator** (recommended)
- **Application Administrator**
- **Cloud Application Administrator**

### Required Scopes

The script requests the following Microsoft Graph API permissions:
- `Application.ReadWrite.All` - Create and manage applications
- `Directory.ReadWrite.All` - Read and write directory data
- `AppRoleAssignment.ReadWrite.All` - Manage app role assignments

## Quick Start

### Interactive Mode (Recommended)

1. Open PowerShell and navigate to this directory:
   ```powershell
   cd dotnet/CustomerServiceAgent/scripts
   ```

2. Run the setup script:
   ```powershell
   .\Setup-EntraIdApps.ps1
   ```

3. Sign in when prompted with your Azure AD credentials

4. Review the output and copy the configuration values

### Update Config Files Automatically

To automatically update all `appsettings.json` files:

```powershell
.\Setup-EntraIdApps.ps1 -OutputFormat UpdateConfig
```

### Specify Tenant

If you want to target a specific tenant:

```powershell
.\Setup-EntraIdApps.ps1 -TenantId "your-tenant-id-here"
```

### Skip Agent Identities

If your tenant doesn't have the Agent Identities preview feature:

```powershell
.\Setup-EntraIdApps.ps1 -SkipAgentIdentities
```

## Usage Examples

### Example 1: Basic Setup with PowerShell Output

```powershell
.\Setup-EntraIdApps.ps1
```

**Output:**
```powershell
$TenantId = "a1b2c3d4-e5f6-g7h8-i9j0-k1l2m3n4o5p6"
$OrchestratorClientId = "11111111-2222-3333-4444-555555555555"
$OrchestratorClientSecret = "abc123..."
$OrderClientId = "22222222-3333-4444-5555-666666666666"
$CrmClientId = "33333333-4444-5555-6666-777777777777"
$ShippingClientId = "44444444-5555-6666-7777-888888888888"
$EmailClientId = "55555555-6666-7777-8888-999999999999"
```

### Example 2: JSON Output for Automation

```powershell
.\Setup-EntraIdApps.ps1 -OutputFormat Json
```

**Output:**
```json
{
  "TenantId": "a1b2c3d4-e5f6-g7h8-i9j0-k1l2m3n4o5p6",
  "Orchestrator": {
    "ClientId": "11111111-2222-3333-4444-555555555555",
    "ClientSecret": "abc123..."
  },
  "Services": {
    "OrderAPI": {
      "ClientId": "22222222-3333-4444-5555-666666666666"
    },
    ...
  }
}
```

### Example 3: Environment Variables

```powershell
.\Setup-EntraIdApps.ps1 -OutputFormat EnvVars
```

**Output:**
```powershell
$env:TENANT_ID = "a1b2c3d4-e5f6-g7h8-i9j0-k1l2m3n4o5p6"
$env:ORCHESTRATOR_CLIENT_ID = "11111111-2222-3333-4444-555555555555"
$env:ORCHESTRATOR_CLIENT_SECRET = "abc123..."
$env:ORDER_CLIENT_ID = "22222222-3333-4444-5555-666666666666"
$env:CRM_CLIENT_ID = "33333333-4444-5555-6666-777777777777"
$env:SHIPPING_CLIENT_ID = "44444444-5555-6666-7777-888888888888"
$env:EMAIL_CLIENT_ID = "55555555-6666-7777-8888-999999999999"
```

### Example 4: Direct Config File Update

```powershell
.\Setup-EntraIdApps.ps1 -OutputFormat UpdateConfig
```

This will update all `appsettings.json` files automatically with the generated values.

## Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `TenantId` | String | No | Current tenant | The Azure AD tenant ID to use |
| `OutputFormat` | String | No | `PowerShell` | Output format: `PowerShell`, `Json`, `EnvVars`, or `UpdateConfig` |
| `SkipAgentIdentities` | Switch | No | False | Skip Agent Identity creation |
| `ServiceAccountUpn` | String | No | None | UPN for agent user service account |

## What the Script Does

The script performs the following operations in order:

### 1. Connection (2 minutes)
- Connects to Microsoft Graph PowerShell
- Validates tenant access
- Requests required permissions

### 2. Create Applications (10 minutes)
Creates the following app registrations:
- ✅ `CustomerService-Orchestrator` (with client secret)
- ✅ `CustomerService-OrderAPI`
- ✅ `CustomerService-CrmAPI`
- ✅ `CustomerService-ShippingAPI`
- ✅ `CustomerService-EmailAPI`

### 3. Configure API Scopes (5 minutes)
For each service, configures:
- Application ID URI (e.g., `api://[client-id]`)
- OAuth2 permission scopes:
  - **OrderAPI**: `Orders.Read`
  - **CrmAPI**: `CRM.Read`
  - **ShippingAPI**: `Shipping.Read`, `Shipping.Write`
  - **EmailAPI**: `Email.Send`

### 4. Grant API Permissions (5 minutes)
- Configures the orchestrator app with permissions to call all downstream APIs
- Uses delegated (Scope) permissions for authentication flow

### 5. Grant Admin Consent (2 minutes)
- Automatically grants tenant-wide admin consent for all permissions
- Creates necessary service principals

### 6. Output Configuration (1 minute)
- Displays or writes configuration values in the selected format

**Total Time: ~25 minutes**

## Idempotency

The script is designed to be idempotent, meaning you can safely run it multiple times:

- **Existing apps**: If an app with the same name exists, it will be reused (not duplicated)
- **Existing scopes**: If a scope already exists, it will be preserved
- **Existing permissions**: If permissions are already granted, they won't be duplicated
- **Secrets**: A new secret is created each time (old secrets remain valid until expiry)

### When to Re-run

You should re-run the script if:
- ✅ Initial setup failed partway through
- ✅ You need to regenerate a client secret
- ✅ You want to verify configuration
- ✅ You need to update permissions

## Mapping to Manual Setup

This table maps script operations to manual setup steps in [02-entra-id-setup.md](../docs/setup/02-entra-id-setup.md):

| Manual Step | Script Operation | Function |
|-------------|------------------|----------|
| Step 1: Register Orchestrator | Automated | `Get-OrCreateApplication` |
| Step 2: Create Client Secret | Automated | `New-ApplicationSecret` |
| Step 3: Register Services | Automated | `Get-OrCreateApplication` |
| Step 4: Expose APIs | Automated | `Set-ApiScopes` |
| Step 5: Grant Permissions | Automated | `Grant-ApiPermissions` |
| Step 5: Admin Consent | Automated | `Grant-AdminConsent` |
| Step 6-8: Agent Identities | Manual* | See notes below |
| Step 9-10: Update Config | Automated with `-UpdateConfig` | `Update-ConfigFiles` |

\* Agent Identities are in preview and the API may not be available via Microsoft.Graph PowerShell yet. Create these manually via Azure Portal.

## Troubleshooting

### Error: "Connect-MgGraph: Insufficient privileges"

**Cause**: Your account doesn't have permission to create applications.

**Solution**: 
1. Contact your tenant administrator
2. Request Global Administrator or Application Administrator role
3. Or ask an admin to run the script for you

### Error: "Module 'Microsoft.Graph' not found"

**Cause**: Microsoft.Graph PowerShell module is not installed.

**Solution**:
```powershell
Install-Module Microsoft.Graph -Scope CurrentUser -Force
```

### Error: "Application already exists but cannot be retrieved"

**Cause**: Race condition or permission issue.

**Solution**:
1. Wait 30 seconds and try again
2. Check that you have read permissions on the application
3. Manually delete the partial application and re-run

### Warning: "Admin consent may need to be granted manually"

**Cause**: Your account lacks permission to grant admin consent.

**Solution**:
1. Sign in to [Azure Portal](https://portal.azure.com)
2. Navigate to **App registrations** → **CustomerService-Orchestrator**
3. Click **API permissions**
4. Click **Grant admin consent for [Your Tenant]**

### Agent Identity Blueprint creation skipped

**Cause**: Agent Identity Blueprints API is in preview and may not be available.

**Solution**:
1. Use the `-SkipAgentIdentities` flag
2. Create the blueprint manually following [02-entra-id-setup.md](../docs/setup/02-entra-id-setup.md) Part 3
3. Update configuration with blueprint and identity IDs

## Security Considerations

### Client Secrets

- ✅ Secrets are generated with 24-month expiration
- ✅ Store secrets securely (Azure Key Vault recommended for production)
- ✅ Never commit secrets to source control
- ✅ Rotate secrets regularly (every 90 days recommended)

### Permissions

- ✅ Script uses least-privilege approach
- ✅ Only requests necessary Graph API permissions
- ✅ Grants minimal permissions to applications

### Audit

- ✅ All operations are logged to Azure AD audit logs
- ✅ Review logs at: Azure Portal → Entra ID → Audit logs

## Next Steps

After running the script:

1. **Verify Configuration**
   ```powershell
   # Check that apps were created
   Get-MgApplication -Filter "startswith(displayName, 'CustomerService-')"
   ```

2. **Update Configuration** (if not using `-OutputFormat UpdateConfig`)
   - Copy the output values to your `appsettings.json` files
   - See [02-entra-id-setup.md](../docs/setup/02-entra-id-setup.md) Part 4

3. **Create Agent Identities** (if skipped)
   - Follow [02-entra-id-setup.md](../docs/setup/02-entra-id-setup.md) Part 3
   - Update configuration with IDs

4. **Test the Application**
   ```bash
   cd ../src
   dotnet build
   dotnet run --project CustomerServiceAgent.AppHost
   ```

## Advanced Usage

### Use in CI/CD Pipeline

For automated environments, use a service principal:

```powershell
# Authenticate with service principal
$clientId = $env:AZURE_CLIENT_ID
$clientSecret = $env:AZURE_CLIENT_SECRET | ConvertTo-SecureString -AsPlainText -Force
$tenantId = $env:AZURE_TENANT_ID

$credential = New-Object System.Management.Automation.PSCredential($clientId, $clientSecret)
Connect-MgGraph -TenantId $tenantId -ClientSecretCredential $credential

# Run setup
.\Setup-EntraIdApps.ps1 -TenantId $tenantId -OutputFormat Json > config.json
```

### Export Configuration to File

```powershell
.\Setup-EntraIdApps.ps1 -OutputFormat Json | Out-File -FilePath "../config.json"
```

### Integration with Other Scripts

```powershell
# Run setup and capture output
.\Setup-EntraIdApps.ps1 -OutputFormat Json | ConvertFrom-Json | ForEach-Object {
    # Use the configuration
    $tenantId = $_.TenantId
    $orchestratorClientId = $_.Orchestrator.ClientId
    # ... your automation ...
}
```

## Support

If you encounter issues:

1. Check the [Troubleshooting Guide](#troubleshooting) above
2. Review the [main setup documentation](../docs/setup/02-entra-id-setup.md)
3. Check the [repository issues](https://github.com/Azure-Samples/ms-identity-agent-identities/issues)
4. Create a new issue with:
   - PowerShell version (`$PSVersionTable`)
   - Microsoft.Graph module version (`Get-Module Microsoft.Graph`)
   - Error messages and stack trace
   - Steps to reproduce

## Contributing

Contributions are welcome! Please:
1. Test changes thoroughly
2. Update documentation
3. Follow existing code style
4. Add comments for complex logic

## License

This script is part of the ms-identity-agent-identities sample and follows the same license (MIT).

---

**Last Updated**: 2025-10-15  
**Version**: 1.0.0  
**Tested With**: 
- PowerShell 7.4+
- Microsoft.Graph 2.0+
- Windows, macOS, Linux
