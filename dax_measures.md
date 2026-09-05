# CreditCheck - DAX Reference

This is a plain reference of every calculated column and measure used in the
Power BI dashboard, kept outside the .pbix so the logic is visible without
opening Power BI (and so it's readable on GitHub).

## Data model

- `repayments` is the fact table - one row per EMI installment, the most
  granular data in the model.
- `customers`, `branches`, `loan_applications`, and `loans` are dimension
  tables, joined one-to-many into `repayments` / `loans` / `loan_applications`.
- All relationships are single-direction, with the "many" side always being
  `loans`, `loan_applications`, or `repayments`.

---

## Calculated columns

These are added directly on the tables, before any measures are built on
top of them.

**On `customers`:**

```dax
Credit Band =
SWITCH(
    TRUE(),
    customers[credit_score] < 600, "<600",
    customers[credit_score] < 700, "600-699",
    customers[credit_score] < 750, "700-749",
    customers[credit_score] < 800, "750-799",
    "800+"
)

Income Band =
SWITCH(
    TRUE(),
    customers[income] < 30000, "<30k",
    customers[income] < 50000, "30k-50k",
    customers[income] < 75000, "50k-75k",
    customers[income] < 100000, "75k-100k",
    "100k+"
)
```

**On `loans`:**

```dax
Current DPD =
VAR WorstDPD =
    CALCULATE(
        MAX(repayments[dpd]),
        FILTER(repayments, repayments[loan_id] = loans[loan_id] && repayments[payment_status] = "missed")
    )
RETURN IF(ISBLANK(WorstDPD), 0, WorstDPD)
```
Looks across all of a loan's missed installments and keeps the worst
(highest) DPD value. If a loan has never missed a payment, this returns 0
instead of blank.

```dax
DPD Bucket =
SWITCH(
    TRUE(),
    loans[Current DPD] = 0, "0 - Current",
    loans[Current DPD] <= 30, "1-30",
    loans[Current DPD] <= 60, "31-60",
    loans[Current DPD] <= 90, "61-90",
    "90+"
)
```

**On the `Dates` table:**

```dax
Month = FORMAT(Dates[Date], "MMM YYYY")

MonthNum = YEAR(Dates[Date]) * 100 + MONTH(Dates[Date])
```
`MonthNum` exists purely so months sort correctly on chart axes (text
month names like "Jan 2024" sort alphabetically otherwise).

```dax
Financial Quarter =
VAR m = MONTH(Dates[Date])
RETURN
SWITCH(
    TRUE(),
    m IN {4,5,6}, "Q1 (Apr-Jun)",
    m IN {7,8,9}, "Q2 (Jul-Sep)",
    m IN {10,11,12}, "Q3 (Oct-Dec)",
    "Q4 (Jan-Mar)"
)
```
Uses the Indian financial year (April to March) instead of the calendar
year, since that's how this data would actually be reported in a BFSI
context.

---

## Measures

Grouped by what they're used for, not alphabetically.

### Portfolio size

```dax
Total Loans = COUNTROWS(loans)

Active Loans = CALCULATE(COUNTROWS(loans), loans[status] = "active")

Defaulted Loans = CALCULATE(COUNTROWS(loans), loans[status] = "defaulted")

Total Portfolio Value = SUM(loans[loan_amount])

Outstanding Portfolio = CALCULATE(SUM(loans[loan_amount]), loans[status] <> "closed")

Avg Loan Amount = AVERAGE(loans[loan_amount])

Avg Interest Rate = AVERAGE(loans[interest_rate])

Avg Credit Score = AVERAGE(customers[credit_score])
```

Note on `Outstanding Portfolio`: the dataset doesn't track a separate
amortized balance that goes down with each EMI paid, so this is the full
`loan_amount` for any loan that isn't closed yet. That's a reasonable
simplification for a portfolio-risk view, but worth stating as an
assumption rather than presenting it as an exact remaining balance.

### Applications and approvals

```dax
Total Applications = COUNTROWS(loan_applications)

Approved Applications =
CALCULATE(COUNTROWS(loan_applications), loan_applications[approval_status] = "Approved")

Approval Rate % = DIVIDE([Approved Applications], [Total Applications], 0)
```

### Repayment and collection health

```dax
Amount Collected = SUM(repayments[amount_paid])

Amount Due = SUM(repayments[amount_due])

Repayment Rate % = DIVIDE([Amount Collected], [Amount Due], 0)

Missed EMI Rate % =
DIVIDE(
    CALCULATE(COUNTROWS(repayments), repayments[payment_status] = "missed"),
    COUNTROWS(repayments),
    0
)

Repayment Chance % =
DIVIDE(
    CALCULATE(COUNTROWS(repayments), repayments[payment_status] <> "missed"),
    COUNTROWS(repayments),
    0
)
```

### Default and loss

```dax
Default Rate % = DIVIDE([Defaulted Loans], [Total Loans], 0)

Expected from Defaulted = CALCULATE(SUM(repayments[amount_due]), loans[status] = "defaulted")

Recovered from Defaulted = CALCULATE(SUM(repayments[amount_paid]), loans[status] = "defaulted")

Amount Lost on Default = [Expected from Defaulted] - [Recovered from Defaulted]
```
`Amount Lost on Default` is built on top of two other measures rather than
written as one long formula - easier to audit each piece separately if a
number looks wrong.

### Interest income

```dax
Total Interest Earned =
SUMX(loans, loans[loan_amount] * loans[interest_rate]/100 * loans[tenure_months]/12)
```
Calculated row by row across every loan (simple interest based on amount,
rate, and tenure) rather than as one flat estimate on the total portfolio.

### Branch ranking

```dax
Branch Default Rank = RANKX(ALL(branches[branch_name]), CALCULATE([Default Rate %]), , DESC)
```
Ranks every branch by its default rate, ignoring whatever filter context
the report page is currently in - this is what powers the "riskiest
branch" view independent of which region or quarter is selected elsewhere
on the page.

---

## A note for future me

If a KPI card ever looks wrong, check the `DIVIDE(x, y, 0)` pattern first -
every rate measure in this file uses it instead of a raw `/` so nothing
breaks when a slicer filters a group down to zero rows. That's usually
where a "blank card" bug comes from if it's not there.
