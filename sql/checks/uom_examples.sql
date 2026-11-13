-- Check: conversions for one real device per category. Compare with the FDA packaging by hand.
-- Ceros syringe: BX = 100, CS = 800. Unolok IV catheter: BX = 100, CT = 1000. MedClick glove: BP = 100, CS = 1000.
select i.category, i.brand_name, c.uom, c.base_units_per_uom as eaches, c.source
from uom_conversions c
join items i on i.item_id = c.item_id
where i.primary_di in ('00850060997426', '08903347003289', '00850084857324')
order by i.category, c.base_units_per_uom;
