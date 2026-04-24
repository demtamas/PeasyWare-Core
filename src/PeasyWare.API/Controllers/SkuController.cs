using Microsoft.AspNetCore.Mvc;
using PeasyWare.API.Requests;
using PeasyWare.API.Responses;
using PeasyWare.Infrastructure.Bootstrap;

namespace PeasyWare.API.Controllers;

[ApiController]
[Route("api/skus")]
public sealed class SkuController : ControllerBase
{
    private readonly AppRuntime _runtime;

    public SkuController(AppRuntime runtime) => _runtime = runtime;

    /// <summary>Creates a new SKU.</summary>
    [HttpPost]
    [ProducesResponseType(typeof(ApiResponse<SkuResponse>), 200)]
    [ProducesResponseType(typeof(ApiResponse),              409)]
    [ProducesResponseType(typeof(ApiResponse),              400)]
    public IActionResult Create([FromBody] CreateSkuRequest request)
    {
        var repo   = _runtime.Repositories.CreateSkuCommand();
        var result = repo.CreateSku(
            skuCode:            request.SkuCode,
            skuDescription:     request.SkuDescription,
            ean:                request.Ean,
            uomCode:            request.UomCode,
            weightPerUnit:      request.WeightPerUnit,
            standardHuQuantity: request.StandardHuQuantity,
            isHazardous:        request.IsHazardous);

        if (!result.Success)
        {
            var status = result.ResultCode == "ERRSKU02" ? 409 : 400;
            return StatusCode(status, ApiResponse.Fail(result.ResultCode, result.FriendlyMessage));
        }

        var sku = _runtime.Repositories.CreateSkuQuery().GetByCode(request.SkuCode);

        return Ok(ApiResponse<SkuResponse>.Ok(
            result.ResultCode,
            result.FriendlyMessage,
            new SkuResponse
            {
                SkuId              = sku!.SkuId,
                SkuCode            = sku.SkuCode,
                SkuDescription     = sku.SkuDescription,
                Ean                = sku.Ean,
                UomCode            = sku.UomCode,
                WeightPerUnit      = sku.WeightPerUnit,
                StandardHuQuantity = sku.StandardHuQuantity,
                IsHazardous        = sku.IsHazardous,
                IsActive           = sku.IsActive
            }));
    }

    /// <summary>Returns a SKU by code.</summary>
    [HttpGet("{skuCode}")]
    [ProducesResponseType(typeof(ApiResponse<SkuResponse>), 200)]
    [ProducesResponseType(typeof(ApiResponse),              404)]
    public IActionResult GetByCode(string skuCode)
    {
        var sku = _runtime.Repositories.CreateSkuQuery().GetByCode(skuCode);

        if (sku is null)
            return NotFound(ApiResponse.Fail("ERRSKU01", $"SKU '{skuCode}' not found."));

        return Ok(ApiResponse<SkuResponse>.Ok("SUCSKU00", "OK", new SkuResponse
        {
            SkuId              = sku.SkuId,
            SkuCode            = sku.SkuCode,
            SkuDescription     = sku.SkuDescription,
            Ean                = sku.Ean,
            UomCode            = sku.UomCode,
            WeightPerUnit      = sku.WeightPerUnit,
            StandardHuQuantity = sku.StandardHuQuantity,
            IsHazardous        = sku.IsHazardous,
            IsActive           = sku.IsActive
        }));
    }
}
