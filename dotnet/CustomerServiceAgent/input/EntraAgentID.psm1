# EntraAgentID PowerShell Module
# Provides functions for managing Entra Agent Identity Blueprints

# Module-level variable to store the current Agent Blueprint ID
$script:CurrentAgentBlueprintId = $null

# Module-level variable to store the current Agent Blueprint Secret
$script:CurrentAgentBlueprintSecret = $null

# Module-level variable to store the current Agent Identity Blueprint Service Principal ID
$script:CurrentAgentBlueprintServicePrincipalId = $null

# Module-level variable to cache the Microsoft Graph Service Principal ID
$script:MSGraphServicePrincipalId = $null

# Module-level variable to store the last configured inheritable scopes
$script:LastConfiguredInheritableScopes = $null

# Module-level variable to store the current Agent Identity ID
$script:CurrentAgentIdentityId = $null

# Module-level variable to store the current tenant ID
$script:CurrentTenantId = $null

# Module-level variable to store the last client secret
$script:LastClientSecret = $null

# Module-level variable to track the last successful connection type
$script:LastSuccessfulConnection = $null

# Module-level variable to store the current Agent User ID
$script:CurrentAgentUserId = $null

function Get-MSGraphServicePrincipalId {
    <#
    .SYNOPSIS
    Internal function to get the Microsoft Graph Service Principal ID
    
    .DESCRIPTION
    Retrieves the service principal ID (object ID) for Microsoft Graph (app ID 00000003-0000-0000-c000-000000000000)
    in the current tenant. Caches the result for subsequent calls to improve performance.
    
    .OUTPUTS
    String - The service principal ID (object ID) of Microsoft Graph
    #>
    
    # Return cached value if available
    if ($script:MSGraphServicePrincipalId) {
        Write-Verbose "Using cached Microsoft Graph Service Principal ID: $script:MSGraphServicePrincipalId"
        return $script:MSGraphServicePrincipalId
    }
    
    try {
        Write-Verbose "Retrieving Microsoft Graph Service Principal ID from tenant..."
        
        # Microsoft Graph App ID is always 00000003-0000-0000-c000-000000000000
        $msGraphAppId = "00000003-0000-0000-c000-000000000000"
        
        # Get the service principal for Microsoft Graph
        $msGraphServicePrincipal = Get-MgServicePrincipal -Filter "appId eq '$msGraphAppId'" -Select "id,appId,displayName"
        
        if (-not $msGraphServicePrincipal) {
            throw "Microsoft Graph Service Principal not found in tenant"
        }
        
        # Cache the result
        $script:MSGraphServicePrincipalId = $msGraphServicePrincipal.Id
        
        Write-Verbose "Microsoft Graph Service Principal found - ID: $script:MSGraphServicePrincipalId, Display Name: $($msGraphServicePrincipal.DisplayName)"
        
        return $script:MSGraphServicePrincipalId
    }
    catch {
        Write-Error "Failed to retrieve Microsoft Graph Service Principal ID: $_"
        throw
    }
}

function EnsureRequiredModules {
    <#
    .SYNOPSIS
    Ensures that required PowerShell modules are installed and imported
    
    .DESCRIPTION
    Checks for required modules and installs them if they are not available
    #>
    
    $requiredModules = @(
        'Microsoft.Graph.Authentication',
        'Microsoft.Graph.Applications',
        'Microsoft.Graph.Identity.SignIns'
    )
    
    foreach ($module in $requiredModules) {
        Write-Host "Checking module: $module" -ForegroundColor Yellow
        
        if (!(Get-Module -ListAvailable -Name $module)) {
            Write-Host "Module $module not found. Installing..." -ForegroundColor Red
            try {
                Install-Module -Name $module -Scope CurrentUser -Force -AllowClobber
                Write-Host "Successfully installed $module" -ForegroundColor Green
            }
            catch {
                Write-Error "Failed to install module $module`: $_"
                return $false
            }
        }
        else {
            Write-Host "Module $module is already installed" -ForegroundColor Green
        }
        
        # Import the module if not already imported
        if (!(Get-Module -Name $module)) {
            try {
                Import-Module -Name $module -Force
                Write-Host "Successfully imported $module" -ForegroundColor Green
            }
            catch {
                Write-Error "Failed to import module $module`: $_"
                return $false
            }
        }
    }
    
    return $true
}

function Connect-EntraAsUser {
    <#
    .SYNOPSIS
    Connects to Microsoft Graph as a user with required scopes and validates admin privileges
    
    .DESCRIPTION
    Establishes a connection to Microsoft Graph with the necessary permissions for Agent Identity operations
    and validates that the authenticated user has Global Admin or Global Reader role
    
    .PARAMETER Scopes
    Array of scopes to request. Defaults to AgentIdentityBlueprint.Create plus Directory.Read.All for role validation
    
    .EXAMPLE
    Connect-EntraAsUser
    
    .EXAMPLE
    Connect-EntraAsUser -Scopes @('AgentIdentityBlueprint.Create', 'User.ReadWrite.All')
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string[]]$Scopes = @('AgentIdentityBlueprint.Create', 'AgentIdentityBlueprintPrincipal.Create', 'AppRoleAssignment.ReadWrite.All', 'Application.ReadWrite.All', 'User.ReadWrite.All')
    )
    
    # Ensure required modules are available
    if (!(EnsureRequiredModules)) {
        Write-Error "Failed to ensure required modules are available."
        return
    }
    
    try {
        # Check if we need to disconnect from a different connection type
        if ($script:LastSuccessfulConnection -and $script:LastSuccessfulConnection -ne "EntraAsUser") {
            Write-Host "Disconnecting from previous connection type: $script:LastSuccessfulConnection" -ForegroundColor Yellow
            Disconnect-MgGraph -ErrorAction SilentlyContinue
        }
        
        Write-Host "Connecting to Microsoft Graph as user..." -ForegroundColor Yellow
        connect-mggraph -contextscope process -scopes $Scopes
        
        # Get the tenant ID and current user
        $context = Get-MgContext
        $tenantId = $context.TenantId
        $script:CurrentTenantId = $tenantId
        $script:LastSuccessfulConnection = "EntraAsUser"
        Write-Host "Connected to tenant: $tenantId" -ForegroundColor Green
       
        return $tenantId
    }
    catch {
        Write-Error "Failed to connect to Microsoft Graph or validate admin privileges: $_"
        throw
    }
}

function ConnectAsAgentIdentityBlueprint {
    <#
    .SYNOPSIS
    Connects to Microsoft Graph using stored Agent Identity Blueprint credentials
    
    .DESCRIPTION
    Internal function that connects to Microsoft Graph using the stored client secret from 
    Add-ClientSecretToAgentIdentityBlueprint and the stored blueprint ID and tenant ID
    
    .NOTES
    This is an internal function that requires:
    - $script:CurrentAgentBlueprintId to be set (from New-AgentIdentityBlueprint)
    - $script:LastClientSecret to be set (from Add-ClientSecretToAgentIdentityBlueprint)  
    - $script:CurrentTenantId to be set (from Connect-EntraAsUser)
    #>
    [CmdletBinding()]
    param()
    
    # Validate that we have the required stored values
    if (-not $script:CurrentAgentBlueprintId) {
        Write-Error "No Agent Identity Blueprint ID found. Please run New-AgentIdentityBlueprint first."
        return $false
    }
    
    if (-not $script:LastClientSecret) {
        Write-Error "No client secret found. Please run Add-ClientSecretToAgentIdentityBlueprint first."
        return $false
    }
    
    if (-not $script:CurrentTenantId) {
        Write-Error "No tenant ID found. Please run Connect-EntraAsUser or New-AgentIdentityBlueprint first."
        return $false
    }
    
    try {
        # Check if we need to disconnect from a different connection type
        if ($script:LastSuccessfulConnection -and $script:LastSuccessfulConnection -ne "AgentIdentityBlueprint") {
            Write-Host "Disconnecting from previous connection type: $script:LastSuccessfulConnection" -ForegroundColor Yellow
            Disconnect-MgGraph -ErrorAction SilentlyContinue
        }
        
        Write-Host "Connecting to Microsoft Graph using Agent Identity Blueprint credentials..." -ForegroundColor Yellow
        
        # Convert the stored client secret to a secure credential
        $SecureClientSecret = ConvertTo-SecureString $script:LastClientSecret -AsPlainText -Force
        $ClientSecretCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $script:CurrentAgentBlueprintId, $SecureClientSecret
        
        # Connect to Microsoft Graph using the blueprint's credentials
        connect-mggraph -tenantId $script:CurrentTenantId -ClientSecretCredential $ClientSecretCredential -ContextScope Process -NoWelcome
        
        $script:LastSuccessfulConnection = "AgentIdentityBlueprint"
        Write-Host "Successfully connected as Agent Identity Blueprint: $script:CurrentAgentBlueprintId" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Failed to connect to Microsoft Graph using Agent Identity Blueprint credentials: $_"
        return $false
    }
}

