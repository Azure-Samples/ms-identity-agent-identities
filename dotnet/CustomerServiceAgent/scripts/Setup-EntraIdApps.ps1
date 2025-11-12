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
    [Parameter(Mandatory = $false)]
    [string]$TenantId,
    
    [Parameter(Mandatory = $false)]
    [string]$SampleInstancePrefix = "CustomerServiceSample-",
    
    [Parameter(Mandatory = $false)]
    [ValidateSet('PowerShell', 'Json', 'EnvVars', 'UpdateConfig')]
    [string]$OutputFormat = 'PowerShell',
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipAgentIdentities,
    
    [Parameter(Mandatory = $false)]
    [string]$ServiceAccountUpn
)

# Error handling
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Script configuration
$script:Config = @{
    SampleInstancePrefix = $SampleInstancePrefix
    BlueprintName        = "${SampleInstancePrefix}Blueprint"
    OrchestratorName     = "${SampleInstancePrefix}Orchestrator"
    Services             = @(
        @{
            Name        = "OrderAPI"
            DisplayName = "${SampleInstancePrefix}OrderAPI"
            Scopes      = @(
                @{ Name = "Orders.Read"; DisplayName = "Read order data"; Description = "Allows the application to read order information" }
            )
            AppRoles    = @(
                @{
                    Value       = "Orders.Read.All"
                    DisplayName = "Read all orders"
                    Description = "Allows the application to read all order information as an autonomous agent"
                    Id          = "a1b2c3d4-e5f6-4a5b-8c9d-0e1f2a3b4c5d"
                }
            )
        },
        @{
            Name        = "ShippingAPI"
            DisplayName = "${SampleInstancePrefix}ShippingAPI"
            Scopes      = @(
                @{ Name = "Shipping.Read"; DisplayName = "Read shipping data"; Description = "Allows the application to read shipping information" }
                @{ Name = "Shipping.Write"; DisplayName = "Write shipping data"; Description = "Allows the application to update shipping information" }
            )
            AppRoles    = @()
        },
        @{
            Name        = "EmailAPI"
            DisplayName = "${SampleInstancePrefix}EmailAPI"
            Scopes      = @(
                @{ Name = "Email.Send"; DisplayName = "Send email"; Description = "Allows the application to send email notifications" }
            )
            AppRoles    = @()
        }
    )
    AutonomousAgentName  = "${SampleInstancePrefix}AutonomousAgent"
    AgentUserName        = "${SampleInstancePrefix}AgentUser"
}

# Store results
$script:Results = @{
    TenantId        = $null
    Orchestrator    = $null
    Services        = @{}
    Blueprint       = $null
    AutonomousAgent = $null
    AgentUser       = $null
    Errors          = @()
}

#region Helper Functions

