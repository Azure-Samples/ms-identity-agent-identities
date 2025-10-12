using Microsoft.Identity.Abstractions;
using Shared.Models;
using System.Net.Http.Headers;
using System.Net.Http.Json;

namespace AgentOrchestrator.Services;

/// <summary>
/// Orchestration service that calls downstream APIs using agent identities
/// This is a demonstration of how to use IAuthorizationHeaderProvider
/// In a production scenario with Agent Identities, use .WithAgentIdentity() and .WithAgentUserIdentity() extension methods
/// </summary>
public class OrchestrationService
{
    private readonly IAuthorizationHeaderProvider _authorizationHeaderProvider;
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly IConfiguration _configuration;
    private readonly ILogger<OrchestrationService> _logger;

    public OrchestrationService(
        IAuthorizationHeaderProvider authorizationHeaderProvider,
        IHttpClientFactory httpClientFactory,
        IConfiguration configuration,
        ILogger<OrchestrationService> logger)
    {
        _authorizationHeaderProvider = authorizationHeaderProvider;
        _httpClientFactory = httpClientFactory;
        _configuration = configuration;
        _logger = logger;
    }

    /// <summary>
    /// Get order details using autonomous agent identity (read operation)
    /// NOTE: In production, this should use:
    ///   .CreateAuthorizationHeaderForAppAsync(scope, options.WithAgentIdentity(agentId))
    /// </summary>
    public async Task<OrderDetails?> GetOrderDetailsAsync(string orderId)
    {
        var orderServiceUrl = _configuration["Services:OrderService"] 
            ?? throw new InvalidOperationException("OrderService URL not configured");

        _logger.LogInformation("Acquiring token for Order Service (Autonomous Agent Identity pattern)");

        // In production with Agent Identities enabled:
        // var authHeader = await _authorizationHeaderProvider.CreateAuthorizationHeaderForAppAsync(
        //     $"api://YOUR_ORDER_SERVICE_CLIENT_ID/.default",
        //     new AuthorizationHeaderProviderOptions().WithAgentIdentity(autonomousAgentId));
        
        // For demo purposes, using standard app-only token
        var authHeader = await _authorizationHeaderProvider.CreateAuthorizationHeaderForAppAsync(
            $"api://YOUR_ORDER_SERVICE_CLIENT_ID/.default");

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
    /// Get customer history using autonomous agent identity (read operation)
    /// </summary>
    public async Task<CustomerHistory?> GetCustomerHistoryAsync(string customerId)
    {
        var crmServiceUrl = _configuration["Services:CrmService"] 
            ?? throw new InvalidOperationException("CrmService URL not configured");

        _logger.LogInformation("Acquiring token for CRM Service (Autonomous Agent Identity pattern)");

        // For demo purposes, using standard app-only token
        var authHeader = await _authorizationHeaderProvider.CreateAuthorizationHeaderForAppAsync(
            $"api://YOUR_CRM_SERVICE_CLIENT_ID/.default");

        var httpClient = _httpClientFactory.CreateClient();
        httpClient.DefaultRequestHeaders.Authorization = AuthenticationHeaderValue.Parse(authHeader);

        _logger.LogInformation("Calling CRM Service GET /api/customers/{CustomerId}", customerId);
        var response = await httpClient.GetAsync($"{crmServiceUrl}/api/customers/{customerId}");

        if (response.IsSuccessStatusCode)
        {
            _logger.LogInformation("Successfully retrieved customer {CustomerId}", customerId);
            return await response.Content.ReadFromJsonAsync<CustomerHistory>();
        }

        _logger.LogWarning("Failed to retrieve customer {CustomerId}: {StatusCode}", customerId, response.StatusCode);
        return null;
    }

    /// <summary>
    /// Update delivery info using agent user identity (write operation with user context)
    /// NOTE: In production with Agent Identities, this should use:
    ///   .CreateAuthorizationHeaderForUserAsync(scopes, options.WithAgentUserIdentity(agentUserId, userUpn))
    /// </summary>
    public async Task<DeliveryInfo?> UpdateDeliveryAsync(string orderId, DeliveryInfo updatedInfo, string userUpn)
    {
        var shippingServiceUrl = _configuration["Services:ShippingService"] 
            ?? throw new InvalidOperationException("ShippingService URL not configured");

        _logger.LogInformation("Acquiring token for Shipping Service (Agent User Identity pattern) for user {UserUpn}", userUpn);

        // In production with Agent Identities enabled:
        // var authHeader = await _authorizationHeaderProvider.CreateAuthorizationHeaderForUserAsync(
        //     new[] { $"api://YOUR_SHIPPING_SERVICE_CLIENT_ID/.default" },
        //     new AuthorizationHeaderProviderOptions().WithAgentUserIdentity(agentUserId, userUpn));
        
        // For demo purposes, using standard delegated token (requires interactive login)
        try
        {
            var authHeader = await _authorizationHeaderProvider.CreateAuthorizationHeaderForUserAsync(
                new[] { $"api://YOUR_SHIPPING_SERVICE_CLIENT_ID/.default" });

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
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Unable to acquire user token. Agent User Identity would be used in production.");
        }
        
        return null;
    }

    /// <summary>
    /// Send email using agent user identity
    /// </summary>
    public async Task<bool> SendEmailAsync(EmailRequest emailRequest, string userUpn)
    {
        var emailServiceUrl = _configuration["Services:EmailService"] 
            ?? throw new InvalidOperationException("EmailService URL not configured");

        _logger.LogInformation("Acquiring token for Email Service (Agent User Identity pattern) for user {UserUpn}", userUpn);

        try
        {
            var authHeader = await _authorizationHeaderProvider.CreateAuthorizationHeaderForUserAsync(
                new[] { $"api://YOUR_EMAIL_SERVICE_CLIENT_ID/.default" });

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
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Unable to acquire user token. Agent User Identity would be used in production.");
        }
        
        return false;
    }
}