function Disconnect-MgGraphIfNeeded {
    <#
    .SYNOPSIS
    Internal function to disconnect from Microsoft Graph if currently connected
    
    .DESCRIPTION
    Safely disconnects from Microsoft Graph and clears the connection tracking state
    #>
    [CmdletBinding()]
    param()
    
    try {
        if ($script:LastSuccessfulConnection) {
            Write-Host "Disconnecting from Microsoft Graph (previous connection: $script:LastSuccessfulConnection)" -ForegroundColor Yellow
            Disconnect-MgGraph -ErrorAction SilentlyContinue
            $script:LastSuccessfulConnection = $null
        }
    }
    catch {
        # Silent failure on disconnect - not critical
        Write-Debug "Error during disconnect: $_"
    }
}

function Get-SponsorsAndOwners {
    <#
    .SYNOPSIS
    Internal function to prompt for and validate sponsors and owners
    
    .DESCRIPTION
    Prompts the user for sponsor and owner information when not provided,
    ensuring at least one sponsor or owner is specified
    
    .PARAMETER SponsorUserIds
    Array of user IDs to set as sponsors
    
    .PARAMETER SponsorGroupIds
    Array of group IDs to set as sponsors
    
    .PARAMETER OwnerUserIds
    Array of user IDs to set as owners
    
    .OUTPUTS
    Hashtable with SponsorUserIds, SponsorGroupIds, and OwnerUserIds arrays
    #>
    [CmdletBinding()]
    param (
        [string[]]$SponsorUserIds,
        [string[]]$SponsorGroupIds,
        [string[]]$OwnerUserIds
    )
    
    # Check if at least one owner or sponsor is provided, if not prompt for them
    $hasSponsorsOrOwners = (($SponsorUserIds -and $SponsorUserIds.Count -gt 0) -or 
                           ($SponsorGroupIds -and $SponsorGroupIds.Count -gt 0) -or 
                           ($OwnerUserIds -and $OwnerUserIds.Count -gt 0))
    
    if (-not $hasSponsorsOrOwners) {
        Write-Host "At least one owner or sponsor must be specified." -ForegroundColor Yellow
        Write-Host "Please provide at least one of the following:" -ForegroundColor Yellow
        
        # Prompt for sponsor users
        $sponsorUserInput = Read-Host "Enter sponsor user IDs (comma-separated, or press Enter to skip)"
        if ($sponsorUserInput -and $sponsorUserInput.Trim() -ne "") {
            $SponsorUserIds = $sponsorUserInput.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        }
        
        # Prompt for sponsor groups
        $sponsorGroupInput = Read-Host "Enter sponsor group IDs (comma-separated, or press Enter to skip)"
        if ($sponsorGroupInput -and $sponsorGroupInput.Trim() -ne "") {
            $SponsorGroupIds = $sponsorGroupInput.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        }
        
        # Prompt for owner users if no sponsors provided
        if ((-not $SponsorUserIds -or $SponsorUserIds.Count -eq 0) -and 
            (-not $SponsorGroupIds -or $SponsorGroupIds.Count -eq 0)) {
            do {
                $ownerUserInput = Read-Host "Enter owner user IDs (comma-separated, required since no sponsors provided)"
                if ($ownerUserInput -and $ownerUserInput.Trim() -ne "") {
                    $OwnerUserIds = $ownerUserInput.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
                }
            } while (-not $OwnerUserIds -or $OwnerUserIds.Count -eq 0)
        } else {
            # Optional owners if sponsors are already provided
            $ownerUserInput = Read-Host "Enter owner user IDs (comma-separated, or press Enter to skip)"
            if ($ownerUserInput -and $ownerUserInput.Trim() -ne "") {
                $OwnerUserIds = $ownerUserInput.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
            }
        }
    }
    
    return @{
        SponsorUserIds = $SponsorUserIds
        SponsorGroupIds = $SponsorGroupIds
        OwnerUserIds = $OwnerUserIds
    }
}

function New-AgentIdentityBlueprint {
    <#
    .SYNOPSIS
    Creates a new Agent Identity Blueprint
    
    .DESCRIPTION
    Uses Invoke-MgGraphRequest to post a request to create an Agent Identity Blueprint
    
    .PARAMETER DisplayName
    The display name for the Agent Identity Blueprint
    
    .PARAMETER SponsorUserIds
    Array of user IDs to set as sponsors
    
    .PARAMETER SponsorGroupIds
    Array of group IDs to set as sponsors
    
    .PARAMETER OwnerUserIds
    Array of user IDs to set as owners
    
    .NOTES
    At least one owner or sponsor (user or group) must be specified
    
    .EXAMPLE
    New-AgentIdentityBlueprint -DisplayName "My Blueprint" -SponsorUserIds @("user1") -OwnerUserIds @("owner1")
    
    .EXAMPLE
    New-AgentIdentityBlueprint  # Will prompt for all required parameters
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$DisplayName,
        
        [Parameter(Mandatory = $false)]
        [string[]]$SponsorUserIds,
        
        [Parameter(Mandatory = $false)]
        [string[]]$SponsorGroupIds,
        
        [Parameter(Mandatory = $false)]
        [string[]]$OwnerUserIds
    )
    
    # Ensure required modules are available and connect as admin
    Connect-EntraAsUser -Scopes @('AgentIdentityBlueprint.Create', 'AgentIdentityBlueprintPrincipal.Create', 'AppRoleAssignment.ReadWrite.All', 'Application.ReadWrite.All', 'User.ReadWrite.All')

    # Prompt for missing DisplayName if not provided
    if (-not $DisplayName -or $DisplayName.Trim() -eq "") {
        do {
            $DisplayName = Read-Host "Enter the display name for the Agent Identity Blueprint"
        } while (-not $DisplayName -or $DisplayName.Trim() -eq "")
    }
    
    # Get sponsors and owners (prompt if not provided)
    $sponsorsAndOwners = Get-SponsorsAndOwners -SponsorUserIds $SponsorUserIds -SponsorGroupIds $SponsorGroupIds -OwnerUserIds $OwnerUserIds
    $SponsorUserIds = $sponsorsAndOwners.SponsorUserIds
    $SponsorGroupIds = $sponsorsAndOwners.SponsorGroupIds
    $OwnerUserIds = $sponsorsAndOwners.OwnerUserIds
    
    # Build the request body
    $Body = [PSCustomObject]@{
        displayName = $DisplayName
    }
    
    # Add sponsors if provided
    if ($SponsorUserIds -or $SponsorGroupIds) {
        $sponsorBindings = @()
        
        if ($SponsorUserIds) {
            foreach ($userId in $SponsorUserIds) {
                $sponsorBindings += "https://graph.microsoft.com/v1.0/users/$userId"
            }
        }
        
        if ($SponsorGroupIds) {
            foreach ($groupId in $SponsorGroupIds) {
                $sponsorBindings += "https://graph.microsoft.com/v1.0/groups/$groupId"
            }
        }
        
        $Body | Add-Member -MemberType NoteProperty -Name "sponsors@odata.bind" -Value $sponsorBindings
    }
    
    # Add owners if provided
    if ($OwnerUserIds) {
        $ownerBindings = @()
        foreach ($userId in $OwnerUserIds) {
            $ownerBindings += "https://graph.microsoft.com/v1.0/users/$userId"
        }
        $Body | Add-Member -MemberType NoteProperty -Name "owners@odata.bind" -Value $ownerBindings
    }
    
    $JsonBody = $Body | ConvertTo-Json -Depth 5
    Write-Host "Creating Agent Identity Blueprint: $DisplayName" -ForegroundColor Yellow
    Write-Debug "Request Body: $JsonBody"
    
    try {
        $BlueprintRes = Invoke-MgGraphRequest -Method Post -Uri "https://graph.microsoft.com/beta/applications/graph.agentIdentityBlueprint" -Body $JsonBody
        
        # Extract and store the blueprint ID
        $AgentBlueprintId = $BlueprintRes.id
        Write-Host "Successfully created Agent Identity Blueprint" -ForegroundColor Green
        Write-Host "Agent Blueprint ID: $AgentBlueprintId" -ForegroundColor Cyan
        
        # Store the ID in module-level variable for use by other functions
        $script:CurrentAgentBlueprintId = $AgentBlueprintId
        
        # Add the ID to the response object for easy access
        $BlueprintRes | Add-Member -MemberType NoteProperty -Name "AgentBlueprintId" -Value $AgentBlueprintId -Force
        
        return $BlueprintRes
    }
    catch {
        Write-Error "Failed to create Agent Identity Blueprint: $_"
        throw
    }
}

