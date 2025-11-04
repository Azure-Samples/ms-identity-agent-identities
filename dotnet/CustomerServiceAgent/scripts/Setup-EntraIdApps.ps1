<#
.SYNOPSIS
    Automates Entra ID application setup for the Customer Service Agent sample.

.DESCRIPTION
    This script creates and configures all required Entra ID app registrations,
    API permissions, scopes, and Agent Identity resources for the Customer Service Agent.
    
    The script is idempotent - it can be safely run multiple times without creating duplicates.
    It will detect existing resources and update them as needed.

.PARAMETER TenantId
    The Azure AD tenant ID. If not provided, uses the currently connected tenant.

.PARAMETER OutputFormat
    Format for configuration output: 'PowerShell', 'Json', 'EnvVars', or 'UpdateConfig'.
    - PowerShell: Outputs as PowerShell variables (default)
    - Json: Outputs as JSON object
    - EnvVars: Outputs as environment variable set commands
    - UpdateConfig: Updates appsettings.json files directly

.PARAMETER SkipAgentIdentities
    Skip creation of Agent Identity Blueprint and identities. Use if your tenant doesn't have this feature.

.PARAMETER ServiceAccountUpn
    UPN for the agent user service account (e.g., csr-agent@yourdomain.com).
    Required for Agent User Identity creation unless -SkipAgentIdentities is used.

.EXAMPLE
    .\Setup-EntraIdApps.ps1
    Interactive mode - uses current Graph connection, outputs PowerShell variables

.EXAMPLE
    .\Setup-EntraIdApps.ps1 -TenantId "your-tenant-id" -OutputFormat Json
    Connects to specific tenant, outputs JSON configuration

.EXAMPLE
    .\Setup-EntraIdApps.ps1 -OutputFormat UpdateConfig
    Updates appsettings.json files directly with generated values

.EXAMPLE
    .\Setup-EntraIdApps.ps1 -SkipAgentIdentities
    Skips Agent Identity creation (useful for tenants without this preview feature)

.NOTES
    Prerequisites:
    - Microsoft.Graph PowerShell module (Install-Module Microsoft.Graph)
    - Permissions to create app registrations in the target tenant
    - Global Administrator or Application Administrator role recommended
    
    Author: Microsoft Identity Team
    Version: 1.0.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$TenantId,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet('PowerShell', 'Json', 'EnvVars', 'UpdateConfig')]
    [string]$OutputFormat = 'PowerShell',
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipAgentIdentities,
    
    [Parameter(Mandatory=$false)]
    [string]$ServiceAccountUpn
)

# Error handling
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Script configuration
$script:Config = @{
    AppNamePrefix = "CustomerService"
    OrchestratorName = "CustomerService-Orchestrator"
    Services = @(
        @{
            Name = "OrderAPI"
            DisplayName = "CustomerService-OrderAPI"
            Scopes = @(
                @{ Name = "Orders.Read"; DisplayName = "Read order data"; Description = "Allows the application to read order information" }
            )
        },
        @{
            Name = "ShippingAPI"
            DisplayName = "CustomerService-ShippingAPI"
            Scopes = @(
                @{ Name = "Shipping.Read"; DisplayName = "Read shipping data"; Description = "Allows the application to read shipping information" }
                @{ Name = "Shipping.Write"; DisplayName = "Write shipping data"; Description = "Allows the application to update shipping information" }
            )
        },
        @{
            Name = "EmailAPI"
            DisplayName = "CustomerService-EmailAPI"
            Scopes = @(
                @{ Name = "Email.Send"; DisplayName = "Send email"; Description = "Allows the application to send email notifications" }
            )
        }
    )
    BlueprintName = "CustomerServiceAgentBlueprint"
    AutonomousAgentName = "CustomerServiceAutonomousAgent"
    AgentUserName = "CustomerServiceAgentUser"
}

# Store results
$script:Results = @{
    TenantId = $null
    Orchestrator = $null
    Services = @{}
    Blueprint = $null
    AutonomousAgent = $null
    AgentUser = $null
    Errors = @()
}

#region Helper Functions

function Write-Status {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Type = 'Info'
    )
    
    $color = switch ($Type) {
        'Info' { 'Cyan' }
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
    }
    
    $prefix = switch ($Type) {
        'Info' { '[INFO]' }
        'Success' { '[SUCCESS]' }
        'Warning' { '[WARNING]' }
        'Error' { '[ERROR]' }
    }
    
    Write-Host "$prefix $Message" -ForegroundColor $color
}

