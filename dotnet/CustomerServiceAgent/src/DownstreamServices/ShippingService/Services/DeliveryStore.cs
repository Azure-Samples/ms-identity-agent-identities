using Shared.Models;
using System.Collections.Concurrent;

namespace ShippingService.Services;

/// <summary>
/// In-memory delivery info store for demo purposes
/// </summary>
public class DeliveryStore
{
    private readonly ConcurrentDictionary<string, DeliveryInfo> _deliveries = new();

    public DeliveryStore()
    {
        // Seed with sample data
        _deliveries.TryAdd("12345", new DeliveryInfo
        {
            OrderId = "12345",
            TrackingNumber = "TRK123456789",
            Status = "In Transit",
            Carrier = "FedEx",
            EstimatedDelivery = DateTime.UtcNow.AddDays(2),
            ShippingAddress = "123 Main St, Seattle, WA 98101"
        });

        _deliveries.TryAdd("67890", new DeliveryInfo
        {
            OrderId = "67890",
            TrackingNumber = "TRK987654321",
            Status = "Out for Delivery",
            Carrier = "UPS",
            EstimatedDelivery = DateTime.UtcNow.AddDays(1),
            ShippingAddress = "456 Oak Ave, Portland, OR 97201"
        });

        _deliveries.TryAdd("11111", new DeliveryInfo
        {
            OrderId = "11111",
            TrackingNumber = "TRK111111111",
            Status = "Delivered",
            Carrier = "USPS",
            EstimatedDelivery = DateTime.UtcNow.AddDays(-2),
            ShippingAddress = "789 Pine Rd, San Francisco, CA 94102"
        });
    }

    public DeliveryInfo? GetDelivery(string orderId)
    {
        _deliveries.TryGetValue(orderId, out var delivery);
        return delivery;
    }

    public bool UpdateDelivery(string orderId, DeliveryInfo updatedInfo)
    {
        return _deliveries.TryUpdate(orderId, updatedInfo, _deliveries[orderId]);
    }

    public IEnumerable<DeliveryInfo> GetAllDeliveries()
    {
        return _deliveries.Values;
    }
}
