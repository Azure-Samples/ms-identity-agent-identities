namespace Shared.Models;

/// <summary>
/// Represents shipping/delivery information
/// </summary>
public class DeliveryInfo
{
    public required string OrderId { get; set; }
    public required string TrackingNumber { get; set; }
    public required string Status { get; set; }
    public required string Carrier { get; set; }
    public DateTime EstimatedDelivery { get; set; }
    public required string ShippingAddress { get; set; }
}
