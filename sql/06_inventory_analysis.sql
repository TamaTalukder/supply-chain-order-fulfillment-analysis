/* =====================================================================
   06_inventory_analysis.sql
   Project : Supply Chain Order Fulfillment & Inventory Optimization
   Stage   : 6 - Inventory analysis
   Database: MySQL 8 (supply_chain_db)

   Business question: which products need tighter stock control?

   Limits
   - DataCo has no real stock levels, supplier lead times or warehouse
     data. Safety stock and reorder points below are estimates built on
     demand (units ordered per week) and the assumptions listed here.
   - Demand comes from past orders and may not repeat.

   Assumptions
   - Lead time = 1 week (assumed, not measured).
   - Service level 95% (Z = 1.65).
   - Canceled lines are excluded (they never became real demand).
   - Weeks with no sales count as zero demand (see 6.4).
   - Lead time and Z can be changed in the params row of 6.5 and 6.6.

   Formulas
   - Safety stock  = Z * sd_weekly * SQRT(lead_weeks)
   - Reorder point = avg_weekly * lead_weeks + safety stock
   - CV            = sd_weekly / avg_weekly (high CV = unsteady demand)
   ===================================================================== */

USE supply_chain_db;


-- 6.1 Demand and revenue per product.
--     Expected: one row per product (118).
SELECT p.product_name,
       p.category_name,
       COUNT(*)                       AS order_lines,
       SUM(o.order_item_quantity)     AS units_sold,
       ROUND(SUM(o.sales), 2)         AS revenue,
       MIN(o.order_date)              AS first_sale,
       MAX(o.order_date)              AS last_sale
FROM orders o
JOIN products p ON o.product_card_id = p.product_card_id
WHERE o.is_canceled = 0
GROUP BY p.product_card_id, p.product_name, p.category_name
ORDER BY revenue DESC;


