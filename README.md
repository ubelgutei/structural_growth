<h1 align="center">
Structural Growth of EM Nations
</h1>

<h3 align="center">
v1.
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
•
<a href="#report">Report</a>
</strong>
</p>

---

## Overview

This repository contains an exploratory research project that applies Ruchir Sharma’s Breakout Nations framework to countries in the MSCI Emerging Markets Index.

The project combines:
- **Python** for data collection and cleaning  
- **R** for normalization, scoring, visualization  

---

## Project status

> Version 1: I am planning to extend it in future iterations by incorporating equity market analysis
(e.g. valuation measures such as P/E ratios).
> 
> Methodological choices are intentionally simple, and results should be interpreted as
> illustrative rather than definitive.
>
> Feedback, critique, and suggestions are very welcome.  
> I hope to connect with others interested in emerging markets.

---

## Data & pipeline

The workflow follows a two-stage structure:

1. **Python**
   - Pull macroeconomic indicators 
   - Harmonize country identifiers (ISO3)
   - Reshape data into a country–year panel

2. **R**
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

These choices are **simplifying assumptions** and are not claimed to be optimal.

---

## Results

The results provide descriptive rankings rather than investment recommendations.
They highlight how countries commonly grouped together as “EM” can differ substantially
in their structural profiles.

---

## Report

The full write-up for this Version 1 project is available here:

📄 **[View exploratory report (PDF)](report.pdf)**

> The report documents the methodology, assumptions, and country rankings
> produced in this initial implementation.

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
