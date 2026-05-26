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
                da.line_1       AS delivery_line_1,
                da.city         AS delivery_city,
                da.postal_code  AS delivery_postal_code,
                COUNT(l.outbound_line_id)                   AS total_lines,
                ISNULL(SUM(l.allocated_qty), 0)             AS total_allocated,
                ISNULL(SUM(l.ordered_qty),   0)             AS total_ordered,
                ISNULL(SUM(l.picked_qty),    0)             AS total_picked
            FROM outbound.outbound_orders o
            JOIN core.parties p
                ON p.party_id = o.customer_party_id
            LEFT JOIN core.party_addresses da
                ON da.address_id = o.delivery_address_id
            JOIN outbound.outbound_lines l
                ON l.outbound_order_id = o.outbound_order_id
               AND l.line_status_code <> 'CNL'
            WHERE o.order_status_code IN ('ALLOCATED','PICKING')
            GROUP BY
                o.outbound_order_id, o.order_ref, o.order_status_code,
                p.display_name, o.required_date,
                da.line_1, da.city, da.postal_code
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
                da.line_1       AS delivery_line_1,
                da.city         AS delivery_city,
                da.postal_code  AS delivery_postal_code,
                COUNT(l.outbound_line_id)                   AS total_lines,
                ISNULL(SUM(l.allocated_qty), 0)             AS total_allocated,
                ISNULL(SUM(l.ordered_qty),   0)             AS total_ordered,
                ISNULL(SUM(l.picked_qty),    0)             AS total_picked
            FROM outbound.outbound_orders o
            JOIN core.parties p
                ON p.party_id = o.customer_party_id
            LEFT JOIN core.party_addresses da
                ON da.address_id = o.delivery_address_id
            JOIN outbound.outbound_lines l
                ON l.outbound_order_id = o.outbound_order_id
               AND l.line_status_code <> 'CNL'
            WHERE o.order_ref = @order_ref
            GROUP BY
                o.outbound_order_id, o.order_ref, o.order_status_code,
                p.display_name, o.required_date,
                da.line_1, da.city, da.postal_code
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
              AND a.allocation_status IN ('PENDING','CONFIRMED','PICKED')
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
    // Departed orders (SHIPPED / DEPARTED)
    // --------------------------------------------------

    public IReadOnlyList<OutboundOrderSummaryDto> GetDepartedOrders()
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = """
            SELECT
                o.outbound_order_id,
                o.order_ref,
                o.order_status_code,
                p.display_name                              AS customer_name,
                CONVERT(NVARCHAR(10), o.required_date, 103) AS required_date,
                da.line_1       AS delivery_line_1,
                da.city         AS delivery_city,
                da.postal_code  AS delivery_postal_code,
                COUNT(l.outbound_line_id)                   AS total_lines,
                ISNULL(SUM(l.ordered_qty),   0)             AS total_ordered,
                ISNULL(SUM(l.allocated_qty), 0)             AS total_allocated,
                ISNULL(SUM(l.picked_qty),    0)             AS total_picked
            FROM outbound.outbound_orders o
            JOIN core.parties p
                ON p.party_id = o.customer_party_id
            LEFT JOIN core.party_addresses da
                ON da.address_id = o.delivery_address_id
            LEFT JOIN outbound.outbound_lines l
                ON l.outbound_order_id = o.outbound_order_id
               AND l.line_status_code <> 'CNL'
            WHERE o.order_status_code IN ('SHIPPED', 'DEPARTED')
            GROUP BY
                o.outbound_order_id, o.order_ref, o.order_status_code,
                p.display_name, o.required_date,
                da.line_1, da.city, da.postal_code
            ORDER BY o.required_date DESC, o.order_ref
        """;

        using var reader = command.ExecuteReader();
        var results = new List<OutboundOrderSummaryDto>();
        while (reader.Read()) results.Add(ReadOrderSummary(reader));
        return results;
    }

    // --------------------------------------------------
    // All orders
    // --------------------------------------------------

    public IReadOnlyList<OutboundOrderSummaryDto> GetAllOrders()
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = """
            SELECT
                o.outbound_order_id,
                o.order_ref,
                o.order_status_code,
                p.display_name                              AS customer_name,
                CONVERT(NVARCHAR(10), o.required_date, 103) AS required_date,
                da.line_1       AS delivery_line_1,
                da.city         AS delivery_city,
                da.postal_code  AS delivery_postal_code,
                COUNT(l.outbound_line_id)                   AS total_lines,
                ISNULL(SUM(l.ordered_qty),   0)             AS total_ordered,
                ISNULL(SUM(l.allocated_qty), 0)             AS total_allocated,
                ISNULL(SUM(l.picked_qty),    0)             AS total_picked
            FROM outbound.outbound_orders o
            JOIN core.parties p
                ON p.party_id = o.customer_party_id
            LEFT JOIN core.party_addresses da
                ON da.address_id = o.delivery_address_id
            LEFT JOIN outbound.outbound_lines l
                ON l.outbound_order_id = o.outbound_order_id
               AND l.line_status_code <> 'CNL'
            GROUP BY
                o.outbound_order_id, o.order_ref, o.order_status_code,
                p.display_name, o.required_date,
                da.line_1, da.city, da.postal_code
            ORDER BY o.required_date DESC, o.order_status_code, o.order_ref
        """;

        using var reader = command.ExecuteReader();
        var results = new List<OutboundOrderSummaryDto>();
        while (reader.Read()) results.Add(ReadOrderSummary(reader));
        return results;
    }

    // --------------------------------------------------
    // Outstanding orders (NEW / ALLOCATED / PICKING / PICKED / LOADED)
    // --------------------------------------------------

    public IReadOnlyList<OutboundOrderSummaryDto> GetOutstandingOrders()
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = """
            SELECT
                o.outbound_order_id,
                o.order_ref,
                o.order_status_code,
                p.display_name                              AS customer_name,
                CONVERT(NVARCHAR(10), o.required_date, 103) AS required_date,
                da.line_1       AS delivery_line_1,
                da.city         AS delivery_city,
                da.postal_code  AS delivery_postal_code,
                COUNT(l.outbound_line_id)                   AS total_lines,
                ISNULL(SUM(l.ordered_qty),   0)             AS total_ordered,
                ISNULL(SUM(l.allocated_qty), 0)             AS total_allocated,
                ISNULL(SUM(l.picked_qty),    0)             AS total_picked
            FROM outbound.outbound_orders o
            JOIN core.parties p
                ON p.party_id = o.customer_party_id
            LEFT JOIN core.party_addresses da
                ON da.address_id = o.delivery_address_id
            LEFT JOIN outbound.outbound_lines l
                ON l.outbound_order_id = o.outbound_order_id
               AND l.line_status_code <> 'CNL'
            WHERE o.order_status_code NOT IN ('SHIPPED', 'DEPARTED', 'CANCELLED')
            GROUP BY
                o.outbound_order_id, o.order_ref, o.order_status_code,
                p.display_name, o.required_date,
                da.line_1, da.city, da.postal_code
            ORDER BY o.required_date, o.order_status_code, o.order_ref
        """;

        using var reader = command.ExecuteReader();
        var results = new List<OutboundOrderSummaryDto>();
        while (reader.Read()) results.Add(ReadOrderSummary(reader));
        return results;
    }

    // --------------------------------------------------
    // Order lines for a single order (Lines tab)
    // --------------------------------------------------

    public IReadOnlyList<OutboundOrderLineDto> GetOrderLines(int outboundOrderId)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = """
            SELECT
                l.outbound_line_id,
                l.line_no,
                s.sku_code,
                s.sku_description,
                l.ordered_qty,
                l.allocated_qty,
                l.picked_qty,
                l.line_status_code,
                l.requested_batch,
                CONVERT(NVARCHAR(10), l.requested_bbe, 103) AS requested_bbe,
                l.notes
            FROM outbound.outbound_lines l
            JOIN inventory.skus s ON s.sku_id = l.sku_id
            WHERE l.outbound_order_id = @outbound_order_id
              AND l.line_status_code  <> 'CNL'
            ORDER BY l.line_no
        """;

        command.Parameters.Add(
            new SqlParameter("@outbound_order_id", SqlDbType.Int)
            { Value = outboundOrderId });

        using var reader = command.ExecuteReader();
        var results = new List<OutboundOrderLineDto>();

        while (reader.Read())
            results.Add(new OutboundOrderLineDto
            {
                OutboundLineId  = reader.GetInt32(reader.GetOrdinal("outbound_line_id")),
                LineNo          = reader.GetInt32(reader.GetOrdinal("line_no")),
                SkuCode         = reader.GetString(reader.GetOrdinal("sku_code")),
                SkuDescription  = reader.GetString(reader.GetOrdinal("sku_description")),
                OrderedQty      = reader.GetInt32(reader.GetOrdinal("ordered_qty")),
                AllocatedQty    = reader.GetInt32(reader.GetOrdinal("allocated_qty")),
                PickedQty       = reader.GetInt32(reader.GetOrdinal("picked_qty")),
                LineStatusCode  = reader.GetString(reader.GetOrdinal("line_status_code")),
                RequestedBatch  = reader.IsDBNull(reader.GetOrdinal("requested_batch")) ? null : reader.GetString(reader.GetOrdinal("requested_batch")),
                RequestedBbe    = reader.IsDBNull(reader.GetOrdinal("requested_bbe"))   ? null : reader.GetString(reader.GetOrdinal("requested_bbe")),
                Notes           = reader.IsDBNull(reader.GetOrdinal("notes"))           ? null : reader.GetString(reader.GetOrdinal("notes"))
            });

        return results;
    }

    // --------------------------------------------------
    // Orders eligible for shipment (PICKED, not on any active shipment)
    // --------------------------------------------------

    public IReadOnlyList<OutboundOrderSummaryDto> GetOrdersEligibleForShipment()
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = """
            SELECT
                o.outbound_order_id,
                o.order_ref,
                o.order_status_code,
                p.display_name                              AS customer_name,
                CONVERT(NVARCHAR(10), o.required_date, 103) AS required_date,
                da.line_1       AS delivery_line_1,
                da.city         AS delivery_city,
                da.postal_code  AS delivery_postal_code,
                COUNT(l.outbound_line_id)                   AS total_lines,
                ISNULL(SUM(l.ordered_qty),   0)             AS total_ordered,
                ISNULL(SUM(l.allocated_qty), 0)             AS total_allocated,
                ISNULL(SUM(l.picked_qty),    0)             AS total_picked
            FROM outbound.outbound_orders o
            JOIN core.parties p
                ON p.party_id = o.customer_party_id
            LEFT JOIN core.party_addresses da
                ON da.address_id = o.delivery_address_id
            LEFT JOIN outbound.outbound_lines l
                ON l.outbound_order_id = o.outbound_order_id
               AND l.line_status_code <> 'CNL'
            WHERE o.order_status_code = 'PICKED'
              AND NOT EXISTS (
                  SELECT 1
                  FROM outbound.shipment_orders so
                  JOIN outbound.shipments s ON s.shipment_id = so.shipment_id
                  WHERE so.outbound_order_id = o.outbound_order_id
                    AND s.shipment_status NOT IN ('CNL', 'DEPARTED')
              )
            GROUP BY
                o.outbound_order_id, o.order_ref, o.order_status_code,
                p.display_name, o.required_date,
                da.line_1, da.city, da.postal_code
            ORDER BY o.required_date, o.order_ref
            """;

        using var reader = command.ExecuteReader();
        var results = new List<OutboundOrderSummaryDto>();
        while (reader.Read()) results.Add(ReadOrderSummary(reader));
        return results;
    }

    // --------------------------------------------------
    // Shipped shipments
    // --------------------------------------------------

    public IReadOnlyList<ShipmentSummaryDto> GetShippedShipments()
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
                SUM(CASE WHEN o.order_status_code = 'PICKED'   THEN 1 ELSE 0 END) AS orders_picked,
                SUM(CASE WHEN o.order_status_code = 'LOADED'   THEN 1 ELSE 0 END) AS orders_loaded
            FROM outbound.shipments s
            LEFT JOIN core.parties p
                ON p.party_id = s.haulier_party_id
            LEFT JOIN outbound.shipment_orders so
                ON so.shipment_id = s.shipment_id
            LEFT JOIN outbound.outbound_orders o
                ON o.outbound_order_id = so.outbound_order_id
            WHERE s.shipment_status IN ('SHIPPED', 'DEPARTED')
            GROUP BY
                s.shipment_id, s.shipment_ref, s.shipment_status,
                s.vehicle_ref, p.display_name, s.planned_departure
            ORDER BY s.shipment_id DESC
        """;

        using var reader = command.ExecuteReader();
        var results = new List<ShipmentSummaryDto>();
        while (reader.Read()) results.Add(ReadShipmentSummary(reader));
        return results;
    }

    // --------------------------------------------------
    // All shipments
    // --------------------------------------------------

    public IReadOnlyList<ShipmentSummaryDto> GetAllShipments()
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
                SUM(CASE WHEN o.order_status_code = 'PICKED'   THEN 1 ELSE 0 END) AS orders_picked,
                SUM(CASE WHEN o.order_status_code = 'LOADED'   THEN 1 ELSE 0 END) AS orders_loaded
            FROM outbound.shipments s
            LEFT JOIN core.parties p
                ON p.party_id = s.haulier_party_id
            LEFT JOIN outbound.shipment_orders so
                ON so.shipment_id = s.shipment_id
            LEFT JOIN outbound.outbound_orders o
                ON o.outbound_order_id = so.outbound_order_id
            GROUP BY
                s.shipment_id, s.shipment_ref, s.shipment_status,
                s.vehicle_ref, p.display_name, s.planned_departure
            ORDER BY s.shipment_id DESC
        """;

        using var reader = command.ExecuteReader();
        var results = new List<ShipmentSummaryDto>();
        while (reader.Read()) results.Add(ReadShipmentSummary(reader));
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
    // Orders on a shipment (all statuses — for supervisor view)
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
                da.line_1       AS delivery_line_1,
                da.city         AS delivery_city,
                da.postal_code  AS delivery_postal_code,
                COUNT(l.outbound_line_id)                   AS total_lines,
                ISNULL(SUM(l.allocated_qty), 0)             AS total_allocated,
                ISNULL(SUM(l.ordered_qty),   0)             AS total_ordered,
                ISNULL(SUM(l.picked_qty),    0)             AS total_picked
            FROM outbound.outbound_orders o
            JOIN core.parties p
                ON p.party_id = o.customer_party_id
            LEFT JOIN core.party_addresses da
                ON da.address_id = o.delivery_address_id
            LEFT JOIN outbound.outbound_lines l
                ON l.outbound_order_id = o.outbound_order_id
               AND l.line_status_code <> 'CNL'
            JOIN outbound.shipment_orders so
                ON so.outbound_order_id = o.outbound_order_id
               AND so.shipment_id = @shipment_id
            GROUP BY
                o.outbound_order_id, o.order_ref, o.order_status_code,
                p.display_name, o.required_date,
                da.line_1, da.city, da.postal_code
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
            OutboundOrderId      = reader.GetInt32(reader.GetOrdinal("outbound_order_id")),
            OrderRef             = reader.GetString(reader.GetOrdinal("order_ref")),
            OrderStatusCode      = reader.GetString(reader.GetOrdinal("order_status_code")),
            CustomerName         = reader.IsDBNull(reader.GetOrdinal("customer_name"))         ? string.Empty : reader.GetString(reader.GetOrdinal("customer_name")),
            DeliveryAddressLine1 = reader.IsDBNull(reader.GetOrdinal("delivery_line_1"))       ? null         : reader.GetString(reader.GetOrdinal("delivery_line_1")),
            DeliveryCity         = reader.IsDBNull(reader.GetOrdinal("delivery_city"))         ? null         : reader.GetString(reader.GetOrdinal("delivery_city")),
            DeliveryPostalCode   = reader.IsDBNull(reader.GetOrdinal("delivery_postal_code"))  ? null         : reader.GetString(reader.GetOrdinal("delivery_postal_code")),
            RequiredDate         = reader.IsDBNull(reader.GetOrdinal("required_date"))         ? null         : reader.GetString(reader.GetOrdinal("required_date")),
            TotalLines           = reader.GetInt32(reader.GetOrdinal("total_lines")),
            TotalOrdered         = reader.GetInt32(reader.GetOrdinal("total_ordered")),
            TotalAllocated       = reader.GetInt32(reader.GetOrdinal("total_allocated")),
            TotalPicked          = reader.IsDBNull(reader.GetOrdinal("total_picked")) ? 0 : reader.GetInt32(reader.GetOrdinal("total_picked"))
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
