using Microsoft.Identity.Abstractions;
using Microsoft.Identity.Web;
using Shared.Models;
using System.Net.Http.Headers;
using System.Net.Http.Json;

namespace AgentOrchestrator.Services;

/// <summary>
/// Orchestration service that calls downstream APIs using agent identities
/// Note: Agent Identities support is configured with extension methods like .WithAgentIdentity() and .WithAgentUserIdentity()
/// These methods are part of Microsoft.Identity.Web.AgentIdentities and may require specific setup
/// </summary>
public class OrchestrationService
{
	private readonly IAuthorizationHeaderProvider _authorizationHeaderProvider;
	private readonly IDownstreamApi _downstreamApi;
	private readonly IHttpClientFactory _httpClientFactory;
	private readonly IConfiguration _configuration;
	private readonly ILogger<OrchestrationService> _logger;

	public OrchestrationService(
		IAuthorizationHeaderProvider authorizationHeaderProvider,
		IDownstreamApi downstreamApi,
		IHttpClientFactory httpClientFactory,
		IConfiguration configuration,
		ILogger<OrchestrationService> logger)
	{
		_authorizationHeaderProvider = authorizationHeaderProvider;
		_downstreamApi = downstreamApi;
		_httpClientFactory = httpClientFactory;
		_configuration = configuration;
		_logger = logger;
	}

	/// <summary>
	/// Get order details using agent identity (using IAuthorizationHeaderProvider)
	/// </summary>
	public async Task<OrderDetails?> GetOrderDetailsAsync(string orderId, string? agentIdentity = null)
	{
		var orderServiceConfig = _configuration.GetSection("DownstreamApis:OrderService");
		var orderServiceUrl = orderServiceConfig["BaseUrl"]
			?? throw new InvalidOperationException("OrderService URL not configured");
		var scopes = orderServiceConfig["Scopes:0"]
			?? throw new InvalidOperationException("OrderService scopes not configured");

		var agentId = agentIdentity ?? _configuration["AgentIdentities:AgentIdentity"];
		_logger.LogInformation("Acquiring token for Order Service using agent identity {AgentId}", agentId);

		// Acquire token using agent identity
		var authHeader = await _authorizationHeaderProvider.CreateAuthorizationHeaderForAppAsync(scopes,
			agentIdentity != null ? new AuthorizationHeaderProviderOptions().WithAgentIdentity(agentIdentity) : null);

		var httpClient = _httpClientFactory.CreateClient();
		httpClient.DefaultRequestHeaders.Authorization = AuthenticationHeaderValue.Parse(authHeader);

		_logger.LogInformation("Calling Order Service GET /api/orders/{OrderId}", orderId);
		var response = await httpClient.GetAsync($"{orderServiceUrl}/api/orders/{orderId}");

		if (response.IsSuccessStatusCode)
		{
			_logger.LogInformation("Successfully retrieved order {OrderId}", orderId);
			return await response.Content.ReadFromJsonAsync<OrderDetails>();
		}

		_logger.LogWarning("Failed to retrieve order {OrderId}: {StatusCode}", orderId, response.StatusCode);
		return null;
	}

	/// <summary>
	/// Update delivery info using agent user identity (write operation with user context)
	/// </summary>
	public async Task<DeliveryInfo?> UpdateDeliveryAsync(string orderId, DeliveryInfo updatedInfo, string userUpn, string? agentIdentity = null)
	{
		var shippingServiceConfig = _configuration.GetSection("DownstreamApis:ShippingService");
		var shippingServiceUrl = shippingServiceConfig["BaseUrl"]
			?? throw new InvalidOperationException("ShippingService URL not configured");
		var scopes = shippingServiceConfig.GetSection("Scopes").Get<string[]>()
			?? throw new InvalidOperationException("ShippingService scopes not configured");

		var agentUserId = agentIdentity ?? _configuration["AgentIdentities:AgentUserId"];
		_logger.LogInformation("Acquiring token for Shipping Service using agent user identity {AgentUserId} with user {UserUpn}",
			agentUserId, userUpn);

		// Acquire token using agent user identity with user context
		var authHeader = await _authorizationHeaderProvider.CreateAuthorizationHeaderForUserAsync(scopes,
			new AuthorizationHeaderProviderOptions().WithAgentUserIdentity(agentIdentity, userUpn));

		var httpClient = _httpClientFactory.CreateClient();
		httpClient.DefaultRequestHeaders.Authorization = AuthenticationHeaderValue.Parse(authHeader);

		_logger.LogInformation("Calling Shipping Service PUT /api/shipping/{OrderId}", orderId);
		var response = await httpClient.PutAsJsonAsync($"{shippingServiceUrl}/api/shipping/{orderId}", updatedInfo);

		if (response.IsSuccessStatusCode)
		{
			_logger.LogInformation("Successfully updated delivery for order {OrderId}", orderId);
			return await response.Content.ReadFromJsonAsync<DeliveryInfo>();
		}

		_logger.LogWarning("Failed to update delivery for order {OrderId}: {StatusCode}", orderId, response.StatusCode);
		return null;
	}

	/// <summary>
	/// Send email using agent user identity
	/// </summary>
	public async Task<bool> SendEmailAsync(EmailRequest emailRequest, string userUpn, string? agentIdentity = null)
	{
		var emailServiceConfig = _configuration.GetSection("DownstreamApis:EmailService");
		var emailServiceUrl = emailServiceConfig["BaseUrl"]
			?? throw new InvalidOperationException("EmailService URL not configured");
		var scopes = emailServiceConfig.GetSection("Scopes").Get<string[]>()
			?? throw new InvalidOperationException("EmailService scopes not configured");

		var agentUserId = agentIdentity ?? _configuration["AgentIdentities:AgentUserId"];
		_logger.LogInformation("Acquiring token for Email Service using agent user identity {AgentUserId} with user {UserUpn}",
			agentUserId, userUpn);

		// Acquire token using agent user identity with user context
		var authHeader = await _authorizationHeaderProvider.CreateAuthorizationHeaderForUserAsync(scopes,
			new AuthorizationHeaderProviderOptions().WithAgentUserIdentity(agentUserId, userUpn));

		var httpClient = _httpClientFactory.CreateClient();
		httpClient.DefaultRequestHeaders.Authorization = AuthenticationHeaderValue.Parse(authHeader);

		_logger.LogInformation("Calling Email Service POST /api/email/send");
		var response = await httpClient.PostAsJsonAsync($"{emailServiceUrl}/api/email/send", emailRequest);

		if (response.IsSuccessStatusCode)
		{
			_logger.LogInformation("Successfully sent email to {To}", emailRequest.To);
			return true;
		}

		_logger.LogWarning("Failed to send email: {StatusCode}", response.StatusCode);
		return false;
	}
}
