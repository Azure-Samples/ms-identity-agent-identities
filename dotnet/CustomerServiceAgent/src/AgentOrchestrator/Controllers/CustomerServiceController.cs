using Microsoft.AspNetCore.Mvc;
using AgentOrchestrator.Services;
using Shared.Models;

namespace AgentOrchestrator.Controllers;

/// <summary>
/// Customer Service orchestration controller
/// Demonstrates how agents securely call downstream services using Agent Identities
/// </summary>
[ApiController]
[Route("api/[controller]")]
public class CustomerServiceController : ControllerBase
{
    private readonly OrchestrationService _orchestrationService;
    private readonly ILogger<CustomerServiceController> _logger;

    public CustomerServiceController(
        OrchestrationService orchestrationService,
        ILogger<CustomerServiceController> logger)
    {
        _orchestrationService = orchestrationService;
        _logger = logger;
    }

    /// <summary>
    /// Process a customer service request
    /// This demonstrates the complete orchestration flow using both autonomous and user agent identities
    /// </summary>
    /// <param name="request">Orchestration request with order ID and optional user UPN</param>
    /// <returns>Orchestration result with data from all services</returns>
    [HttpPost("process")]
    public async Task<ActionResult<OrchestrationResult>> ProcessRequest([FromBody] OrchestrationRequest request)
    {
        _logger.LogInformation("Processing customer service request for order {OrderId}", request.OrderId);

        var result = new OrchestrationResult
        {
            OrderId = request.OrderId,
            Status = "Processing",
            Messages = new List<string>()
        };

        try
        {
            // Step 1: Get order details using agent identity (read operation)
            _logger.LogInformation("Step 1: Fetching order details using agent identity");
            result.Messages.Add("Fetching order details using agent identity...");
            
            result.OrderDetails = await _orchestrationService.GetOrderDetailsAsync(request.OrderId, request.AgentIdentity);
            
            if (result.OrderDetails == null)
            {
                result.Status = "Failed";
                result.Messages.Add($"Order {request.OrderId} not found");
                return NotFound(result);
            }

            result.Messages.Add($"Order {request.OrderId} retrieved successfully");

            // Step 2: Get customer history using agent identity (read operation)
            _logger.LogInformation("Step 2: Fetching customer history using agent identity");
            result.Messages.Add("Fetching customer history using agent identity...");
            
            result.CustomerHistory = await _orchestrationService.GetCustomerHistoryAsync(result.OrderDetails.CustomerId, request.AgentIdentity);
            
            if (result.CustomerHistory != null)
            {
                result.Messages.Add($"Customer {result.OrderDetails.CustomerId} history retrieved successfully");
            }
            else
            {
                result.Messages.Add($"Customer history not found (non-critical)");
            }

            // Step 3: Update delivery info using agent user identity (write operation - requires user context)
            if (!string.IsNullOrEmpty(request.UserUpn))
            {
                _logger.LogInformation("Step 3: Updating delivery info using agent user identity");
                result.Messages.Add("Updating delivery info using agent user identity...");

                var updatedDelivery = new DeliveryInfo
                {
                    OrderId = request.OrderId,
                    TrackingNumber = "TRK-UPDATED-" + Guid.NewGuid().ToString("N")[..8].ToUpper(),
                    Status = "Updated by Agent",
                    Carrier = "Express Delivery",
                    EstimatedDelivery = DateTime.UtcNow.AddDays(1),
                    ShippingAddress = "Updated via orchestration"
                };

                result.DeliveryInfo = await _orchestrationService.UpdateDeliveryAsync(
                    request.OrderId, 
                    updatedDelivery, 
                    request.UserUpn,
                    request.AgentIdentity);

                if (result.DeliveryInfo != null)
                {
                    result.Messages.Add("Delivery info updated successfully");
                }

                // Step 4: Send email notification using agent user identity
                _logger.LogInformation("Step 4: Sending email notification using agent user identity");
                result.Messages.Add("Sending email notification using agent user identity...");

                var emailRequest = new EmailRequest
                {
                    To = result.CustomerHistory?.Email ?? "customer@example.com",
                    Subject = $"Order {request.OrderId} Status Update",
                    Body = $"Your order {request.OrderId} has been updated. Status: {result.OrderDetails.Status}",
                    From = "customerservice@example.com"
                };

                result.EmailSent = await _orchestrationService.SendEmailAsync(emailRequest, request.UserUpn, request.AgentIdentity);
                
                if (result.EmailSent)
                {
                    result.Messages.Add("Email notification sent successfully");
                }
            }
            else
            {
                result.Messages.Add("User UPN not provided - skipping write operations (delivery update and email)");
            }

            result.Status = "Completed";
            result.Messages.Add("Customer service request processed successfully");

            _logger.LogInformation("Customer service request for order {OrderId} completed successfully", request.OrderId);
            return Ok(result);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing customer service request for order {OrderId}", request.OrderId);
            result.Status = "Failed";
            result.Messages.Add($"Error: {ex.Message}");
            return StatusCode(500, result);
        }
    }

    /// <summary>
    /// Health check endpoint
    /// </summary>
    [HttpGet("health")]
    public ActionResult<object> HealthCheck()
    {
        return Ok(new 
        { 
            status = "Healthy", 
            service = "Customer Service Agent Orchestrator",
            timestamp = DateTime.UtcNow 
        });
    }
}
