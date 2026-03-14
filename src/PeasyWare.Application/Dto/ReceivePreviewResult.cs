namespace PeasyWare.Application.Dto;

public sealed record ReceivePreviewResult
(
    bool Success,
    string ResultCode,

    int? InboundExpectedUnitId,   // ✅ NEW

    int? InboundLineId,
    string? InboundRef,
    string? HeaderStatus,
    string? LineState,

    string? SkuCode,
    string? SkuDescription,

    int? ExpectedUnitQty,
    int? LineExpectedQty,
    int? LineReceivedQty,

    int? OutstandingBefore,
    int? OutstandingAfter,

    string? BatchNumber,
    DateTime? BestBeforeDate,

    Guid? ClaimToken,
    DateTime? ClaimExpiresAt
);