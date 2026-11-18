"""Load cleaned sales into SQLite, run sql/analysis_queries.sql and export tables for the Power BI / Tableau dashboard."""
import sqlite3
from pathlib import Path
import pandas as pd

root = Path(__file__).resolve().parents[1]
db = root / "data" / "retail.db"
con = sqlite3.connect(db)
df = pd.read_csv(root / "data" / "retail_clean.csv.gz", parse_dates=["invoice_date"])
df["invoice_date"] = df["invoice_date"].dt.strftime("%Y-%m-%d %H:%M:%S")
df.to_sql("sales", con, if_exists="replace", index=False)

sql = (root / "sql" / "analysis_queries.sql").read_text()
for block in [b.strip() for b in sql.split(";") if b.strip()]:
    title = next((l[3:] for l in block.splitlines() if l.startswith("-- Q")), "query")
    res = pd.read_sql(block, con)
    print(f"\n=== {title} ===")
    print(res.head(15).to_string(index=False))
    export = next((l.split("export:")[1].strip() for l in block.splitlines() if "export:" in l), None)
    if export:
        res.to_csv(root / "data" / export, index=False)
