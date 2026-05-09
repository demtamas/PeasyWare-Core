namespace PeasyWare.Application.Scanning;

/// <summary>
/// The parsed result of a GS1-128 barcode scan.
///
/// A single scan may contain one or more Application Identifiers (AIs).
/// All fields are optional — only the AIs present in the scan are populated.
///
/// Supported AIs:
///   00 — SSCC-18 (pallet identifier)
///   01 — GTIN-14 (product identifier, the pallet's own GTIN)
///   02 — GTIN-14 (GTIN of contained trade items — used on pallet labels
///                  like Ardagh where the pallet GTIN differs from the item GTIN)
///   10 — Batch / Lot number
///   11 — Production date (YYMMDD)
///   15 — Best Before End date (YYMMDD)
///   17 — Use By / Expiry date (YYMMDD)
///   21 — Serial number (variable length, up to 20 chars)
///   37 — Quantity of contained items
/// </summary>
public sealed class GtinScanResult
{
    /// <summary>AI 00 — Serial Shipping Container Code (18 digits)</summary>
    public string? Sscc { get; init; }

    /// <summary>AI 01 — GTIN-14 of the pallet / shipping unit itself</summary>
    public string? Gtin { get; init; }

    /// <summary>
    /// AI 02 — GTIN-14 of the contained trade items.
    /// Present on pallet labels where the pallet's GTIN (AI 01) differs from
    /// the item GTIN (AI 02). Common on supplier labels (e.g. Ardagh Group).
    /// Use this as the product identifier when AI 01 is absent.
    /// </summary>
    public string? ContainedGtin { get; init; }

    /// <summary>AI 10 — Batch or lot number (variable length, up to 20 chars)</summary>
    public string? Batch { get; init; }

    /// <summary>AI 11 — Production date</summary>
    public DateOnly? ProductionDate { get; init; }

    /// <summary>AI 15 or 17 — Best before / expiry date</summary>
    public DateOnly? BestBefore { get; init; }

    /// <summary>
    /// AI 21 — Serial number (variable length, up to 20 chars).
    /// Distinct from batch number — identifies a specific unit rather than a lot.
    /// On Ardagh labels this is the Customer Ref / production run number.
    /// </summary>
    public string? SerialNumber { get; init; }

    /// <summary>AI 37 — Count of contained trade items</summary>
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

    /// <summary>
    /// True if this scan identifies a product by GTIN.
    /// Checks both AI 01 (pallet GTIN) and AI 02 (contained item GTIN).
    /// </summary>
    public bool IsProductScan => Gtin is not null || ContainedGtin is not null;

    /// <summary>
    /// The best available product GTIN from this scan.
    /// Prefers AI 01 (direct GTIN) over AI 02 (contained GTIN).
    /// </summary>
    public string? EffectiveGtin => Gtin ?? ContainedGtin;

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
