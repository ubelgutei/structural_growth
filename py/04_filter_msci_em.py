from pathlib import Path
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
CLEAN = ROOT / "data_clean"
REG = ROOT / "registry"

PANEL_IN = CLEAN / "panel_long.parquet"
PANEL_OUT = CLEAN / "panel_em_long.parquet"

MSCI = REG / "msci_em_iso3.csv"


def main():
    panel = pd.read_parquet(PANEL_IN)
    msci = pd.read_csv(MSCI)

    em_iso3 = set(msci["iso3"])

    panel_em = panel[panel["iso3"].isin(em_iso3)].copy()

    panel_em.to_parquet(PANEL_OUT, index=False)

    print(f"Saved: {PANEL_OUT}")
    print(f"Countries: {panel_em['iso3'].nunique()}")
    print(f"Rows: {len(panel_em)}")


if __name__ == "__main__":
    main()
