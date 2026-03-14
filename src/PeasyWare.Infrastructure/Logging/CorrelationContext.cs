using System.Threading;

namespace PeasyWare.Infrastructure.Logging;

/// <summary>
/// Holds the current correlation ID for the active execution context.
/// Uses AsyncLocal to flow correctly across async boundaries.
/// </summary>
public static class CorrelationContext
{
    private static readonly AsyncLocal<Guid?> _current = new();

    /// <summary>
    /// Gets the current correlation ID, or null if none is set.
    /// </summary>
    public static Guid? Current => _current.Value;

    /// <summary>
    /// Sets the correlation ID for the current execution context.
    /// </summary>
    public static void Set(Guid correlationId)
    {
        _current.Value = correlationId;
    }

    /// <summary>
    /// Clears the correlation ID from the current execution context.
    /// </summary>
    public static void Clear()
    {
        _current.Value = null;
    }
}
