using PeasyWare.Application.Dto;
using System;
using System.Collections.Generic;
using System.Text;

namespace PeasyWare.Application.Interfaces
{
    public interface ISessionDetailsRepository
    {
        SessionDetailsDto? GetSessionDetails(Guid sessionId);
    }
}
