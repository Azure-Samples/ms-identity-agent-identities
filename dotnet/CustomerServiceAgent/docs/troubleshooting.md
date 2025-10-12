# Troubleshooting Guide

Common issues and solutions for the Customer Service Agent sample.

## Build Issues

### ❌ Error: .NET 9 SDK not found
**Symptom:**
```
error NETSDK1045: The current .NET SDK does not support targeting .NET 9.0
```

**Solution:**
1. Install .NET 9 SDK from https://dotnet.microsoft.com/download/dotnet/9.0
2. Verify installation: `dotnet --version` should show `9.0.xxx`
3. Restart your IDE/terminal

### ❌ Error: Aspire workload not installed
**Symptom:**
```
error: The project references the following workload packs that are not available: Aspire.Hosting.Sdk
```

**Solution:**
```bash
dotnet workload install aspire
```

### ❌ Build warnings about package versions
**Symptom:**
```
warning NU1608: Detected package version outside of dependency constraint
```

**Solution:**
These warnings are informational and don't prevent the sample from running. To resolve:
```bash
dotnet restore --force
dotnet clean
dotnet build
```

---

## Runtime Issues

### ❌ Port already in use
**Symptom:**
```
System.IO.IOException: Failed to bind to address https://localhost:7000
```

**Solution:**
Edit `src/CustomerServiceAgent.AppHost/Program.cs` and change port numbers:
```csharp
var orchestrator = builder.AddProject("agentorchestrator", "../AgentOrchestrator/AgentOrchestrator.csproj")
    .WithHttpsEndpoint(port: 8000, name: "https");  // Changed from 7000
```

### ❌ Aspire Dashboard not accessible
**Symptom:**
Browser shows "This site can't be reached" at `localhost:15888`

**Solution:**
1. Check the console output for the actual URL - it may be different
2. Look for lines like:
   ```
   Now listening on: https://localhost:16543
   ```
3. Use that URL in your browser
4. If using HTTPS, accept the self-signed certificate warning

### ❌ Services not showing in Aspire Dashboard
**Symptom:**
Aspire Dashboard shows no services or some services missing

**Solution:**
1. Ensure all projects built successfully
2. Check console logs for errors
3. Try stopping (`Ctrl+C`) and restarting the AppHost:
   ```bash
   dotnet run --project src/CustomerServiceAgent.AppHost
   ```

---

## API Call Issues

### ❌ 404 Not Found when calling orchestrator
**Symptom:**
```
curl: (404) Not Found
```

**Solution:**
1. Verify the orchestrator is running - check Aspire Dashboard Resources tab
2. Ensure you're using the correct URL:
   ```bash
   curl https://localhost:7000/api/customerservice/health
   ```
3. Check that the port matches what's in the Aspire Dashboard

### ❌ SSL certificate errors with curl
**Symptom:**
```
curl: (60) SSL certificate problem: self signed certificate
```

**Solution:**
Add `-k` flag to bypass certificate validation (dev/test only):
```bash
curl -k -X POST https://localhost:7000/api/customerservice/process \
  -H "Content-Type: application/json" \
  -d '{"orderId": "12345"}'
```

### ❌ Downstream service returns 401 Unauthorized
**Symptom:**
```json
{
  "status": "Failed",
  "messages": ["Failed to retrieve order 12345: Unauthorized"]
}
```

**Solution (Dev Mode - Expected):**
1. This is expected in dev mode with mock tokens
2. Downstream services have authentication commented out for demo purposes
3. In production, configure real Azure AD authentication

**Solution (Production Mode):**
1. Verify Azure AD configuration in appsettings.json
2. Check that client IDs and tenant IDs are correct
3. Ensure app registrations have correct API permissions
4. Verify agent identities are configured in your tenant

---

## Configuration Issues

### ❌ Missing appsettings.json values
**Symptom:**
```
InvalidOperationException: OrderService URL not configured
```

**Solution:**
Verify `src/AgentOrchestrator/appsettings.json` has service URLs:
```json
{
  "Services": {
    "OrderService": "https://localhost:7001",
    "CrmService": "https://localhost:7002",
    "ShippingService": "https://localhost:7003",
    "EmailService": "https://localhost:7004"
  }
}
```

### ❌ Azure AD authentication not working
**Symptom:**
```
Microsoft.Identity.Client.MsalServiceException: AADSTS700016: Application not found
```

**Solution:**
1. Verify `ClientId` in appsettings.json matches your app registration
2. Verify `TenantId` is correct
3. Ensure app registration is not deleted
4. Check that you're using the correct environment (test vs. production tenant)

---

## Agent Identities Issues

### ❌ Agent Identity extension methods not found
**Symptom:**
```
error CS1061: 'AuthorizationHeaderProviderOptions' does not contain a definition for 'WithAgentIdentity'
```

