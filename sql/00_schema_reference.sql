-- ======================================================================
-- Reference schema for the raw table (reconstructed from the columns used in this project)
-- Adjust data types if your import differs. The raw table is never modified after import.
-- ======================================================================
CREATE TABLE IF NOT EXISTS retail_raw (
    category        TEXT,
    city            TEXT,
    country         TEXT,
    customer_id     TEXT,
    customer_name   TEXT,
    discount        NUMERIC(5,3),
    market          TEXT,
    record_count    INTEGER,          -- source column with non-Latin header; constant = 1
    order_date      DATE,
    order_id        TEXT,
    order_priority  TEXT,
    product_id      TEXT,
    product_name    TEXT,
    profit          NUMERIC(14,4),
    quantity        INTEGER,
    region          TEXT,
    row_id          INTEGER,
    sales           NUMERIC(14,3),
    segment         TEXT,
    ship_date       DATE,
    ship_mode       TEXT,
    shipping_cost   NUMERIC(14,3),
    state           TEXT,
    sub_category    TEXT,
    year            INTEGER,
    market2         TEXT,
    week_num        INTEGER
);
-- Import (psql):  \copy retail_raw FROM 'Global_Superstore.csv' WITH (FORMAT csv, HEADER true)
-- (column order must match the CSV; pgAdmin's Import/Export wizard works too)
