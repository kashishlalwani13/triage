-- DEVELOPMENT ONLY: deletes every Triage table and all its data, so sql/schema.sql can rebuild from scratch.
-- Use it when the schema changes. Never run it against a database whose data you need.
drop table if exists
    exception_actions, exceptions, match_results, integration_errors, integration_log,
    invoice_lines, invoices, receipt_lines, receipts, po_lines, purchase_orders,
    erp_requisitions, pages, request_events, requests,
    par_levels, units, uom_conversions, item_packages, items, suppliers
cascade;
