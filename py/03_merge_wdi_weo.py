from __future__ import annotations

from pathlib import Path
import pandas as pd


ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "data_raw"
CLEAN = ROOT / "data_clean"
REG = ROOT / "registry"
CLEAN.mkdir(exist_ok=True)

WDI_PATH = RAW / "wdi_long.parquet"
WEO_PATH = RAW / "weo_long.parquet"

IND_WDI = REG / "indicators_wdi.csv"
IND_WEO = REG / "indicators_weo.csv"

OUT_LONG = CLEAN / "panel_long.parquet"
OUT_COVERAGE = CLEAN / "coverage_report.csv"


def main():
    wdi = pd.read_parquet(WDI_PATH)
    weo = pd.read_parquet(WEO_PATH)

    # unify schema
    wdi = wdi[["iso3", "year", "indicator_code", "value"]].copy()
    weo = weo[["iso3", "year", "indicator_code", "value"]].copy()

    # tag sources (optional but useful)
    wdi["source"] = "WDI"
    weo["source"] = "WEO"

    panel = pd.concat([wdi, weo], ignore_index=True)

    # Load indicator metadata for pillars/names
    meta_wdi = pd.read_csv(IND_WDI)
    meta_weo = pd.read_csv(IND_WEO)
    meta = pd.concat([meta_wdi, meta_weo], ignore_index=True)

    meta = meta.rename(columns={"indicator_code": "indicator_code"})
    meta = meta[["pillar", "indicator_code", "indicator_name", "source"]].drop_duplicates()

    panel = panel.merge(meta, on="indicator_code", how="left", suffixes=("", "_meta"))

    # Save master long panel
    panel.to_parquet(OUT_LONG, index=False)
    print(f"Saved: {OUT_LONG} rows={len(panel)} indicators={panel['indicator_code'].nunique()}")

    # --- Coverage report ---
    # Coverage = share of non-missing values in the country-year grid for each indicator.
    # We define the grid based on observed iso3/year in the PANEL (not ALL possible).
    iso_year = panel[["iso3", "year"]].drop_duplicates()
    grid_n = len(iso_year)

    cov = (
        panel.dropna(subset=["value"])
        .groupby(["pillar", "indicator_code", "indicator_name"], dropna=False)
        .agg(non_missing=("value", "count"))
        .reset_index()
    )
    cov["grid_n"] = grid_n
    cov["coverage_pct"] = (cov["non_missing"] / cov["grid_n"]) * 100

    # Also show coverage by recent windows (useful for EM investing)
    def window_cov(df: pd.DataFrame, start: int, end: int, label: str) -> pd.DataFrame:
        win = df[(df["year"] >= start) & (df["year"] <= end)]
        iso_year_win = win[["iso3", "year"]].drop_duplicates()
        grid_win = len(iso_year_win)
        out = (
            win.dropna(subset=["value"])
            .groupby(["indicator_code"])
            .agg(non_missing=( "value", "count"))
            .reset_index()
        )
        out[f"grid_{label}"] = grid_win
        out[f"coverage_{label}_pct"] = (out["non_missing"] / grid_win) * 100 if grid_win else 0
        return out[["indicator_code", f"coverage_{label}_pct"]]

    cov_2010_2024 = window_cov(panel, 2010, 2024, "2010_2024")
    cov_2000_2024 = window_cov(panel, 2000, 2024, "2000_2024")

    cov = cov.merge(cov_2000_2024, on="indicator_code", how="left")
    cov = cov.merge(cov_2010_2024, on="indicator_code", how="left")

    cov = cov.sort_values(["pillar", "coverage_2010_2024_pct", "coverage_pct"], ascending=[True, False, False])
    cov.to_csv(OUT_COVERAGE, index=False)
    print(f"Saved: {OUT_COVERAGE}")


if __name__ == "__main__":
    main()