function Write-Status {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
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
                # To create an agent blueprint and it's service principal
                'AgentIdentityBlueprint.Create',
                'AgentIdentityBlueprintPrincipal.Create',
                'AppRoleAssignment.ReadWrite.All',
                'Application.ReadWrite.All',
                'User.ReadWrite.All',

                # for adding creds
                'AgentIdentityBlueprint.AddRemoveCreds.All',

                # For inheritable permissions
                'AgentIdentityBlueprint.ReadWrite.All',

                # For creating agent identities
                'AgentIdentity.Create.All',
                'AgentIdUser.ReadWrite.IdentityParentedBy'
            )
            
            if ($TenantIdParam) {
                Connect-MgGraph -TenantId $TenantIdParam -Scopes $scopes -NoWelcome
            }
            else {
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
        [Parameter(Mandatory = $true)]
        [string]$DisplayName,
        
        [Parameter(Mandatory = $false)]
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
            DisplayName    = $DisplayName
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
        [Parameter(Mandatory = $true)]
        [string]$ApplicationId,
        
        [Parameter(Mandatory = $true)]
        [string]$DisplayName
    )
    
    Write-Status "Creating client secret for: $DisplayName" -Type Info
    
    try {
        $passwordCredential = @{
            displayName = "Generated by Setup Script"
            endDateTime = (Get-Date).AddDays(90).ToString("o")
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
        [Parameter(Mandatory = $true)]
        [string]$ApplicationId,
        
        [Parameter(Mandatory = $true)]
        [string]$AppClientId,
        
        [Parameter(Mandatory = $true)]
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
        $needsUpdate = $false
        
        # Check if we need to add any new scopes
        foreach ($scope in $Scopes) {
            # Check if scope already exists
            $existing = $null
            if ($app.Api.Oauth2PermissionScopes) {
                $existing = $app.Api.Oauth2PermissionScopes | Where-Object { $_.Value -eq $scope.Name }
            }
            
            if ($existing) {
                Write-Status "Scope already exists: $($scope.Name)" -Type Info
                $oauth2Permissions += $existing
            }
            else {
                $scopeId = [Guid]::NewGuid().ToString()
                $oauth2Permissions += @{
                    Id                      = $scopeId
                    AdminConsentDescription = $scope.Description
                    AdminConsentDisplayName = $scope.DisplayName
                    IsEnabled               = $true
                    Type                    = "Admin"
                    Value                   = $scope.Name
                }
                $needsUpdate = $true
                Write-Status "Adding scope: $($scope.Name)" -Type Success
            }
        }
        
        # Only update if we have new scopes to add
        if ($needsUpdate) {
            Write-Status "Updating OAuth2 permission scopes..." -Type Info
            
            # Step 1: If there are existing enabled scopes, disable them first
            if ($app.Api.Oauth2PermissionScopes -and $app.Api.Oauth2PermissionScopes.Count -gt 0) {
                $hasEnabledScopes = $app.Api.Oauth2PermissionScopes | Where-Object { $_.IsEnabled -eq $true }
                
                if ($hasEnabledScopes) {
                    Write-Status "Disabling existing scopes before update..." -Type Info
                    
                    # Create disabled versions of all existing scopes
                    $disabledScopes = @()
                    foreach ($existingScope in $app.Api.Oauth2PermissionScopes) {
                        $disabledScopes += @{
                            Id                      = $existingScope.Id
                            AdminConsentDescription = $existingScope.AdminConsentDescription
                            AdminConsentDisplayName = $existingScope.AdminConsentDisplayName
                            IsEnabled               = $false
                            Type                    = $existingScope.Type
                            Value                   = $existingScope.Value
                        }
                    }
                    
                    # Update with disabled scopes
                    $disableParams = @{
                        Api = @{
                            Oauth2PermissionScopes = $disabledScopes
                        }
                    }
                    
                    Update-MgApplication -ApplicationId $ApplicationId -BodyParameter $disableParams
                    Write-Status "Existing scopes disabled" -Type Info
                    Start-Sleep -Seconds 3
                }
            }
            
            # Step 2: Update with the new/updated scopes (now enabled)
            $apiParams = @{
                Api = @{
                    Oauth2PermissionScopes = $oauth2Permissions
                }
            }
            
            Update-MgApplication -ApplicationId $ApplicationId -BodyParameter $apiParams
            Write-Status "API scopes configured successfully" -Type Success
            Start-Sleep -Seconds 2
        }
        else {
            Write-Status "All required scopes already exist, no update needed" -Type Info
        }
    }
    catch {
        Write-Status "Error configuring API scopes: $($_.Exception.Message)" -Type Error
        throw
    }
}

function Ensure-AppRoles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ApplicationId,
        
        [Parameter(Mandatory = $true)]
        [array]$DesiredAppRoles
    )
    
    Write-Status "Configuring app roles..." -Type Info
    
    try {
        $app = Get-MgApplication -ApplicationId $ApplicationId
        
        # Get existing app roles
        $existingAppRoles = @()
        if ($app.AppRoles) {
            $existingAppRoles = $app.AppRoles
        }
        
        # Track if we need to update
        $needsUpdate = $false
        $updatedAppRoles = @()
        
        # Keep existing app roles
        foreach ($existingRole in $existingAppRoles) {
            $updatedAppRoles += $existingRole
        }
        
        # Add new app roles if they don't exist
        foreach ($desiredRole in $DesiredAppRoles) {
            # Check if role already exists by value
            $existing = $existingAppRoles | Where-Object { $_.Value -eq $desiredRole.Value }
            
            if ($existing) {
                Write-Status "App role already exists: $($desiredRole.Value)" -Type Info
            }
            else {
                $newAppRole = @{
                    Id                 = $desiredRole.Id
                    AllowedMemberTypes = @("Application")
                    Description        = $desiredRole.Description
                    DisplayName        = $desiredRole.DisplayName
                    IsEnabled          = $true
                    Value              = $desiredRole.Value
                }
                
                $updatedAppRoles += $newAppRole
                $needsUpdate = $true
                Write-Status "Adding app role: $($desiredRole.Value)" -Type Success
            }
        }
        
        # Only update if we have new roles to add
        if ($needsUpdate) {
            Write-Status "Updating app roles..." -Type Info
            
            $appRoleParams = @{
                AppRoles = $updatedAppRoles
            }
            
            Update-MgApplication -ApplicationId $ApplicationId -BodyParameter $appRoleParams
            Write-Status "App roles configured successfully" -Type Success
            Start-Sleep -Seconds 2
        }
        else {
            Write-Status "All required app roles already exist, no update needed" -Type Info
        }
    }
    catch {
        Write-Status "Error configuring app roles: $($_.Exception.Message)" -Type Error
        throw
    }
}

