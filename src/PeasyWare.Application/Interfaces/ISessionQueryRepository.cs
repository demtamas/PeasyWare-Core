using PeasyWare.Application.DTOs;
using System;
using System.Collections.Generic;
using System.Text;

namespace PeasyWare.Application.Interfaces;

public interface ISessionQueryRepository
{
    IReadOnlyList<ActiveSessionDto> GetActiveSessions();
}


