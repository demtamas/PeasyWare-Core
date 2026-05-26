namespace PeasyWare.Application.Dto;

public sealed class UserActivityDto
{
    public long      EventId          { get; init; }
    public DateTime  OccurredAt       { get; init; }
    public string    Source           { get; init; } = string.Empty;  // TRIGGER / TRACE
    public string    EventType        { get; init; } = string.Empty;
    public int?      SubjectUserId    { get; init; }
    public string?   SubjectUsername  { get; init; }
    public int?      ActorUserId      { get; init; }
    public string?   ActorUsername    { get; init; }
    public string?   Detail           { get; init; }
    public string?   ResultCode       { get; init; }
    public string?   SourceApp        { get; init; }
}
