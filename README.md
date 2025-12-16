<h1 align="center">
Structural Growth of EM Nations
</h1>

<h3 align="center">
ver.1
</h3>

<p align="center">
<strong>
<a href="#overview">Overview</a>
•
<a href="#project-status">Project status</a>
•
<a href="#methodology">Methodology</a>
•
<a href="#results">Results</a>
•
<a href="#project-structure">Structure</a>
</strong>
</p>

---

## Overview

This repository contains an exploratory research project that focuses on applying
Ruchir Sharma’s *“Breakout Nations”* framework on the countries listed in the MSCI Emerging Market Index.

The goal is not to produce definitive rankings, but to learn how to build a reproducible 
pipeline and to explore how structural economic indicators differ
across emerging-market countries.

The project combines:
- Python for data collection and cleaning  
- R for normalization, scoring, visualization, and reporting  

---

## Project status

> **Version 1.**  
> This repository represents my first attempt at building a research
> workflow aside from my typical university assignments.
>
> Methodological choices are intentionally simple, and results should be interpreted as
> illustrative rather than definitive.
>
> Feedback, critique, and suggestions are very welcome. I hope I find people as interested
> in the EM markets as much as I do and looking forward to keep exploring this field.

---

## Data & pipeline

The workflow follows a two-stage structure:

1. **Python – data preparation**
   - Pull macroeconomic indicators (e.g. World Bank WDI, IMF WEO)
   - Harmonize country identifiers (ISO3)
   - Reshape data into a country–year panel

2. **R – scoring & reporting**
   - Winsorization of indicators
   - Sign adjustment for “risk” variables
   - Z-score normalization
   - Pillar-level aggregation
   - Composite scoring and visualization

Raw and intermediate datasets are intentionally excluded from version control.

---

## Methodology

### Structural pillars

Indicators are grouped into seven broad structural pillars:

1. Demographics & labor-force dynamics  
2. Fiscal sustainability & debt structure  
3. Investment
4. Foreign direct investment (FDI)  
5. Trade & external openness  
6. Commodity dependence  
7. Income level / development stage  

### Normalization & aggregation

- Indicators are winsorized at the 1st / 99th percentiles.
- Variables where “higher is worse” are sign-flipped for consistency.
- Z-scores are computed on a pooled panel.
- Pillar scores are simple averages of available indicators.
- The composite score is an average across available pillars.

These choices are simplifying assumptions and are not claimed to be optimal.

---

## Results

The results provide descriptive rankings rather than investment recommendations.
They highlight how countries commonly grouped together as “EM” can differ substantially
in their structural profiles.

Selected country discussions and a full ranking table are included in `report.pdf`.

---

## Project structure

```text
structural_growth/
  py/                  # Python scripts (data pull & cleaning)
  research_r/          # R analysis, scoring, and reporting
  registry/            # Indicator lists, metadata, ISO3 mappings
  docs/                
  data_raw/            # Raw data (not tracked)
  data_clean/          # Cleaned intermediate data (not tracked)
  data_final/          # Final analysis datasets (not tracked)
  outputs/             # Generated figures & tables (not tracked)
  renv.lock            # Pinned R dependencies
  .Rprofile
