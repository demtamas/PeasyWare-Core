namespace PeasyWare.Application.Interfaces;

public interface ISkuCommandRepository
{
    OperationResult CreateSku(
        string   skuCode,
        string   skuDescription,
        string?  ean                = null,
        string   uomCode            = "Each",
        decimal? weightPerUnit      = null,
        int      standardHuQuantity = 0,
        bool     isHazardous        = false);
}
