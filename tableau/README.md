# Tableau dashboard: build kit

A three-page dashboard on `data/transactions.csv` and `output/impact_sizing.csv`, built in Tableau Public Desktop (free, runs on Mac). Every page carries a "Synthetic data, illustrative" note, because the data is generated (see the main README).

The calculated fields below mirror `powerbi/measures.dax`, so the same numbers must come out. I wrote this kit from Tableau's documented syntax and could not run Tableau here, so **the reconciliation table is your check**: if a number differs, fix the field before building any chart on it.

## 1. Load the data

1. Open Tableau Public Desktop > Connect > Text file > choose `data/transactions.csv`.
2. In the data grid, check the types: `created_at` must be Date & Time (click the type icon to change it), `amount_eur` a decimal number, `is_retry` and `three_ds_required` whole numbers.
3. Add the second file as a separate data source (Data > New Data Source > Text file > `output/impact_sizing.csv`). It is used only on page 3.

## 2. Calculated fields (Analysis > Create Calculated Field)

Tableau renames imported columns to Title Case with spaces (`is_retry` becomes `[Is Retry]`), so the formulas use those display names. The names must match exactly.

| Field name | Formula |
|---|---|
| First attempts | `SUM(IF [Is Retry] = 0 THEN 1 ELSE 0 END)` |
| Approved first attempts | `SUM(IF [Is Retry] = 0 AND [Status] = "approved" THEN 1 ELSE 0 END)` |
| Auth rate % | `[Approved first attempts] / [First attempts]` |
| Requested value EUR | `SUM(IF [Is Retry] = 0 THEN [Amount Eur] END)` |
| Declined value EUR | `SUM(IF [Is Retry] = 0 AND [Status] = "declined" THEN [Amount Eur] END)` |
| Recovered value EUR | `SUM(IF [Is Retry] = 1 AND [Status] = "approved" THEN [Amount Eur] END)` |
| Recovered % of declined value | `[Recovered value EUR] / [Declined value EUR]` |
| Declines | `SUM(IF [Is Retry] = 0 AND [Status] = "declined" THEN 1 ELSE 0 END)` |
| Issuer unavailable % of attempts | `SUM(IF [Is Retry] = 0 AND [Decline Code] = "issuer_unavailable" THEN 1 ELSE 0 END) / [First attempts]` |
| Challenged payments | `SUM(IF [Is Retry] = 0 AND ([Three Ds Outcome] = "challenge_passed" OR [Three Ds Outcome] = "challenge_failed") THEN 1 ELSE 0 END)` |
| Challenge failure % | `SUM(IF [Is Retry] = 0 AND [Three Ds Outcome] = "challenge_failed" THEN 1 ELSE 0 END) / [Challenged payments]` |
| Amount band | `IF [Amount Eur] >= 200 THEN ">= EUR 200" ELSE "< EUR 200" END` |

Format the four ratio fields (`Auth rate %`, `Recovered % of declined value`, `Issuer unavailable % of attempts`, `Challenge failure %`) as percentages with 2 decimals (right-click the field > Default properties > Number format).

## 3. Reconcile before drawing anything

Put each field on a Text mark in a scratch sheet and compare with this table.

| Field (filters) | Expected | Comes from |
|---|---|---|
| First attempts | 88,000 | `transactions` rows where `is_retry = 0` |
| Approved first attempts | 77,740 | same, `status = approved` |
| Auth rate % | 88.34% | 77,740 / 88,000 |
| Auth rate %, by payment_method: card / ewallet / bank_transfer | 84.06% / 94.82% / 96.22% | Q1 |
| Requested value EUR | 5,886,677 | sum of `amount_eur`, first attempts |
| Declined value EUR | 806,796 (806,796.50 unrounded) | Q3; its per-reason values are each rounded, so they add to 806,797 |
| Recovered value EUR | 46,597 | Q8, sum over months |
| Recovered % of declined value | 5.78% | 46,597 / 806,796 |
| Auth rate %, Gamma, non-EUR cards | GBP 73.54, USD 74.01, IDR 74.06, SGD 74.27 | Q2 |
| Challenge failure %, all / EUR 200+ / under EUR 200 | 18.69% / 29.12% / 17.42% | Q6 |
| Issuer unavailable % of attempts, Beta, July | 3.15% | Q5 |
| Auth rate %, Beta, July | 80.35% | Q4 |
| impact_sizing, row 2 Low / High | 32,007 / 64,013 | `impact_sizing.csv` |

