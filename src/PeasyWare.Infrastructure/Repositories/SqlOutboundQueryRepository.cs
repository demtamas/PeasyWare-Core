using Microsoft.Data.SqlClient;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Infrastructure.Sql;
using System;
using System.Collections.Generic;
using System.Data;

namespace PeasyWare.Infrastructure.Repositories;

public sealed class SqlOutboundQueryRepository : IOutboundQueryRepository
{
    private readonly SqlConnectionFactory _factory;
    private readonly SessionContext       _session;

    public SqlOutboundQueryRepository(
        SqlConnectionFactory factory,
        SessionContext       session)
    {
        _factory = factory ?? throw new ArgumentNullException(nameof(factory));
        _session = session ?? throw new ArgumentNullException(nameof(session));
    }

    // --------------------------------------------------
    // Orders ready to pick (ALLOCATED or PICKING)
    // --------------------------------------------------

    public IReadOnlyList<OutboundOrderSummaryDto> GetPickableOrders()
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = """
            SELECT
                o.outbound_order_id,
                o.order_ref,
                o.order_status_code,
                p.display_name          AS customer_name,
                CONVERT(NVARCHAR(10), o.required_date, 103) AS required_date,
                COUNT(l.outbound_line_id)                   AS total_lines,
                SUM(l.allocated_qty)                        AS total_allocated,
                SUM(l.ordered_qty)                          AS total_ordered
            FROM outbound.outbound_orders o
            JOIN core.parties p
                ON p.party_id = o.customer_party_id
            JOIN outbound.outbound_lines l
                ON l.outbound_order_id = o.outbound_order_id
               AND l.line_status_code <> 'CNL'
            WHERE o.order_status_code IN ('ALLOCATED','PICKING')
            GROUP BY
                o.outbound_order_id, o.order_ref, o.order_status_code,
                p.display_name, o.required_date
            ORDER BY o.required_date, o.order_ref
        """;

