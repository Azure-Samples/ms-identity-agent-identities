using AgentOrchestrator.Services;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Identity.Abstractions;
using Microsoft.Identity.Web;

var builder = WebApplication.CreateBuilder(args);

// Add Aspire service defaults
builder.AddServiceDefaults();

// Add Microsoft Identity Web with agent identities support
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddMicrosoftIdentityWebApi(builder.Configuration, "AzureAd")
        .EnableTokenAcquisitionToCallDownstreamApi()
        .AddInMemoryTokenCaches();

builder.Services.AddAgentIdentities();
builder.Services.AddDownstreamApis(builder.Configuration.GetSection("DownstreamApis"));

/*
 	"msGraphAgentIdentity": {
			"BaseUrl": "https://graph.microsoft.com",
			"RelativePath": "/beta/serviceprincipals/Microsoft.Graph.AgentIdentity",
			"Scopes": [ "00000003-0000-0000-c000-000000000000/.default" ],
			"RequestAppToken": true,
			"ExtraHeaderParameters ": {
				"OData-Version": "4.0"
			}
 */
builder.Services.Configure<DownstreamApiOptions>("msGraphAgentIdentity", options =>
{
	options.BaseUrl = "https://graph.microsoft.com";
	options.RelativePath = "/beta/serviceprincipals/Microsoft.Graph.AgentIdentity";
	options.Scopes = [ "00000003-0000-0000-c000-000000000000/.default" ];
	options.RequestAppToken = true;
	options.ExtraHeaderParameters = new Dictionary<string, string>
	{
		{ "OData-Version", "4.0" }
	};
});

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

app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();

app.Run();

