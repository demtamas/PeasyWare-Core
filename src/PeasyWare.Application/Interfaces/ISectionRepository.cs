using PeasyWare.Application.Dto;

namespace PeasyWare.Application.Interfaces;

public interface ISectionRepository
{
    // Query
    IReadOnlyList<SectionDto> GetSections(bool includeInactive = false);

    // Command
    OperationResult CreateSection(string sectionCode, string sectionName, string? description = null);
    OperationResult UpdateSection(string sectionCode, string? sectionName = null, string? description = null, bool clearDesc = false);
    OperationResult DeactivateSection(string sectionCode);
    OperationResult ReactivateSection(string sectionCode);
}
