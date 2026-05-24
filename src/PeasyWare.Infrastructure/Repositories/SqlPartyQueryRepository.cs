using Microsoft.Data.SqlClient;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Infrastructure.Sql;
using System.Data;

namespace PeasyWare.Infrastructure.Repositories;

public sealed class SqlPartyQueryRepository : IPartyQueryRepository
{
    private readonly SqlConnectionFactory _factory;
    private readonly SessionContext       _session;

    public SqlPartyQueryRepository(SqlConnectionFactory factory, SessionContext session)
    {
        _factory = factory;
        _session = session;
    }

    private const string SelectCols = """
        SELECT party_id, party_code, legal_name, display_name,
               country_code, tax_id, is_active, roles,
               is_supplier, is_customer, is_haulier, is_owner, is_warehouse,
               created_at, created_by_username,
               updated_at, updated_by_username
        FROM core.v_parties
        """;

    public IReadOnlyList<PartyDto> GetParties(string? roleFilter = null, bool includeInactive = false)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        var where = new List<string>();
        if (!includeInactive) where.Add("is_active = 1");
        if (roleFilter is not null) where.Add($"is_{roleFilter.ToLowerInvariant()} = 1");

        command.CommandText = SelectCols
            + (where.Count > 0 ? " WHERE " + string.Join(" AND ", where) : "")
            + " ORDER BY display_name";

        return ReadList(command);
    }

    public PartyDto? GetParty(int partyId)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = SelectCols + " WHERE party_id = @party_id";
        command.Parameters.Add(new SqlParameter("@party_id", SqlDbType.Int) { Value = partyId });

        return ReadList(command).FirstOrDefault();
    }

    private static List<PartyDto> ReadList(SqlCommand command)
    {
        using var reader = command.ExecuteReader();
        var results = new List<PartyDto>();

        while (reader.Read())
        {
            results.Add(new PartyDto
            {
                PartyId           = reader.GetInt32(reader.GetOrdinal("party_id")),
                PartyCode         = reader.GetString(reader.GetOrdinal("party_code")),
                LegalName         = reader.GetString(reader.GetOrdinal("legal_name")),
                DisplayName       = reader.GetString(reader.GetOrdinal("display_name")),
                CountryCode       = reader.IsDBNull(reader.GetOrdinal("country_code"))        ? null : reader.GetString(reader.GetOrdinal("country_code")),
                TaxId             = reader.IsDBNull(reader.GetOrdinal("tax_id"))              ? null : reader.GetString(reader.GetOrdinal("tax_id")),
                IsActive          = reader.GetBoolean(reader.GetOrdinal("is_active")),
                Roles             = reader.GetString(reader.GetOrdinal("roles")),
                IsSupplier        = reader.GetBoolean(reader.GetOrdinal("is_supplier")),
                IsCustomer        = reader.GetBoolean(reader.GetOrdinal("is_customer")),
                IsHaulier         = reader.GetBoolean(reader.GetOrdinal("is_haulier")),
                IsOwner           = reader.GetBoolean(reader.GetOrdinal("is_owner")),
                IsWarehouse       = reader.GetBoolean(reader.GetOrdinal("is_warehouse")),
                CreatedAt         = reader.IsDBNull(reader.GetOrdinal("created_at"))          ? null : reader.GetDateTime(reader.GetOrdinal("created_at")),
                CreatedByUsername = reader.IsDBNull(reader.GetOrdinal("created_by_username")) ? null : reader.GetString(reader.GetOrdinal("created_by_username")),
                UpdatedAt         = reader.IsDBNull(reader.GetOrdinal("updated_at"))          ? null : reader.GetDateTime(reader.GetOrdinal("updated_at")),
                UpdatedByUsername = reader.IsDBNull(reader.GetOrdinal("updated_by_username")) ? null : reader.GetString(reader.GetOrdinal("updated_by_username"))
            });
        }

        return results;
    }
}
