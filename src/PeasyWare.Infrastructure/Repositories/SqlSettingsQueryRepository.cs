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
/// QUERY repository for system settings.
/// Read-only, uses SessionContext for tracing.
/// </summary>
public sealed class SqlSettingsQueryRepository : ISettingsQueryRepository
{
    private readonly SqlConnectionFactory _factory;
    private readonly SessionContext _session;

    public SqlSettingsQueryRepository(
        SqlConnectionFactory factory,
        SessionContext session)
    {
        _factory = factory ?? throw new ArgumentNullException(nameof(factory));
        _session = session ?? throw new ArgumentNullException(nameof(session));
    }

    public IEnumerable<SettingDto> GetSettings()
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command = connection.CreateCommand();

        command.CommandText = "SELECT * FROM operations.v_settings";
        command.CommandType = CommandType.Text; // explicit for clarity

        using var reader = command.ExecuteReader();

        var ordSettingName = reader.GetOrdinal("setting_name");
        var ordDisplayName = reader.GetOrdinal("display_name");

        var ordCategory = reader.GetOrdinal("category");
        var ordCategoryName = reader.GetOrdinal("category_name");
        var ordCategoryOrder = reader.GetOrdinal("category_order");

        var ordDisplayOrder = reader.GetOrdinal("display_order");

        var ordSettingValue = reader.GetOrdinal("setting_value");
        var ordDataType = reader.GetOrdinal("data_type");

        var ordValidationRule = reader.GetOrdinal("validation_rule");

        var ordDescription = reader.GetOrdinal("description");
        var ordIsSensitive = reader.GetOrdinal("is_sensitive");
        var ordRequiresRestart = reader.GetOrdinal("requires_restart");

        var ordCreatedAt = reader.GetOrdinal("created_at");
        var ordCreatedBy = reader.GetOrdinal("created_by");

        var ordUpdatedAt = reader.GetOrdinal("updated_at");
        var ordUpdatedByUsername = reader.GetOrdinal("updated_by_username");

        var ordIsBoolean = reader.GetOrdinal("is_boolean");
        var ordIsEnum = reader.GetOrdinal("is_enum");
        var ordIsRange = reader.GetOrdinal("is_range");

        var ordRangeMin = reader.GetOrdinal("range_min");
        var ordRangeMax = reader.GetOrdinal("range_max");

        while (reader.Read())
        {
            yield return new SettingDto
            {
                SettingName = reader.GetString(ordSettingName),
                DisplayName = reader.IsDBNull(ordDisplayName) ? null : reader.GetString(ordDisplayName),

                Category = reader.IsDBNull(ordCategory) ? null : reader.GetString(ordCategory),
                CategoryName = reader.IsDBNull(ordCategoryName) ? null : reader.GetString(ordCategoryName),
                CategoryOrder = reader.GetInt32(ordCategoryOrder),

                DisplayOrder = reader.GetInt32(ordDisplayOrder),

                SettingValue = reader.IsDBNull(ordSettingValue) ? null : reader.GetString(ordSettingValue),
                DataType = reader.GetString(ordDataType),
                ValidationRule = reader.IsDBNull(ordValidationRule) ? null : reader.GetString(ordValidationRule),

                Description = reader.IsDBNull(ordDescription) ? null : reader.GetString(ordDescription),
                IsSensitive = reader.GetBoolean(ordIsSensitive),
                RequiresRestart = reader.GetBoolean(ordRequiresRestart),

                CreatedAt = reader.GetDateTime(ordCreatedAt),
                CreatedBy = reader.IsDBNull(ordCreatedBy) ? null : reader.GetInt32(ordCreatedBy),

                UpdatedAt = reader.IsDBNull(ordUpdatedAt) ? null : reader.GetDateTime(ordUpdatedAt),
                UpdatedByUsername = reader.IsDBNull(ordUpdatedByUsername) ? null : reader.GetString(ordUpdatedByUsername),

                IsBoolean = reader.GetBoolean(ordIsBoolean),
                IsEnum = reader.GetBoolean(ordIsEnum),
                IsRange = reader.GetBoolean(ordIsRange),

                RangeMin = reader.IsDBNull(ordRangeMin) ? null : reader.GetInt32(ordRangeMin),
                RangeMax = reader.IsDBNull(ordRangeMax) ? null : reader.GetInt32(ordRangeMax)
            };
        }
    }
}