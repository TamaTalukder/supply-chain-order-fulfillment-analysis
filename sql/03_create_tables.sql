/* =====================================================================
   03_create_tables.sql
   Project : Supply Chain Order Fulfillment & Inventory Optimization
   Stage   : 3 - Create MySQL tables
   Database: MySQL 8 (supply_chain_db)

   Creates one staging table (landing place for clean_orders.csv) and
   four final tables: customers, products, orders, shipping.
   Run this script before 03_load_tables.sql.
   ===================================================================== */


/* ---------------------------------------------------------------------
   1. Check the database is empty
   Expected: no tables yet.
   --------------------------------------------------------------------- */
CREATE DATABASE IF NOT EXISTS supply_chain_db;
USE supply_chain_db;
SHOW TABLES;


/* ---------------------------------------------------------------------
   2. Staging table
   Holds clean_orders.csv as it is. Column order must match the CSV
   (the import matches by position). No keys, so no row is refused.
   --------------------------------------------------------------------- */
CREATE TABLE stg_clean_orders (
    shipping_days_real INT,
    shipping_days_scheduled INT,
    delivery_status VARCHAR(30),
    late_delivery_risk TINYINT,
    category_id INT,
    category_name VARCHAR(60),
    customer_id INT,
    customer_segment VARCHAR(20),
    department_name VARCHAR(50),
    market VARCHAR(30),
    order_country VARCHAR(60),
    order_date DATETIME,
    order_id INT,
    order_item_discount DECIMAL(10,2),
    order_item_id INT,
    order_item_quantity INT,
    sales DECIMAL(10,2),
    order_item_total DECIMAL(10,2),
    order_profit_per_order DECIMAL(10,2),
    order_region VARCHAR(50),
    order_status VARCHAR(30),
    product_card_id INT,
    product_name VARCHAR(100),
    product_price DECIMAL(10,2),
    shipping_date DATETIME,
    shipping_mode VARCHAR(30),
    delay_days INT,
    is_late TINYINT,
    is_canceled TINYINT
);


/* ---------------------------------------------------------------------
   3. Final tables
   Created in dependency order: customers and products first, because
   orders refers to them, and shipping refers to orders.
   --------------------------------------------------------------------- */

-- One row per customer
CREATE TABLE customers (
    customer_id INT NOT NULL,
    customer_segment VARCHAR(20) NOT NULL,
    PRIMARY KEY (customer_id)
);

-- One row per product
CREATE TABLE products (
    product_card_id INT NOT NULL,
    product_name VARCHAR(100) NOT NULL,
    category_id INT NOT NULL,
    category_name VARCHAR(60) NOT NULL,
    department_name VARCHAR(50) NOT NULL,
    product_price DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (product_card_id)
);

-- One row per order line (an order can have many lines)
CREATE TABLE orders (
    order_item_id INT NOT NULL,
    order_id INT NOT NULL,
    order_date DATETIME NOT NULL,
    customer_id INT NOT NULL,
    product_card_id INT NOT NULL,
    order_status VARCHAR(30) NOT NULL,
    order_item_quantity INT NOT NULL,
    order_item_discount DECIMAL(10,2) NOT NULL,
    sales DECIMAL(10,2) NOT NULL,
    order_item_total DECIMAL(10,2) NOT NULL,
    order_profit_per_order DECIMAL(10,2) NOT NULL,
    is_canceled TINYINT NOT NULL,
    PRIMARY KEY (order_item_id),
    FOREIGN KEY (customer_id) REFERENCES customers (customer_id),
    FOREIGN KEY (product_card_id) REFERENCES products (product_card_id)
);

-- One row per order line: shipping details
CREATE TABLE shipping (
    order_item_id INT NOT NULL,
    shipping_date DATETIME NOT NULL,
    shipping_mode VARCHAR(30) NOT NULL,
    shipping_days_real INT NOT NULL,
    shipping_days_scheduled INT NOT NULL,
    delay_days INT NOT NULL,
    is_late TINYINT NOT NULL,
    delivery_status VARCHAR(30) NOT NULL,
    late_delivery_risk TINYINT NOT NULL,
    market VARCHAR(30) NOT NULL,
    order_region VARCHAR(50) NOT NULL,
    order_country VARCHAR(60) NOT NULL,
    PRIMARY KEY (order_item_id),
    FOREIGN KEY (order_item_id) REFERENCES orders (order_item_id)
);


/* ---------------------------------------------------------------------
   4. Check the result
   Expected: 5 tables (customers, orders, products, shipping,
   stg_clean_orders).
   --------------------------------------------------------------------- */
SHOW TABLES;
DESCRIBE orders;
DESCRIBE shipping;



