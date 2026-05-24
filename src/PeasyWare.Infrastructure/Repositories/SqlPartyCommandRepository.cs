using Microsoft.Data.SqlClient;
using PeasyWare.Application;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Infrastructure.Sql;
using System.Data;

namespace PeasyWare.Infrastructure.Repositories;

public sealed class SqlPartyCommandRepository : IPartyCommandRepository
{
    private readonly SqlConnectionFactory _factory;
    private readonly SessionContext       _session;

    public SqlPartyCommandRepository(SqlConnectionFactory factory, SessionContext session)
    {
        _factory = factory;
        _session = session;
    }

    public OperationResult CreateParty(
        string  partyCode,
        string  legalName,
        string  displayName,
        string? countryCode = null,
        string? taxId       = null,
        string? roles       = null)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "core.usp_create_party";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add(new SqlParameter("@party_code",   SqlDbType.NVarChar, 50)  { Value = partyCode });
        command.Parameters.Add(new SqlParameter("@legal_name",   SqlDbType.NVarChar, 200) { Value = legalName });
        command.Parameters.Add(new SqlParameter("@display_name", SqlDbType.NVarChar, 200) { Value = displayName });
        command.Parameters.Add(new SqlParameter("@country_code", SqlDbType.Char, 2)       { Value = (object?)countryCode ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@tax_id",       SqlDbType.NVarChar, 50)  { Value = (object?)taxId       ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@roles",        SqlDbType.NVarChar, 500) { Value = (object?)roles       ?? DBNull.Value });
        command.Parameters.AddWithValue("@user_id",    _session.UserId);
        command.Parameters.AddWithValue("@session_id", _session.SessionId);

        using var reader = command.ExecuteReader();
        if (!reader.Read()) return OperationResult.Create(false, "ERRPARTY99", "Unexpected error.");

        var success = reader.GetBoolean(reader.GetOrdinal("success"));
        var code    = reader.GetString(reader.GetOrdinal("result_code"));

        return OperationResult.Create(success, code,
            success ? "Party created successfully." : code switch
            {
                "ERRPARTY01" => "A party with this code already exists.",
                _            => "Unexpected error."
            });
    }

    public OperationResult UpdateParty(
        int     partyId,
        string  legalName,
        string  displayName,
        string? countryCode = null,
        string? taxId       = null,
        bool    isActive    = true,
        string? roles       = null)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "core.usp_update_party";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add(new SqlParameter("@party_id",     SqlDbType.Int)           { Value = partyId });
        command.Parameters.Add(new SqlParameter("@legal_name",   SqlDbType.NVarChar, 200) { Value = legalName });
        command.Parameters.Add(new SqlParameter("@display_name", SqlDbType.NVarChar, 200) { Value = displayName });
        command.Parameters.Add(new SqlParameter("@country_code", SqlDbType.Char, 2)       { Value = (object?)countryCode ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@tax_id",       SqlDbType.NVarChar, 50)  { Value = (object?)taxId       ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@is_active",    SqlDbType.Bit)           { Value = isActive });
        command.Parameters.Add(new SqlParameter("@roles",        SqlDbType.NVarChar, 500) { Value = (object?)roles       ?? DBNull.Value });
        command.Parameters.AddWithValue("@user_id",    _session.UserId);
        command.Parameters.AddWithValue("@session_id", _session.SessionId);

        using var reader = command.ExecuteReader();
        if (!reader.Read()) return OperationResult.Create(false, "ERRPARTY99", "Unexpected error.");

        var success = reader.GetBoolean(reader.GetOrdinal("success"));
        var code    = reader.GetString(reader.GetOrdinal("result_code"));

        return OperationResult.Create(success, code,
            success ? "Party updated successfully." : "Unexpected error.");
    }
}
