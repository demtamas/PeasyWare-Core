using PeasyWare.Application.Contexts;

namespace PeasyWare.Application.Interfaces;

public interface ILogger
{
    void SetSession(SessionContext session);

    void Info(string action, object? data);
    void Warn(string action, object? data);
    void Error(string action, object? data);
    void Error(string action, object? data, Exception ex);
}