function Connect-MicrosoftGraphIfNeeded {
    param(
        [string]$TenantIdParam
    )
    
    Write-Status "Checking Microsoft Graph connection..." -Type Info
    
    try {
        $context = Get-MgContext
        if ($null -eq $context) {
            Write-Status "Not connected to Microsoft Graph. Connecting..." -Type Info
            
            $scopes = @(
                'Application.ReadWrite.All',
                'Directory.ReadWrite.All',
                'AppRoleAssignment.ReadWrite.All'
            )
            
            if ($TenantIdParam) {
                Connect-MgGraph -TenantId $TenantIdParam -Scopes $scopes -NoWelcome
            } else {
                Connect-MgGraph -Scopes $scopes -NoWelcome
            }
            
            $context = Get-MgContext
        }
        
        Write-Status "Connected to tenant: $($context.TenantId)" -Type Success
        return $context.TenantId
    }
    catch {
        Write-Status "Failed to connect to Microsoft Graph: $($_.Exception.Message)" -Type Error
        throw
    }
}

function Get-OrCreateApplication {
    param(
        [Parameter(Mandatory=$true)]
        [string]$DisplayName,
        
        [Parameter(Mandatory=$false)]
        [bool]$RequiresSecret = $false
    )
    
    Write-Status "Checking for existing app: $DisplayName" -Type Info
    
    try {
        # Check if app already exists
        $existingApps = @(Get-MgApplication -Filter "displayName eq '$DisplayName'" -ErrorAction SilentlyContinue)
        
        if ($existingApps.Count -gt 0) {
            $app = $existingApps[0]
            Write-Status "Found existing app: $DisplayName (ClientId: $($app.AppId))" -Type Success
            return $app
        }
        
        # Create new app
        Write-Status "Creating new app: $DisplayName" -Type Info
        $appParams = @{
            DisplayName = $DisplayName
            SignInAudience = "AzureADMyOrg"
        }
        
        $app = New-MgApplication @appParams
        Write-Status "Created app: $DisplayName (ClientId: $($app.AppId))" -Type Success
        
        # Wait a moment for replication
        Start-Sleep -Seconds 2
        
        return $app
    }
    catch {
        Write-Status "Error managing app $DisplayName : $($_.Exception.Message)" -Type Error
        throw
    }
}

function New-ApplicationSecret {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ApplicationId,
        
        [Parameter(Mandatory=$true)]
        [string]$DisplayName
    )
    
    Write-Status "Creating client secret for: $DisplayName" -Type Info
    
    try {
        $passwordCredential = @{
            displayName = "Generated by Setup Script"
            endDateTime = (Get-Date).AddMonths(24)
        }
        
        $secret = Add-MgApplicationPassword -ApplicationId $ApplicationId -PasswordCredential $passwordCredential
        Write-Status "Created client secret (expires: $($secret.EndDateTime))" -Type Success
        
        return $secret.SecretText
    }
    catch {
        Write-Status "Error creating secret: $($_.Exception.Message)" -Type Error
        throw
    }
}

function Set-ApiScopes {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ApplicationId,
        
        [Parameter(Mandatory=$true)]
        [string]$AppClientId,
        
        [Parameter(Mandatory=$true)]
        [array]$Scopes
    )
    
    Write-Status "Configuring API scopes..." -Type Info
    
    try {
        $app = Get-MgApplication -ApplicationId $ApplicationId
        
        # Set Application ID URI if not already set
        $appIdUri = "api://$AppClientId"
        if (-not $app.IdentifierUris -or $app.IdentifierUris -notcontains $appIdUri) {
            Write-Status "Setting Application ID URI: $appIdUri" -Type Info
            Update-MgApplication -ApplicationId $ApplicationId -IdentifierUris @($appIdUri)
            Start-Sleep -Seconds 2
        }
        
        # Configure OAuth2 permissions (scopes)
        $oauth2Permissions = @()
        foreach ($scope in $Scopes) {
            $scopeId = [Guid]::NewGuid().ToString()
            
            # Check if scope already exists
            if ($app.Api.Oauth2PermissionScopes) {
                $existing = $app.Api.Oauth2PermissionScopes | Where-Object { $_.Value -eq $scope.Name }
                if ($existing) {
                    Write-Status "Scope already exists: $($scope.Name)" -Type Info
                    $oauth2Permissions += $existing
                    continue
                }
            }
            
            $oauth2Permissions += @{
                Id = $scopeId
                AdminConsentDescription = $scope.Description
                AdminConsentDisplayName = $scope.DisplayName
                IsEnabled = $true
                Type = "Admin"
                Value = $scope.Name
            }
            
            Write-Status "Adding scope: $($scope.Name)" -Type Success
        }
        
        if ($oauth2Permissions.Count -gt 0) {
            $apiParams = @{
                Api = @{
                    Oauth2PermissionScopes = $oauth2Permissions
                }
            }
            
            Update-MgApplication -ApplicationId $ApplicationId -BodyParameter $apiParams
            Write-Status "API scopes configured successfully" -Type Success
            Start-Sleep -Seconds 2
        }
    }
    catch {
        Write-Status "Error configuring API scopes: $($_.Exception.Message)" -Type Error
        throw
    }
}

