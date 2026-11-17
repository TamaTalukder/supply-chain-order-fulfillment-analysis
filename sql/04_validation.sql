/* =====================================================================
   04_validation.sql
   Project : Supply Chain Order Fulfillment & Inventory Optimization
   Stage   : 4 - SQL validation
   Database: MySQL 8 (supply_chain_db)

   Read-only checks (SELECT only) on the loaded tables.
   Each check states the expected result. If a check fails, fix the
   cause in the cleaning notebook, reload the tables and run this again.
   ===================================================================== */

USE supply_chain_db;


/* =====================================================================
   A. ROW COUNTS, TOTALS AND LINKS
   ===================================================================== */

-- A1. Row counts of all five tables.
--     Expected: staging = orders = shipping; customers and products are smaller.

SELECT 'stg_clean_orders' AS table_name, COUNT(*) AS row_count FROM stg_clean_orders
UNION ALL SELECT 'customers', COUNT(*) FROM customers
UNION ALL SELECT 'products',  COUNT(*) FROM products
UNION ALL SELECT 'orders',    COUNT(*) FROM orders
UNION ALL SELECT 'shipping',  COUNT(*) FROM shipping;

-- A2. Totals match between staging and final tables.
SELECT (SELECT ROUND(SUM(sales), 2) FROM stg_clean_orders) AS staging_sales,
       (SELECT ROUND(SUM(sales), 2) FROM orders)           AS orders_sales,
       (SELECT ROUND(SUM(order_profit_per_order), 2) FROM stg_clean_orders) AS staging_profit,
       (SELECT ROUND(SUM(order_profit_per_order), 2) FROM orders)           AS orders_profit;

-- A3. Orders with no shipping row. Expected: 0.
SELECT COUNT(*) AS orders_without_shipping
FROM orders o
LEFT JOIN shipping s ON o.order_item_id = s.order_item_id
WHERE s.order_item_id IS NULL;

-- A4. Orders pointing to a missing customer or product. Expected: 0 and 0.
SELECT COUNT(*) AS orders_without_customer
FROM orders o
LEFT JOIN customers c ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;

SELECT COUNT(*) AS orders_without_product
FROM orders o
LEFT JOIN products p ON o.product_card_id = p.product_card_id
WHERE p.product_card_id IS NULL;


/* =====================================================================
   B. NULL AND EMPTY VALUES
   In MySQL, "col IS NULL" gives 1 or 0, so SUM counts the problems.
   ===================================================================== */

-- B1. NULLs in important columns of orders. Expected: all 0.
SELECT SUM(order_id IS NULL)            AS null_order_id,
       SUM(order_date IS NULL)          AS null_order_date,
       SUM(customer_id IS NULL)         AS null_customer_id,
       SUM(product_card_id IS NULL)     AS null_product_id,
       SUM(sales IS NULL)               AS null_sales,
       SUM(order_item_quantity IS NULL) AS null_quantity
FROM orders;

-- B2. NULLs in shipping. Expected: all 0.
SELECT SUM(shipping_date IS NULL)  AS null_shipping_date,
       SUM(shipping_mode IS NULL)  AS null_shipping_mode,
       SUM(delay_days IS NULL)     AS null_delay_days,
       SUM(order_region IS NULL)   AS null_region,
       SUM(market IS NULL)         AS null_market
FROM shipping;

-- B3. Empty text (a blank string is not NULL). Expected: all 0.
SELECT SUM(TRIM(shipping_mode) = '')   AS empty_shipping_mode,
       SUM(TRIM(order_region) = '')    AS empty_region,
       SUM(TRIM(order_country) = '')   AS empty_country,
       SUM(TRIM(delivery_status) = '') AS empty_delivery_status
FROM shipping;

SELECT SUM(TRIM(product_name) = '')    AS empty_product_name,
       SUM(TRIM(category_name) = '')   AS empty_category_name,
       SUM(TRIM(department_name) = '') AS empty_department_name
FROM products;


/* =====================================================================
   C. VALUES MAKE SENSE
   ===================================================================== */