function New-AgentIdentityBlueprintPrincipal {
    <#
    .SYNOPSIS
    Creates a service principal for the Agent Identity Blueprint
    
    .DESCRIPTION
    Creates a service principal for the current Agent Identity Blueprint using the specialized 
    graph.agentIdentityBlueprintPrincipal endpoint. Uses the stored AgentBlueprintId from 
    the last New-AgentIdentityBlueprint call.
    
    .PARAMETER AgentBlueprintId
    Optional. The Application ID (AppId) of the Agent Identity Blueprint to create the service principal for. 
    If not provided, uses the stored ID from the last blueprint creation.
    
    .EXAMPLE
    New-AgentIdentityBlueprint -DisplayName "My Blueprint" -SponsorUserIds @("user1")
    New-AgentIdentityBlueprintPrincipal
    
    .EXAMPLE
    New-AgentIdentityBlueprintPrincipal -AgentBlueprintId "021fe0d0-d128-4769-950c-fcfbf7b87def"
    
    .OUTPUTS
    Returns the service principal response object from Microsoft Graph
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$AgentBlueprintId
    )
    
    # Use provided ID or fall back to stored ID
    if (-not $AgentBlueprintId) {
        if (-not $script:CurrentAgentBlueprintId) {
            throw "No Agent Blueprint ID provided and no stored ID available. Please run New-AgentIdentityBlueprint first or provide the AgentBlueprintId parameter."
        }
        $AgentBlueprintId = $script:CurrentAgentBlueprintId
        Write-Host "Using stored Agent Blueprint ID: $AgentBlueprintId" -ForegroundColor Yellow
    }
    else {
        Write-Host "Using provided Agent Blueprint ID: $AgentBlueprintId" -ForegroundColor Yellow
    }
    
    # Ensure we're connected to Microsoft Graph
    $context = Get-MgContext
    if (-not $context) {
        Write-Host "Not connected to Microsoft Graph. Attempting to connect..." -ForegroundColor Yellow
        Connect-EntraAsUser
    }
    else {
        Write-Host "Connected to Microsoft Graph as: $($context.Account)" -ForegroundColor Green
    }
    
    try {
        Write-Host "Creating Agent Identity Blueprint Service Principal..." -ForegroundColor Green
        
        # Prepare the body for the service principal creation
        $body = @{
            appId = $AgentBlueprintId
        }
        
        # Create the service principal using the specialized endpoint
        Write-Host "Making request to create service principal for Agent Blueprint: $AgentBlueprintId" -ForegroundColor Cyan
        
        $servicePrincipalResponse = Invoke-MgRestMethod -Uri "/beta/serviceprincipals/graph.agentIdentityBlueprintPrincipal" -Method POST -Body ($body | ConvertTo-Json) -ContentType "application/json"
        
        Write-Host "Successfully created Agent Identity Blueprint Service Principal" -ForegroundColor Green
        Write-Host "Service Principal ID: $($servicePrincipalResponse.id)" -ForegroundColor Cyan
        Write-Host "Service Principal App ID: $($servicePrincipalResponse.appId)" -ForegroundColor Cyan
        
        # Store the service principal ID in module-level variable for use by other functions
        $script:CurrentAgentBlueprintServicePrincipalId = $servicePrincipalResponse.id
        
        return $servicePrincipalResponse
    }
    catch {
        Write-Error "Failed to create Agent Identity Blueprint Service Principal: $_"
        if ($_.Exception.Response) {
            Write-Host "Response Status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
            if ($_.Exception.Response.Content) {
                Write-Host "Response Content: $($_.Exception.Response.Content)" -ForegroundColor Red
            }
        }
        throw
    }
}

function Add-ClientSecretToAgentIdentityBlueprint {
    <#
    .SYNOPSIS
    Adds a client secret to the current Agent Identity Blueprint
    
    .DESCRIPTION
    Creates an application password for the most recently created Agent Identity Blueprint using New-MgApplicationPassword.
    Uses the stored AgentBlueprintId from the last New-AgentIdentityBlueprint call.
    
    .PARAMETER AgentBlueprintId
    Optional. The ID of the Agent Identity Blueprint to add the secret to. If not provided, uses the stored ID from the last blueprint creation.
    
    .EXAMPLE
    New-AgentIdentityBlueprint -DisplayName "My Blueprint" -SponsorUserIds @("user1")
    Add-ClientSecretToAgentIdentityBlueprint  # Uses the stored blueprint ID
    
    .EXAMPLE
    Add-ClientSecretToAgentIdentityBlueprint -AgentBlueprintId "12345678-1234-1234-1234-123456789012"  # Uses specific ID
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$AgentBlueprintId
    )
    
    # Use stored blueprint ID if not provided
    if (-not $AgentBlueprintId) {
        if (-not $script:CurrentAgentBlueprintId) {
            Write-Error "No Agent Blueprint ID available. Please create a blueprint first using New-AgentIdentityBlueprint or provide an explicit AgentBlueprintId parameter."
            return
        }
        $AgentBlueprintId = $script:CurrentAgentBlueprintId
        Write-Host "Using stored Agent Blueprint ID: $AgentBlueprintId" -ForegroundColor Gray
    }
    
    # Ensure we're connected to Microsoft Graph
    $context = Get-MgContext
    if (-not $context) {
        Write-Error "Not connected to Microsoft Graph. Please run Connect-MgGraph first."
        return
    }
    
    try {
        Write-Host "Adding secret to Agent Blueprint: $AgentBlueprintId" -ForegroundColor Yellow
        
        # Create the password credential object
        $passwordCredential = @{
            displayName = "1st blueprint secret for dev/test. Not recommended for production use"
            endDateTime = (Get-Date).AddDays(90).ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
        
        # Add the secret to the application
        $secretResult = Add-MgApplicationPassword -ApplicationId $AgentBlueprintId -PasswordCredential $passwordCredential
        
        Write-Host "Successfully added secret to Agent Blueprint" -ForegroundColor Green
        Write-Host "Secret Value: $($secretResult.SecretText)" -ForegroundColor Red
        
        # Add additional properties for easy access
        $secretResult | Add-Member -MemberType NoteProperty -Name "Description" -Value "Not recommended for production use" -Force
        $secretResult | Add-Member -MemberType NoteProperty -Name "AgentBlueprintId" -Value $AgentBlueprintId -Force
        
        # Store the secret in module-level variables for use by other functions
        $script:CurrentAgentBlueprintSecret = $secretResult
        $script:LastClientSecret = $secretResult.SecretText
        
        return $secretResult
    }
    catch {
        Write-Error "Failed to add secret to Agent Blueprint: $_"
        throw
    }
}

