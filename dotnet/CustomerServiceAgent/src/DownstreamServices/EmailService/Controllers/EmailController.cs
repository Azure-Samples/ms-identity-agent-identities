using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Identity.Web.Resource;
using EmailService.Services;
using Shared.Models;

namespace EmailService.Controllers;

/// <summary>
/// Email API controller - mock email sending
/// </summary>
// [Authorize] // Commented for demo - enable for production with Azure AD
[ApiController]
[Route("api/[controller]")]
// [RequiredScope("Email.Send")]
public class EmailController : ControllerBase
{
    private readonly EmailSender _emailSender;
    private readonly ILogger<EmailController> _logger;

    public EmailController(EmailSender emailSender, ILogger<EmailController> logger)
    {
        _emailSender = emailSender;
        _logger = logger;
    }

    /// <summary>
    /// Send email (mock)
    /// </summary>
    [HttpPost("send")]
    public async Task<ActionResult> SendEmail([FromBody] EmailRequest request)
    {
        _logger.LogInformation("Sending email to {To} by user {User}", 
            request.To, User.Identity?.Name ?? "Unknown");

        var success = await _emailSender.SendEmailAsync(
            request.To, 
            request.Subject, 
            request.Body, 
            request.From);

        if (success)
        {
            _logger.LogInformation("Email sent successfully to {To}", request.To);
            return Ok(new { message = "Email sent successfully (mock)", recipient = request.To });
        }

        _logger.LogError("Failed to send email to {To}", request.To);
        return StatusCode(500, new { message = "Failed to send email" });
    }
}
