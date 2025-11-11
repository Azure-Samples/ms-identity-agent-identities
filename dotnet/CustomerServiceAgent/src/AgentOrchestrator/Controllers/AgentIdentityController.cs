using AgentIdentityModel;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Identity.Abstractions;
using Microsoft.Identity.Web;
using System.Net.Http.Headers;
using System.Runtime.CompilerServices;
using System.Text.Json;

// For more information on enabling Web API for empty projects, visit https://go.microsoft.com/fwlink/?LinkID=397860

namespace api.Controllers
{
[Route("api/[controller]")]
[ApiController]
public class AgentIdentityController : ControllerBase
{
private string agentApplicationId;
private string sponsorUserId;
private readonly IAuthorizationHeaderProvider authorizationHeaderProvider;
private List<string> scopesToRequest;
private string tenantId;
public IDownstreamApi DownstreamApi { get; }

// Compiled regex for better performance when sanitizing log inputs
private static readonly System.Text.RegularExpressions.Regex LogSanitizationRegex = 
new(@"[\r\n\t\x00-\x1F\x7F]", System.Text.RegularExpressions.RegexOptions.Compiled);


public AgentIdentityController(IConfiguration configuration, IDownstreamApi downstreamApi, IAuthorizationHeaderProvider authorizationHeaderProvider)
{
agentApplicationId = configuration["AzureAd:ClientId"] ?? "Define ClientId in the configuration.";
tenantId = configuration["AzureAd:TenantId"] ?? "Define TenantId in the configuration.";
sponsorUserId = configuration["AgentIdentities:SponsorUserId"] ?? "Define SponsorUserId in the configuration.";
DownstreamApi = downstreamApi;
this.authorizationHeaderProvider = authorizationHeaderProvider;

Dictionary<string, DownstreamApiOptions> downstreamApiOptions = new();
configuration.GetSection("DownstreamApis").Bind(downstreamApiOptions);
scopesToRequest = new();
foreach(var option in downstreamApiOptions)
{
string? scopes = option.Value.Scopes?.FirstOrDefault();
if (scopes == null)
{
continue;
}
switch (option.Key)
{
default:
case "OrderService":
scopesToRequest.Add(scopes.Replace(".default", "Orders.Read"));
break;
case "ShippingService":
scopesToRequest.Add(scopes.Replace(".default", "Shipping.Read"));
scopesToRequest.Add(scopes.Replace(".default", "Shipping.Write"));
break;

case "EmailService":
scopesToRequest.Add(scopes.Replace(".default", "Email.Send"));
break;
}
}
}

/// <summary>
/// Sanitizes user input to prevent log forging attacks by removing newlines and control characters
/// </summary>
private static string SanitizeForLog(string? input)
{
    if (string.IsNullOrEmpty(input))
        return string.Empty;
    
    // Remove newlines, carriage returns, and other control characters that could be used for log forging
    return LogSanitizationRegex.Replace(input, "_");
}

/// <summary>
/// Create a new Agent Identity with the specified name (for the current Agent Application).
/// Optionally create a new agent user identity.
/// </summary>
[HttpPost]
public async Task<IActionResult> Post([FromQuery] string agentIdentityName, [FromQuery] string? agentUserIdentityUpn = null)
{
ArgumentNullException.ThrowIfNull(agentIdentityName, nameof(agentIdentityName));

var logger = HttpContext.RequestServices.GetRequiredService<ILogger<AgentIdentityController>>();

try
{
logger.LogInformation("Creating agent identity with name: {AgentIdentityName}", SanitizeForLog(agentIdentityName));

// Call the downstream API with a POST request to create an Agent Identity
// Use "Logging:LogLevel:Microsoft.Identity.Web": "Debug" in the configuration if this fails.
var newAgentIdentity = await DownstreamApi.PostForAppAsync<AgentIdentity, AgentIdentity>(
"msGraphAgentIdentity",
new AgentIdentity
{
displayName = agentIdentityName,
agentIdentityBlueprintId = agentApplicationId,
sponsorsOdataBind = [$"https://graph.microsoft.com/v1.0/users/{sponsorUserId}"],
ownersOdataBind = [$"https://graph.microsoft.com/v1.0/users/{sponsorUserId}"],
}
);

// Create a user agent identity if a UPN is provided
AgentUserIdentity? newAgentUserId = null;
string adminConsentUrl = string.Empty;
if (!string.IsNullOrEmpty(agentUserIdentityUpn))
{
logger.LogInformation("Creating agent user identity with UPN: {AgentUserIdentityUpn}", SanitizeForLog(agentUserIdentityUpn));

// Call the downstream API (canary Graph) with a POST request to create an Agent Identity
newAgentUserId = await DownstreamApi.PostForAppAsync<AgentUserIdentity, AgentUserIdentity>(
   "msGraphAgentIdentity",
   new AgentUserIdentity
   {
   displayName = agentUserIdentityUpn.Substring(0, agentUserIdentityUpn.IndexOf('@', StringComparison.Ordinal)),
   mailNickname = agentUserIdentityUpn.Substring(0, agentUserIdentityUpn.IndexOf('@', StringComparison.Ordinal)),
   userPrincipalName = agentUserIdentityUpn,
   accountEnabled = true,
   identityParentId = newAgentIdentity!.id
   },
   options =>
   {
   options.RelativePath = "/beta/users";
   });


adminConsentUrl = $"https://login.microsoftonline.com/{tenantId}/v2.0/adminconsent?client_id={newAgentIdentity.id}&scope={string.Join("%20", scopesToRequest)}&redirect_uri=https://entra.microsoft.com/TokenAuthorize&state=xyz123";
}

logger.LogInformation("Successfully created agent identity: {AgentIdentityId}", newAgentIdentity!.id);
return Ok(new {AgentIdentity=newAgentIdentity, AgentUserIdentity = newAgentUserId, AdminConsentUrl = adminConsentUrl});
}
catch (MicrosoftIdentityWebChallengeUserException authEx)
{
logger.LogWarning(authEx, "Authentication challenge when creating agent identity");
return Unauthorized(new { error = "Authentication required", details = "Unable to authenticate to Microsoft Graph. Please ensure you are signed in and have the required permissions." });
}
catch (HttpRequestException httpEx)
{
logger.LogError(httpEx, "HTTP error when creating agent identity. Status: {StatusCode}", httpEx.StatusCode);
return StatusCode(503, new { error = "Service unavailable", details = "Unable to communicate with Microsoft Graph API. Please try again later." });
}
catch (ArgumentException argEx)
{
logger.LogWarning(argEx, "Invalid argument when creating agent identity");
return BadRequest(new { error = "Invalid input", details = argEx.Message });
}
catch (Exception ex)
{
logger.LogError(ex, "Unexpected error when creating agent identity");
return StatusCode(500, new { error = "Internal server error", details = "An unexpected error occurred while creating the agent identity. Please contact support if this persists." });
}
}



// Get the list of Agent Identities associated with the current agent application (on behalf of the current user)
// GET: api/<AgentIdentity>
[HttpGet]
public async Task<ActionResult<IEnumerable<AgentIdentity>>> Get()
{
try
{
var identities = await DownstreamApi.GetForAppAsync<IEnumerable<AgentIdentity>>("msGraphAgentIdentity");
return Ok(identities);
}
catch (MicrosoftIdentityWebChallengeUserException authEx)
{
// Authentication/authorization error - user needs to authenticate or lacks permissions
var logger = HttpContext.RequestServices.GetRequiredService<ILogger<AgentIdentityController>>();
logger.LogWarning(authEx, "Authentication challenge when retrieving agent identities");
return Unauthorized(new { error = "Authentication required", details = "Unable to authenticate to Microsoft Graph. Please ensure you are signed in and have the required permissions." });
}
catch (HttpRequestException httpEx)
{
// Network or API communication error
var logger = HttpContext.RequestServices.GetRequiredService<ILogger<AgentIdentityController>>();
logger.LogError(httpEx, "HTTP error when retrieving agent identities. Status: {StatusCode}", httpEx.StatusCode);
return StatusCode(503, new { error = "Service unavailable", details = "Unable to communicate with Microsoft Graph API. Please try again later." });
}
catch (Exception ex)
{
// Unexpected error
var logger = HttpContext.RequestServices.GetRequiredService<ILogger<AgentIdentityController>>();
logger.LogError(ex, "Unexpected error when retrieving agent identities");
return StatusCode(500, new { error = "Internal server error", details = "An unexpected error occurred while retrieving agent identities. Please contact support if this persists." });
}
}


// Delete an Agent Identity by ID (on behalf of the agent application)
// DELETE api/<AgentIdentity>/5
[HttpDelete("{id}")]
public async Task<IActionResult> Delete(string id)
{
var logger = HttpContext.RequestServices.GetRequiredService<ILogger<AgentIdentityController>>();

try
{
logger.LogInformation("Deleting agent identity: {AgentIdentityId}", SanitizeForLog(id));

var result = await DownstreamApi.DeleteForAppAsync<string, object>(
"msGraphAgentIdentity",
input: null!,
options =>
{
options.RelativePath += $"/{id}"; // Specify the ID of the agent identity to delete
});

logger.LogInformation("Successfully deleted agent identity: {AgentIdentityId}", SanitizeForLog(id));
return Ok(new { id, status = "deleted", result = result?.ToString() });
}
catch (MicrosoftIdentityWebChallengeUserException authEx)
{
logger.LogWarning(authEx, "Authentication challenge when deleting agent identity {AgentIdentityId}", SanitizeForLog(id));
return Unauthorized(new { error = "Authentication required", details = "Unable to authenticate to Microsoft Graph. Please ensure you are signed in and have the required permissions." });
}
catch (HttpRequestException httpEx)
{
logger.LogError(httpEx, "HTTP error when deleting agent identity {AgentIdentityId}. Status: {StatusCode}", SanitizeForLog(id), httpEx.StatusCode);
return StatusCode(503, new { error = "Service unavailable", details = "Unable to communicate with Microsoft Graph API. Please try again later." });
}
catch (Exception ex)
{
logger.LogError(ex, "Unexpected error when deleting agent identity {AgentIdentityId}", SanitizeForLog(id));
return StatusCode(500, new { error = "Internal server error", details = "An unexpected error occurred while deleting the agent identity. Please contact support if this persists." });
}
}
}
}
