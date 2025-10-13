using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Identity.Web.Resource;
using ShippingService.Services;
using Shared.Models;

namespace ShippingService.Controllers;

/// <summary>
/// Shipping API controller - requires authentication with agent user identity
/// </summary>
[Authorize]
[ApiController]
[Route("api/[controller]")]
public class ShippingController : ControllerBase
{
    private readonly DeliveryStore _deliveryStore;
    private readonly ILogger<ShippingController> _logger;

    public ShippingController(DeliveryStore deliveryStore, ILogger<ShippingController> logger)
    {
        _deliveryStore = deliveryStore;
        _logger = logger;
    }

    /// <summary>
    /// Get delivery info by order ID (read operation)
    /// </summary>
    [HttpGet("{orderId}")]
    [RequiredScope("Shipping.Read")]
    public ActionResult<DeliveryInfo> GetDelivery(string orderId)
    {
        _logger.LogInformation("Fetching delivery info for order {OrderId}", orderId);

        var delivery = _deliveryStore.GetDelivery(orderId);
        if (delivery == null)
        {
            _logger.LogWarning("Delivery info for order {OrderId} not found", orderId);
            return NotFound(new { message = $"Delivery info for order {orderId} not found" });
        }

        _logger.LogInformation("Delivery info for order {OrderId} retrieved successfully", orderId);
        return Ok(delivery);
    }

    /// <summary>
    /// Update delivery info (write operation - requires user context)
    /// </summary>
    [HttpPut("{orderId}")]
    [RequiredScope("Shipping.Write")]
    public ActionResult<DeliveryInfo> UpdateDelivery(string orderId, [FromBody] DeliveryInfo updatedInfo)
    {
        _logger.LogInformation("Updating delivery info for order {OrderId} by user {User}", 
            orderId, User.Identity?.Name ?? "Unknown");

        var existingDelivery = _deliveryStore.GetDelivery(orderId);
        if (existingDelivery == null)
        {
            _logger.LogWarning("Delivery info for order {OrderId} not found", orderId);
            return NotFound(new { message = $"Delivery info for order {orderId} not found" });
        }

        if (_deliveryStore.UpdateDelivery(orderId, updatedInfo))
        {
            _logger.LogInformation("Delivery info for order {OrderId} updated successfully", orderId);
            return Ok(updatedInfo);
        }

        _logger.LogError("Failed to update delivery info for order {OrderId}", orderId);
        return StatusCode(500, new { message = "Failed to update delivery info" });
    }

    /// <summary>
    /// Get all deliveries
    /// </summary>
    [HttpGet]
    [RequiredScope("Shipping.Read")]
    public ActionResult<IEnumerable<DeliveryInfo>> GetAllDeliveries()
    {
        _logger.LogInformation("Fetching all deliveries");
        var deliveries = _deliveryStore.GetAllDeliveries();
        return Ok(deliveries);
    }
}
