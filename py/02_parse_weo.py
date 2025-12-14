from __future__ import annotations

from pathlib import Path
import pandas as pd


ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "registry"
RAW = ROOT / "data_raw"

IND_PATH = REGISTRY / "indicators_weo.csv"
OUT_PATH = RAW / "weo_long.parquet"

WEO_FILE = RAW / "weoapr2025all.xls"


def main():
    if not WEO_FILE.exists():
        raise FileNotFoundError(f"Cannot find WEO file at: {WEO_FILE}")

    # Load indicator registry
    ind = pd.read_csv(IND_PATH)
    wanted = set(ind["indicator_code"].dropna().astype(str))

    # --- Read IMF WEO bulk file ---
    # NOTE: File is UTF-16 TSV mislabeled as .xls
    df = pd.read_csv(
        WEO_FILE,
        sep="\t",
        encoding="utf-16-le",
        engine="python"
    )
    print("Read WEO file as UTF-16 TSV")

    # --- Validate required columns ---
    required_cols = {"ISO", "WEO Subject Code"}
    missing = required_cols - set(df.columns)
    if missing:
        raise ValueError(
            f"Missing required columns: {missing}\n"
            f"Columns found: {list(df.columns)}"
        )

    # --- Filter to indicators we care about ---
    df = df[df["WEO Subject Code"].astype(str).isin(wanted)].copy()

    # --- Identify year columns ---
    # IMF WEO uses numeric years as column headers
    year_cols = [
        c for c in df.columns
        if isinstance(c, (int, float)) or (isinstance(c, str) and c.isdigit())
    ]

    # Normalize year columns to int
    col_map = {c: int(c) for c in year_cols if not isinstance(c, int)}
    df = df.rename(columns=col_map)

    year_cols = sorted(
        c for c in df.columns
        if isinstance(c, int) and 1900 <= c <= 2100
    )

    # --- Reshape to long format ---
    out = df.melt(
        id_vars=["ISO", "WEO Subject Code"],
        value_vars=year_cols,
        var_name="year",
        value_name="value"
    )

    out = out.rename(
        columns={
            "ISO": "iso3",
            "WEO Subject Code": "indicator_code"
        }
    )

    out["year"] = out["year"].astype(int)
    out["value"] = pd.to_numeric(out["value"], errors="coerce")

    # Drop missing values
    out = out.dropna(subset=["iso3", "year", "value"])

    # --- Save ---
    out.to_parquet(OUT_PATH, index=False)

    print(
        f"Saved: {OUT_PATH}\n"
        f"Rows: {len(out)} | "
        f"Indicators: {out['indicator_code'].nunique()} | "
        f"Countries: {out['iso3'].nunique()}"
    )


if __name__ == "__main__":
    main()
