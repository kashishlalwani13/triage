-- Triage database schema: all 21 tables.
-- Safe to re-run: "if not exists" skips tables that already exist and never deletes data.
-- Tables are created in dependency order: a table must exist before another table can point to it.
-- The mock ERP tables are a simulation. They are not Workday or any real ERP system.


-- =====================================================================
-- MASTER DATA: the "who and what". Changes rarely.
-- =====================================================================

-- SYNTHETIC: supplier (distributor) names are made up.
create table if not exists suppliers (
    supplier_id    bigint generated always as identity primary key,
    supplier_name  text not null unique
);
comment on table suppliers is 'SYNTHETIC: made-up suppliers.';

-- Device data comes from the real FDA GUDID (via openFDA).
-- Two columns are SYNTHETIC: item_type and unit_price, because GUDID has no hospital stocking or price data.
create table if not exists items (
    item_id              bigint generated always as identity primary key,
    primary_di           text not null unique,   -- GUDID device identifier for the smallest unit (real)
    brand_name           text,                   -- real
    version_model        text,                   -- real
    company_name         text,                   -- manufacturer (real)
    device_description   text,                   -- real
    category             text not null check (category in ('SYRINGE', 'IV_CATHETER', 'EXAM_GLOVE')),
    base_uom             text not null default 'EA',   -- every quantity is converted to this before comparing
    base_package_count   integer not null default 1 check (base_package_count > 0),   -- devices in the primary DI (real), e.g. 100 for a box of gloves
    item_type            text not null check (item_type in ('STOCK', 'NON_STOCK')),   -- SYNTHETIC
    unit_price           numeric(12,4) check (unit_price >= 0),   -- SYNTHETIC, price per base unit
    default_supplier_id  bigint references suppliers (supplier_id),   -- SYNTHETIC
    source               text not null default 'FDA GUDID via openFDA'
);
comment on table items is 'Real FDA GUDID devices. item_type, unit_price and default_supplier_id are SYNTHETIC.';

