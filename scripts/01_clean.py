"""Clean the UCI Online Retail II dataset (UK online gift retailer, Dec 2009 - Dec 2011).

Download: https://archive.ics.uci.edu/dataset/502/online+retail+ii
Usage:    python scripts/01_clean.py <path to online_retail_II.xlsx>
Output:   data/retail_clean.csv.gz (+ data/cleaning_log.csv)
"""
import sys
from pathlib import Path
import pandas as pd

root = Path(__file__).resolve().parents[1]
sheets = pd.read_excel(sys.argv[1], sheet_name=None, dtype={"Invoice": str, "StockCode": str})
df = pd.concat(sheets.values(), ignore_index=True)
df.columns = ["invoice", "stock_code", "description", "quantity", "invoice_date", "unit_price", "customer_id", "country"]

log = [("Raw rows (both sheets)", len(df))]
df = df.drop_duplicates();                                   log.append(("After removing exact duplicates", len(df)))
df["is_cancellation"] = df["invoice"].str.startswith("C")
cancellations = df[df["is_cancellation"]]
df = df[~df["is_cancellation"]];                             log.append(("After removing cancellations (invoice starts with C)", len(df)))

# Remove the original order lines that were later cancelled (same customer, product and quantity,
# cancelled on or after the order date). Without this step, mistaken bulk orders such as
# 80,995 x "PAPER CRAFT , LITTLE BIRDIE" stay in the data and distort the product ranking.
c = (cancellations.dropna(subset=["customer_id"])
     .assign(quantity=lambda d: -d["quantity"])
     [["customer_id", "stock_code", "quantity", "invoice_date"]]
     .rename(columns={"invoice_date": "cancel_date"}))
df = df.reset_index().rename(columns={"index": "row_id"})
m = df.merge(c, on=["customer_id", "stock_code", "quantity"])
m = m[m["cancel_date"] >= m["invoice_date"]]
# each cancellation removes at most one original line: the latest one before it
m = m.sort_values("invoice_date").groupby(["customer_id", "stock_code", "quantity", "cancel_date"]).tail(1)
df = df[~df["row_id"].isin(m["row_id"])].drop(columns="row_id")
log.append(("After removing orders that were later cancelled", len(df)))
df = df[(df["quantity"] > 0) & (df["unit_price"] > 0)];      log.append(("After removing zero/negative quantity or price", len(df)))
non_products = ["POST", "DOT", "M", "BANK CHARGES", "AMAZONFEE", "CRUK", "D", "S", "B", "ADJUST", "ADJUST2", "TEST001", "TEST002", "PADS", "C2"]
df = df[~df["stock_code"].str.upper().isin(non_products)];   log.append(("After removing postage, fees and manual adjustments", len(df)))

df["description"] = df["description"].str.strip().str.upper()
df["customer_id"] = df["customer_id"].astype("Int64")
df["revenue"] = (df["quantity"] * df["unit_price"]).round(2)
df["month"] = df["invoice_date"].dt.to_period("M").astype(str)
df["has_customer_id"] = df["customer_id"].notna()
log.append(("Rows with a customer ID (used for customer analysis)", int(df["has_customer_id"].sum())))

df.drop(columns="is_cancellation").to_csv(root / "data" / "retail_clean.csv.gz", index=False, compression="gzip")
pd.DataFrame(log, columns=["step", "rows"]).to_csv(root / "data" / "cleaning_log.csv", index=False)
print(pd.DataFrame(log, columns=["step", "rows"]).to_string(index=False))
print(f"Cancelled lines removed: {len(cancellations):,}, value £{-(cancellations['quantity'] * cancellations['unit_price']).sum():,.0f}")
