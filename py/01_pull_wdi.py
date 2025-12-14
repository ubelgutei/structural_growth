from __future__ import annotations

from pathlib import Path
import time
import requests
import pandas as pd


# repo-root + paths
def get_repo_root() -> Path:
    """Best-effort repo root discovery for scripts and notebooks."""
    try:
        start = Path(__file__).resolve()
    except NameError:  # __file__ missing in notebooks/REPL
        start = Path.cwd().resolve()

    if start.is_file():
        start = start.parent

    markers = {".git", "pyproject.toml", "requirements.txt", "renv.lock"}
    for candidate in (start, *start.parents):
        if any((candidate / marker).exists() for marker in markers):
            return candidate
    # Fallback: assume repo root is the parent of the script directory
    return start.parent if start.parent != start else start


ROOT = get_repo_root()
REGISTRY = ROOT / "registry"
RAW = ROOT / "data_raw"
REGISTRY.mkdir(exist_ok=True)
RAW.mkdir(exist_ok=True)

IND_PATH = REGISTRY / "indicators_wdi.csv"
OUT_PATH = RAW / "wdi_long.parquet"
FAIL_PATH = RAW / "wdi_failures.csv"
COUNTRY_CACHE = REGISTRY / "wb_countries_real.csv"


# API config
API_BASE = "https://api.worldbank.org/v2"
WDI_SOURCE_ID = 2
PER_PAGE = 20000


# helpers
def fetch_real_country_iso3(session: requests.Session, refresh: bool = False) -> set[str]:
    """
    Fetch a whitelist of REAL countries (exclude aggregates like World, regions, income groups).
    Caches to registry/wb_countries_real.csv for repeatable runs.

    World Bank convention: aggregates typically have region.id == "NA".
    """
    if COUNTRY_CACHE.exists() and not refresh:
        df = pd.read_csv(COUNTRY_CACHE)
        if "iso3" in df.columns and df["iso3"].notna().any():
            codes = set(df["iso3"].dropna().astype(str).unique())
            print(f"Loaded cached countries: {COUNTRY_CACHE} (n={len(codes)})")
            return codes
        else:
            print("Country cache empty or invalid; rebuilding...")

    url = f"{API_BASE}/country"
    params = {"format": "json", "per_page": 500, "page": 1}
    r = session.get(url, params=params, timeout=60)
    r.raise_for_status()
    j = r.json()

    if not isinstance(j, list) or len(j) < 2:
        raise ValueError(f"Unexpected country response structure: {type(j)}")

    meta = j[0] or {}
    pages = int(meta.get("pages", 1))

    rows: list[tuple[str, str, str]] = []
    for page in range(1, pages + 1):
        params["page"] = page
        rp = session.get(url, params=params, timeout=60)
        rp.raise_for_status()
        jp = rp.json()

        if not isinstance(jp, list) or len(jp) < 2 or jp[1] is None:
            continue

        for item in jp[1]:
            iso3 = item.get("id") or item.get("iso3Code")  # WB API uses id for ISO3; iso3Code is fallback
            name = item.get("name")

            region = item.get("region") or {}
            region_id = region.get("id") if isinstance(region, dict) else None

            # Filter out aggregates: region.id == "NA"
            if not iso3 or region_id == "NA":
                continue

            # Keep a few helpful fields for auditability
            income = item.get("incomeLevel") or {}
            income_name = income.get("value") if isinstance(income, dict) else None

            rows.append((iso3, name, income_name))

        time.sleep(0.05)  # polite

    df = pd.DataFrame(rows, columns=["iso3", "country_name", "income_group"]).drop_duplicates()
    df.to_csv(COUNTRY_CACHE, index=False)
    print(f"Cached real countries: {COUNTRY_CACHE} (n={len(df)})")

    return set(df["iso3"].dropna().astype(str).unique())