-- Real GUDID package levels, e.g. a box of 50 or a case of 10 boxes.
-- Kept separate from items because one device can come in several packages.
-- Stored exactly as GUDID has them; the cleaned UOM code is derived in sql/build_uom_conversions.sql.
create table if not exists item_packages (
    package_id   bigint generated always as identity primary key,
    item_id      bigint not null references items (item_id),
    package_di   text not null unique,   -- GUDID identifier of this package level
    package_type text,                   -- as written in GUDID, e.g. 'Box', 'CASE', 'cs' (messy, sometimes empty)
    quantity     integer not null check (quantity > 0),   -- how many of the next level down it holds
    contains_di  text                    -- the identifier it holds (null if GUDID doesn't say)
);

-- How many base units (EA) are in one of each UOM, per item. Built from item_packages.
-- The key is (item_id, uom) because "1 BX" means different amounts for different items.
create table if not exists uom_conversions (
    item_id            bigint not null references items (item_id),
    uom                text not null,
    base_units_per_uom numeric(12,4) not null check (base_units_per_uom > 0),
    source             text not null check (source in ('BASE', 'GUDID')),
    primary key (item_id, uom)
);

-- SYNTHETIC: hospital units (departments).
create table if not exists units (
    unit_id    bigint generated always as identity primary key,
    unit_code  text not null unique,   -- short code, e.g. '4W'
    unit_name  text not null           -- e.g. '4 West Med-Surg'
);
comment on table units is 'SYNTHETIC: made-up hospital units.';

-- SYNTHETIC: how much of each item a unit keeps at its par location, and how much is there now.
create table if not exists par_levels (
    unit_id       bigint not null references units (unit_id),
    item_id       bigint not null references items (item_id),
    par_location  text not null,   -- e.g. 'Supply room cart A'
    par_qty_base  integer not null check (par_qty_base >= 0),   -- in base units (EA)
    on_hand_base  integer not null check (on_hand_base >= 0),   -- in base units (EA)
    primary key (unit_id, item_id)
);
comment on table par_levels is 'SYNTHETIC: made-up par levels and on-hand counts.';


-- =====================================================================
-- TRANSACTIONS: things that happen.
-- =====================================================================

-- SYNTHETIC: supply requests from nurses (direct) or call-center agents (on behalf of a nurse).
-- Holds the CURRENT state only. The history lives in request_events.
create table if not exists requests (
    request_id        bigint generated always as identity primary key,
    idempotency_key   uuid not null unique default gen_random_uuid(),   -- sent to the ERP so a retry never creates a duplicate
    unit_id           bigint not null references units (unit_id),
    item_id           bigint not null references items (item_id),
    quantity          integer not null check (quantity > 0),
    uom               text not null,
    request_type      text not null check (request_type in ('STAT', 'EMERGENCY_REPLENISHMENT', 'REGULAR')),
    route             text check (route in ('STOCK_REQUEST', 'REQUISITION')),   -- set by routing rules from item_type
    path              text not null check (path in ('DIRECT', 'CALL_CENTER')),
    requested_by      text not null,   -- the nurse
    entered_by_role   text not null check (entered_by_role in ('NURSE', 'CALL_CENTER_AGENT')),
    on_behalf_of      boolean not null default false,   -- true when an agent typed it for the nurse
    status            text not null default 'SUBMITTED' check (status in (
                          'SUBMITTED', 'PENDING_APPROVAL', 'APPROVED', 'ACKNOWLEDGED',
                          'FULFILLED', 'EXPEDITED', 'REJECTED', 'CANCELLED')),
    erp_status        text not null default 'NOT_SENT' check (erp_status in (
                          'NOT_SENT', 'SENDING', 'SENT', 'FAILED')),   -- flows back from the integration worker
    submitted_at      timestamptz not null default now()
);
comment on table requests is 'SYNTHETIC: simulated supply requests.';

-- SYNTHETIC: every change to a request, one row per event. Append-only: rows are added, never edited.
create table if not exists request_events (
    event_id     bigint generated always as identity primary key,
    request_id   bigint not null references requests (request_id),
    event_type   text not null,   -- e.g. 'SUBMITTED', 'ACKNOWLEDGED', 'APPROVED', 'POST_REVIEW'
    from_status  text,
    to_status    text,
    actor_role   text not null check (actor_role in (
                     'NURSE', 'CALL_CENTER_AGENT', 'DISPATCH', 'BUYER', 'ON_CALL_ADMIN', 'AP_CLERK', 'SYSTEM')),
    note         text,
    created_at   timestamptz not null default now()
);
comment on table request_events is 'SYNTHETIC: simulated request history.';

-- SYNTHETIC: escalation pages for STAT requests. Level 1 Dispatch, 2 Buyer, 3 On-Call Admin.
create table if not exists pages (
    page_id      bigint generated always as identity primary key,
    request_id   bigint not null references requests (request_id),
    level        integer not null check (level between 1 and 3),
    paged_role   text not null check (paged_role in ('DISPATCH', 'BUYER', 'ON_CALL_ADMIN')),
    reason       text not null,   -- e.g. 'Not acknowledged in 5 min', 'After hours'
    paged_at     timestamptz not null default now()
);
comment on table pages is 'SYNTHETIC: simulated escalation pages.';

-- MOCK ERP: requisitions as recorded by the mock ERP (not Workday or any real system).
-- request_id is a plain number, not a foreign key: the ERP is a separate system and doesn't share our tables.
create table if not exists erp_requisitions (
    erp_req_id       bigint generated always as identity primary key,
    erp_number       text not null unique,   -- e.g. 'REQ-000123'
    idempotency_key  uuid not null unique,   -- the duplicate guard: the same key can only ever create one row
    request_id       bigint not null,
    item_id          bigint not null,
    quantity         integer not null,
    uom              text not null,
    created_at       timestamptz not null default now()
);
comment on table erp_requisitions is 'SYNTHETIC: mock ERP records. Not a real ERP.';

-- SYNTHETIC: purchase orders (header). One PO, many lines.
create table if not exists purchase_orders (
    po_id        bigint generated always as identity primary key,
    po_number    text not null unique,
    supplier_id  bigint not null references suppliers (supplier_id),
    erp_req_id   bigint references erp_requisitions (erp_req_id),   -- null for POs not created from a Triage request
    order_date   date not null default current_date
);
comment on table purchase_orders is 'SYNTHETIC: simulated purchase orders.';

-- SYNTHETIC: PO lines. Price is per the line's UOM, exactly as ordered.
create table if not exists po_lines (
    po_line_id   bigint generated always as identity primary key,
    po_id        bigint not null references purchase_orders (po_id),
    line_number  integer not null,
    item_id      bigint not null references items (item_id),
    quantity     integer not null check (quantity > 0),
    uom          text not null,
    unit_price   numeric(12,4) not null check (unit_price >= 0),
    unique (po_id, line_number)
);
comment on table po_lines is 'SYNTHETIC: simulated PO lines.';

-- SYNTHETIC: goods received on the dock (header).
create table if not exists receipts (
    receipt_id   bigint generated always as identity primary key,
    po_id        bigint not null references purchase_orders (po_id),
    received_at  timestamptz not null default now()
);
comment on table receipts is 'SYNTHETIC: simulated receipts.';

-- SYNTHETIC: what was received, per PO line. May be in a different UOM than the PO.
create table if not exists receipt_lines (
    receipt_line_id  bigint generated always as identity primary key,
    receipt_id       bigint not null references receipts (receipt_id),
    po_line_id       bigint not null references po_lines (po_line_id),
    quantity         integer not null check (quantity > 0),
    uom              text not null
);
comment on table receipt_lines is 'SYNTHETIC: simulated receipt lines.';

-- SYNTHETIC: supplier invoices (header).
-- invoice_number is deliberately NOT unique: duplicate invoices must be stored so they can be flagged (DUP_INVOICE).
create table if not exists invoices (
    invoice_id      bigint generated always as identity primary key,
    supplier_id     bigint not null references suppliers (supplier_id),
    invoice_number  text not null,
    po_id           bigint references purchase_orders (po_id),
    invoice_date    date not null default current_date
);
comment on table invoices is 'SYNTHETIC: simulated supplier invoices.';

-- SYNTHETIC: invoice lines. May be billed in a different UOM than the PO (e.g. BX vs EA).
create table if not exists invoice_lines (
    invoice_line_id  bigint generated always as identity primary key,
    invoice_id       bigint not null references invoices (invoice_id),
    po_line_id       bigint references po_lines (po_line_id),
    item_id          bigint not null references items (item_id),
    quantity         integer not null check (quantity > 0),
    uom              text not null,
    unit_price       numeric(12,4) not null check (unit_price >= 0)
);
comment on table invoice_lines is 'SYNTHETIC: simulated invoice lines.';


-- =====================================================================
-- LOGS AND RESULTS: records about what happened.
-- =====================================================================

-- SYNTHETIC: every attempt to send a request to the mock ERP, including failures.
create table if not exists integration_log (
    log_id          bigint generated always as identity primary key,
    request_id      bigint not null references requests (request_id),
    attempt_number  integer not null check (attempt_number >= 1),
    succeeded       boolean not null,
    http_status     integer,
    erp_number      text,   -- filled in when the ERP accepted it
    error_message   text,
    attempted_at    timestamptz not null default now()
);
comment on table integration_log is 'SYNTHETIC: simulated integration attempts.';

-- SYNTHETIC: requests that failed every retry and now need a person to look at them.
create table if not exists integration_errors (
    error_id          bigint generated always as identity primary key,
    request_id        bigint not null references requests (request_id),
    attempts          integer not null,
    last_error        text,
    queued_at         timestamptz not null default now(),
    resolved_at       timestamptz,
    resolved_by_role  text
);
comment on table integration_errors is 'SYNTHETIC: simulated integration error queue.';

-- SYNTHETIC: result of the three-way match for each invoice line.
-- Stored twice per line: with and without UOM normalization, to measure false exceptions avoided.
create table if not exists match_results (
    match_id             bigint generated always as identity primary key,
    invoice_line_id      bigint not null references invoice_lines (invoice_line_id),
    normalized           boolean not null,   -- true = converted to base units before comparing
    po_base_qty          numeric(12,4),
    received_base_qty    numeric(12,4),
    invoiced_base_qty    numeric(12,4),
    po_base_price        numeric(12,4),
    invoiced_base_price  numeric(12,4),
    reason_code          text not null check (reason_code in (
                             'MATCHED', 'UOM_CONVERTED', 'UOM_NO_CONVERSION', 'PRICE_VAR',
                             'QTY_OVER_RECEIPT', 'NO_RECEIPT', 'DUP_INVOICE')),
    is_exception         boolean not null,
    matched_at           timestamptz not null default now(),
    unique (invoice_line_id, normalized)
);
comment on table match_results is 'SYNTHETIC: match results on simulated invoices.';

-- SYNTHETIC: match results that need an AP clerk to review them.
create table if not exists exceptions (
    exception_id    bigint generated always as identity primary key,
    match_id        bigint not null unique references match_results (match_id),
    reason_code     text not null,
    amount_on_hold  numeric(12,2) not null default 0,
    status          text not null default 'OPEN' check (status in ('OPEN', 'APPROVED', 'HELD', 'REJECTED')),
    created_at      timestamptz not null default now()
);
comment on table exceptions is 'SYNTHETIC: simulated AP exceptions.';

-- SYNTHETIC: what the AP clerk decided on each exception. Append-only, like request_events.
create table if not exists exception_actions (
    action_id     bigint generated always as identity primary key,
    exception_id  bigint not null references exceptions (exception_id),
    action        text not null check (action in ('APPROVE', 'HOLD', 'REJECT')),
    actor_role    text not null default 'AP_CLERK',
    note          text,
    acted_at      timestamptz not null default now()
);
comment on table exception_actions is 'SYNTHETIC: simulated AP clerk actions.';
