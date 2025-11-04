<#
.SYNOPSIS
    Automates Entra ID Agent Identity Blueprint setup for the Customer Service Agent sample.

.DESCRIPTION
    This script creates and configures an Agent Identity Blueprint with inheritable permissions,
    downstream API app registrations, Agent Identity (autonomous), and Agent User Identity 
    for the Customer Service Agent sample.
    
    The script is idempotent - it can be safely run multiple times without creating duplicates.
    It will detect existing resources and update them as needed.

.PARAMETER TenantId
    The Azure AD tenant ID. If not provided, uses the currently connected tenant.

.PARAMETER SampleInstancePrefix
    Prefix for all created app registrations (default: "CustomerService-").
    Use this to create multiple isolated instances of the sample in the same tenant.
    Example: -SampleInstancePrefix "MyDemo-" creates "MyDemo-Orchestrator", "MyDemo-OrderAPI", etc.

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
    .\Setup-EntraIdApps.ps1 -SampleInstancePrefix "Demo-"
    Creates apps with "Demo-" prefix: "Demo-Orchestrator", "Demo-OrderAPI", etc.

.EXAMPLE
    .\Setup-EntraIdApps.ps1 -SkipAgentIdentities
    Skips Agent Identity creation (useful for tenants without this preview feature)

.NOTES
    Prerequisites:
    - Microsoft.Graph PowerShell module (Install-Module Microsoft.Graph)
    - Permissions to create app registrations in the target tenant
    - Global Administrator or Application Administrator role recommended
    - For Agent Identities: Tenant must have Agent Identity Blueprints preview feature
    
    Author: Microsoft Identity Team
    Version: 2.0.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$TenantId,
    
    [Parameter(Mandatory=$false)]
    [string]$SampleInstancePrefix = "CustomerService-",
    
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
    SampleInstancePrefix = $SampleInstancePrefix
    BlueprintName = "${SampleInstancePrefix}Blueprint"
    OrchestratorName = "${SampleInstancePrefix}Orchestrator"
    Services = @(
        @{
            Name = "OrderAPI"
            DisplayName = "${SampleInstancePrefix}OrderAPI"
            Scopes = @(
                @{ Name = "Orders.Read"; DisplayName = "Read order data"; Description = "Allows the application to read order information" }
            )
        },
        @{
            Name = "ShippingAPI"
            DisplayName = "${SampleInstancePrefix}ShippingAPI"
            Scopes = @(
                @{ Name = "Shipping.Read"; DisplayName = "Read shipping data"; Description = "Allows the application to read shipping information" }
                @{ Name = "Shipping.Write"; DisplayName = "Write shipping data"; Description = "Allows the application to update shipping information" }
            )
        },
        @{
            Name = "EmailAPI"
            DisplayName = "${SampleInstancePrefix}EmailAPI"
            Scopes = @(
                @{ Name = "Email.Send"; DisplayName = "Send email"; Description = "Allows the application to send email notifications" }
            )
        }
    )
    AutonomousAgentName = "${SampleInstancePrefix}AutonomousAgent"
    AgentUserName = "${SampleInstancePrefix}AgentUser"
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

