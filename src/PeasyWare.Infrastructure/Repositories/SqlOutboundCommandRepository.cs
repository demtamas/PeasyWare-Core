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

public sealed class SqlOutboundCommandRepository
    : RepositoryBase, IOutboundCommandRepository
{
    private readonly SqlConnectionFactory  _factory;
    private readonly SessionContext        _session;
    private readonly IErrorMessageResolver _resolver;
    private readonly ILogger               _logger;

    public SqlOutboundCommandRepository(
        SqlConnectionFactory  factory,
        SessionContext        session,
        IErrorMessageResolver resolver,
        ILogger               logger,
        SessionGuard          sessionGuard)
        : base(sessionGuard, session.SessionId)
    {
        _factory  = factory  ?? throw new ArgumentNullException(nameof(factory));
        _session  = session  ?? throw new ArgumentNullException(nameof(session));
        _resolver = resolver ?? throw new ArgumentNullException(nameof(resolver));
        _logger   = logger   ?? throw new ArgumentNullException(nameof(logger));
    }

    // ────────────────────────────────────────────────────────
    // Create pick task
    // destinationBinCode = null → SP auto-selects first staging bin
    // ────────────────────────────────────────────────────────

    public PickTaskResult CreatePickTask(int allocationId, string? destinationBinCode)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "outbound.usp_pick_create";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add("@allocation_id",  SqlDbType.Int).Value              = allocationId;
        command.Parameters.Add("@user_id",         SqlDbType.Int).Value              = _session.UserId;
        command.Parameters.Add("@session_id",      SqlDbType.UniqueIdentifier).Value = _session.SessionId;

        var destParam = command.Parameters.Add("@destination_bin_code", SqlDbType.NVarChar, 100);
        destParam.Value = destinationBinCode is not null
            ? (object)destinationBinCode.Trim()
            : DBNull.Value;

        using var reader = command.ExecuteReader();

        if (!reader.Read())
            throw new InvalidOperationException("Unexpected empty response from pick task creation.");

        var colSuccess  = reader.GetOrdinal("success");
        var colCode     = reader.GetOrdinal("result_code");
        var colTaskId   = reader.GetOrdinal("task_id");
        var colUnitId   = reader.GetOrdinal("inventory_unit_id");
        var colSrcBin   = reader.GetOrdinal("source_bin_code");
        var colDestBin  = reader.GetOrdinal("destination_bin_code");

        var success = reader.GetBoolean(colSuccess);
        var code    = reader.GetString(colCode);
        var message = _resolver.Resolve(code);

        if (!success)
        {
            _logger.Warn("Outbound.Pick.Create", new
            {
                _session.UserId, _session.SessionId,
                AllocationId = allocationId, ResultCode = code, Success = false
            });

            return new PickTaskResult
            {
                Success = false, ResultCode = code, FriendlyMessage = message
            };
        }

        var result = new PickTaskResult
        {
            Success            = true,
            ResultCode         = code,
            FriendlyMessage    = message,
            TaskId             = reader.GetInt32(colTaskId),
            InventoryUnitId    = reader.IsDBNull(colUnitId)  ? 0            : reader.GetInt32(colUnitId),
            SourceBinCode      = reader.IsDBNull(colSrcBin)  ? string.Empty : reader.GetString(colSrcBin),
            DestinationBinCode = reader.IsDBNull(colDestBin) ? string.Empty : reader.GetString(colDestBin)
        };

        _logger.Info("Outbound.Pick.Create", new
        {
            _session.UserId, _session.SessionId,
            AllocationId = allocationId,
            result.TaskId, result.SourceBinCode, result.DestinationBinCode,
            ResultCode = code, Success = true
        });

        return result;
    }

    // ────────────────────────────────────────────────────────
    // Confirm pick task
    // ────────────────────────────────────────────────────────

    public OperationResult ConfirmPickTask(int taskId, string scannedBinCode, string scannedSscc)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "outbound.usp_pick_confirm";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add("@task_id",           SqlDbType.Int).Value              = taskId;
        command.Parameters.Add("@scanned_bin_code",  SqlDbType.NVarChar, 100).Value    = scannedBinCode.Trim();
        command.Parameters.Add("@scanned_sscc",      SqlDbType.NVarChar, 100).Value    = scannedSscc.Trim();
        command.Parameters.Add("@user_id",           SqlDbType.Int).Value              = _session.UserId;
        command.Parameters.Add("@session_id",        SqlDbType.UniqueIdentifier).Value = _session.SessionId;

        using var reader = command.ExecuteReader();

        if (!reader.Read())
            throw new InvalidOperationException("Unexpected empty response from pick confirmation.");

        var success = reader.GetBoolean(reader.GetOrdinal("success"));
        var code    = reader.GetString(reader.GetOrdinal("result_code"));
        var message = _resolver.Resolve(code);
        var result  = OperationResult.Create(success, code, message);

        if (success)
            _logger.Info("Outbound.Pick.Confirm", new
            {
                _session.UserId, _session.SessionId,
                TaskId = taskId, ResultCode = code, Success = true
            });
        else
            _logger.Warn("Outbound.Pick.Confirm", new
            {
                _session.UserId, _session.SessionId,
                TaskId = taskId, ScannedBin = scannedBinCode,
                ResultCode = code, Success = false
            });

        return result;
    }
}
