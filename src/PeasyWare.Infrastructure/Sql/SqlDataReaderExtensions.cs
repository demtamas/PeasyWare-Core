using Microsoft.Data.SqlClient;
using System;

namespace PeasyWare.Infrastructure.Sql;

public static class SqlDataReaderExtensions
{
    public static DateTime? GetNullableDateTime(this SqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        return reader.IsDBNull(ordinal)
            ? null
            : reader.GetDateTime(ordinal);
    }

    public static string? GetNullableString(this SqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        return reader.IsDBNull(ordinal)
            ? null
            : reader.GetString(ordinal);
    }

    public static int? GetNullableInt32(this SqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        return reader.IsDBNull(ordinal)
            ? null
            : reader.GetInt32(ordinal);
    }

    public static bool? GetNullableBoolean(this SqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        return reader.IsDBNull(ordinal)
            ? null
            : reader.GetBoolean(ordinal);
    }
}
