# Customer Service Agent Sample - Agent Identities with .NET Aspire

[![.NET 9](https://img.shields.io/badge/.NET-9.0-purple)](https://dot.net)
[![Aspire 9.0](https://img.shields.io/badge/Aspire-9.0-blue)](https://learn.microsoft.com/dotnet/aspire/)
[![Microsoft Identity Web](https://img.shields.io/badge/Identity.Web-4.0.0-green)](https://github.com/AzureAD/microsoft-identity-web)

A comprehensive sample demonstrating how AI agents securely call downstream services using **Agent Identities** in Microsoft Entra ID. This Customer Service Orchestration Agent showcases realistic business scenarios where an agent orchestrates multiple downstream APIs using both autonomous agent identities and agent user identities, all with full observability via .NET Aspire.

## 🎯 Overview

This sample illustrates:
- **Autonomous Agent Identity** (Order API - read operations with app role-based access control)
- **Agent User Identities** with user context (Shipping & Email APIs - write operations)  
- **App Role-Based Authorization** - Order API accepts both delegated permissions (`Orders.Read`) and application permissions (`Orders.Read.All`)
- **.NET Aspire Dashboard** - Distributed tracing, logs, metrics, and service map
- **Service Discovery** - Dynamic service resolution via Aspire
- **In-Memory Stores** - Simple demonstration without external dependencies

## 🏗️ Architecture

```mermaid
graph TB
    subgraph "Aspire AppHost"
        AppHost[AppHost Project<br/>Orchestrates all services]
        Dashboard[Aspire Dashboard<br/>Traces, Logs, Metrics]
    end
    
    subgraph "Application Services"
        Orchestrator[Agent Orchestrator API<br/>CustomerServiceController]
        OrderAPI[Order Service API<br/>In-memory order store]
        ShippingAPI[Shipping Service API<br/>In-memory delivery management]
        EmailAPI[Email Service API<br/>Mock email sender]
    end
    
    subgraph "External Services"
        EntraID[Microsoft Entra ID<br/>Token Acquisition & Validation]
    end
    
    AppHost -->|Configures & Starts| Orchestrator
    AppHost -->|Configures & Starts| OrderAPI
    AppHost -->|Configures & Starts| ShippingAPI
    AppHost -->|Configures & Starts| EmailAPI
    
    Dashboard -.->|Observes Telemetry| Orchestrator
    Dashboard -.->|Observes Telemetry| OrderAPI
    Dashboard -.->|Observes Telemetry| ShippingAPI
    Dashboard -.->|Observes Telemetry| EmailAPI
    
    Orchestrator -->|Service Discovery| OrderAPI
    Orchestrator -->|Service Discovery| ShippingAPI
    Orchestrator -->|Service Discovery| EmailAPI
    
    Orchestrator -->|Acquire Token| EntraID
    OrderAPI -->|Validate Token| EntraID
    ShippingAPI -->|Validate Token| EntraID
    EmailAPI -->|Validate Token| EntraID
    
    style AppHost fill:#512BD4,color:#fff
    style Dashboard fill:#512BD4,color:#fff
    style Orchestrator fill:#0078D4,color:#fff
    style EntraID fill:#00BCF2,color:#000
```

## 🚀 Quick Start

### Prerequisites

- [.NET 9 SDK](https://dotnet.microsoft.com/download/dotnet/9.0)
- [Visual Studio 2022](https://visualstudio.microsoft.com/) or [VS Code](https://code.visualstudio.com/) with C# extension
- *(Optional)* [Microsoft 365 Developer account](https://developer.microsoft.com/microsoft-365/dev-program) for Graph API integration

### Run the Sample

1. **Clone the repository**
   ```bash
   git clone https://github.com/Azure-Samples/ms-identity-agent-identities.git
   cd ms-identity-agent-identities/dotnet/CustomerServiceAgent
   ```

2. **Build the solution**
   ```bash
   dotnet build
   ```

3. **Run with .NET Aspire**
   ```bash
   dotnet run --project src/CustomerServiceAgent.AppHost
   ```

4. **Access the Aspire Dashboard**
   - Open your browser to `https://localhost:15888` (or the URL shown in the console)
   - Explore the service map, traces, logs, and metrics

5. **Test the orchestration**
   ```bash
   # Using curl
   curl -X POST https://localhost:7000/api/customerservice/process \
     -H "Content-Type: application/json" \
     -d '{"orderId": "12345", "userUpn": "agent@contoso.com"}'
   
   # Or use the .http file in VS Code
   # Open: src/AgentOrchestrator/AgentOrchestrator.http
   ```

   Note that this endpoint is on purpose anonymous, so that you can more easily test things out. In production you would need to uncomment the [Authorize] attribute on the endpoint.

## 🔐 Setting Up Agent Identities (Visual Studio)

To enable real Agent Identities in Microsoft Entra ID for this sample, follow these steps to create agent blueprints, downstream API registrations, and runtime agent identities.

### 1. Script Setup: Create Entra ID App Registrations

Before running the sample with real agent identities, you need to register applications in Microsoft Entra ID.

**Run the setup script** from the `scripts` directory:

```powershell
cd scripts
.\Setup-EntraIdApps.ps1 -TenantId <your-tenant-id> -OutputFormat UpdateConfig
```

**What this script creates:**
- **Agent Identity Blueprint** (`CustomerServiceSample-Orchestrator`) - The orchestrator application that serves as the blueprint for creating agent identities
- **Downstream API Registrations** - Three service app registrations:
  - `CustomerServiceSample-OrderAPI` (read operations with app role)
  - `CustomerServiceSample-ShippingAPI` (write operations with user context)
  - `CustomerServiceSample-EmailAPI` (write operations with user context)
- **API Permissions & Scopes** - Configured inheritable permissions for all downstream APIs
- **Client Secrets** - Secure credentials for the blueprint application

**Configuration updates:**
- The script automatically updates all `appsettings.json` files with the generated Client IDs, Tenant ID, and secrets
- Configuration values are placed in:
  - `src/AgentOrchestrator/appsettings.json`
  - `src/DownstreamServices/OrderService/appsettings.json`
  - `src/DownstreamServices/ShippingService/appsettings.json`
  - `src/DownstreamServices/EmailService/appsettings.json`

📖 **For detailed script documentation**, see [scripts/README.md](scripts/README.md)  
📖 **For manual setup instructions**, see [Entra ID Setup Guide](docs/setup/02-entra-id-setup.md)

### 2. Starting the Sample in Visual Studio

1. **Open the solution** in Visual Studio:
   ```bash
   cd dotnet/CustomerServiceAgent
   devenv CustomerServiceAgent.sln
   ```
   
   Or use **File → Open → Project/Solution** and select `CustomerServiceAgent.sln`

2. **Build the solution**:
   - Press `Ctrl+Shift+B` or select **Build → Build Solution**

3. **Set the startup project**:
   - Right-click `CustomerServiceAgent.AppHost` in Solution Explorer
   - Select **Set as Startup Project**

4. **Run the application**:
   - Press `F5` or select **Debug → Start Debugging**
   - The Aspire Dashboard will open in your browser (typically at `https://localhost:15888`)

5. **Observe the Aspire Dashboard**:
   - Navigate to **Resources** to see all running services
   - Go to **Traces** and select the **AgentOrchestrator** resource to view distributed traces

### 3. Runtime Agent Creation: Using the .http File

With the application running, you'll create agent identities at runtime using the `/api/agentidentity` endpoint.

1. **Open the HTTP request file** in Visual Studio:
   - In Solution Explorer, navigate to `src/AgentOrchestrator/AgentOrchestrator.http`
   - Double-click to open it in the editor

2. **Update the tenant name** (first time only):
   - Find the line: `@TenantName=YOURDOMAIN.onmicrosoft.com`
   - Replace `YOURDOMAIN` with your actual tenant name
   - Example: `@TenantName=contoso.onmicrosoft.com`

3. **Execute the first request** to create agent identities:
   - Locate the `POST {{AgentOrchestrator_HostAddress}}/api/agentidentity` request
   - Click the **"Send request"** link that appears above the request (Visual Studio 2022 17.6+)
   - Alternatively, press `Ctrl+Alt+H` while the cursor is on the request

4. **Understand the response**:
   The API returns JSON with several important values:
   
   ```json
   {
     "agentIdentity": {
       "id": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"  // 👈 Copy this GUID
     },
     "adminConsentUrlScopes": "https://login.microsoftonline.com/.../adminconsent?...",
     "adminConsentUrlRoles": "https://login.microsoftonline.com/.../adminconsent?..."
   }
   ```

5. **Copy the agent identity ID**:
   - From the response pane, copy the `agentIdentity.id` value (a GUID)
   - In the `AgentOrchestrator.http` file, replace `RESULT_FROM_FIRST_REQUEST` on line 3:
     ```
     @AgentIdentity=<paste-the-guid-here>
     ```

### 4. Admin Consent Flow: Granting Permissions

The agent identities require admin consent to access downstream APIs on behalf of the agent.

1. **Copy the consent URLs** from the previous API response:
   - `adminConsentUrlScopes` - For delegated permissions (user context)
   - `adminConsentUrlRoles` - For application permissions (app-only context)

2. **Grant admin consent**:
   - Open each URL in your browser
   - Sign in as a **Tenant Administrator** (Global Admin or Application Admin role required)
   - Review the requested permissions
   - Click **Accept** to grant consent

3. **Why admin consent is needed**:
   - Agent identities inherit permissions from the blueprint but require explicit consent
   - Delegated permissions (`Orders.Read`, `Shipping.Write`, `Email.Send`) enable the agent to act with user context
   - Application permissions (`Orders.Read.All`) enable autonomous agent operations without user context

📖 **For more details on agent identities**, see [Agent Identities Documentation](https://github.com/AzureAD/microsoft-identity-web/blob/main/src/Microsoft.Identity.Web.AgentIdentities/README.AgentIdentities.md)

### 5. Testing the Full Flow: End-to-End Orchestration

Now that your agent identity is configured and consented, test the complete workflow.

1. **Execute the customer service process request**:
   - In `AgentOrchestrator.http`, find the second request: `POST {{AgentOrchestrator_HostAddress}}/api/customerservice/process`
   - Ensure `@AgentIdentity` contains your copied GUID from step 3
   - Ensure `@TenantName` is correct
   - Click **"Send request"** or press `Ctrl+Alt+H`

2. **Review the request payload**:
   ```json
   {
     "OrderId": "12345",
     "UserUpn": "agentuser1@yourtenant.onmicrosoft.com",
     "AgentIdentity": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
   }
   ```
   - `OrderId`: The order to process (exists in the in-memory store)
   - `UserUpn`: The agent user identity UPN created by the `/api/agentidentity` endpoint
   - `AgentIdentity`: The agent identity GUID you copied earlier

3. **Confirm orchestration using Aspire Dashboard traces**:
   - Switch to the Aspire Dashboard in your browser (`https://localhost:15888`)
   - Navigate to **Traces**
   - Filter by **AgentOrchestrator** resource
   - Observe the distributed trace showing:
     - Token acquisition using the agent identity
     - Call to OrderService (autonomous agent identity with app role)
     - Call to ShippingService (agent user identity with user context)
     - Call to EmailService (agent user identity with user context)
   
4. **Expected successful response**:
   ```json
   {
     "message": "Customer service request processed successfully",
     "orderId": "12345",
     "details": {
       "orderRetrieved": true,
       "shippingUpdated": true,
       "emailSent": true
     }
   }
   ```

**Troubleshooting tips:**
- If you get authentication errors, verify admin consent was granted for both URLs
- If services return 401/403, check that the Entra ID apps were created correctly by the script
- If agent identity is not found, ensure the GUID is correct in the `@AgentIdentity` variable
- Review the Aspire Dashboard logs for detailed error messages

📖 **For common issues and solutions**, see [Troubleshooting Guide](docs/troubleshooting.md)

## 📁 Project Structure

```
CustomerServiceAgent/
├── README.md                              # This file
├── CustomerServiceAgent.sln               # Solution file
├── docs/
│   ├── lab-instructions.md                # 30-minute hands-on lab
│   ├── architecture.md                    # Deep dive architecture
│   ├── troubleshooting.md                 # Common issues & solutions
│   └── setup/
│       ├── 01-prerequisites.md
│       ├── 02-entra-id-setup.md
│       ├── 03-office365-dev-tenant.md
│       └── 04-appsettings-configuration.md
└── src/
    ├── CustomerServiceAgent.AppHost/      # Aspire orchestration
    ├── CustomerServiceAgent.ServiceDefaults/  # Shared Aspire config
    ├── AgentOrchestrator/                 # Main orchestrator service
    │   ├── Controllers/
    │   │   └── CustomerServiceController.cs
    │   ├── Services/
    │   │   └── OrchestrationService.cs    # Agent identity token acquisition
    │   └── appsettings.json
    ├── DownstreamServices/
    │   ├── OrderService/                  # Read operations (autonomous)
    │   ├── ShippingService/               # Write operations (agent user)
    │   └── EmailService/                  # Write operations (agent user)
    └── Shared/
        └── Models/                        # Common DTOs
```

## 🔑 Key Features

### 1. Autonomous Agent Identity with App Roles (Read Operations)
```csharp
// OrderService uses autonomous agent identity with app role-based access
var authHeader = await _authorizationHeaderProvider
    .CreateAuthorizationHeaderForAppAsync(
        $"api://YOUR_SERVICE_CLIENT_ID/.default",
        new AuthorizationHeaderProviderOptions().WithAgentIdentity(autonomousAgentId)
    );
```

The Order Service uses `RequiredScopeOrAppPermission` attribute to accept both scopes and app roles:
```csharp
// Accepts both delegated permissions (scopes) and application permissions (app roles)
[Authorize]
[RequiredScopeOrAppPermission(
    AcceptedScope = new[] { "Orders.Read" },
    AcceptedAppPermission = new[] { "Orders.Read.All" }
)]
public class OrdersController : ControllerBase
```

### 2. Agent User Identity (Write Operations)
```csharp
// Shipping and Email services use agent user identity with user context
var authHeader = await _authorizationHeaderProvider
    .CreateAuthorizationHeaderForUserAsync(
        new[] { $"api://YOUR_SERVICE_CLIENT_ID/.default" },
        new AuthorizationHeaderProviderOptions().WithAgentUserIdentity(agentUserId, userUpn)
    );
```

### 3. Token Validation
```csharp
// All downstream services validate tokens
builder.Services.AddMicrosoftIdentityWebApiAuthentication(
    builder.Configuration, "AzureAd");
```

### 4. Distributed Tracing
All API calls are automatically traced and visible in the Aspire Dashboard.

## 📚 Documentation

- **[Lab Instructions](docs/lab-instructions.md)** - 30-minute hands-on lab
- **[Architecture Deep Dive](docs/architecture.md)** - Detailed design decisions
- **[Entra ID Setup](docs/setup/02-entra-id-setup.md)** - Configure agent identities
- **[Troubleshooting](docs/troubleshooting.md)** - Common issues and solutions

## 🔧 Configuration

### Production Mode (Azure AD)
To enable real Agent Identities:

1. **Register the downstream APIs in Azure AD** (see [Entra ID Setup](docs/setup/02-entra-id-setup.md))
2. **Create Agent Identity Blueprint** in your tenant
3. **Update appsettings.json** with your tenant and client IDs
4. **Configure Program.cs** to use real Microsoft Identity Web services

### Configuration Fields in appsettings.json

The `src/AgentOrchestrator/appsettings.json` file contains the following key configuration sections:

#### Agent Identities Configuration
```json
"AgentIdentities": {
  "AgentIdentity": "YOUR_AGENT_IDENTITY_ID",
  "AgentUserId": "YOUR_AGENT_USER_ID",
  "SponsorUserId": "HUMAN_SPONSOR_USER_ID"
}
```

- **`AgentIdentity`**: The default agent identity used to call Order Service when no `AgentIdentity` parameter is provided in `CustomerService/process`.
- **`AgentUserId`**: The Object ID of the agent user identity used by default for operations requiring user context (e.g., Shipping, Email services), when no `UserUpn` parameter is provided in `CustomerService/process`
- **`SponsorUserId`** (Required): The Object ID of the human user who sponsors/manages the agent identities. This is typically the user running the setup script or the person responsible for the agent's operations. It's needed when calling `POST /AgentIdentity` to create the agent identity (and agent user name)

#### Microsoft Graph Scopes Format
```json
"DownstreamApis": {
  "MicrosoftGraph": {
    "BaseUrl": "https://graph.microsoft.com/v1.0",
    "Scopes": "User.Read Mail.Send ChannelMessage.Send"
  }
}
```

**Note**: Microsoft Graph scopes use a **space-delimited string** format (e.g., `"User.Read Mail.Send"`), while other downstream services use an **array format** (e.g., `["api://SERVICE_ID/.default"]`). This is due to the Microsoft Graph SDK requirements.

To add additional Graph permissions:
1. Add the scope name to the space-delimited string (e.g., `"User.Read Mail.Send Files.Read"`)
2. Ensure your app registration has been granted these permissions
3. See [Microsoft Graph Permissions Reference](https://learn.microsoft.com/graph/permissions-reference) for available scopes

## 🧪 Testing Scenarios

### Scenario 1: Agent Identity
```json
POST /api/customerservice/process
{
  "orderId": "12345",
  "agentIdentity": "YOUR_AGENT_IDENTITY_ID"
}
```
**Expected:** Order retrieved using agent identity.

### Scenario 2: Full Orchestration (Agent User Identity)
```json
POST /api/customerservice/process
{
  "orderId": "12345",
  "userUpn": "agent@contoso.com",
  "agentIdentity": "YOUR_AGENT_USER_ID"
}
```
**Expected:** All operations complete, including shipping update and email notification using agent user identity.

## 📊 Observability

The Aspire Dashboard (`https://localhost:15888`) provides:
- **Traces** - End-to-end request flows across services
- **Logs** - Aggregated logs from all services with filtering
- **Metrics** - HTTP request rates, durations, error rates
- **Service Map** - Visual representation of service dependencies
- **Health Checks** - Real-time service health status

## 🌟 What's Next?

- **[Add Microsoft Graph integration](docs/setup/03-office365-dev-tenant.md)** - Send Teams messages and emails
- **Deploy to Azure** - Use Azure Container Apps with Aspire
- **Add resilience patterns** - Implement retry policies and circuit breakers
- **Expand agent scenarios** - Add more autonomous vs. user-delegated patterns

## 📖 Resources

- [Agent Identities Documentation](https://github.com/AzureAD/microsoft-identity-web/blob/main/src/Microsoft.Identity.Web.AgentIdentities/README.AgentIdentities.md)
- [.NET Aspire Documentation](https://learn.microsoft.com/dotnet/aspire/)
- [Microsoft Graph SDK](https://learn.microsoft.com/graph/sdks/sdks-overview)
- [Microsoft Identity Web](https://github.com/AzureAD/microsoft-identity-web)

## 🤝 Contributing

This project welcomes contributions. Please see [CONTRIBUTING.md](../../CONTRIBUTING.md) for guidelines.

## ⚖️ License

This project is licensed under the MIT License - see the [LICENSE.md](../../LICENSE.md) file for details.

---

**Target:** Microsoft Ignite 2025 (November)  
**Duration:** 30-minute hands-on lab  
**Audience:** Enterprise developers building AI agent solutions
