namespace PeasyWare.Application.Dto;

public sealed class PutawayTaskResult
{
    public bool Success { get; init; }
    public string ResultCode { get; init; } = string.Empty;
    public string FriendlyMessage { get; init; } = string.Empty;
    public int TaskId { get; init; }
    public string DestinationBinCode { get; init; } = string.Empty;

    // TRACE fields
    public int InventoryUnitId { get; init; }
    public string SourceBinCode { get; init; } = string.Empty;
    public string StockStateCode { get; init; } = string.Empty;
    public string StockStatusCode { get; init; } = string.Empty;
    public DateTime? ExpiresAt { get; init; }
    public string? ZoneCode { get; init; }
}