function Add-ScopeToAgentIdentityBlueprint {
    <#
    .SYNOPSIS
    Adds an OAuth2 permission scope to the current Agent Identity Blueprint
    
    .DESCRIPTION
    Adds a custom OAuth2 permission scope to the Agent Identity Blueprint, allowing applications
    to request specific permissions when accessing the agent. Uses the stored AgentBlueprintId
    from the last New-AgentIdentityBlueprint call.
    
    .PARAMETER AgentBlueprintId
    Optional. The ID of the Agent Identity Blueprint to add the scope to. If not provided, uses the stored ID from the last blueprint creation.
    
    .PARAMETER AdminConsentDescription
    Optional. The description that appears in admin consent experiences. If not provided, will prompt for input.
    
    .PARAMETER AdminConsentDisplayName
    Optional. The display name that appears in admin consent experiences. If not provided, will prompt for input.
    
    .PARAMETER Value
    Optional. The value of the permission scope (used in token claims). If not provided, will prompt for input.
    
    .EXAMPLE
    New-AgentIdentityBlueprint -DisplayName "My Blueprint" -SponsorUserIds @("user1")
    Add-ScopeToAgentIdentityBlueprint  # Will prompt for scope details
    
    .EXAMPLE
    Add-ScopeToAgentIdentityBlueprint -AdminConsentDescription "Allow agent access" -AdminConsentDisplayName "Agent Access" -Value "agent_access"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$AgentBlueprintId,
        
        [Parameter(Mandatory = $false)]
        [string]$AdminConsentDescription,
        
        [Parameter(Mandatory = $false)]
        [string]$AdminConsentDisplayName,
        
        [Parameter(Mandatory = $false)]
        [string]$Value
    )
    
    # Use stored blueprint ID if not provided
    if (-not $AgentBlueprintId) {
        if (-not $script:CurrentAgentBlueprintId) {
            Write-Error "No Agent Blueprint ID available. Please create a blueprint first using New-AgentIdentityBlueprint or provide an explicit AgentBlueprintId parameter."
            return
        }
        $AgentBlueprintId = $script:CurrentAgentBlueprintId
        Write-Host "Using stored Agent Blueprint ID: $AgentBlueprintId" -ForegroundColor Gray
    }
    
    # Prompt for missing parameters
    if (-not $AdminConsentDescription -or $AdminConsentDescription.Trim() -eq "") {
        $defaultDescription = "Access AI as the current user"
        Write-Host "Default: $defaultDescription" -ForegroundColor Gray
        $userInput = Read-Host "Enter the admin consent description for the scope (press Enter for default)"
        if ($userInput -and $userInput.Trim() -ne "") {
            $AdminConsentDescription = $userInput.Trim()
        } else {
            $AdminConsentDescription = $defaultDescription
            Write-Host "Using default: $AdminConsentDescription" -ForegroundColor Cyan
        }
    }
    
    if (-not $AdminConsentDisplayName -or $AdminConsentDisplayName.Trim() -eq "") {
        $defaultDisplayName = "Access AI as user"
        Write-Host "Default: $defaultDisplayName" -ForegroundColor Gray
        $userInput = Read-Host "Enter the admin consent display name for the scope (press Enter for default)"
        if ($userInput -and $userInput.Trim() -ne "") {
            $AdminConsentDisplayName = $userInput.Trim()
        } else {
            $AdminConsentDisplayName = $defaultDisplayName
            Write-Host "Using default: $AdminConsentDisplayName" -ForegroundColor Cyan
        }
    }
    
    if (-not $Value -or $Value.Trim() -eq "") {
        $defaultValue = "access_AI_as_user"
        Write-Host "Default: $defaultValue" -ForegroundColor Gray
        $userInput = Read-Host "Enter the scope value (used in token claims, press Enter for default)"
        if ($userInput -and $userInput.Trim() -ne "") {
            $Value = $userInput.Trim()
        } else {
            $Value = $defaultValue
            Write-Host "Using default: $Value" -ForegroundColor Cyan
        }
    }
    
    # Ensure we're connected to Microsoft Graph
    $context = Get-MgContext
    if (-not $context) {
        Write-Error "Not connected to Microsoft Graph. Please run Connect-MgGraph first."
        return
    }
    
    try {
        Write-Host "Adding OAuth2 permission scope to Agent Blueprint: $AgentBlueprintId" -ForegroundColor Yellow
        Write-Host "Scope Details:" -ForegroundColor Cyan
        Write-Host "  Description: $AdminConsentDescription" -ForegroundColor White
        Write-Host "  Display Name: $AdminConsentDisplayName" -ForegroundColor White
        Write-Host "  Value: $Value" -ForegroundColor White
        
        # Generate a new GUID for the scope ID
        $scopeId = [System.Guid]::NewGuid().ToString()
        
        # Build the request body
        $Body = [PSCustomObject]@{
            identifierUris = @("api://$AgentBlueprintId")
            api = [PSCustomObject]@{
                oauth2PermissionScopes = @(
                    [PSCustomObject]@{
                        adminConsentDescription = $AdminConsentDescription
                        adminConsentDisplayName = $AdminConsentDisplayName
                        id = $scopeId
                        isEnabled = $true
                        type = "User"
                        value = $Value
                    }
                )
            }
        }
        
        $JsonBody = $Body | ConvertTo-Json -Depth 5
        Write-Debug "Request Body: $JsonBody"
        
        # Use Invoke-MgRestMethod to update the application
        $scopeResult = Invoke-MgRestMethod -Method PATCH -Uri "https://graph.microsoft.com/v1.0/applications/$AgentBlueprintId" -Body $JsonBody -ContentType "application/json"
        
        Write-Host "Successfully added OAuth2 permission scope to Agent Blueprint" -ForegroundColor Green
        Write-Host "Scope ID: $scopeId" -ForegroundColor Cyan
        Write-Host "Identifier URI: api://$AgentBlueprintId" -ForegroundColor Cyan
        
        # Create a result object with scope information
        $result = [PSCustomObject]@{
            ScopeId = $scopeId
            AdminConsentDescription = $AdminConsentDescription
            AdminConsentDisplayName = $AdminConsentDisplayName
            Value = $Value
            IdentifierUri = "api://$AgentBlueprintId"
            AgentBlueprintId = $AgentBlueprintId
            FullScopeReference = "api://$AgentBlueprintId/$Value"
        }
        
        return $result
    }
    catch {
        Write-Error "Failed to add OAuth2 permission scope to Agent Blueprint: $_"
        throw
    }
}

function Add-InheritablePermissionsToAgentIdentityBlueprint {
    <#
    .SYNOPSIS
    Adds inheritable permissions to Agent Identity Blueprints
    
    .DESCRIPTION
    Configures inheritable Microsoft Graph permissions that can be granted to Agent Identity Blueprints.
    This allows agents created from the blueprint to inherit specific Microsoft Graph permissions.
    
    .PARAMETER Scopes
    Optional. Array of Microsoft Graph permission scopes to make inheritable. If not provided, will prompt for input.
    Common scopes include: User.Read, Mail.Read, Calendars.Read, etc.
    
    .PARAMETER ResourceAppId
    Optional. The resource application ID. Defaults to Microsoft Graph (00000003-0000-0000-c000-000000000000).
    
    .EXAMPLE
    Add-InheritablePermissionsToAgentIdentityBlueprint  # Will prompt for scopes
    
    .EXAMPLE
    Add-InheritablePermissionsToAgentIdentityBlueprint -Scopes @("User.Read", "Mail.Read", "Calendars.Read")
    
    .EXAMPLE
    Add-InheritablePermissionsToAgentIdentityBlueprint -Scopes @("User.Read") -ResourceAppId "00000003-0000-0000-c000-000000000000"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string[]]$Scopes,
        
        [Parameter(Mandatory = $false)]
        [string]$ResourceAppId = "00000003-0000-0000-c000-000000000000"
    )
    
    # Prompt for ResourceAppId if not provided
    if (-not $ResourceAppId -or $ResourceAppId.Trim() -eq "") {
        Write-Host "Enter the Resource Application ID for the permissions." -ForegroundColor Yellow
        Write-Host "Default: 00000003-0000-0000-c000-000000000000 (Microsoft Graph)" -ForegroundColor Gray
        
        $resourceInput = Read-Host "Resource App ID (press Enter for Microsoft Graph default)"
        if ($resourceInput -and $resourceInput.Trim() -ne "") {
            $ResourceAppId = $resourceInput.Trim()
        } else {
            $ResourceAppId = "00000003-0000-0000-c000-000000000000"
            Write-Host "Using default: Microsoft Graph" -ForegroundColor Cyan
        }
    }
    
    # Determine resource name for display
    $resourceName = switch ($ResourceAppId) {
        "00000003-0000-0000-c000-000000000000" { "Microsoft Graph" }
        "00000002-0000-0000-c000-000000000000" { "Azure Active Directory Graph" }
        default { "Custom Resource ($ResourceAppId)" }
    }
    
    # Prompt for scopes if not provided
    if (-not $Scopes -or $Scopes.Count -eq 0) {
        Write-Host "Enter permission scopes to make inheritable for $resourceName." -ForegroundColor Yellow
        if ($ResourceAppId -eq "00000003-0000-0000-c000-000000000000") {
            Write-Host "Common Microsoft Graph scopes: User.Read, Mail.Read, Calendars.Read, Files.Read, etc." -ForegroundColor Gray
        }
        Write-Host "Enter multiple scopes separated by commas." -ForegroundColor Gray
        
        do {
            $scopeInput = Read-Host "Enter permission scopes (comma-separated)"
            if ($scopeInput -and $scopeInput.Trim() -ne "") {
                $Scopes = $scopeInput.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
            }
        } while (-not $Scopes -or $Scopes.Count -eq 0)
    }
    
    # Check if we have a stored Agent Blueprint ID
    if (-not $script:CurrentAgentBlueprintId) {
        Write-Error "No Agent Blueprint ID available. Please create a blueprint first using New-AgentIdentityBlueprint."
        return
    }
    
    # Ensure we're connected to Microsoft Graph
    $context = Get-MgContext
    if (-not $context) {
        Write-Error "Not connected to Microsoft Graph. Please run Connect-MgGraph first."
        return
    }
    
    try {
        Write-Host "Adding inheritable permissions to Agent Identity Blueprint..." -ForegroundColor Yellow
        Write-Host "Agent Blueprint ID: $($script:CurrentAgentBlueprintId)" -ForegroundColor Gray
        Write-Host "Resource App ID: $ResourceAppId ($resourceName)" -ForegroundColor Cyan
        Write-Host "Scopes to make inheritable:" -ForegroundColor Cyan
        foreach ($scope in $Scopes) {
            Write-Host "  - $scope" -ForegroundColor White
        }
        
        # Build the request body
        $Body = [PSCustomObject]@{
            resourceAppId = $ResourceAppId
            inheritableScopes = [PSCustomObject]@{
                "@odata.type" = "microsoft.graph.enumeratedScopes"
                scopes = $Scopes
            }
        }
        
        $JsonBody = $Body | ConvertTo-Json -Depth 5
        Write-Debug "Request Body: $JsonBody"
        
        # Use Invoke-MgRestMethod to make the API call with the stored Agent Blueprint ID
        $apiUrl = "https://graph.microsoft.com/beta/applications/microsoft.graph.agentIdentityBlueprint/$($script:CurrentAgentBlueprintId)/inheritablePermissions"
        Write-Debug "API URL: $apiUrl"
        $result = Invoke-MgRestMethod -Method POST -Uri $apiUrl -Body $JsonBody -ContentType "application/json"
        
        Write-Host "Successfully added inheritable permissions to Agent Identity Blueprints" -ForegroundColor Green
        Write-Host "Permissions are now available for inheritance by agent blueprints" -ForegroundColor Green
        
        # Store the scopes for use in other functions
        $script:LastConfiguredInheritableScopes = $Scopes
        
        # Create a result object with permission information
        $permissionResult = [PSCustomObject]@{
            AgentBlueprintId = $script:CurrentAgentBlueprintId
            ResourceAppId = $ResourceAppId
            ResourceAppName = $resourceName
            InheritableScopes = $Scopes
            ScopeCount = $Scopes.Count
            ConfiguredAt = Get-Date
            ApiResponse = $result
        }
        
        return $permissionResult
    }
    catch {
        Write-Error "Failed to add inheritable permissions: $_"
        if ($_.Exception.Response) {
            Write-Host "Response Status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
            if ($_.Exception.Response.Content) {
                Write-Host "Response Content: $($_.Exception.Response.Content)" -ForegroundColor Red
            }
        }
        throw
    }
}

