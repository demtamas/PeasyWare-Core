using PeasyWare.Application.Dto;

namespace PeasyWare.Application.Interfaces;

public interface IStorageTypeRepository
{
    // Query
    IReadOnlyList<StorageTypeDto> GetStorageTypes(bool includeInactive = false);

    // Command
    OperationResult CreateStorageType(string storageTypeCode, string storageTypeName, string? description = null);
    OperationResult UpdateStorageType(string storageTypeCode, string? storageTypeName = null, string? description = null, bool clearDesc = false);
    OperationResult DeactivateStorageType(string storageTypeCode);
    OperationResult ReactivateStorageType(string storageTypeCode);
    OperationResult DeleteStorageType(string storageTypeCode);
}
