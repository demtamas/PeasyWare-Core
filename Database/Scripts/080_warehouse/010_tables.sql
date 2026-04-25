CREATE TABLE warehouse.warehouse_tasks
(
    task_id                 INT IDENTITY(1,1) PRIMARY KEY,

    -- Task classification
    task_type_code          NVARCHAR(20) NOT NULL,   -- PUTAWAY, MOVE, PICK

    -- Object being moved
    inventory_unit_id       INT NOT NULL,

    -- Movement context
    source_bin_id           INT NULL,
    destination_bin_id      INT NULL,

    -- Task lifecycle
    task_state_code         VARCHAR(3) NOT NULL DEFAULT 'OPN', -- OPN, CLM, CNF, CNL, EXP

    -- Assignment
    claimed_by_user_id      INT NULL,
    claimed_session_id      UNIQUEIDENTIFIER NULL,

    claimed_at              DATETIME2(3) NULL,
    expires_at              DATETIME2(3) NULL,

    -- Completion
    completed_at            DATETIME2(3) NULL,
    completed_by_user_id    INT NULL,

    -- Audit
    created_at              DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by              INT NULL,
    updated_at              DATETIME2(3) NULL,
    updated_by              INT NULL,

    CONSTRAINT fk_tasks_inventory_unit
        FOREIGN KEY (inventory_unit_id)
        REFERENCES inventory.inventory_units(inventory_unit_id),

    CONSTRAINT fk_tasks_source_bin
        FOREIGN KEY (source_bin_id)
        REFERENCES locations.bins(bin_id),

    CONSTRAINT fk_tasks_destination_bin
        FOREIGN KEY (destination_bin_id)
        REFERENCES locations.bins(bin_id)
);

CREATE INDEX IX_tasks_state
ON warehouse.warehouse_tasks (task_state_code);

CREATE INDEX IX_tasks_inventory
ON warehouse.warehouse_tasks (inventory_unit_id);

CREATE INDEX IX_tasks_expiry
ON warehouse.warehouse_tasks (expires_at);

/* ============================================================
   warehouse.task_states
   ------------------------------------------------------------
   Canonical lifecycle states for warehouse tasks.
   ============================================================ */
CREATE TABLE warehouse.task_states
(
    state_code      VARCHAR(3) NOT NULL PRIMARY KEY,
    state_desc      NVARCHAR(30) NOT NULL,
    is_terminal     BIT NOT NULL DEFAULT 0
);

INSERT INTO warehouse.task_states (state_code, state_desc, is_terminal)
VALUES
('OPN','OPEN',0),
('CLM','CLAIMED',0),
('CNF','CONFIRMED',1),
('EXP','EXPIRED',1),
('CNL','CANCELLED',1);

/* ============================================================
   warehouse.task_state_transitions
   ------------------------------------------------------------
   Defines legal transitions between task lifecycle states.
   ============================================================ */
CREATE TABLE warehouse.task_state_transitions
(
    from_state_code    VARCHAR(3) NOT NULL,
    to_state_code      VARCHAR(3) NOT NULL,
    requires_authority BIT NOT NULL DEFAULT 0,
    notes              NVARCHAR(200) NULL,

    PRIMARY KEY (from_state_code, to_state_code),

    FOREIGN KEY (from_state_code)
        REFERENCES warehouse.task_states(state_code),

    FOREIGN KEY (to_state_code)
        REFERENCES warehouse.task_states(state_code)
);

INSERT INTO warehouse.task_state_transitions
VALUES
('OPN','CLM',0,'Operator claims task'),
('OPN','CNL',1,'Task cancelled before claim'),

('CLM','CNF',0,'Task completed'),
('CLM','EXP',0,'Task expired due to TTL'),
('CLM','CNL',1,'Supervisor cancels task');

ALTER TABLE warehouse.warehouse_tasks
ADD CONSTRAINT fk_tasks_state
FOREIGN KEY (task_state_code)
REFERENCES warehouse.task_states(state_code);

CREATE UNIQUE INDEX UX_tasks_open_unit
ON warehouse.warehouse_tasks (inventory_unit_id)
WHERE task_state_code IN ('OPN','CLM');
GO
