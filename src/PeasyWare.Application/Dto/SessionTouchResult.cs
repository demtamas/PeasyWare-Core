using System;
using System.Collections.Generic;
using System.Text;

namespace PeasyWare.Application.Dto
{
    public sealed class SessionTouchResult
    {
        public bool IsAlive { get; set; }

        public string ResultCode { get; set; } = "";

        public string? FriendlyMessage { get; set; }
    }
}
