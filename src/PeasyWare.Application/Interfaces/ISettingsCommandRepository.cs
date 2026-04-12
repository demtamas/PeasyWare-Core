using PeasyWare.Application;

public interface ISettingsCommandRepository
{
    OperationResult UpdateSetting(
        string settingName,
        string settingValue);
}