-- Check: number of rows in every Triage table, grouped by kind.
select 'master'      as kind, 'suppliers'          as table_name, count(*) as row_count from suppliers
union all select 'master',      'items',              count(*) from items
union all select 'master',      'item_packages',      count(*) from item_packages
union all select 'master',      'uom_conversions',    count(*) from uom_conversions
union all select 'master',      'units',              count(*) from units
union all select 'master',      'par_levels',         count(*) from par_levels
union all select 'transaction', 'requests',           count(*) from requests
union all select 'transaction', 'request_events',     count(*) from request_events
union all select 'transaction', 'pages',              count(*) from pages
union all select 'transaction', 'erp_requisitions',   count(*) from erp_requisitions
union all select 'transaction', 'purchase_orders',    count(*) from purchase_orders
union all select 'transaction', 'po_lines',           count(*) from po_lines
union all select 'transaction', 'receipts',           count(*) from receipts
union all select 'transaction', 'receipt_lines',      count(*) from receipt_lines
union all select 'transaction', 'invoices',           count(*) from invoices
union all select 'transaction', 'invoice_lines',      count(*) from invoice_lines
union all select 'log',         'integration_log',    count(*) from integration_log
union all select 'log',         'integration_errors', count(*) from integration_errors
union all select 'log',         'match_results',      count(*) from match_results
union all select 'log',         'exceptions',         count(*) from exceptions
union all select 'log',         'exception_actions',  count(*) from exception_actions;
