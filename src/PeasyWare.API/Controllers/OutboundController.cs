using Microsoft.AspNetCore.Mvc;
using PeasyWare.API.Requests;
using PeasyWare.API.Responses;
using PeasyWare.Application.Dto;
using PeasyWare.Infrastructure.Bootstrap;

namespace PeasyWare.API.Controllers;

[ApiController]
[Route("api/outbound")]
public sealed class OutboundController : ControllerBase
{
    private readonly AppRuntime _runtime;

    public OutboundController(AppRuntime runtime) => _runtime = runtime;

    /// <summary>Creates a new outbound order.</summary>
    [HttpPost("orders")]
    [ProducesResponseType(typeof(ApiResponse<OrderCreatedResponse>), 200)]
    [ProducesResponseType(typeof(ApiResponse),                       409)]
    [ProducesResponseType(typeof(ApiResponse),                       400)]
    public IActionResult CreateOrder([FromBody] CreateOrderRequest request)
    {
        var repo   = _runtime.Repositories.CreateOutboundCommand();
        var result = repo.CreateOrder(
            orderRef:          request.OrderRef,
            customerPartyCode: request.CustomerPartyCode,
            haulierPartyCode:  request.HaulierPartyCode,
            requiredDate:      request.RequiredDate.HasValue
                                   ? request.RequiredDate.Value.ToDateTime(TimeOnly.MinValue)
                                   : null,
            notes:             request.Notes,
            lines:             request.Lines.Select(l => new OrderLineDto
            {
                LineNo         = l.LineNo,
                SkuCode        = l.SkuCode,
                OrderedQty     = l.OrderedQty,
                RequestedBatch = l.RequestedBatch,
                RequestedBbe   = l.RequestedBbe.HasValue
                                     ? l.RequestedBbe.Value.ToDateTime(TimeOnly.MinValue)
                                     : null,
                Notes          = l.Notes
            }).ToList());

        if (!result.Success)
        {
            var status = result.ResultCode == "ERRORD02" ? 409 : 400;
            return StatusCode(status, ApiResponse.Fail(result.ResultCode, result.FriendlyMessage));
        }

        return Ok(ApiResponse<OrderCreatedResponse>.Ok(
            result.ResultCode,
            result.FriendlyMessage,
            new OrderCreatedResponse
            {
                OutboundOrderId = result.EntityId,
                OrderRef        = request.OrderRef
            }));
    }

    /// <summary>Creates a new shipment.</summary>
    [HttpPost("shipments")]
    [ProducesResponseType(typeof(ApiResponse<ShipmentCreatedResponse>), 200)]
    [ProducesResponseType(typeof(ApiResponse),                          409)]
    [ProducesResponseType(typeof(ApiResponse),                          400)]
    public IActionResult CreateShipment([FromBody] CreateShipmentRequest request)
    {
        var repo   = _runtime.Repositories.CreateOutboundCommand();
        var result = repo.CreateShipment(
            shipmentRef:      request.ShipmentRef,
            haulierPartyCode: request.HaulierPartyCode,
            vehicleRef:       request.VehicleRef,
            plannedDeparture: request.PlannedDeparture,
            notes:            request.Notes);

        if (!result.Success)
        {
            var status = result.ResultCode == "ERRSHIP02" ? 409 : 400;
            return StatusCode(status, ApiResponse.Fail(result.ResultCode, result.FriendlyMessage));
        }

        return Ok(ApiResponse<ShipmentCreatedResponse>.Ok(
            result.ResultCode,
            result.FriendlyMessage,
            new ShipmentCreatedResponse
            {
                ShipmentId  = result.EntityId,
                ShipmentRef = request.ShipmentRef
            }));
    }

    /// <summary>Adds an order to an existing shipment.</summary>
    [HttpPost("shipments/{shipmentRef}/orders")]
    [ProducesResponseType(typeof(ApiResponse), 200)]
    [ProducesResponseType(typeof(ApiResponse), 404)]
    [ProducesResponseType(typeof(ApiResponse), 400)]
    public IActionResult AddOrderToShipment(
        string shipmentRef,
        [FromBody] AddOrderToShipmentRequest request)
    {
        var repo   = _runtime.Repositories.CreateOutboundCommand();
        var result = repo.AddOrderToShipment(
            shipmentRef: shipmentRef,
            orderRef:    request.OrderRef);

        if (!result.Success)
        {
            var status = result.ResultCode is "ERRSHIP03" or "ERRORD03" ? 404 : 400;
            return StatusCode(status, ApiResponse.Fail(result.ResultCode, result.FriendlyMessage));
        }

        return Ok(ApiResponse.FromResult(result));
    }
}
