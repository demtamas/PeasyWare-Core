namespace PeasyWare.Application.Scanning;

/// <summary>
/// The parsed result of a GS1-128 barcode scan.
///
/// A single scan may contain one or more Application Identifiers (AIs).
/// All fields are optional — only the AIs present in the scan are populated.
///
/// Supported AIs:
///   00 — SSCC-18 (pallet identifier)
///   01 — GTIN-14 (product identifier)
///   10 — Batch / Lot number
///   15 — Best Before End date (YYMMDD, last day of month)
///   17 — Use By / Expiry date (YYMMDD, exact date)
///   37 — Quantity
/// </summary>
public sealed class GtinScanResult
{
    /// <summary>AI 00 — Serial Shipping Container Code (18 digits)</summary>
    public string? Sscc { get; init; }

    /// <summary>AI 01 — Global Trade Item Number (14 digits)</summary>
    public string? Gtin { get; init; }

    /// <summary>AI 10 — Batch or lot number (variable length, up to 20 chars)</summary>
    public string? Batch { get; init; }

    /// <summary>AI 15 or 17 — Best before / expiry date</summary>
    public DateOnly? BestBefore { get; init; }

    /// <summary>AI 37 — Item quantity (variable length)</summary>
    public int? Quantity { get; init; }

    /// <summary>True if at least one recognised AI was successfully parsed.</summary>
    public bool IsValid { get; init; }

    /// <summary>Populated when IsValid is false or a parsing error occurred.</summary>
    public string? ErrorReason { get; init; }

    /// <summary>
    /// The original raw string as received from the scanner, before any parsing.
    /// Preserved for diagnostics and troubleshooting — if a scan misparse causes
    /// a receiving error, this field allows the exact scanner output to be replayed.
    /// </summary>
    public string? RawScan { get; init; }

    // --------------------------------------------------
    // Convenience
    // --------------------------------------------------

    /// <summary>True if this scan identifies a specific pallet (has SSCC).</summary>
    public bool IsPalletScan => Sscc is not null;

    /// <summary>True if this scan identifies a product (has GTIN).</summary>
    public bool IsProductScan => Gtin is not null;

    // --------------------------------------------------
    // Factory helpers
    // --------------------------------------------------

    internal static GtinScanResult Invalid(string reason, string? rawScan = null) => new()
    {
        IsValid     = false,
        ErrorReason = reason,
        RawScan     = rawScan
    };

    internal static GtinScanResult Empty(string? rawScan = null) => new()
    {
        IsValid     = false,
        ErrorReason = "No recognised Application Identifiers found in scan.",
        RawScan     = rawScan
    };
}
