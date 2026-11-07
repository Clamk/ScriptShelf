"""Combine all CSV files in a folder into one table, tagging each row with its source file."""
from pathlib import Path
import pandas as pd

folder = Path(r"D:\Exports\Plate01")
frames = []
for csv in sorted(folder.glob("*.csv")):
    if csv.name == "combined.csv":
        continue
    df = pd.read_csv(csv)
    df["source_file"] = csv.name
    frames.append(df)

combined = pd.concat(frames, ignore_index=True)
combined.to_csv(folder / "combined.csv", index=False)
print(f"{len(frames)} files, {len(combined)} rows -> combined.csv")