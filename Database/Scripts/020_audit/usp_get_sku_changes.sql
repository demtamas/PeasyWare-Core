USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE audit.usp_get_sku_changes
(
    @sku_code  NVARCHAR(50) = NULL,
    @from_date DATE         = NULL,
    @to_date   DATE         = NULL,
    @top       INT          = 200
)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (@top)
        trace_id,
        occurred_at,
        username,
        action_type,
        sku_code,
        desc_before,     ean_before,       uom_before,       weight_before,
        hu_qty_before,   batch_req_before,  full_hu_req_before,
        hazardous_before, active_before,   storage_before,   section_before,
        desc_after,      ean_after,        uom_after,        weight_after,
        hu_qty_after,    batch_req_after,   full_hu_req_after,
        hazardous_after,  active_after,    storage_after,    section_after
    FROM audit.v_sku_changes
    WHERE (@sku_code  IS NULL OR sku_code     = @sku_code)
      AND (@from_date IS NULL OR occurred_at >= @from_date)
      AND (@to_date   IS NULL OR occurred_at <  DATEADD(DAY, 1, @to_date))
    ORDER BY occurred_at DESC;
END;
GO
PRINT 'audit.usp_get_sku_changes created.';
GO

-- ============================================================
-- inventory.v_active_inventory: inbound_ref + order_ref
-- Merged from WIP: 2026-05-16
-- ============================================================

-- ── inventory.v_active_inventory ──────────────────────────────────────────────
-- Added:
--   inbound_ref   — the delivery reference the unit arrived on
--   order_ref     — the outbound order reference if currently allocated
--
-- Logic:
--   inbound_ref  : inventory_unit → inbound_receipts → inbound_lines
--                  → inbound_deliveries.inbound_ref
--                  (most recent non-reversal receipt; handles re-receives after reversal)
--
--   order_ref    : inventory_unit → outbound_allocations (active only)
--                  → outbound_lines → outbound_orders.order_ref
--
-- Display rule (application layer):
--   Show order_ref when allocated (state PKD or MOV, or order_ref IS NOT NULL)
--   Show inbound_ref otherwise
--   A single "Reference" column in the Desktop grid covers both cases
GO
