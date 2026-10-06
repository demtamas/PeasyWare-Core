using PeasyWare.Application.Dto;

namespace PeasyWare.Application.Interfaces;

public interface ICountCommandRepository
{
    /// <summary>Starts an empty-bin count for a storage type, or resumes the open one.</summary>
    CountStartResult StartEmptyBinCount(string storageTypeCode);

    /// <summary>The operator scanned a bin from the count and it is empty.</summary>
    CountBinResult   ConfirmEmpty(int countId, string binCode);

    /// <summary>The operator found a pallet in a bin the system believed was empty.</summary>
    CountStockResult ReportStock(int countId, string binCode, string scannedRef);

    /// <summary>
    /// Closes an open count: REVIEW if it found something a person has to deal
    /// with, otherwise COMPLETE (nothing pending) or CLOSED (bins left uncounted).
    /// </summary>
    CountCloseResult Close(int countId);

    /// <summary>
    /// Marks a count in REVIEW as reviewed, with a note saying what was done about
    /// its findings. Needs the counts.review permission; a note is required.
    /// </summary>
    CountReviewResult Review(int countId, string note);
}
