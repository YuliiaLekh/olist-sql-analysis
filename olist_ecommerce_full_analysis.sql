/*
Olist Brazilian E-Commerce Data Analysis

Dataset: ~100k orders from Sep 2016 to Aug 2018
Business Context: Marketplace connecting small businesses to customers

Skills used: Joins, CTEs, Window Functions, Aggregate Functions, 
CASE statements, Date Functions, Subqueries, Views, Data Quality checks

Author: Yuliia Lekh
Date: January 2026
*/

-- ============================================
-- BLOCK 1: BASIC DATA EXPLORATION
-- ============================================

-- 1.1 Overall dataset statistics
SELECT 
    (SELECT COUNT(*) FROM orders) as total_orders,
    (SELECT COUNT(DISTINCT customer_id) FROM customers) as total_customers,
    (SELECT COUNT(*) FROM products) as total_products,
    (SELECT COUNT(*) FROM sellers) as total_sellers,
    (SELECT MIN(order_purchase_timestamp) FROM orders) as first_order_date,
    (SELECT MAX(order_purchase_timestamp) FROM orders) as last_order_date;

-- 1.2 Order status distribution with percentages
SELECT 
    order_status,
    COUNT(*) as order_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as percentage,
    REPEAT('█', (COUNT(*) * 50 / MAX(COUNT(*)) OVER())::int) as visual_bar
FROM orders
GROUP BY order_status
ORDER BY order_count DESC;


-- ============================================
-- BLOCK 2: AGGREGATE FUNCTIONS (Business Metrics)
-- ============================================

-- 2.1 Monthly revenue trend
SELECT 
    DATE_TRUNC('month', o.order_purchase_timestamp) as month,
    COUNT(DISTINCT o.order_id) as total_orders,
    COUNT(oi.product_id) as total_items_sold,
    ROUND(SUM(oi.price), 2) as total_revenue,
    ROUND(AVG(oi.price), 2) as avg_item_price,
    ROUND(SUM(oi.price + oi.freight_value), 2) as revenue_with_shipping
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY month
ORDER BY month;

-- 2.2 Top 10 product categories by revenue
SELECT 
    COALESCE(pt.product_category_name_english, 'Unknown') as category,
    COUNT(DISTINCT oi.order_id) as orders_count,
    COUNT(oi.product_id) as items_sold,
    ROUND(SUM(oi.price), 2) as total_revenue,
    ROUND(AVG(oi.price), 2) as avg_price
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
LEFT JOIN product_category_name_translation pt 
    ON p.product_category_name = pt.product_category_name
GROUP BY pt.product_category_name_english
ORDER BY total_revenue DESC
LIMIT 10;

-- ============================================
-- BLOCK 3: JOINS (Multi-table Analysis)
-- ============================================

-- 3.1 Geographic analysis: Top states by orders and revenue
SELECT 
    c.customer_state,
    COUNT(DISTINCT o.order_id) as total_orders,
    COUNT(DISTINCT c.customer_id) as unique_customers,
    ROUND(SUM(oi.price + oi.freight_value), 2) as total_revenue,
    ROUND(AVG(oi.price + oi.freight_value), 2) as avg_order_value
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_state
ORDER BY total_revenue DESC
LIMIT 10;

-- 3.2 Payment methods analysis
SELECT 
    op.payment_type,
    COUNT(DISTINCT op.order_id) as orders_count,
    ROUND(SUM(op.payment_value), 2) as total_paid,
    ROUND(AVG(op.payment_value), 2) as avg_payment,
    ROUND(AVG(op.payment_installments), 1) as avg_installments,
    ROUND(SUM(op.payment_value) * 100.0 / SUM(SUM(op.payment_value)) OVER(), 2) as revenue_share_pct
FROM order_payments op
JOIN orders o ON op.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY op.payment_type
ORDER BY total_paid DESC;

