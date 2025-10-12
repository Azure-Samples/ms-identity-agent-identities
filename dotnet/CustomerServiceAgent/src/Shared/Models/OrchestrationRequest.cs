namespace Shared.Models;

/// <summary>
/// Request to orchestrate a customer service scenario
/// </summary>
public class OrchestrationRequest
{
    public required string OrderId { get; set; }
    public string? UserUpn { get; set; }
}
