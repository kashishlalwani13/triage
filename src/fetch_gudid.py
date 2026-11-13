"""Download a small sample of REAL devices from the FDA GUDID (via openFDA) and save a snapshot.

Run:  python src/fetch_gudid.py
Output: data/gudid_sample.json

The snapshot is saved to the repo so everyone gets the same devices, even after openFDA updates.
Only devices with a complete packaging chain are kept, because packaging drives the UOM conversions.
"""

import json
from datetime import datetime, timezone
from pathlib import Path

import requests

OPENFDA_URL = "https://api.fda.gov/device/udi.json"
OUTPUT_PATH = Path("data/gudid_sample.json")

# FDA product codes for the three med-surg categories.
CATEGORIES = {
    "SYRINGE": "FMF",       # Syringe, Piston
    "IV_CATHETER": "FOZ",   # Catheter, Intravascular, Therapeutic, Short-Term
    "EXAM_GLOVE": "LYZ",    # Polymer Patient Examination Glove
}
DEVICES_PER_CATEGORY = 67   # about 200 in total
FETCH_LIMIT = 300           # fetch extra, because some records get filtered out


def fetch_records(product_code: str) -> list[dict]:
    query = (
        f"product_codes.code:{product_code}"
        ' AND commercial_distribution_status:"In Commercial Distribution"'
        " AND _exists_:identifiers.quantity_per_package"
    )
    response = requests.get(OPENFDA_URL, params={"search": query, "limit": FETCH_LIMIT}, timeout=30)
    response.raise_for_status()
    return response.json()["results"]


def extract_packaging(record: dict) -> tuple[str, list[dict]] | None:
    """Return (primary DI, package levels), or None if the packaging chain is incomplete."""
    identifiers = record.get("identifiers", [])
    primary = [i["id"] for i in identifiers if i.get("type") == "Primary"]
    if len(primary) != 1:
        return None

    packages = []
    for ident in identifiers:
        if ident.get("type") != "Package":
            continue
        if ident.get("package_status", "In Commercial Distribution") != "In Commercial Distribution":
            continue   # discontinued package levels would give stale conversions
        qty = ident.get("quantity_per_package")
        if not qty or not qty.isdigit() or int(qty) <= 0:
            return None
        packages.append({
            "package_di": ident["id"],
            "package_type": ident.get("package_type"),
            "quantity": int(qty),
            "contains_di": ident.get("unit_of_use_id"),
        })

    # Every package must point to the primary DI or to another package, or we can't convert it to each.
    known = {primary[0]} | {p["package_di"] for p in packages}
    if not packages or any(p["contains_di"] not in known for p in packages):
        return None
    return primary[0], packages


def to_device(record: dict, category: str) -> dict | None:
    packaging = extract_packaging(record)
    if packaging is None:
        return None
    primary_di, packages = packaging
    base_count = record.get("device_count_in_base_package") or "1"
    gmdn = record.get("gmdn_terms") or [{}]
    return {
        "category": category,
        "primary_di": primary_di,
        "brand_name": record.get("brand_name"),
        "version_model": record.get("version_or_model_number"),
        "company_name": record.get("company_name"),
        "device_description": record.get("device_description"),
        "gmdn_term": gmdn[0].get("name"),
        # How many devices the primary DI holds (e.g. 100 for a box of gloves).
        "device_count_in_base_package": int(base_count) if base_count.isdigit() else 1,
        "packages": packages,
    }


def main() -> None:
    devices = []
    for category, product_code in CATEGORIES.items():
        seen = set()
        kept = []
        for record in fetch_records(product_code):
            device = to_device(record, category)
            if device and device["primary_di"] not in seen:
                seen.add(device["primary_di"])
                kept.append(device)
            if len(kept) == DEVICES_PER_CATEGORY:
                break
        print(f"{category}: kept {len(kept)} devices")
        devices.extend(kept)

    snapshot = {
        "source": "FDA GUDID via openFDA (" + OPENFDA_URL + ")",
        "fetched_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "product_codes": CATEGORIES,
        "device_count": len(devices),
        "devices": devices,
    }
    OUTPUT_PATH.parent.mkdir(exist_ok=True)
    OUTPUT_PATH.write_text(json.dumps(snapshot, indent=2))
    print(f"Saved {len(devices)} real devices to {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
