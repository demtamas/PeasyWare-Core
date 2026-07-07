namespace PeasyWare.Application.Dto;

public sealed class ClientDto
{
    public string   ClientName             { get; init; } = null!;
    public int?     SessionTimeoutMinutes  { get; init; }
    public int?     MaxConcurrentSessions  { get; init; }
    public bool     IsActive               { get; init; }
    public string?  Description            { get; init; }
    public DateTime CreatedAt              { get; init; }
    public string?  CreatedByUsername      { get; init; }
}
