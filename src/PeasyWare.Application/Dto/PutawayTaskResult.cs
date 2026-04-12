namespace PeasyWare.Application.Dto;

public sealed class PutawayTaskResult
{
    public bool Success { get; init; }

    public string ResultCode { get; init; } = string.Empty;

    public string FriendlyMessage { get; init; } = string.Empty;

    public int TaskId { get; init; }

    public string DestinationBinCode { get; init; } = string.Empty;
}