using Microsoft.Data.SqlClient;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Infrastructure.Sql;
using System.Data;

namespace PeasyWare.Infrastructure.Repositories;

public sealed class SqlShipmentManifestRepository : IShipmentManifestRepository
{
    private readonly SqlConnectionFactory _factory;
    private readonly SessionContext       _session;

    public SqlShipmentManifestRepository(SqlConnectionFactory factory, SessionContext session)
    {
        _factory = factory;
        _session = session;
    }

    public ShipmentManifestDto? GetManifest(string shipmentRef)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = """
            SELECT
                shipment_ref, shipment_status, vehicle_ref,
                haulier_name, customer_name,
                delivery_line_1, delivery_city, delivery_postal_code, delivery_country,
                actual_departure,
                sscc, sku_code, sku_description,
                batch_number,
                CONVERT(NVARCHAR(10), best_before_date, 103) AS best_before,
                quantity, uom_code, weight_per_unit, total_weight_kg, order_ref, picked_from_bin
            FROM outbound.v_shipment_manifest
            WHERE shipment_ref = @ref
            ORDER BY order_ref, sku_code, sscc
            """;

        command.Parameters.Add(new SqlParameter("@ref", SqlDbType.NVarChar, 50) { Value = shipmentRef });

        using var reader = command.ExecuteReader();

        ShipmentManifestDto? header = null;
        var lines = new List<ShipmentManifestLineDto>();

        while (reader.Read())
        {
            // Build header from first row
            header ??= new ShipmentManifestDto
            {
                ShipmentRef        = reader.GetString(reader.GetOrdinal("shipment_ref")),
                ShipmentStatus     = reader.GetString(reader.GetOrdinal("shipment_status")),
                VehicleRef         = Str(reader, "vehicle_ref"),
                HaulierName        = Str(reader, "haulier_name"),
                CustomerName       = Str(reader, "customer_name"),
                DeliveryLine1      = Str(reader, "delivery_line_1"),
                DeliveryCity       = Str(reader, "delivery_city"),
                DeliveryPostalCode = Str(reader, "delivery_postal_code"),
                DeliveryCountry    = Str(reader, "delivery_country"),
                ActualDeparture    = reader.IsDBNull(reader.GetOrdinal("actual_departure"))
                                     ? null
                                     : reader.GetDateTime(reader.GetOrdinal("actual_departure"))
            };

            lines.Add(new ShipmentManifestLineDto
            {
                Sscc           = reader.GetString(reader.GetOrdinal("sscc")),
                SkuCode        = reader.GetString(reader.GetOrdinal("sku_code")),
                SkuDescription = reader.GetString(reader.GetOrdinal("sku_description")),
                BatchNumber    = Str(reader, "batch_number"),
                BestBefore     = Str(reader, "best_before"),
                Quantity       = reader.GetInt32(reader.GetOrdinal("quantity")),
                UomCode        = Str(reader, "uom_code"),
                WeightPerUnit  = reader.IsDBNull(reader.GetOrdinal("weight_per_unit"))  ? null : reader.GetDecimal(reader.GetOrdinal("weight_per_unit")),
                TotalWeightKg  = reader.IsDBNull(reader.GetOrdinal("total_weight_kg"))  ? null : reader.GetDecimal(reader.GetOrdinal("total_weight_kg")),
                OrderRef       = Str(reader, "order_ref"),
                PickedFromBin  = Str(reader, "picked_from_bin")
            });
        }

        if (header is null) return null;

        return new ShipmentManifestDto
        {
            ShipmentRef        = header.ShipmentRef,
            ShipmentStatus     = header.ShipmentStatus,
            VehicleRef         = header.VehicleRef,
            HaulierName        = header.HaulierName,
            CustomerName       = header.CustomerName,
            DeliveryLine1      = header.DeliveryLine1,
            DeliveryCity       = header.DeliveryCity,
            DeliveryPostalCode = header.DeliveryPostalCode,
            DeliveryCountry    = header.DeliveryCountry,
            ActualDeparture    = header.ActualDeparture,
            TotalPallets       = lines.Count,
            TotalUnits         = lines.Sum(l => l.Quantity),
            TotalWeightKg      = lines.Sum(l => l.TotalWeightKg ?? 0m),
            Lines              = lines
        };
    }

    private static string? Str(SqlDataReader r, string col) =>
        r.IsDBNull(r.GetOrdinal(col)) ? null : r.GetString(r.GetOrdinal(col));
}
