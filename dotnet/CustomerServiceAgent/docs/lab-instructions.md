# 30-Minute Hands-On Lab: Agent Identities with .NET Aspire

## Overview
In this lab, you'll explore how AI agents securely call downstream services using Agent Identities in Microsoft Entra ID, with full observability via .NET Aspire.

**Duration:** 30 minutes  
**Level:** Intermediate

## Prerequisites ✅
- .NET 9 SDK installed
- Visual Studio 2022 or VS Code with C# extension
- Basic understanding of ASP.NET Core and REST APIs

## Lab Objectives 🎯
By the end of this lab, you will:
1. Understand agent identity blueprints and agent identities
2. Run a multi-service application using .NET Aspire
3. Observe distributed tracing of token acquisition and API calls
4. Differentiate between autonomous and user-impersonating token patterns
5. Explore the Aspire Dashboard for observability

---

## Part 1: Setup (5 minutes)

### Step 1: Clone and Build
```bash
# Clone the repository
git clone https://github.com/Azure-Samples/ms-identity-agent-identities.git
cd ms-identity-agent-identities/dotnet/CustomerServiceAgent

# Build the solution
dotnet build
```

**Expected Output:** Build succeeded with 0 errors

### Step 2: Start the Aspire AppHost
```bash
dotnet run --project src/CustomerServiceAgent.AppHost
```

**Expected Output:**
```
Now listening on: https://localhost:15888
Aspire Dashboard is running
```