        using var reader = command.ExecuteReader();
        var results = new List<OutboundOrderSummaryDto>();
        while (reader.Read()) results.Add(ReadOrderSummary(reader));
        return results;
    }

    // --------------------------------------------------
    // Single order summary by ref
    // --------------------------------------------------

    public OutboundOrderSummaryDto? GetOrderSummary(string orderRef)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = """
            SELECT
                o.outbound_order_id,
                o.order_ref,
                o.order_status_code,
                p.display_name          AS customer_name,
                CONVERT(NVARCHAR(10), o.required_date, 103) AS required_date,
                COUNT(l.outbound_line_id)                   AS total_lines,
                SUM(l.allocated_qty)                        AS total_allocated,
                SUM(l.ordered_qty)                          AS total_ordered
            FROM outbound.outbound_orders o
            JOIN core.parties p
                ON p.party_id = o.customer_party_id
            JOIN outbound.outbound_lines l
                ON l.outbound_order_id = o.outbound_order_id
               AND l.line_status_code <> 'CNL'
            WHERE o.order_ref = @order_ref
            GROUP BY
                o.outbound_order_id, o.order_ref, o.order_status_code,
                p.display_name, o.required_date
        """;

        command.Parameters.Add(new SqlParameter("@order_ref", SqlDbType.NVarChar, 50) { Value = orderRef.Trim() });

        using var reader = command.ExecuteReader();
        return reader.Read() ? ReadOrderSummary(reader) : null;
    }

    // --------------------------------------------------
    // Allocations for an order
    // --------------------------------------------------

    public IReadOnlyList<OutboundAllocationDto> GetAllocationsForOrder(int outboundOrderId)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = """
            SELECT
                a.allocation_id,
                l.outbound_line_id,
                l.line_no,
                s.sku_code,
                s.sku_description,
                a.allocated_qty,
                l.ordered_qty,
                a.allocation_status,
                iu.external_ref         AS sscc,
                b.bin_code              AS source_bin_code,
                iu.batch_number,
                CONVERT(NVARCHAR(10), iu.best_before_date, 103) AS best_before_date
            FROM outbound.outbound_allocations a
            JOIN outbound.outbound_lines l    ON l.outbound_line_id   = a.outbound_line_id
            JOIN inventory.skus s             ON s.sku_id             = l.sku_id
            JOIN inventory.inventory_units iu ON iu.inventory_unit_id = a.inventory_unit_id
            JOIN inventory.inventory_placements ip ON ip.inventory_unit_id = iu.inventory_unit_id
            JOIN locations.bins b             ON b.bin_id             = ip.bin_id
            WHERE l.outbound_order_id  = @outbound_order_id
              AND a.allocation_status IN ('PENDING','CONFIRMED')
            ORDER BY l.line_no, b.bin_code
        """;

        command.Parameters.Add(new SqlParameter("@outbound_order_id", SqlDbType.Int) { Value = outboundOrderId });

        using var reader = command.ExecuteReader();
        var results = new List<OutboundAllocationDto>();

        while (reader.Read())
            results.Add(new OutboundAllocationDto
            {
                AllocationId     = reader.GetInt32(reader.GetOrdinal("allocation_id")),
                OutboundLineId   = reader.GetInt32(reader.GetOrdinal("outbound_line_id")),
                LineNo           = reader.GetInt32(reader.GetOrdinal("line_no")),
                SkuCode          = reader.GetString(reader.GetOrdinal("sku_code")),
                SkuDescription   = reader.GetString(reader.GetOrdinal("sku_description")),
                AllocatedQty     = reader.GetInt32(reader.GetOrdinal("allocated_qty")),
                OrderedQty       = reader.GetInt32(reader.GetOrdinal("ordered_qty")),
                AllocationStatus = reader.GetString(reader.GetOrdinal("allocation_status")),
                Sscc             = reader.IsDBNull(reader.GetOrdinal("sscc"))             ? string.Empty : reader.GetString(reader.GetOrdinal("sscc")),
                SourceBinCode    = reader.IsDBNull(reader.GetOrdinal("source_bin_code"))  ? string.Empty : reader.GetString(reader.GetOrdinal("source_bin_code")),
                BatchNumber      = reader.IsDBNull(reader.GetOrdinal("batch_number"))     ? null         : reader.GetString(reader.GetOrdinal("batch_number")),
                BestBeforeDate   = reader.IsDBNull(reader.GetOrdinal("best_before_date")) ? null         : reader.GetString(reader.GetOrdinal("best_before_date"))
            });

        return results;
    }

    // --------------------------------------------------
    // Active shipments (OPEN or LOADING)
    // --------------------------------------------------

    public IReadOnlyList<ShipmentSummaryDto> GetActiveShipments()
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = """
            SELECT
                s.shipment_id,
                s.shipment_ref,
                s.shipment_status,
                s.vehicle_ref,
                p.display_name                              AS haulier_name,
                CONVERT(NVARCHAR(16), s.planned_departure, 120) AS planned_departure,
                COUNT(so.outbound_order_id)                 AS total_orders,
                SUM(CASE WHEN o.order_status_code = 'PICKED'  THEN 1 ELSE 0 END) AS orders_picked,
                SUM(CASE WHEN o.order_status_code = 'LOADED'  THEN 1 ELSE 0 END) AS orders_loaded
            FROM outbound.shipments s
            LEFT JOIN core.parties p
                ON p.party_id = s.haulier_party_id
            LEFT JOIN outbound.shipment_orders so
                ON so.shipment_id = s.shipment_id
            LEFT JOIN outbound.outbound_orders o
                ON o.outbound_order_id = so.outbound_order_id
            WHERE s.shipment_status IN ('OPEN','LOADING')
            GROUP BY
                s.shipment_id, s.shipment_ref, s.shipment_status,
                s.vehicle_ref, p.display_name, s.planned_departure
            ORDER BY s.shipment_id
        """;

        using var reader = command.ExecuteReader();
        var results = new List<ShipmentSummaryDto>();
        while (reader.Read()) results.Add(ReadShipmentSummary(reader));
        return results;
    }

    // --------------------------------------------------
    // Single shipment by ref
    // --------------------------------------------------

    public ShipmentSummaryDto? GetShipmentByRef(string shipmentRef)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = """
            SELECT
                s.shipment_id,
                s.shipment_ref,
                s.shipment_status,
                s.vehicle_ref,
                p.display_name                              AS haulier_name,
                CONVERT(NVARCHAR(16), s.planned_departure, 120) AS planned_departure,
                COUNT(so.outbound_order_id)                 AS total_orders,
                SUM(CASE WHEN o.order_status_code = 'PICKED'  THEN 1 ELSE 0 END) AS orders_picked,
                SUM(CASE WHEN o.order_status_code = 'LOADED'  THEN 1 ELSE 0 END) AS orders_loaded
            FROM outbound.shipments s
            LEFT JOIN core.parties p
                ON p.party_id = s.haulier_party_id
            LEFT JOIN outbound.shipment_orders so
                ON so.shipment_id = s.shipment_id
            LEFT JOIN outbound.outbound_orders o
                ON o.outbound_order_id = so.outbound_order_id
            WHERE s.shipment_ref = @shipment_ref
            GROUP BY
                s.shipment_id, s.shipment_ref, s.shipment_status,
                s.vehicle_ref, p.display_name, s.planned_departure
        """;

        command.Parameters.Add(new SqlParameter("@shipment_ref", SqlDbType.NVarChar, 50) { Value = shipmentRef.Trim() });

        using var reader = command.ExecuteReader();
        return reader.Read() ? ReadShipmentSummary(reader) : null;
    }

    // --------------------------------------------------
    // Orders on a shipment (PICKED or LOADED — loadable)
    // --------------------------------------------------

    public IReadOnlyList<OutboundOrderSummaryDto> GetOrdersOnShipment(int shipmentId)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = """
            SELECT
                o.outbound_order_id,
                o.order_ref,
                o.order_status_code,
                p.display_name          AS customer_name,
                CONVERT(NVARCHAR(10), o.required_date, 103) AS required_date,
                COUNT(l.outbound_line_id)                   AS total_lines,
                SUM(l.allocated_qty)                        AS total_allocated,
                SUM(l.ordered_qty)                          AS total_ordered
            FROM outbound.outbound_orders o
            JOIN core.parties p
                ON p.party_id = o.customer_party_id
            JOIN outbound.outbound_lines l
                ON l.outbound_order_id = o.outbound_order_id
               AND l.line_status_code <> 'CNL'
            WHERE o.shipment_id       = @shipment_id
              AND o.order_status_code IN ('PICKED','LOADED')
            GROUP BY
                o.outbound_order_id, o.order_ref, o.order_status_code,
                p.display_name, o.required_date
            ORDER BY o.order_ref
        """;

        command.Parameters.Add(new SqlParameter("@shipment_id", SqlDbType.Int) { Value = shipmentId });

        using var reader = command.ExecuteReader();
        var results = new List<OutboundOrderSummaryDto>();
        while (reader.Read()) results.Add(ReadOrderSummary(reader));
        return results;
    }

    // --------------------------------------------------
    // Shared mappers
    // --------------------------------------------------

    private static OutboundOrderSummaryDto ReadOrderSummary(SqlDataReader reader) =>
        new OutboundOrderSummaryDto
        {
            OutboundOrderId = reader.GetInt32(reader.GetOrdinal("outbound_order_id")),
            OrderRef        = reader.GetString(reader.GetOrdinal("order_ref")),
            OrderStatusCode = reader.GetString(reader.GetOrdinal("order_status_code")),
            CustomerName    = reader.IsDBNull(reader.GetOrdinal("customer_name"))  ? string.Empty : reader.GetString(reader.GetOrdinal("customer_name")),
            RequiredDate    = reader.IsDBNull(reader.GetOrdinal("required_date"))  ? null         : reader.GetString(reader.GetOrdinal("required_date")),
            TotalLines      = reader.GetInt32(reader.GetOrdinal("total_lines")),
            TotalAllocated  = reader.GetInt32(reader.GetOrdinal("total_allocated")),
            TotalOrdered    = reader.GetInt32(reader.GetOrdinal("total_ordered"))
        };

    private static ShipmentSummaryDto ReadShipmentSummary(SqlDataReader reader) =>
        new ShipmentSummaryDto
        {
            ShipmentId       = reader.GetInt32(reader.GetOrdinal("shipment_id")),
            ShipmentRef      = reader.GetString(reader.GetOrdinal("shipment_ref")),
            ShipmentStatus   = reader.GetString(reader.GetOrdinal("shipment_status")),
            VehicleRef       = reader.IsDBNull(reader.GetOrdinal("vehicle_ref"))       ? null : reader.GetString(reader.GetOrdinal("vehicle_ref")),
            HaulierName      = reader.IsDBNull(reader.GetOrdinal("haulier_name"))      ? null : reader.GetString(reader.GetOrdinal("haulier_name")),
            PlannedDeparture = reader.IsDBNull(reader.GetOrdinal("planned_departure")) ? null : reader.GetString(reader.GetOrdinal("planned_departure")),
            TotalOrders      = reader.GetInt32(reader.GetOrdinal("total_orders")),
            OrdersPicked     = reader.IsDBNull(reader.GetOrdinal("orders_picked"))     ? 0    : reader.GetInt32(reader.GetOrdinal("orders_picked")),
            OrdersLoaded     = reader.IsDBNull(reader.GetOrdinal("orders_loaded"))     ? 0    : reader.GetInt32(reader.GetOrdinal("orders_loaded"))
        };
}