**Solution:**
1. Verify Microsoft.Identity.Web.AgentIdentities package is installed (version >= 3.10.0)
2. Add using statement:
   ```csharp
   using Microsoft.Identity.Web.AgentIdentities;
   ```
3. Ensure you're using the latest version:
   ```bash
   dotnet add package Microsoft.Identity.Web.AgentIdentities --version 3.10.0
   ```

### ❌ Agent Identity Blueprint not found
**Symptom:**
When setting up in production, error about agent identity not being valid

**Solution:**
1. Ensure Agent Identity Blueprint is created in your Entra ID tenant
2. Verify the blueprint ID matches configuration
3. Check that autonomous agent and agent user identities are properly configured
4. See [Entra ID Setup Guide](setup/02-entra-id-setup.md) for detailed instructions

---

## Performance Issues

### ❌ Slow startup time
**Symptom:**
AppHost takes several minutes to start all services

**Solution:**
1. This is normal for first run (NuGet package restore)
2. Subsequent runs should be faster
3. If consistently slow:
   - Close other applications
   - Check antivirus isn't scanning build output
   - Try `dotnet clean` then `dotnet build`

### ❌ High memory usage
**Symptom:**
System becomes slow when running the sample

**Solution:**
1. .NET Aspire runs multiple processes - this is expected
2. Each service runs in its own process
3. If memory is constrained:
   - Close unnecessary applications
   - Run fewer services (modify AppHost Program.cs)
   - Increase system RAM if possible

---

## Aspire Dashboard Issues

### ❌ Traces not showing
**Symptom:**
Traces tab in Aspire Dashboard is empty

**Solution:**
1. Make an API call to generate traces
2. Refresh the dashboard
3. Check that OpenTelemetry is configured (done automatically by ServiceDefaults)
4. Verify services are running and processing requests

### ❌ Logs not appearing
**Symptom:**
Console tab shows no logs or missing logs from some services

**Solution:**
1. Check that services are actually running
2. Verify logging configuration in appsettings.json
3. Try restarting the AppHost
4. Look for errors in terminal output

---

## IDE-Specific Issues

### Visual Studio

**Issue:** Solution doesn't load properly  
**Solution:**
1. Close Visual Studio
2. Delete `.vs` folder in solution directory
3. Delete `bin` and `obj` folders
4. Reopen solution

**Issue:** IntelliSense errors but builds successfully  
**Solution:**
1. Right-click solution → "Clean Solution"
2. Right-click solution → "Rebuild Solution"
3. Restart Visual Studio if issues persist

### VS Code

**Issue:** C# extension not working  
**Solution:**
1. Ensure C# Dev Kit extension is installed
2. Reload window: `Ctrl+Shift+P` → "Reload Window"
3. Check Output panel → C# for errors

**Issue:** Can't debug  
**Solution:**
1. Install C# Dev Kit and .NET Install Tool extensions
2. Open `.vscode/launch.json` and verify configuration
3. Set breakpoints before starting debug session

---

## Getting More Help

If your issue isn't covered here:

1. **Check the logs** - Look at console output and Aspire Dashboard logs
2. **Review the documentation** - See other docs in the `/docs` folder
3. **GitHub Issues** - Search existing issues or create a new one: https://github.com/Azure-Samples/ms-identity-agent-identities/issues
4. **Microsoft Identity Web Docs** - https://github.com/AzureAD/microsoft-identity-web
5. **Aspire Docs** - https://learn.microsoft.com/dotnet/aspire/

---

## Known Limitations (Demo Mode)

The sample runs in "demo mode" by default with these limitations:

- ❗ **Mock tokens** - No real Azure AD authentication
- ❗ **In-memory storage** - Data lost on restart
- ❗ **No persistence** - No database
- ❗ **Limited validation** - Authorization attributes commented out
- ❗ **No Graph API** - Microsoft Graph integration requires setup

To enable production features, follow the setup guides in `/docs/setup/`.

---

## Diagnostic Commands

Useful commands for troubleshooting:

```bash
# Check .NET version
dotnet --version

# List installed workloads
dotnet workload list

# Check running processes
dotnet --list-runtimes

# Restore packages with verbose output
dotnet restore --verbosity detailed

# Clean build artifacts
dotnet clean

# Build with detailed output
dotnet build --verbosity detailed

# Check listening ports (Windows)
netstat -ano | findstr "7000 7001 7002 7003 7004 15888"

# Check listening ports (Linux/Mac)
lsof -i :7000 -i :7001 -i :7002 -i :7003 -i :7004 -i :15888
```

---

**Last Updated:** 2025-01-12  
**Applies To:** Customer Service Agent Sample v1.0
