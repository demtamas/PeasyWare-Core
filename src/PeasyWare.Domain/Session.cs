namespace PeasyWare.Domain;

public sealed class Session
{
    public Guid Id { get; }
    public int UserId { get; }
    public DateTime StartedAtUtc { get; }
    public bool IsActive { get; private set; }

    public Session(Guid id, int userId, DateTime startedAtUtc)
    {
        Id = id;
        UserId = userId;
        StartedAtUtc = startedAtUtc;
        IsActive = true;
    }

    public void Touch()
    {
        if (!IsActive)
            throw new InvalidOperationException("Cannot touch inactive session.");
    }

    public void Deactivate()
    {
        IsActive = false;
    }
}
