CREATE DATABASE fraud_detection;
USE fraud_detection;

-- ============================================
-- QUERY 1: General Fraud Statistics
-- Description: Overview of fraud in the dataset
-- Business Question: What is the scale of the fraud problem?
-- ============================================

SELECT *
FROM transactions
LIMIT 30;

SELECT 
    COUNT(*) AS total_transactions,
    SUM(is_fraud) AS total_frauds,
    COUNT(*) - SUM(is_fraud) AS total_legitimte,
    ROUND((SUM(is_fraud) / COUNT(*)) * 100, 4) AS fraud_rate_pct,
    ROUND(SUM(amount), 2) AS total_volume_eur,
    ROUND(SUM(CASE WHEN is_fraud = 1 THEN amount ELSE 0 END), 2) AS fraud_loss_eur,
    ROUND(SUM(CASE WHEN is_fraud = 0 THEN amount ELSE 0 END), 2) AS legitimate_volume_eur
FROM transactions;

```
📊 Key Findings:
• 284,807 transactions analyzed
• 0.17% fraud rate (492 fraudulent transactions)
• €89,721 lost to fraud
• €25.1M in legitimate transactions processed
```

-- ============================================
-- QUERY 2: Fraud Analysis by Hour of Day
-- Description: Identify peak fraud hours
-- Business Question: When do most frauds occur?
-- Recommendation: Allocate monitoring resources to high-risk hours
-- ============================================

WITH hourly_stats AS (
	SELECT
		hour_of_day,
        COUNT(*) AS total_transactions,
        SUM(is_fraud) AS total_frauds,
		COUNT(*) - SUM(is_fraud) AS total_legitimate,
        ROUND((SUM(is_fraud) / COUNT(*)) * 100, 2) AS fraud_rate_pct,
        ROUND(SUM(CASE WHEN is_fraud = 1 THEN amount ELSE 0 END), 2) AS fraud_loss_eur,
        ROUND(SUM(CASE WHEN is_fraud = 0 THEN amount ELSE 0 END), 2) AS legitimate_volume_eur
	FROM transactions
    GROUP BY hour_of_day
    )
    SELECT
		hour_of_day,
		total_transactions,
        total_frauds,
        total_legitimate,
        fraud_rate_pct,
        fraud_loss_eur,
        legitimate_volume_eur,
		CASE
			WHEN fraud_rate_pct >= 0.20 THEN 'High Risk'
            WHEN fraud_rate_pct >= 0.15 THEN 'Medium Risk'
            ELSE 'Low Risk'
		END AS risk_level
	FROM hourly_stats
    ORDER BY fraud_rate_pct DESC;

```
 KEY FINDINGS:
 • Peak fraud hours: 2 AM (1.71%), 4 AM (1.04%), 3 AM (0.49%)
 • Night hours (0-5 AM) have 5-10x higher fraud rates
 • Hour 2 alone: €4,517 lost to fraud
 • Hour 11 has most frauds (53) but lower rate due to high volume
 
 RECOMMENDATIONS:
 ✅ Increase monitoring during 0-5 AM (night shift critical)
 ✅ Lower transaction limits during high-risk hours
 ✅ Deploy real-time fraud alerts for night transactions
 ✅ Consider requiring additional authentication at night
```

-- ============================================
-- QUERY 3: Fraud Analysis by Amount Range
-- Description: Identify which transaction amounts are most risky
-- Business Question: Are small or large transactions more likely to be fraud?
-- ============================================

-- CTE 1: Categorize transactions by amount 
WITH amount_categories AS (
    SELECT 
        transaction_id,
        amount,
        is_fraud,
        CASE 
            WHEN amount < 10 THEN '€0-10 (Micro)'
            WHEN amount < 50 THEN '€10-50 (Small)'
            WHEN amount < 100 THEN '€50-100 (Medium)'
            WHEN amount < 200 THEN '€100-200 (High)'
            ELSE '€200+ (Very High)'
        END AS amount_range
    FROM transactions
),
-- CTE 2: Calculate statistics per category
category_stats AS (
    SELECT 
        amount_range,
        COUNT(*) AS total_transactions,
        SUM(is_fraud) AS total_frauds,
        COUNT(*) - SUM(is_fraud) AS total_legitimate,
        ROUND((SUM(is_fraud) / COUNT(*)) * 100, 2) AS fraud_rate_pct,
        ROUND(AVG(amount), 2) AS avg_amount_eur,
        ROUND(SUM(amount), 2) AS total_volume_eur,
        ROUND(SUM(CASE WHEN is_fraud = 1 THEN amount ELSE 0 END), 2) AS fraud_loss_eur,
        ROUND(SUM(CASE WHEN is_fraud = 1 THEN amount ELSE 0 END) / 
              NULLIF(SUM(CASE WHEN is_fraud = 1 THEN 1 ELSE 0 END), 0), 2) AS avg_fraud_amount
    FROM amount_categories
    GROUP BY amount_range
)
SELECT 
    amount_range,
    total_transactions,
    total_frauds,
    total_legitimate,
    fraud_rate_pct,
    avg_amount_eur,
    avg_fraud_amount,
    total_volume_eur,
    fraud_loss_eur,
    CASE 
        WHEN fraud_rate_pct >= 0.30 THEN 'Critical Risk'
        WHEN fraud_rate_pct >= 0.20 THEN 'High Risk'
        WHEN fraud_rate_pct >= 0.10 THEN 'Medium Risk'
        ELSE 'Low Risk'
    END AS risk_level
