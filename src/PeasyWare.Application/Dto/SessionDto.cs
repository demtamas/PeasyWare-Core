using System;
using System.Collections.Generic;
using System.Text;

namespace PeasyWare.Application.DTOs;

public sealed class ActiveSessionDto
{
    public Guid SessionId { get; init; }
    public string Username { get; init; } = null!;
    public string ClientApp { get; init; } = null!;
    public string ClientInfo { get; init; } = null!;
    public DateTime LastSeen { get; init; }
    public bool IsActive { get; init; }
}

