"""
build_db.py : build a local DuckDB database from the raw Olist CSVs.

DuckDB needs no server, so anyone can reproduce the project with:
    pip install duckdb pandas
    python scripts/build_db.py

The SQL files in /sql use the PostgreSQL-compatible subset, so the same
queries also run on PostgreSQL (load it with sql/00b_load_postgres.sql).
"""
import sys
from pathlib import Path
import duckdb

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "data" / "raw"
DB = ROOT / "data" / "olist.duckdb"

# table -> (csv file, expected row count in the official Kaggle release)
FILES = {
    "customers":            ("olist_customers_dataset.csv", 99441),
    "orders":               ("olist_orders_dataset.csv", 99441),
    "products":             ("olist_products_dataset.csv", 32951),
    "sellers":              ("olist_sellers_dataset.csv", 3095),
    "order_items":          ("olist_order_items_dataset.csv", 112650),
    "order_payments":       ("olist_order_payments_dataset.csv", 103886),
    "order_reviews":        ("olist_order_reviews_dataset.csv", 99224),  # current Kaggle release; an older release has 100,000
    "geolocation":          ("olist_geolocation_dataset.csv", 1000163),
    "category_translation": ("product_category_name_translation.csv", 71),
}
# zip prefixes must be read as text or leading zeros are lost ("01037" -> 1037)
ZIP_COL = {
    "customers": "customer_zip_code_prefix",
    "sellers": "seller_zip_code_prefix",
    "geolocation": "geolocation_zip_code_prefix",
}

def main() -> int:
    missing = [f for f, _ in FILES.values() if not (RAW / f).exists()]
    if missing:
        print("Missing files in data/raw/:", *missing, sep="\n  ")
        print("See data/README.md for download instructions.")
        return 1

    if DB.exists():
        DB.unlink()
    con = duckdb.connect(str(DB))
    con.execute((ROOT / "sql" / "00_schema.sql").read_text())

    ok = True
    for table, (csv, expected) in FILES.items():
        path = (RAW / csv).as_posix()
        # positional insert: column order in the CSVs matches the schema
        types = f", types={{'{ZIP_COL[table]}':'VARCHAR'}}" if table in ZIP_COL else ""
        con.execute(
            f"INSERT INTO {table} SELECT * FROM "
            f"read_csv('{path}', header=true{types})"
        )
        n = con.execute(f"SELECT count(*) FROM {table}").fetchone()[0]
        good = (n == expected) or (table == 'order_reviews' and n == 100000)   # older release
        ok &= good
        print(f"{'OK      ' if good else 'MISMATCH'} {table:22s} {n:>10,} rows (expected {expected:,})")
    con.close()
    print("\nDatabase built:" if ok else "\nBuilt WITH ROW-COUNT MISMATCHES, check your CSVs:", DB)
    return 0 if ok else 2

if __name__ == "__main__":
    sys.exit(main())
