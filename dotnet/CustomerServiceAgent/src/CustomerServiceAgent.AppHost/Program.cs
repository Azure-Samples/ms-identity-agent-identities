var builder = DistributedApplication.CreateBuilder(args);

// Add downstream services
var orderService = builder.AddProject("orderservice", "../DownstreamServices/OrderService/OrderService.csproj");

var crmService = builder.AddProject("crmservice", "../DownstreamServices/CrmService/CrmService.csproj");

var shippingService = builder.AddProject("shippingservice", "../DownstreamServices/ShippingService/ShippingService.csproj");

var emailService = builder.AddProject("emailservice", "../DownstreamServices/EmailService/EmailService.csproj");

// Add orchestrator service with references to all downstream services
var orchestrator = builder.AddProject("agentorchestrator", "../AgentOrchestrator/AgentOrchestrator.csproj")
    .WithReference(orderService)
    .WithReference(crmService)
    .WithReference(shippingService)
    .WithReference(emailService);

builder.Build().Run();