-- C1. Zero or negative quantity, sales or price.
--  Expected: 0 and 0, then 0.
SELECT SUM(order_item_quantity <= 0) AS bad_quantity,
       SUM(sales < 0)                AS negative_sales
FROM orders;

SELECT SUM(product_price <= 0) AS bad_price FROM products;

-- C2. Delay range. Expected (DataCo): 
-- about -4 to +4 days.
SELECT MIN(delay_days) AS min_delay, MAX(delay_days) AS max_delay,
       ROUND(AVG(delay_days), 2) AS avg_delay
FROM shipping;

-- C3. delay_days = real minus scheduled days. Expected: 0.
SELECT COUNT(*) AS wrong_delay_days
FROM shipping
WHERE delay_days <> shipping_days_real - shipping_days_scheduled;

-- C4. is_late is consistent with delay_days. Expected: 0.
SELECT COUNT(*) AS wrong_is_late
FROM shipping
WHERE is_late <> (delay_days > 0);

-- C5. is_late against the dataset's own late_delivery_risk.
--     Expected: 0, or a small number that can be explained.
SELECT COUNT(*) AS late_flag_disagree
FROM shipping
WHERE is_late <> late_delivery_risk;

-- C6. Shipping must not happen before the order. Expected: 0.
SELECT COUNT(*) AS shipped_before_ordered
FROM orders o
JOIN shipping s ON o.order_item_id = s.order_item_id
WHERE s.shipping_date < o.order_date;

-- C7. is_canceled agrees with order_status. Expected: 0.
SELECT COUNT(*) AS wrong_canceled_flag
FROM orders
WHERE is_canceled <> (order_status = 'CANCELED');

-- C8. Allowed values. Expected: no spelling twins in any list.
SELECT shipping_mode,    COUNT(*) AS n FROM shipping GROUP BY shipping_mode;
SELECT delivery_status,  COUNT(*) AS n FROM shipping GROUP BY delivery_status;
SELECT order_status,     COUNT(*) AS n FROM orders   GROUP BY order_status;
SELECT customer_segment, COUNT(*) AS n FROM customers GROUP BY customer_segment;
SELECT market,           COUNT(*) AS n FROM shipping GROUP BY market;


/* =====================================================================
   D. DUPLICATES AND ONE-TO-ONE RULES
   ===================================================================== */

-- D1. Duplicate order lines. Expected: empty result.
SELECT order_item_id, COUNT(*) AS n
FROM orders
GROUP BY order_item_id
HAVING COUNT(*) > 1;

-- D2. Same product twice in the same order (informational).
SELECT COUNT(*) AS orders_with_repeated_product
FROM (SELECT order_id, product_card_id
      FROM orders
      GROUP BY order_id, product_card_id
      HAVING COUNT(*) > 1) AS t;

-- D3. One customer per order. Expected: empty result.
SELECT order_id, COUNT(DISTINCT customer_id) AS customers
FROM orders
GROUP BY order_id
HAVING COUNT(DISTINCT customer_id) > 1;

-- D4. One order date per order. Expected: empty result.
SELECT order_id, COUNT(DISTINCT order_date) AS dates
FROM orders
GROUP BY order_id
HAVING COUNT(DISTINCT order_date) > 1;

-- D5. Orders with more than one shipping mode (informational).
--     If any exist, delivery KPIs are counted per order line, not per order.
SELECT COUNT(*) AS orders_with_many_modes
FROM (SELECT o.order_id
      FROM orders o
      JOIN shipping s ON o.order_item_id = s.order_item_id
      GROUP BY o.order_id
      HAVING COUNT(DISTINCT s.shipping_mode) > 1) AS t;

-- D6. Each order line has exactly one shipping row. Expected: 0.
SELECT COUNT(*) AS lines_with_wrong_shipping_count
FROM (SELECT o.order_item_id
      FROM orders o
      LEFT JOIN shipping s ON o.order_item_id = s.order_item_id
      GROUP BY o.order_item_id
      HAVING COUNT(s.order_item_id) <> 1) AS t;