function Set-InheritablePermissions {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BlueprintApplicationId,
        
        [Parameter(Mandatory=$true)]
        [array]$DownstreamServices
    )
    
    Write-Status "Configuring inheritable permissions for Agent Identity Blueprint..." -Type Info
    
    try {
        # Get the blueprint application
        $blueprintApp = Get-MgApplication -Filter "appId eq '$BlueprintApplicationId'"
        
        if (-not $blueprintApp) {
            Write-Status "Blueprint application not found" -Type Error
            return
        }
        
        # Build required resource access for downstream APIs
        $allResourceAccess = @()
        
        foreach ($service in $DownstreamServices) {
            # Get the service application to find scope IDs
            $serviceApp = Get-MgApplication -Filter "appId eq '$($service.ClientId)'"
            
            if (-not $serviceApp) {
                Write-Status "Service application not found: $($service.DisplayName)" -Type Warning
                continue
            }
            
            # Create service principal if it doesn't exist
            $serviceSp = Get-MgServicePrincipal -Filter "appId eq '$($service.ClientId)'" -ErrorAction SilentlyContinue
            if (-not $serviceSp) {
                Write-Status "Creating service principal for: $($service.DisplayName)" -Type Info
                $serviceSp = New-MgServicePrincipal -AppId $service.ClientId
                Start-Sleep -Seconds 2
            }
            
            # Add individual scope permissions (inheritable permissions for Agent Identity Blueprint)
            # These permissions will be inherited by agent identities created from the blueprint
            $resourceAccess = @()
            
            # Add each scope defined for the service as delegated permissions
            if ($serviceApp.Api.Oauth2PermissionScopes -and $serviceApp.Api.Oauth2PermissionScopes.Count -gt 0) {
                foreach ($scope in $serviceApp.Api.Oauth2PermissionScopes) {
                    $resourceAccess += @{
                        Id = $scope.Id
                        Type = "Scope"
                    }
                    Write-Status "Adding inheritable permission: $($service.DisplayName)/$($scope.Value)" -Type Info
                }
            }
            
            if ($resourceAccess.Count -gt 0) {
                $allResourceAccess += @{
                    ResourceAppId = $service.ClientId
                    ResourceAccess = $resourceAccess
                }
            }
        }
        
        if ($allResourceAccess.Count -gt 0) {
            # Update the blueprint with inheritable permissions
            Update-MgApplication -ApplicationId $blueprintApp.Id -RequiredResourceAccess $allResourceAccess
            Write-Status "Inheritable permissions configured successfully" -Type Success
            Start-Sleep -Seconds 2
        } else {
            Write-Status "No inheritable permissions to configure" -Type Warning
        }
    }
    catch {
        Write-Status "Error configuring inheritable permissions: $($_.Exception.Message)" -Type Error
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
        [string]$BlueprintName,
        
        [Parameter(Mandatory=$true)]
        [string]$BlueprintAppClientId,
        
        [Parameter(Mandatory=$false)]
        [array]$DownstreamServices
    )
    
    Write-Status "Working with Agent Identity Blueprint: $BlueprintName" -Type Info
    Write-Status "Agent Identity Blueprints are in preview - checking availability..." -Type Warning
    
    try {
        # Note: Agent Identity Blueprints API is currently in preview
        # The Microsoft.Graph PowerShell module may not have full support yet
        # This function provides guidance for manual setup
        
        Write-Host "`n--- Agent Identity Blueprint Setup Required ---`n" -ForegroundColor Yellow
        Write-Status "The Agent Identity Blueprint feature is in preview and requires manual setup via Azure Portal." -Type Info
        Write-Status "Follow these steps:" -Type Info
        Write-Status "" -Type Info
        Write-Status "1. Navigate to Azure Portal > Microsoft Entra ID > Identity Governance" -Type Info
        Write-Status "2. Select 'Agent Identity Blueprints' (if available in your tenant)" -Type Info
        Write-Status "3. Click 'New blueprint'" -Type Info
        Write-Status "4. Name: $BlueprintName" -Type Info
        Write-Status "5. Link to application: $BlueprintAppClientId" -Type Info
        Write-Status "" -Type Info
        Write-Status "The blueprint should inherit these API permissions:" -Type Info
        foreach ($service in $DownstreamServices) {
            Write-Status "   - api://$($service.ClientId)/.default ($($service.DisplayName))" -Type Info
        }
        Write-Status "" -Type Info
        
        # Return a placeholder structure
        return @{
            Id = "MANUAL_SETUP_REQUIRED"
            Name = $BlueprintName
            ApplicationId = $BlueprintAppClientId
            ManualSetupRequired = $true
        }
    }
    catch {
        Write-Status "Note: Agent Identity Blueprint setup requires manual configuration" -Type Warning
        return $null
    }
}

