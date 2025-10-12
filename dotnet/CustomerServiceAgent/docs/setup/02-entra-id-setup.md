# Azure AD / Entra ID Setup for Agent Identities

This guide walks you through configuring Microsoft Entra ID (formerly Azure AD) to use real Agent Identities with the Customer Service Agent sample.

> **Note:** This is optional. The sample works in demo mode with mock tokens. Follow this guide only if you want production-ready authentication.

---

## Overview

To enable Agent Identities, you need to:
1. Create app registrations for each service
2. Configure API permissions
3. Create an Agent Identity Blueprint
4. Create autonomous and agent user identities
5. Update appsettings.json files

**Time Required:** ~45 minutes  
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
| CRM Service | `CustomerService-CrmAPI` |
| Shipping Service | `CustomerService-ShippingAPI` |
| Email Service | `CustomerService-EmailAPI` |

For each:
1. **App registrations** → **New registration**
2. Configure name as shown above
3. **Register**
4. Note the **Application (client) ID**
5. No client secret needed (these are APIs, not clients)

### Step 4: Expose APIs

For **each downstream service** (Order, CRM, Shipping, Email):

1. Go to the app registration
2. Select **Expose an API**
3. Click **Add a scope**
4. **Application ID URI:** Accept default or customize (e.g., `api://customerservice-orders`)
5. **Save and continue**
6. Create scope:
   - **Scope name:** Based on service:
     - OrderService: `Orders.Read`
     - CrmService: `CRM.Read`
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

---

## Part 2: Configure API Permissions (10 minutes)

### Step 5: Grant Orchestrator Permissions to Downstream APIs

1. Go to **Orchestrator app registration**
2. Select **API permissions**
3. Click **Add a permission** → **My APIs**
4. For each downstream service:
   - Select the service (e.g., `CustomerService-OrderAPI`)
   - Check **Application permissions** (for autonomous agent)
   - Select the scopes (e.g., `Orders.Read`)
   - Click **Add permissions**
5. Repeat for all services
6. Click **Grant admin consent for [Your Tenant]**
7. Confirm by clicking **Yes**

**Result:** Orchestrator should have permissions to:
- `api://customerservice-orders/Orders.Read`
- `api://customerservice-crm/CRM.Read`
- `api://customerservice-shipping/Shipping.Read`
- `api://customerservice-shipping/Shipping.Write`
- `api://customerservice-email/Email.Send`

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
    "AutonomousAgentId": "YOUR_AUTONOMOUS_AGENT_ID",
    "AgentUserId": "YOUR_AGENT_USER_ID"
  },
  "Services": {
    "OrderService": "https://localhost:7001",
    "CrmService": "https://localhost:7002",
    "ShippingService": "https://localhost:7003",
    "EmailService": "https://localhost:7004"
  }
}
```

### Step 10: Update Downstream Service appsettings.json

For **each service** (Order, CRM, Shipping, Email):

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
// Uncomment these lines:
builder.Services.AddMicrosoftIdentityWebApiAuthentication(builder.Configuration, "AzureAd")
    .EnableTokenAcquisitionToCallDownstreamApi()
    .AddAgentIdentities(builder.Configuration);

// Comment out or remove the mock provider:
// builder.Services.AddSingleton<IAuthorizationHeaderProvider, MockAuthorizationHeaderProvider>();
```

#### Downstream Services (All Controllers)

Uncomment the `[Authorize]` and `[RequiredScope]` attributes:

```csharp
// Before (demo mode):
// [Authorize] // Commented for demo
// [RequiredScope("Orders.Read")]

// After (production):
[Authorize]
[RequiredScope("Orders.Read")]
```

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

4. **Check Aspire Dashboard logs** for:
   - Token acquisition from Azure AD
   - Successful authentication
   - No mock token warnings

---

## Verification Checklist

- [ ] All 5 app registrations created
- [ ] Client secret created for orchestrator
- [ ] APIs exposed with appropriate scopes
- [ ] Orchestrator has admin-consented permissions
- [ ] Agent Identity Blueprint created
- [ ] Autonomous agent identity created
- [ ] Agent user identity created
- [ ] All appsettings.json files updated
- [ ] Authentication code uncommented
- [ ] Solution builds successfully
- [ ] Sample runs with real Azure AD tokens

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
- Check token in https://jwt.ms - ensure it has correct audience and roles

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
