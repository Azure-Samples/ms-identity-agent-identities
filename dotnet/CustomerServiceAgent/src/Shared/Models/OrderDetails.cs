namespace Shared.Models;

/// <summary>
/// Represents order information
/// </summary>
public class OrderDetails
{
    public required string OrderId { get; set; }
    public required string CustomerId { get; set; }
    public required string ProductName { get; set; }
    public int Quantity { get; set; }
    public decimal Price { get; set; }
    public required string Status { get; set; }
    public DateTime OrderDate { get; set; }
}