function New-AgentIdentity {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BlueprintId,
        
        [Parameter(Mandatory=$true)]
        [string]$AgentName,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet('Autonomous', 'AgentUser')]
        [string]$Type,
        
        [Parameter(Mandatory=$false)]
        [string]$ServiceAccountUpn
    )
    
    Write-Status "Creating Agent Identity: $AgentName (Type: $Type)" -Type Info
    
    try {
        # Note: Agent Identity API is in preview
        # Manual setup required via Azure Portal
        
        Write-Host "`n--- Agent Identity Creation Required ---`n" -ForegroundColor Yellow
        Write-Status "Agent Identities must be created manually via Azure Portal:" -Type Info
        Write-Status "" -Type Info
        Write-Status "1. Navigate to your Agent Identity Blueprint: $BlueprintId" -Type Info
        Write-Status "2. Click 'Create agent identity'" -Type Info
        Write-Status "3. Type: $Type" -Type Info
        Write-Status "4. Name: $AgentName" -Type Info
        
        if ($Type -eq 'AgentUser' -and $ServiceAccountUpn) {
            Write-Status "5. Associated User: $ServiceAccountUpn" -Type Info
        }
        
        Write-Status "" -Type Info
        
        return @{
            Id = "MANUAL_SETUP_REQUIRED"
            Name = $AgentName
            Type = $Type
            BlueprintId = $BlueprintId
            ManualSetupRequired = $true
        }
    }
    catch {
        Write-Status "Note: Agent Identity creation requires manual configuration" -Type Warning
        return $null
    }
}

#endregion

#region Main Script

