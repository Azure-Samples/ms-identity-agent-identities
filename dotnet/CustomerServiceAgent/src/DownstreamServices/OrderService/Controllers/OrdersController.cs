using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Identity.Web.Resource;
using OrderService.Services;
using Shared.Models;

namespace OrderService.Controllers;

/// <summary>
/// Order API controller - requires authentication with autonomous agent identity
/// </summary>
[Authorize]
[ApiController]
[Route("api/[controller]")]
//[RequiredScope("Orders.Read")]
public class OrdersController : ControllerBase
{
    private readonly OrderStore _orderStore;
    private readonly ILogger<OrdersController> _logger;

    public OrdersController(OrderStore orderStore, ILogger<OrdersController> logger)
    {
        _orderStore = orderStore;
        _logger = logger;
    }

    /// <summary>
    /// Get order by ID
    /// </summary>
    [HttpGet("{orderId}")]
    public ActionResult<OrderDetails> GetOrder(string orderId)
    {
        _logger.LogInformation("Fetching order {OrderId}", orderId);

        var order = _orderStore.GetOrder(orderId);
        if (order == null)
        {
            _logger.LogWarning("Order {OrderId} not found", orderId);
            return NotFound(new { message = $"Order {orderId} not found" });
        }

        _logger.LogInformation("Order {OrderId} retrieved successfully", orderId);
        return Ok(order);
    }

    /// <summary>
    /// Get all orders
    /// </summary>
    [HttpGet]
    public ActionResult<IEnumerable<OrderDetails>> GetAllOrders()
    {
        _logger.LogInformation("Fetching all orders");
        var orders = _orderStore.GetAllOrders();
        return Ok(orders);
    }
}