function Add-RedirectURIToAgentIdentityBlueprint {
    <#
    .SYNOPSIS
    Adds a web redirect URI to the current Agent Identity Blueprint
    
    .DESCRIPTION
    Configures a web redirect URI for the Agent Identity Blueprint application registration.
    This allows the application to receive authorization callbacks at the specified URI.
    Uses the stored AgentBlueprintId from the last New-AgentIdentityBlueprint call.
    
    .PARAMETER RedirectUri
    Optional. The redirect URI to add. Defaults to "http://localhost".
    
    .PARAMETER AgentBlueprintId
    Optional. The ID of the Agent Identity Blueprint to configure. If not provided, uses the stored ID from the last blueprint creation.
    
    .EXAMPLE
    New-AgentIdentityBlueprint -DisplayName "My Blueprint" -SponsorUserIds @("user1")
    Add-RedirectURIToAgentIdentityBlueprint  # Uses default "http://localhost"
    
    .EXAMPLE
    Add-RedirectURIToAgentIdentityBlueprint -RedirectUri "http://localhost:3000"
    
    .EXAMPLE
    Add-RedirectURIToAgentIdentityBlueprint -RedirectUri "https://myapp.com/callback" -AgentBlueprintId "12345678-1234-1234-1234-123456789012"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$RedirectUri = "http://localhost",
        
        [Parameter(Mandatory = $false)]
        [string]$AgentBlueprintId
    )
    
    # Use stored blueprint ID if not provided
    if (-not $AgentBlueprintId) {
        if (-not $script:CurrentAgentBlueprintId) {
            Write-Error "No Agent Blueprint ID available. Please create a blueprint first using New-AgentIdentityBlueprint or provide an explicit AgentBlueprintId parameter."
            return
        }
        $AgentBlueprintId = $script:CurrentAgentBlueprintId
        Write-Host "Using stored Agent Blueprint ID: $AgentBlueprintId" -ForegroundColor Gray
    }
    
    # Ensure we're connected to Microsoft Graph
    $context = Get-MgContext
    if (-not $context) {
        Write-Error "Not connected to Microsoft Graph. Please run Connect-MgGraph first."
        return
    }
    
    try {
        Write-Host "Adding web redirect URI to Agent Identity Blueprint..." -ForegroundColor Yellow
        Write-Host "Agent Blueprint ID: $AgentBlueprintId" -ForegroundColor Gray
        Write-Host "Redirect URI: $RedirectUri" -ForegroundColor Cyan
        
        # First, get the current application configuration to preserve existing redirect URIs
        Write-Host "Retrieving current application configuration..." -ForegroundColor Yellow
        $currentApp = Invoke-MgRestMethod -Method GET -Uri "https://graph.microsoft.com/v1.0/applications/$AgentBlueprintId" -ContentType "application/json"
        
        # Get existing redirect URIs or initialize empty array
        $existingRedirectUris = @()
        if ($currentApp.web -and $currentApp.web.redirectUris) {
            $existingRedirectUris = $currentApp.web.redirectUris
        }
        
        # Check if the redirect URI already exists
        if ($existingRedirectUris -contains $RedirectUri) {
            Write-Host "Redirect URI '$RedirectUri' already exists in the application" -ForegroundColor Yellow
            
            $result = [PSCustomObject]@{
                AgentBlueprintId = $AgentBlueprintId
                RedirectUri = $RedirectUri
                Action = "Already Exists"
                AllRedirectUris = $existingRedirectUris
                ConfiguredAt = Get-Date
            }
            
            return $result
        }
        
        # Add the new redirect URI to the existing ones
        $updatedRedirectUris = $existingRedirectUris + $RedirectUri
        
        # Build the request body to update the web redirect URIs
        $Body = [PSCustomObject]@{
            web = [PSCustomObject]@{
                redirectUris = $updatedRedirectUris
            }
        }
        
        $JsonBody = $Body | ConvertTo-Json -Depth 5
        Write-Debug "Request Body: $JsonBody"
        
        # Use Invoke-MgRestMethod to update the application
        $updateResult = Invoke-MgRestMethod -Method PATCH -Uri "https://graph.microsoft.com/v1.0/applications/$AgentBlueprintId" -Body $JsonBody -ContentType "application/json"
        
        Write-Host "Successfully added web redirect URI to Agent Identity Blueprint" -ForegroundColor Green
        Write-Host "Total redirect URIs: $($updatedRedirectUris.Count)" -ForegroundColor Cyan
        
        # Create a result object with redirect URI information
        $result = [PSCustomObject]@{
            AgentBlueprintId = $AgentBlueprintId
            RedirectUri = $RedirectUri
            Action = "Added"
            AllRedirectUris = $updatedRedirectUris
            ConfiguredAt = Get-Date
            ApiResponse = $updateResult
        }
        
        return $result
    }
    catch {
        Write-Error "Failed to add redirect URI to Agent Identity Blueprint: $_"
        if ($_.Exception.Response) {
            Write-Host "Response Status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
            if ($_.Exception.Response.Content) {
                Write-Host "Response Content: $($_.Exception.Response.Content)" -ForegroundColor Red
            }
        }
        throw
    }
}

