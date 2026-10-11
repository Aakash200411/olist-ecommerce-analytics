
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "data" / "olist.duckdb"
OUTPUT_DIR = ROOT / "outputs" / "tableau"
OUTPUT_PATH = OUTPUT_DIR / "seller_delivery_analytics.csv"

OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

con = duckdb.connect(str(DB_PATH), read_only=True)

query = """
WITH seller_orders AS (
    SELECT DISTINCT
        oi.order_id,
        oi.seller_id,
        o.order_status,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date
    FROM order_items oi
    JOIN orders o
        ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
)
SELECT
    seller_id,
    COUNT(*) AS delivered_orders,
    SUM(
        CASE
            WHEN order_delivered_customer_date
                 > order_estimated_delivery_date
            THEN 1 ELSE 0
        END
    ) AS late_orders,
    AVG(
        CASE
            WHEN order_delivered_customer_date
                 > order_estimated_delivery_date
            THEN 1.0 ELSE 0.0
        END
    ) AS late_delivery_rate
FROM seller_orders
GROUP BY seller_id
ORDER BY delivered_orders DESC
"""

df = con.execute(query).fetchdf()
df.to_csv(OUTPUT_PATH, index=False)

print(f"Export created: {OUTPUT_PATH}")
print(f"Seller rows: {len(df):,}")
print(f"Total delivered seller-order records: {df['delivered_orders'].sum():,}")
print(f"Late-delivery rate range: "
      f"{df['late_delivery_rate'].min():.2%}–"
      f"{df['late_delivery_rate'].max():.2%}")

con.close()
