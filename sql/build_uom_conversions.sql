-- Build uom_conversions from the real GUDID packaging in item_packages.
-- Result: for every item, how many eaches (EA) are in one of each package size.
-- Rebuilt from scratch on every run, so it always matches item_packages.

delete from uom_conversions;

with recursive chain as (
    -- Start at the smallest FDA-registered unit (the primary DI).
    -- Usually it is 1 device; for many gloves it is already a pack of 100 (base_package_count).
    select i.item_id, i.primary_di as di, i.base_package_count::numeric as eaches,
           null::text as package_type, 0 as level
    from items i

    union all

    -- Walk up one package level at a time: a box of 100 singles, a case of 8 boxes = 800, and so on.
    select c.item_id, p.package_di, p.quantity * c.eaches, p.package_type, c.level + 1
    from chain c
    join item_packages p on p.item_id = c.item_id and p.contains_di = c.di
    where c.level < 10   -- guard against bad data that loops back on itself
),

named as (
    -- Clean the free-text package type into a short UOM code. First matching rule wins.
    select item_id, eaches,
        case
            when level = 0 then 'BP'   -- base package: FDA gives no name for it, so we don't invent one
            when lower(trim(package_type)) in ('cs', 'ca') or lower(package_type) like '%case%' then 'CS'
            when lower(package_type) like '%carton%'                                       then 'CT'
            when lower(trim(package_type)) = 'bx' or lower(package_type) like '%box%'      then 'BX'
            when lower(package_type) like '%pack%'                                         then 'PK'
            when lower(package_type) like '%tray%'                                         then 'TR'
            when lower(package_type) like '%bag%' or lower(package_type) like '%pouch%'    then 'BG'
            when lower(package_type) like 'pal%'                                           then 'PL'
            else 'PKG'   -- missing or unclear name (e.g. '', '604'): kept, but flagged as unknown
        end as code
    from chain
    where not (level = 0 and eaches = 1)   -- a base unit of 1 device is just EA, added below
),

numbered as (
    -- If one item has two levels with the same code (inner box and outer box), the bigger one becomes BX2.
    select item_id, eaches,
        code || case when rn = 1 then '' else rn::text end as uom
    from (
        select item_id, eaches, code,
               row_number() over (partition by item_id, code order by eaches) as rn
        from named
    ) ranked
)

insert into uom_conversions (item_id, uom, base_units_per_uom, source)
select item_id, 'EA', 1, 'BASE' from items          -- every item: 1 EA = 1 EA
union all
select item_id, uom, eaches, 'GUDID' from numbered;  -- every package size, from real FDA data
