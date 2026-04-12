using System;

namespace PeasyWare.Application.Security;

public sealed class SessionExpiredException : Exception
{
    public SessionExpiredException(string message)
        : base(message)
    {
    }
}