-- 3.3 Seller performance: Top sellers by revenue and customer satisfaction
SELECT 
    s.seller_id,
    s.seller_city,
    s.seller_state,
    COUNT(DISTINCT oi.order_id) as orders_fulfilled,
    ROUND(SUM(oi.price), 2) as total_revenue,
    ROUND(AVG(orv.review_score), 2) as avg_review_score,
    COUNT(orv.review_id) as reviews_received
FROM sellers s
JOIN order_items oi ON s.seller_id = oi.seller_id
JOIN orders o ON oi.order_id = o.order_id
LEFT JOIN order_reviews orv ON o.order_id = orv.order_id
WHERE o.order_status = 'delivered'
GROUP BY s.seller_id, s.seller_city, s.seller_state
HAVING COUNT(DISTINCT oi.order_id) >= 10  -- Only sellers with at least 10 orders
ORDER BY total_revenue DESC
LIMIT 20;


-- ============================================
-- BLOCK 4: WINDOW FUNCTIONS (Advanced Analytics)
-- ============================================

-- 4.1 Running total revenue by month
SELECT 
    DATE_TRUNC('month', o.order_purchase_timestamp) as month,
    ROUND(SUM(oi.price), 2) as monthly_revenue,
    ROUND(SUM(SUM(oi.price)) OVER (ORDER BY DATE_TRUNC('month', o.order_purchase_timestamp)), 2) as cumulative_revenue
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY month
ORDER BY month;

-- 4.2 Top 3 products in each category (RANK)
WITH category_products AS (
    SELECT 
        COALESCE(pt.product_category_name_english, 'Unknown') as category,
        p.product_id,
        COUNT(DISTINCT oi.order_id) as times_sold,
        ROUND(SUM(oi.price), 2) as total_revenue,
        RANK() OVER (
            PARTITION BY pt.product_category_name_english 
            ORDER BY SUM(oi.price) DESC
        ) as revenue_rank
    FROM products p
    LEFT JOIN product_category_name_translation pt 
        ON p.product_category_name = pt.product_category_name
    JOIN order_items oi ON p.product_id = oi.product_id
    JOIN orders o ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY pt.product_category_name_english, p.product_id
)
SELECT 
    category,
    product_id,
    times_sold,
    total_revenue,
    revenue_rank
FROM category_products
WHERE revenue_rank <= 3
ORDER BY category, revenue_rank;

-- 4.3 Month-over-month revenue growth (LAG function)
WITH monthly_revenue AS (
    SELECT 
        DATE_TRUNC('month', o.order_purchase_timestamp) as month,
        ROUND(SUM(oi.price), 2) as revenue
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY month
)
SELECT 
    month,
    revenue,
    LAG(revenue) OVER (ORDER BY month) as prev_month_revenue,
    ROUND(revenue - LAG(revenue) OVER (ORDER BY month), 2) as revenue_change,
    ROUND(
        (revenue - LAG(revenue) OVER (ORDER BY month)) * 100.0 / 
        NULLIF(LAG(revenue) OVER (ORDER BY month), 0), 
        2
    ) as growth_pct
FROM monthly_revenue
ORDER BY month;

-- 4.4 Customer order numbering (ROW_NUMBER)
SELECT
    c.customer_unique_id,
    o.order_id,
    o.order_purchase_timestamp,
    ROW_NUMBER() OVER (
        PARTITION BY c.customer_unique_id
        ORDER BY o.order_purchase_timestamp
    ) as order_number,
    ROUND(SUM(oi.price + oi.freight_value), 2) as order_value
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_unique_id, o.order_id, o.order_purchase_timestamp
ORDER BY c.customer_unique_id, order_number
LIMIT 100;


-- ============================================
-- BLOCK 5: CTE
-- ============================================