function Add-PermissionToCreateAgentUsersToAgentIdentityBlueprintPrincipal {
    <#
    .SYNOPSIS
    Grants permission to create Agent Users to the Agent Identity Blueprint Principal
    
    .DESCRIPTION
    Adds the AgentIdUser.ReadWrite.IdentityParentedBy permission to the Agent Identity Blueprint Service Principal.
    This permission allows the blueprint to create agent users that are parented to agent identities.
    Uses the stored AgentBlueprintId from the last New-AgentIdentityBlueprint call and the cached Microsoft Graph Service Principal ID.
    
    .PARAMETER AgentBlueprintId
    Optional. The ID of the Agent Identity Blueprint Service Principal to grant permissions to. 
    If not provided, uses the stored ID from the last blueprint creation.
    
    .EXAMPLE
    New-AgentIdentityBlueprint -DisplayName "My Blueprint" -SponsorUserIds @("user1")
    New-AgentIdentityBlueprintPrincipal
    Add-PermissionToCreateAgentUsersToAgentIdentityBlueprintPrincipal
    
    .EXAMPLE
    Add-PermissionToCreateAgentUsersToAgentIdentityBlueprintPrincipal -AgentBlueprintId "7c0c1226-1e81-41a5-ad6c-532c95504443"
    
    .OUTPUTS
    Returns the app role assignment response object from Microsoft Graph
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$AgentBlueprintId
    )
    
    # Use provided ID or fall back to stored ID
    if (-not $AgentBlueprintId) {
        if (-not $script:CurrentAgentBlueprintId) {
            throw "No Agent Blueprint ID provided and no stored ID available. Please run New-AgentIdentityBlueprint first or provide the AgentBlueprintId parameter."
        }
        $AgentBlueprintId = $script:CurrentAgentBlueprintId
        Write-Host "Using stored Agent Blueprint ID: $AgentBlueprintId" -ForegroundColor Yellow
    }
    else {
        Write-Host "Using provided Agent Blueprint ID: $AgentBlueprintId" -ForegroundColor Yellow
    }
    
    # Ensure we're connected to Microsoft Graph
    $context = Get-MgContext
    if (-not $context) {
        Write-Host "Not connected to Microsoft Graph. Attempting to connect..." -ForegroundColor Yellow
        Connect-EntraAsUser
    }
    else {
        Write-Host "Connected to Microsoft Graph as: $($context.Account)" -ForegroundColor Green
    }
    
    try {
        Write-Host "Adding permission to create Agent Users to Agent Identity Blueprint Principal..." -ForegroundColor Green
        
        # Check if we have the service principal ID from New-AgentIdentityBlueprintPrincipal
        if (-not $script:CurrentAgentBlueprintServicePrincipalId) {
            throw "No Agent Identity Blueprint Service Principal ID available. Please run New-AgentIdentityBlueprintPrincipal first."
        }
        
        $servicePrincipalId = $script:CurrentAgentBlueprintServicePrincipalId
        Write-Host "Using stored Agent Identity Blueprint Service Principal ID: $servicePrincipalId" -ForegroundColor Yellow
        
        # Get the Microsoft Graph Service Principal ID using our internal function
        Write-Host "Retrieving Microsoft Graph Service Principal ID..." -ForegroundColor Cyan
        $msGraphServicePrincipalId = Get-MSGraphServicePrincipalId
        Write-Host "Microsoft Graph Service Principal ID: $msGraphServicePrincipalId" -ForegroundColor Cyan
        
        # AgentIdUser.ReadWrite.IdentityParentedBy permission ID
        $appRoleId = "4aa6e624-eee0-40ab-bdd8-f9639038a614"
        Write-Host "App Role ID (AgentIdUser.ReadWrite.IdentityParentedBy): $appRoleId" -ForegroundColor Cyan
        
        # Prepare the body for the app role assignment
        $body = @{
            principalId = $servicePrincipalId
            resourceId = $msGraphServicePrincipalId
            appRoleId = $appRoleId
        }
        
        Write-Host "Request Details:" -ForegroundColor Cyan
        Write-Host "  Principal ID (Service Principal): $servicePrincipalId" -ForegroundColor White
        Write-Host "  Resource ID (Microsoft Graph): $msGraphServicePrincipalId" -ForegroundColor White
        Write-Host "  App Role ID: $appRoleId (AgentIdUser.ReadWrite.IdentityParentedBy)" -ForegroundColor White
        
        # Create the app role assignment using the Microsoft Graph REST API
        $apiUrl = "/beta/servicePrincipals/$servicePrincipalId/appRoleAssignments"
        Write-Host "Making request to: $apiUrl" -ForegroundColor Cyan
        
        $appRoleAssignmentResponse = Invoke-MgRestMethod -Uri $apiUrl -Method POST -Body ($body | ConvertTo-Json) -ContentType "application/json"
        
        Write-Host "Successfully granted AgentIdUser.ReadWrite.IdentityParentedBy permission" -ForegroundColor Green
        Write-Host "App Role Assignment ID: $($appRoleAssignmentResponse.id)" -ForegroundColor Cyan
        Write-Host "Principal ID: $($appRoleAssignmentResponse.principalId)" -ForegroundColor Cyan
        Write-Host "Resource ID: $($appRoleAssignmentResponse.resourceId)" -ForegroundColor Cyan
        Write-Host "App Role ID: $($appRoleAssignmentResponse.appRoleId)" -ForegroundColor Cyan
        
        # Add descriptive properties to the response
        $appRoleAssignmentResponse | Add-Member -MemberType NoteProperty -Name "AgentBlueprintId" -Value $AgentBlueprintId -Force
        $appRoleAssignmentResponse | Add-Member -MemberType NoteProperty -Name "AgentBlueprintServicePrincipalId" -Value $servicePrincipalId -Force
        $appRoleAssignmentResponse | Add-Member -MemberType NoteProperty -Name "PermissionName" -Value "AgentIdUser.ReadWrite.IdentityParentedBy" -Force
        $appRoleAssignmentResponse | Add-Member -MemberType NoteProperty -Name "PermissionDescription" -Value "Allows creation of agent users parented to agent identities" -Force
        $appRoleAssignmentResponse | Add-Member -MemberType NoteProperty -Name "MSGraphServicePrincipalId" -Value $msGraphServicePrincipalId -Force
        
        return $appRoleAssignmentResponse
    }
    catch {
        Write-Error "Failed to add AgentIdUser.ReadWrite.IdentityParentedBy permission to Agent Identity Blueprint Principal: $_"
        if ($_.Exception.Response) {
            Write-Host "Response Status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
            if ($_.Exception.Response.Content) {
                Write-Host "Response Content: $($_.Exception.Response.Content)" -ForegroundColor Red
            }
        }
        throw
    }
}

