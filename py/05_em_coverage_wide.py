from __future__ import annotations

from pathlib import Path
import pandas as pd


ROOT = Path(__file__).resolve().parents[1]
CLEAN = ROOT / "data_clean"
REG = ROOT / "registry"

PANEL_EM = CLEAN / "panel_em_long.parquet"
BASELINE = REG / "indicators_baseline_v1.csv"

OUT_COVERAGE = CLEAN / "coverage_em_baseline_v1.csv"
OUT_WIDE = CLEAN / "panel_em_wide_baseline_v1.parquet"


def main():
    panel = pd.read_parquet(PANEL_EM)

    # Keep only the core long schema (ignore any old metadata columns)
    core_cols = ["iso3", "year", "indicator_code", "value"]
    panel = panel[core_cols].copy()
    panel["indicator_code"] = panel["indicator_code"].astype(str)

    # Load baseline registry (source of truth for pillar + names)
    reg = pd.read_csv(BASELINE)
    reg["indicator_code"] = reg["indicator_code"].astype(str)

    # Filter to baseline indicators only
    keep = set(reg["indicator_code"])
    panel = panel[panel["indicator_code"].isin(keep)].copy()

    # Attach clean metadata (no suffix mess)
    reg_small = reg[["pillar", "indicator_code", "indicator_name", "source"]].drop_duplicates()
    panel = panel.merge(reg_small, on="indicator_code", how="left")

    # Hard checks
    if panel["pillar"].isna().any():
        bad = panel.loc[panel["pillar"].isna(), "indicator_code"].unique().tolist()
        raise ValueError(f"Missing pillar for indicator_code(s): {bad}. Check registry file.")
    if panel["indicator_name"].isna().any():
        # Not fatal, but warn you
        print("WARNING: Some indicator_name values are missing in indicators_baseline_v1.csv.")

    # --- Coverage on EM grid ---
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

    def window_cov(start: int, end: int, label: str) -> pd.DataFrame:
        win = panel[(panel["year"] >= start) & (panel["year"] <= end)]
        iso_year_win = win[["iso3", "year"]].drop_duplicates()
        grid_win = len(iso_year_win)

        out = (
            win.dropna(subset=["value"])
            .groupby(["indicator_code"])
            .agg(non_missing=("value", "count"))
            .reset_index()
        )
        out[f"coverage_{label}_pct"] = (out["non_missing"] / grid_win) * 100 if grid_win else 0
        return out[["indicator_code", f"coverage_{label}_pct"]]

    cov = cov.merge(window_cov(2000, 2024, "2000_2024"), on="indicator_code", how="left")
    cov = cov.merge(window_cov(2010, 2024, "2010_2024"), on="indicator_code", how="left")

    cov = cov.sort_values(["pillar", "coverage_2010_2024_pct", "coverage_pct"], ascending=[True, False, False])
    cov.to_csv(OUT_COVERAGE, index=False)
    print(f"Saved coverage: {OUT_COVERAGE}")

    # --- Wide panel (scoring-ready) ---
    wide = panel.pivot_table(
        index=["iso3", "year"],
        columns="indicator_code",
        values="value",
        aggfunc="first"
    ).reset_index()

    wide.to_parquet(OUT_WIDE, index=False)
    print(f"Saved wide panel: {OUT_WIDE} rows={len(wide)} cols={len(wide.columns)}")


if __name__ == "__main__":
    main()