function Ensure-AppRoleAssignment {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PrincipalServicePrincipalId,
        
        [Parameter(Mandatory = $true)]
        [string]$ResourceServicePrincipalId,
        
        [Parameter(Mandatory = $true)]
        [string]$AppRoleId
    )
    
    Write-Status "Assigning app role to service principal..." -Type Info
    
    try {
        # Check if assignment already exists
        $existingAssignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $PrincipalServicePrincipalId -ErrorAction SilentlyContinue
        
        $existingAssignment = $existingAssignments | Where-Object {
            $_.ResourceId -eq $ResourceServicePrincipalId -and $_.AppRoleId -eq $AppRoleId
        }
        
        if ($existingAssignment) {
            Write-Status "App role assignment already exists" -Type Info
            return
        }
        
        # Create the app role assignment
        $appRoleAssignment = @{
            PrincipalId = $PrincipalServicePrincipalId
            ResourceId  = $ResourceServicePrincipalId
            AppRoleId   = $AppRoleId
        }
        
        New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $PrincipalServicePrincipalId -BodyParameter $appRoleAssignment | Out-Null
        Write-Status "App role assigned successfully" -Type Success
        Start-Sleep -Seconds 2
    }
    catch {
        Write-Status "Error assigning app role: $($_.Exception.Message)" -Type Error
        # Non-fatal error, continue
        $script:Results.Errors += "App role assignment may need to be done manually"
    }
}

function Set-InheritablePermissions {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BlueprintApplicationId,
        
        [Parameter(Mandatory = $true)]
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
        
            # Build the request body
            $Body = [PSCustomObject]@{
                resourceAppId     = $service.ClientId
                inheritableScopes = [PSCustomObject]@{
                    "@odata.type" = "microsoft.graph.enumeratedScopes"
                    scopes        = @($service.Scopes.Name)
                    kind          = "enumerated"
                }
            }
        
            $JsonBody = $Body | ConvertTo-Json -Depth 5
            Write-Debug "Request Body: $JsonBody"
        
            # Use Invoke-MgRestMethod to make the API call with the stored Agent Blueprint ID
            $apiUrl = "https://graph.microsoft.com/beta/applications/microsoft.graph.agentIdentityBlueprint/$($BlueprintApplicationId)/inheritablePermissions"
            Write-Debug "API URL: $apiUrl"
            $result = Invoke-MgRestMethod -Method POST -Uri $apiUrl -Body $JsonBody -ContentType "application/json"
        }
        
        Write-Host "Successfully added inheritable permissions to Agent Identity Blueprints" -ForegroundColor Green
        Write-Host "Permissions are now available for inheritance by agent blueprints" -ForegroundColor Green
    }
    catch {
        Write-Status "Error configuring inheritable permissions: $($_.Exception.Message)" -Type Warning
    }
}