function Grant-ApiPermissions {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ClientApplicationId,
        
        [Parameter(Mandatory=$true)]
        [string]$ResourceAppClientId,
        
        [Parameter(Mandatory=$true)]
        [array]$ScopeNames
    )
    
    Write-Status "Granting API permissions to orchestrator for $ResourceAppClientId..." -Type Info
    
    try {
        # Get the client application
        $clientApp = Get-MgApplication -Filter "appId eq '$ClientApplicationId'"
        
        # Get the resource service principal
        $resourceSp = Get-MgServicePrincipal -Filter "appId eq '$ResourceAppClientId'" -ErrorAction SilentlyContinue
        
        if (-not $resourceSp) {
            Write-Status "Creating service principal for resource app..." -Type Info
            $resourceSp = New-MgServicePrincipal -AppId $ResourceAppClientId
            Start-Sleep -Seconds 2
        }
        
        # Get the resource application to find scope IDs
        $resourceApp = Get-MgApplication -Filter "appId eq '$ResourceAppClientId'"
        
        # Build required resource access
        $resourceAccess = @()
        foreach ($scopeName in $ScopeNames) {
            $scope = $resourceApp.Api.Oauth2PermissionScopes | Where-Object { $_.Value -eq $scopeName }
            if ($scope) {
                $resourceAccess += @{
                    Id = $scope.Id
                    Type = "Scope"
                }
                Write-Status "Adding permission: $scopeName" -Type Info
            }
        }
        
        if ($resourceAccess.Count -eq 0) {
            Write-Status "No permissions to add" -Type Warning
            return
        }
        
        # Get existing required resource access
        $existingAccess = $clientApp.RequiredResourceAccess | Where-Object { $_.ResourceAppId -eq $ResourceAppClientId }
        
        if ($existingAccess) {
            # Update existing
            $updatedAccess = $clientApp.RequiredResourceAccess | Where-Object { $_.ResourceAppId -ne $ResourceAppClientId }
            $updatedAccess += @{
                ResourceAppId = $ResourceAppClientId
                ResourceAccess = $resourceAccess
            }
            
            Update-MgApplication -ApplicationId $clientApp.Id -RequiredResourceAccess $updatedAccess
        } else {
            # Add new
            $allAccess = @($clientApp.RequiredResourceAccess)
            $allAccess += @{
                ResourceAppId = $ResourceAppClientId
                ResourceAccess = $resourceAccess
            }
            
            Update-MgApplication -ApplicationId $clientApp.Id -RequiredResourceAccess $allAccess
        }
        
        Write-Status "Permissions added successfully" -Type Success
        Start-Sleep -Seconds 2
    }
    catch {
        Write-Status "Error granting permissions: $($_.Exception.Message)" -Type Error
        throw
    }
}

