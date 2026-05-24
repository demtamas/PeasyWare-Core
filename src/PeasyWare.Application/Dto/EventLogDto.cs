namespace PeasyWare.Application.Dto;

public sealed class EventLogDto
{
    public long      TraceId        { get; init; }
    public DateTime  OccurredAt     { get; init; }
    public string    Level          { get; init; } = string.Empty;
    public string    Action         { get; init; } = string.Empty;
    public int?      UserId         { get; init; }
    public string?   Username       { get; init; }
    public string?   SourceApp      { get; init; }
    public string?   SourceClient   { get; init; }
    public string?   ResultCode     { get; init; }
    public string?   Success        { get; init; }
    public string?   PayloadJson    { get; init; }
}