One known small difference: Q8 books a recovery in the month of the original decline, while `Recovered value EUR` books it in the month of the retry. A retry can land up to an hour after midnight on the first of a month, so a single month can differ slightly. Full-year totals match.

## 4. Sheets and dashboards

Create one sheet per item, then assemble three dashboards (Dashboard > New Dashboard, size "Automatic" or 1200 x 800). For each dashboard add a text object: "Synthetic data, illustrative".

**Page 1: Is there a problem?**
- KPI tiles: four sheets, each with one field on Text: `First attempts`, `Auth rate %`, `Declined value EUR`, `Recovered % of declined value`.
- Auth rate by month: Columns `MONTH(Created At)`, Rows `Auth rate %`, Color `Provider`. Shows Beta's July dip.
- Auth rate by method: Columns `Auth rate %`, Rows `Payment Method`.
- Filters `Provider`, `Payment Method`, `Currency`: right-click each > Apply to Worksheets > All Using This Data Source, and show them on the dashboard.

**Page 2: Where and why?**
- Decline reasons: Rows `Decline Code`, Columns `Declines`, sorted descending, with `Decline Code` filtered to exclude Null (the two-reasons-explain-55% finding).
- Provider by currency: Rows `Provider`, Columns `Currency`, `Auth rate %` on Color and Text, filter `Payment Method = card`. The four Gamma non-EUR cells should stand out.
- 3DS by amount: Columns `Amount band`, Rows `Challenge failure %`.
- Issuer unavailable by month: Columns `MONTH(Created At)`, Rows `Issuer unavailable % of attempts`, Color `Provider`.

**Page 3: What should we do, and what is it worth?** (data source: `impact_sizing`)
- Bars: Rows `recommendation`, Columns `SUM(addressable_value_eur)`, Color `scenario`.
- Table: `recommendation`, `scenario`, `assumption`, `addressable_value_eur`, so the assumptions stay visible beside the numbers.
- Text object: the four recommendations from the main README and "Gross value, before fees and fraud cost; recommendations overlap and must not be added."

## 5. Publish

1. Create a free Tableau Public account at public.tableau.com. This is your own account, so I cannot create it for you.
2. File > Save to Tableau Public As..., sign in, name it "Where do card payments fail, and what is it worth fixing?".
3. Everything in a Tableau Public workbook is public, including the data. That is fine here: the data is synthetic and the impact table is derived from it.
4. Copy the public URL, export each dashboard as an image (Dashboard > Export Image) into `tableau/`, and link the URL from the main README.

## How to talk about it in an interview

- **Why these three pages?** They follow the question a payments team asks: is there a problem, where and why, and is it worth fixing.
- **Why reconcile to SQL?** A dashboard is only as trustworthy as its numbers, and the SQL outputs were checked first.
- **Why conditional aggregates (`IF [Is Retry] = 0 ...`) in one table instead of filtering the data?** Retries and first attempts live in the same table, and approval rate must count only first attempts while recovered value counts only retries.
- **What would change with real data?** A live connection to a database instead of a CSV, and a data quality page showing the 17 checks.

## Notes from the actual build

- The workbook was built in Tableau Public Desktop on a Mac. Every number on the sheets matched the reconciliation table above: 88,000 first attempts, 88.34% auth rate, EUR 806,797 declined, 5.78% recovered, Gamma non-EUR cards 73.54 to 74.27%, challenge failure 17.42% vs 29.12%, and the four impact rows.
- Dashboard sizes are fixed at 1200 x 800. Dashboard titles carry "Synthetic data, illustrative".
- Page 3 uses a grouped bar (recommendation, then scenario on Rows) instead of a stacked bar: stacking low and high would add two scenarios of the same fix. The "overlap, do not add" caveat sits in the chart title.
- Not built: the cross-dashboard quick filters (provider, payment method, currency) and the assumption table on page 3. The assumptions are in `output/impact_sizing.csv` and the main README.
- The Auth rate % colour scale uses an orange (low) to blue (high) diverging palette, so the four weak Gamma cells read as orange.
