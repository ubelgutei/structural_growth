library(dplyr)

# ---- Pillar scoring helper ----
# Purpose:
# Aggregate indicator-level standardized scores (the *_z columns produced by normalize_indicators())
# into a smaller set of pillar scores (e.g., Demographics_score, Fiscal_score, ...).
#
# Inputs:
# - df: data frame containing normalized indicator columns ending in "_z"
# - pillar_map: named list where each name is a pillar (e.g., "Fiscal") and each value is a character
#   vector of the *_z columns that belong to that pillar.
#
# Output:
# - Returns df with one new column per pillar named "<PillarName>_score"
#
# Method:
# - Unweighted average (row-wise mean) of the pillar's component z-scores.
# - Missing component indicators are ignored via na.rm = TRUE.
# - If all components are missing for a row, rowMeans() returns NaN; we convert this to NA_real_.
#
# Design note:
# - This is intentionally simple and transparent (equal weights).
# - If you later want differential weights (e.g., based on data quality, economic importance, PCA),
#   this is the function to extend.

compute_pillar_scores <- function(df, pillar_map) {

  df_out <- df

  for (pillar_name in names(pillar_map)) {

    # Candidate indicator z-score columns for this pillar
    z_cols <- pillar_map[[pillar_name]]

    # Keep only columns that exist in df (protects against missing indicators / version mismatches)
    z_cols <- intersect(z_cols, names(df_out))

    # Row-wise average across the pillar's indicator z-scores
    df_out[[paste0(pillar_name, "_score")]] <- {
      m <- rowMeans(df_out[, z_cols, drop = FALSE], na.rm = TRUE)
      ifelse(is.nan(m), NA_real_, m)
    }
  }

  df_out
}
