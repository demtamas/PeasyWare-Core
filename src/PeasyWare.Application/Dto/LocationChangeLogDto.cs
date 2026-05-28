namespace PeasyWare.Application.Dto;

public sealed class LocationChangeLogDto
{
    public long      TraceId        { get; init; }
    public DateTime  OccurredAt     { get; init; }
    public string?   Username       { get; init; }
    public string    ActionType     { get; init; } = null!; // CREATE / UPDATE / LOCK / UNLOCK / DEACTIVATE / REACTIVATE
    public string?   BinCode        { get; init; }
    public string?   Reason         { get; init; }

    // Before (UPDATE only)
    public string?   BinCodeBefore    { get; init; }
    public string?   TypeBefore       { get; init; }
    public string?   SectionBefore    { get; init; }
    public string?   ZoneBefore       { get; init; }
    public int?      CapacityBefore   { get; init; }
    public bool?     ActiveBefore     { get; init; }
    public bool?     LockedBefore     { get; init; }
    public string?   NotesBefore      { get; init; }

    // After (UPDATE only)
    public string?   BinCodeAfter     { get; init; }
    public string?   TypeAfter        { get; init; }
    public string?   SectionAfter     { get; init; }
    public string?   ZoneAfter        { get; init; }
    public int?      CapacityAfter    { get; init; }
    public string?   NotesAfter       { get; init; }
}
