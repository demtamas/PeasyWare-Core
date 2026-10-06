using Microsoft.Data.SqlClient;
using PeasyWare.Application;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Application.Security;
using PeasyWare.Infrastructure.Sql;
using System;
using System.Data;

namespace PeasyWare.Infrastructure.Repositories;

/// <summary>
/// Command repository for stock counting (empty-bin check today).
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

    // ────────────────────────────────────────────────────────
    // Start / resume
    // ────────────────────────────────────────────────────────

    public CountStartResult StartEmptyBinCount(string storageTypeCode)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "warehouse.usp_count_start_empty_bin";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add("@storage_type_code", SqlDbType.NVarChar, 50).Value = storageTypeCode.Trim();
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

        Log("Count.Start", code, success, new
        {
            StorageTypeCode = storageTypeCode,
            result.CountId, result.TotalBins, result.PendingBins, result.Resumed
        });

        return result;
    }

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

    // ────────────────────────────────────────────────────────
    // Helpers
    // ────────────────────────────────────────────────────────

    /// <summary>
    /// SUC codes log at INFO. WARN codes (unknown pallet, not corrected,
    /// stock appeared since the snapshot) and failures log at WARN, so the
    /// outcomes that need a human look stand out in the trace log.
    /// </summary>
    private void Log(string action, string code, bool success, object outcome)
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

        if (success && code.StartsWith("SUC", StringComparison.OrdinalIgnoreCase))
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