function Add-PermissionsToInheritToAgentIdentityBlueprintPrincipal {
    <#
    .SYNOPSIS
    Opens admin consent page in browser for Agent Identity Blueprint Principal to inherit permissions
    
    .DESCRIPTION
    Launches the system browser with the admin consent URL for the Agent Identity Blueprint Principal.
    This allows the administrator to grant permissions that the blueprint can inherit and use.
    Uses the stored AgentBlueprintId from the last New-AgentIdentityBlueprint call.
    
    .PARAMETER AgentBlueprintId
    Optional. The Application ID (AppId) of the Agent Identity Blueprint to grant consent for. 
    If not provided, uses the stored ID from the last blueprint creation.
    
    .PARAMETER Scope
    Optional. The permission scopes to request consent for. Defaults to "user.read mail.read".
    Use space-separated scope names (e.g., "user.read mail.read calendars.read").
    
    .PARAMETER RedirectUri
    Optional. The redirect URI after consent. Defaults to "https://entra.microsoft.com/TokenAuthorize".
    
    .PARAMETER State
    Optional. State parameter for the consent request. Defaults to a random value.
    
    .EXAMPLE
    New-AgentIdentityBlueprint -DisplayName "My Blueprint" -SponsorUserIds @("user1")
    Add-PermissionsToInheritToAgentIdentityBlueprintPrincipal
    
    .EXAMPLE
    Add-PermissionsToInheritToAgentIdentityBlueprintPrincipal -Scope "user.read mail.read calendars.read"
    
    .EXAMPLE
    Add-PermissionsToInheritToAgentIdentityBlueprintPrincipal -AgentBlueprintId "7c0c1226-1e81-41a5-ad6c-532c95504443" -Scope "user.read"
    
    .OUTPUTS
    Returns an object with the consent URL and parameters used
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$AgentBlueprintId,
        
        [Parameter(Mandatory=$false)]
        [string]$Scope = "user.read mail.read",
        
        [Parameter(Mandatory=$false)]
        [string]$RedirectUri = "https://entra.microsoft.com/TokenAuthorize",
        
        [Parameter(Mandatory=$false)]
        [string]$State
    )
    
    # Use provided ID or fall back to stored ID
    if (-not $AgentBlueprintId) {
        if (-not $script:CurrentAgentBlueprintId) {
            throw "No Agent Blueprint ID provided and no stored ID available. Please run New-AgentIdentityBlueprint first or provide the AgentBlueprintId parameter."
        }
        $AgentBlueprintId = $script:CurrentAgentBlueprintId
        Write-Host "Using stored Agent Blueprint ID: $AgentBlueprintId" -ForegroundColor Yellow
    }
    else {
        Write-Host "Using provided Agent Blueprint ID: $AgentBlueprintId" -ForegroundColor Yellow
    }
    
    # Prompt for scopes if not provided or if using defaults
    if (-not $Scope -or $Scope.Trim() -eq "" -or $Scope -eq "user.read mail.read") {
        $suggestedScope = "user.read mail.read"  # Default fallback
        
        # Use previously configured inheritable scopes as suggestion if available
        if ($script:LastConfiguredInheritableScopes -and $script:LastConfiguredInheritableScopes.Count -gt 0) {
            # Convert array to space-separated string and make lowercase for consistency
            $suggestedScope = ($script:LastConfiguredInheritableScopes | ForEach-Object { $_.ToLower() }) -join " "
            Write-Host "Found previously configured inheritable scopes from Add-InheritablePermissionsToAgentIdentityBlueprint" -ForegroundColor Green
        }
        
        Write-Host "Enter permission scopes for admin consent." -ForegroundColor Yellow
        Write-Host "These scopes will be requested during the admin consent flow." -ForegroundColor Gray
        Write-Host "Suggested (from inheritable permissions): $suggestedScope" -ForegroundColor Cyan
        Write-Host "You can edit these scopes before submitting." -ForegroundColor Gray
        
        # Pre-populate with suggested scopes and allow editing
        Write-Host "Current scopes: $suggestedScope" -ForegroundColor Yellow
        $userInput = Read-Host "Edit permission scopes (space-separated, press Enter to use current)"
        if ($userInput -and $userInput.Trim() -ne "") {
            $Scope = $userInput.Trim()
        } else {
            $Scope = $suggestedScope
            Write-Host "Using suggested scopes: $Scope" -ForegroundColor Cyan
        }
    }
    
    # Generate a random state if not provided
    if (-not $State) {
        $State = "xyz$(Get-Random -Minimum 100 -Maximum 999999)"
    }
    
    # Ensure we're connected to Microsoft Graph to get tenant ID
    $context = Get-MgContext
    if (-not $context) {
        Write-Host "Not connected to Microsoft Graph. Attempting to connect..." -ForegroundColor Yellow
        Connect-EntraAsUser
        $context = Get-MgContext
    }
    
    if (-not $context.TenantId) {
        throw "Unable to determine tenant ID. Please ensure you're connected to Microsoft Graph."
    }
    
    $tenantId = $context.TenantId
    Write-Host "Connected to Microsoft Graph as: $($context.Account)" -ForegroundColor Green
    Write-Host "Tenant ID: $tenantId" -ForegroundColor Cyan
    
    try {
        Write-Host "Preparing admin consent page for Agent Identity Blueprint Principal..." -ForegroundColor Green
        
        # URL encode the parameters
        $encodedClientId = [System.Web.HttpUtility]::UrlEncode($AgentBlueprintId)
        $encodedScope = [System.Web.HttpUtility]::UrlEncode($Scope)
        $encodedRedirectUri = [System.Web.HttpUtility]::UrlEncode($RedirectUri)
        $encodedState = [System.Web.HttpUtility]::UrlEncode($State)
        
        # Build the admin consent URL
        $requestUri = "https://login.microsoftonline.com/$tenantId/v2.0/adminconsent" +
            "?client_id=$encodedClientId" +
            "&scope=$encodedScope" +
            "&redirect_uri=$encodedRedirectUri" +
            "&state=$encodedState"
        
        Write-Host "Admin Consent Request Details:" -ForegroundColor Cyan
        Write-Host "  Client ID (Agent Blueprint): $AgentBlueprintId" -ForegroundColor White
        Write-Host "  Tenant ID: $tenantId" -ForegroundColor White
        Write-Host "  Requested Scopes: $Scope" -ForegroundColor White
        Write-Host "  Redirect URI: $RedirectUri" -ForegroundColor White
        Write-Host "  State: $State" -ForegroundColor White
        Write-Host ""
        Write-Host "Admin Consent URL:" -ForegroundColor Yellow
        Write-Host $requestUri -ForegroundColor Cyan
        Write-Host ""
        
        # Launch the system browser with the consent URL
        try {
            Write-Host "Opening admin consent page in system browser..." -ForegroundColor Green
            Start-Process $requestUri
            Write-Host "✓ Admin consent page opened in browser successfully" -ForegroundColor Green
            Write-Host ""
            Write-Host "Please complete the admin consent process in the browser window." -ForegroundColor Yellow
            Write-Host "After consent is granted, the Agent Blueprint will be able to inherit the requested permissions." -ForegroundColor Yellow
        }
        catch {
            Write-Error "Error opening admin consent page in browser: $($_.Exception.Message)"
            Write-Host "You can manually copy and paste the above URL into your browser." -ForegroundColor Yellow
            throw
        }
        
        # Create a result object with consent information
        $consentResult = [PSCustomObject]@{
            AgentBlueprintId = $AgentBlueprintId
            TenantId = $tenantId
            RequestedScopes = $Scope
            RedirectUri = $RedirectUri
            State = $State
            ConsentUrl = $requestUri
            Action = "Browser Launched"
            Timestamp = Get-Date
        }
        
        return $consentResult
    }
    catch {
        Write-Error "Failed to launch admin consent page for Agent Identity Blueprint Principal: $_"
        throw
    }
}

function New-AgentIDForAgentIdentityBlueprint {
    <#
    .SYNOPSIS
    Creates a new Agent Identity using an Agent Identity Blueprint
    
    .DESCRIPTION
    Creates a new Agent Identity by posting to the Microsoft Graph AgentIdentity endpoint
    using the current Agent Identity Blueprint ID and specified sponsors/owners
    
    .PARAMETER DisplayName
    The display name for the Agent Identity
    
    .PARAMETER SponsorUserIds
    Array of user IDs to set as sponsors
    
    .PARAMETER SponsorGroupIds
    Array of group IDs to set as sponsors
    
    .PARAMETER OwnerUserIds
    Array of user IDs to set as owners
    
    .NOTES
    Requires an Agent Identity Blueprint to be created first (uses stored blueprint ID)
    At least one owner or sponsor (user or group) must be specified
    
    .EXAMPLE
    New-AgentIDForAgentIdentityBlueprint -DisplayName "My Agent Identity" -SponsorUserIds @("user1") -OwnerUserIds @("owner1")
    
    .EXAMPLE
    New-AgentIDForAgentIdentityBlueprint  # Will prompt for all required parameters
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$DisplayName,
        
        [Parameter(Mandatory = $false)]
        [string[]]$SponsorUserIds,
        
        [Parameter(Mandatory = $false)]
        [string[]]$SponsorGroupIds,
        
        [Parameter(Mandatory = $false)]
        [string[]]$OwnerUserIds
    )
    
    # Connect using Agent Identity Blueprint credentials
    if (!(ConnectAsAgentIdentityBlueprint)) {
        Write-Error "Failed to connect using Agent Identity Blueprint credentials. Cannot create Agent Identity."
        return
    }
    
    # Validate that we have a current Agent Identity Blueprint ID
    if (-not $script:CurrentAgentBlueprintId) {
        Write-Error "No Agent Identity Blueprint ID found. Please run New-AgentIdentityBlueprint first."
        return
    }
    
    # Prompt for missing DisplayName if not provided
    if (-not $DisplayName -or $DisplayName.Trim() -eq "") {
        do {
            $DisplayName = Read-Host "Enter the display name for the Agent Identity"
        } while (-not $DisplayName -or $DisplayName.Trim() -eq "")
    }
    
    # Get sponsors and owners (prompt if not provided)
    $sponsorsAndOwners = Get-SponsorsAndOwners -SponsorUserIds $SponsorUserIds -SponsorGroupIds $SponsorGroupIds -OwnerUserIds $OwnerUserIds
    $SponsorUserIds = $sponsorsAndOwners.SponsorUserIds
    $SponsorGroupIds = $sponsorsAndOwners.SponsorGroupIds
    $OwnerUserIds = $sponsorsAndOwners.OwnerUserIds
    
    # Build the request body
    $Body = [PSCustomObject]@{
        displayName = $DisplayName
        AgentIdentityBlueprintId = $script:CurrentAgentBlueprintId
    }
    
    # Add sponsors if provided
    if ($SponsorUserIds -or $SponsorGroupIds) {
        $sponsorBindings = @()
        
        if ($SponsorUserIds) {
            foreach ($userId in $SponsorUserIds) {
                $sponsorBindings += "https://graph.microsoft.com/v1.0/users/$userId"
            }
        }
        
        if ($SponsorGroupIds) {
            foreach ($groupId in $SponsorGroupIds) {
                $sponsorBindings += "https://graph.microsoft.com/v1.0/groups/$groupId"
            }
        }
        
        $Body | Add-Member -MemberType NoteProperty -Name "sponsors@odata.bind" -Value $sponsorBindings
    }
    
    # Add owners if provided
    if ($OwnerUserIds) {
        $ownerBindings = @()
        foreach ($userId in $OwnerUserIds) {
            $ownerBindings += "https://graph.microsoft.com/v1.0/users/$userId"
        }
        $Body | Add-Member -MemberType NoteProperty -Name "owners@odata.bind" -Value $ownerBindings
    }
    
    try {
        Write-Host "Creating Agent Identity '$DisplayName' using blueprint '$script:CurrentAgentBlueprintId'..." -ForegroundColor Yellow
        
        # Convert the body to JSON
        $JsonBody = $Body | ConvertTo-Json -Depth 5
        Write-Host "Request body:" -ForegroundColor Gray
        Write-Host $JsonBody -ForegroundColor Gray
        
        # Make the REST API call
        $agentIdentity = Invoke-MgRestMethod -Method POST -Uri "https://graph.microsoft.com/beta/serviceprincipals/Microsoft.Graph.AgentIdentity" -Body $JsonBody -ContentType "application/json"
        
        Write-Host "Agent Identity created successfully!" -ForegroundColor Green
        Write-Host "Agent Identity ID: $($agentIdentity.id)" -ForegroundColor Cyan
        Write-Host "Display Name: $($agentIdentity.displayName)" -ForegroundColor Cyan
        
        # Store the Agent Identity ID in module state
        $script:CurrentAgentIdentityId = $agentIdentity.id
        
        return $agentIdentity
    }
    catch {
        Write-Error "Failed to create Agent Identity: $_"
        throw
    }
}

