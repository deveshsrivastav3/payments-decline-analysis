# Power BI dashboard: build kit

A three-page report on `data/transactions.csv` and `output/impact_sizing.csv`. Every page carries a "Synthetic data, illustrative" note, because the data is generated (see the main README).

Power BI Desktop is free but runs on Windows only. On an Apple-silicon Mac that means a Windows 11 ARM virtual machine (UTM or Parallels; check each one's current Windows licensing terms) or a Windows PC. Power BI on the web needs a work or school account, so it is not an option with a personal Gmail address.

## Build order

1. **Load.** Paste the two queries from `load.m` (Home > Get data > Blank query > Advanced editor). Name them `transactions` and `impact_sizing`, and fix the two file paths.
2. **Date table and columns.** Create them from the top of `measures.dax`. Relate `Date[Date]` to `transactions[date]` (one to many), mark `Date` as the date table, and sort `Date[Month label]` by `Date[Month]`.
3. **Measures.** Add each measure from `measures.dax` to the `transactions` table; `Addressable value EUR` goes on `impact_sizing`.
4. **Reconcile before drawing anything.** Put each measure in a card or table and compare it with the table below. If a number is off, fix the measure first. A dashboard whose numbers do not match its source is worse than none.
5. **Pages.** Build the three pages below.
6. **Deliver.** Save the `.pbix` and export each page as PNG (File > Export). Put them in `powerbi/` and link them from the main README. "Publish to web" needs a Power BI service account, so screenshots are the way to show it.

## Pages

**Page 1: Is there a problem?**
- Cards: `First attempts`, `Auth rate %`, `Declined value EUR`, `Recovered % of declined value`.
- Line chart: `Auth rate %` by `Date[Month label]`, legend `provider`. This shows Beta's July dip.
- Bar chart: `Auth rate %` by `payment_method`.
- Slicers: `provider`, `payment_method`, `currency`.

**Page 2: Where and why?**
- Bar chart: `Declines` by `decline_code`, sorted descending (the two-reasons-explain-55% finding).
- Matrix: rows `provider`, columns `currency`, values `Auth rate %`, with a page-level filter `payment_method = card` and a colour scale. The four Gamma non-EUR cells should stand out.
- Clustered column: `Challenge failure %` by `Amount band`.
- Line chart: `Issuer unavailable % of attempts` by month, legend `provider`.

**Page 3: What should we do, and what is it worth?**
- Clustered bar: `Addressable value EUR` by `impact_sizing[recommendation]`, legend `scenario`.
- Table: recommendation, scenario, assumption, value. The assumptions stay visible next to the numbers.
- Text box: the four recommendations from the main README and the line "Gross value, before fees and fraud cost; recommendations overlap and must not be added."

## Reconciliation: Power BI must match the SQL

| Measure (filters) | Expected | Comes from |
|---|---|---|
| `First attempts` | 88,000 | `transactions` rows where `is_retry = 0` |
| `Approved first attempts` | 77,740 | same, `status = approved` |
| `Auth rate %` | 88.34% | 77,740 / 88,000 |
| `Auth rate %` for card / ewallet / bank_transfer | 84.06% / 94.82% / 96.22% | Q1 |
| `Requested value EUR` | 5,886,677 | sum of `amount_eur`, first attempts |
| `Declined value EUR` | 806,796 (806,796.50 unrounded) | Q3; its per-reason values are each rounded, so they add to 806,797 |
| `Recovered value EUR` | 46,597 | Q8, sum over months |
| `Recovered % of declined value` | 5.78% | 46,597 / 806,796 |
| `Auth rate %`, Gamma, non-EUR cards | GBP 73.54, USD 74.01, IDR 74.06, SGD 74.27 | Q2 |
| `Challenge failure %`, all / EUR 200+ / under EUR 200 | 18.69% / 29.12% / 17.42% | Q6 |
| `Issuer unavailable % of attempts`, Beta, July | 3.15% | Q5 |
| `Auth rate %`, Beta, July | 80.35% | Q4 |
| `Addressable value EUR`, row 2 Low / High | 32,007 / 64,013 | `impact_sizing.csv` |

Known small difference: Q8 books a recovery in the month of the original decline, while `Recovered value EUR` books it in the month of the retry. A retry can land up to an hour after midnight on the first of a month, so a single month can differ slightly. The full-year totals match.

I wrote the DAX and checked it by reading, but I could not run Power BI here. The reconciliation table is how you find out whether each measure is right.

## How to talk about it in an interview

- **Why these three pages?** They follow the question a payments team asks: is there a problem, where and why, and is it worth fixing.
- **Why reconcile to SQL?** A dashboard is only as trustworthy as its numbers, and the SQL outputs were checked first.
- **Why a separate `Date` table?** Month-over-month logic (`PREVIOUSMONTH`) needs a continuous date table, and it keeps month sorting correct.
- **What would change with real data?** Refresh from a database instead of CSV, row-level security if teams should see only their own providers, and a data quality page showing the 17 checks.
