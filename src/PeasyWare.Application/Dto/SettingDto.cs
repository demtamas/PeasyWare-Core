public class SettingDto
{
    // Identity
    public string SettingName { get; set; } = "";

    public string? DisplayName { get; set; }

    public string? Category { get; set; }

    public string? CategoryName { get; set; }

    public int CategoryOrder { get; set; }

    public int DisplayOrder { get; set; }

    // Value
    public string? SettingValue { get; set; }

    public string DataType { get; set; } = "";

    // Validation metadata
    public string? ValidationRule { get; set; }

    public bool IsBoolean { get; set; }

    public bool IsEnum { get; set; }

    public bool IsRange { get; set; }

    public int? RangeMin { get; set; }

    public int? RangeMax { get; set; }

    public bool RequiresRestart { get; set; }

    // Description / flags
    public string? Description { get; set; }

    public bool IsSensitive { get; set; }

    // Audit
    public DateTime CreatedAt { get; set; }

    public int? CreatedBy { get; set; }

    public DateTime? UpdatedAt { get; set; }

    public string? UpdatedByUsername { get; set; }
}