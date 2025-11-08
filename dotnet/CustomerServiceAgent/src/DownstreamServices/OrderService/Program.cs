using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.Identity.Web;
using OrderService.Services;

var builder = WebApplication.CreateBuilder(args);

// Add Aspire service defaults
builder.AddServiceDefaults();

// Add Microsoft Identity Web for token validation
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddMicrosoftIdentityWebApi(builder.Configuration, "AzureAd");

// Add authorization policies
builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("Orders.Read.Any", policy =>
        policy.RequireAssertion(ctx =>
            ctx.User.HasClaim(c => c.Type == "scp" && c.Value.Split(' ').Contains("Orders.Read")) ||
            ctx.User.HasClaim(c => c.Type == "roles" && c.Value.Split(' ').Contains("Orders.Read.All"))
        )
    );
});

// Add in-memory order store
builder.Services.AddSingleton<OrderStore>();

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
