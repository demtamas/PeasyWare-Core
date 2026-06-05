using PeasyWare.Application;

namespace PeasyWare.Application.Interfaces;

public interface ILocationCommandRepository
{
    OperationResult LockBin(string binCode, string? reason = null);
    OperationResult UnlockBin(string binCode);

    OperationResult CreateBin(
        string  binCode,
        string  storageTypeCode,
        string? zoneCode        = null,
        string? sectionCode     = null,
        int     capacity        = 1,
        string? notes           = null);

    OperationResult CreateBinsBulk(
        string  prefix,
        string  storageTypeCode,
        int     rowFrom,
        int     rowTo,
        char    colFrom         = 'A',
        char    colTo           = 'A',
        int     depthFrom       = 1,
        int     depthTo         = 1,
        string? zoneCode        = null,
        string? sectionCode     = null,
        int     capacity        = 1);

    OperationResult UpdateBin(
        string  binCode,
        string? newBinCode       = null,
        string? storageTypeCode  = null,
        string? zoneCode         = null,
        string? sectionCode      = null,
        int?    capacity         = null,
        string? notes            = null,
        bool    clearNotes       = false);

    OperationResult DeactivateBin(string binCode, string? reason = null);
    OperationResult ReactivateBin(string binCode);
    OperationResult ActivateBins(IEnumerable<string> binCodes);
    OperationResult AssignBinsToSection(string sectionCode, IEnumerable<string> binCodes);
    OperationResult AssignBinsToZone(string zoneCode, IEnumerable<string> binCodes);
}
