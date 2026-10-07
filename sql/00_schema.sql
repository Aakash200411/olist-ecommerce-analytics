-- =====================================================================
-- 00_schema.sql : table definitions for the Olist public dataset
-- Dialect: PostgreSQL-compatible (also runs unchanged on DuckDB)
-- Note: product_*_lenght typos in the source CSV are corrected here.
-- Zip prefixes are VARCHAR on purpose (leading zeros matter).
-- =====================================================================
DROP TABLE IF EXISTS order_reviews;
DROP TABLE IF EXISTS order_payments;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS sellers;
DROP TABLE IF EXISTS geolocation;
DROP TABLE IF EXISTS category_translation;

CREATE TABLE customers (
    customer_id              VARCHAR PRIMARY KEY,   -- one per ORDER, not per person
    customer_unique_id       VARCHAR NOT NULL,      -- the real customer
    customer_zip_code_prefix VARCHAR,
    customer_city            VARCHAR,
    customer_state           VARCHAR
);

CREATE TABLE orders (
    order_id                       VARCHAR PRIMARY KEY,
    customer_id                    VARCHAR NOT NULL,
    order_status                   VARCHAR,
    order_purchase_timestamp       TIMESTAMP,
    order_approved_at              TIMESTAMP,
    order_delivered_carrier_date   TIMESTAMP,
    order_delivered_customer_date  TIMESTAMP,
    order_estimated_delivery_date  TIMESTAMP
);

CREATE TABLE products (
    product_id                 VARCHAR PRIMARY KEY,
    product_category_name      VARCHAR,
    product_name_length        INTEGER,
    product_description_length INTEGER,
    product_photos_qty         INTEGER,
    product_weight_g           INTEGER,
    product_length_cm          INTEGER,
    product_height_cm          INTEGER,
    product_width_cm           INTEGER
);

CREATE TABLE sellers (
    seller_id              VARCHAR PRIMARY KEY,
    seller_zip_code_prefix VARCHAR,
    seller_city            VARCHAR,
    seller_state           VARCHAR
);

CREATE TABLE order_items (
    order_id            VARCHAR NOT NULL,
    order_item_id       INTEGER NOT NULL,
    product_id          VARCHAR NOT NULL,
    seller_id           VARCHAR NOT NULL,
    shipping_limit_date TIMESTAMP,
    price               NUMERIC(10,2),
    freight_value       NUMERIC(10,2),
    PRIMARY KEY (order_id, order_item_id)
);

CREATE TABLE order_payments (
    order_id             VARCHAR NOT NULL,
    payment_sequential   INTEGER NOT NULL,
    payment_type         VARCHAR,
    payment_installments INTEGER,
    payment_value        NUMERIC(10,2),
    PRIMARY KEY (order_id, payment_sequential)
);

-- review_id is NOT unique in the source data (see 01_data_audit.sql),
-- so no primary key here.
CREATE TABLE order_reviews (
    review_id               VARCHAR NOT NULL,
    order_id                VARCHAR NOT NULL,
    review_score            INTEGER,
    review_comment_title    VARCHAR,
    review_comment_message  VARCHAR,
    review_creation_date    TIMESTAMP,
    review_answer_timestamp TIMESTAMP
);

CREATE TABLE geolocation (
    geolocation_zip_code_prefix VARCHAR,
    geolocation_lat             DOUBLE PRECISION,
    geolocation_lng             DOUBLE PRECISION,
    geolocation_city            VARCHAR,
    geolocation_state           VARCHAR
);

CREATE TABLE category_translation (
    product_category_name         VARCHAR PRIMARY KEY,
    product_category_name_english VARCHAR
);
