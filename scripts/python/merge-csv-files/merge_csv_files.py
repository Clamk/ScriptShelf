# ---
# title: Merge all CSV files in a folder into one table
# tags: csv, pandas, data
# tested:
# notes: Asks for a folder, reads every .csv in it, adds a source_file column so
#   you know where each row came from, and writes combined.csv in the same folder.
#   Requires pandas. Skips its own output file if you run it twice.
# ---
"""Combine all CSV files in a folder into one table, tagging each row with its source file."""
from pathlib import Path
import pandas as pd

folder = Path(input("Folder with the CSV files: ").strip().strip('"'))
frames = []
for csv in sorted(folder.glob("*.csv")):
    if csv.name == "combined.csv":
        continue
    df = pd.read_csv(csv)
    df["source_file"] = csv.name
    frames.append(df)

if not frames:
    raise SystemExit(f"No CSV files found in {folder}")

combined = pd.concat(frames, ignore_index=True)
combined.to_csv(folder / "combined.csv", index=False)
print(f"{len(frames)} files, {len(combined)} rows -> combined.csv")
