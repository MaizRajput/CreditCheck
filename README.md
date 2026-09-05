# CreditCheck

An end-to-end BFSI credit risk analytics project: a synthetic loan
portfolio, analyzed in MySQL and visualized in a Power BI dashboard.

## What this is

A bank lends money across four loan types (home, business, auto,
personal) through 25 branches. Some borrowers pay on time, some miss
EMIs, some default entirely. This project builds the SQL and Power BI
layer to answer the questions a credit risk team actually asks:

- How big is the portfolio, and how much of it is at risk?
- Which branches and regions carry the most risk?
- Does credit score actually predict default? Does income? Employment type?
- Is the default rate trending up or down month over month?
- Where is the bank losing the most money when a loan does go bad?

## Data

Synthetic dataset, 5 tables:

| Table              | Rows     | What it holds                          |
|--------------------|----------|-----------------------------------------|
| `branches`         | 25       | Branch name, city, region, manager      |
| `customers`         | 5,000    | Demographics, income, credit score      |
| `loan_applications` | 7,500+   | Every application, approved or not      |
| `loans`             | 6,113    | Disbursed loans only                    |
| `repayments`        | 153,000+ | One row per EMI installment (fact table)|

Total portfolio value: ₹7.37bn.

## Tech stack

- **MySQL 8.0+** for all analysis queries (window functions require 8.0+)
- **Power BI** for the dashboard, with a star-schema data model
- **DAX** for all measures and calculated columns

## Repo structure

```
creditcheck/
├── schema.sql          -- table definitions and indexes
├── queries.sql          -- 15 analysis queries, organized by dashboard section
├── dax_measures.md       -- every calculated column and measure used in Power BI
├── CreditCheck.pbix      -- the dashboard file
└── dashboard_screenshots/
```

## SQL highlights

15 queries covering portfolio KPIs, disbursement trends, loan-type
breakdowns, delinquency buckets, credit/income risk segmentation, and
branch-level risk. Beyond basic aggregation, this includes:

- **Window functions** - `RANK()` for branch risk ranking, `DENSE_RANK()`
  for branch approval ranking, `LAG()` for month-over-month default rate
  change
- **CTEs** feeding into window functions for cleaner, more readable
  multi-step queries
- **LEFT JOIN + COALESCE** to correctly bucket loans with zero missed
  payments, instead of silently dropping them
- **HAVING on an aggregate** to isolate customers holding more than one
  loan, as a concentration-risk check

Full breakdown of what each query answers is in the comments inside
`queries.sql`.

## Power BI / DAX highlights

- Star-schema model: `repayments` as the fact table, everything else as
  dimensions, single-direction relationships
- A dedicated `Dates` table with a custom **Indian financial year**
  (Apr-Mar) quarter column, not calendar-year quarters
- 7 calculated columns (credit/income bands, DPD bucket, financial
  quarter) and 23 measures - full list with explanations in
  `dax_measures.md`
- `RANKX` for branch default ranking, `SUMX` for row-by-row interest
  income calculation, and layered measures (e.g. loss = expected minus
  recovered, each side its own measure)
- 2-page dashboard with 5 interactive slicers: region, branch, financial
  quarter, loan status, and a year range slider

## Key findings

- Default rate falls cleanly from **8.11% to 2.20%** as credit score
  moves from below 600 to above 800 - credit score is a genuinely
  predictive signal in this data, not noise
- **Business loans** are the highest-loss segment by rupee amount lost to
  default, despite home loans holding a larger share of total portfolio
  value - a concentration risk that a volume-only view would miss
- Missed EMI rate falls steadily as income rises, reinforcing income band
  as a real repayment-risk indicator

## Assumptions worth stating up front

`Outstanding Portfolio` uses the full loan amount for any loan that isn't
closed, since the dataset doesn't track a separate amortized balance that
decreases with each EMI paid. That's a reasonable simplification for a
portfolio-risk view, but it's an approximation, not an exact remaining
balance - noted here rather than presented as more precise than it is.

## Running this yourself

1. Run `schema.sql` in MySQL 8.0+ to create the database and tables
2. Load the 5 CSVs into their matching tables (in the order: branches,
   customers, loan_applications, loans, repayments, since later tables
   have foreign keys into earlier ones)
3. Run the queries in `queries.sql` directly, or open `CreditCheck.pbix`
   in Power BI Desktop and point it at the same data
