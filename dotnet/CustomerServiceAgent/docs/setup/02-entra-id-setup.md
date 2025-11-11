# Azure AD / Entra ID Setup for Agent Identities

This guide walks you through configuring Microsoft Entra ID (formerly Azure AD) to use real Agent Identities with the Customer Service Agent sample.

> **Note:** This is optional. The sample works in demo mode with mock tokens. Follow this guide only if you want production-ready authentication.

## 🚀 Quick Start: Automated Setup

**NEW!** Use our PowerShell automation script to complete steps 1-5 automatically:

```powershell
cd scripts
.\Setup-EntraIdApps.ps1 -OutputFormat UpdateConfig
```

This idempotent script creates all required app registrations, permissions, and configuration in ~25 minutes.  
📖 See [scripts/README.md](../../scripts/README.md) for detailed usage instructions.

> **Tip:** If you prefer manual setup or want to understand each step, continue with the instructions below.

---

## Overview

To enable Agent Identities, you need to:
1. Create app registrations for each service
2. Configure API permissions
3. Create an Agent Identity Blueprint
4. Create autonomous and agent user identities
5. Update appsettings.json files

**Time Required:** ~45 minutes (manual) or ~25 minutes (automated)  
**Prerequisites:** Azure subscription with Global Administrator role

---

## Part 1: Register Applications (20 minutes)

### Step 1: Register the Orchestrator Application