def fetch_indicator_long(
    session: requests.Session,
    ind_code: str,
    valid_iso3: set[str],
) -> pd.DataFrame:
    """
    Pull one WDI indicator for all REAL countries, all years (paginated).
    Returns long df: iso3, year, indicator_code, value
    """
    url = f"{API_BASE}/country/ALL/indicator/{ind_code}"
    params = {
        "format": "json",
        "per_page": PER_PAGE,
        "page": 1,
        "source": WDI_SOURCE_ID,  # enforce WDI
    }

    r = session.get(url, params=params, timeout=60)
    r.raise_for_status()
    j = r.json()

    # Handle invalid / empty series
    if not isinstance(j, list) or len(j) < 2 or j[1] is None:
        return pd.DataFrame(columns=["iso3", "year", "indicator_code", "value"])

    meta = j[0] or {}
    pages = int(meta.get("pages", 1))

    rows: list[tuple[str, int, str, float | None]] = []

    def consume(page_json):
        if not isinstance(page_json, list) or len(page_json) < 2 or page_json[1] is None:
            return
        for item in page_json[1]:
            iso3 = item.get("countryiso3code")
            year = item.get("date")
            val = item.get("value")

            if not iso3 or not year:
                continue
            if iso3 not in valid_iso3:  # removes WLD/HIC/ECS/etc.
                continue

            try:
                y = int(year)
            except ValueError:
                continue

            rows.append((iso3, y, ind_code, val))

    # page 1
    consume(j)

    # remaining pages
    for page in range(2, pages + 1):
        params["page"] = page
        rp = session.get(url, params=params, timeout=60)
        rp.raise_for_status()
        consume(rp.json())
        time.sleep(0.05)  # polite

    df = pd.DataFrame(rows, columns=["iso3", "year", "indicator_code", "value"])
    return df


def load_indicator_codes(path: Path) -> list[str]:
    if not path.exists():
        raise FileNotFoundError(f"Indicator registry not found: {path}")

    ind = pd.read_csv(path)
    if "indicator_code" not in ind.columns:
        raise ValueError(f"{path} must contain a column named 'indicator_code'.")

    codes = (
        ind["indicator_code"]
        .dropna()
        .astype(str)
        .str.strip()
        .unique()
        .tolist()
    )
    return codes


# main
def main():
    session = requests.Session()

    codes = load_indicator_codes(IND_PATH)
    print(f"Loaded {len(codes)} indicator codes from {IND_PATH}")

    valid_iso3 = fetch_real_country_iso3(session, refresh=False)
    print(f"Valid real-country ISO3 count: {len(valid_iso3)}")

    all_parts: list[pd.DataFrame] = []
    failures: list[tuple[str, str]] = []

    for i, code in enumerate(codes, start=1):
        try:
            df = fetch_indicator_long(session, code, valid_iso3)
            all_parts.append(df)
            print(f"[{i}/{len(codes)}] OK   {code:<20} rows={len(df)}")
        except Exception as e:
            failures.append((code, str(e)))
            print(f"[{i}/{len(codes)}] FAIL {code:<20} err={e}")

        time.sleep(0.15)  # extra politeness between indicators

    if not all_parts:
        raise RuntimeError("No data downloaded (all indicators failed or returned empty).")

    out = pd.concat(all_parts, ignore_index=True)

    # Clean + enforce numeric
    out = out.dropna(subset=["iso3", "year"])
    out["value"] = pd.to_numeric(out["value"], errors="coerce")

    out.to_parquet(OUT_PATH, index=False)
    print(
        f"\nSaved: {OUT_PATH}\n"
        f"  rows={len(out):,}\n"
        f"  indicators={out['indicator_code'].nunique()}\n"
        f"  countries={out['iso3'].nunique()}\n"
        f"  years=[{out['year'].min()}..{out['year'].max()}]"
    )

    if failures:
        fail_df = pd.DataFrame(failures, columns=["indicator_code", "error"])
        fail_df.to_csv(FAIL_PATH, index=False)
        print(f"\nSome indicators failed. Saved: {FAIL_PATH} (n={len(fail_df)})")


if __name__ == "__main__":
    main()
