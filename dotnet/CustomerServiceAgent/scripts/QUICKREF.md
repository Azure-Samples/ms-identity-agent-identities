# Setup-EntraIdApps.ps1 - Quick Reference

## One-Line Commands

```powershell
# Most common: Interactive setup with config file updates
.\Setup-EntraIdApps.ps1 -SkipAgentIdentities -OutputFormat UpdateConfig

# Get PowerShell variables (default)
.\Setup-EntraIdApps.ps1 -SkipAgentIdentities

# Get JSON output
.\Setup-EntraIdApps.ps1 -SkipAgentIdentities -OutputFormat Json

# Get environment variables
.\Setup-EntraIdApps.ps1 -SkipAgentIdentities -OutputFormat EnvVars
```

## What Gets Created

| Resource | Name | Description |
|----------|------|-------------|
| **Orchestrator App** | CustomerService-Orchestrator | Main application with client secret |
| **Order API** | CustomerService-OrderAPI | Exposes `Orders.Read` scope |
| **CRM API** | CustomerService-CrmAPI | Exposes `CRM.Read` scope |
| **Shipping API** | CustomerService-ShippingAPI | Exposes `Shipping.Read`, `Shipping.Write` scopes |
| **Email API** | CustomerService-EmailAPI | Exposes `Email.Send` scope |

## Time Required

- **First run**: ~25 minutes
- **Subsequent runs** (idempotent): ~5 minutes

## Prerequisites Checklist

- [ ] PowerShell 7.x installed
- [ ] Microsoft.Graph module installed (`Install-Module Microsoft.Graph`)
- [ ] Global Administrator or Application Administrator role
- [ ] Azure AD tenant access

## Common Issues

| Error | Solution |
|-------|----------|
| "Module not found" | `Install-Module Microsoft.Graph -Scope CurrentUser` |
| "Insufficient privileges" | Get Global Admin or App Admin role |
| "Cannot connect" | Run `Connect-MgGraph` with required scopes first |
| "App already exists" | This is normal! Script is idempotent and will reuse it |

## What Happens on Re-run (Idempotency)

✅ **Reuses** existing applications (no duplicates)  
✅ **Reuses** existing scopes  
✅ **Reuses** existing permissions  
⚠️ **Creates** new client secret (old ones stay valid)

## Output Formats Explained

| Format | Use Case | Example |
|--------|----------|---------|
| **PowerShell** | Copy/paste into terminal | `$TenantId = "..."` |
| **Json** | CI/CD, automation | `{"TenantId": "..."}` |
| **EnvVars** | Container, Docker | `$env:TENANT_ID = "..."` |
| **UpdateConfig** | Direct file update | Updates `appsettings.json` |

## Verification Commands

```powershell
# Check apps were created
Get-MgApplication -Filter "startswith(displayName, 'CustomerService-')"

# Check orchestrator permissions
$orchestrator = Get-MgApplication -Filter "displayName eq 'CustomerService-Orchestrator'"
$orchestrator.RequiredResourceAccess

# Check service scopes
$orderService = Get-MgApplication -Filter "displayName eq 'CustomerService-OrderAPI'"
$orderService.Api.Oauth2PermissionScopes
```

## Next Steps After Running Script

1. ✅ **Review output** - Verify all client IDs were generated
2. ✅ **Update configs** - If not using `-OutputFormat UpdateConfig`, manually update appsettings.json files
3. ✅ **Create Agent Identities** - Follow manual steps in [02-entra-id-setup.md](../docs/setup/02-entra-id-setup.md) Part 3
4. ✅ **Test the app** - Run `dotnet run --project src/CustomerServiceAgent.AppHost`

## Security Reminders

- 🔒 **Never commit** client secrets to source control
- 🔒 **Store secrets** in Azure Key Vault (production)
- 🔒 **Rotate secrets** every 90 days
- 🔒 **Review permissions** regularly
- 🔒 **Monitor** Azure AD audit logs

## Links

- 📖 [Full README](README.md) - Complete documentation
- 🧪 [Testing Guide](TESTING.md) - Test scenarios
- 💡 [Examples](EXAMPLES.ps1) - Usage examples
- 📋 [Setup Documentation](../docs/setup/02-entra-id-setup.md) - Manual steps

## Support

Having issues? Check:
1. [Troubleshooting section in README.md](README.md#troubleshooting)
2. [Testing scenarios in TESTING.md](TESTING.md)
3. [GitHub Issues](https://github.com/Azure-Samples/ms-identity-agent-identities/issues)

---

**Version**: 1.0.0  
**Last Updated**: 2025-10-15