function Grant-ApiPermissions {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClientApplicationId,
        
        [Parameter(Mandatory = $true)]
        [string]$ResourceAppClientId,
        
        [Parameter(Mandatory = $true)]
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
                    Id   = $scope.Id
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
                ResourceAppId  = $ResourceAppClientId
                ResourceAccess = $resourceAccess
            }
            
            Update-MgApplication -ApplicationId $clientApp.Id -RequiredResourceAccess $updatedAccess
        }
        else {
            # Add new
            $allAccess = @($clientApp.RequiredResourceAccess)
            $allAccess += @{
                ResourceAppId  = $ResourceAppClientId
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
        [Parameter(Mandatory = $true)]
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
                        ClientId    = $clientSp.Id
                        ConsentType = "AllPrincipals"
                        ResourceId  = $resourceSp.Id
                        Scope       = $scopeObj.Value
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

function New-AgentIdentityBlueprintApp {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DisplayName,
        
        [Parameter(Mandatory = $false)]
        [string]$CurrentUserId
    )
    
    Write-Status "Creating Agent Identity Blueprint application: $DisplayName" -Type Info
    
    try {
        # Check if blueprint already exists
        $existingBlueprints = @(Get-MgApplication -Filter "displayName eq '$DisplayName'" -ErrorAction SilentlyContinue)
        
        if ($existingBlueprints.Count -gt 0) {
            $blueprint = $existingBlueprints[0]
            Write-Status "Found existing blueprint application: $DisplayName (AppId: $($blueprint.AppId))" -Type Success
            return $blueprint
        }
        
        # Get current user ID if not provided
        if (-not $CurrentUserId) {
            try {
                $currentUser = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/me" -ErrorAction SilentlyContinue
                $CurrentUserId = $currentUser.id
                Write-Status "Using current user as owner: $($currentUser.userPrincipalName)" -Type Info
            }
            catch {
                Write-Status "Could not retrieve current user ID. Blueprint will be created without owner." -Type Warning
            }
        }
        
        # Build the request body for Agent Identity Blueprint
        $Body = @{
            displayName   = $DisplayName
            "@odata.type" = "Microsoft.Graph.AgentIdentityBlueprint"
        }
        
        # Add owner if available
        if ($CurrentUserId) {
            $Body["owners@odata.bind"] = @("https://graph.microsoft.com/v1.0/users/$CurrentUserId")
            $Body["sponsors@odata.bind"] = @("https://graph.microsoft.com/v1.0/users/$CurrentUserId")
        }
        
        $JsonBody = $Body | ConvertTo-Json -Depth 5
        Write-Status "Creating Agent Identity Blueprint using beta endpoint..." -Type Info
        
        # Use the specialized Agent Identity Blueprint endpoint
        $BlueprintRes = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/applications/graph.agentIdentityBlueprint" -Body $JsonBody -Headers @{ "OData-Version" = "4.0" } 
        
        Write-Status "Successfully created Agent Identity Blueprint" -Type Success
        Write-Status "Blueprint Application ID: $($BlueprintRes.id)" -Type Info
        Write-Status "Blueprint App ID (Client ID): $($BlueprintRes.appId)" -Type Info
        
        # Wait for replication
        Start-Sleep -Seconds 3
        
        return $BlueprintRes
    }
    catch {
        Write-Status "Error creating Agent Identity Blueprint: $($_.Exception.Message)" -Type Error
        # Check if it's a permissions error
        if ($_.Exception.Message -like "*Insufficient privileges*" -or $_.Exception.Message -like "*Unauthorized*") {
            Write-Status "This may indicate that your tenant doesn't have Agent Identity Blueprints enabled or you lack required permissions." -Type Warning
            Write-Status "Required permission: AgentIdentityBlueprint.Create" -Type Warning
        }
        throw
    }
}

function New-AgentIdentityBlueprintServicePrincipal {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BlueprintAppId
    )
    
    Write-Status "Creating Agent Identity Blueprint Service Principal..." -Type Info
    
    try {
        # Check if service principal already exists
        $existingSp = Get-MgServicePrincipal -Filter "appId eq '$BlueprintAppId'" -ErrorAction SilentlyContinue
        
        if ($existingSp) {
            Write-Status "Found existing service principal for blueprint (ID: $($existingSp.Id))" -Type Success
            return $existingSp
        }
        
        # Prepare the body for the service principal creation
        $body = @{
            appId = $BlueprintAppId
        } | ConvertTo-Json
        
        # Create the service principal using the specialized endpoint
        Write-Status "Using specialized Agent Identity Blueprint service principal endpoint..." -Type Info
        
        $servicePrincipalResponse = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/serviceprincipals/graph.agentIdentityBlueprintPrincipal" -Body $body
        
        Write-Status "Successfully created Agent Identity Blueprint Service Principal" -Type Success
        Write-Status "Service Principal ID: $($servicePrincipalResponse.id)" -Type Info
        
        # Wait for replication
        Start-Sleep -Seconds 2
        
        return $servicePrincipalResponse
    }
    catch {
        Write-Status "Error creating service principal: $($_.Exception.Message)" -Type Error
        # Check if it's a permissions error
        if ($_.Exception.Message -like "*Insufficient privileges*" -or $_.Exception.Message -like "*Unauthorized*") {
            Write-Status "Required permission: AgentIdentityBlueprintPrincipal.Create" -Type Warning
        }
        throw
    }
}