1. Navigate to [Azure Portal](https://portal.azure.com) → **Microsoft Entra ID** → **App registrations**
2. Click **New registration**
3. Configure:
   - **Name:** `CustomerService-Orchestrator`
   - **Supported account types:** Single tenant
   - **Redirect URI:** Leave blank
4. Click **Register**
5. Note the **Application (client) ID** and **Directory (tenant) ID**

### Step 2: Create Client Secret

1. In the orchestrator app registration, go to **Certificates & secrets**
2. Click **New client secret**
3. **Description:** `Orchestrator Secret`
4. **Expires:** 24 months (or per your policy)
5. Click **Add**
6. **Copy the secret value immediately** (it won't be shown again)

### Step 3: Register Downstream Service Applications

Repeat for each downstream service:

| Service | App Name |
|---------|----------|
| Order Service | `CustomerService-OrderAPI` |
| Shipping Service | `CustomerService-ShippingAPI` |
| Email Service | `CustomerService-EmailAPI` |

For each:
1. **App registrations** → **New registration**
2. Configure name as shown above
3. **Register**
4. Note the **Application (client) ID**
5. No client secret needed (these are APIs, not clients)

### Step 4: Expose APIs and App Roles

For **each downstream service** (Order, Shipping, Email):

1. Go to the app registration
2. Select **Expose an API**
3. Click **Add a scope**
4. **Application ID URI:** Accept default or customize (e.g., `api://customerservice-orders`)
5. **Save and continue**
6. Create scope:
   - **Scope name:** Based on service:
     - OrderService: `Orders.Read`
     - ShippingService: `Shipping.Read`, `Shipping.Write`
     - EmailService: `Email.Send`
   - **Who can consent:** Admins only
   - **Admin consent display name:** Descriptive name
   - **Admin consent description:** Descriptive text
   - **State:** Enabled
7. Click **Add scope**

**Example for Order Service:**
```
Scope name: Orders.Read
Display name: Read order data
Description: Allows the application to read order information
```

### Step 4a: Add App Roles (for autonomous agent access)

For **Order Service only** (required for autonomous agent identity):

1. Go to the Order Service app registration
2. Select **App roles**
3. Click **Create app role**
4. Configure:
   - **Display name:** `Read all orders`
   - **Allowed member types:** Applications
   - **Value:** `Orders.Read.All`
   - **Description:** `Allows the application to read all order information as an autonomous agent`
   - **Enable this app role:** Checked
5. Click **Apply**

> **Note:** App roles are used for app-only (autonomous agent) access, while scopes are used for delegated (user) access. The Order Service supports both patterns through a custom authorization policy.

---

## Part 2: Configure API Permissions (10 minutes)

### Step 5: Grant Orchestrator Permissions to Downstream APIs

1. Go to **Orchestrator app registration**
2. Select **API permissions**
3. Click **Add a permission** → **My APIs**
4. For each downstream service:
   - Select the service (e.g., `CustomerService-OrderAPI`)
   - For **Order Service**:
     - Check **Application permissions**
     - Select `Orders.Read.All` (for autonomous agent access)
   - For **Shipping and Email Services**:
     - Check **Delegated permissions**
     - Select the scopes (e.g., `Shipping.Read`, `Shipping.Write`, `Email.Send`)
   - Click **Add permissions**
5. Repeat for all services
6. Click **Grant admin consent for [Your Tenant]**
7. Confirm by clicking **Yes**

**Result:** Orchestrator should have permissions to:
- Application permission: `Orders.Read.All` (app role for Order Service)
- Delegated permissions:
  - `api://customerservice-shipping/Shipping.Read`
  - `api://customerservice-shipping/Shipping.Write`
  - `api://customerservice-email/Email.Send`

> **Note:** The automated setup script (`Setup-EntraIdApps.ps1`) handles both app role configuration and assignment automatically.

---

## Part 3: Create Agent Identity Blueprint (10 minutes)

> **Important:** Agent Identity Blueprints are currently in preview. Ensure your tenant has access to this feature.

### Step 6: Create Blueprint

1. Navigate to **Microsoft Entra ID** → **Identity Governance** (or search for "Agent Identities")
2. Select **Agent Identity Blueprints**
3. Click **New blueprint**
4. Configure:
   - **Name:** `CustomerServiceAgentBlueprint`
   - **Description:** `Blueprint for customer service agents`
5. Click **Create**
6. Note the **Blueprint ID**

### Step 7: Create Autonomous Agent Identity

1. In the blueprint, click **Create agent identity**
2. **Type:** Autonomous Agent
3. Configure:
   - **Name:** `CustomerServiceAutonomousAgent`
   - **Description:** `Autonomous agent for read operations`
4. Click **Create**
5. Note the **Agent Identity ID**

### Step 8: Create Agent User Identity

1. In the blueprint, click **Create agent identity**
2. **Type:** Agent User
3. Configure:
   - **Name:** `CustomerServiceAgentUser`
   - **Description:** `Agent user for write operations`
   - **Associated User:** Select or create a service account (e.g., `csr-agent@yourdomain.com`)
4. Click **Create**
5. Note the **Agent User Identity ID**

---

## Part 4: Update Configuration (5 minutes)

### Step 9: Update Orchestrator appsettings.json

Edit `src/AgentOrchestrator/appsettings.json`:

```json
{
  "AzureAd": {
    "Instance": "https://login.microsoftonline.com/",
    "TenantId": "YOUR_TENANT_ID",
    "ClientId": "YOUR_ORCHESTRATOR_CLIENT_ID",
    "ClientSecret": "YOUR_ORCHESTRATOR_CLIENT_SECRET"
  },
  "AgentIdentities": {
    "AgentIdentity": "YOUR_AUTONOMOUS_AGENT_ID",
    "AgentUserId": "YOUR_AGENT_USER_ID"
  },
  "Services": {
    "OrderService": "https://localhost:7001",
    "ShippingService": "https://localhost:7003",
    "EmailService": "https://localhost:7004"
  }
}
```

### Step 10: Update Downstream Service appsettings.json

For **each service** (Order, Shipping, Email):

Edit `src/DownstreamServices/[ServiceName]/appsettings.json`:

```json
{
  "AzureAd": {
    "Instance": "https://login.microsoftonline.com/",
    "TenantId": "YOUR_TENANT_ID",
    "ClientId": "YOUR_SERVICE_CLIENT_ID",
    "Audience": "api://YOUR_SERVICE_CLIENT_ID"
  }
}
```

**Example for Order Service:**
```json
{
  "AzureAd": {
    "Instance": "https://login.microsoftonline.com/",
    "TenantId": "a1b2c3d4-e5f6-g7h8-i9j0-k1l2m3n4o5p6",
    "ClientId": "11111111-2222-3333-4444-555555555555",
    "Audience": "api://11111111-2222-3333-4444-555555555555"
  }
}
```

### Step 11: Enable Authentication in Code

#### Orchestrator (src/AgentOrchestrator/Program.cs)

Uncomment the authentication configuration:

```csharp
// Use this pattern:
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddMicrosoftIdentityWebApi(builder.Configuration, "AzureAd")
        .EnableTokenAcquisitionToCallDownstreamApi()
        .AddInMemoryTokenCaches();

builder.Services.AddAgentIdentities();
```

#### Downstream Services

**Order Service** uses the `RequiredScopeOrAppPermission` attribute from Microsoft.Identity.Web to support both delegated and application permissions:

```csharp
// Order Service supports both app roles and scopes
[Authorize]
[RequiredScopeOrAppPermission(
    AcceptedScope = new[] { "Orders.Read" },
    AcceptedAppPermission = new[] { "Orders.Read.All" }
)]
[ApiController]
[Route("api/[controller]")]
public class OrdersController : ControllerBase
{
    // ... controller implementation
}
```

This allows the Order Service to accept:
- **Delegated permission:** `scp` claim containing `Orders.Read` (user context)
- **Application permission:** `roles` claim containing `Orders.Read.All` (app-only context)

**Other Services** (Shipping, Email) continue to use `[RequiredScope]` for delegated permissions only.

---

## Part 5: Test the Configuration (5 minutes)

### Step 12: Run and Test

1. **Build the solution:**
   ```bash
   dotnet build
   ```

2. **Start the AppHost:**
   ```bash
   dotnet run --project src/CustomerServiceAgent.AppHost
   ```

3. **Test with authentication:**
   ```bash
   curl -X POST https://localhost:7000/api/customerservice/process \
     -H "Content-Type: application/json" \
     -d '{"orderId": "12345", "userUpn": "csr-agent@yourdomain.com"}'
   ```

4. **Verify app role in token:**
   - Capture the access token used to call Order Service (check logs)
   - Decode it at https://jwt.ms
   - Verify the `roles` claim contains `Orders.Read.All`

5. **Check Aspire Dashboard logs** for:
   - Token acquisition from Azure AD
   - Successful authentication with app role
   - Order Service accepting the token
   - No mock token warnings

---

## Verification Checklist

- [ ] All 5 app registrations created
- [ ] Client secret created for orchestrator
- [ ] APIs exposed with appropriate scopes
- [ ] Order API has `Orders.Read.All` app role defined
- [ ] Orchestrator has admin-consented permissions (including app role assignment)
- [ ] Agent Identity Blueprint created
- [ ] Autonomous agent identity created
- [ ] Agent user identity created
- [ ] All appsettings.json files updated
- [ ] Authentication code uncommented
- [ ] Solution builds successfully
- [ ] Sample runs with real Azure AD tokens
- [ ] App role appears in access token for Order Service

---

## Troubleshooting

### Error: AADSTS700016 (Application not found)
- Verify ClientId in appsettings.json matches app registration
- Ensure you're using the correct tenant

### Error: AADSTS65001 (User consent required)
- Grant admin consent in API permissions
- Ensure permissions are application-level, not delegated

### Error: 401 Unauthorized from downstream service
- Verify Audience in service appsettings.json
- Check token in https://jwt.ms - ensure it has correct audience and roles/scopes
- For Order Service specifically:
  - Autonomous agent tokens should have `roles` claim with `Orders.Read.All`
  - User tokens should have `scp` claim with `Orders.Read`

### Error: Missing app role in token
- Verify app role `Orders.Read.All` is defined in Order API app registration
- Ensure orchestrator service principal has the app role assigned
- Check API permissions blade for the orchestrator - should show granted app role
- Wait a few minutes for Azure AD to propagate the assignment

### Error: Agent Identity not found
- Verify Agent Identity Blueprint is created
- Check that Agent Identity IDs in configuration are correct
- Ensure your tenant has Agent Identities feature enabled

---

## Security Best Practices

✅ **Use Key Vault** for storing client secrets in production  
✅ **Rotate secrets** regularly (every 90 days recommended)  
✅ **Limit permissions** to minimum required (least privilege)  
✅ **Monitor** authentication logs in Azure AD  
✅ **Enable Conditional Access** for additional security  
✅ **Use managed identities** when deploying to Azure  

---

## Next Steps

- **[Configure Microsoft Graph](03-office365-dev-tenant.md)** - Add Teams and Outlook integration
- **[Deploy to Azure](../../README.md)** - Run in production environment
- **[Monitor and Optimize](../../docs/troubleshooting.md)** - Production monitoring

---

**Last Updated:** 2025-01-12  
**Applies To:** Microsoft Entra ID with Agent Identities (Preview)
