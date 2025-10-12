var builder = DistributedApplication.CreateBuilder(args);

// Add downstream services
var orderService = builder.AddProject("orderservice", "../DownstreamServices/OrderService/OrderService.csproj")
    .WithHttpsEndpoint(port: 7001, name: "https");

var crmService = builder.AddProject("crmservice", "../DownstreamServices/CrmService/CrmService.csproj")
    .WithHttpsEndpoint(port: 7002, name: "https");

var shippingService = builder.AddProject("shippingservice", "../DownstreamServices/ShippingService/ShippingService.csproj")
    .WithHttpsEndpoint(port: 7003, name: "https");

var emailService = builder.AddProject("emailservice", "../DownstreamServices/EmailService/EmailService.csproj")
    .WithHttpsEndpoint(port: 7004, name: "https");

// Add orchestrator service with references to all downstream services
var orchestrator = builder.AddProject("agentorchestrator", "../AgentOrchestrator/AgentOrchestrator.csproj")
    .WithHttpsEndpoint(port: 7000, name: "https")
    .WithReference(orderService)
    .WithReference(crmService)
    .WithReference(shippingService)
    .WithReference(emailService);

builder.Build().Run();
