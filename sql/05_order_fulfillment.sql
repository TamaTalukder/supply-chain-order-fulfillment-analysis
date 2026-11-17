/* =====================================================================
   05_order_fulfillment.sql
   Project : Supply Chain Order Fulfillment & Inventory Optimization
   Stage   : 5 - Order fulfillment analysis
   Database: MySQL 8 (supply_chain_db)

   Business question: why are orders late, and where (shipping mode,
   market, region, category, product, month)?

   Definitions
   - Unit: one order line (one row of orders / shipping), not a whole order.
   - Canceled lines are excluded (is_canceled = 0): they never reached
     the customer, so "late" has no meaning.
   - Late: shipping_days_real > shipping_days_scheduled (is_late = 1).
   - late_pct: share of lines that were late, in percent.
   ===================================================================== */

USE supply_chain_db;


-- 5.1 Overall KPIs.
--     Expected: 176,827 lines, late_pct 57.28.
SELECT COUNT(*)                         AS order_lines,
       COUNT(DISTINCT o.order_id)       AS different_orders,
       SUM(s.is_late)                   AS late_lines,
       ROUND(100 * AVG(s.is_late), 2)   AS late_pct,
       ROUND(AVG(s.delay_days), 2)      AS avg_delay_days,
       ROUND(AVG(s.shipping_days_real), 2)      AS avg_real_days,
       ROUND(AVG(s.shipping_days_scheduled), 2) AS avg_scheduled_days
FROM orders o
JOIN shipping s ON o.order_item_id = s.order_item_id
WHERE o.is_canceled = 0;


-- 5.2 By shipping mode.
--     Promised days are fixed per mode, so late_pct shows how realistic each
--     promise is, not which carrier is worse.
SELECT s.shipping_mode,
       COUNT(*)                       AS order_lines,
       ROUND(AVG(s.shipping_days_scheduled), 2) AS avg_scheduled_days,
       ROUND(AVG(s.shipping_days_real), 2)      AS avg_real_days,
       ROUND(100 * AVG(s.is_late), 2) AS late_pct,
       ROUND(AVG(s.delay_days), 2)    AS avg_delay_days
FROM orders o
JOIN shipping s ON o.order_item_id = s.order_item_id
WHERE o.is_canceled = 0
GROUP BY s.shipping_mode
ORDER BY late_pct DESC;


-- 5.3a By market.
SELECT s.market,
       COUNT(*)                       AS order_lines,
       ROUND(100 * AVG(s.is_late), 2) AS late_pct,
       ROUND(AVG(s.delay_days), 2)    AS avg_delay_days
FROM orders o
JOIN shipping s ON o.order_item_id = s.order_item_id
WHERE o.is_canceled = 0
GROUP BY s.market
ORDER BY late_pct DESC;

-- 5.3b By region, worst first (check order_lines before trusting a small group).
SELECT s.market, s.order_region,
       COUNT(*)                       AS order_lines,
       ROUND(100 * AVG(s.is_late), 2) AS late_pct,
       ROUND(AVG(s.delay_days), 2)    AS avg_delay_days
FROM orders o
JOIN shipping s ON o.order_item_id = s.order_item_id
WHERE o.is_canceled = 0
GROUP BY s.market, s.order_region
ORDER BY late_pct DESC;


-- 5.4a By department (needs the products table).
SELECT p.department_name,
       COUNT(*)                       AS order_lines,
       ROUND(100 * AVG(s.is_late), 2) AS late_pct
FROM orders o
JOIN shipping s ON o.order_item_id = s.order_item_id
JOIN products p ON o.product_card_id = p.product_card_id
WHERE o.is_canceled = 0
GROUP BY p.department_name
ORDER BY late_pct DESC;

-- 5.4b By category. HAVING keeps groups with at least 100 lines.
SELECT p.category_name,
       COUNT(*)                       AS order_lines,
       ROUND(100 * AVG(s.is_late), 2) AS late_pct,
       ROUND(AVG(s.delay_days), 2)    AS avg_delay_days
FROM orders o
JOIN shipping s ON o.order_item_id = s.order_item_id
JOIN products p ON o.product_card_id = p.product_card_id
WHERE o.is_canceled = 0
GROUP BY p.category_name
HAVING COUNT(*) >= 100
ORDER BY late_pct DESC;


-- 5.5 Top 10 products by number of late lines.
SELECT p.product_name,
       COUNT(*)                       AS order_lines,
       SUM(s.is_late)                 AS late_lines,
       ROUND(100 * AVG(s.is_late), 2) AS late_pct
