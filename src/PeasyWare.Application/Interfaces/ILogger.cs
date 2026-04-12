using PeasyWare.Application.Contexts;

namespace PeasyWare.Application.Interfaces;

public interface ILogger
{
    void SetSession(SessionContext session);

    void Info(string message);
    void Warn(string message);
    void Error(string message);
    void Error(string message, Exception ex);
    void Error(string message, Exception ex, object context);

    void Info(string action, object? data);
    void Warn(string action, object? data);
    void Error(string action, object? data);
}