function Disconnect-EntraAgentID {
    <#
    .SYNOPSIS
    Disconnects from Microsoft Graph and clears module connection state
    
    .DESCRIPTION
    Safely disconnects from Microsoft Graph and resets all module connection tracking variables
    
    .EXAMPLE
    Disconnect-EntraAgentID
    #>
    [CmdletBinding()]
    param()
    
    try {
        if ($script:LastSuccessfulConnection) {
            Write-Host "Disconnecting from Microsoft Graph (connection type: $script:LastSuccessfulConnection)" -ForegroundColor Yellow
            Disconnect-MgGraph
            Write-Host "Successfully disconnected from Microsoft Graph" -ForegroundColor Green
        } else {
            Write-Host "No active Microsoft Graph connection found" -ForegroundColor Gray
        }
        
        # Clear connection tracking state
        $script:LastSuccessfulConnection = $null
    }
    catch {
        Write-Warning "Error during disconnect: $_"
    }
}

function New-AgentIDUserForAgentId {
    <#
    .SYNOPSIS
    Creates a new Agent User using an Agent Identity
    
    .DESCRIPTION
    Creates a new Agent User by posting to the Microsoft Graph users endpoint
    using the current Agent Identity ID as the identity parent
    
    .PARAMETER DisplayName
    The display name for the Agent User
    
    .PARAMETER UserPrincipalName
    The user principal name (email) for the Agent User
    
    .NOTES
    Requires an Agent Identity to be created first using New-AgentIDForAgentIdentityBlueprint (uses stored Agent Identity ID)
    The mailNickname is automatically derived from the userPrincipalName
    
    .EXAMPLE
    New-AgentIDUserForAgentId -DisplayName "Agent Identity 26192008" -UserPrincipalName "AgentIdentity26192008@67lxx6.onmicrosoft.com"
    
    .EXAMPLE
    New-AgentIDUserForAgentId  # Will prompt for all required parameters
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$DisplayName,
        
        [Parameter(Mandatory = $false)]
        [string]$UserPrincipalName
    )
    
    # Connect using Agent Identity Blueprint credentials
    if (!(ConnectAsAgentIdentityBlueprint)) {
        Write-Error "Failed to connect using Agent Identity Blueprint credentials. Cannot create Agent User."
        return
    }
    
    # Validate that we have a current Agent Identity ID (from New-AgentIDForAgentIdentityBlueprint)
    if (-not $script:CurrentAgentIdentityId) {
        Write-Error "No Agent Identity ID found. Please run New-AgentIDForAgentIdentityBlueprint first to create an Agent Identity."
        return
    }
    
    # Prompt for missing DisplayName if not provided
    if (-not $DisplayName -or $DisplayName.Trim() -eq "") {
        do {
            $DisplayName = Read-Host "Enter the display name for the Agent User"
        } while (-not $DisplayName -or $DisplayName.Trim() -eq "")
    }
    
    # Prompt for missing UserPrincipalName if not provided
    if (-not $UserPrincipalName -or $UserPrincipalName.Trim() -eq "") {
        do {
            $UserPrincipalName = Read-Host "Enter the user principal name (email) for the Agent User (e.g., username@domain.onmicrosoft.com)"
        } while (-not $UserPrincipalName -or $UserPrincipalName.Trim() -eq "" -or $UserPrincipalName -notlike "*@*")
    }
    
    # Validate UserPrincipalName format
    if ($UserPrincipalName -notlike "*@*") {
        Write-Error "Invalid UserPrincipalName format. Must be in email format (e.g., username@domain.com)"
        return
    }
    
    # Build mailNickname from userPrincipalName by removing the domain
    $mailNickname = $UserPrincipalName.Split('@')[0]
    
    # Build the request body
    $Body = [PSCustomObject]@{
        "@odata.type" = "microsoft.graph.agentUser"
        displayName = $DisplayName
        userPrincipalName = $UserPrincipalName
        identityParentId = $script:CurrentAgentIdentityId
        mailNickname = $mailNickname
        accountEnabled = $true
    }
    
    try {
        Write-Host "Creating Agent User '$DisplayName' with UPN '$UserPrincipalName'..." -ForegroundColor Yellow
        Write-Host "Using Agent Identity ID: $script:CurrentAgentIdentityId" -ForegroundColor Gray
        
        # Convert the body to JSON
        $JsonBody = $Body | ConvertTo-Json -Depth 5
        Write-Host "Request body:" -ForegroundColor Gray
        Write-Host $JsonBody -ForegroundColor Gray
        
        # Make the REST API call
        $agentUser = Invoke-MgRestMethod -Method POST -Uri "https://graph.microsoft.com/beta/users/" -Body $JsonBody -ContentType "application/json"
        
        Write-Host "Agent User created successfully!" -ForegroundColor Green
        Write-Host "Agent User ID: $($agentUser.id)" -ForegroundColor Cyan
        Write-Host "Display Name: $($agentUser.displayName)" -ForegroundColor Cyan
        Write-Host "User Principal Name: $($agentUser.userPrincipalName)" -ForegroundColor Cyan
        Write-Host "Mail Nickname: $($agentUser.mailNickname)" -ForegroundColor Cyan
        
        # Store the Agent User ID in module state (could be useful for future operations)
        $script:CurrentAgentUserId = $agentUser.id
        
        return $agentUser
    }
    catch {
        Write-Error "Failed to create Agent User: $_"
        throw
    }
}

# Export module members - these functions will be available when the module is imported
Export-ModuleMember -Function New-AgentIdentityBlueprint
Export-ModuleMember -Function New-AgentIdentityBlueprintPrincipal
Export-ModuleMember -Function Add-ClientSecretToAgentIdentityBlueprint
Export-ModuleMember -Function Add-ScopeToAgentIdentityBlueprint
Export-ModuleMember -Function Add-InheritablePermissionsToAgentIdentityBlueprint
Export-ModuleMember -Function Add-RedirectURIToAgentIdentityBlueprint
Export-ModuleMember -Function Add-PermissionToCreateAgentUsersToAgentIdentityBlueprintPrincipal
Export-ModuleMember -Function Add-PermissionsToInheritToAgentIdentityBlueprintPrincipal
Export-ModuleMember -Function New-AgentIDForAgentIdentityBlueprint
Export-ModuleMember -Function New-AgentIDUserForAgentId
Export-ModuleMember -Function Disconnect-EntraAgentID