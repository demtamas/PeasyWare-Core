using PeasyWare.Application.Contexts;
using PeasyWare.Application.Interfaces;

namespace PeasyWare.Application.Logging;

public sealed class NoOpLogger : ILogger
{
    public void SetSession(SessionContext session) { }

    public void Info(string action, object? data)  { }
    public void Warn(string action, object? data)  { }
    public void Error(string action, object? data) { }
    public void Error(string action, object? data, Exception ex) { }
}
