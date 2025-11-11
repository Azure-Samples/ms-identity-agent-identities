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
		private string tenantId;
		public IDownstreamApi DownstreamApi { get; }


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
			rolesToRequest = new();
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
		/// Create a new Agent Identity with the specified name (for the current Agent Application).
		/// Optionally create a new agent user identity.
		/// </summary>
		/// <param name="agentIdentityName">The display name for the new agent identity. This is required.</param>
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

				var agentId = newAgentIdentity?.id ?? string.Empty;
				adminConsentUrlScopes = $"https://login.microsoftonline.com/{Uri.EscapeDataString(tenantId)}/v2.0/adminconsent?client_id={Uri.EscapeDataString(agentId)}&scope={string.Join("%20", scopesToRequest.Select(Uri.EscapeDataString))}&redirect_uri=https://entra.microsoft.com/TokenAuthorize&state=xyz123";
				adminConsentUrlRoles = $"https://login.microsoftonline.com/{Uri.EscapeDataString(tenantId)}/v2.0/adminconsent?client_id={Uri.EscapeDataString(agentId)}&role={string.Join("%20", rolesToRequest.Select(Uri.EscapeDataString))}&redirect_uri=https://entra.microsoft.com/TokenAuthorize&state=xyz123";
			}

			return Ok(new {AgentIdentity=newAgentIdentity, AgentUserIdentity = newAgentUserId, AdminConsentUrlScopes = adminConsentUrlScopes, AdminConsentUrlRoles = adminConsentUrlRoles });
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
		public async Task<IEnumerable<AgentIdentity>?> Get()
		{
			try
			{
				return await DownstreamApi.GetForAppAsync<IEnumerable<AgentIdentity>>("msGraphAgentIdentity");
			}
			catch (Exception ex)
			{
				// Don't do that in production!
				throw;
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
		public async Task<string?> Delete(string id)
		{
			var result = await DownstreamApi.DeleteForAppAsync<string, object>(
				"msGraphAgentIdentity",
				input: null!,
			  	options =>
				  {
					  options.RelativePath += $"/{id}"; // Specify the ID of the agent identity to delete
				  });
			return result?.ToString();
		}
	}
}