-- 5.1 Customer segmentation by total spend
WITH customer_spending AS (
    SELECT 
        c.customer_unique_id,
        c.customer_state,
        COUNT(DISTINCT o.order_id) as total_orders,
        ROUND(SUM(oi.price + oi.freight_value), 2) as lifetime_value,
        MAX(o.order_purchase_timestamp) as last_order_date
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id, c.customer_state
),
customer_segments AS (
    SELECT 
        customer_unique_id,
        customer_state,
        total_orders,
        lifetime_value,
        last_order_date,
        CASE 
            WHEN lifetime_value >= 1000 THEN 'VIP'
            WHEN lifetime_value >= 500 THEN 'High Value'
            WHEN lifetime_value >= 200 THEN 'Medium Value'
            ELSE 'Low Value'
        END as customer_segment
    FROM customer_spending
)
SELECT 
    customer_segment,
    COUNT(*) as customers_count,
    ROUND(AVG(total_orders), 1) as avg_orders_per_customer,
    ROUND(AVG(lifetime_value), 2) as avg_lifetime_value,
    ROUND(SUM(lifetime_value), 2) as segment_total_revenue
FROM customer_segments
GROUP BY customer_segment
ORDER BY 
    CASE 
        WHEN customer_segment = 'VIP' THEN 1
        WHEN customer_segment = 'High Value' THEN 2
        WHEN customer_segment = 'Medium Value' THEN 3
        ELSE 4
    END;

-- 5.2 Multiple CTEs: Delivery performance analysis
WITH delivery_times AS (
    SELECT 
        o.order_id,
        o.customer_id,
        o.order_purchase_timestamp,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date,
        EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_purchase_timestamp))/86400 as actual_delivery_days,
        EXTRACT(EPOCH FROM (o.order_estimated_delivery_date - o.order_purchase_timestamp))/86400 as estimated_delivery_days
    FROM orders o
    WHERE o.order_status = 'delivered'
        AND o.order_delivered_customer_date IS NOT NULL
        AND o.order_estimated_delivery_date IS NOT NULL
),
delivery_performance AS (
    SELECT 
        order_id,
        actual_delivery_days,
        estimated_delivery_days,
        CASE 
            WHEN actual_delivery_days <= estimated_delivery_days THEN 'On Time'
            WHEN actual_delivery_days <= estimated_delivery_days + 3 THEN 'Slightly Delayed'
            WHEN actual_delivery_days <= estimated_delivery_days + 7 THEN 'Delayed'
            ELSE 'Very Delayed'
        END as delivery_status
    FROM delivery_times
)
SELECT 
    delivery_status,
    COUNT(*) as orders_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as percentage,
    ROUND(AVG(actual_delivery_days), 1) as avg_delivery_days,
    ROUND(MIN(actual_delivery_days), 1) as min_delivery_days,
    ROUND(MAX(actual_delivery_days), 1) as max_delivery_days
FROM delivery_performance
GROUP BY delivery_status
ORDER BY 
    CASE 
        WHEN delivery_status = 'On Time' THEN 1
        WHEN delivery_status = 'Slightly Delayed' THEN 2
        WHEN delivery_status = 'Delayed' THEN 3
        ELSE 4
    END;


-- ============================================
-- BLOCK 6: CASE WHEN
-- ============================================

