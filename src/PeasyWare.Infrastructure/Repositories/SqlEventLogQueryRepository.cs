using Microsoft.Data.SqlClient;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Infrastructure.Sql;
using System.Data;

namespace PeasyWare.Infrastructure.Repositories;

public sealed class SqlEventLogQueryRepository : IEventLogQueryRepository
{
    private readonly SqlConnectionFactory _factory;
    private readonly SessionContext       _session;

    public SqlEventLogQueryRepository(SqlConnectionFactory factory, SessionContext session)
    {
        _factory = factory;
        _session = session;
    }

    public IReadOnlyList<EventLogDto> GetEventLog(
        string?   actionFilter   = null,
        string?   levelFilter    = null,
        string?   usernameFilter = null,
        DateTime? fromDate       = null,
        DateTime? toDate         = null,
        int       top            = 500)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        var where = new List<string>();
        if (actionFilter   is not null) where.Add("action LIKE @action");
        if (levelFilter    is not null) where.Add("level = @level");
        if (usernameFilter is not null) where.Add("username LIKE @username");
        if (fromDate       is not null) where.Add("occurred_at >= @from_date");
        if (toDate         is not null) where.Add("occurred_at <  @to_date");

        command.CommandText = $"""
            SELECT TOP (@top)
                trace_id, occurred_at, level, action,
                user_id, username, source_app, source_client,
                result_code, success, payload_json
            FROM audit.v_event_log
            {(where.Count > 0 ? "WHERE " + string.Join(" AND ", where) : "")}
            ORDER BY occurred_at DESC
            """;

        command.Parameters.Add(new SqlParameter("@top", SqlDbType.Int) { Value = top });

        if (actionFilter   is not null)
            command.Parameters.Add(new SqlParameter("@action",   SqlDbType.NVarChar, 200) { Value = $"%{actionFilter}%" });
        if (levelFilter    is not null)
            command.Parameters.Add(new SqlParameter("@level",    SqlDbType.NVarChar, 10)  { Value = levelFilter });
        if (usernameFilter is not null)
            command.Parameters.Add(new SqlParameter("@username", SqlDbType.NVarChar, 100) { Value = $"%{usernameFilter}%" });
        if (fromDate       is not null)
            command.Parameters.Add(new SqlParameter("@from_date", SqlDbType.DateTime2)    { Value = fromDate.Value });
        if (toDate         is not null)
            command.Parameters.Add(new SqlParameter("@to_date",   SqlDbType.DateTime2)    { Value = toDate.Value.AddDays(1) });

        using var reader = command.ExecuteReader();
        var results = new List<EventLogDto>();

        while (reader.Read())
        {
            results.Add(new EventLogDto
            {
                TraceId      = reader.GetInt64(reader.GetOrdinal("trace_id")),
                OccurredAt   = reader.GetDateTime(reader.GetOrdinal("occurred_at")),
                Level        = reader.GetString(reader.GetOrdinal("level")),
                Action       = reader.GetString(reader.GetOrdinal("action")),
                UserId       = reader.IsDBNull(reader.GetOrdinal("user_id"))       ? null : reader.GetInt32(reader.GetOrdinal("user_id")),
                Username     = reader.IsDBNull(reader.GetOrdinal("username"))      ? null : reader.GetString(reader.GetOrdinal("username")),
                SourceApp    = reader.IsDBNull(reader.GetOrdinal("source_app"))    ? null : reader.GetString(reader.GetOrdinal("source_app")),
                SourceClient = reader.IsDBNull(reader.GetOrdinal("source_client")) ? null : reader.GetString(reader.GetOrdinal("source_client")),
                ResultCode   = reader.IsDBNull(reader.GetOrdinal("result_code"))   ? null : reader.GetString(reader.GetOrdinal("result_code")),
                Success      = reader.IsDBNull(reader.GetOrdinal("success"))       ? null : reader.GetString(reader.GetOrdinal("success")),
                PayloadJson  = reader.IsDBNull(reader.GetOrdinal("payload_json"))  ? null : reader.GetString(reader.GetOrdinal("payload_json"))
            });
        }

        return results;
    }

    public IReadOnlyList<UserActivityDto> GetUserActivity(
        string?   usernameFilter = null,
        DateTime? fromDate       = null,
        DateTime? toDate         = null,
        int       top            = 500)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        var where = new List<string>();
        if (usernameFilter is not null) where.Add("(subject_username LIKE @username OR actor_username LIKE @username)");
        if (fromDate       is not null) where.Add("occurred_at >= @from_date");
        if (toDate         is not null) where.Add("occurred_at <  @to_date");

        command.CommandText = $"""
            SELECT TOP (@top)
                event_id, occurred_at, source, event_type,
                subject_user_id, subject_username,
                actor_user_id,   actor_username,
                detail, result_code, source_app
            FROM audit.v_user_activity
            {(where.Count > 0 ? "WHERE " + string.Join(" AND ", where) : "")}
            ORDER BY occurred_at DESC
            """;

        command.Parameters.Add(new SqlParameter("@top", SqlDbType.Int) { Value = top });

        if (usernameFilter is not null)
            command.Parameters.Add(new SqlParameter("@username",  SqlDbType.NVarChar, 100) { Value = $"%{usernameFilter}%" });
        if (fromDate is not null)
            command.Parameters.Add(new SqlParameter("@from_date", SqlDbType.DateTime2) { Value = fromDate.Value });
        if (toDate is not null)
            command.Parameters.Add(new SqlParameter("@to_date",   SqlDbType.DateTime2) { Value = toDate.Value.AddDays(1) });

        using var reader = command.ExecuteReader();
        var results = new List<UserActivityDto>();

        while (reader.Read())
        {
            results.Add(new UserActivityDto
            {
                EventId         = reader.GetInt64(reader.GetOrdinal("event_id")),
                OccurredAt      = reader.GetDateTime(reader.GetOrdinal("occurred_at")),
                Source          = reader.GetString(reader.GetOrdinal("source")),
                EventType       = reader.GetString(reader.GetOrdinal("event_type")),
                SubjectUserId   = reader.IsDBNull(reader.GetOrdinal("subject_user_id"))  ? null : reader.GetInt32(reader.GetOrdinal("subject_user_id")),
                SubjectUsername = reader.IsDBNull(reader.GetOrdinal("subject_username")) ? null : reader.GetString(reader.GetOrdinal("subject_username")),
                ActorUserId     = reader.IsDBNull(reader.GetOrdinal("actor_user_id"))    ? null : reader.GetInt32(reader.GetOrdinal("actor_user_id")),
                ActorUsername   = reader.IsDBNull(reader.GetOrdinal("actor_username"))   ? null : reader.GetString(reader.GetOrdinal("actor_username")),
                Detail          = reader.IsDBNull(reader.GetOrdinal("detail"))           ? null : reader.GetString(reader.GetOrdinal("detail")),
                ResultCode      = reader.IsDBNull(reader.GetOrdinal("result_code"))      ? null : reader.GetString(reader.GetOrdinal("result_code")),
                SourceApp       = reader.IsDBNull(reader.GetOrdinal("source_app"))       ? null : reader.GetString(reader.GetOrdinal("source_app"))
            });
        }

        return results;
    }
}
