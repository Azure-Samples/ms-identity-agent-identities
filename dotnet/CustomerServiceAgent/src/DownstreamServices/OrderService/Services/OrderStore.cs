using Shared.Models;
using System.Collections.Concurrent;

namespace OrderService.Services;

/// <summary>
/// In-memory order store for demo purposes
/// </summary>
public class OrderStore
{
    private readonly ConcurrentDictionary<string, OrderDetails> _orders = new();

    public OrderStore()
    {
        // Seed with sample data
        _orders.TryAdd("12345", new OrderDetails
        {
            OrderId = "12345",
            CustomerId = "C001",
            ProductName = "Enterprise Software License",
            Quantity = 10,
            Price = 9999.99m,
            Status = "Processing",
            OrderDate = DateTime.UtcNow.AddDays(-2)
        });

        _orders.TryAdd("67890", new OrderDetails
        {
            OrderId = "67890",
            CustomerId = "C002",
            ProductName = "Cloud Services Package",
            Quantity = 5,
            Price = 4999.99m,
            Status = "Shipped",
            OrderDate = DateTime.UtcNow.AddDays(-5)
        });

        _orders.TryAdd("11111", new OrderDetails
        {
            OrderId = "11111",
            CustomerId = "C001",
            ProductName = "Support Contract",
            Quantity = 1,
            Price = 2499.99m,
            Status = "Delivered",
            OrderDate = DateTime.UtcNow.AddDays(-10)
        });
    }

    public OrderDetails? GetOrder(string orderId)
    {
        _orders.TryGetValue(orderId, out var order);
        return order;
    }

    public IEnumerable<OrderDetails> GetAllOrders()
    {
        return _orders.Values;
    }
}
