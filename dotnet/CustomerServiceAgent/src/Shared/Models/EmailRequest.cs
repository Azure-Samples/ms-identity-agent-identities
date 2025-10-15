namespace Shared.Models;

/// <summary>
/// Represents an email request
/// </summary>
public class EmailRequest
{
    public required string To { get; set; }
    public required string Subject { get; set; }
    public required string Body { get; set; }
    public string? From { get; set; }
}
