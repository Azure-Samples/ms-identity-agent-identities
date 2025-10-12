namespace Shared.Models;

/// <summary>
/// Represents customer history from CRM
/// </summary>
public class CustomerHistory
{
    public required string CustomerId { get; set; }
    public required string CustomerName { get; set; }
    public required string Email { get; set; }
    public int TotalOrders { get; set; }
    public decimal LifetimeValue { get; set; }
    public required string Tier { get; set; }
    public DateTime CustomerSince { get; set; }
}
