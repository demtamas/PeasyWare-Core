using System;
using System.Collections.Generic;
using System.Text;

namespace PeasyWare.Application.Dto
{
    public sealed class SessionDetailsDto
    {
        public Guid SessionId { get; init; }
        public bool IsActive { get; init; }
        public DateTime LoginTime { get; init; }
        public DateTime LastSeen { get; init; }

        public int UserId { get; init; }
        public string Username { get; init; } = "";
        public string DisplayName { get; init; } = "";

        public string? ClientApp { get; init; }
        public string? ClientInfo { get; init; }
        public string? IpAddress { get; init; }
        public string? OsInfo { get; init; }
        public Guid? CorrelationId { get; init; }
    }
}
