"""Real-data analysis on the Olist Brazilian e-commerce dataset (CC BY-NC-SA 4.0).

Expects three files in olist/data/ (download them yourself from Kaggle, see README):
  olist_orders_dataset.csv, olist_order_payments_dataset.csv, olist_customers_dataset.csv

Loads them into in-memory SQLite, builds the order-level table, runs the data quality checks and
the analysis queries, and writes each result to olist/output/<name>.csv.
"""
import re
import sqlite3
import sys
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).parent
DATA = ROOT / "data"
FILES = {
    "orders": "olist_orders_dataset.csv",
    "order_payments": "olist_order_payments_dataset.csv",
    "customers": "olist_customers_dataset.csv",
}


def build_db():
    """Return a SQLite connection with the raw tables, order_level and the scope view."""
    missing = [f for f in FILES.values() if not (DATA / f).exists()]
    if missing:
        sys.exit(f"Missing in {DATA}: {', '.join(missing)}\n"
                 "Download the dataset from https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce")
    con = sqlite3.connect(":memory:")
    for table, file in FILES.items():
        pd.read_csv(DATA / file).to_sql(table, con, index=False)
    con.executescript((ROOT / "sql" / "build.sql").read_text())
    return con


def run_named_queries(con, sql_file):
    """Run every '-- name: x' block in a SQL file; write output/x.csv; return {name: DataFrame}."""
    results = {}
    blocks = re.split(r"(?m)^-- name: (\w+)\n", (ROOT / "sql" / sql_file).read_text())[1:]
    (ROOT / "output").mkdir(exist_ok=True)
    for name, query in zip(blocks[0::2], blocks[1::2]):
        query = re.split(r"\n\n(?=--)", query)[0].strip()
        df = pd.read_sql_query(query, con)
        df.to_csv(ROOT / "output" / f"{name}.csv", index=False)
        results[name] = df
    return results


if __name__ == "__main__":
    con = build_db()
    for sql_file in ["quality_checks.sql", "analysis.sql"]:
        for name, df in run_named_queries(con, sql_file).items():
            print(f"\n== {name} ({len(df)} rows)")
            print(df.to_string(index=False))