FROM orders o
JOIN shipping s ON o.order_item_id = s.order_item_id
JOIN products p ON o.product_card_id = p.product_card_id
WHERE o.is_canceled = 0
GROUP BY p.product_card_id, p.product_name
ORDER BY late_lines DESC
LIMIT 10;


-- 5.6 Trend by month. Check order_lines before judging the last month (may be partial).
SELECT DATE_FORMAT(o.order_date, '%Y-%m') AS order_month,
       COUNT(*)                           AS order_lines,
       ROUND(100 * AVG(s.is_late), 2)     AS late_pct
FROM orders o
JOIN shipping s ON o.order_item_id = s.order_item_id
WHERE o.is_canceled = 0
GROUP BY DATE_FORMAT(o.order_date, '%Y-%m')
ORDER BY order_month;


-- 5.7 Market x shipping mode. If late_pct is similar across markets inside
--     the same mode, the mode is the driver, not the market.
SELECT s.market, s.shipping_mode,
       COUNT(*)                       AS order_lines,
       ROUND(100 * AVG(s.is_late), 2) AS late_pct
FROM orders o
JOIN shipping s ON o.order_item_id = s.order_item_id
WHERE o.is_canceled = 0
GROUP BY s.market, s.shipping_mode
ORDER BY s.market, late_pct DESC;


-- 5.8 Severity of lateness (share of lines per bucket).
SELECT CASE
           WHEN s.delay_days <= 0 THEN '0 on time or early'
           WHEN s.delay_days = 1  THEN '1 day late'
           WHEN s.delay_days = 2  THEN '2 days late'
           ELSE '3 or more days late'
       END AS lateness,
       COUNT(*) AS order_lines,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_lines
FROM orders o
JOIN shipping s ON o.order_item_id = s.order_item_id
WHERE o.is_canceled = 0
GROUP BY lateness
ORDER BY MIN(s.delay_days);


-- 5.9 Same question at order level. An order counts as late if any line was late.
--     Expected: late_orders_pct is equal to or higher than late_pct in 5.1.
SELECT COUNT(*)                         AS orders_counted,
       SUM(order_is_late)               AS late_orders,
       ROUND(100 * AVG(order_is_late), 2) AS late_orders_pct
FROM (SELECT o.order_id, MAX(s.is_late) AS order_is_late
      FROM orders o
      JOIN shipping s ON o.order_item_id = s.order_item_id
      WHERE o.is_canceled = 0
      GROUP BY o.order_id) AS t;


-- 5.10 Late % by year.
SELECT YEAR(o.order_date) AS yr, COUNT(*) AS order_lines, ROUND(100*AVG(s.is_late),2) AS late_pct
FROM orders o JOIN shipping s ON o.order_item_id = s.order_item_id
WHERE o.is_canceled = 0
GROUP BY YEAR(o.order_date) ORDER BY yr;

-- 5.11 Late % by market (repeat of 5.3a, used as a cross-check).
SELECT s.market, COUNT(*) AS order_lines,
       ROUND(100*AVG(s.is_late),2) AS late_pct
FROM orders o JOIN shipping s ON o.order_item_id = s.order_item_id
WHERE o.is_canceled = 0
GROUP BY s.market ORDER BY late_pct DESC;

-- 5.12 Late % by shipping mode (repeat of 5.2, used as a cross-check).
SELECT s.shipping_mode, COUNT(*) AS order_lines,
       ROUND(100*AVG(s.is_late),2) AS late_pct
FROM orders o JOIN shipping s ON o.order_item_id = s.order_item_id
WHERE o.is_canceled = 0
GROUP BY s.shipping_mode ORDER BY late_pct DESC;

-- 5.13 Scheduled vs real shipping days by mode.
SELECT s.shipping_mode,
       MIN(s.shipping_days_scheduled) AS min_sched,
       MAX(s.shipping_days_scheduled) AS max_sched,
       MIN(s.shipping_days_real) AS min_real,
       MAX(s.shipping_days_real) AS max_real,
       ROUND(AVG(s.shipping_days_scheduled),2) AS avg_sched,
       ROUND(AVG(s.shipping_days_real),2) AS avg_real
FROM orders o JOIN shipping s ON o.order_item_id = s.order_item_id
WHERE o.is_canceled = 0
GROUP BY s.shipping_mode;
