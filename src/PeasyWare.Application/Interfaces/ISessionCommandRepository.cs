using System;

namespace PeasyWare.Application.Interfaces;

public interface ISessionCommandRepository
{
    SessionTouchResult TouchSession(
        Guid sessionId,
        string sourceApp,
        string sourceClient,
        string? sourceIp = null);

    OperationResult LogoutSession(
        Guid sessionId,
        string sourceApp,
        string sourceClient,
        string? sourceIp = null);
}