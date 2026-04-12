using PeasyWare.Application.Contexts;
using PeasyWare.Application.Interfaces;

namespace PeasyWare.Application.Logging;

public sealed class NoOpLogger : ILogger
{
    public void SetSession(SessionContext session)
    {
        // intentionally do nothing
    }

    public void Info(string message) { }
    public void Info(string message, object? data) { }

    public void Warn(string message) { }
    public void Warn(string message, object? data) { }

    public void Error(string message) { }
    public void Error(string message, object? data) { }

    public void Error(string message, Exception exception) { }

    public void Error(string message, Exception exception, object? data) { }
}