"""Load data/transactions.csv into SQLite, run every named query in the sql/ folder
and write each result to output/<name>.csv (these files feed the Power BI report).

Query files: quality_checks.sql, analysis.sql, impact_sizing.sql
A query starts at a line "-- name: <name>" and ends at the next blank line followed by a comment.
"""
import re
import sqlite3
from pathlib import Path

import pandas as pd

root = Path(__file__).parent
con = sqlite3.connect(":memory:")
pd.read_csv(root / "data" / "transactions.csv").to_sql("transactions", con, index=False)
(root / "output").mkdir(exist_ok=True)

for file in ["quality_checks.sql", "analysis.sql", "impact_sizing.sql"]:
    path = root / "sql" / file
    if not path.exists():
        continue
    blocks = re.split(r"(?m)^-- name: (\w+)\n", path.read_text())[1:]   # [name, query, name, query, ...]
    for name, query in zip(blocks[0::2], blocks[1::2]):
        query = re.split(r"\n\n(?=--)", query)[0].strip()               # drop the next query's header comment
        result = pd.read_sql_query(query, con)
        result.to_csv(root / "output" / f"{name}.csv", index=False)
        print(f"\n== {name} ({len(result)} rows)")
        print(result.head(25).to_string(index=False))
