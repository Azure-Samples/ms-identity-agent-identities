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
		if (!orderServiceConfig.Exists())
		{
			_logger.LogError("OrderService configuration section not found in appsettings");
			throw new InvalidOperationException("OrderService configuration is missing. Please ensure 'DownstreamApis:OrderService' is configured in appsettings.json.");
		}

		var scopes = orderServiceConfig["Scopes:0"];
		if (string.IsNullOrEmpty(scopes))
		{
			_logger.LogError("OrderService scopes not configured");
			throw new InvalidOperationException("OrderService scopes are missing. Please ensure 'DownstreamApis:OrderService:Scopes' is configured in appsettings.json.");
		}

		var orderServiceBaseUrl = _configuration.GetValue<string>("services:orderservice:https:0");
		if (string.IsNullOrEmpty(orderServiceBaseUrl))
		{
			_logger.LogError("OrderService URL not configured");
			throw new InvalidOperationException("OrderService URL is missing. This value is typically provided by Aspire service discovery. Ensure the service is configured correctly.");
		}

		var agentId = agentIdentity ?? _configuration["AgentIdentities:AgentIdentity"];
		if (string.IsNullOrEmpty(agentId))
		{
			_logger.LogError("Agent identity not provided and not configured");
			throw new InvalidOperationException("Agent identity is required. Please provide an agentIdentity parameter or configure 'AgentIdentities:AgentIdentity' in appsettings.json.");
		}

		_logger.LogInformation("Acquiring token for Order Service using agent identity {AgentId}", agentId);

		// Acquire token using agent identity
		var authHeader = await _authorizationHeaderProvider.CreateAuthorizationHeaderForAppAsync(scopes,
			agentIdentity != null ? new AuthorizationHeaderProviderOptions().WithAgentIdentity(agentIdentity) : null);

		var httpClient = _httpClientFactory.CreateClient("orderservice");

		httpClient.DefaultRequestHeaders.Authorization = AuthenticationHeaderValue.Parse(authHeader);

		_logger.LogInformation("Calling Order Service GET /api/orders/{OrderId}", orderId);
		var response = await httpClient.GetAsync($"{orderServiceBaseUrl}/api/orders/{orderId}");

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
		if (!shippingServiceConfig.Exists())
		{
			_logger.LogError("ShippingService configuration section not found in appsettings");
			throw new InvalidOperationException("ShippingService configuration is missing. Please ensure 'DownstreamApis:ShippingService' is configured in appsettings.json.");
		}

		var shippingServiceUrl = _configuration.GetValue<string>("services:shippingservice:https:0");
		if (string.IsNullOrEmpty(shippingServiceUrl))
		{
			_logger.LogError("ShippingService URL not configured");
			throw new InvalidOperationException("ShippingService URL is missing. This value is typically provided by Aspire service discovery. Ensure the service is configured correctly.");
		}

		var scopes = shippingServiceConfig.GetSection("Scopes").Get<string[]>();
		if (scopes == null || scopes.Length == 0)
		{
			_logger.LogError("ShippingService scopes not configured");
			throw new InvalidOperationException("ShippingService scopes are missing. Please ensure 'DownstreamApis:ShippingService:Scopes' is configured in appsettings.json.");
		}

		var agentUserId = agentIdentity ?? _configuration["AgentIdentities:AgentUserId"];
		if (string.IsNullOrEmpty(agentUserId))
		{
			_logger.LogError("Agent user identity not provided and not configured");
			throw new InvalidOperationException("Agent user identity is required. Please provide an agentIdentity parameter or configure 'AgentIdentities:AgentUserId' in appsettings.json.");
		}

		if (string.IsNullOrEmpty(userUpn))
		{
			_logger.LogError("User UPN is required for agent user identity operations");
			throw new ArgumentException("User UPN cannot be null or empty", nameof(userUpn));
		}

		_logger.LogInformation("Acquiring token for Shipping Service using agent user identity {AgentUserId} with user {UserUpn}",
			agentUserId, userUpn);

		// Acquire token using agent user identity with user context
		var authHeader = await _authorizationHeaderProvider.CreateAuthorizationHeaderForUserAsync(scopes,
			agentIdentity != null ? new AuthorizationHeaderProviderOptions().WithAgentUserIdentity(agentIdentity, userUpn) : null);

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
		if (!emailServiceConfig.Exists())
		{
			_logger.LogError("EmailService configuration section not found in appsettings");
			throw new InvalidOperationException("EmailService configuration is missing. Please ensure 'DownstreamApis:EmailService' is configured in appsettings.json.");
		}

		var emailServiceUrl = _configuration.GetValue<string>("services:emailservice:https:0");
		if (string.IsNullOrEmpty(emailServiceUrl))
		{
			_logger.LogError("EmailService URL not configured");
			throw new InvalidOperationException("EmailService URL is missing. This value is typically provided by Aspire service discovery. Ensure the service is configured correctly.");
		}

		var scopes = emailServiceConfig.GetSection("Scopes").Get<string[]>();
		if (scopes == null || scopes.Length == 0)
		{
			_logger.LogError("EmailService scopes not configured");
			throw new InvalidOperationException("EmailService scopes are missing. Please ensure 'DownstreamApis:EmailService:Scopes' is configured in appsettings.json.");
		}

		var agentUserId = agentIdentity ?? _configuration["AgentIdentities:AgentUserId"];
		if (string.IsNullOrEmpty(agentUserId))
		{
			_logger.LogError("Agent user identity not provided and not configured");
			throw new InvalidOperationException("Agent user identity is required. Please provide an agentIdentity parameter or configure 'AgentIdentities:AgentUserId' in appsettings.json.");
		}

		if (string.IsNullOrEmpty(userUpn))
		{
			_logger.LogError("User UPN is required for agent user identity operations");
			throw new ArgumentException("User UPN cannot be null or empty", nameof(userUpn));
		}

		_logger.LogInformation("Acquiring token for Email Service using agent user identity {AgentUserId} with user {UserUpn}",
			agentUserId, userUpn);

		// Acquire token using agent user identity with user context
		var authHeader = await _authorizationHeaderProvider.CreateAuthorizationHeaderForUserAsync(scopes,
			agentUserId !=null ? new AuthorizationHeaderProviderOptions().WithAgentUserIdentity(agentUserId, userUpn) : null);

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
