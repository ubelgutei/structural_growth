# ---- Normalization helpers ----
# Purpose:
# Convert heterogeneous macro indicators (different units/scales) into comparable inputs for scoring.
# Output convention:
# For each indicator in `indicator_cols`, we create a standardized column named "<indicator>_z"
# where higher values always mean "better" after applying sign rules (bad_if_high).

library(dplyr)

# ---- winsorize() ----
# Robust outlier handling: cap the lower/upper tails of a numeric vector.
# - With p = 0.01, values below the 1st percentile and above the 99th percentile are set to the
#   respective cutoff values. This reduces the influence of crisis spikes, one-off data errors,
#   and heavy-tailed distributions before standardization.
winsorize <- function(x, p = 0.01) {
  q <- quantile(x, probs = c(p, 1 - p), na.rm = TRUE)
  x[x < q[1]] <- q[1]
  x[x > q[2]] <- q[2]
  x
}

# ---- normalize_indicators() ----
# Steps (per indicator):
# 1) Winsorize the raw series (tail capping) using winsor_p
# 2) Flip sign for indicators where "higher is worse" (bad_if_high), so all series have a consistent
#    direction: higher => better
# 3) Compute pooled z-scores across the full sample (all countries and years):
#    z = (x - mean(x)) / sd(x)
#
# Design note:
# - "Pooled" means the mean/sd is computed across the entire panel, not within each year.
#   This is appropriate if we want a single global benchmark for the full sample.
#   (If the goal is purely cross-sectional ranking within each year, a "within-year z-score"
#   alternative may be preferable for strongly trending variables like GDP per capita.)
#
# Edge cases:
# - If an indicator has sd = 0 (constant series) or sd is NA, we return NA z-scores for that indicator.
normalize_indicators <- function(df,
                                 indicator_cols,
                                 bad_if_high = character(),
                                 winsor_p = 0.01) {

  df_norm <- df

  for (col in indicator_cols) {

    x <- df_norm[[col]]

    # 1) Winsorize (robustify against extreme tails)
    x <- winsorize(x, p = winsor_p)

    # 2) Directional alignment: flip sign if higher values indicate worse outcomes
    #    After this step, "higher" should always correspond to "better" for scoring.
    if (col %in% bad_if_high) {
      x <- -x
    }

    # 3) Standardize: pooled z-score across all countries & years
    mu   <- mean(x, na.rm = TRUE)
    sd_x <- sd(x, na.rm = TRUE)

    if (sd_x == 0 || is.na(sd_x)) {
      # Constant (or invalid) series -> cannot standardize meaningfully
      df_norm[[paste0(col, "_z")]] <- NA_real_
    } else {
      df_norm[[paste0(col, "_z")]] <- (x - mu) / sd_x
    }
  }

  df_norm
}
