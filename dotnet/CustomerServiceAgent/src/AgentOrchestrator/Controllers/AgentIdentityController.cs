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
		/// Create a new Agent Identity with the specified name (for the current Agent Application).
		/// Optionally create a new agent user identity.
		/// </summary>
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
			string adminConsentUrl = string.Empty;
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


				adminConsentUrl = $"https://login.microsoftonline.com/{tenantId}/v2.0/adminconsent?client_id={newAgentIdentity.id}&scope={string.Join("%20", scopesToRequest)}&redirect_uri=https://entra.microsoft.com/TokenAuthorize&state=xyz123";
			}

			return Ok(new {AgentIdentity=newAgentIdentity, AgentUserIdentity = newAgentUserId, AdminConsentUrl = adminConsentUrl});
		}



		// Get the list of Agent Identities associated with the current agent application (on behalf of the current user)
		// GET: api/<AgentIdentity>
		[HttpGet]
		public async Task<IEnumerable<AgentIdentity>> Get()
		{
			try
			{
				return await DownstreamApi.GetForAppAsync<IEnumerable<AgentIdentity>>("msGraphAgentIdentity");
			}
			catch (Exception ex)
			{
				throw;
			}
		}


		// Delete an Agent Identity by ID (on behalf of the agent application)
		// DELETE api/<AgentIdentity>/5
		[HttpDelete("{id}")]
		public async Task<string> Delete(string id)
		{
			var result = await DownstreamApi.DeleteForAppAsync<string, object>(
				"msGraphAgentIdentity",
				input: null!,
			  	options =>
				  {
					  options.RelativePath += $"/{id}"; // Specify the ID of the agent identity to delete
				  });
			return result!.ToString();
		}
	}
}
