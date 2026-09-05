-- CreditCheck - analysis queries
-- MySQL 8.0+ required (uses RANK, DENSE_RANK, LAG window functions)
-- These 15 queries power every section of the Power BI dashboard.
-- Grouped by what they answer, not just by table.


-- ============================================================
-- 1. Portfolio KPIs - the top card row of the dashboard
-- ============================================================

-- Overall loan book size and how much of it has gone bad
SELECT
    COUNT(*) AS total_loans,
    SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END) AS active_loans,
    SUM(loan_amount) AS total_portfolio_value,
    ROUND(100.0 * SUM(CASE WHEN status = 'defaulted' THEN 1 ELSE 0 END) / COUNT(*), 2) AS default_rate_pct
FROM loans;

-- How many applications actually get approved
SELECT
    COUNT(*) AS total_applications,
    SUM(CASE WHEN approval_status = 'Approved' THEN 1 ELSE 0 END) AS approved,
    ROUND(100.0 * SUM(CASE WHEN approval_status = 'Approved' THEN 1 ELSE 0 END) / COUNT(*), 2) AS approval_rate_pct
FROM loan_applications;

-- How much of what's owed is actually getting collected
SELECT
    ROUND(SUM(amount_paid), 2) AS total_collected,
    ROUND(SUM(amount_due), 2) AS total_due,
    ROUND(100.0 * SUM(amount_paid) / SUM(amount_due), 2) AS repayment_rate_pct
FROM repayments;


-- ============================================================
-- 2. Disbursement trend over time
-- ============================================================

-- Loans and amount disbursed per month
SELECT
    DATE_FORMAT(disbursement_date, '%Y-%m') AS disb_month,
    COUNT(*) AS loans_disbursed,
    SUM(loan_amount) AS amount_disbursed
FROM loans
GROUP BY disb_month
ORDER BY disb_month;

-- Same thing, but as a running total - shows portfolio growth over time
WITH monthly AS (
    SELECT
        DATE_FORMAT(disbursement_date, '%Y-%m') AS disb_month,
        SUM(loan_amount) AS month_disbursed
    FROM loans
    GROUP BY disb_month
)
SELECT
    disb_month,
    month_disbursed,
    SUM(month_disbursed) OVER (ORDER BY disb_month) AS running_total_disbursed
FROM monthly
ORDER BY disb_month;


-- ============================================================
-- 3. Portfolio by loan type
-- ============================================================

-- Where the bank's money actually is, and which loan type defaults most
SELECT
    loan_type,
    COUNT(*) AS total_loans,
    SUM(loan_amount) AS total_loan_amount,
    SUM(CASE WHEN status = 'defaulted' THEN 1 ELSE 0 END) AS defaults,
    ROUND(100.0 * SUM(CASE WHEN status = 'defaulted' THEN 1 ELSE 0 END) / COUNT(*), 2) AS default_rate_pct
FROM loans
GROUP BY loan_type
ORDER BY total_loan_amount DESC;


-- ============================================================
-- 4. Delinquency (DPD) buckets
-- ============================================================

-- Worst days-past-due per loan, then bucketed - shows how serious
-- the repayment problem actually is, not just a single default number.
-- LEFT JOIN + COALESCE keeps loans with zero missed payments in the
-- "0 - Current" bucket instead of dropping them.
WITH loan_worst_dpd AS (
    SELECT loan_id, MAX(dpd) AS current_dpd
    FROM repayments
    WHERE payment_status = 'missed'
    GROUP BY loan_id
)
SELECT
    CASE
        WHEN w.current_dpd IS NULL THEN '0 - Current'
        WHEN w.current_dpd <= 30 THEN '1-30 (early delinquency)'
        WHEN w.current_dpd <= 60 THEN '31-60'
        WHEN w.current_dpd <= 90 THEN '61-90'
        ELSE '90+ (severe)'
    END AS dpd_bucket,
    COUNT(*) AS loan_count,
    ROUND(SUM(l.loan_amount), 2) AS outstanding_amount
FROM loans l
LEFT JOIN loan_worst_dpd w ON l.loan_id = w.loan_id
WHERE l.status != 'closed'
GROUP BY dpd_bucket
ORDER BY MIN(COALESCE(w.current_dpd, 0));


-- ============================================================
-- 5. Credit score bands
-- ============================================================

-- Does a better credit score actually mean fewer defaults?
SELECT
    CASE
        WHEN c.credit_score < 600 THEN '<600'
        WHEN c.credit_score < 700 THEN '600-699'
        WHEN c.credit_score < 750 THEN '700-749'
        WHEN c.credit_score < 800 THEN '750-799'
        ELSE '800+'
    END AS credit_band,
    COUNT(*) AS total_loans,
    SUM(CASE WHEN l.status = 'defaulted' THEN 1 ELSE 0 END) AS defaults,
    ROUND(100.0 * SUM(CASE WHEN l.status = 'defaulted' THEN 1 ELSE 0 END) / COUNT(*), 2) AS default_rate_pct
FROM loans l
JOIN customers c ON l.customer_id = c.customer_id
GROUP BY credit_band
ORDER BY MIN(c.credit_score);


-- ============================================================
-- 6. Risk drivers - why loans go bad, not just how many do
-- ============================================================

