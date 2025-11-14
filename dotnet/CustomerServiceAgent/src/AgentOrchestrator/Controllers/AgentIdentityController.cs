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
		private List<string> rolesToRequest;
		private readonly ILogger<AgentIdentityController> _logger;
		private string tenantId;
		public IDownstreamApi DownstreamApi { get; }

		// Compiled regex for better performance when sanitizing log inputs
		private static readonly System.Text.RegularExpressions.Regex LogSanitizationRegex =
		new(@"[\r\n\t\x00-\x1F\x7F]", System.Text.RegularExpressions.RegexOptions.Compiled);

		// Delay in milliseconds between retry attempts when creating agent user identity
		private const int RetryDelayMilliseconds = 5000;

		public AgentIdentityController(
			IConfiguration configuration,
			IDownstreamApi downstreamApi,
			IAuthorizationHeaderProvider authorizationHeaderProvider,
			ILogger<AgentIdentityController> logger)
		{
			agentApplicationId = configuration["AzureAd:ClientId"] ?? "Define ClientId in the configuration.";
			tenantId = configuration["AzureAd:TenantId"] ?? "Define TenantId in the configuration.";
			sponsorUserId = configuration["AgentIdentities:SponsorUserId"] ?? "Define SponsorUserId in the configuration.";
			DownstreamApi = downstreamApi;
			this.authorizationHeaderProvider = authorizationHeaderProvider;
			_logger = logger;

			Dictionary<string, DownstreamApiOptions> downstreamApiOptions = new();
			configuration.GetSection("DownstreamApis").Bind(downstreamApiOptions);
			scopesToRequest = new();
			rolesToRequest = new();
			foreach (var option in downstreamApiOptions)
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
						rolesToRequest.Add(scopes.Replace(".default", "Orders.Read.All"));
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
		/// <param name="agentIdentityName">The app registration name for the new agent identity. This is required.</param>
		/// <param name="agentUserIdentityUpn">Optional user principal name (UPN) for creating an agent user identity associated with the agent identity. If provided, an agent user identity will be created.</param>
		/// <returns>
		/// An object containing:
		/// - AgentIdentity: The newly created agent identity with its ID and details
		/// - AgentUserIdentity: The newly created agent user identity (if agentUserIdentityUpn was provided), or null
		/// - AdminConsentUrlScopes: URL for admin consent with delegated permissions (scopes)
		/// - AdminConsentUrlRoles: URL for admin consent with application permissions (roles)
		/// </returns>
		/// <response code="200">Returns the newly created agent identity and related information</response>
		/// <response code="400">If the agentIdentityName is null or invalid</response>
		/// <response code="500">If there's an error creating the agent identity or agent user identity in Microsoft Graph</response>
		[HttpPost]
		public async Task<IActionResult> Post([FromQuery] string agentIdentityName, [FromQuery] string? agentUserIdentityUpn = null)
		{
			ArgumentNullException.ThrowIfNull(agentIdentityName, nameof(agentIdentityName));

			try
			{
				_logger.LogInformation("Creating agent identity with name: {AgentIdentityName}", SanitizeForLog(agentIdentityName));

				// Call the downstream API with a POST request to create an Agent Identity
				// Use "Logging:LogLevel:Microsoft.Identity.Web": "Debug" in the configuration if this fails.
				var newAgentIdentity = await DownstreamApi.PostForAppAsync<AgentIdentity, AgentIdentity>(
				"msGraphAgentIdentity",
				new AgentIdentity
				{
					displayName = agentIdentityName,
					agentIdentityBlueprintId = agentApplicationId,
					sponsorsOdataBind = [$"https://graph.microsoft.com/v1.0/users/{Uri.EscapeDataString(sponsorUserId)}"],
					ownersOdataBind = [$"https://graph.microsoft.com/v1.0/users/{Uri.EscapeDataString(sponsorUserId)}"],
				}
				);

				// Create a user agent identity if a UPN is provided
				AgentUserIdentity? newAgentUserId = null;
				string adminConsentUrlScopes = string.Empty;
				string adminConsentUrlRoles = string.Empty;
				if (!string.IsNullOrEmpty(agentUserIdentityUpn))
				{
					_logger.LogInformation("Creating agent user identity with UPN: {AgentUserIdentityUpn}", SanitizeForLog(agentUserIdentityUpn));


					// Retry logic for agent user identity creation (may fail with 400 if agent identity hasn't replicated yet)
					const int maxRetries = 2;
					int retryCount = 0;
					bool success = false;

					while (!success && retryCount <= maxRetries)
					{
						try
						{
							// Call the downstream API (canary Graph) with a POST request to create an Agent User Identity
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

							success = true;
							_logger.LogInformation("Successfully created agent user identity on attempt {Attempt}", retryCount + 1);
						}
						catch (HttpRequestException httpEx) when (httpEx.StatusCode == System.Net.HttpStatusCode.BadRequest && retryCount < maxRetries)
						{
							retryCount++;
							_logger.LogWarning("Agent user identity creation failed with HTTP 400 (attempt {Attempt}/{MaxAttempts}). Waiting 5 seconds for agent identity replication...", 
								retryCount, maxRetries + 1);
							await Task.Delay(RetryDelayMilliseconds);
						}
						catch
						{
							// Re-throw other exceptions to be handled by outer catch blocks
							throw;
						}
					}

					if (!success)
					{
						_logger.LogError("Failed to create agent user identity after {MaxAttempts} attempts", maxRetries + 1);
						throw new HttpRequestException("Failed to create agent user identity after multiple attempts. The agent identity may not have replicated yet.", 
							null, System.Net.HttpStatusCode.BadRequest);
					}

				var agentId = newAgentIdentity?.id ?? string.Empty;
				adminConsentUrlScopes = $"https://login.microsoftonline.com/{Uri.EscapeDataString(tenantId)}/v2.0/adminconsent?client_id={Uri.EscapeDataString(agentId)}&scope={string.Join("%20", scopesToRequest.Select(Uri.EscapeDataString))}&redirect_uri=https://entra.microsoft.com/TokenAuthorize&state=xyz123";
				adminConsentUrlRoles = $"https://login.microsoftonline.com/{Uri.EscapeDataString(tenantId)}/v2.0/adminconsent?client_id={Uri.EscapeDataString(agentId)}&role={string.Join("%20", rolesToRequest.Select(Uri.EscapeDataString))}&redirect_uri=https://entra.microsoft.com/TokenAuthorize&state=xyz123";
			}

				_logger.LogInformation("Successfully created agent identity: {AgentIdentityId}", newAgentIdentity!.id);
				return Ok(new { AgentIdentity = newAgentIdentity, AgentUserIdentity = newAgentUserId, adminConsentUrlScopes = adminConsentUrlScopes, adminConsentUrlRoles = adminConsentUrlRoles });
			}
			catch (MicrosoftIdentityWebChallengeUserException authEx)
			{
				_logger.LogWarning(authEx, "Authentication challenge when creating agent identity");
				return Unauthorized(new { error = "Authentication required", details = "Unable to authenticate to Microsoft Graph. Please ensure you are signed in and have the required permissions." });
			}
			catch (HttpRequestException httpEx)
			{
				_logger.LogError(httpEx, "HTTP error when creating agent identity. Status: {StatusCode}", httpEx.StatusCode);
				return StatusCode(503, new { error = "Service unavailable", details = "Unable to communicate with Microsoft Graph API. Please try again later." });
			}
			catch (ArgumentException argEx)
			{
				_logger.LogWarning(argEx, "Invalid argument when creating agent identity");
				return BadRequest(new { error = "Invalid input", details = argEx.Message });
			}
			catch (Exception ex)
			{
				_logger.LogError(ex, "Unexpected error when creating agent identity");
				return StatusCode(500, new { error = "Internal server error", details = "An unexpected error occurred while creating the agent identity. Please contact support if this persists." });
			}
		}



		/// <summary>
		/// Get the list of Agent Identities associated with the current agent application.
		/// This operation is performed on behalf of the agent application using app-only permissions.
		/// </summary>
		/// <returns>
		/// A collection of agent identities associated with the current agent application, or null if an error occurs.
		/// Each agent identity includes its ID, display name, and other metadata.
		/// </returns>
		/// <response code="200">Returns the list of agent identities</response>
		/// <response code="500">If there's an error retrieving agent identities from Microsoft Graph</response>
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
				_logger.LogWarning(authEx, "Authentication challenge when retrieving agent identities");
				return Unauthorized(new { error = "Authentication required", details = "Unable to authenticate to Microsoft Graph. Please ensure you are signed in and have the required permissions." });
			}
			catch (HttpRequestException httpEx)
			{
				// Network or API communication error
				_logger.LogError(httpEx, "HTTP error when retrieving agent identities. Status: {StatusCode}", httpEx.StatusCode);
				return StatusCode(503, new { error = "Service unavailable", details = "Unable to communicate with Microsoft Graph API. Please try again later." });
			}
			catch (Exception ex)
			{
				// Unexpected error
				_logger.LogError(ex, "Unexpected error when retrieving agent identities");
				return StatusCode(500, new { error = "Internal server error", details = "An unexpected error occurred while retrieving agent identities. Please contact support if this persists." });
			}
		}


		/// <summary>
		/// Delete an Agent Identity by its unique identifier.
		/// This operation is performed on behalf of the agent application using app-only permissions.
		/// </summary>
		/// <param name="id">The unique identifier (GUID) of the agent identity to delete. This is required and should be a valid agent identity ID.</param>
		/// <returns>
		/// A string representation of the delete operation result. Returns null if the deletion fails.
		/// </returns>
		/// <response code="200">Returns the result of the delete operation</response>
		/// <response code="404">If the agent identity with the specified ID is not found</response>
		/// <response code="500">If there's an error deleting the agent identity from Microsoft Graph</response>
		[HttpDelete("{id}")]
		public async Task<IActionResult> Delete(string id)
		{
			try
			{
				_logger.LogInformation("Deleting agent identity: {AgentIdentityId}", SanitizeForLog(id));

				var result = await DownstreamApi.DeleteForAppAsync<string, object>(
				"msGraphAgentIdentity",
				input: null!,
				options =>
				{
					options.RelativePath += $"/{id}"; // Specify the ID of the agent identity to delete
				});

				_logger.LogInformation("Successfully deleted agent identity: {AgentIdentityId}", SanitizeForLog(id));
				return Ok(new { id, status = "deleted", result = result?.ToString() });
			}
			catch (MicrosoftIdentityWebChallengeUserException authEx)
			{
				_logger.LogWarning(authEx, "Authentication challenge when deleting agent identity {AgentIdentityId}", SanitizeForLog(id));
				return Unauthorized(new { error = "Authentication required", details = "Unable to authenticate to Microsoft Graph. Please ensure you are signed in and have the required permissions." });
			}
			catch (HttpRequestException httpEx)
			{
				_logger.LogError(httpEx, "HTTP error when deleting agent identity {AgentIdentityId}. Status: {StatusCode}", SanitizeForLog(id), httpEx.StatusCode);
				return StatusCode(503, new { error = "Service unavailable", details = "Unable to communicate with Microsoft Graph API. Please try again later." });
			}
			catch (Exception ex)
			{
				_logger.LogError(ex, "Unexpected error when deleting agent identity {AgentIdentityId}", SanitizeForLog(id));
				return StatusCode(500, new { error = "Internal server error", details = "An unexpected error occurred while deleting the agent identity. Please contact support if this persists." });
			}
		}
	}
}
