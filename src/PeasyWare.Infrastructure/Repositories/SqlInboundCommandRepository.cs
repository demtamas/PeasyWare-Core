using Microsoft.Data.SqlClient;
using PeasyWare.Application;
using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Infrastructure.Errors;
using PeasyWare.Infrastructure.Sql;
using System.Data;

namespace PeasyWare.Infrastructure.Repositories;

public sealed class SqlInboundCommandRepository : IInboundCommandRepository
{
    private readonly SqlConnectionFactory _factory;
    private readonly Guid _sessionId;
    private readonly int _userId;
    private readonly IErrorMessageResolver _messageResolver;
    private readonly ILogger _logger;

    public SqlInboundCommandRepository(
        SqlConnectionFactory factory,
        Guid sessionId,
        int userId,
        IErrorMessageResolver messageResolver,
        ILogger logger)
    {
        _factory = factory;
        _sessionId = sessionId;
        _userId = userId;
        _messageResolver = messageResolver;
        _logger = logger;
    }

    // --------------------------------------------------
    // Activate inbound by ID
    // --------------------------------------------------

    public OperationResult ActivateInbound(int inboundId)
    {
        using var connection =
            _factory.CreateForCommand(_sessionId, _userId);

        using var command = connection.CreateCommand();
        command.CommandText = "deliveries.usp_activate_inbound";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.AddWithValue("@inbound_Id", inboundId);

        SqlCorrelation.Add(command);

        var pSuccess = command.Parameters.Add(
            "@success",
            SqlDbType.Bit);
        pSuccess.Direction = ParameterDirection.Output;

        var pCode = command.Parameters.Add(
            "@error_code",
            SqlDbType.NVarChar,
            20);
        pCode.Direction = ParameterDirection.Output;

        command.ExecuteNonQuery();

        var success = pSuccess.Value is bool b && b;
        var code = pCode.Value?.ToString() ?? "ERRINB99";
        var message = _messageResolver.Resolve(code);

        var result = OperationResult.Create(success, code, message);

        if (success)
        {
            _logger.Info("Inbound.Activate", new
            {
                UserId = _userId,
                SessionId = _sessionId,
                InboundId = inboundId,
                ResultCode = code,
                Success = true
            });
        }
        else
        {
            _logger.Warn("Inbound.Activate", new
            {
                UserId = _userId,
                SessionId = _sessionId,
                InboundId = inboundId,
                ResultCode = code,
                Success = false
            });
        }

        return result;
    }

    // --------------------------------------------------
    // Activate inbound by reference
    // --------------------------------------------------

    public OperationResult ActivateInboundByRef(string inboundRef)
    {
        using var connection =
            _factory.CreateForCommand(_sessionId, _userId);

        using var command = connection.CreateCommand();
        command.CommandText = "deliveries.usp_activate_inbound";
        command.CommandType = CommandType.StoredProcedure;

        var inboundId = ResolveInboundId(connection, inboundRef);

        command.Parameters.AddWithValue("@inbound_id", inboundId);
        command.Parameters.AddWithValue("@user_id", _userId);
        command.Parameters.AddWithValue("@session_id", _sessionId);

        bool success;
        string code;

        using (var reader = command.ExecuteReader())
        {
            if (!reader.Read())
            {
                code = "ERRINBL99";
                var message = _messageResolver.Resolve(code);
                var result = OperationResult.Create(false, code, message);

                _logger.Warn("Inbound.ActivateByRef", new
                {
                    UserId = _userId,
                    SessionId = _sessionId,
                    InboundRef = inboundRef,
                    ResultCode = code,
                    Success = false
                });

                return result;
            }

            success = reader.GetBoolean(0);
            code = reader.GetString(1);
        }

        var resolvedMessage = _messageResolver.Resolve(code);
        var finalResult = OperationResult.Create(success, code, resolvedMessage);

        if (success)
        {
            _logger.Info("Inbound.ActivateByRef", new
            {
                UserId = _userId,
                SessionId = _sessionId,
                InboundRef = inboundRef,
                ResultCode = code,
                Success = true
            });
        }
        else
        {
            _logger.Warn("Inbound.ActivateByRef", new
            {
                UserId = _userId,
                SessionId = _sessionId,
                InboundRef = inboundRef,
                ResultCode = code,
                Success = false
            });
        }

        return finalResult;
    }

    // --------------------------------------------------
    // Resolve inbound ID from reference
    // --------------------------------------------------

    private int ResolveInboundId(SqlConnection connection, string inboundRef)
    {
        using var cmd = connection.CreateCommand();
        cmd.CommandText = @"
            SELECT inbound_id
            FROM deliveries.inbound_deliveries
            WHERE inbound_ref = @ref";

        cmd.Parameters.AddWithValue("@ref", inboundRef);

        var result = cmd.ExecuteScalar();

        if (result == null)
            return -1;

        return (int)result;
    }

    // --------------------------------------------------
    // Receive inbound line (SSCC / manual)
    // --------------------------------------------------

    public OperationResult ReceiveInboundLine(
    int inboundLineId,
    int receivedQty,
    string stagingBinCode,
    int? inboundExpectedUnitId = null,   // NEW
    string? externalRef = null,
    string? batchNumber = null,
    DateTime? bestBeforeDate = null,
    Guid? claimToken = null)
    {
        using var connection =
            _factory.CreateForCommand(_sessionId, _userId);

        using var command = connection.CreateCommand();
        command.CommandText = "deliveries.usp_receive_inbound_line";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.AddWithValue("@inbound_line_id", inboundLineId);
        command.Parameters.AddWithValue("@received_qty", receivedQty);
        command.Parameters.AddWithValue("@staging_bin_code", stagingBinCode);
        command.Parameters.AddWithValue("@external_ref",
            (object?)externalRef ?? DBNull.Value);
        command.Parameters.AddWithValue("@batch_number",
            (object?)batchNumber ?? DBNull.Value);
        command.Parameters.AddWithValue("@best_before_date",
            (object?)bestBeforeDate ?? DBNull.Value);
        command.Parameters.AddWithValue("@inbound_expected_unit_id",
            (object?)inboundExpectedUnitId ?? DBNull.Value);

        // NEW: claim token
        command.Parameters.AddWithValue("@claim_token",
            (object?)claimToken ?? DBNull.Value);

        command.Parameters.AddWithValue("@user_id", _userId);
        command.Parameters.AddWithValue("@session_id", _sessionId);

        bool success;
        string code;

        using (var reader = command.ExecuteReader())
        {
            if (!reader.Read())
            {
                code = "ERRINBL99";
                var message = _messageResolver.Resolve(code);
                var result = OperationResult.Create(false, code, message);

                _logger.Warn("Inbound.ReceiveLine", new
                {
                    UserId = _userId,
                    SessionId = _sessionId,
                    InboundLineId = inboundLineId,
                    ExternalRef = externalRef,
                    Bin = stagingBinCode,
                    ResultCode = code,
                    Success = false
                });

                return result;
            }

            success = reader.GetBoolean(0);
            code = reader.GetString(1);
        }

        var friendlyMessage = _messageResolver.Resolve(code);

        _logger.Info("Inbound.ReceiveLine", new
        {
            UserId = _userId,
            SessionId = _sessionId,
            InboundLineId = inboundLineId,
            ExternalRef = externalRef,
            Bin = stagingBinCode,
            ResultCode = code,
            Success = success
        });

        return OperationResult.Create(success, code, friendlyMessage);
    }
}