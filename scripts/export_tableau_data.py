
from pathlib import Path
import duckdb

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "data" / "olist.duckdb"
OUTPUT_DIR = ROOT / "outputs" / "tableau"
OUTPUT_FILE = OUTPUT_DIR / "orders_analytics.csv"


def main():
    if not DB_PATH.exists():
        raise FileNotFoundError(
            f"Database not found: {DB_PATH}\n"
            "Run python scripts/build_db.py first."
        )

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    con = duckdb.connect(str(DB_PATH), read_only=True)

    try:
        query = """
        WITH category_per_order AS (
            SELECT
                order_id,
                string_agg(
                    DISTINCT category,
                    ', ' ORDER BY category
                ) AS categories,
                COUNT(DISTINCT category) AS category_count
            FROM v_item_detail
            GROUP BY order_id
        )

        SELECT
            a.order_id,
            a.customer_unique_id,
            a.customer_state,
            a.order_status,

            a.purchased_at,
            CAST(date_trunc('month', a.purchased_at) AS DATE)
                AS purchase_month,
            a.delivered_at,
            a.estimated_at,

            a.n_items,
            a.n_sellers,
            a.items_value,
            a.freight_value,
            a.order_total,

            a.review_score,
            a.delivery_days,
            a.promised_days,
            a.days_late,
            a.is_late,

            CASE
                WHEN a.is_late = 1 THEN 'Late'
                ELSE 'On time / early'
            END AS delivery_status,

            CASE
                WHEN a.review_score <= 2 THEN 1
                ELSE 0
            END AS low_review_flag,

            CASE
                WHEN a.review_score IS NOT NULL THEN 1
                ELSE 0
            END AS has_review,

            COALESCE(c.categories, 'unknown') AS categories,
            COALESCE(c.category_count, 0) AS category_count

        FROM v_analysis_orders a
        LEFT JOIN category_per_order c
            ON a.order_id = c.order_id

        ORDER BY a.purchased_at
        """

        df = con.execute(query).df()

        # Guard against accidental row multiplication.
        if df["order_id"].duplicated().any():
            raise ValueError("Duplicate order IDs detected in export.")

        df.to_csv(OUTPUT_FILE, index=False)

        print(f"Export created: {OUTPUT_FILE}")
        print(f"Rows: {len(df):,}")
        print(f"Unique orders: {df['order_id'].nunique():,}")
        print(f"GMV (item value): R${df['items_value'].sum():,.2f}")
        print(
            "Late-delivery rate: "
            f"{df['is_late'].mean() * 100:.2f}%"
        )
        print(f"Columns: {len(df.columns)}")

    finally:
        con.close()


if __name__ == "__main__":
    main()