-- 6.1 Customer satisfaction analysis by product category
SELECT 
    COALESCE(pt.product_category_name_english, 'Unknown') as category,
    COUNT(orv.review_id) as total_reviews,
    ROUND(AVG(orv.review_score), 2) as avg_rating,
    SUM(CASE WHEN orv.review_score = 5 THEN 1 ELSE 0 END) as excellent_reviews,
    SUM(CASE WHEN orv.review_score = 4 THEN 1 ELSE 0 END) as good_reviews,
    SUM(CASE WHEN orv.review_score = 3 THEN 1 ELSE 0 END) as neutral_reviews,
    SUM(CASE WHEN orv.review_score <= 2 THEN 1 ELSE 0 END) as poor_reviews,
    ROUND(
        SUM(CASE WHEN orv.review_score >= 4 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 
        2
    ) as satisfaction_rate_pct
FROM order_reviews orv
JOIN orders o ON orv.order_id = o.order_id
JOIN order_items oi ON o.order_id = oi.order_id
JOIN products p ON oi.product_id = p.product_id
LEFT JOIN product_category_name_translation pt 
    ON p.product_category_name = pt.product_category_name
GROUP BY pt.product_category_name_english
HAVING COUNT(orv.review_id) >= 50  -- Categories with at least 50 reviews
ORDER BY avg_rating DESC, total_reviews DESC
LIMIT 15;

-- 6.2 Day of week analysis: When do customers buy most?
SELECT 
    CASE EXTRACT(DOW FROM o.order_purchase_timestamp)
        WHEN 0 THEN 'Sunday'
        WHEN 1 THEN 'Monday'
        WHEN 2 THEN 'Tuesday'
        WHEN 3 THEN 'Wednesday'
        WHEN 4 THEN 'Thursday'
        WHEN 5 THEN 'Friday'
        WHEN 6 THEN 'Saturday'
    END as day_of_week,
    COUNT(DISTINCT o.order_id) as orders_count,
    ROUND(AVG(order_totals.order_value), 2) as avg_order_value,
    ROUND(SUM(order_totals.order_value), 2) as total_revenue
FROM orders o
JOIN (
    SELECT 
        order_id,
        SUM(price + freight_value) as order_value
    FROM order_items
    GROUP BY order_id
) as order_totals ON o.order_id = order_totals.order_id
WHERE o.order_status = 'delivered'
GROUP BY EXTRACT(DOW FROM o.order_purchase_timestamp)
ORDER BY EXTRACT(DOW FROM o.order_purchase_timestamp);


-- ============================================
-- BLOCK 7: DATE FUNCTIONS
-- ============================================

-- 7.1 Quarterly performance comparison
SELECT 
    EXTRACT(YEAR FROM o.order_purchase_timestamp) as year,
    EXTRACT(QUARTER FROM o.order_purchase_timestamp) as quarter,
    COUNT(DISTINCT o.order_id) as total_orders,
    ROUND(SUM(oi.price), 2) as revenue,
    ROUND(AVG(oi.price), 2) as avg_item_price,
    COUNT(DISTINCT c.customer_unique_id) as unique_customers
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
GROUP BY year, quarter
ORDER BY year, quarter;

-- 7.2 Holiday season analysis
SELECT 
    DATE_TRUNC('month', o.order_purchase_timestamp) as month,
    CASE 
        WHEN EXTRACT(MONTH FROM o.order_purchase_timestamp) = 11 THEN 'Black Friday Season'
        WHEN EXTRACT(MONTH FROM o.order_purchase_timestamp) = 12 THEN 'Christmas Season'
        ELSE 'Regular Period'
    END as period_type,
    COUNT(DISTINCT o.order_id) as orders_count,
    ROUND(SUM(oi.price + oi.freight_value), 2) as revenue,
    ROUND(AVG(oi.price + oi.freight_value), 2) as avg_order_value
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY month, period_type
ORDER BY month;


-- ============================================
-- BLOCK 8: SUBQUERIES
-- ============================================

-- 8.1 Products priced above category average
SELECT 
    p.product_id,
    COALESCE(pt.product_category_name_english, 'Unknown') as category,
    ROUND(AVG(oi.price), 2) as product_avg_price,
    (
        SELECT ROUND(AVG(oi2.price), 2)
        FROM order_items oi2
        JOIN products p2 ON oi2.product_id = p2.product_id
        WHERE p2.product_category_name = p.product_category_name
    ) as category_avg_price,
    COUNT(DISTINCT oi.order_id) as times_sold
FROM products p
LEFT JOIN product_category_name_translation pt 
    ON p.product_category_name = pt.product_category_name
JOIN order_items oi ON p.product_id = oi.product_id
JOIN orders o ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY p.product_id, p.product_category_name, pt.product_category_name_english
HAVING AVG(oi.price) > (
    SELECT AVG(oi2.price)
    FROM order_items oi2
    JOIN products p2 ON oi2.product_id = p2.product_id
    WHERE p2.product_category_name = p.product_category_name
)
ORDER BY product_avg_price DESC
LIMIT 20;

-- 8.2 Customers who bought from top-performing categories
SELECT 
    c.customer_unique_id,
    c.customer_state,
    COUNT(DISTINCT o.order_id) as orders_count,
    ROUND(SUM(oi.price), 2) as total_spent
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
JOIN products p ON oi.product_id = p.product_id
WHERE p.product_category_name IN (
    -- Subquery: Top 5 categories by revenue
    SELECT p2.product_category_name
    FROM products p2
    JOIN order_items oi2 ON p2.product_id = oi2.product_id
    JOIN orders o2 ON oi2.order_id = o2.order_id
    WHERE o2.order_status = 'delivered'
    GROUP BY p2.product_category_name
    ORDER BY SUM(oi2.price) DESC
    LIMIT 5
)
AND o.order_status = 'delivered'
GROUP BY c.customer_unique_id, c.customer_state
ORDER BY total_spent DESC
LIMIT 50;


-- ============================================
-- BLOCK 9: RFM ANALYSIS
-- ============================================

-- RFM: Recency, Frequency, Monetary - Customer Segmentation
WITH customer_rfm AS (
    SELECT 
        c.customer_unique_id,
        -- Recency: Days since last purchase
        EXTRACT(DAY FROM (
            (SELECT MAX(order_purchase_timestamp) FROM orders) - 
            MAX(o.order_purchase_timestamp)
        )) as recency_days,
        -- Frequency: Number of orders
        COUNT(DISTINCT o.order_id) as frequency,
        -- Monetary: Total spent
        ROUND(SUM(oi.price + oi.freight_value), 2) as monetary
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
rfm_scores AS (
    SELECT 
        customer_unique_id,
        recency_days,
        frequency,
        monetary,
        -- Recency score: Lower is better (5 = most recent)
        NTILE(5) OVER (ORDER BY recency_days) as r_score,
        -- Frequency score: Higher is better (5 = most frequent)
        NTILE(5) OVER (ORDER BY frequency DESC) as f_score,
        -- Monetary score: Higher is better (5 = highest spend)
        NTILE(5) OVER (ORDER BY monetary DESC) as m_score
    FROM customer_rfm
),
rfm_segments AS (
    SELECT 
        customer_unique_id,
        recency_days,
        frequency,
        monetary,
        r_score,
        f_score,
        m_score,
        CASE 
            WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
            WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3 THEN 'Loyal Customers'
            WHEN r_score >= 4 AND f_score <= 2 THEN 'New Customers'
            WHEN r_score <= 2 AND f_score >= 3 THEN 'At Risk'
            WHEN r_score <= 2 AND f_score <= 2 THEN 'Lost Customers'
            WHEN r_score >= 3 AND f_score <= 2 AND m_score <= 2 THEN 'Promising'
            ELSE 'Regular'
        END as customer_segment
    FROM rfm_scores
)
SELECT 
    customer_segment,
    COUNT(*) as customers_count,
    ROUND(AVG(recency_days), 1) as avg_recency_days,
    ROUND(AVG(frequency), 1) as avg_orders,
    ROUND(AVG(monetary), 2) as avg_lifetime_value,
    ROUND(SUM(monetary), 2) as segment_total_value,
    ROUND(SUM(monetary) * 100.0 / SUM(SUM(monetary)) OVER(), 2) as revenue_share_pct
FROM rfm_segments
GROUP BY customer_segment
ORDER BY segment_total_value DESC;


-- ============================================
-- BLOCK 10: COHORT ANALYSIS
-- ============================================

-- Cohort analysis: Customer retention by first purchase month
WITH customer_first_purchase AS (
    SELECT 
        c.customer_unique_id,
        DATE_TRUNC('month', MIN(o.order_purchase_timestamp)) as cohort_month
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
cohort_orders AS (
    SELECT 
        cfp.customer_unique_id,
        cfp.cohort_month,
        DATE_TRUNC('month', o.order_purchase_timestamp) as order_month,
        EXTRACT(MONTH FROM AGE(
            DATE_TRUNC('month', o.order_purchase_timestamp), 
            cfp.cohort_month
        )) as months_since_first_purchase
    FROM customer_first_purchase cfp
    JOIN customers c ON cfp.customer_unique_id = c.customer_unique_id
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
)
SELECT 
    cohort_month,
    COUNT(DISTINCT CASE WHEN months_since_first_purchase = 0 THEN customer_unique_id END) as month_0,
    COUNT(DISTINCT CASE WHEN months_since_first_purchase = 1 THEN customer_unique_id END) as month_1,
    COUNT(DISTINCT CASE WHEN months_since_first_purchase = 2 THEN customer_unique_id END) as month_2,
    COUNT(DISTINCT CASE WHEN months_since_first_purchase = 3 THEN customer_unique_id END) as month_3,
    -- Retention rates
    ROUND(
        COUNT(DISTINCT CASE WHEN months_since_first_purchase = 1 THEN customer_unique_id END) * 100.0 /
        NULLIF(COUNT(DISTINCT CASE WHEN months_since_first_purchase = 0 THEN customer_unique_id END), 0),
        2
    ) as retention_month_1_pct,
    ROUND(
        COUNT(DISTINCT CASE WHEN months_since_first_purchase = 3 THEN customer_unique_id END) * 100.0 /
        NULLIF(COUNT(DISTINCT CASE WHEN months_since_first_purchase = 0 THEN customer_unique_id END), 0),
        2
    ) as retention_month_3_pct
FROM cohort_orders
GROUP BY cohort_month
ORDER BY cohort_month
LIMIT 12;


-- ============================================
-- BLOCK 11: DATA QUALITY CHECKS
-- ============================================

-- 11.1 Finding data quality issues
SELECT 
    'Orders without order items' as issue_type,
    COUNT(*) as count
FROM orders o
LEFT JOIN order_items oi ON o.order_id = oi.order_id
WHERE oi.order_id IS NULL

UNION ALL

SELECT 
    'Orders without payments',
    COUNT(*)
FROM orders o
LEFT JOIN order_payments op ON o.order_id = op.order_id
WHERE op.order_id IS NULL

UNION ALL

SELECT 
    'Delivered orders without reviews',
    COUNT(*)
FROM orders o
LEFT JOIN order_reviews orv ON o.order_id = orv.order_id
WHERE o.order_status = 'delivered' 
    AND orv.order_id IS NULL

UNION ALL

SELECT 
    'Products without category',
    COUNT(*)
FROM products p
WHERE p.product_category_name IS NULL

UNION ALL

SELECT 
    'Negative or zero prices',
    COUNT(*)
FROM order_items
WHERE price <= 0;

-- 11.2 Payment vs Order value reconciliation
SELECT 
    o.order_id,
    ROUND(SUM(oi.price + oi.freight_value), 2) as items_total,
    ROUND(SUM(op.payment_value), 2) as payments_total,
    ROUND(ABS(SUM(oi.price + oi.freight_value) - SUM(op.payment_value)), 2) as difference
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
JOIN order_payments op ON o.order_id = op.order_id
WHERE o.order_status = 'delivered'
GROUP BY o.order_id
HAVING ABS(SUM(oi.price + oi.freight_value) - SUM(op.payment_value)) > 0.01
ORDER BY difference DESC
LIMIT 20;


-- ============================================
-- BLOCK 12: VIEWS
-- ============================================

-- View 1: Monthly Revenue Dashboard
CREATE OR REPLACE VIEW monthly_revenue_dashboard AS
SELECT 
    DATE_TRUNC('month', o.order_purchase_timestamp) as month,
    COUNT(DISTINCT o.order_id) as total_orders,
    COUNT(DISTINCT c.customer_unique_id) as unique_customers,
    COUNT(oi.product_id) as items_sold,
    ROUND(SUM(oi.price), 2) as product_revenue,
    ROUND(SUM(oi.freight_value), 2) as shipping_revenue,
    ROUND(SUM(oi.price + oi.freight_value), 2) as total_revenue,
    ROUND(AVG(oi.price + oi.freight_value), 2) as avg_order_value
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
GROUP BY month
ORDER BY month;

-- View 2: Customer Lifetime Value
CREATE OR REPLACE VIEW customer_lifetime_value AS
SELECT 
    c.customer_unique_id,
    c.customer_state,
    c.customer_city,
    COUNT(DISTINCT o.order_id) as total_orders,
    MIN(o.order_purchase_timestamp) as first_order_date,
    MAX(o.order_purchase_timestamp) as last_order_date,
    ROUND(SUM(oi.price + oi.freight_value), 2) as lifetime_value,
    ROUND(AVG(oi.price + oi.freight_value), 2) as avg_order_value,
    ROUND(
        SUM(oi.price + oi.freight_value) / 
        NULLIF(COUNT(DISTINCT o.order_id), 0), 
        2
    ) as revenue_per_order
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_unique_id, c.customer_state, c.customer_city;

-- View 3: Product Performance Summary
CREATE OR REPLACE VIEW product_performance AS
SELECT 
    p.product_id,
    COALESCE(pt.product_category_name_english, 'Unknown') as category,
    COUNT(DISTINCT oi.order_id) as times_ordered,
    ROUND(SUM(oi.price), 2) as total_revenue,
    ROUND(AVG(oi.price), 2) as avg_price,
    ROUND(AVG(orv.review_score), 2) as avg_review_score,
    COUNT(orv.review_id) as review_count
FROM products p
LEFT JOIN product_category_name_translation pt 
    ON p.product_category_name = pt.product_category_name
JOIN order_items oi ON p.product_id = oi.product_id
JOIN orders o ON oi.order_id = o.order_id
LEFT JOIN order_reviews orv ON o.order_id = orv.order_id
WHERE o.order_status = 'delivered'
GROUP BY p.product_id, pt.product_category_name_english;


-- ============================================
-- BLOCK 13: ADVANCED BUSINESS INSIGHTS
-- ============================================

-- 13.1 Cross-sell analysis: Products frequently bought together
SELECT 
    p1.product_category_name as category_1,
    p2.product_category_name as category_2,
    COUNT(DISTINCT oi1.order_id) as times_bought_together,
    ROUND(AVG(oi1.price + oi2.price), 2) as avg_combined_price
FROM order_items oi1
JOIN order_items oi2 ON oi1.order_id = oi2.order_id 
    AND oi1.product_id < oi2.product_id  -- Avoid duplicates
JOIN products p1 ON oi1.product_id = p1.product_id
JOIN products p2 ON oi2.product_id = p2.product_id
JOIN orders o ON oi1.order_id = o.order_id
WHERE o.order_status = 'delivered'
    AND p1.product_category_name IS NOT NULL
    AND p2.product_category_name IS NOT NULL
GROUP BY p1.product_category_name, p2.product_category_name
HAVING COUNT(DISTINCT oi1.order_id) >= 10
ORDER BY times_bought_together DESC
LIMIT 20;

-- 13.2 Customer acquisition trends
SELECT 
    DATE_TRUNC('month', first_order_date) as acquisition_month,
    COUNT(DISTINCT customer_unique_id) as new_customers,
    ROUND(AVG(first_order_value), 2) as avg_first_order_value,
    SUM(COUNT(DISTINCT customer_unique_id)) OVER (
        ORDER BY DATE_TRUNC('month', first_order_date)
    ) as cumulative_customers
FROM (
    SELECT 
        c.customer_unique_id,
        MIN(o.order_purchase_timestamp) as first_order_date,
        SUM(oi.price + oi.freight_value) as first_order_value
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id, o.order_id
    HAVING MIN(o.order_purchase_timestamp) = (
        SELECT MIN(o2.order_purchase_timestamp)
        FROM orders o2
        WHERE o2.customer_id = o.customer_id
            AND o2.order_status = 'delivered'
    )
) as first_orders
GROUP BY DATE_TRUNC('month', first_order_date)
ORDER BY acquisition_month;