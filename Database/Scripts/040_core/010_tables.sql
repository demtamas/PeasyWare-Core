CREATE TABLE core.parties
(
    party_id        INT IDENTITY(1,1) PRIMARY KEY,

    -- Stable external reference (e.g. SAP BP / Vendor / Customer code)
    party_code      NVARCHAR(50)  NOT NULL,

    -- Legal registered name (finance / compliance)
    legal_name      NVARCHAR(200) NOT NULL,

    -- Friendly operational name (what users see)
    display_name    NVARCHAR(200) NOT NULL,

    -- ISO country code (e.g. GB, HU)
    country_code    CHAR(2)       NULL,

    -- Tax / VAT identifier if applicable
    tax_id          NVARCHAR(50)  NULL,

    -- Soft-enable flag (do not delete historical parties)
    is_active       BIT           NOT NULL DEFAULT (1),

    -- Audit
    created_at      DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by      INT           NULL,
    updated_at      DATETIME2(3)  NULL,
    updated_by      INT           NULL,

    CONSTRAINT uq_parties_code UNIQUE (party_code)
);

/* ============================================================
   core.party_roles
   ------------------------------------------------------------
   Assigns functional roles to parties.

   A party may have multiple roles simultaneously
   (e.g. SUPPLIER + HAULIER).

   Role codes are intentionally free-text for now.
   ============================================================ */
CREATE TABLE core.party_roles
(
    party_id    INT          NOT NULL,
    role_code   NVARCHAR(50) NOT NULL, -- SUPPLIER, CUSTOMER, HAULIER, OWNER

    assigned_at DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    assigned_by      INT           NULL,
    updated_at      DATETIME2(3)  NULL,
    updated_by      INT           NULL,

    CONSTRAINT pk_party_roles
        PRIMARY KEY (party_id, role_code),

    CONSTRAINT fk_party_roles_party
        FOREIGN KEY (party_id)
        REFERENCES core.parties(party_id)
);

/* ============================================================
   core.party_addresses
   ------------------------------------------------------------
   Physical or logical addresses associated with a party.
   Can be reused across inbound, outbound, billing, etc.
   ============================================================ */
CREATE TABLE core.party_addresses
(
    address_id        INT IDENTITY(1,1) PRIMARY KEY,

    -- Owning party
    party_id          INT NOT NULL,

    -- Address usage / intent
    -- e.g. SHIP_FROM, SHIP_TO, BILL_TO, HQ, YARD
    address_type      NVARCHAR(50) NOT NULL,

    -- Free-text address fields (intentionally simple)
    line_1            NVARCHAR(200) NOT NULL,
    line_2            NVARCHAR(200) NULL,
    city              NVARCHAR(100) NULL,
    region            NVARCHAR(100) NULL,
    postal_code       NVARCHAR(50)  NULL,
    country_code      CHAR(2)       NOT NULL,

    -- Optional operational hints
    dock_info         NVARCHAR(200) NULL, -- gate, dock, yard notes
    instructions      NVARCHAR(400) NULL, -- receiving notes, access rules

    -- Flags
    is_primary        BIT NOT NULL DEFAULT (0),
    is_active         BIT NOT NULL DEFAULT (1),

    -- Audit
    created_at        DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by        INT          NULL,
    updated_at        DATETIME2(3) NULL,
    updated_by        INT          NULL,

    CONSTRAINT fk_party_addresses_party
        FOREIGN KEY (party_id)
        REFERENCES core.parties(party_id)
);

/* ============================================================
   suppliers.suppliers
   ------------------------------------------------------------
   Supplier-specific attributes extending core.parties.
   ============================================================ */
CREATE TABLE suppliers.suppliers
(
    party_id             INT PRIMARY KEY,
    supplier_type        NVARCHAR(50) NULL,  -- RAW, PACKAGING, 3PL
    default_lead_days    INT          NULL,
    preferred_haulier_id INT          NULL,

    created_at    DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by    INT          NULL,
    updated_at    DATETIME2(3) NULL,
    updated_by    INT          NULL,

    CONSTRAINT fk_suppliers_party
        FOREIGN KEY (party_id)
        REFERENCES core.parties(party_id),

    CONSTRAINT fk_suppliers_haulier
        FOREIGN KEY (preferred_haulier_id)
        REFERENCES core.parties(party_id)
);


/* ============================================================
   customers.customers
   ------------------------------------------------------------
   Customer-specific attributes extending core.parties.
   ============================================================ */
CREATE TABLE customers.customers
(
    party_id               INT PRIMARY KEY,
    customer_type          NVARCHAR(50) NULL, -- RETAIL, WHOLESALE, EXPORT
    default_delivery_days  INT          NULL,
    preferred_haulier_id   INT          NULL,
    allow_crossdock        BIT NOT NULL DEFAULT (0),

    created_at    DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by    INT          NULL,
    updated_at    DATETIME2(3) NULL,
    updated_by    INT          NULL,

    CONSTRAINT fk_customers_party
        FOREIGN KEY (party_id)
        REFERENCES core.parties(party_id),

    CONSTRAINT fk_customers_haulier
        FOREIGN KEY (preferred_haulier_id)
        REFERENCES core.parties(party_id)
);


/* ============================================================
   logistics.hauliers
   ------------------------------------------------------------
   Haulier-specific attributes extending core.parties.
   ============================================================ */
CREATE TABLE logistics.hauliers
(
    party_id              INT PRIMARY KEY,
    haulier_type          NVARCHAR(50) NULL, -- INTERNAL, CONTRACTED
    default_vehicle_type  NVARCHAR(50) NULL, -- CURTAIN, BOX, FRIDGE
    requires_timeslot     BIT NOT NULL DEFAULT (0),
    notes                 NVARCHAR(500) NULL,

    CONSTRAINT fk_hauliers_party
        FOREIGN KEY (party_id)
        REFERENCES core.parties(party_id)
);


/* ============================================================
   core.party_contacts
   ============================================================ */
CREATE TABLE core.party_contacts
(
    contact_id    INT IDENTITY(1,1) PRIMARY KEY,
    party_id      INT NOT NULL,

    contact_role  NVARCHAR(50) NULL,
    contact_name  NVARCHAR(200) NULL,
    email         NVARCHAR(200) NULL,
    phone         NVARCHAR(50)  NULL,

    is_primary    BIT NOT NULL DEFAULT (0),
    is_active     BIT NOT NULL DEFAULT (1),

    created_at    DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by    INT          NULL,
    updated_at    DATETIME2(3) NULL,
    updated_by    INT          NULL,

    CONSTRAINT fk_party_contacts_party
        FOREIGN KEY (party_id)
        REFERENCES core.parties(party_id)
);


/* ============================================================
   audit.party_changes
   ============================================================ */
CREATE TABLE audit.party_changes
(
    audit_id     BIGINT IDENTITY PRIMARY KEY,
    party_id     INT NOT NULL,

    action       NVARCHAR(50) NOT NULL,
    details      NVARCHAR(500) NULL,

    changed_at   DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    changed_by   INT NULL,
    session_id   UNIQUEIDENTIFIER NULL,

    CONSTRAINT fk_party_changes_party
        FOREIGN KEY (party_id)
        REFERENCES core.parties(party_id)
);
GO
