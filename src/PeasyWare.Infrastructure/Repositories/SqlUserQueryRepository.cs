using Microsoft.Data.SqlClient;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Infrastructure.Sql;
using System;
using System.Collections.Generic;
using System.Data;

namespace PeasyWare.Infrastructure.Repositories;

/// <summary>
/// QUERY repository for users (read-only).
///
/// Responsibilities:
/// - Retrieve user data
/// - Uses SessionContext for DB tracing (SESSION_CONTEXT)
/// - No session validation
/// - No side effects
/// </summary>
public sealed class SqlUserQueryRepository : IUserQueryRepository
{
    private readonly SqlConnectionFactory _factory;
    private readonly SessionContext _session;

    public SqlUserQueryRepository(
        SqlConnectionFactory factory,
        SessionContext session)
    {
        _factory = factory ?? throw new ArgumentNullException(nameof(factory));
        _session = session ?? throw new ArgumentNullException(nameof(session));
    }

    // --------------------------------------------------
    // Users
    // --------------------------------------------------

    public IReadOnlyList<UserSummaryDto> GetUsers(string? search = null)
    {
        var result = new List<UserSummaryDto>();

        using var connection = _factory.CreateForCommand(_session);
        using var command = connection.CreateCommand();

        command.CommandText = """
            SELECT
                id,
                username,
                display_name,
                email,
                role_name,
                is_online,
                last_last_seen,
                is_active,
                must_change_password,
                failed_attempts,
                lockout_until,
                password_expires_at,
                created_at,
                created_by,
                updated_at,
                updated_by
            FROM auth.v_users_admin
            WHERE (
                @search IS NULL
                OR username LIKE '%' + @search + '%'
                OR display_name LIKE '%' + @search + '%'
            )
            ORDER BY username;
        """;

        command.Parameters.Add(
            new SqlParameter("@search", SqlDbType.NVarChar, 100)
            {
                Value = (object?)search ?? DBNull.Value
            });

        using var reader = command.ExecuteReader();

        while (reader.Read())
        {
            result.Add(new UserSummaryDto
            {
                UserId = reader.GetInt32(reader.GetOrdinal("id")),
                Username = reader.GetString(reader.GetOrdinal("username")),
                DisplayName = reader.GetString(reader.GetOrdinal("display_name")),

                Email = reader.GetNullableString("email"),
                RoleName = reader.GetString(reader.GetOrdinal("role_name")),

                IsActive = reader.GetBoolean(reader.GetOrdinal("is_active")),
                IsOnline = reader.GetBoolean(reader.GetOrdinal("is_online")),

                LastLastSeen = reader.GetNullableDateTime("last_last_seen"),

                MustChangePassword = reader.GetBoolean(reader.GetOrdinal("must_change_password")),
                FailedAttempts = reader.GetInt32(reader.GetOrdinal("failed_attempts")),
                LockoutUntil = reader.GetNullableDateTime("lockout_until"),
                PasswordExpiresAt = reader.GetNullableDateTime("password_expires_at"),

                CreatedAt = reader.GetDateTime(reader.GetOrdinal("created_at")),
                CreatedByUserId = reader.GetNullableInt32("created_by"),

                UpdatedAt = reader.GetNullableDateTime("updated_at"),
                UpdatedByUserId = reader.GetNullableInt32("updated_by")
            });
        }

        return result;
    }

    // --------------------------------------------------
    // Roles
    // --------------------------------------------------

    public IEnumerable<RoleDto> GetRoles()
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "auth.usp_roles_get";
        command.CommandType = CommandType.StoredProcedure;

        using var reader = command.ExecuteReader();

        var roles = new List<RoleDto>();

        while (reader.Read())
        {
            roles.Add(new RoleDto
            {
                RoleName     = reader.GetString(reader.GetOrdinal("RoleName")),
                Description  = reader.GetString(reader.GetOrdinal("Description")),
                IsSystemRole = false  // SP only returns non-system roles
            });
        }

        return roles;
    }
}