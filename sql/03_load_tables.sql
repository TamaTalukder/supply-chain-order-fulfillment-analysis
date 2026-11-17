/* =====================================================================
   03_load_tables.sql
   Project : Supply Chain Order Fulfillment & Inventory Optimization
   Stage   : 3 - Load data into MySQL
   Database: MySQL 8 (supply_chain_db)

   Run order: 03_create_tables.sql, then this script.
   A. Load clean_orders.csv into the staging table
   B. Check staging against the Python numbers
   C. Fill customers, products, orders and shipping from staging
   D. Check the final tables

   Requires clean_orders.csv in the folder MySQL allows (see A1).
   ===================================================================== */

USE supply_chain_db;


/* =====================================================================
   A. LOAD THE CSV INTO THE STAGING TABLE
   ===================================================================== */

/* A1. Folder MySQL may read files from (column "Value").
   Copy clean_orders.csv into it and use / (forward slash) in the path.
   NULL = setting is off, LOAD DATA INFILE is blocked.
   Empty = MySQL can read from anywhere. */
   
SHOW VARIABLES LIKE 'secure_file_priv';

/* A2. The staging table must be empty. 
Expected: 0. 
*/
SELECT COUNT(*) FROM stg_clean_orders;

/* A3. Load. Change the path to your own folder from A1.
   If the row count is off on a Windows CSV, use '\r\n' for LINES TERMINATED BY. 
   */

LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/clean_orders.csv'
INTO TABLE stg_clean_orders
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

/* A4. Warnings. Expected: empty result. */
SHOW WARNINGS;


/* =====================================================================
   B. CHECK STAGING AGAINST PYTHON
   Python numbers come from the end of the cleaning notebook .
   ===================================================================== */

/* B1. Row count. Expected: 180,519 */
SELECT COUNT(*) FROM stg_clean_orders;

/* B2. First and last order date. Compare with min and max of order_date in Python. */
SELECT MIN(order_date), MAX(order_date) FROM stg_clean_orders;

/* B3. Total sales. Must equal the Python total (36,784,734.31). */
SELECT ROUND(SUM(sales), 2) FROM stg_clean_orders;

/* B4. Look at five rows for shifted columns or broken accents. */
SELECT * FROM stg_clean_orders LIMIT 5;

/* B5. Shape of the data. Expected: 180,519 rows, 65,752 orders,
   20,652 customers, 118 products. */
SELECT COUNT(*) AS total_rows,
       COUNT(DISTINCT order_id) AS different_orders,
       COUNT(DISTINCT customer_id) AS different_customers,
       COUNT(DISTINCT product_card_id) AS different_products
FROM stg_clean_orders;


/* =====================================================================
   C. FILL THE FINAL TABLES FROM STAGING
   Run in this order (customers and products first).
   ===================================================================== */

INSERT INTO customers (customer_id, customer_segment)
SELECT DISTINCT customer_id, customer_segment
FROM stg_clean_orders;

INSERT INTO products (product_card_id, product_name, category_id, category_name, department_name, product_price)
SELECT DISTINCT product_card_id, product_name, category_id, category_name, department_name, product_price
FROM stg_clean_orders;

INSERT INTO orders (order_item_id, order_id, order_date, customer_id, product_card_id, order_status,
                    order_item_quantity, order_item_discount, sales, order_item_total,
                    order_profit_per_order, is_canceled)
SELECT order_item_id, order_id, order_date, customer_id, product_card_id, order_status,
       order_item_quantity, order_item_discount, sales, order_item_total,
       order_profit_per_order, is_canceled
FROM stg_clean_orders;

INSERT INTO shipping (order_item_id, shipping_date, shipping_mode, shipping_days_real,
                      shipping_days_scheduled, delay_days, is_late, delivery_status,
                      late_delivery_risk, market, order_region, order_country)
SELECT order_item_id, shipping_date, shipping_mode, shipping_days_real,
       shipping_days_scheduled, delay_days, is_late, delivery_status,
       late_delivery_risk, market, order_region, order_country
FROM stg_clean_orders;


/* =====================================================================
   D. CHECK THE FINAL TABLES
   ===================================================================== */

/* D1. Row counts. orders and shipping = staging rows (B1);
   customers and products = distinct counts (B5). */
SELECT COUNT(*) FROM customers;
SELECT COUNT(*) FROM products;
SELECT COUNT(*) FROM orders;
SELECT COUNT(*) FROM shipping;

/* D2. Join check. Must return the same number as orders. */
SELECT COUNT(*)
FROM orders o
JOIN shipping s  ON o.order_item_id = s.order_item_id
JOIN customers c ON o.customer_id = c.customer_id
JOIN products p  ON o.product_card_id = p.product_card_id;

/* D3. Total sales from the final table. Must equal B3. */
SELECT ROUND(SUM(sales), 2) FROM orders;

/* D4. Any customer with two segments in staging? Expected: empty result. */
SELECT customer_id, COUNT(DISTINCT customer_segment) AS segments
FROM stg_clean_orders
GROUP BY customer_id
HAVING COUNT(DISTINCT customer_segment) > 1;



