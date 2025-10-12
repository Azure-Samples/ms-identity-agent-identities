using Shared.Models;
using System.Collections.Concurrent;

namespace CrmService.Services;

/// <summary>
/// In-memory customer history store for demo purposes
/// </summary>
public class CustomerStore
{
    private readonly ConcurrentDictionary<string, CustomerHistory> _customers = new();

    public CustomerStore()
    {
        // Seed with sample data
        _customers.TryAdd("C001", new CustomerHistory
        {
            CustomerId = "C001",
            CustomerName = "Contoso Corporation",
            Email = "purchasing@contoso.com",
            TotalOrders = 25,
            LifetimeValue = 125000.00m,
            Tier = "Platinum",
            CustomerSince = DateTime.UtcNow.AddYears(-3)
        });

        _customers.TryAdd("C002", new CustomerHistory
        {
            CustomerId = "C002",
            CustomerName = "Fabrikam Inc",
            Email = "orders@fabrikam.com",
            TotalOrders = 15,
            LifetimeValue = 75000.00m,
            Tier = "Gold",
            CustomerSince = DateTime.UtcNow.AddYears(-2)
        });

        _customers.TryAdd("C003", new CustomerHistory
        {
            CustomerId = "C003",
            CustomerName = "Northwind Traders",
            Email = "sales@northwind.com",
            TotalOrders = 8,
            LifetimeValue = 35000.00m,
            Tier = "Silver",
            CustomerSince = DateTime.UtcNow.AddYears(-1)
        });
    }

    public CustomerHistory? GetCustomer(string customerId)
    {
        _customers.TryGetValue(customerId, out var customer);
        return customer;
    }

    public IEnumerable<CustomerHistory> GetAllCustomers()
    {
        return _customers.Values;
    }
}
