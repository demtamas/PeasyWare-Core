namespace PeasyWare.Application.Interfaces;

public interface ISkuCommandRepository
{
    OperationResult CreateSku(
        string   skuCode,
        string   skuDescription,
        string?  ean                        = null,
        string   uomCode                    = "Each",
        decimal? weightPerUnit              = null,
        int      standardHuQuantity         = 0,
        bool     isHazardous                = false,
        bool     isBatchRequired            = false,
        bool     isFullHuRequired           = false,
        string?  preferredStorageTypeCode   = null,
        string?  preferredSectionCode       = null);

    OperationResult UpdateSku(
        string   skuCode,
        string   skuDescription,
        string?  ean                        = null,
        string   uomCode                    = "Each",
        decimal? weightPerUnit              = null,
        int      standardHuQuantity         = 0,
        bool     isHazardous                = false,
        bool     isBatchRequired            = false,
        bool     isFullHuRequired           = false,
        bool     isActive                   = true,
        string?  preferredStorageTypeCode   = null,
        string?  preferredSectionCode       = null);
}
