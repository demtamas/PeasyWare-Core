using PeasyWare.Application.Dto;

namespace PeasyWare.Application.Interfaces;

public interface IShipmentManifestRepository
{
    ShipmentManifestDto? GetManifest(string shipmentRef);
}
