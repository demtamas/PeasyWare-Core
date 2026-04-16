namespace PeasyWare.Application.Dto;

/// <summary>
/// Inbound line resolved by EAN/GTIN scan or SKU code.
/// Returned when a product barcode (or manual SKU entry) is used during receiving.
/// </summary>
public sealed class InboundLineByEanDto
{
    public int    InboundLineId          { get; init; }
    public int    LineNo                 { get; init; }
    public string SkuCode                { get; init; } = "";
    public string SkuDescription         { get; init; } = "";
    public string Ean                    { get; init; } = "";
    public int    ExpectedQty            { get; init; }
    public int    ReceivedQty            { get; init; }
    public int    OutstandingQty         { get; init; }
    public string ArrivalStockStatusCode { get; init; } = "AV";

    /// <summary>
    /// Whether a batch number is mandatory for this SKU at receiving time.
    /// Driven by inventory.skus.is_batch_required.
    /// </summary>
    public bool IsBatchRequired { get; init; }

    /// <summary>
    /// Standard handling unit quantity from inventory.skus.standard_hu_quantity.
    /// Used as the default receive quantity. NULL if not configured.
    /// </summary>
    public int? StandardHuQuantity { get; init; }

    /// <summary>
    /// How the inbound line was matched — "EAN" or "SKU".
    /// Used in Trace mode to flag label quality issues.
    /// </summary>
    public string MatchedBy { get; init; } = "EAN";
}