FROM category_stats
ORDER BY fraud_rate_pct DESC;

```
KEY FINDINGS:
 
 FRAUD PATTERNS BY AMOUNT:
 • Micro transactions (€0-10) have HIGHEST fraud rate: 0.26%
 • Average fraud amount in micro range: €1.84 (card testing!)
 • 249 fraud attempts in micro transactions (highest volume)
 • Largest financial loss: €6,142 in €100-200 range (45 frauds)
 • Safest range: €10-50 with only 0.06% fraud rate
 
 FRAUD STRATEGY IDENTIFIED:
 1. Test stolen cards with micro transactions (€1-5)
 2. If successful, escalate to €100-200 range
 3. Skip €10-50 range (low profit, same risk)
 
 RECOMMENDATIONS:
 ✅ Flag multiple micro transactions from same card (card testing pattern)
 ✅ Create velocity rules: >3 transactions under €10 in 1 hour = alert
 ✅ Prioritize investigation of €100-200 frauds (highest financial impact)
 ✅ Lower micro transaction limits for new/dormant cards
 ✅ Require 3D Secure for transactions €100+ from high-risk locations
```

-- ============================================
-- QUERY 4: Top Fraudulent Transactions Ranking
-- Description: Identify and rank the largest fraud cases
-- Business Question: What are our biggest fraud losses?
-- ============================================

-- CTE 1: Get only fraudulent transactions with additional context
WITH fraud_transactions AS (
    SELECT
       transaction_id,
       time_seconds,
       hour_of_day,
       amount,
       CASE
            WHEN amount < 100 THEN 'Low value'
            WHEN amount < 300 THEN 'Medium value'
            WHEN amount < 500 THEN 'High value'
            ELSE 'Very high value'
        END AS value_category,
        CASE
            WHEN hour_of_day >= 0 AND hour_of_day < 6 THEN 'Night (0-5h)'
            WHEN hour_of_day >= 6 AND hour_of_day < 12 THEN 'Morning (6-11h)'
            WHEN hour_of_day >= 12 AND hour_of_day < 18 THEN 'Afternoon (12-17h)'
            ELSE 'Evening (18-23h)'
        END AS time_period
    FROM transactions
    WHERE is_fraud = 1
),
-- CTE 2: Add ranking by amount
ranked_frauds AS (
    SELECT
        transaction_id,
        amount,
        hour_of_day,
        time_period,
        value_category,
        ROW_NUMBER() OVER (ORDER BY amount DESC) AS fraud_rank,
        ROUND(amount / (select SUM(amount) FROM fraud_transactions) * 100, 2) AS pct_of_total_fraud_loss
    FROM fraud_transactions
)
-- Final SELECT: Show top 20 frauds with context
SELECT
    fraud_rank,
    transaction_id,
    amount AS fraud_amount_eur,
    hour_of_day,
    time_period,
    value_category,
    pct_of_total_fraud_loss,
    SUM(pct_of_total_fraud_loss) OVER (ORDER BY fraud_rank) AS cumulative_pct,
    CASE
        WHEN fraud_rank <= 10 THEN 'Priority 1 (Top 10)'
        WHEN fraud_rank <= 20 THEN 'Priority 2 (Top 20)'
        ELSE 'Priority 3'
    END AS investigation_priority
FROM ranked_frauds
WHERE fraud_rank <= 20
ORDER BY fraud_rank;

```
KEY FINDINGS:
 
 CONCENTRATION OF LOSSES (PARETO PRINCIPLE):
 • Single largest fraud: €2,125.87 (3.54% of total losses)
 • TOP 10 frauds: €14,233 (23.67% of total losses)
 • TOP 20 frauds: €22,058 (36.68% of total losses)
 • Just 4% of fraud cases (20 of 492) account for 37% of losses
 
 FRAUD PROFILE:
 • All TOP 20 frauds are "Very High Value" (€500+)
 • Average fraud amount in TOP 20: ~€1,000
 • 5x higher than overall fraud average (€182)
 • Largest fraud occurred at 10 AM (morning business hours)
 
 TIMING PATTERNS:
 • High-value frauds occur throughout the day (not just night)
 • Afternoon: 35% of TOP 20 frauds (7 cases)
 • Evening: 25% of TOP 20 frauds (5 cases)
 • Night/Morning: 40% combined (8 cases)
 
 RECOMMENDATIONS:
 ✅ Prioritize investigation of TOP 20 cases (37% recovery potential)
 ✅ Create special monitoring for transactions €500+ at ANY time
 ✅ Flag accounts with multiple high-value transactions in short period
 ✅ Implement stricter verification for €1,000+ transactions
 ✅ Train fraud team using these TOP cases as examples
```