-- Default rate by income band
SELECT
    CASE
        WHEN c.income < 30000 THEN '<30k'
        WHEN c.income < 50000 THEN '30k-50k'
        WHEN c.income < 75000 THEN '50k-75k'
        WHEN c.income < 100000 THEN '75k-100k'
        ELSE '100k+'
    END AS income_band,
    COUNT(*) AS total_loans,
    SUM(CASE WHEN l.status = 'defaulted' THEN 1 ELSE 0 END) AS defaults,
    ROUND(100.0 * SUM(CASE WHEN l.status = 'defaulted' THEN 1 ELSE 0 END) / COUNT(*), 2) AS default_rate_pct
FROM loans l
JOIN customers c ON l.customer_id = c.customer_id
GROUP BY income_band
ORDER BY MIN(c.income);

-- Default rate by employment type
SELECT
    c.employment_type,
    COUNT(*) AS total_loans,
    SUM(CASE WHEN l.status = 'defaulted' THEN 1 ELSE 0 END) AS defaults,
    ROUND(100.0 * SUM(CASE WHEN l.status = 'defaulted' THEN 1 ELSE 0 END) / COUNT(*), 2) AS default_rate_pct
FROM loans l
JOIN customers c ON l.customer_id = c.customer_id
GROUP BY c.employment_type
ORDER BY default_rate_pct DESC;


-- ============================================================
-- 7. Branch and regional risk
-- ============================================================

-- Portfolio size and default rate by region
SELECT
    b.region,
    COUNT(*) AS total_loans,
    SUM(l.loan_amount) AS portfolio_value,
    SUM(CASE WHEN l.status = 'defaulted' THEN 1 ELSE 0 END) AS defaults,
    ROUND(100.0 * SUM(CASE WHEN l.status = 'defaulted' THEN 1 ELSE 0 END) / COUNT(*), 2) AS default_rate_pct
FROM loans l
JOIN branches b ON l.branch_id = b.branch_id
GROUP BY b.region
ORDER BY portfolio_value DESC;

-- Same idea at branch level, but ranked - this finds the branch with a
-- small portfolio and a surprisingly high default rate, which the
-- region-level view above would hide
WITH branch_stats AS (
    SELECT
        b.branch_name,
        b.region,
        COUNT(*) AS total_loans,
        SUM(l.loan_amount) AS portfolio_value,
        SUM(CASE WHEN l.status = 'defaulted' THEN 1 ELSE 0 END) AS defaults,
        ROUND(100.0 * SUM(CASE WHEN l.status = 'defaulted' THEN 1 ELSE 0 END) / COUNT(*), 2) AS default_rate_pct
    FROM loans l
    JOIN branches b ON l.branch_id = b.branch_id
    GROUP BY b.branch_name, b.region
)
SELECT
    branch_name,
    region,
    total_loans,
    portfolio_value,
    default_rate_pct,
    RANK() OVER (ORDER BY default_rate_pct DESC) AS risk_rank
FROM branch_stats
ORDER BY risk_rank;


-- ============================================================
-- 8. Extra queries - trend and concentration risk
-- ============================================================

-- Is the default rate getting better or worse month over month?
-- LAG() pulls the previous month's rate so we can see the actual delta,
-- not just a static number per month.
WITH monthly_npa AS (
    SELECT
        DATE_FORMAT(disbursement_date, '%Y-%m') AS disb_month,
        SUM(CASE WHEN status = 'defaulted' THEN 1 ELSE 0 END) AS defaults,
        COUNT(*) AS total_loans
    FROM loans
    GROUP BY disb_month
)
SELECT
    disb_month,
    defaults,
    total_loans,
    ROUND(100.0 * defaults / total_loans, 2) AS npa_rate_pct,
    ROUND(100.0 * defaults / total_loans, 2)
        - LAG(ROUND(100.0 * defaults / total_loans, 2)) OVER (ORDER BY disb_month) AS mom_change
FROM monthly_npa
ORDER BY disb_month;

-- Which branches approve the most applications, ranked
-- (DENSE_RANK so tied branches don't cause a gap in the ranking)
WITH branch_approval AS (
    SELECT
        b.branch_name,
        COUNT(*) AS total_apps,
        SUM(CASE WHEN a.approval_status = 'Approved' THEN 1 ELSE 0 END) AS approved,
        ROUND(100.0 * SUM(CASE WHEN a.approval_status = 'Approved' THEN 1 ELSE 0 END) / COUNT(*), 2) AS approval_rate_pct
    FROM loan_applications a
    JOIN branches b ON a.branch_id = b.branch_id
    GROUP BY b.branch_name
)
SELECT
    branch_name,
    total_apps,
    approved,
    approval_rate_pct,
    DENSE_RANK() OVER (ORDER BY approval_rate_pct DESC) AS approval_rank
FROM branch_approval
ORDER BY approval_rank;

-- Customers with more than one loan - this is concentration risk,
-- i.e. how much money the bank has tied up in a single customer
SELECT
    c.customer_id,
    c.name,
    c.credit_score,
    COUNT(l.loan_id) AS num_loans,
    SUM(l.loan_amount) AS total_exposure
FROM customers c
JOIN loans l ON c.customer_id = l.customer_id
GROUP BY c.customer_id, c.name, c.credit_score
HAVING COUNT(l.loan_id) > 1
ORDER BY total_exposure DESC;
