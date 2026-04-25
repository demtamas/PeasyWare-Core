CREATE TABLE locations.storage_types
(
    storage_type_id   INT IDENTITY(1,1) PRIMARY KEY,

    -- Stable code used by SKU preferences & logic (e.g. RACK, BULK)
    storage_type_code NVARCHAR(50) NOT NULL,

    -- Human-friendly name
    storage_type_name NVARCHAR(100) NOT NULL,

    -- Optional operational description
    description       NVARCHAR(255) NULL,

    is_active         BIT NOT NULL DEFAULT (1),

    created_at        DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by        INT NULL,

    CONSTRAINT uq_storage_types_code
        UNIQUE (storage_type_code)
);

/* ============================================================
   locations.storage_sections
   ------------------------------------------------------------
   Sub-division within a storage type.
   Sections are scoped to a single storage type.
   ============================================================ */
CREATE TABLE locations.storage_sections
(
    storage_section_id INT IDENTITY(1,1) PRIMARY KEY,

    --storage_type_id    INT NOT NULL,

    -- Section identifier (FLOOR, MID, TOP, LEFT, RIGHT, etc.)
    section_code       NVARCHAR(50) NOT NULL,

    section_name       NVARCHAR(100) NOT NULL,

    description        NVARCHAR(255) NULL,

    is_active          BIT NOT NULL DEFAULT (1),

    created_at         DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by         INT NULL,

    --CONSTRAINT fk_storage_sections_type
    --    FOREIGN KEY (storage_type_id)
    --    REFERENCES locations.storage_types(storage_type_id),

    --CONSTRAINT uq_storage_sections_type_code
    --    UNIQUE (storage_type_id, section_code)
);


/* ============================================================
   locations.zones
   ------------------------------------------------------------
   Operational grouping for travel paths, load balancing,
   and putaway optimisation (e.g. AISLE_01, BULK_ZONE_A).
   ============================================================ */
CREATE TABLE locations.zones
(
    zone_id        INT IDENTITY(1,1) PRIMARY KEY,

    zone_code      NVARCHAR(50) NOT NULL,
    zone_name      NVARCHAR(100) NOT NULL,

    description    NVARCHAR(255) NULL,

    is_active      BIT NOT NULL DEFAULT (1),

    created_at     DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by     INT NULL,

    CONSTRAINT uq_zones_code
        UNIQUE (zone_code)
);

/* ============================================================
   locations.bins
   ------------------------------------------------------------
   Physical storage units.
   This is the ONLY place inventory can reside.
   ============================================================ */
CREATE TABLE locations.bins
(
    bin_id              INT IDENTITY(1,1) PRIMARY KEY,

    -- Human-readable warehouse identifier (A1-01-01, BAY03, etc.)
    bin_code            NVARCHAR(100) NOT NULL,

    storage_type_id     INT NOT NULL,
    storage_section_id  INT NULL,
    zone_id             INT NULL,

    -- Capacity expressed in logical units (pallets for now)
    capacity            INT NOT NULL DEFAULT (1),

    is_active           BIT NOT NULL DEFAULT (1),

    notes               NVARCHAR(255) NULL,

    created_at          DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by          INT NULL,
    updated_at          DATETIME2(3) NULL,
    updated_by          INT NULL,

    CONSTRAINT uq_bins_code
        UNIQUE (bin_code),

    CONSTRAINT fk_bins_storage_type
        FOREIGN KEY (storage_type_id)
        REFERENCES locations.storage_types(storage_type_id),

    CONSTRAINT fk_bins_storage_section
        FOREIGN KEY (storage_section_id)
        REFERENCES locations.storage_sections(storage_section_id),

    CONSTRAINT fk_bins_zone
        FOREIGN KEY (zone_id)
        REFERENCES locations.zones(zone_id)
);

CREATE INDEX IX_bins_storage_lookup
ON locations.bins (storage_type_id, storage_section_id, zone_id)
INCLUDE (capacity, is_active);

/* ============================================================
   locations.bin_reservations
   ------------------------------------------------------------
   Temporary claims on bins for putaway / movement planning.
   ============================================================ */
CREATE TABLE locations.bin_reservations
(
    reservation_id   INT IDENTITY(1,1) PRIMARY KEY,

    bin_id           INT NOT NULL,

    reservation_type NVARCHAR(50) NOT NULL, -- PUTAWAY, MOVE, PICK

    reserved_by      INT NOT NULL,
    reserved_at      DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    expires_at       DATETIME2(3) NOT NULL,

    CONSTRAINT fk_bin_reservations_bin
        FOREIGN KEY (bin_id)
        REFERENCES locations.bins(bin_id)
);

CREATE INDEX IX_bin_reservations_bin_expiry
ON locations.bin_reservations (bin_id, expires_at);

/* ============================================================
   inventory.skus
   ------------------------------------------------------------
   Canonical product master.
   Defines physical characteristics and storage intent.
   ============================================================ */
GO