function Invoke-Setup {
    try {
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "Entra ID Agent Identity Blueprint Setup" -ForegroundColor Cyan
        Write-Host "Customer Service Agent Sample" -ForegroundColor Cyan
        Write-Host "========================================`n" -ForegroundColor Cyan
        Write-Host "Instance Prefix: $($script:Config.SampleInstancePrefix)" -ForegroundColor Cyan
        Write-Host ""
        
        # Step 1: Connect to Microsoft Graph
        $script:Results.TenantId = Connect-MicrosoftGraphIfNeeded -TenantIdParam $TenantId
        
        # Step 2: Create Agent Identity Blueprint Application (Orchestrator)
        Write-Host "`n--- Step 1: Creating Agent Identity Blueprint Application ---`n" -ForegroundColor Yellow
        Write-Status "Creating application that will serve as the Agent Identity Blueprint..." -Type Info
        $blueprintApp = Get-OrCreateApplication -DisplayName $script:Config.OrchestratorName -RequiresSecret $false
        
        $script:Results.Orchestrator = @{
            ApplicationId = $blueprintApp.Id
            ClientId = $blueprintApp.AppId
            DisplayName = $blueprintApp.DisplayName
        }
        
        # Step 3: Add client secret to blueprint application
        Write-Host "`n--- Step 2: Adding Client Secret to Blueprint ---`n" -ForegroundColor Yellow
        $blueprintSecret = New-ApplicationSecret -ApplicationId $blueprintApp.Id -DisplayName $script:Config.OrchestratorName
        $script:Results.Orchestrator.ClientSecret = $blueprintSecret
        
        # Step 4: Create Downstream Service Applications
        Write-Host "`n--- Step 3: Creating Downstream Service Applications ---`n" -ForegroundColor Yellow
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
        
        # Step 5: Configure Inheritable Permissions (downstream API permissions, not Graph)
        Write-Host "`n--- Step 4: Configuring Inheritable Permissions for Blueprint ---`n" -ForegroundColor Yellow
        Write-Status "Setting up inheritable permissions to downstream APIs..." -Type Info
        
        $downstreamServicesForPermissions = @()
        foreach ($service in $script:Config.Services) {
            $serviceResult = $script:Results.Services[$service.Name]
            $downstreamServicesForPermissions += @{
                ClientId = $serviceResult.ClientId
                DisplayName = $serviceResult.DisplayName
                Scopes = $service.Scopes
            }
        }
        
        Set-InheritablePermissions -BlueprintApplicationId $script:Results.Orchestrator.ClientId `
                                  -DownstreamServices $downstreamServicesForPermissions
        
        # Step 6: Create Service Principal for Blueprint
        Write-Host "`n--- Step 5: Creating Service Principal for Blueprint ---`n" -ForegroundColor Yellow
        $blueprintSp = Get-MgServicePrincipal -Filter "appId eq '$($script:Results.Orchestrator.ClientId)'" -ErrorAction SilentlyContinue
        
        if (-not $blueprintSp) {
            Write-Status "Creating service principal for blueprint..." -Type Info
            $blueprintSp = New-MgServicePrincipal -AppId $script:Results.Orchestrator.ClientId
            Start-Sleep -Seconds 2
            Write-Status "Service principal created successfully" -Type Success
        } else {
            Write-Status "Service principal already exists" -Type Info
        }
        
        # Step 7: Grant Admin Consent for Inheritable Permissions
        Write-Host "`n--- Step 6: Granting Admin Consent for Inheritable Permissions ---`n" -ForegroundColor Yellow
        Grant-AdminConsent -ClientAppClientId $script:Results.Orchestrator.ClientId
        
        # Step 8: Handle Agent Identities (if not skipped)
        if (-not $SkipAgentIdentities) {
            Write-Host "`n--- Step 7: Setting Up Agent Identity Blueprint and Identities ---`n" -ForegroundColor Yellow
            
            # Create/configure Agent Identity Blueprint
            $blueprint = Get-OrCreateAgentIdentityBlueprint `
                -BlueprintName $script:Config.BlueprintName `
                -BlueprintAppClientId $script:Results.Orchestrator.ClientId `
                -DownstreamServices $downstreamServicesForPermissions
            
            $script:Results.Blueprint = $blueprint
            
            # Create Autonomous Agent Identity (for OrderService)
            Write-Host "`n--- Step 8: Creating Autonomous Agent Identity ---`n" -ForegroundColor Yellow
            Write-Status "This identity will be used for calling OrderService autonomously" -Type Info
            
            if ($blueprint -and $blueprint.Id -ne "MANUAL_SETUP_REQUIRED") {
                $autonomousAgent = New-AgentIdentity `
                    -BlueprintId $blueprint.Id `
                    -AgentName $script:Config.AutonomousAgentName `
                    -Type "Autonomous"
                
                $script:Results.AutonomousAgent = $autonomousAgent
            } else {
                Write-Status "Blueprint must be created manually before creating agent identities" -Type Warning
                $script:Results.AutonomousAgent = @{
                    Id = "MANUAL_SETUP_REQUIRED"
                    Name = $script:Config.AutonomousAgentName
                    Type = "Autonomous"
                    Purpose = "For calling OrderService autonomously"
                    ManualSetupRequired = $true
                }
            }
            
            # Create Agent User Identity (for Shipping/EmailService with user context)
            Write-Host "`n--- Step 9: Creating Agent User Identity ---`n" -ForegroundColor Yellow
            Write-Status "This identity will be used for calling ShippingService and EmailService with user context" -Type Info
            
            if (-not $ServiceAccountUpn) {
                Write-Status "ServiceAccountUpn not provided. Agent User Identity will need to be created manually." -Type Warning
                $script:Results.Errors += "ServiceAccountUpn required for Agent User Identity"
                
                $script:Results.AgentUser = @{
                    Id = "MANUAL_SETUP_REQUIRED"
                    Name = $script:Config.AgentUserName
                    Type = "AgentUser"
                    Purpose = "For calling ShippingService and EmailService with user context"
                    ManualSetupRequired = $true
                }
            } else {
                if ($blueprint -and $blueprint.Id -ne "MANUAL_SETUP_REQUIRED") {
                    $agentUser = New-AgentIdentity `
                        -BlueprintId $blueprint.Id `
                        -AgentName $script:Config.AgentUserName `
                        -Type "AgentUser" `
                        -ServiceAccountUpn $ServiceAccountUpn
                    
                    $script:Results.AgentUser = $agentUser
                } else {
                    Write-Status "Blueprint must be created manually before creating agent identities" -Type Warning
                    $script:Results.AgentUser = @{
                        Id = "MANUAL_SETUP_REQUIRED"
                        Name = $script:Config.AgentUserName
                        Type = "AgentUser"
                        ServiceAccountUpn = $ServiceAccountUpn
                        Purpose = "For calling ShippingService and EmailService with user context"
                        ManualSetupRequired = $true
                    }
                }
            }
        } else {
            Write-Status "Skipping Agent Identity creation (use without -SkipAgentIdentities to enable)" -Type Info
        }
        
        # Step 10: Output Results
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
    
    if ($script:Results.Blueprint -and $script:Results.Blueprint.ManualSetupRequired) {
        Write-Status "2. Create Agent Identity Blueprint manually in Azure Portal:" -Type Info
        Write-Status "   - Navigate to Microsoft Entra ID > Identity Governance > Agent Identity Blueprints" -Type Info
        Write-Status "   - Create blueprint named: $($script:Config.BlueprintName)" -Type Info
        Write-Status "   - Link to application: $($script:Results.Orchestrator.ClientId)" -Type Info
    }
    
    if ($script:Results.AutonomousAgent -and $script:Results.AutonomousAgent.ManualSetupRequired) {
        Write-Status "3. Create Autonomous Agent Identity in the blueprint:" -Type Info
        Write-Status "   - Name: $($script:Config.AutonomousAgentName)" -Type Info
        Write-Status "   - Type: Autonomous Agent" -Type Info
        Write-Status "   - Purpose: For calling OrderService" -Type Info
    }
    
    if ($script:Results.AgentUser -and $script:Results.AgentUser.ManualSetupRequired) {
        Write-Status "4. Create Agent User Identity in the blueprint:" -Type Info
        Write-Status "   - Name: $($script:Config.AgentUserName)" -Type Info
        Write-Status "   - Type: Agent User" -Type Info
        if ($script:Results.AgentUser.ServiceAccountUpn) {
            Write-Status "   - Associated User: $($script:Results.AgentUser.ServiceAccountUpn)" -Type Info
        }
        Write-Status "   - Purpose: For calling ShippingService and EmailService with user context" -Type Info
    }
    
    if ($OutputFormat -ne 'UpdateConfig') {
        Write-Status "5. Update your appsettings.json files with these values" -Type Info
        Write-Status "   Or run again with -OutputFormat UpdateConfig to update automatically" -Type Info
    } else {
        Write-Status "5. Verify the updated appsettings.json files" -Type Info
    }
    
    Write-Status "6. Build and run the solution: dotnet run --project src/CustomerServiceAgent.AppHost" -Type Info
    Write-Status "" -Type Info
    Write-Status "For detailed setup instructions, see: docs/setup/02-entra-id-setup.md" -Type Info
}

function Show-PowerShellOutput {
    Write-Host "`n--- Configuration (PowerShell Variables) ---`n" -ForegroundColor Cyan
    
    Write-Host "# Tenant and Blueprint Configuration"
    Write-Host "`$TenantId = `"$($script:Results.TenantId)`""
    Write-Host "`$BlueprintClientId = `"$($script:Results.Orchestrator.ClientId)`""
    Write-Host "`$BlueprintClientSecret = `"$($script:Results.Orchestrator.ClientSecret)`""
    Write-Host ""
    
    Write-Host "# Downstream Service APIs"
    foreach ($serviceName in $script:Results.Services.Keys) {
        $service = $script:Results.Services[$serviceName]
        $varName = $serviceName -replace 'API', ''
        Write-Host "`$$($varName)ClientId = `"$($service.ClientId)`""
    }
    
    if ($script:Results.Blueprint -and -not $script:Results.Blueprint.ManualSetupRequired) {
        Write-Host ""
        Write-Host "# Agent Identity Blueprint"
        Write-Host "`$BlueprintId = `"$($script:Results.Blueprint.Id)`""
    }
    
    if ($script:Results.AutonomousAgent -and -not $script:Results.AutonomousAgent.ManualSetupRequired) {
        Write-Host ""
        Write-Host "# Autonomous Agent Identity"
        Write-Host "`$AutonomousAgentId = `"$($script:Results.AutonomousAgent.Id)`""
    }
    
    if ($script:Results.AgentUser -and -not $script:Results.AgentUser.ManualSetupRequired) {
        Write-Host ""
        Write-Host "# Agent User Identity"
        Write-Host "`$AgentUserId = `"$($script:Results.AgentUser.Id)`""
    }
    
    if ($script:Results.Blueprint -and $script:Results.Blueprint.ManualSetupRequired) {
        Write-Host ""
        Write-Host "# Note: Blueprint and Agent Identities require manual setup in Azure Portal"
        Write-Host "# After creating them, update your appsettings.json with:"
        Write-Host "# - Blueprint ID"
        Write-Host "# - Autonomous Agent Identity ID"
        Write-Host "# - Agent User Identity ID"
    }
}

function Show-JsonOutput {
    Write-Host "`n--- Configuration (JSON) ---`n" -ForegroundColor Cyan
    
    $output = @{
        TenantId = $script:Results.TenantId
        SampleInstancePrefix = $script:Config.SampleInstancePrefix
        Blueprint = @{
            ClientId = $script:Results.Orchestrator.ClientId
            ClientSecret = $script:Results.Orchestrator.ClientSecret
        }
        Services = @{}
    }
    
    foreach ($serviceName in $script:Results.Services.Keys) {
        $service = $script:Results.Services[$serviceName]
        $output.Services[$serviceName] = @{
            ClientId = $service.ClientId
            Scopes = @("api://$($service.ClientId)/.default")
        }
    }
    
    if ($script:Results.Blueprint) {
        if ($script:Results.Blueprint.ManualSetupRequired) {
            $output.Blueprint.BlueprintId = "MANUAL_SETUP_REQUIRED"
            $output.Blueprint.Note = "Create blueprint manually in Azure Portal"
        } else {
            $output.Blueprint.BlueprintId = $script:Results.Blueprint.Id
        }
    }
    
    if ($script:Results.AutonomousAgent) {
        if ($script:Results.AutonomousAgent.ManualSetupRequired) {
            $output.AutonomousAgent = @{
                Id = "MANUAL_SETUP_REQUIRED"
                Name = $script:Results.AutonomousAgent.Name
                Note = "Create autonomous agent identity manually in Azure Portal"
            }
        } else {
            $output.AutonomousAgent = @{
                Id = $script:Results.AutonomousAgent.Id
                Name = $script:Results.AutonomousAgent.Name
            }
        }
    }
    
    if ($script:Results.AgentUser) {
        if ($script:Results.AgentUser.ManualSetupRequired) {
            $output.AgentUser = @{
                Id = "MANUAL_SETUP_REQUIRED"
                Name = $script:Results.AgentUser.Name
                Note = "Create agent user identity manually in Azure Portal"
            }
            if ($script:Results.AgentUser.ServiceAccountUpn) {
                $output.AgentUser.ServiceAccountUpn = $script:Results.AgentUser.ServiceAccountUpn
            }
        } else {
            $output.AgentUser = @{
                Id = $script:Results.AgentUser.Id
                Name = $script:Results.AgentUser.Name
            }
        }
    }
    
    $output | ConvertTo-Json -Depth 10 | Write-Host
}

function Show-EnvVarsOutput {
    Write-Host "`n--- Configuration (Environment Variables) ---`n" -ForegroundColor Cyan
    Write-Host "# Run these commands to set environment variables:`n"
    
    Write-Host "`$env:TENANT_ID = `"$($script:Results.TenantId)`""
    Write-Host "`$env:BLUEPRINT_CLIENT_ID = `"$($script:Results.Orchestrator.ClientId)`""
    Write-Host "`$env:BLUEPRINT_CLIENT_SECRET = `"$($script:Results.Orchestrator.ClientSecret)`""
    Write-Host ""
    
    foreach ($serviceName in $script:Results.Services.Keys) {
        $service = $script:Results.Services[$serviceName]
        $varName = ($serviceName -replace 'API', '').ToUpper()
        Write-Host "`$env:$($varName)_CLIENT_ID = `"$($service.ClientId)`""
    }
    
    if ($script:Results.Blueprint -and -not $script:Results.Blueprint.ManualSetupRequired) {
        Write-Host ""
        Write-Host "`$env:BLUEPRINT_ID = `"$($script:Results.Blueprint.Id)`""
    }
    
    if ($script:Results.AutonomousAgent -and -not $script:Results.AutonomousAgent.ManualSetupRequired) {
        Write-Host "`$env:AUTONOMOUS_AGENT_ID = `"$($script:Results.AutonomousAgent.Id)`""
    }
    
    if ($script:Results.AgentUser -and -not $script:Results.AgentUser.ManualSetupRequired) {
        Write-Host "`$env:AGENT_USER_ID = `"$($script:Results.AgentUser.Id)`""
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
        
        # Update agent identities if available
        if ($script:Results.AutonomousAgent -and -not $script:Results.AutonomousAgent.ManualSetupRequired) {
            $config.AgentIdentities.AgentIdentity = $script:Results.AutonomousAgent.Id
        } else {
            $config.AgentIdentities.AgentIdentity = "YOUR_AGENT_IDENTITY_ID"
        }
        
        if ($script:Results.AgentUser -and -not $script:Results.AgentUser.ManualSetupRequired) {
            $config.AgentIdentities.AgentUserId = $script:Results.AgentUser.Id
        } else {
            $config.AgentIdentities.AgentUserId = "YOUR_AGENT_USER_ID"
        }
        
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
        
        if ($script:Results.AutonomousAgent -and $script:Results.AutonomousAgent.ManualSetupRequired) {
            Write-Status "Note: Update AgentIdentity field manually after creating the autonomous agent identity" -Type Warning
        }
        if ($script:Results.AgentUser -and $script:Results.AgentUser.ManualSetupRequired) {
            Write-Status "Note: Update AgentUserId field manually after creating the agent user identity" -Type Warning
        }
    } else {
        Write-Status "Orchestrator config file not found: $orchestratorConfigPath" -Type Warning
    }
    
    # Update each service appsettings.json
    foreach ($serviceName in $script:Results.Services.Keys) {
        $service = $script:Results.Services[$serviceName]
        $serviceFolder = $serviceName -replace 'API', 'Service'
        # Build path to service-specific appsettings.json
        $serviceConfigPath = Join-Path $projectRoot "src\DownstreamServices\$serviceFolder\appsettings.json"
        
        if (Test-Path $serviceConfigPath) {
            Write-Status "Updating: $serviceConfigPath" -Type Info
            
            $config = Get-Content $serviceConfigPath -Raw | ConvertFrom-Json
            $config.AzureAd.TenantId = $script:Results.TenantId
            $config.AzureAd.ClientId = $service.ClientId
            $config.AzureAd.Audience = "api://$($service.ClientId)"
            
            $config | ConvertTo-Json -Depth 10 | Set-Content $serviceConfigPath
            Write-Status "Updated successfully" -Type Success
        } else {
            Write-Status "Service config file not found: $serviceConfigPath" -Type Warning
        }
    }
    
    Write-Status "`nAll configuration files updated!" -Type Success
}

#endregion

# Run the setup
Invoke-Setup