### Step 3: Open the Aspire Dashboard
1. Open your browser to `https://localhost:15888`
2. Explore the Dashboard:
   - **Resources** tab: See all 5 services running
   - **Console** tab: View aggregated logs
   - **Traces** tab: Distributed tracing (we'll use this soon)

---

## Part 2: Execute Orchestration (10 minutes)

### Step 4: Test Read-Only Operations (Autonomous Agent Identity)

**What's happening:** The orchestrator acquires an autonomous agent identity token to call Order and CRM services (read operations).

Open a new terminal and execute:
```bash
curl -X POST https://localhost:7000/api/customerservice/process \
  -H "Content-Type: application/json" \
  -d '{"orderId": "12345"}'
```

**Expected Response:**
```json
{
  "orderId": "12345",
  "status": "Completed",
  "orderDetails": { ... },
  "customerHistory": { ... },
  "messages": [
    "Fetching order details using autonomous agent identity...",
    "Order 12345 retrieved successfully",
    ...
  ]
}
```

### Step 5: Observe in Aspire Dashboard
1. Switch to the **Traces** tab in the Aspire Dashboard
2. Click on the latest trace for `agentorchestrator`
3. Expand the spans to see:
   - Token acquisition (MOCK in dev mode)
   - HTTP calls to OrderService
   - HTTP calls to CrmService
   - Response times for each operation

**💡 Key Insight:** Notice how the trace shows the entire request flow across all services.

### Step 6: Test Full Orchestration (Agent User Identity)

**What's happening:** With a `userUpn` provided, the orchestrator also performs write operations using agent user identity tokens.

```bash
curl -X POST https://localhost:7000/api/customerservice/process \
  -H "Content-Type: application/json" \
  -d '{"orderId": "12345", "userUpn": "agent@contoso.com"}'
```

**Expected Response:**
```json
{
  "orderId": "12345",
  "status": "Completed",
  "deliveryInfo": { ... },
  "emailSent": false,
  "messages": [
    ...
    "Updating delivery info using agent user identity...",
    "Sending email notification using agent user identity...",
    ...
  ]
}
```

### Step 7: Explore Logs
1. Go to the **Console** tab in Aspire Dashboard
2. Filter by service: Select "agentorchestrator"
3. Look for log messages:
   ```
   MOCK: Using mock authorization header for app
   Calling Order Service GET /api/orders/12345
   Successfully retrieved order 12345
   ```

4. Switch to "shippingservice" and look for:
   ```
   Updating delivery info for order 12345 by user Unknown
   ```

---

## Part 3: Code Exploration (10 minutes)

### Step 8: Autonomous Agent Identity Pattern
Open `src/AgentOrchestrator/Services/OrchestrationService.cs`:

```csharp
// Lines 40-60: Autonomous Agent Identity for read operations
public async Task<OrderDetails?> GetOrderDetailsAsync(string orderId)
{
    // In production with Agent Identities:
    // var authHeader = await _authorizationHeaderProvider
    //     .CreateAuthorizationHeaderForAppAsync(
    //         $"api://YOUR_ORDER_SERVICE_CLIENT_ID/.default",
    //         new AuthorizationHeaderProviderOptions().WithAgentIdentity(autonomousAgentId)
    //     );
    
    // Demo: Using mock token
    var authHeader = await _authorizationHeaderProvider
        .CreateAuthorizationHeaderForAppAsync(...);
    
    // Call downstream API with token
    httpClient.DefaultRequestHeaders.Authorization = 
        AuthenticationHeaderValue.Parse(authHeader);
}
```

**💡 Key Insight:** `.WithAgentIdentity(autonomousAgentId)` acquires an app-only token using the specified agent identity.

### Step 9: Agent User Identity Pattern
In the same file, scroll to line 100:

```csharp
// Lines 100-130: Agent User Identity for write operations
public async Task<DeliveryInfo?> UpdateDeliveryAsync(
    string orderId, DeliveryInfo updatedInfo, string userUpn)
{
    // In production with Agent Identities:
    // var authHeader = await _authorizationHeaderProvider
    //     .CreateAuthorizationHeaderForUserAsync(
    //         new[] { $"api://YOUR_SHIPPING_SERVICE_CLIENT_ID/.default" },
    //         new AuthorizationHeaderProviderOptions()
    //             .WithAgentUserIdentity(agentUserId, userUpn)
    //     );
}
```

**💡 Key Insight:** `.WithAgentUserIdentity(agentUserId, userUpn)` acquires a token with user context, suitable for operations requiring user identity.

### Step 10: Token Validation (Downstream Services)
Open `src/DownstreamServices/OrderService/Program.cs`:

```csharp
// Lines 10-11: Token validation configuration
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddMicrosoftIdentityWebApi(builder.Configuration, "AzureAd");
```

Open `src/DownstreamServices/OrderService/Controllers/OrdersController.cs`:

```csharp
// Lines 11-15: Authorization requirements
// [Authorize]  // Commented for demo - enable for production
[ApiController]
[Route("api/[controller]")]
// [RequiredScope("Orders.Read")]
```

**💡 Key Insight:** In production, uncomment these attributes and the service will validate tokens from Entra ID.

---

## Part 4: Observability Deep Dive (5 minutes)

### Step 11: Service Map
1. In Aspire Dashboard, click on the **Resources** tab
2. Select "View Details" for `agentorchestrator`
3. Observe the service dependencies:
   - `agentorchestrator` → `orderservice`
   - `agentorchestrator` → `crmservice`
   - `agentorchestrator` → `shippingservice`
   - `agentorchestrator` → `emailservice`

### Step 12: Metrics
1. Click on the **Metrics** tab
2. Select a service (e.g., `orderservice`)
3. View metrics:
   - HTTP request rate
   - Request duration (p50, p90, p99)
   - Error rate

---

## Cleanup

Stop the Aspire AppHost by pressing `Ctrl+C` in the terminal where it's running.

---

## Next Steps 🚀

### Enable Real Agent Identities
1. **Register applications in Azure AD** - Follow [Entra ID Setup Guide](setup/02-entra-id-setup.md)
2. **Create Agent Identity Blueprint** in your Microsoft Entra ID tenant
3. **Update appsettings.json** files with your configuration
4. **Uncomment** `[Authorize]` attributes in controllers
5. **Update Program.cs** in AgentOrchestrator to use real Microsoft Identity Web

### Add Microsoft Graph Integration
- Follow [Office 365 Dev Tenant Setup](setup/03-office365-dev-tenant.md)
- Uncomment Graph API calls in the orchestration service
- Send Teams messages and emails as part of the workflow

### Deploy to Azure
- Use Azure Container Apps with Aspire
- Configure Azure Key Vault for secrets
- Set up Azure Monitor for production observability

---

## Troubleshooting

**Issue:** Port already in use  
**Solution:** Change ports in `src/CustomerServiceAgent.AppHost/Program.cs`

**Issue:** Build errors related to SDK version  
**Solution:** Verify .NET 9 SDK is installed: `dotnet --version`

**Issue:** Aspire Dashboard not accessible  
**Solution:** Check console output for the correct URL, may be different than localhost:15888

For more issues, see [Troubleshooting Guide](troubleshooting.md).

---

## Summary

In this lab, you:
✅ Ran a multi-service application using .NET Aspire  
✅ Explored autonomous agent identity patterns (read operations)  
✅ Explored agent user identity patterns (write operations)  
✅ Observed distributed tracing and logs in Aspire Dashboard  
✅ Understood how to configure real Azure AD integration  

**Congratulations!** You've completed the Agent Identities with .NET Aspire lab.
