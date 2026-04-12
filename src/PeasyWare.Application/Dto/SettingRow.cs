public class SettingRow
{
    public bool IsCategoryHeader { get; set; }

    public string? CategoryName { get; set; }

    public SettingDto? Setting { get; set; }

    public string DisplayName => Setting?.DisplayName ?? "";

    public string? SettingValue => Setting?.SettingValue;

    public string DataType => Setting?.DataType ?? "";

    public string? Description => Setting?.Description;

    public string? UpdatedByUsername => Setting?.UpdatedByUsername;

    public DateTime? UpdatedAt => Setting?.UpdatedAt;
}