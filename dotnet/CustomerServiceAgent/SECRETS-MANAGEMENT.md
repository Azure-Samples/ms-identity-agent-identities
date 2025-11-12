# Secrets Management Guide

## Overview

This application uses sensitive credentials (client secrets, API keys) that **must not be committed to source control**. This guide explains how to properly manage these secrets in different environments.

## Development Environment

### Using .NET User Secrets

For local development, use the [.NET User Secrets](https://docs.microsoft.com/aspnet/core/security/app-secrets) feature to store sensitive configuration outside of your project directory.

#### Initialize User Secrets

Navigate to the AgentOrchestrator project directory and initialize user secrets:

```bash
cd src/AgentOrchestrator
dotnet user-secrets init
```

#### Set the Client Secret

Store your Azure AD client secret using the following command:

```bash
dotnet user-secrets set "AzureAd:ClientCredentials:0:ClientSecret" "YOUR_ACTUAL_SECRET_HERE"
```

Replace `YOUR_ACTUAL_SECRET_HERE` with your actual client secret from the Azure Portal.

#### View Stored Secrets

To view all stored secrets:

```bash
dotnet user-secrets list
```

#### Remove a Secret

To remove a specific secret:

```bash
dotnet user-secrets remove "AzureAd:ClientCredentials:0:ClientSecret"
```

#### Clear All Secrets

To clear all user secrets:

```bash
dotnet user-secrets clear
```

### Location of User Secrets

User secrets are stored in a JSON file outside your project directory:

- **Windows**: `%APPDATA%\Microsoft\UserSecrets\<user_secrets_id>\secrets.json`
- **Linux/macOS**: `~/.microsoft/usersecrets/<user_secrets_id>/secrets.json`

The `<user_secrets_id>` is defined in the `AgentOrchestrator.csproj` file.

## Production Environment

**Never use User Secrets in production.** For production deployments, use one of the following approaches:

### Option 1: Azure Key Vault (Recommended)

Azure Key Vault provides secure storage and management of secrets, certificates, and keys.

#### Setup Steps

1. Create an Azure Key Vault in the Azure Portal
2. Add your secrets to Key Vault
3. Configure your application to use Key Vault:

```csharp
// In Program.cs
builder.Configuration.AddAzureKeyVault(
    new Uri($"https://{keyVaultName}.vault.azure.net/"),
    new DefaultAzureCredential());
```

4. Use Managed Identity to grant your application access to Key Vault

#### Key Vault Secret Naming

When storing the client secret in Key Vault, use this naming convention:

```
AzureAd--ClientCredentials--0--ClientSecret
```

Note: Key Vault doesn't support `:` in secret names, so use `--` instead.

### Option 2: Environment Variables

For containerized deployments or simple scenarios:

```bash
export AzureAd__ClientCredentials__0__ClientSecret="YOUR_SECRET_HERE"
```

Note: Use double underscores (`__`) to represent nested configuration hierarchy.

### Option 3: Azure App Configuration

For centralized configuration management:

1. Create an Azure App Configuration resource
2. Store configuration values and use Key Vault references for secrets
3. Configure your application to use App Configuration

## CI/CD Pipeline

For automated deployments, use secure variable storage:

### GitHub Actions

Use [GitHub Secrets](https://docs.github.com/actions/security-guides/encrypted-secrets):

```yaml
- name: Deploy
  env:
    AZURE_CLIENT_SECRET: ${{ secrets.AZURE_CLIENT_SECRET }}
  run: |
    # Your deployment commands
```

### Azure DevOps

Use [Azure Pipelines secret variables](https://docs.microsoft.com/azure/devops/pipelines/process/variables#secret-variables):

1. Navigate to Pipeline > Edit > Variables
2. Add a new variable
3. Check "Keep this value secret"

## Security Best Practices

1. ✅ **DO** use User Secrets for local development
2. ✅ **DO** use Azure Key Vault for production secrets
3. ✅ **DO** rotate secrets regularly
4. ✅ **DO** use Managed Identity when possible to avoid storing credentials
5. ✅ **DO** restrict access to secrets using RBAC
6. ❌ **DON'T** commit secrets to source control
7. ❌ **DON'T** share secrets via email, chat, or other insecure channels
8. ❌ **DON'T** log secret values
9. ❌ **DON'T** use User Secrets in production

## Checking for Leaked Secrets

If you accidentally committed a secret:

1. **Immediately revoke/rotate the secret** in Azure Portal
2. Remove the secret from Git history:
   ```bash
   git filter-branch --force --index-filter \
     "git rm --cached --ignore-unmatch path/to/file" \
     --prune-empty --tag-name-filter cat -- --all
   ```
3. Force push to remote (if you have permissions)
4. Notify your security team

## Additional Resources

- [Safe storage of app secrets in development](https://docs.microsoft.com/aspnet/core/security/app-secrets)
- [Azure Key Vault configuration provider](https://docs.microsoft.com/aspnet/core/security/key-vault-configuration)
- [Use Key Vault references for App Service and Azure Functions](https://docs.microsoft.com/azure/app-service/app-service-key-vault-references)
- [Managed identities for Azure resources](https://docs.microsoft.com/azure/active-directory/managed-identities-azure-resources/overview)
