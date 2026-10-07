-- =====================================================================
-- 00b_load_postgres.sql : load the raw CSVs into PostgreSQL
-- Run from the project root with psql:
--     psql -d olist -f sql/00_schema.sql
--     psql -d olist -f sql/00b_load_postgres.sql
-- (\copy reads files from YOUR machine, so no server permissions needed)
-- The translation CSV starts with a UTF-8 BOM. If the first category key
-- looks odd after loading, re-save that one file as UTF-8 without BOM.
-- =====================================================================
\copy customers            FROM 'data/raw/olist_customers_dataset.csv'           WITH (FORMAT csv, HEADER true)
\copy orders               FROM 'data/raw/olist_orders_dataset.csv'              WITH (FORMAT csv, HEADER true)
\copy products             FROM 'data/raw/olist_products_dataset.csv'            WITH (FORMAT csv, HEADER true)
\copy sellers              FROM 'data/raw/olist_sellers_dataset.csv'             WITH (FORMAT csv, HEADER true)
\copy order_items          FROM 'data/raw/olist_order_items_dataset.csv'         WITH (FORMAT csv, HEADER true)
\copy order_payments       FROM 'data/raw/olist_order_payments_dataset.csv'      WITH (FORMAT csv, HEADER true)
\copy order_reviews        FROM 'data/raw/olist_order_reviews_dataset.csv'       WITH (FORMAT csv, HEADER true)
\copy geolocation          FROM 'data/raw/olist_geolocation_dataset.csv'         WITH (FORMAT csv, HEADER true)
\copy category_translation FROM 'data/raw/product_category_name_translation.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

CREATE INDEX idx_orders_customer  ON orders(customer_id);
CREATE INDEX idx_orders_purchase  ON orders(order_purchase_timestamp);
CREATE INDEX idx_items_product    ON order_items(product_id);
CREATE INDEX idx_items_seller     ON order_items(seller_id);
CREATE INDEX idx_reviews_order    ON order_reviews(order_id);
CREATE INDEX idx_customers_unique ON customers(customer_unique_id);
