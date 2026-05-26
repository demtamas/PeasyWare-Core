using PeasyWare.Application.Dto;

namespace PeasyWare.Application.Interfaces;

public interface IEventLogQueryRepository
{
    IReadOnlyList<EventLogDto> GetEventLog(
        string?   actionFilter  = null,
        string?   levelFilter   = null,
        string?   usernameFilter = null,
        DateTime? fromDate      = null,
        DateTime? toDate        = null,
        int       top           = 500);

    IReadOnlyList<UserActivityDto> GetUserActivity(
        string?   usernameFilter = null,
        DateTime? fromDate       = null,
        DateTime? toDate         = null,
        int       top            = 500);
}
