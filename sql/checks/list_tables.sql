-- Check: which Triage tables exist, how many columns each has, and whether it's labeled SYNTHETIC.
-- Expect 21 rows.
select
    t.table_name,
    count(c.column_name)                          as columns,
    obj_description(('public.' || t.table_name)::regclass) as label
from information_schema.tables t
join information_schema.columns c
  on c.table_schema = t.table_schema and c.table_name = t.table_name
where t.table_schema = 'public'
group by t.table_name
order by t.table_name;
