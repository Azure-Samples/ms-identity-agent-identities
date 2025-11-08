using System.Text.Json.Serialization;

namespace AgentIdentityModel
{
	public class AgentIdentity
	{
		[JsonPropertyName("@odata.type")]
		public string @odata_type { get; set; } = "#Microsoft.Graph.AgentIdentity";

		[JsonPropertyName("displayName")]
		public string? displayName { get; set; }

		[JsonPropertyName("agentIdentityBlueprintId")]
		public string? agentIdentityBlueprintId { get; set; }

		[JsonPropertyName("id")]
		public string? id { get; set; }

		[JsonPropertyName("sponsors@odata.bind")]
		public string[]? sponsorsOdataBind { get; set; }

		[JsonPropertyName("owners@odata.bind")]
		public string[]? ownersOdataBind { get; set; }
	}
}