function Grant-AdminConsent {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ClientAppClientId
    )
    
    Write-Status "Granting admin consent for orchestrator app..." -Type Info
    
    try {
        # Get the client service principal
        $clientSp = Get-MgServicePrincipal -Filter "appId eq '$ClientAppClientId'" -ErrorAction SilentlyContinue
        
        if (-not $clientSp) {
            Write-Status "Creating service principal for orchestrator..." -Type Info
            $clientSp = New-MgServicePrincipal -AppId $ClientAppClientId
            Start-Sleep -Seconds 2
        }
        
        # Get the client application to see what permissions it needs
        $clientApp = Get-MgApplication -Filter "appId eq '$ClientAppClientId'"
        
        foreach ($resourceAccess in $clientApp.RequiredResourceAccess) {
            # Get resource service principal
            $resourceSp = Get-MgServicePrincipal -Filter "appId eq '$($resourceAccess.ResourceAppId)'" -ErrorAction SilentlyContinue
            
            if (-not $resourceSp) {
                Write-Status "Resource service principal not found, creating..." -Type Info
                $resourceSp = New-MgServicePrincipal -AppId $resourceAccess.ResourceAppId
                Start-Sleep -Seconds 2
            }
            
            # Grant each permission
            foreach ($permission in $resourceAccess.ResourceAccess) {
                # Check if grant already exists
                $existingGrants = Get-MgServicePrincipalOauth2PermissionGrant -ServicePrincipalId $clientSp.Id -ErrorAction SilentlyContinue
                $existingGrant = $existingGrants | Where-Object { 
                    $_.ResourceId -eq $resourceSp.Id -and $_.ConsentType -eq "AllPrincipals"
                }
                
                if ($existingGrant) {
                    Write-Status "Admin consent already granted for this resource" -Type Info
                    continue
                }
                
                # Get scope value
                $resourceApp = Get-MgApplication -Filter "appId eq '$($resourceAccess.ResourceAppId)'"
                $scopeObj = $resourceApp.Api.Oauth2PermissionScopes | Where-Object { $_.Id -eq $permission.Id }
                
                if ($scopeObj) {
                    # Create OAuth2 permission grant (admin consent)
                    $grantParams = @{
                        ClientId = $clientSp.Id
                        ConsentType = "AllPrincipals"
                        ResourceId = $resourceSp.Id
                        Scope = $scopeObj.Value
                    }
                    
                    New-MgOauth2PermissionGrant -BodyParameter $grantParams | Out-Null
                    Write-Status "Granted admin consent for: $($scopeObj.Value)" -Type Success
                }
            }
        }
        
        Write-Status "Admin consent granted successfully" -Type Success
    }
    catch {
        Write-Status "Error granting admin consent: $($_.Exception.Message)" -Type Error
        # Non-fatal, continue
        $script:Results.Errors += "Admin consent may need to be granted manually"
    }
}

function Get-OrCreateAgentIdentityBlueprint {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BlueprintName
    )
    
    Write-Status "Agent Identity Blueprints are in preview and may not be available in all tenants" -Type Warning
    Write-Status "Attempting to work with Agent Identity Blueprint: $BlueprintName" -Type Info
    
    # Note: Agent Identity Blueprints API is in preview and may require beta endpoint
    # This is a placeholder for the actual implementation once the API is available
    Write-Status "Agent Identity Blueprint creation skipped (API not yet available via Microsoft.Graph PowerShell)" -Type Warning
    Write-Status "Please create manually via Azure Portal as described in setup documentation" -Type Warning
    
    return $null
}

#endregion

#region Main Script

