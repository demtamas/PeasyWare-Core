namespace PeasyWare.Application.Dto;

public sealed class BinMoveTaskResult
{
    public bool    Success             { get; init; }
    public string  ResultCode          { get; init; } = string.Empty;
    public string  FriendlyMessage     { get; init; } = string.Empty;
    public int     TaskId              { get; init; }
    public int     InventoryUnitId     { get; init; }
    public string  SourceBinCode       { get; init; } = string.Empty;
    public string  DestinationBinCode  { get; init; } = string.Empty;
}
