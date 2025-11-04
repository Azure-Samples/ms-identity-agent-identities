# Microsoft Identity - Agent Identities Samples

This repository contains samples demonstrating how to use **Agent Identities** in Microsoft Entra ID with Microsoft Identity Web. Agent Identities enable AI agents to securely access downstream services using either autonomous (app-only) or user-delegated tokens.

## 📦 Samples

### [.NET Customer Service Agent with Aspire](dotnet/CustomerServiceAgent/)
[![.NET 9](https://img.shields.io/badge/.NET-9.0-purple)](https://dot.net)
[![Aspire 9.0](https://img.shields.io/badge/Aspire-9.0-blue)](https://learn.microsoft.com/dotnet/aspire/)

A comprehensive sample showcasing how an AI agent orchestrates multiple downstream APIs using:
- **Autonomous Agent Identity** (Order API - read operations)
- **Agent User Identities** with user context (Shipping & Email APIs - write operations)
- **.NET Aspire** for distributed tracing, logging, and service orchestration
- **In-memory stores** for quick setup without external dependencies

**Perfect for:** Microsoft Ignite 2025 - 30-minute hands-on lab

[View Sample →](dotnet/CustomerServiceAgent/)

---

## 🎯 What are Agent Identities?

**Agent Identities** are a new capability in Microsoft Entra ID that enable AI agents to:

1. **Autonomous Agent Identity** - Acquire app-only tokens for operations that don't require user context.
2. **Agent User Identity** - Acquire tokens with user context for operations requiring user identity (e.g., sending emails, participating in Teams channels)

This allows developers to build AI agents that can securely call downstream APIs with the appropriate level of authorization.

### Key Benefits
✅ **Secure by design** - Tokens are validated by Microsoft Entra ID  
✅ **Flexible authorization** - Mix app-only and user-delegated patterns  
✅ **Audit trail** - All operations are logged with proper identity context  
✅ **Works with existing APIs** - No changes needed to downstream services  

---

## 🚀 Getting Started

### Prerequisites
- [.NET 9 SDK](https://dotnet.microsoft.com/download/dotnet/9.0) (for .NET samples)
- Visual Studio 2022 or VS Code
- *(Optional)* Azure subscription for cloud deployment
- *(Optional)* Microsoft 365 Developer account if you want to try Graph API integration with Teams/Mails

### Quick Start
```bash
# Clone the repository
git clone https://github.com/Azure-Samples/ms-identity-agent-identities.git

# Navigate to a sample
cd ms-identity-agent-identities/dotnet/CustomerServiceAgent

# Install .NET aspire if needed
dotnet workload install aspire

# Build and run
dotnet build
dotnet run --project src/CustomerServiceAgent.AppHost
```

---

## 📚 Documentation

- **[Agent Identities Official Documentation](https://github.com/AzureAD/microsoft-identity-web/blob/main/src/Microsoft.Identity.Web.AgentIdentities/README.AgentIdentities.md)** - Detailed guide on Agent Identities
- **[Microsoft Identity Web](https://github.com/AzureAD/microsoft-identity-web)** - The library powering these samples
- **[.NET Aspire](https://learn.microsoft.com/dotnet/aspire/)** - Cloud-native application orchestration
- **[Microsoft Graph SDK](https://learn.microsoft.com/graph/sdks/sdks-overview)** - Integrate with Microsoft 365

---

## 🤝 Contributing

This project welcomes contributions and suggestions. Most contributions require you to agree to a Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us the rights to use your contribution. For details, visit https://cla.opensource.microsoft.com.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide a CLA and decorate the PR appropriately. Simply follow the instructions provided by the bot.

See [CONTRIBUTING.md](CONTRIBUTING.md) for more information.

---

## ⚖️ License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details.

---

## 📧 Support

For questions or issues:
- **GitHub Issues** - [Create an issue](https://github.com/Azure-Samples/ms-identity-agent-identities/issues)
- **Microsoft Q&A** - [Ask on Microsoft Q&A](https://learn.microsoft.com/answers/tags/455/entra-id)
- **Stack Overflow** - Tag your question with `azure-ad` and `microsoft-identity-web`

---

## 🌟 Additional Resources

- [Microsoft Entra ID Documentation](https://learn.microsoft.com/entra/identity/)
- [Azure Identity Samples](https://github.com/Azure-Samples?q=identity)
- [Microsoft Identity Platform](https://learn.microsoft.com/entra/identity-platform/)
- [Office 365 Developer Program](https://developer.microsoft.com/microsoft-365/dev-program)

---

**Target:** Microsoft Ignite 2025 (November)  
**Maintained by:** Microsoft Identity Team

