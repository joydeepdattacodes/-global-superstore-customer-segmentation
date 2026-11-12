# Data

The raw dataset is **not committed** to this repository (file size and redistribution terms).

**Dataset:** Global Superstore transaction-line data - 51,290 rows x 27 fields, order dates 2011-01-01 to 2014-12-31.

**To reproduce**
1. Download the Global Superstore CSV from its public source.
2. Create the table with [`sql/00_schema_reference.sql`](../sql/00_schema_reference.sql) and import the CSV into `retail_raw`.
3. Run the SQL scripts in order, then the notebooks (`notebooks/01` exports `customer_features.csv`, which notebooks 02 and 03 read).
