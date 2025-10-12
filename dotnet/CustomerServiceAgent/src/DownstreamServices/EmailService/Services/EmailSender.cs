namespace EmailService.Services;

/// <summary>
/// Mock email sender for demo purposes
/// </summary>
public class EmailSender
{
    private readonly ILogger<EmailSender> _logger;

    public EmailSender(ILogger<EmailSender> logger)
    {
        _logger = logger;
    }

    public Task<bool> SendEmailAsync(string to, string subject, string body, string? from = null)
    {
        _logger.LogInformation("MOCK EMAIL SENT:");
        _logger.LogInformation("  From: {From}", from ?? "noreply@customerservice.com");
        _logger.LogInformation("  To: {To}", to);
        _logger.LogInformation("  Subject: {Subject}", subject);
        _logger.LogInformation("  Body: {Body}", body);
        
        // Simulate email sending
        return Task.FromResult(true);
    }
}
