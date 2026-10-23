# Does the way customers pay predict cancelled orders? A check on real data

A SQL and Python analysis of about 97,000 real e-commerce orders from Brazil (January 2017 to August 2018). Nothing in this data is planted, so unlike the [synthetic project](../README.md) the findings are whatever the data says, including where it contradicts what I expected.

**Data:** *Brazilian E-Commerce Public Dataset by Olist*, published by Olist on [Kaggle](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce), licensed [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/). The raw files are not included here; see "Run it". Values are in Brazilian reais (BRL).

## The question, and what I expected

Payment methods differ in how fast and how reliably the money arrives. In Brazil, *boleto* is a printed or digital bank slip that the customer pays later, often a day or more after ordering. Card payments can be split into installments. Olist also records *vouchers* as a payment type.

I expected that the slower or more complex ways to pay (boleto, many installments) would go with more cancelled orders. The data says otherwise.

## Scope and data quality

Three tables (orders, order payments, customers) were joined into one row per order (`sql/build.sql`). Fifteen data quality rules (`sql/quality_checks.sql`) were run. Seven pass outright, including all duplicate-key and customer-link checks. The other eight flag small issues, each with a stated handling, for example one order with no payment record (dropped) and 14 delivered orders with no approval time (left out of the speed figures).

The analysis covers orders **bought January 2017 to August 2018 that were delivered or cancelled**: 96,791 orders, of which 580 (0.60%) were cancelled.

- Earlier months have only a few hundred orders, and the dataset ends in October 2018. The last two months (September, October 2018) contain only 19 finished orders, all cancelled, because delivered orders had not been recorded yet. Including them would show a 100% cancellation rate that means nothing.
- In-flight orders (shipped, processing, invoiced, created, approved: 1,699) and `unavailable` orders (602, a stock problem at the seller) are left out, as neither is a finished payment outcome.

An order can be paid with several payments (2,961 of 99,440 are). Each order is labelled by its single payment method, or `mixed` when it combined methods.

## What the data shows

Differences are given in percentage points with 95% confidence intervals; p-values come from Fisher's exact test (`olist_stats.py`).

**1. Payment method does not explain cancellations.** Credit card orders cancel at 0.56% (404 of 72,322) and boleto at 0.48% (92 of 19,232). The difference is -0.08 points [-0.19 to +0.04], p = 0.19: nothing distinguishable from noise. Debit card (0.47%) has only 7 cancellations in 1,489 orders, too few to say anything.

**2. The loudest signal was a single month.** Voucher-only orders cancel at 3.68% against 0.56% for cards, an odds ratio of 7.2 in a regression that adjusts for order value and installments. Taken at face value, that reads as "vouchers are risky". But 51 of the 57 voucher-only cancellations happened in **August 2018**: 39.2% of that month's 130 voucher-only orders, against 0.42% (6 of 1,421) in every other month. With August 2018 removed, voucher-only orders are no different from card orders (-0.14 points [-0.38 to +0.36], p = 0.59). This data cannot say what happened in August 2018 (a promotion, a voucher system fault, a recording change); it is a question to put to the business.

**3. Installments do not matter.** Credit card orders with 7 or more installments cancel at 0.64% against 0.54% for a single payment: +0.10 points [-0.06 to +0.29], p = 0.23. In the regression each extra installment has an odds ratio of 0.98 [0.95 to 1.02].

**4. Bigger orders cancel more, modestly.** Orders of BRL 500 or more cancel at 1.24% against 0.57% below that (+0.67 points [+0.37 to +1.06]). After removing August 2018 and holding payment method and installments constant, each doubling of order value multiplies the odds of cancellation by 1.13 [1.04 to 1.23].

**5. The real difference between payment methods is speed.** Median time from order to payment approval is 29.1 hours for boleto against 0.27 hours (16 minutes) for credit cards. Only 3.0% of boleto orders are approved within an hour, against 80.1% of card orders. Delivered boleto orders also arrive later, with a median of 11.3 days against 10.0 for cards. That 1.3-day gap is about the size of the approval wait, which fits the explanation but does not prove it: boleto customers may also differ in where they live and what they buy.

**6. Two months stand out on cancellations.** February 2018 (1.10%, 73 cancellations) and August 2018 (1.31%, 84) sit well above the previous three months' average (0.39% and 0.44%). August is the voucher episode above. February 2018 is not tied to one payment method: boleto 0.9% and card 1.1%. These tables cannot explain it.

**7. How much is at stake.** Cancelled orders hold BRL 133,102 of the BRL 15.5 million paid in the period (0.86%). The August 2018 voucher episode alone accounts for BRL 17,586 of that, 13%.

## What I would do with this

- **Do not restrict boleto to cut cancellations.** There is no evidence it causes any. Judge it on speed instead: a one-day wait before approval is a cost to delivery time, not to completion.
- **Investigate August 2018 vouchers with the business before drawing a conclusion.** A rule built on the all-months result would have targeted the wrong thing.
- **Watch high-value orders** for cancellation drivers other than payment method, since value is the only factor that holds up in the regression.
- **Look for the February 2018 cause outside these tables** (seller, logistics or product data).

## Limits

- Observational data: associations, not causes. Boleto customers, voucher users and large-order buyers differ in ways this data does not record.
- `canceled` mixes customer-initiated and seller-initiated cancellations; the reason is not in the data.
- Six tests were run, and the p-values are not corrected for that. The three significant results (T2, T4 and T6 in `olist_tests.csv`) would all survive a Bonferroni correction (threshold 0.008).
- The dataset is an anonymised sample of Olist orders, and nominal BRL values are not adjusted for inflation.
- Orders are treated as independent. The 99,441 customer IDs map to 96,096 distinct customers, so some customers appear in more than one order; this is a minor approximation.

## Run it

1. Download the dataset from [Kaggle](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) and unzip it.
2. Copy these three files into `olist/data/`: `olist_orders_dataset.csv`, `olist_order_payments_dataset.csv`, `olist_customers_dataset.csv`.
3. From the `olist/` folder:

```bash
pip install -r ../requirements.txt
python3 run_olist.py       # data quality checks and analysis queries -> output/*.csv
python3 olist_stats.py     # tests and regression -> output/olist_tests.csv, output/olist_logit.csv
```

## Attribution and licence

Data: Olist, *Brazilian E-Commerce Public Dataset by Olist*, via Kaggle, CC BY-NC-SA 4.0. The result tables in `olist/output/` are derived from that data and are shared under the same licence: attribution required, non-commercial use only, and adaptations shared alike. The queries, scripts and write-up are my own work.

---
Devesh Kumar Srivastav · [LinkedIn](https://www.linkedin.com/in/devesh-kumar-srivastav-96a274174/)
