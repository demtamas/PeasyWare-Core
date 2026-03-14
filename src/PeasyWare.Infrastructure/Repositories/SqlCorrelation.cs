using Microsoft.Data.SqlClient;
using PeasyWare.Infrastructure.Logging;
using System;
using System.Collections.Generic;
using System.Data;
using System.Text;

namespace PeasyWare.Infrastructure.Repositories
{
    internal static class SqlCorrelation
    {
        public static void Add(
            SqlCommand command,
            string parameterName = "@correlation_id")
        {
            command.Parameters.Add(
                parameterName,
                SqlDbType.VarChar,
                32
            ).Value =
                CorrelationContext.Current != null
                    ? CorrelationContext.Current.Value.ToString("N")
                    : (object)DBNull.Value;
        }
    }

}