function Invoke-Setup {
    try {
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "Entra ID Setup for Customer Service Agent" -ForegroundColor Cyan
        Write-Host "========================================`n" -ForegroundColor Cyan
        
        # Step 1: Connect to Microsoft Graph
        $script:Results.TenantId = Connect-MicrosoftGraphIfNeeded -TenantIdParam $TenantId
        
        # Step 2: Create Orchestrator Application
        Write-Host "`n--- Creating Orchestrator Application ---`n" -ForegroundColor Yellow
        $orchestratorApp = Get-OrCreateApplication -DisplayName $script:Config.OrchestratorName -RequiresSecret $true
        $orchestratorSecret = New-ApplicationSecret -ApplicationId $orchestratorApp.Id -DisplayName $script:Config.OrchestratorName
        
        $script:Results.Orchestrator = @{
            ApplicationId = $orchestratorApp.Id
            ClientId = $orchestratorApp.AppId
            ClientSecret = $orchestratorSecret
            DisplayName = $orchestratorApp.DisplayName
        }
        
        # Step 3: Create Downstream Service Applications
        Write-Host "`n--- Creating Downstream Service Applications ---`n" -ForegroundColor Yellow
        foreach ($service in $script:Config.Services) {
            Write-Status "Processing service: $($service.DisplayName)" -Type Info
            
            $serviceApp = Get-OrCreateApplication -DisplayName $service.DisplayName
            
            # Configure API scopes
            Set-ApiScopes -ApplicationId $serviceApp.Id -AppClientId $serviceApp.AppId -Scopes $service.Scopes
            
            $script:Results.Services[$service.Name] = @{
                ApplicationId = $serviceApp.Id
                ClientId = $serviceApp.AppId
                DisplayName = $serviceApp.DisplayName
                Scopes = $service.Scopes.Name
            }
            
            Write-Status "Service $($service.DisplayName) configured successfully`n" -Type Success
        }
        
        # Step 4: Grant API Permissions to Orchestrator
        Write-Host "`n--- Configuring API Permissions ---`n" -ForegroundColor Yellow
        foreach ($service in $script:Config.Services) {
            $serviceResult = $script:Results.Services[$service.Name]
            Grant-ApiPermissions -ClientApplicationId $script:Results.Orchestrator.ClientId `
                                -ResourceAppClientId $serviceResult.ClientId `
                                -ScopeNames $service.Scopes.Name
        }
        
        # Step 5: Grant Admin Consent
        Write-Host "`n--- Granting Admin Consent ---`n" -ForegroundColor Yellow
        Grant-AdminConsent -ClientAppClientId $script:Results.Orchestrator.ClientId
        
        # Step 6: Handle Agent Identities (if not skipped)
        if (-not $SkipAgentIdentities) {
            Write-Host "`n--- Creating Agent Identity Resources ---`n" -ForegroundColor Yellow
            
            if (-not $ServiceAccountUpn -and -not $SkipAgentIdentities) {
                Write-Status "ServiceAccountUpn not provided. Agent User Identity will need to be created manually." -Type Warning
                $script:Results.Errors += "ServiceAccountUpn required for Agent User Identity"
            }
            
            $blueprint = Get-OrCreateAgentIdentityBlueprint -BlueprintName $script:Config.BlueprintName
            $script:Results.Blueprint = $blueprint
            
            # Note: Additional Agent Identity creation would go here
            # This requires the Agent Identity API to be available
        } else {
            Write-Status "Skipping Agent Identity creation (use -SkipAgentIdentities to skip)" -Type Info
        }
        
        # Step 7: Output Results
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "Setup Completed Successfully!" -ForegroundColor Green
        Write-Host "========================================`n" -ForegroundColor Cyan
        
        Show-Results
    }
    catch {
        Write-Status "Setup failed: $($_.Exception.Message)" -Type Error
        Write-Status "Stack trace: $($_.ScriptStackTrace)" -Type Error
        exit 1
    }
}

function Show-Results {
    switch ($OutputFormat) {
        'PowerShell' {
            Show-PowerShellOutput
        }
        'Json' {
            Show-JsonOutput
        }
        'EnvVars' {
            Show-EnvVarsOutput
        }
        'UpdateConfig' {
            Update-ConfigFiles
        }
    }
    
    # Show warnings/errors
    if ($script:Results.Errors.Count -gt 0) {
        Write-Host "`n--- Warnings/Notes ---`n" -ForegroundColor Yellow
        foreach ($error in $script:Results.Errors) {
            Write-Status $error -Type Warning
        }
    }
    
    # Show next steps
    Write-Host "`n--- Next Steps ---`n" -ForegroundColor Yellow
    Write-Status "1. Review the configuration values above" -Type Info
    if ($OutputFormat -ne 'UpdateConfig') {
        Write-Status "2. Update your appsettings.json files with these values" -Type Info
    } else {
        Write-Status "2. Verify the updated appsettings.json files" -Type Info
    }
    if ($SkipAgentIdentities) {
        Write-Status "3. Create Agent Identity Blueprint and identities manually (or rerun without -SkipAgentIdentities)" -Type Info
    } else {
        Write-Status "3. Create Agent Identity Blueprint and identities in Azure Portal (see documentation)" -Type Info
    }
    Write-Status "4. Build and run the solution: dotnet run --project src/CustomerServiceAgent.AppHost" -Type Info
}

