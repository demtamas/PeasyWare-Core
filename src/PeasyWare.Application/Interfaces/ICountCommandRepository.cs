using PeasyWare.Application.Dto;

namespace PeasyWare.Application.Interfaces;

public interface ICountCommandRepository
{
    // ──────────────────────────────────────────────────────
    // Empty-bin check
    // ──────────────────────────────────────────────────────

    /// <summary>Starts an empty-bin count for a storage type, or resumes the open one.</summary>
    CountStartResult StartEmptyBinCount(string storageTypeCode);

    /// <summary>The operator scanned a bin from the count and it is empty.</summary>
    CountBinResult   ConfirmEmpty(int countId, string binCode);

    /// <summary>The operator found a pallet in a bin the system believed was empty.</summary>
    CountStockResult ReportStock(int countId, string binCode, string scannedRef);

    // ──────────────────────────────────────────────────────
    // Bin count (blind)
    // ──────────────────────────────────────────────────────

    /// <summary>
    /// Starts a bin count - a blind count of the bins that hold stock - or resumes
    /// the open one of the same scope. A null / blank storage type is a sweep: every
    /// storage type. A sweep and a single-storage-type count cannot be open together.
    /// </summary>
    CountStartResult StartBinCount(string? storageTypeCode);

    /// <summary>
    /// Starts an AD HOC bin count: a count of a hand-picked list of bins. Any active
    /// bin may be named, empty or occupied. Nothing is started unless every bin is
    /// valid (the first that is not comes back in InvalidBinCode). Every call starts a
    /// new count; ad hoc counts never conflict with a sweep or a storage-type count.
    /// </summary>
    CountStartResult StartAdHocCount(IReadOnlyCollection<string> binCodes);

    /// <summary>
    /// The operator scanned a bin's label and is about to count it. The bin is held
    /// (nothing can be put into it or taken out) until it is finished or cancelled.
    /// Opening a bin that is already open resumes it, keeping the scans so far.
    /// </summary>
    BinCountOpenResult OpenBin(int countId, string binCode);

    /// <summary>
    /// One pallet counted in an open bin: its SSCC and the quantity counted. Blind -
    /// nothing comes back about what the system holds. If the pallet is recorded in
    /// this bin and the quantity differs, nothing is recorded and NeedsConfirmation
    /// is true: ask the operator, then call again with confirmDifference = true.
    /// Scanning the same SSCC again replaces the earlier quantity.
    /// </summary>
    BinCountScanResult ScanUnit(
        int    countId,
        string binCode,
        string scannedRef,
        int    countedQty,
        bool   confirmDifference = false);

    /// <summary>
    /// The operator has scanned everything in the bin. Compares it with the system
    /// and records every difference as a finding; changes no stock record. If the
    /// bin changed while it was being counted (the movement ledger shows it), nothing
    /// is recorded and RecountRequired is true.
    /// </summary>
    BinCountFinishResult FinishBin(int countId, string binCode);

    /// <summary>Abandons the open bin: scans discarded, hold released, back to pending.</summary>
    CountBinResult CancelBin(int countId, string binCode);

    // ──────────────────────────────────────────────────────
    // Closing and review (both kinds of count)
    // ──────────────────────────────────────────────────────

    /// <summary>
    /// Closes an open count: REVIEW if it found something a person has to deal
    /// with, otherwise COMPLETE (nothing pending) or CLOSED (bins left uncounted).
    /// Refused while a bin of a bin count is still open.
    /// </summary>
    CountCloseResult Close(int countId);

    /// <summary>
    /// Applies one finding of a bin count in REVIEW: the stock record is changed to
    /// match the count (quantity set, pallet written off, or pallet relocated) and
    /// the ledger row that did it is recorded on the finding. Needs counts.adjust.
    /// Re-checks the stock first; a refusal changes nothing.
    /// </summary>
    CountApplyResult ApplyFinding(int findingId);

    /// <summary>
    /// Declines one finding: the records are left as they are. A note saying why is
    /// required. Needs counts.adjust. Also how an unknown or shipped pallet's finding
    /// is acknowledged.
    /// </summary>
    CountApplyResult DeclineFinding(int findingId, string note);

    /// <summary>
    /// Marks a count in REVIEW as reviewed, with a note saying what was done about
    /// its findings. Needs the counts.review permission; a note is required. For a
    /// bin count, every quantity / missing / misplaced finding must be decided first.
    /// </summary>
    CountReviewResult Review(int countId, string note);
}
