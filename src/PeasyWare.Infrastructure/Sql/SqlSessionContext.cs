using Microsoft.Data.SqlClient;

internal static class SqlSessionContext
{
    public static void Apply(
        SqlConnection connection,
        Guid sessionId,
        int userId)
    {
        using var cmd = connection.CreateCommand();
        cmd.CommandText = @"
            EXEC sys.sp_set_session_context 
                @key = N'session_id',
                @value = @sessionId;

            EXEC sys.sp_set_session_context 
                @key = N'user_id',
                @value = @userId;
        ";

        cmd.Parameters.AddWithValue("@sessionId", sessionId);
        cmd.Parameters.AddWithValue("@userId", userId);

        cmd.ExecuteNonQuery();
    }
}
