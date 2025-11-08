using System.Text.Json.Serialization;

namespace AgentIdentityModel
{
	public class AgentUserIdentity
	{
		[JsonPropertyName("@odata.type")]
		public string @odata_type { get; set; } = "#Microsoft.graph.agentUser";

		[JsonPropertyName("displayName")]
		public string? displayName { get; set; }

		// "agentuserupn@tenant.onmicrosoft.com"
		[JsonPropertyName("userPrincipalName")]
		public string? userPrincipalName { get; set; }

		[JsonPropertyName("id")]
		public string? id { get; set; }

		// Parent agent identity ID
		[JsonPropertyName("identityParentId")]
		public string? identityParentId { get; set; }

		[JsonPropertyName("mailNickname")]
		public string? mailNickname { get; set; }

		[JsonPropertyName("accountEnabled")]
		public bool accountEnabled { get; set; } = true;
	}

}
