using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Infrastructure.Sql;
using PeasyWare.Infrastructure.Errors;
using PeasyWare.Application.Logging;
using System.Data;
using Microsoft.Data.SqlClient;
using PeasyWare.Application;

namespace PeasyWare.Infrastructure.Repositories;

public sealed class SqlWarehouseTaskCommandRepository
{
    private readonly SqlConnectionFactory _connectionFactory;
    private readonly Guid _sessionId;
    private readonly int _userId;
    private readonly IErrorMessageResolver _errorResolver;
    private readonly ILogger _logger;

    public SqlWarehouseTaskCommandRepository(
        SqlConnectionFactory connectionFactory,
        Guid sessionId,
        int userId,
        IErrorMessageResolver errorResolver,
        ILogger logger)
        {
            _connectionFactory = connectionFactory;
            _sessionId = sessionId;
            _userId = userId;
            _errorResolver = errorResolver;
            _logger = logger;
        }

    // --------------------------------------------------------
    // Create Putaway Task
    // --------------------------------------------------------

    public PutawayTaskCreateResult CreatePutawayTask(int inventoryUnitId)
    {
        using var conn = _connectionFactory.Create();

        using var cmd = new SqlCommand(
            "warehouse.usp_putaway_create_task_for_unit",
            conn);

        cmd.CommandType = CommandType.StoredProcedure;

        cmd.Parameters.AddWithValue("@inventory_unit_id", inventoryUnitId);
        cmd.Parameters.AddWithValue("@user_id", _userId);
        cmd.Parameters.AddWithValue("@session_id", _sessionId);

        conn.Open();

        using var reader = cmd.ExecuteReader();

        if (!reader.Read())
            throw new InvalidOperationException("Unexpected empty response from putaway task creation.");

        var success = reader.GetBoolean(0);
        var resultCode = reader.GetString(1);

        if (!success)
        {
            return new PutawayTaskCreateResult
            {
                Success = false,
                ResultCode = resultCode,
                FriendlyMessage = _errorResolver.Resolve(resultCode)
            };
        }

        return new PutawayTaskCreateResult
        {
            Success = true,
            ResultCode = resultCode,
            TaskId = reader.GetInt32(2),
            DestinationBinCode = reader.GetString(3),
            FriendlyMessage = _errorResolver.Resolve(resultCode)
        };
    }

    // --------------------------------------------------------
    // Confirm Putaway Task
    // --------------------------------------------------------

    public OperationResult ConfirmPutawayTask(int taskId, string destination)
    {
        using var conn = _connectionFactory.Create();

        using var cmd = new SqlCommand(
            "warehouse.usp_putaway_confirm_task",
            conn);

        cmd.CommandType = CommandType.StoredProcedure;

        cmd.Parameters.AddWithValue("@task_id", taskId);
        cmd.Parameters.AddWithValue("@user_id", _userId);
        cmd.Parameters.AddWithValue("@session_id", _sessionId);

        conn.Open();

        using var reader = cmd.ExecuteReader();

        if (!reader.Read())
            throw new InvalidOperationException(
                "Unexpected empty response from putaway confirmation.");

        var success = reader.GetBoolean(0);
        var resultCode = reader.GetString(1);

        var message = _errorResolver.Resolve(resultCode);

        return OperationResult.Create(
            success,
            resultCode,
            message);
    }
}