function New-AgentIdentity {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BlueprintAppId,
        
        [Parameter(Mandatory = $true)]
        [string]$AgentName,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('Autonomous', 'AgentUser')]
        [string]$Type,
        
        [Parameter(Mandatory = $false)]
        [string]$CurrentUserId,
        
        [Parameter(Mandatory = $false)]
        [string]$ServiceAccountUpn
    )
    
    Write-Status "Creating Agent Identity: $AgentName (Type: $Type)" -Type Info
    
    try {
        # Get current user ID if not provided
        if (-not $CurrentUserId) {
            try {
                $currentUser = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/me" -ErrorAction SilentlyContinue
                $CurrentUserId = $currentUser.id
            }
            catch {
                Write-Status "Could not retrieve current user ID for agent ownership" -Type Warning
            }
        }
        
        # Build the request body
        $Body = @{
            displayName              = $AgentName
            AgentIdentityBlueprintId = $BlueprintAppId
        }
        
        # Add owner if available
        if ($CurrentUserId) {
            $Body["owners@odata.bind"] = @("https://graph.microsoft.com/v1.0/users/$CurrentUserId")
        }
        
        $JsonBody = $Body | ConvertTo-Json -Depth 5
        
        Write-Status "Creating $Type agent identity using beta endpoint..." -Type Info
        
        # Create the agent identity using the specialized endpoint
        $agentIdentity = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/serviceprincipals/Microsoft.Graph.AgentIdentity" -Body $JsonBody
        
        Write-Status "Successfully created Agent Identity" -Type Success
        Write-Status "Agent Identity ID: $($agentIdentity.id)" -Type Info
        Write-Status "Display Name: $($agentIdentity.displayName)" -Type Info
        
        # If this is an AgentUser type, create the user association
        if ($Type -eq 'AgentUser' -and $ServiceAccountUpn) {
            Write-Status "Creating Agent User association for: $ServiceAccountUpn" -Type Info
            try {
                # Create Agent ID User (this requires the agent identity to exist first)
                $userBody = @{
                    displayName       = "$AgentName User"
                    userPrincipalName = $ServiceAccountUpn
                } | ConvertTo-Json
                
                $agentUser = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/serviceprincipals/$($agentIdentity.id)/agentIdUsers" -Body $userBody
                
                Write-Status "Successfully created Agent User" -Type Success
                Write-Status "Agent User ID: $($agentUser.id)" -Type Info
                
                # Add user info to the result
                $agentIdentity | Add-Member -MemberType NoteProperty -Name "AgentUserId" -Value $agentUser.id
                $agentIdentity | Add-Member -MemberType NoteProperty -Name "AgentUserUpn" -Value $ServiceAccountUpn
            }
            catch {
                Write-Status "Note: Could not create Agent User automatically. This may need manual setup." -Type Warning
                Write-Status "Error: $($_.Exception.Message)" -Type Warning
            }
        }
        
        return $agentIdentity
    }
    catch {
        Write-Status "Error creating Agent Identity: $($_.Exception.Message)" -Type Error
        
        # Provide helpful guidance based on error
        if ($_.Exception.Message -like "*Insufficient privileges*" -or $_.Exception.Message -like "*Unauthorized*") {
            Write-Status "This feature may not be available in your tenant or you lack required permissions." -Type Warning
            Write-Status "Required permissions: AgentIdentity.ReadWrite.All" -Type Warning
        }
        
        # Return a manual setup placeholder
        return @{
            Id                  = "MANUAL_SETUP_REQUIRED"
            Name                = $AgentName
            Type                = $Type
            BlueprintId         = $BlueprintAppId
            ServiceAccountUpn   = $ServiceAccountUpn
            ManualSetupRequired = $true
            Error               = $_.Exception.Message
        }
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
        
        # Get current user ID for ownership
        $currentUserId = $null
        try {
            $currentUser = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/me" -ErrorAction SilentlyContinue
            $currentUserId = $currentUser.id
            Write-Status "Current user: $($currentUser.userPrincipalName)" -Type Info
        }
        catch {
            Write-Status "Could not retrieve current user information" -Type Warning
        }
        
        # Step 2: Create Agent Identity Blueprint Application using specialized endpoint
        Write-Host "`n--- Step 1: Creating Agent Identity Blueprint ---`n" -ForegroundColor Yellow
        Write-Status "Using specialized Agent Identity Blueprint endpoint..." -Type Info
        
        if (-not $SkipAgentIdentities) {
            try {
                $blueprintApp = New-AgentIdentityBlueprintApp -DisplayName $script:Config.OrchestratorName -CurrentUserId $currentUserId
                
                $script:Results.Orchestrator = @{
                    ApplicationId = $blueprintApp.id
                    ClientId      = $blueprintApp.appId
                    DisplayName   = $blueprintApp.displayName
                    UsedFallback  = $false
                }

                Set-ApiScopes -ApplicationId $blueprintApp.id -AppClientId $blueprintApp.appId -Scopes $blueprintApp.scopes @(
                    @{ Name = "Agent.Access"; DisplayName = "Access agent"; Description = "Access the agent" }
                )
                
            }
            catch {
                Write-Status "Could not create Agent Identity Blueprint using API. Falling back to standard application." -Type Warning
                Write-Status "Error: $($_.Exception.Message)" -Type Warning
                
                # Fallback to standard application creation
                $blueprintApp = Get-OrCreateApplication -DisplayName $script:Config.OrchestratorName -RequiresSecret $false
                
                $script:Results.Orchestrator = @{
                    ApplicationId = $blueprintApp.Id
                    ClientId      = $blueprintApp.AppId
                    DisplayName   = $blueprintApp.DisplayName
                }
                $script:Results.Orchestrator.UsedFallback = $true
            }
        }
        else {
            # Skip agent identities - use standard app creation
            Write-Status "Skipping Agent Identity Blueprint creation (use without -SkipAgentIdentities to enable)" -Type Info
            $blueprintApp = Get-OrCreateApplication -DisplayName $script:Config.OrchestratorName -RequiresSecret $false
            
            $script:Results.Orchestrator = @{
                ApplicationId = $blueprintApp.Id
                ClientId      = $blueprintApp.AppId
                DisplayName   = $blueprintApp.DisplayName
            }
        }

        # Step 6: Create Service Principal for Blueprint using specialized endpoint
        Write-Host "`n--- Step 5: Creating Service Principal for Blueprint ---`n" -ForegroundColor Yellow
        
        if (-not $SkipAgentIdentities -and -not $script:Results.Orchestrator.UsedFallback) {
            try {
                $blueprintSp = New-AgentIdentityBlueprintServicePrincipal -BlueprintAppId $script:Results.Orchestrator.ClientId
                Write-Status "Agent Identity Blueprint Service Principal created" -Type Success
            }
            catch {
                Write-Status "Could not create service principal using specialized endpoint. Using standard method." -Type Warning
                $blueprintSp = Get-MgServicePrincipal -Filter "appId eq '$($script:Results.Orchestrator.ClientId)'" -ErrorAction SilentlyContinue
                
                if (-not $blueprintSp) {
                    Write-Status "Creating standard service principal for blueprint..." -Type Info
                    $blueprintSp = New-MgServicePrincipal -AppId $script:Results.Orchestrator.ClientId
                    Start-Sleep -Seconds 2
                    Write-Status "Service principal created successfully" -Type Success
                }
                else {
                    Write-Status "Service principal already exists" -Type Info
                }
            }
        }
        else {
            $blueprintSp = Get-MgServicePrincipal -Filter "appId eq '$($script:Results.Orchestrator.ClientId)'" -ErrorAction SilentlyContinue
            
            if (-not $blueprintSp) {
                Write-Status "Creating service principal for blueprint..." -Type Info

                # Prepare the body for the service principal creation
                $body = @{
                    appId = $script:Results.Orchestrator.ClientId
                }
        
                # Create the service principal using the specialized endpoint
                Write-Host "Making request to create service principal for Agent Blueprint: $script:Results.Orchestrator.ClientId" -ForegroundColor Cyan
 
                $blueprintSp = Invoke-MgRestMethod -Uri "/beta/serviceprincipals/graph.agentIdentityBlueprintPrincipal" -Method POST -Body ($body | ConvertTo-Json) -ContentType "application/json"
                Start-Sleep -Seconds 2
                Write-Status "Service principal created successfully" -Type Success
            }
            else {
                Write-Status "Service principal already exists" -Type Info
            }
        }

        # Step 3: Add client secret to blueprint
        Write-Host "`n--- Step 2: Adding Client Secret to Blueprint ---`n" -ForegroundColor Yellow
        $passwordCredential = @{
            displayName = "1st blueprint secret for dev/test. Not recommended for production use"
            endDateTime = (Get-Date).AddDays(90).ToString("o")
        }
        $secretResult = Add-MgApplicationPassword -ApplicationId $script:Results.Orchestrator.ApplicationId -PasswordCredential $passwordCredential
        $script:Results.Orchestrator.ClientSecret = $($secretResult.SecretText)
        
        # Step 4: Create Downstream Service Applications
        Write-Host "`n--- Step 3: Creating Downstream Service Applications ---`n" -ForegroundColor Yellow
        foreach ($service in $script:Config.Services) {
            Write-Status "Processing service: $($service.DisplayName)" -Type Info
            
            $serviceApp = Get-OrCreateApplication -DisplayName $service.DisplayName
            
            # Configure API scopes
            Set-ApiScopes -ApplicationId $serviceApp.Id -AppClientId $serviceApp.AppId -Scopes $service.Scopes
            
            # Configure app roles if defined
            if ($service.AppRoles -and $service.AppRoles.Count -gt 0) {
                Ensure-AppRoles -ApplicationId $serviceApp.Id -DesiredAppRoles $service.AppRoles
            }
            
            $script:Results.Services[$service.Name] = @{
                ApplicationId = $serviceApp.Id
                ClientId      = $serviceApp.AppId
                DisplayName   = $serviceApp.DisplayName
                Scopes        = $service.Scopes.Name
                AppRoles      = if ($service.AppRoles) { $service.AppRoles } else { @() }
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
                ClientId    = $serviceResult.ClientId
                DisplayName = $serviceResult.DisplayName
                Scopes      = $service.Scopes
            }
        }
        
        Set-InheritablePermissions -BlueprintApplicationId $script:Results.Orchestrator.ClientId `
            -DownstreamServices $downstreamServicesForPermissions
        
 
        
        # Step 7: Grant Admin Consent for Inheritable Permissions
        Write-Host "`n--- Step 6: Granting Admin Consent for Inheritable Permissions ---`n" -ForegroundColor Yellow
        Grant-AdminConsent -ClientAppClientId $script:Results.Orchestrator.ClientId
        
       
        # Step 8: Grant the blueprint service principal the 'AgentIdentity.CreateAsManager' role in Microsoft Graph
        
        # Get the service principal for Microsoft Graph
        try {
            $msGraphAppId = "00000003-0000-0000-c000-000000000000"
            $msGraphServicePrincipal = Get-MgServicePrincipal -Filter "appId eq '$msGraphAppId'" -Select "id,appId,displayName"
            $msGraphServicePrincipalId = $msGraphServicePrincipal.Id
            $appRoleId = "4aa6e624-eee0-40ab-bdd8-f9639038a614"

            New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $blueprintSp.Id `
                -PrincipalId $blueprintSp.Id `
                -ResourceId $msGraphServicePrincipalId `
                -AppRoleId $appRoleId

        }
        catch {
            # Already done
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
        foreach ($resultError in $script:Results.Errors) {
            Write-Status $resultError -Type Warning
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
    }
    else {
        Write-Status "5. Verify the updated appsettings.json files" -Type Info
    }
    
    Write-Status "6. Build and run the solution: dotnet run --project src/CustomerServiceAgent.AppHost" -Type Info
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
    
    if ($script:Results.Blueprint) {
        Write-Host ""
        Write-Host "# Agent Identity Blueprint"
        Write-Host "`$BlueprintId = `"$($script:Results.Blueprint.Id)`""
    }
    
    if ($script:Results.AutonomousAgent ) {
        Write-Host ""
        Write-Host "# Autonomous Agent Identity"
        Write-Host "`$AutonomousAgentId = `"$($script:Results.AutonomousAgent.Id)`""
    }
    
    if ($script:Results.AgentUser) {
        Write-Host ""
        Write-Host "# Agent User Identity"
        Write-Host "`$AgentUserId = `"$($script:Results.AgentUser.Id)`""
    }
}

function Show-JsonOutput {
    Write-Host "`n--- Configuration (JSON) ---`n" -ForegroundColor Cyan
    
    $output = @{
        TenantId             = $script:Results.TenantId
        SampleInstancePrefix = $script:Config.SampleInstancePrefix
        Blueprint            = @{
            ClientId     = $script:Results.Orchestrator.ClientId
            ClientSecret = $script:Results.Orchestrator.ClientSecret
        }
        Services             = @{}
    }
    
    foreach ($serviceName in $script:Results.Services.Keys) {
        $service = $script:Results.Services[$serviceName]
        $output.Services[$serviceName] = @{
            ClientId = $service.ClientId
            Scopes   = @("api://$($service.ClientId)/.default")
        }
    }
    
    if ($script:Results.Blueprint) {
        if ($script:Results.Blueprint.ManualSetupRequired) {
            $output.Blueprint.BlueprintId = "MANUAL_SETUP_REQUIRED"
            $output.Blueprint.Note = "Create blueprint manually in Azure Portal"
        }
        else {
            $output.Blueprint.BlueprintId = $script:Results.Blueprint.Id
        }
    }
    
    if ($script:Results.AutonomousAgent) {
        if ($script:Results.AutonomousAgent.ManualSetupRequired) {
            $output.AutonomousAgent = @{
                Id   = "MANUAL_SETUP_REQUIRED"
                Name = $script:Results.AutonomousAgent.Name
                Note = "Create autonomous agent identity manually in Azure Portal"
            }
        }
        else {
            $output.AutonomousAgent = @{
                Id   = $script:Results.AutonomousAgent.Id
                Name = $script:Results.AutonomousAgent.Name
            }
        }
    }
    
    if ($script:Results.AgentUser) {
        if ($script:Results.AgentUser.ManualSetupRequired) {
            $output.AgentUser = @{
                Id   = "MANUAL_SETUP_REQUIRED"
                Name = $script:Results.AgentUser.Name
                Note = "Create agent user identity manually in Azure Portal"
            }
            if ($script:Results.AgentUser.ServiceAccountUpn) {
                $output.AgentUser.ServiceAccountUpn = $script:Results.AgentUser.ServiceAccountUpn
            }
        }
        else {
            $output.AgentUser = @{
                Id   = $script:Results.AgentUser.Id
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
    
    # Get current user ID for SponsorUserId and tenant information
    $currentUserId = $null
    $tenantDomain = $null
    try {
        $currentUser = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/me" -ErrorAction SilentlyContinue
        $currentUserId = $currentUser.id
        Write-Status "Setting SponsorUserId to current user: $($currentUser.userPrincipalName) ($currentUserId)" -Type Info
        
        # Extract tenant domain from user's UPN or get from organization info
        if ($currentUser.userPrincipalName -match "@(.+)$") {
            $tenantDomain = $Matches[1]
            Write-Status "Detected tenant domain: $tenantDomain" -Type Info
        }
        else {
            # Fallback: Get tenant domain from organization endpoint
            try {
                $org = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/organization" -ErrorAction SilentlyContinue
                if ($org.value -and $org.value[0].verifiedDomains) {
                    $defaultDomain = $org.value[0].verifiedDomains | Where-Object { $_.isDefault -eq $true } | Select-Object -First 1
                    if ($defaultDomain) {
                        $tenantDomain = $defaultDomain.name
                        Write-Status "Retrieved tenant domain from organization: $tenantDomain" -Type Info
                    }
                }
            }
            catch {
                Write-Status "Could not retrieve tenant domain from organization endpoint" -Type Warning
            }
        }
    }
    catch {
        Write-Status "Could not retrieve current user ID for SponsorUserId" -Type Warning
    }
    
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
        }
        else {
            $config.AgentIdentities.AgentIdentity = "YOUR_AGENT_IDENTITY_ID"
        }
        
        if ($script:Results.AgentUser -and -not $script:Results.AgentUser.ManualSetupRequired) {
            $config.AgentIdentities.AgentUserId = $script:Results.AgentUser.Id
        }
        else {
            $config.AgentIdentities.AgentUserId = "YOUR_AGENT_USER_ID"
        }
        
        # Set SponsorUserId to current user's object ID
        if ($currentUserId) {
            $config.AgentIdentities.SponsorUserId = $currentUserId
        }
        else {
            $config.AgentIdentities.SponsorUserId = "HUMAN_SPONSOR_USER_ID"
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
    }
    else {
        Write-Status "Orchestrator config file not found: $orchestratorConfigPath" -Type Warning
    }
    
    # Update .http file with tenant domain
    $httpFilePath = Join-Path $projectRoot "src\AgentOrchestrator\AgentOrchestrator.http"
    if (Test-Path $httpFilePath) {
        Write-Status "Updating: $httpFilePath" -Type Info
        
        $httpContent = Get-Content $httpFilePath -Raw
        
        if ($tenantDomain) {
            # Replace the TenantName variable
            $httpContent = $httpContent -replace '(?m)^@TenantName=.*$', "@TenantName=$tenantDomain"
            Set-Content $httpFilePath -Value $httpContent -NoNewline
            Write-Status "Updated TenantName to: $tenantDomain" -Type Success
        }
        else {
            Write-Status "Could not determine tenant domain. TenantName in .http file not updated." -Type Warning
        }
    }
    else {
        Write-Status ".http file not found: $httpFilePath" -Type Warning
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
        }
        else {
            Write-Status "Service config file not found: $serviceConfigPath" -Type Warning
        }
    }
    
    Write-Status "`nAll configuration files updated!" -Type Success
}

#endregion

# Run the setup
Invoke-Setup
