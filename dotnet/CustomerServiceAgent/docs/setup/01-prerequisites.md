# Prerequisites

Before running the Customer Service Agent sample, ensure you have the following installed and configured.

## Required Software

### 1. .NET 9 SDK
**Required Version:** 9.0 or later

**Download:** https://dotnet.microsoft.com/download/dotnet/9.0

**Verify Installation:**
```bash
dotnet --version
# Should show: 9.0.xxx
```

### 2. .NET Aspire Workload
**Required for:** Running the AppHost and Aspire Dashboard

**Install:**
```bash
dotnet workload install aspire
```

**Verify Installation:**
```bash
dotnet workload list
# Should show: aspire   8.2.xxx/9.0.xxx
```

### 3. IDE (Choose One)

#### Option A: Visual Studio 2022 (Recommended for Windows)
- **Version:** 17.8 or later
- **Workloads Required:**
  - ASP.NET and web development
  - .NET Aspire SDK (included in 17.9+)
- **Download:** https://visualstudio.microsoft.com/

#### Option B: Visual Studio Code
- **Version:** Latest stable
- **Required Extensions:**
  - C# Dev Kit
  - .NET Install Tool
- **Download:** https://code.visualstudio.com/

### 4. Git
**Required for:** Cloning the repository

**Download:** https://git-scm.com/downloads

**Verify Installation:**
```bash
git --version
```

---

## Optional Components

### 1. Azure Subscription
**Required for:** Production deployment and real Azure AD configuration

- **Get a free account:** https://azure.microsoft.com/free/
- **Alternative:** Use mock authentication (default in sample)

### 2. Microsoft 365 Developer Account
**Required for:** Microsoft Graph API integration (Teams, Outlook)

- **Get a free account:** https://developer.microsoft.com/microsoft-365/dev-program
- **Includes:** Free Microsoft 365 E5 subscription (renewable)
- **Alternative:** Graph integration can be skipped for demo

---

## System Requirements

### Minimum Requirements
- **OS:** Windows 10/11, macOS 12+, or Ubuntu 20.04+
- **RAM:** 8 GB
- **Disk Space:** 2 GB free
- **CPU:** Dual-core processor

### Recommended Requirements
- **RAM:** 16 GB (for better performance with multiple services)
- **Disk Space:** 5 GB free
- **CPU:** Quad-core processor

---

## Network Requirements

### Ports
The sample uses the following local ports by default:
- **15888** - Aspire Dashboard (HTTPS)
- **7000** - Agent Orchestrator (HTTPS)
- **7001** - Order Service (HTTPS)
- **7002** - CRM Service (HTTPS)
- **7003** - Shipping Service (HTTPS)
- **7004** - Email Service (HTTPS)

**Note:** These ports must be available. If in use, modify `src/CustomerServiceAgent.AppHost/Program.cs`.

### Firewall
- Ensure your firewall allows localhost connections
- No inbound internet connections required for demo mode

---

## Browser Requirements

For accessing the Aspire Dashboard:
- **Recommended:** Chrome, Edge, or Firefox (latest versions)
- **Minimum:** Any modern browser with JavaScript enabled

---

## Pre-flight Checklist

Before starting the lab, verify:

- [ ] .NET 9 SDK installed and version verified
- [ ] Aspire workload installed
- [ ] IDE (Visual Studio or VS Code) installed with required extensions
- [ ] Git installed and configured
- [ ] At least 8 GB RAM available
- [ ] Ports 7000-7004 and 15888 are not in use
- [ ] Internet connection available (for NuGet package restore)

---

## Troubleshooting Prerequisites

### .NET SDK Issues

**Problem:** Multiple .NET versions installed
```bash
dotnet --list-sdks
```
Ensure 9.0.xxx is listed. If not, reinstall.

**Problem:** Command not found
- **Windows:** Add to PATH: `C:\Program Files\dotnet`
- **macOS/Linux:** Add to PATH: `/usr/local/share/dotnet`

### Aspire Workload Issues

**Problem:** Workload installation fails
```bash
# Try with sudo/admin privileges (Linux/macOS)
sudo dotnet workload install aspire

# Windows: Run PowerShell as Administrator
dotnet workload install aspire
```

### IDE Issues

**Problem:** Visual Studio doesn't recognize .NET 9
- Update Visual Studio to latest version (17.12+)
- Tools → Options → Environment → Preview Features → Enable

**Problem:** VS Code C# extension not working
- Reload window: `Ctrl+Shift+P` → "Reload Window"
- Reinstall C# Dev Kit extension
- Check Output panel for errors

---

## Next Steps

Once all prerequisites are installed:

1. **[Clone and Build](../README.md#-quick-start)** - Get the sample running
2. **[Run the Lab](../docs/lab-instructions.md)** - Follow the 30-minute guided lab
3. **[Configure Azure AD](02-entra-id-setup.md)** - Set up production authentication

---

## Additional Resources

- [.NET Installation Guide](https://learn.microsoft.com/dotnet/core/install/)
- [.NET Aspire Setup](https://learn.microsoft.com/dotnet/aspire/fundamentals/setup-tooling)
- [Visual Studio Downloads](https://visualstudio.microsoft.com/downloads/)
- [VS Code Setup](https://code.visualstudio.com/docs/setup/setup-overview)

---

**Last Updated:** 2025-01-12  
**Applies To:** Customer Service Agent Sample v1.0
