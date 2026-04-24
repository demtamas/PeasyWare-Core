namespace PeasyWare.Application;

public sealed class OperationResult
{
    public bool    Success        { get; }
    public string  ResultCode     { get; }
    public string  FriendlyMessage { get; }
    public int     EntityId       { get; }
    public int     ParentId       { get; }

    private OperationResult(bool success, string code, string message, int entityId, int parentId)
    {
        Success         = success;
        ResultCode      = code;
        FriendlyMessage = message;
        EntityId        = entityId;
        ParentId        = parentId;
    }

    public static OperationResult Create(
        bool   success,
        string code,
        string message,
        int    entityId = 0,
        int    parentId = 0)
        => new(success, code, message, entityId, parentId);
}