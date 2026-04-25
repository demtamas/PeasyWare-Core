namespace PeasyWare.Application.Scanning;

/// <summary>
/// Canonical forms for warehouse identifiers.
///
/// These methods declare data policy explicitly rather than
/// scattering normalisation decisions across UI helpers and
/// controllers. Every entry point that accepts a batch number,
/// SSCC, or bin code from an operator or external system should
/// call the appropriate method here before passing the value
/// downstream.
///
/// BATCH NUMBER POLICY:
///   Batch numbers are treated as case-insensitive identifiers.
///   They are normalised to uppercase on entry. This aligns with
///   GS1 AI-10 practice (uppercase alphanumeric), SAP batch storage,
///   and real-world label formats (Britvic, etc.).
///
///   If a future supplier uses meaningful lowercase in batch numbers,
///   this policy must be revisited here — not worked around at call sites.
///
/// BIN CODE POLICY:
///   Bin codes are uppercase (RACK01, BAY02, etc.).
///   Normalised to uppercase on entry to tolerate operator input casing.
///
/// SSCC POLICY:
///   See GtinParser for SSCC normalisation (18-digit canonical, no AI prefix).
/// </summary>
public static class IdentifierPolicy
{
    /// <summary>
    /// Normalises a batch number to canonical form.
    /// Returns null if input is null or whitespace.
    /// </summary>
    public static string? NormaliseBatch(string? input)
    {
        if (string.IsNullOrWhiteSpace(input))
            return null;

        return input.Trim().ToUpperInvariant();
    }

    /// <summary>
    /// Normalises a bin code to canonical form.
    /// Returns null if input is null or whitespace.
    /// </summary>
    public static string? NormaliseBinCode(string? input)
    {
        if (string.IsNullOrWhiteSpace(input))
            return null;

        return input.Trim().ToUpperInvariant();
    }
}
