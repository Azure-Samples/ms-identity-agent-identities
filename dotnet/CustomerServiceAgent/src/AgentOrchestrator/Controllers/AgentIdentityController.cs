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
		/// Creates a new Agent Identity with the specified name for the current Agent Application.
		/// Optionally creates a new agent user identity if a UPN is provided.
		/// </summary>
		/// <param name="agentIdentityName">The display name for the new agent identity.</param>
		/// <param name="agentUserIdentityUpn">Optional user principal name (UPN) to create an agent user identity.</param>
		/// <returns>
		/// An object containing:
		/// - AgentIdentity: The newly created agent identity
		/// - AgentUserIdentity: The newly created agent user identity (if agentUserIdentityUpn was provided)
		/// - AdminConsentUrlScopes: URL for admin consent with scope permissions (if agent user identity was created)
		/// - AdminConsentUrlRoles: URL for admin consent with role permissions (if agent user identity was created)
		/// </returns>
		/// <response code="200">Agent identity successfully created.</response>
		/// <response code="400">Invalid request parameters.</response>
		/// <response code="500">Internal server error during agent identity creation.</response>
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
					sponsorsOdataBind = [$"https://graph.microsoft.com/v1.0/users/{sponsorUserId}"],
					ownersOdataBind = [$"https://graph.microsoft.com/v1.0/users/{sponsorUserId}"],
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

				adminConsentUrlScopes = $"https://login.microsoftonline.com/{Uri.EscapeDataString(tenantId)}/v2.0/adminconsent?client_id={Uri.EscapeDataString(newAgentIdentity.id!)}&scope={string.Join("%20", scopesToRequest.Select(Uri.EscapeDataString))}&redirect_uri=https://entra.microsoft.com/TokenAuthorize&state=xyz123";
				adminConsentUrlRoles = $"https://login.microsoftonline.com/{Uri.EscapeDataString(tenantId)}/v2.0/adminconsent?client_id={Uri.EscapeDataString(newAgentIdentity.id!)}&role={string.Join("%20", rolesToRequest.Select(Uri.EscapeDataString))}&redirect_uri=https://entra.microsoft.com/TokenAuthorize&state=xyz123";
			}

			return Ok(new {AgentIdentity=newAgentIdentity, AgentUserIdentity = newAgentUserId, AdminConsentUrlScopes = adminConsentUrlScopes, AdminConsentUrlRoles = adminConsentUrlRoles });
		}



		/// <summary>
		/// Retrieves the list of Agent Identities associated with the current agent application.
		/// </summary>
		/// <returns>A collection of agent identities associated with the current application.</returns>
		/// <response code="200">Successfully retrieved the list of agent identities.</response>
		/// <response code="500">Internal server error while retrieving agent identities.</response>
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
		/// Deletes an Agent Identity by its unique identifier.
		/// </summary>
		/// <param name="id">The unique identifier of the agent identity to delete.</param>
		/// <returns>A string representation of the deletion result.</returns>
		/// <response code="200">Agent identity successfully deleted.</response>
		/// <response code="404">Agent identity with the specified ID not found.</response>
		/// <response code="500">Internal server error during deletion.</response>
		[HttpDelete("{id}")]
		public async Task<string?> Delete(string id)
		{
			var result = await DownstreamApi.DeleteForAppAsync<string, object>(
				"msGraphAgentIdentity",
				input: null!,
			  	options =>
				  {
					  options.RelativePath += $"/{Uri.EscapeDataString(id)}"; // Specify the ID of the agent identity to delete
				  });
			return result?.ToString();
		}
	}
}
