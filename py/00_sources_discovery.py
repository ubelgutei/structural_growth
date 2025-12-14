from pathlib import Path  # lightweight path helper so script works cross-platform
import requests  # reach World Bank API
import pandas as pd  # reshape JSON payloads into tabular form

# paths
ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
DOCS.mkdir(exist_ok=True)  # create storage for generated catalog

# download WB sources list 
URL = "https://api.worldbank.org/v2/sources?format=json&per_page=20000"
r = requests.get(URL, timeout=60)  # pull the full source registry
r.raise_for_status()  # fail loudly on HTTP issues
j = r.json()

sources = pd.DataFrame(j[1]).rename(columns={"id": "source_id"})  # flatten list of dicts
sources = sources[["source_id", "code", "name"]].sort_values("name")  # keep only useful columns

out_path = DOCS / "worldbank_sources.csv"
sources.to_csv(out_path, index=False)  # canonical CSV snapshot
print(f"Saved: {out_path}")

# print the ones we care about 
def show(pattern: str, title: str):
    m = sources[sources["name"].str.contains(pattern, case=False, na=False)]  # quick substring filter
    print(f"\n{title}:")
    if len(m) == 0:
        print("  (no matches)")
    else:
        print(m.to_string(index=False))

show("World Development Indicators", "WDI match")
show("Worldwide Governance Indicators", "WGI match")
show("Findex", "Findex matches")
