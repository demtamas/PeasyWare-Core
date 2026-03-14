namespace PeasyWare.Application.Interfaces;

public interface ILogger
{
    void Info(string message);
    void Info(string message, object data);

    void Warn(string message);
    void Warn(string message, object data);

    void Error(string message);
    void Error(string message, object data);
    void Error(string message, Exception exception);
    void Error(string message, Exception exception, object data);
}