using Microsoft.Data.SqlClient;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Application.Security;
using PeasyWare.Infrastructure.Sql;
using System;
using System.Collections.Generic;
using System.Data;

namespace PeasyWare.Infrastructure.Repositories;

public sealed class SqlCountQueryRepository
    : RepositoryBase, ICountQueryRepository
{
    private const string SessionColumns = """
        count_id, count_type_code, scope_code, storage_type_code, status_code,
        started_at, started_by, completed_at, completed_by,
        total_bins, pending_bins, confirmed_empty, stock_found, occupied_since,
        counting_bins, matched_bins, difference_bins,
        findings_to_review, reviewed_at, reviewed_by, review_note
        """;

    private const string LineColumns = """
        count_line_id, count_id, bin_code, zone_code, storage_type_code,
        line_status_code, opened_at, counted_at, counted_by,
        pallets_scanned, finding_count
        """;

    // Walk order: by zone (numerically where the code is a number, unzoned
    // last), then bin code.
    private const string LineOrder = """
        ORDER BY
            CASE WHEN zone_code IS NULL THEN 1 ELSE 0 END,
            TRY_CAST(zone_code AS INT),
            zone_code,
            bin_code
        """;

    private readonly SqlConnectionFactory _factory;
    private readonly SessionContext       _session;

    public SqlCountQueryRepository(
        SqlConnectionFactory  factory,
        SessionContext        session,
        IErrorMessageResolver resolver,
        ILogger               logger,
        SessionGuard          sessionGuard)
        : base(sessionGuard, session, resolver, logger)
    {
        _factory = factory ?? throw new ArgumentNullException(nameof(factory));
        _session = session ?? throw new ArgumentNullException(nameof(session));
    }

    // ────────────────────────────────────────────────────────
    // Picker: storage types with empty bins (or an open count)
    // ────────────────────────────────────────────────────────

    public IReadOnlyList<EmptyBinSummaryDto> GetEmptyBinSummary()
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        // One definition of "empty" (warehouse.v_empty_bins), the same one the
        // count snapshot uses. A storage type with an open count is listed even
        // if nothing is empty right now, so the count can be resumed.
        command.CommandText = """
            SELECT *
            FROM (
                SELECT
                    st.storage_type_code,
                    st.storage_type_name,
                    (SELECT COUNT(*)
                     FROM warehouse.v_empty_bins eb
                     WHERE eb.storage_type_id = st.storage_type_id)   AS empty_bins,
                    cs.count_id                                       AS open_count_id,
                    cs.pending_bins                                   AS open_pending_bins
                FROM locations.storage_types st
                LEFT JOIN warehouse.v_count_sessions cs
                       ON cs.storage_type_code = st.storage_type_code
                      AND cs.count_type_code   = 'EMPTY_BIN'
                      AND cs.status_code       = 'OPEN'
                WHERE st.is_active = 1
            ) x
            WHERE x.empty_bins > 0 OR x.open_count_id IS NOT NULL
            ORDER BY x.storage_type_code
            """;

        command.CommandType = CommandType.Text;

        using var reader = command.ExecuteReader();
        var results = new List<EmptyBinSummaryDto>();

        while (reader.Read())
        {
            results.Add(new EmptyBinSummaryDto
            {
                StorageTypeCode = reader.GetString(reader.GetOrdinal("storage_type_code")),
                StorageTypeName = reader.GetString(reader.GetOrdinal("storage_type_name")),
                EmptyBins       = reader.GetInt32(reader.GetOrdinal("empty_bins")),
                OpenCountId     = Int(reader, "open_count_id"),
                OpenPendingBins = Int(reader, "open_pending_bins")
            });
        }

        return results;
    }

    // ────────────────────────────────────────────────────────
    // Picker: storage types with bins to bin-count (or an open bin count)
    // ────────────────────────────────────────────────────────

    public IReadOnlyList<BinCountSummaryDto> GetBinCountSummary()
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        // One definition of "a bin to count" (warehouse.v_occupied_bins), the same
        // one the count snapshot uses. A storage type with an open bin count is
        // listed even if nothing holds stock right now, so it can be resumed. A
        // sweep (no storage type) is not here: it belongs to no storage type.
        command.CommandText = """
            SELECT *
            FROM (
                SELECT
                    st.storage_type_code,
                    st.storage_type_name,
                    (SELECT COUNT(*)
                     FROM warehouse.v_occupied_bins ob
                     WHERE ob.storage_type_id = st.storage_type_id)   AS bins_with_stock,
                    cs.count_id                                       AS open_count_id,
                    cs.pending_bins + cs.counting_bins                AS open_pending_bins
                FROM locations.storage_types st
                LEFT JOIN warehouse.v_count_sessions cs
                       ON cs.storage_type_code = st.storage_type_code
                      AND cs.count_type_code   = 'BIN_COUNT'
                      AND cs.status_code       = 'OPEN'
                WHERE st.is_active = 1
            ) x
            WHERE x.bins_with_stock > 0 OR x.open_count_id IS NOT NULL
            ORDER BY x.storage_type_code
            """;

        command.CommandType = CommandType.Text;

        using var reader = command.ExecuteReader();
        var results = new List<BinCountSummaryDto>();

        while (reader.Read())
        {
            results.Add(new BinCountSummaryDto
            {
                StorageTypeCode = reader.GetString(reader.GetOrdinal("storage_type_code")),
                StorageTypeName = reader.GetString(reader.GetOrdinal("storage_type_name")),
                BinsWithStock   = reader.GetInt32(reader.GetOrdinal("bins_with_stock")),
                OpenCountId     = Int(reader, "open_count_id"),
                OpenPendingBins = Int(reader, "open_pending_bins")
            });
        }

        return results;
    }

    // ────────────────────────────────────────────────────────
    // Ad hoc: is this a bin that can be named in a hand-picked list?
    // ────────────────────────────────────────────────────────

    public bool IsCountableBin(string binCode)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        // Bin codes are matched exactly: a wrong-case entry is not that bin
        command.CommandText = """
            SELECT CASE WHEN EXISTS (
                SELECT 1
                FROM locations.bins b
                JOIN locations.storage_types st ON st.storage_type_id = b.storage_type_id
                WHERE b.bin_code  = @bin_code COLLATE Latin1_General_CS_AS
                  AND b.is_active  = 1
                  AND st.is_active = 1
            ) THEN 1 ELSE 0 END
            """;

        command.CommandType = CommandType.Text;
        command.Parameters.Add(new SqlParameter("@bin_code", SqlDbType.NVarChar, 100) { Value = (binCode ?? string.Empty).Trim() });

        return Convert.ToInt32(command.ExecuteScalar()) == 1;
    }

    // ────────────────────────────────────────────────────────
    // Lines
    // ────────────────────────────────────────────────────────

    public IReadOnlyList<CountLineDto> GetPendingLines(int countId)
        => QueryLines(countId, pendingOnly: true);

    public IReadOnlyList<CountLineDto> GetLines(int countId)
        => QueryLines(countId, pendingOnly: false);

    private IReadOnlyList<CountLineDto> QueryLines(int countId, bool pendingOnly)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = $"""
            SELECT {LineColumns}
            FROM warehouse.v_count_lines
            WHERE count_id = @count_id
              {(pendingOnly ? "AND line_status_code = 'PENDING'" : "")}
            {LineOrder}
            """;

        command.CommandType = CommandType.Text;
        command.Parameters.Add(new SqlParameter("@count_id", SqlDbType.Int) { Value = countId });

        using var reader = command.ExecuteReader();
        var results = new List<CountLineDto>();

        while (reader.Read())
            results.Add(ReadLine(reader));

        return results;
    }

    // ────────────────────────────────────────────────────────
    // Sessions
    // ────────────────────────────────────────────────────────

    public CountSessionDto? GetSession(int countId)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = $"""
            SELECT {SessionColumns}
            FROM warehouse.v_count_sessions
            WHERE count_id = @count_id
            """;

        command.CommandType = CommandType.Text;
        command.Parameters.Add(new SqlParameter("@count_id", SqlDbType.Int) { Value = countId });

        using var reader = command.ExecuteReader();

        return reader.Read() ? ReadSession(reader) : null;
    }

    public IReadOnlyList<CountSessionDto> GetSessions(bool needsAttentionOnly)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        // Needs-attention (OPEN in progress, REVIEW waiting for a person) is
        // unbounded - those must never fall off a list. The full history is the
        // most recent 200.
        command.CommandText = needsAttentionOnly
            ? $"""
              SELECT {SessionColumns}
              FROM warehouse.v_count_sessions
              WHERE status_code IN ('OPEN', 'REVIEW')
              ORDER BY count_id DESC
              """
            : $"""
              SELECT TOP (200) {SessionColumns}
              FROM warehouse.v_count_sessions
              ORDER BY count_id DESC
              """;

        command.CommandType = CommandType.Text;

        using var reader = command.ExecuteReader();
        var results = new List<CountSessionDto>();

        while (reader.Read())
            results.Add(ReadSession(reader));

        return results;
    }

    // ────────────────────────────────────────────────────────
    // Findings
    // ────────────────────────────────────────────────────────

    public IReadOnlyList<CountFindingDto> GetFindings(int countId)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = """
            SELECT
                finding_id, count_id, bin_code, scanned_ref, inventory_unit_id,
                sku_code, finding_code, reason_code, reason_message,
                previous_bin_code, movement_id, found_at, found_by,
                counted_qty, system_qty,
                resolution_code, resolved_at, resolved_by, resolution_note,
                resolution_movement_id,
                shipment_ref, vehicle_ref, shipped_at, order_ref, customer_name
            FROM warehouse.v_count_findings
            WHERE count_id = @count_id
            ORDER BY found_at, finding_id
            """;

        command.CommandType = CommandType.Text;
        command.Parameters.Add(new SqlParameter("@count_id", SqlDbType.Int) { Value = countId });

        using var reader = command.ExecuteReader();
        var results = new List<CountFindingDto>();

        while (reader.Read())
        {
            results.Add(new CountFindingDto
            {
                FindingId       = reader.GetInt32(reader.GetOrdinal("finding_id")),
                CountId         = reader.GetInt32(reader.GetOrdinal("count_id")),
                BinCode         = reader.GetString(reader.GetOrdinal("bin_code")),
                ScannedRef      = reader.GetString(reader.GetOrdinal("scanned_ref")),
                InventoryUnitId = Int(reader, "inventory_unit_id"),
                SkuCode         = Str(reader, "sku_code"),
                FindingCode     = reader.GetString(reader.GetOrdinal("finding_code")),
                ReasonCode      = Str(reader, "reason_code"),
                ReasonMessage   = Str(reader, "reason_message"),
                PreviousBinCode = Str(reader, "previous_bin_code"),
                MovementId      = Int(reader, "movement_id"),
                FoundAt         = reader.GetDateTime(reader.GetOrdinal("found_at")),
                FoundBy         = Str(reader, "found_by"),
                CountedQty      = Int(reader, "counted_qty"),
                SystemQty       = Int(reader, "system_qty"),
                ResolutionCode  = Str(reader, "resolution_code"),
                ResolvedAt      = Date(reader, "resolved_at"),
                ResolvedBy      = Str(reader, "resolved_by"),
                ResolutionNote  = Str(reader, "resolution_note"),
                ResolutionMovementId = Int(reader, "resolution_movement_id"),
                ShipmentRef     = Str(reader, "shipment_ref"),
                VehicleRef      = Str(reader, "vehicle_ref"),
                ShippedAt       = Date(reader, "shipped_at"),
                OrderRef        = Str(reader, "order_ref"),
                CustomerName    = Str(reader, "customer_name")
            });
        }

        return results;
    }

    // ────────────────────────────────────────────────────────
    // Row mapping
    // ────────────────────────────────────────────────────────

    private static CountLineDto ReadLine(SqlDataReader r) => new()
    {
        CountLineId     = r.GetInt32(r.GetOrdinal("count_line_id")),
        CountId         = r.GetInt32(r.GetOrdinal("count_id")),
        BinCode         = r.GetString(r.GetOrdinal("bin_code")),
        ZoneCode        = Str(r, "zone_code"),
        StorageTypeCode = Str(r, "storage_type_code"),
        LineStatusCode  = r.GetString(r.GetOrdinal("line_status_code")),
        OpenedAt        = Date(r, "opened_at"),
        CountedAt       = Date(r, "counted_at"),
        CountedBy       = Str(r, "counted_by"),
        PalletsScanned  = r.GetInt32(r.GetOrdinal("pallets_scanned")),
        FindingCount    = r.GetInt32(r.GetOrdinal("finding_count"))
    };

    private static CountSessionDto ReadSession(SqlDataReader r) => new()
    {
        CountId         = r.GetInt32(r.GetOrdinal("count_id")),
        CountTypeCode   = r.GetString(r.GetOrdinal("count_type_code")),
        ScopeCode       = r.GetString(r.GetOrdinal("scope_code")),
        StorageTypeCode = Str(r, "storage_type_code"),
        StatusCode      = r.GetString(r.GetOrdinal("status_code")),
        StartedAt       = r.GetDateTime(r.GetOrdinal("started_at")),
        StartedBy       = Str(r, "started_by"),
        CompletedAt     = Date(r, "completed_at"),
        CompletedBy     = Str(r, "completed_by"),
        TotalBins       = r.GetInt32(r.GetOrdinal("total_bins")),
        PendingBins     = r.GetInt32(r.GetOrdinal("pending_bins")),
        ConfirmedEmpty  = r.GetInt32(r.GetOrdinal("confirmed_empty")),
        StockFound      = r.GetInt32(r.GetOrdinal("stock_found")),
        OccupiedSince   = r.GetInt32(r.GetOrdinal("occupied_since")),
        CountingBins    = r.GetInt32(r.GetOrdinal("counting_bins")),
        MatchedBins     = r.GetInt32(r.GetOrdinal("matched_bins")),
        DifferenceBins  = r.GetInt32(r.GetOrdinal("difference_bins")),
        FindingsToReview = r.GetInt32(r.GetOrdinal("findings_to_review")),
        ReviewedAt      = Date(r, "reviewed_at"),
        ReviewedBy      = Str(r, "reviewed_by"),
        ReviewNote      = Str(r, "review_note")
    };

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
