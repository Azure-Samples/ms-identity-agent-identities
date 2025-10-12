using Microsoft.Identity.Abstractions;
using Microsoft.Identity.Web;
using AgentOrchestrator.Services;
using System.Security.Claims;

var builder = WebApplication.CreateBuilder(args);

// Add Aspire service defaults
builder.AddServiceDefaults();

// Add Microsoft Identity Web
// Note: Agent Identities configuration would be added here in production
// builder.Services.AddMicrosoftIdentityWebApiAuthentication(builder.Configuration, "AzureAd")
//     .EnableTokenAcquisitionToCallDownstreamApi()
//     .AddAgentIdentities(builder.Configuration);

// For demo/development, register a mock IAuthorizationHeaderProvider
builder.Services.AddSingleton<IAuthorizationHeaderProvider, MockAuthorizationHeaderProvider>();

// Register orchestration service
builder.Services.AddSingleton<OrchestrationService>();

// Add HTTP client factory
builder.Services.AddHttpClient();

// Add services to the container
builder.Services.AddControllers();
builder.Services.AddOpenApi();

var app = builder.Build();

// Configure the HTTP request pipeline
app.MapDefaultEndpoints();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

app.UseHttpsRedirection();

app.MapControllers();

app.Run();

// Mock implementation for demo purposes
// In production, this would be provided by Microsoft.Identity.Web with Agent Identities configured
public class MockAuthorizationHeaderProvider : IAuthorizationHeaderProvider
{
    private readonly ILogger<MockAuthorizationHeaderProvider> _logger;

    public MockAuthorizationHeaderProvider(ILogger<MockAuthorizationHeaderProvider> logger)
    {
        _logger = logger;
    }

    public Task<string> CreateAuthorizationHeaderForAppAsync(string scopes, AuthorizationHeaderProviderOptions? downstreamApiOptions = null, CancellationToken cancellationToken = default)
    {
        _logger.LogWarning("MOCK: Using mock authorization header for app. Configure Azure AD for production.");
        // Return a mock bearer token
        return Task.FromResult("Bearer MOCK_APP_TOKEN_" + Guid.NewGuid().ToString("N")[..16]);
    }

    public Task<string> CreateAuthorizationHeaderForUserAsync(IEnumerable<string> scopes, AuthorizationHeaderProviderOptions? authorizationHeaderProviderOptions = null, ClaimsPrincipal? claimsPrincipal = null, CancellationToken cancellationToken = default)
    {
        _logger.LogWarning("MOCK: Using mock authorization header for user. Configure Azure AD for production.");
        // Return a mock bearer token
        return Task.FromResult("Bearer MOCK_USER_TOKEN_" + Guid.NewGuid().ToString("N")[..16]);
    }

    public Task<string> CreateAuthorizationHeaderAsync(IEnumerable<string> scopes, AuthorizationHeaderProviderOptions? authorizationHeaderProviderOptions = null, ClaimsPrincipal? claimsPrincipal = null, CancellationToken cancellationToken = default)
    {
        _logger.LogWarning("MOCK: Using mock authorization header. Configure Azure AD for production.");
        // Return a mock bearer token
        return Task.FromResult("Bearer MOCK_TOKEN_" + Guid.NewGuid().ToString("N")[..16]);
    }
}