-- ============================================
-- QUERY 5: Hourly Temporal Fraud Analysis
-- Description: Analyze fraud patterns hour by hour across 2 days
-- Business Question: How do frauds evolve throughout the 48-hour period?
-- ============================================

-- CTE 1: Create continuous hour sequence and aggregate
WITH hourly_transactions AS (
    SELECT 
        FLOOR(time_seconds / 3600) AS hour_sequence,
        hour_of_day,
        FLOOR(time_seconds / 86400) AS day_number,
        COUNT(*) AS total_transactions,
        SUM(is_fraud) AS total_frauds,
        ROUND((SUM(is_fraud) / COUNT(*)) * 100, 2) AS fraud_rate_pct,
        ROUND(SUM(CASE WHEN is_fraud = 1 THEN amount ELSE 0 END), 2) AS fraud_loss_eur
    FROM transactions
    GROUP BY hour_sequence, hour_of_day, day_number
),
-- CTE 2: Add moving averages and comparisons
hourly_with_trends AS (
    SELECT 
        hour_sequence,
        day_number,
        hour_of_day,
        total_transactions,
        total_frauds,
        fraud_rate_pct,
        fraud_loss_eur,
        -- Previous hour comparison
        LAG(total_frauds) OVER (ORDER BY hour_sequence) AS prev_hour_frauds,
        -- 3-hour moving average
        ROUND(AVG(total_frauds) OVER (
            ORDER BY hour_sequence 
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ), 1) AS fraud_3hour_avg,
        ROUND(AVG(fraud_rate_pct) OVER (
            ORDER BY hour_sequence 
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ), 2) AS rate_3hour_avg
    FROM hourly_transactions
)
-- Final SELECT: Show hourly trends with analysis
SELECT 
    hour_sequence,
    CONCAT('Day ', day_number, ' - ', 
           LPAD(hour_of_day, 2, '0'), ':00') AS time_label,
    total_transactions,
    total_frauds,
    fraud_rate_pct,
    fraud_loss_eur,
    prev_hour_frauds,
    CASE 
        WHEN prev_hour_frauds IS NULL THEN 'N/A'
        WHEN total_frauds > prev_hour_frauds THEN 'Increased'
        WHEN total_frauds < prev_hour_frauds THEN 'Decreased'
        ELSE 'Stable'
    END AS fraud_trend,
    total_frauds - COALESCE(prev_hour_frauds, total_frauds) AS fraud_change,
    fraud_3hour_avg,
    rate_3hour_avg,
    CASE 
        WHEN total_frauds > fraud_3hour_avg * 1.5 THEN 'Spike Alert'
        WHEN total_frauds < fraud_3hour_avg * 0.5 THEN 'Below Average'
        ELSE 'Normal'
    END AS anomaly_status
FROM hourly_with_trends
ORDER BY hour_sequence;

```
KEY FINDINGS:
 
 DATASET COVERAGE:
 • 48 hours of transaction data (2 consecutive days)
 • 284,807 total transactions
 • 492 fraudulent transactions
 
 CRITICAL FRAUD SPIKES IDENTIFIED:
 • 7 spike alerts detected across 48 hours
 • Highest fraud count: Day 0 at 11:00 AM (43 frauds, €5,393 lost)
 • Highest fraud rate: Day 1 at 02:00 AM (2.05%, 36 frauds)
 • Peak fraud hours consistently: 02:00-03:00 AM and 11:00 AM
 
 TEMPORAL PATTERNS:
 • Night hours (2-4 AM) show 5-10x higher fraud rates
 • Business hours (11 AM) also vulnerable due to high transaction volume
 • Day 0 had more total frauds (281) vs Day 1 (211) - 25% decrease
 • Moving averages reveal fraud clustering in specific time windows
 
 ANOMALY DETECTION:
 • 8 "Below Average" periods (fraud lulls - potential system improvements?)
 • Frauds tend to spike after quiet periods (fraud testing patterns?)
 • Consecutive spikes at same hours across both days (2 AM, 11 AM)
 
 RECOMMENDATIONS:
 ✅ Deploy heightened monitoring during 2-4 AM window (highest risk)
 ✅ Increase fraud team staffing at 11 AM (highest volume + fraud)
 ✅ Investigate why Day 1 had 25% fewer frauds (replicate success factors)
 ✅ Use 3-hour moving average as baseline for real-time spike detection
 ✅ Create automated alerts when fraud rate exceeds 0.50% in any hour
 ✅ Study "Below Average" periods to understand deterrent factors
 ```