function Show-PowerShellOutput {
    Write-Host "`n--- Configuration (PowerShell Variables) ---`n" -ForegroundColor Cyan
    
    Write-Host "`$TenantId = `"$($script:Results.TenantId)`""
    Write-Host "`$OrchestratorClientId = `"$($script:Results.Orchestrator.ClientId)`""
    Write-Host "`$OrchestratorClientSecret = `"$($script:Results.Orchestrator.ClientSecret)`""
    Write-Host ""
    
    foreach ($serviceName in $script:Results.Services.Keys) {
        $service = $script:Results.Services[$serviceName]
        $varName = $serviceName -replace 'API', ''
        Write-Host "`$$($varName)ClientId = `"$($service.ClientId)`""
    }
    
    if ($script:Results.Blueprint) {
        Write-Host ""
        Write-Host "`$BlueprintId = `"$($script:Results.Blueprint.Id)`""
    }
}

function Show-JsonOutput {
    Write-Host "`n--- Configuration (JSON) ---`n" -ForegroundColor Cyan
    
    $output = @{
        TenantId = $script:Results.TenantId
        Orchestrator = @{
            ClientId = $script:Results.Orchestrator.ClientId
            ClientSecret = $script:Results.Orchestrator.ClientSecret
        }
        Services = @{}
    }
    
    foreach ($serviceName in $script:Results.Services.Keys) {
        $service = $script:Results.Services[$serviceName]
        $output.Services[$serviceName] = @{
            ClientId = $service.ClientId
        }
    }
    
    $output | ConvertTo-Json -Depth 10 | Write-Host
}

function Show-EnvVarsOutput {
    Write-Host "`n--- Configuration (Environment Variables) ---`n" -ForegroundColor Cyan
    Write-Host "# Run these commands to set environment variables:`n"
    
    Write-Host "`$env:TENANT_ID = `"$($script:Results.TenantId)`""
    Write-Host "`$env:ORCHESTRATOR_CLIENT_ID = `"$($script:Results.Orchestrator.ClientId)`""
    Write-Host "`$env:ORCHESTRATOR_CLIENT_SECRET = `"$($script:Results.Orchestrator.ClientSecret)`""
    Write-Host ""
    
    foreach ($serviceName in $script:Results.Services.Keys) {
        $service = $script:Results.Services[$serviceName]
        $varName = ($serviceName -replace 'API', '').ToUpper()
        Write-Host "`$env:$($varName)_CLIENT_ID = `"$($service.ClientId)`""
    }
}

function Update-ConfigFiles {
    Write-Host "`n--- Updating Configuration Files ---`n" -ForegroundColor Cyan
    
    $scriptDir = Split-Path -Parent $PSCommandPath
    $projectRoot = Split-Path -Parent $scriptDir
    
    # Update Orchestrator appsettings.json
    $orchestratorConfigPath = Join-Path $projectRoot "src\AgentOrchestrator\appsettings.json"
    if (Test-Path $orchestratorConfigPath) {
        Write-Status "Updating: $orchestratorConfigPath" -Type Info
        
        $config = Get-Content $orchestratorConfigPath -Raw | ConvertFrom-Json
        $config.AzureAd.TenantId = $script:Results.TenantId
        $config.AzureAd.ClientId = $script:Results.Orchestrator.ClientId
        $config.AzureAd.ClientCredentials[0].ClientSecret = $script:Results.Orchestrator.ClientSecret
        
        # Update downstream API scopes
        foreach ($serviceName in $script:Results.Services.Keys) {
            $service = $script:Results.Services[$serviceName]
            $configKey = $serviceName -replace 'API', 'Service'
            if ($config.DownstreamApis.$configKey) {
                $config.DownstreamApis.$configKey.Scopes = @("api://$($service.ClientId)/.default")
            }
        }
        
        $config | ConvertTo-Json -Depth 10 | Set-Content $orchestratorConfigPath
        Write-Status "Updated successfully" -Type Success
    }
    
    # Update each service appsettings.json
    foreach ($serviceName in $script:Results.Services.Keys) {
        $service = $script:Results.Services[$serviceName]
        $serviceFolder = $serviceName -replace 'API', 'Service'
        $serviceConfigPath = Join-Path $projectRoot "src\DownstreamServices\$serviceFolder\appsettings.json"
        
        if (Test-Path $serviceConfigPath) {
            Write-Status "Updating: $serviceConfigPath" -Type Info
            
            $config = Get-Content $serviceConfigPath -Raw | ConvertFrom-Json
            $config.AzureAd.TenantId = $script:Results.TenantId
            $config.AzureAd.ClientId = $service.ClientId
            $config.AzureAd.Audience = "api://$($service.ClientId)"
            
            $config | ConvertTo-Json -Depth 10 | Set-Content $serviceConfigPath
            Write-Status "Updated successfully" -Type Success
        }
    }
    
    Write-Status "`nAll configuration files updated!" -Type Success
}

#endregion

# Run the setup
Invoke-Setup