-- 6.2 ABC analysis. Products ranked by revenue with a running total.
--     A = running total before the product is under 80%, B = under 95%, C = the rest.
WITH prod_sales AS (
    SELECT p.product_card_id, p.product_name, p.category_name,
           SUM(o.order_item_quantity) AS units_sold,
           SUM(o.sales)               AS revenue
    FROM orders o
    JOIN products p ON o.product_card_id = p.product_card_id
    WHERE o.is_canceled = 0
    GROUP BY p.product_card_id, p.product_name, p.category_name
),
ranked AS (
    SELECT ps.*,
           SUM(revenue) OVER (ORDER BY revenue DESC, product_card_id
                              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_revenue,
           SUM(revenue) OVER () AS total_revenue
    FROM prod_sales ps
)
SELECT product_card_id, product_name, category_name, units_sold,
       ROUND(revenue, 2) AS revenue,
       ROUND(100 * revenue / total_revenue, 2)     AS revenue_pct,
       ROUND(100 * cum_revenue / total_revenue, 2) AS cumulative_pct,
       CASE WHEN (cum_revenue - revenue) / total_revenue < 0.80 THEN 'A'
            WHEN (cum_revenue - revenue) / total_revenue < 0.95 THEN 'B'
            ELSE 'C' END AS abc_class
FROM ranked
ORDER BY revenue DESC;


-- 6.3 ABC summary: products and revenue per class.
--     Expected: A = 8, B = 16, C = 94 products.
WITH prod_sales AS (
    SELECT p.product_card_id, SUM(o.sales) AS revenue
    FROM orders o
    JOIN products p ON o.product_card_id = p.product_card_id
    WHERE o.is_canceled = 0
    GROUP BY p.product_card_id
),
ranked AS (
    SELECT ps.*,
           SUM(revenue) OVER (ORDER BY revenue DESC, product_card_id
                              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_revenue,
           SUM(revenue) OVER () AS total_revenue
    FROM prod_sales ps
),
classed AS (
    SELECT revenue, total_revenue,
           CASE WHEN (cum_revenue - revenue) / total_revenue < 0.80 THEN 'A'
                WHEN (cum_revenue - revenue) / total_revenue < 0.95 THEN 'B'
                ELSE 'C' END AS abc_class
    FROM ranked
)
SELECT abc_class,
       COUNT(*)                                    AS products,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_products,
       ROUND(SUM(revenue), 2)                      AS revenue,
       ROUND(100 * SUM(revenue) / MAX(total_revenue), 2) AS pct_of_revenue
FROM classed
GROUP BY abc_class
ORDER BY abc_class;


-- 6.4 Weekly demand: average and standard deviation per product.
--     Weeks with no sales do not appear in "weekly" but are real zero-demand
--     weeks, so STDDEV on the weekly rows would hide them. The variance uses
--     (sum of squares - total * total / N) / (N - 1), which counts missing
--     weeks as zeros.
WITH line AS (
    SELECT o.product_card_id, o.order_item_quantity AS qty,
           YEARWEEK(o.order_date, 3) AS yw
    FROM orders o
    WHERE o.is_canceled = 0
),
weekly AS (
    SELECT product_card_id, yw, SUM(qty) AS units
    FROM line
    GROUP BY product_card_id, yw
),
n_weeks AS (
    SELECT COUNT(DISTINCT yw) AS n FROM line
),
stats AS (
    SELECT w.product_card_id,
           SUM(w.units)           AS total_units,
           SUM(w.units * w.units) AS sum_sq,
           MAX(nw.n)              AS n_weeks
    FROM weekly w
    CROSS JOIN n_weeks nw
    GROUP BY w.product_card_id
)
SELECT p.product_name,
       s.n_weeks,
       s.total_units,
       ROUND(s.total_units / s.n_weeks, 2) AS avg_weekly_units,
       ROUND(SQRT(GREATEST((s.sum_sq - s.total_units * s.total_units / s.n_weeks)
                           / (s.n_weeks - 1), 0)), 2) AS sd_weekly_units
FROM stats s
JOIN products p ON s.product_card_id = p.product_card_id
ORDER BY avg_weekly_units DESC;


-- 6.5 Safety stock and reorder point per product (estimate).
WITH params AS (
    SELECT 1.65 AS z_value, 1 AS lead_weeks
),
line AS (
    SELECT o.product_card_id, o.order_item_quantity AS qty,
           YEARWEEK(o.order_date, 3) AS yw
    FROM orders o
    WHERE o.is_canceled = 0
),
weekly AS (
    SELECT product_card_id, yw, SUM(qty) AS units
    FROM line
    GROUP BY product_card_id, yw
),
n_weeks AS (
    SELECT COUNT(DISTINCT yw) AS n FROM line
),
stats AS (
    SELECT w.product_card_id,
           SUM(w.units)           AS total_units,
           SUM(w.units * w.units) AS sum_sq,
           MAX(nw.n)              AS n_weeks
    FROM weekly w
    CROSS JOIN n_weeks nw
    GROUP BY w.product_card_id
),
calc AS (
    SELECT product_card_id,
           total_units / n_weeks AS avg_weekly,
           SQRT(GREATEST((sum_sq - total_units * total_units / n_weeks)
                         / (n_weeks - 1), 0)) AS sd_weekly
    FROM stats
)
SELECT p.product_name,
       ROUND(c.avg_weekly, 2) AS avg_weekly_units,
       ROUND(c.sd_weekly, 2)  AS sd_weekly_units,
       ROUND(c.sd_weekly / c.avg_weekly, 2) AS cv,
       ROUND(pr.z_value * c.sd_weekly * SQRT(pr.lead_weeks), 0) AS safety_stock,
       ROUND(c.avg_weekly * pr.lead_weeks
             + pr.z_value * c.sd_weekly * SQRT(pr.lead_weeks), 0) AS reorder_point
FROM calc c
JOIN products p ON c.product_card_id = p.product_card_id
CROSS JOIN params pr
ORDER BY avg_weekly_units DESC;


-- 6.6 Priority list: ABC class, demand variability (cv), estimated stock
--     rule and late_pct (from stage 5) in one table. Class A products with a
--     high cv and a high late_pct are the strongest candidates for tighter control.
WITH params AS (
    SELECT 1.65 AS z_value, 1 AS lead_weeks
),
line AS (
    SELECT o.product_card_id, o.order_item_quantity AS qty,
           YEARWEEK(o.order_date, 3) AS yw
    FROM orders o
    WHERE o.is_canceled = 0
),
weekly AS (
    SELECT product_card_id, yw, SUM(qty) AS units
    FROM line
    GROUP BY product_card_id, yw
),
n_weeks AS (
    SELECT COUNT(DISTINCT yw) AS n FROM line
),
stats AS (
    SELECT w.product_card_id,
           SUM(w.units)           AS total_units,
           SUM(w.units * w.units) AS sum_sq,
           MAX(nw.n)              AS n_weeks
    FROM weekly w
    CROSS JOIN n_weeks nw
    GROUP BY w.product_card_id
),
calc AS (
    SELECT product_card_id,
           total_units / n_weeks AS avg_weekly,
           SQRT(GREATEST((sum_sq - total_units * total_units / n_weeks)
                         / (n_weeks - 1), 0)) AS sd_weekly
    FROM stats
),
prod_sales AS (
    SELECT o.product_card_id, SUM(o.sales) AS revenue,
           100 * AVG(s.is_late) AS late_pct
    FROM orders o
    JOIN shipping s ON o.order_item_id = s.order_item_id
    WHERE o.is_canceled = 0
    GROUP BY o.product_card_id
),
ranked AS (
    SELECT ps.*,
           SUM(revenue) OVER (ORDER BY revenue DESC, product_card_id
                              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_revenue,
           SUM(revenue) OVER () AS total_revenue
    FROM prod_sales ps
)
SELECT p.product_name,
       p.category_name,
       CASE WHEN (r.cum_revenue - r.revenue) / r.total_revenue < 0.80 THEN 'A'
            WHEN (r.cum_revenue - r.revenue) / r.total_revenue < 0.95 THEN 'B'
            ELSE 'C' END AS abc_class,
       ROUND(r.revenue, 0)       AS revenue,
       ROUND(c.avg_weekly, 1)    AS avg_weekly_units,
       ROUND(c.sd_weekly / c.avg_weekly, 2) AS cv,
       ROUND(pr.z_value * c.sd_weekly * SQRT(pr.lead_weeks), 0) AS safety_stock,
       ROUND(c.avg_weekly * pr.lead_weeks
             + pr.z_value * c.sd_weekly * SQRT(pr.lead_weeks), 0) AS reorder_point,
       ROUND(r.late_pct, 1)      AS late_pct
FROM ranked r
JOIN calc c     ON r.product_card_id = c.product_card_id
JOIN products p ON r.product_card_id = p.product_card_id
CROSS JOIN params pr
ORDER BY abc_class, cv DESC, late_pct DESC;
