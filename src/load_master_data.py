"""Load master data: real GUDID items and packages, plus SYNTHETIC suppliers, units and par levels.

Run:  python src/load_master_data.py   (after sql/schema.sql)
Safe to re-run: rows that already exist are skipped, never duplicated.
A fixed random seed means everyone gets the same synthetic values.
"""

import json
import random

import psycopg

from check_connection import get_database_url

SNAPSHOT_PATH = "data/gudid_sample.json"
rng = random.Random(42)   # fixed seed: same synthetic data on every run and every computer

# SYNTHETIC: made-up distributors (not real companies).
SUPPLIERS = ["Northgate Medical Supply", "Bluepeak Clinical Distribution", "Cedar Valley Healthcare Products"]

# SYNTHETIC: hospital units.
UNITS = [
    ("4W", "4 West Med-Surg"),
    ("ICU", "Intensive Care Unit"),
    ("ED", "Emergency Department"),
    ("PEDS", "Pediatrics"),
]
ITEMS_PER_UNIT = 30
PAR_LOCATIONS = ["Supply room", "Clean utility room", "Med room cart"]

# SYNTHETIC: price per each (EA), and typical par in eaches, by category.
PRICE_RANGE = {"SYRINGE": (0.10, 0.60), "IV_CATHETER": (1.50, 4.00), "EXAM_GLOVE": (0.05, 0.15)}
PAR_RANGE = {"SYRINGE": (100, 400), "IV_CATHETER": (20, 80), "EXAM_GLOVE": (500, 2000)}
STOCK_SHARE = 0.7   # about 70% of items kept in the storeroom, the rest ordered from suppliers


def load_suppliers(conn) -> list[int]:
    for name in SUPPLIERS:
        conn.execute("insert into suppliers (supplier_name) values (%s) on conflict do nothing", (name,))
    return [row[0] for row in conn.execute("select supplier_id from suppliers order by supplier_id")]


def load_items(conn, devices: list[dict], supplier_ids: list[int]) -> dict[int, str]:
    """Insert each real device and its real packages. Returns {item_id: category}."""
    items = {}
    for d in devices:
        # SYNTHETIC fields: GUDID has no stocking, price or supplier data.
        item_type = "STOCK" if rng.random() < STOCK_SHARE else "NON_STOCK"
        low, high = PRICE_RANGE[d["category"]]
        unit_price = round(rng.uniform(low, high), 4)
        supplier_id = rng.choice(supplier_ids)

        row = conn.execute(
            """
            insert into items (primary_di, brand_name, version_model, company_name, device_description,
                               category, base_package_count, item_type, unit_price, default_supplier_id)
            values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            on conflict (primary_di) do update set primary_di = excluded.primary_di
            returning item_id
            """,
            (d["primary_di"], d["brand_name"], d["version_model"], d["company_name"], d["device_description"],
             d["category"], d["device_count_in_base_package"], item_type, unit_price, supplier_id),
        ).fetchone()
        item_id = row[0]
        items[item_id] = d["category"]

        for p in d["packages"]:
            conn.execute(
                """
                insert into item_packages (item_id, package_di, package_type, quantity, contains_di)
                values (%s, %s, %s, %s, %s)
                on conflict (package_di) do nothing
                """,
                (item_id, p["package_di"], p["package_type"], p["quantity"], p["contains_di"]),
            )
    return items


def load_units_and_par_levels(conn, items: dict[int, str]) -> None:
    item_ids = sorted(items)
    for code, name in UNITS:
        unit_id = conn.execute(
            """
            insert into units (unit_code, unit_name) values (%s, %s)
            on conflict (unit_code) do update set unit_name = excluded.unit_name
            returning unit_id
            """,
            (code, name),
        ).fetchone()[0]

        # Each unit stocks a different subset of items at its par locations.
        for item_id in rng.sample(item_ids, ITEMS_PER_UNIT):
            low, high = PAR_RANGE[items[item_id]]
            par_qty = rng.randrange(low, high, 10)
            on_hand = int(par_qty * rng.uniform(0.3, 1.0))   # somewhere between 30% and full
            conn.execute(
                """
                insert into par_levels (unit_id, item_id, par_location, par_qty_base, on_hand_base)
                values (%s, %s, %s, %s, %s)
                on conflict do nothing
                """,
                (unit_id, item_id, rng.choice(PAR_LOCATIONS), par_qty, on_hand),
            )


def main() -> None:
    with open(SNAPSHOT_PATH) as f:
        devices = json.load(f)["devices"]

    # One transaction: if anything fails, nothing is saved.
    with psycopg.connect(get_database_url()) as conn:
        supplier_ids = load_suppliers(conn)
        items = load_items(conn, devices, supplier_ids)
        load_units_and_par_levels(conn, items)

    print(f"Loaded {len(SUPPLIERS)} suppliers, {len(items)} items, {len(UNITS)} units, "
          f"{len(UNITS) * ITEMS_PER_UNIT} par levels")


if __name__ == "__main__":
    main()
