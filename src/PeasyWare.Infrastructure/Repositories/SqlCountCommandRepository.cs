using Microsoft.Data.SqlClient;
using PeasyWare.Application;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Application.Security;
using PeasyWare.Infrastructure.Sql;
using System;
using System.Collections.Generic;
using System.Data;
using System.Linq;

namespace PeasyWare.Infrastructure.Repositories;

/// <summary>
/// Command repository for stock counting: the empty-bin check and the bin count.
///
/// Each method calls one stored procedure that always returns exactly one
/// row. Rich-DTO results mean each method does its own logging: the
/// outcome carries the detail that makes the trace log useful afterwards
/// (which bin, which pallet, what was done, what stopped it).
/// </summary>
public sealed class SqlCountCommandRepository
    : RepositoryBase, ICountCommandRepository
{
    private readonly SqlConnectionFactory  _factory;
    private readonly SessionContext        _session;
    private readonly IErrorMessageResolver _resolver;
    private readonly ILogger               _logger;

    public SqlCountCommandRepository(
        SqlConnectionFactory  factory,
        SessionContext        session,
        IErrorMessageResolver resolver,
        ILogger               logger,
        SessionGuard          sessionGuard)
        : base(sessionGuard, session, resolver, logger)
    {
        _factory  = factory  ?? throw new ArgumentNullException(nameof(factory));
        _session  = session  ?? throw new ArgumentNullException(nameof(session));
        _resolver = resolver ?? throw new ArgumentNullException(nameof(resolver));
        _logger   = logger   ?? throw new ArgumentNullException(nameof(logger));
    }

    // ════════════════════════════════════════════════════════
    // EMPTY-BIN CHECK
    // ════════════════════════════════════════════════════════

    // ────────────────────────────────────────────────────────
    // Start / resume
    // ────────────────────────────────────────────────────────

    public CountStartResult StartEmptyBinCount(string storageTypeCode)
        => ExecuteStart("warehouse.usp_count_start_empty_bin", "Count.Start", storageTypeCode);

    // ────────────────────────────────────────────────────────
    // Confirm a bin empty
    // ────────────────────────────────────────────────────────

    public CountBinResult ConfirmEmpty(int countId, string binCode)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "warehouse.usp_count_confirm_empty";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add("@count_id",   SqlDbType.Int).Value               = countId;
        command.Parameters.Add("@bin_code",   SqlDbType.NVarChar, 100).Value     = binCode.Trim();
        command.Parameters.Add("@user_id",    SqlDbType.Int).Value               = _session.UserId;
        command.Parameters.Add("@session_id", SqlDbType.UniqueIdentifier).Value  = _session.SessionId;

        using var reader = command.ExecuteReader();

        if (!reader.Read())
            throw new InvalidOperationException("Unexpected empty response from count confirm.");

        var success = reader.GetBoolean(reader.GetOrdinal("success"));
        var code    = reader.GetString(reader.GetOrdinal("result_code"));

        var result = new CountBinResult
        {
            Success         = success,
            ResultCode      = code,
            FriendlyMessage = _resolver.Resolve(code),
            CountId         = Int(reader, "count_id") ?? countId,
            PendingBins     = Int(reader, "pending_bins") ?? 0
        };

        Log("Count.ConfirmEmpty", code, success, new
        {
            CountId = countId, BinCode = binCode, result.PendingBins
        });

        return result;
    }

    // ────────────────────────────────────────────────────────
    // Report a pallet found in a "empty" bin
    // ────────────────────────────────────────────────────────

    public CountStockResult ReportStock(int countId, string binCode, string scannedRef)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "warehouse.usp_count_report_stock";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add("@count_id",    SqlDbType.Int).Value               = countId;
        command.Parameters.Add("@bin_code",    SqlDbType.NVarChar, 100).Value     = binCode.Trim();
        command.Parameters.Add("@scanned_ref", SqlDbType.NVarChar, 100).Value     = scannedRef.Trim();
        command.Parameters.Add("@user_id",     SqlDbType.Int).Value               = _session.UserId;
        command.Parameters.Add("@session_id",  SqlDbType.UniqueIdentifier).Value  = _session.SessionId;

        using var reader = command.ExecuteReader();

        if (!reader.Read())
            throw new InvalidOperationException("Unexpected empty response from count report.");

        var success    = reader.GetBoolean(reader.GetOrdinal("success"));
        var code       = reader.GetString(reader.GetOrdinal("result_code"));
        var reasonCode = Str(reader, "reason_code");

        var result = new CountStockResult
        {
            Success         = success,
            ResultCode      = code,
            FriendlyMessage = _resolver.Resolve(code),
            FindingCode     = Str(reader, "finding_code"),
            CountId         = Int(reader, "count_id") ?? countId,
            InventoryUnitId = Int(reader, "inventory_unit_id"),
            SkuCode         = Str(reader, "sku_code"),
            PreviousBinCode = Str(reader, "previous_bin_code"),
            PendingBins     = Int(reader, "pending_bins") ?? 0,
            ReasonCode      = reasonCode,
            ReasonMessage   = reasonCode is null ? null : _resolver.Resolve(reasonCode),
            ShipmentRef     = Str(reader, "shipment_ref"),
            VehicleRef      = Str(reader, "vehicle_ref"),
            ShippedAt       = Date(reader, "shipped_at"),
            OrderRef        = Str(reader, "order_ref"),
            CustomerName    = Str(reader, "customer_name")
        };

        Log("Count.ReportStock", code, success, new
        {
            CountId = countId, BinCode = binCode, ScannedRef = scannedRef,
            result.FindingCode, result.InventoryUnitId, result.SkuCode,
            result.PreviousBinCode, result.ReasonCode, result.PendingBins,
            result.ShipmentRef, result.ShippedAt, result.OrderRef, result.CustomerName
        });

        return result;
    }

    // ════════════════════════════════════════════════════════
    // BIN COUNT (blind)
    // ════════════════════════════════════════════════════════

    // ────────────────────────────────────────────────────────
    // Start / resume (a null / blank storage type is a sweep)
    // ────────────────────────────────────────────────────────

    public CountStartResult StartBinCount(string? storageTypeCode)
        => ExecuteStart("warehouse.usp_count_start_bin", "Count.StartBin", storageTypeCode);

    // ────────────────────────────────────────────────────────
    // Start an ad hoc count: a hand-picked list of bins
    // ────────────────────────────────────────────────────────

    public CountStartResult StartAdHocCount(IReadOnlyCollection<string> binCodes)
    {
        EnsureSession();

        var codes = (binCodes ?? Array.Empty<string>())
            .Select(c => (c ?? string.Empty).Trim())
            .Where(c => c.Length > 0)
            .ToList();

        // The list travels as one string, separated by the ASCII record separator
        // (NCHAR(30)) - a character that cannot appear in a bin code
        var joined = string.Join('\u001e', codes);

        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "warehouse.usp_count_start_adhoc";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add("@bin_codes",  SqlDbType.NVarChar, -1).Value      = joined;
        command.Parameters.Add("@user_id",    SqlDbType.Int).Value               = _session.UserId;
        command.Parameters.Add("@session_id", SqlDbType.UniqueIdentifier).Value  = _session.SessionId;

        using var reader = command.ExecuteReader();

        if (!reader.Read())
            throw new InvalidOperationException("Unexpected empty response from ad hoc count start.");

        var success = reader.GetBoolean(reader.GetOrdinal("success"));
        var code    = reader.GetString(reader.GetOrdinal("result_code"));

        var result = new CountStartResult
        {
            Success         = success,
            ResultCode      = code,
            FriendlyMessage = _resolver.Resolve(code),
            CountId         = Int(reader, "count_id") ?? 0,
            TotalBins       = Int(reader, "total_bins") ?? 0,
            PendingBins     = Int(reader, "pending_bins") ?? 0,
            Resumed         = reader.GetBoolean(reader.GetOrdinal("resumed")),
            InvalidBinCode  = Str(reader, "invalid_bin_code")
        };

        Log("Count.StartAdHoc", code, success, new
        {
            BinCodes = codes, result.InvalidBinCode,
            result.CountId, result.TotalBins, result.PendingBins
        });

        return result;
    }

    // ────────────────────────────────────────────────────────
    // Open a bin: the operator scanned its label
    // ────────────────────────────────────────────────────────

    public BinCountOpenResult OpenBin(int countId, string binCode)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "warehouse.usp_count_open_bin";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add("@count_id",   SqlDbType.Int).Value               = countId;
        command.Parameters.Add("@bin_code",   SqlDbType.NVarChar, 100).Value     = binCode.Trim();
        command.Parameters.Add("@user_id",    SqlDbType.Int).Value               = _session.UserId;
        command.Parameters.Add("@session_id", SqlDbType.UniqueIdentifier).Value  = _session.SessionId;

        using var reader = command.ExecuteReader();

        if (!reader.Read())
            throw new InvalidOperationException("Unexpected empty response from count open bin.");

        var success = reader.GetBoolean(reader.GetOrdinal("success"));
        var code    = reader.GetString(reader.GetOrdinal("result_code"));

        var result = new BinCountOpenResult
        {
            Success         = success,
            ResultCode      = code,
            FriendlyMessage = _resolver.Resolve(code),
            CountId         = Int(reader, "count_id") ?? countId,
            BinCode         = Str(reader, "bin_code") ?? binCode.Trim(),
            PalletsScanned  = Int(reader, "pallets_scanned") ?? 0,
            PendingBins     = Int(reader, "pending_bins") ?? 0,
            Resumed         = reader.GetBoolean(reader.GetOrdinal("resumed"))
        };

        Log("Count.OpenBin", code, success, new
        {
            CountId = countId, BinCode = binCode, result.PalletsScanned,
            result.PendingBins, result.Resumed
        });

        return result;
    }

    // ────────────────────────────────────────────────────────
    // Scan one pallet (SSCC + counted quantity) in an open bin
    // ────────────────────────────────────────────────────────

    public BinCountScanResult ScanUnit(
        int    countId,
        string binCode,
        string scannedRef,
        int    countedQty,
        bool   confirmDifference = false)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "warehouse.usp_count_scan_unit";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add("@count_id",           SqlDbType.Int).Value               = countId;
        command.Parameters.Add("@bin_code",           SqlDbType.NVarChar, 100).Value     = binCode.Trim();
        command.Parameters.Add("@scanned_ref",        SqlDbType.NVarChar, 100).Value     = scannedRef.Trim();
        command.Parameters.Add("@counted_qty",        SqlDbType.Int).Value               = countedQty;
        command.Parameters.Add("@confirm_difference", SqlDbType.Bit).Value               = confirmDifference;
        command.Parameters.Add("@user_id",            SqlDbType.Int).Value               = _session.UserId;
        command.Parameters.Add("@session_id",         SqlDbType.UniqueIdentifier).Value  = _session.SessionId;

        using var reader = command.ExecuteReader();

        if (!reader.Read())
            throw new InvalidOperationException("Unexpected empty response from count scan.");

        var success = reader.GetBoolean(reader.GetOrdinal("success"));
        var code    = reader.GetString(reader.GetOrdinal("result_code"));

        var result = new BinCountScanResult
        {
            Success           = success,
            ResultCode        = code,
            FriendlyMessage   = _resolver.Resolve(code),
            CountId           = Int(reader, "count_id") ?? countId,
            PalletsScanned    = Int(reader, "pallets_scanned") ?? 0,
            Replaced          = reader.GetBoolean(reader.GetOrdinal("replaced")),
            NeedsConfirmation = reader.GetBoolean(reader.GetOrdinal("needs_confirmation"))
        };

        // Asking the operator to confirm a quantity is part of the normal flow,
        // not something that needs a human look - so it logs at INFO, not WARN
        Log("Count.ScanUnit", code, success, new
        {
            CountId = countId, BinCode = binCode, ScannedRef = scannedRef,
            CountedQty = countedQty, ConfirmDifference = confirmDifference,
            result.NeedsConfirmation, result.Replaced, result.PalletsScanned
        }, routine: result.NeedsConfirmation);

        return result;
    }

    // ────────────────────────────────────────────────────────
    // Finish a bin: compare, record the findings
    // ────────────────────────────────────────────────────────

    public BinCountFinishResult FinishBin(int countId, string binCode)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "warehouse.usp_count_finish_bin";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add("@count_id",   SqlDbType.Int).Value               = countId;
        command.Parameters.Add("@bin_code",   SqlDbType.NVarChar, 100).Value     = binCode.Trim();
        command.Parameters.Add("@user_id",    SqlDbType.Int).Value               = _session.UserId;
        command.Parameters.Add("@session_id", SqlDbType.UniqueIdentifier).Value  = _session.SessionId;

        using var reader = command.ExecuteReader();

        if (!reader.Read())
            throw new InvalidOperationException("Unexpected empty response from count finish bin.");

        var success = reader.GetBoolean(reader.GetOrdinal("success"));
        var code    = reader.GetString(reader.GetOrdinal("result_code"));

        var result = new BinCountFinishResult
        {
            Success         = success,
            ResultCode      = code,
            FriendlyMessage = _resolver.Resolve(code),
            CountId         = Int(reader, "count_id") ?? countId,
            PalletsScanned  = Int(reader, "pallets_scanned") ?? 0,
            Differences     = Int(reader, "differences") ?? 0,
            PendingBins     = Int(reader, "pending_bins") ?? 0,
            RecountRequired = reader.GetBoolean(reader.GetOrdinal("recount_required"))
        };

        Log("Count.FinishBin", code, success, new
        {
            CountId = countId, BinCode = binCode, result.PalletsScanned,
            result.Differences, result.PendingBins, result.RecountRequired
        });

        return result;
    }

    // ────────────────────────────────────────────────────────
    // Cancel an open bin
    // ────────────────────────────────────────────────────────

    public CountBinResult CancelBin(int countId, string binCode)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "warehouse.usp_count_cancel_bin";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add("@count_id",   SqlDbType.Int).Value               = countId;
        command.Parameters.Add("@bin_code",   SqlDbType.NVarChar, 100).Value     = binCode.Trim();
        command.Parameters.Add("@user_id",    SqlDbType.Int).Value               = _session.UserId;
        command.Parameters.Add("@session_id", SqlDbType.UniqueIdentifier).Value  = _session.SessionId;

        using var reader = command.ExecuteReader();

        if (!reader.Read())
            throw new InvalidOperationException("Unexpected empty response from count cancel bin.");

        var success = reader.GetBoolean(reader.GetOrdinal("success"));
        var code    = reader.GetString(reader.GetOrdinal("result_code"));

        var result = new CountBinResult
        {
            Success         = success,
            ResultCode      = code,
            FriendlyMessage = _resolver.Resolve(code),
            CountId         = Int(reader, "count_id") ?? countId,
            PendingBins     = Int(reader, "pending_bins") ?? 0
        };

        Log("Count.CancelBin", code, success, new
        {
            CountId = countId, BinCode = binCode, result.PendingBins
        });

        return result;
    }

    // ════════════════════════════════════════════════════════
    // CLOSE / DECIDE / REVIEW (both kinds of count)
    // ════════════════════════════════════════════════════════

    // ────────────────────────────────────────────────────────
    // Close
    // ────────────────────────────────────────────────────────

    public CountCloseResult Close(int countId)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "warehouse.usp_count_close";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add("@count_id",   SqlDbType.Int).Value               = countId;
        command.Parameters.Add("@user_id",    SqlDbType.Int).Value               = _session.UserId;
        command.Parameters.Add("@session_id", SqlDbType.UniqueIdentifier).Value  = _session.SessionId;

        using var reader = command.ExecuteReader();

        if (!reader.Read())
            throw new InvalidOperationException("Unexpected empty response from count close.");

        var success = reader.GetBoolean(reader.GetOrdinal("success"));
        var code    = reader.GetString(reader.GetOrdinal("result_code"));

        var result = new CountCloseResult
        {
            Success         = success,
            ResultCode      = code,
            FriendlyMessage = _resolver.Resolve(code),
            CountId         = Int(reader, "count_id") ?? countId,
            PendingBins     = Int(reader, "pending_bins") ?? 0,
            FinalStatus     = Str(reader, "final_status"),
            FindingsToReview = Int(reader, "findings_to_review") ?? 0
        };

        Log("Count.Close", code, success, new
        {
            CountId = countId, result.FinalStatus, result.PendingBins, result.FindingsToReview
        });

        return result;
    }

    // ────────────────────────────────────────────────────────
    // Apply / decline one finding of a bin count (counts.adjust)
    // ────────────────────────────────────────────────────────

    public CountApplyResult ApplyFinding(int findingId)
        => ExecuteDecision(findingId, "APPLY", note: null);

    public CountApplyResult DeclineFinding(int findingId, string note)
        => ExecuteDecision(findingId, "DECLINE", (note ?? string.Empty).Trim());

    private CountApplyResult ExecuteDecision(int findingId, string action, string? note)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "warehouse.usp_count_apply_finding";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add("@finding_id", SqlDbType.Int).Value               = findingId;
        command.Parameters.Add("@action",     SqlDbType.VarChar, 10).Value       = action;
        command.Parameters.Add("@note",       SqlDbType.NVarChar, 500).Value     = (object?)note ?? DBNull.Value;
        command.Parameters.Add("@user_id",    SqlDbType.Int).Value               = _session.UserId;
        command.Parameters.Add("@session_id", SqlDbType.UniqueIdentifier).Value  = _session.SessionId;

        using var reader = command.ExecuteReader();

        if (!reader.Read())
            throw new InvalidOperationException("Unexpected empty response from count apply finding.");

        var success = reader.GetBoolean(reader.GetOrdinal("success"));
        var code    = reader.GetString(reader.GetOrdinal("result_code"));

        var result = new CountApplyResult
        {
            Success            = success,
            ResultCode         = code,
            FriendlyMessage    = _resolver.Resolve(code),
            FindingId          = Int(reader, "finding_id") ?? findingId,
            FindingCode        = Str(reader, "finding_code"),
            CountId            = Int(reader, "count_id") ?? 0,
            MovementId         = Int(reader, "movement_id"),
            UnresolvedFindings = Int(reader, "unresolved_findings") ?? 0
        };

        // The decision, and the ledger row that carried it out, go in the trace
        // log as well as on the finding: this is the record of who changed (or
        // chose not to change) a stock record because of a count, and why.
        Log(action == "APPLY" ? "Count.ApplyFinding" : "Count.DeclineFinding", code, success, new
        {
            FindingId = findingId, result.FindingCode, result.CountId,
            result.MovementId, Note = note, result.UnresolvedFindings
        });

        return result;
    }

    // ────────────────────────────────────────────────────────
    // Review
    // ────────────────────────────────────────────────────────

    public CountReviewResult Review(int countId, string note)
    {
        EnsureSession();

        var trimmed = (note ?? string.Empty).Trim();

        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "warehouse.usp_count_review";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add("@count_id",   SqlDbType.Int).Value               = countId;
        command.Parameters.Add("@note",       SqlDbType.NVarChar, 500).Value     = trimmed;
        command.Parameters.Add("@user_id",    SqlDbType.Int).Value               = _session.UserId;
        command.Parameters.Add("@session_id", SqlDbType.UniqueIdentifier).Value  = _session.SessionId;

        using var reader = command.ExecuteReader();

        if (!reader.Read())
            throw new InvalidOperationException("Unexpected empty response from count review.");

        var success = reader.GetBoolean(reader.GetOrdinal("success"));
        var code    = reader.GetString(reader.GetOrdinal("result_code"));

        var result = new CountReviewResult
        {
            Success         = success,
            ResultCode      = code,
            FriendlyMessage = _resolver.Resolve(code),
            CountId         = Int(reader, "count_id") ?? countId,
            FinalStatus     = Str(reader, "final_status")
        };

        // The note goes in the trace log as well as on the count: this is the
        // record of who dealt with what the count found, and what they did.
        Log("Count.Review", code, success, new
        {
            CountId = countId, Note = trimmed, result.FinalStatus
        });

        return result;
    }

    // ════════════════════════════════════════════════════════
    // Helpers
    // ════════════════════════════════════════════════════════

    /// <summary>
    /// Start / resume, shared by the empty-bin check and the bin count: the same
    /// procedure contract, the same result. A null / blank storage type is sent as
    /// NULL (a bin-count sweep); the empty-bin procedure answers ERRCNT01 to it.
    /// </summary>
    private CountStartResult ExecuteStart(string procedure, string action, string? storageTypeCode)
    {
        EnsureSession();

        var scope = string.IsNullOrWhiteSpace(storageTypeCode) ? null : storageTypeCode.Trim();

        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = procedure;
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add("@storage_type_code", SqlDbType.NVarChar, 50).Value = (object?)scope ?? DBNull.Value;
        command.Parameters.Add("@user_id",           SqlDbType.Int).Value               = _session.UserId;
        command.Parameters.Add("@session_id",        SqlDbType.UniqueIdentifier).Value  = _session.SessionId;

        using var reader = command.ExecuteReader();

        if (!reader.Read())
            throw new InvalidOperationException("Unexpected empty response from count start.");

        var success = reader.GetBoolean(reader.GetOrdinal("success"));
        var code    = reader.GetString(reader.GetOrdinal("result_code"));

        var result = new CountStartResult
        {
            Success         = success,
            ResultCode      = code,
            FriendlyMessage = _resolver.Resolve(code),
            CountId         = Int(reader, "count_id") ?? 0,
            TotalBins       = Int(reader, "total_bins") ?? 0,
            PendingBins     = Int(reader, "pending_bins") ?? 0,
            Resumed         = reader.GetBoolean(reader.GetOrdinal("resumed"))
        };

        Log(action, code, success, new
        {
            StorageTypeCode = scope ?? "(all - sweep)",
            result.CountId, result.TotalBins, result.PendingBins, result.Resumed
        });

        return result;
    }

    /// <summary>
    /// SUC codes log at INFO. WARN codes (unknown pallet, not corrected,
    /// stock appeared since the snapshot, a bin that changed under the count)
    /// and failures log at WARN, so the outcomes that need a human look stand
    /// out in the trace log. <paramref name="routine"/> keeps a step that is a
    /// normal part of the flow (asking the operator to confirm a quantity) at INFO.
    /// </summary>
    private void Log(string action, string code, bool success, object outcome, bool routine = false)
    {
        var payload = new
        {
            _session.UserId,
            _session.SessionId,
            _session.CorrelationId,
            ResultCode = code,
            Success    = success,
            Outcome    = outcome
        };

        if (routine || (success && code.StartsWith("SUC", StringComparison.OrdinalIgnoreCase)))
            _logger.Info(action, payload);
        else
            _logger.Warn(action, payload);
    }

    private static string? Str(SqlDataReader r, string column)
    {
        var o = r.GetOrdinal(column);
        return r.IsDBNull(o) ? null : r.GetString(o);
    }

    private static int? Int(SqlDataReader r, string column)
    {
        var o = r.GetOrdinal(column);
        return r.IsDBNull(o) ? null : r.GetInt32(o);
    }

    private static DateTime? Date(SqlDataReader r, string column)
    {
        var o = r.GetOrdinal(column);
        return r.IsDBNull(o) ? null : r.GetDateTime(o);
    }
}
