namespace PeasyWare.Application.Dto;

public sealed class PutawayTaskCreateResult
{
    public bool Success { get; set; }

    public string ResultCode { get; set; } = "";

    public string FriendlyMessage { get; set; } = "";

    public int TaskId { get; set; }

    public string DestinationBinCode { get; set; } = "";
}