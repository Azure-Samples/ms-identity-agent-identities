using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Identity.Web.Resource;
using CrmService.Services;
using Shared.Models;

namespace CrmService.Controllers;

/// <summary>
/// CRM API controller - requires authentication with autonomous agent identity
/// </summary>
[Authorize]
[ApiController]
[Route("api/[controller]")]
[RequiredScope("CRM.Read")]
public class CustomersController : ControllerBase
{
    private readonly CustomerStore _customerStore;
    private readonly ILogger<CustomersController> _logger;

    public CustomersController(CustomerStore customerStore, ILogger<CustomersController> logger)
    {
        _customerStore = customerStore;
        _logger = logger;
    }

    /// <summary>
    /// Get customer history by ID
    /// </summary>
    [HttpGet("{customerId}")]
    public ActionResult<CustomerHistory> GetCustomer(string customerId)
    {
        _logger.LogInformation("Fetching customer {CustomerId}", customerId);

        var customer = _customerStore.GetCustomer(customerId);
        if (customer == null)
        {
            _logger.LogWarning("Customer {CustomerId} not found", customerId);
            return NotFound(new { message = $"Customer {customerId} not found" });
        }

        _logger.LogInformation("Customer {CustomerId} retrieved successfully", customerId);
        return Ok(customer);
    }

    /// <summary>
    /// Get all customers
    /// </summary>
    [HttpGet]
    public ActionResult<IEnumerable<CustomerHistory>> GetAllCustomers()
    {
        _logger.LogInformation("Fetching all customers");
        var customers = _customerStore.GetAllCustomers();
        return Ok(customers);
    }
}
