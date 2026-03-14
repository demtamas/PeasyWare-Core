using Microsoft.Data.SqlClient;

namespace PeasyWare.Application.Interfaces;

public interface IErrorMessageResolver
{
    string Resolve(string errorCode);
}