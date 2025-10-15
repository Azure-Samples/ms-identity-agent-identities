namespace Shared.Models;

/// <summary>
/// Result of orchestration
/// </summary>
public class OrchestrationResult
{
    public required string OrderId { get; set; }
    public required string Status { get; set; }
    public OrderDetails? OrderDetails { get; set; }
    public CustomerHistory? CustomerHistory { get; set; }
    public DeliveryInfo? DeliveryInfo { get; set; }
    public bool EmailSent { get; set; }
    public bool TeamsMessagePosted { get; set; }
    public List<string> Messages { get; set; } = new();
}
