public interface ISettingsQueryRepository
{
    IEnumerable<SettingDto> GetSettings();
}