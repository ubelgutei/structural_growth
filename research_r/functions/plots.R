library(tidyverse)
library(gt)
library(scales)

# ---- Tiering logic (rule-based, Sharma-style) ----
# Tier 1 (High-Score Leaders):
#   - Overall score in the top quantile (breakout_q)
#   - Broad-based strength: at least min_pos pillars > 0
#
# Tier 4 (High-Risk Profiles):
#   - Demographics < 0 AND Fiscal < 0 AND overall score in bottom quantile (fragile_q)
#
# Tier 3 (Commodity-Exposed Profiles): 
#   - Because commodity dependence indicators are in bad_if_high and get sign-flipped,
#     Commodities_score is oriented so HIGH = GOOD (LOW commodity dependence).
#   - Therefore "commodity-exposed" must be LOW Commodities_score (bottom tail), not high.
#
# Tier 2 (Mixed-Score Middle): everything else.

make_tierlist <- function(df,
                          year,
                          exclude_iso3 = character(),
                          score_col = "Breakout_Score_penalized",
                          pillar_cols = c("Demographics_score","Fiscal_score","Investment_score","FDI_score",
                                          "Trade_score","Commodities_score","Income_score"),
                          min_pos = 5,
                          breakout_q = 0.75,
                          fragile_q  = 0.25,
                          commodity_q = 0.25) {  # NOTE: now interpreted as LOW-tail threshold

  df_year <- df %>%
    filter(year == !!year, !iso3 %in% exclude_iso3) %>%
    filter(Pillars_Available == 7) %>%
    mutate(score = .data[[score_col]])

  if (nrow(df_year) == 0) stop("No rows after filtering. Check year/exclusions/Pillars_Available.")

  # thresholds computed within that year cross-section
  q_break <- as.numeric(quantile(df_year$score, breakout_q, na.rm = TRUE))
  q_frag  <- as.numeric(quantile(df_year$score, fragile_q,  na.rm = TRUE))

  # FIX: commodity exposure = weak commodities pillar (high dependence) => LOW Commodities_score
  q_comm_low <- as.numeric(quantile(df_year$Commodities_score, commodity_q, na.rm = TRUE))

  tier_1 <- "Tier 1 — High-Score Leaders"
  tier_2 <- "Tier 2 — Mixed-Score Middle"
  tier_3 <- "Tier 3 — Commodity-Exposed Profiles"
  tier_4 <- "Tier 4 — High-Risk Profiles"

  out <- df_year %>%
    mutate(
      Rank  = dense_rank(desc(score)),
      n_pos = rowSums(across(all_of(pillar_cols), ~ .x > 0), na.rm = TRUE),

      is_high_risk =
        (Demographics_score < 0) &
        (Fiscal_score < 0) &
        (score <= q_frag),

      is_leader =
        (score >= q_break) &
        (n_pos >= min_pos),

      is_commodity_exposed =
        (Commodities_score <= q_comm_low) &
        (!is_leader),

      Tier = case_when(
        is_high_risk         ~ tier_4,
        is_leader            ~ tier_1,
        is_commodity_exposed ~ tier_3,
        TRUE                 ~ tier_2
      ),

      Tier = factor(Tier, levels = c(tier_1, tier_2, tier_3, tier_4))
    ) %>%
    # IMPORTANT CHANGE: remove tier-based ordering; keep it simple & consistent by rank
    arrange(Rank) %>%
    select(year, Rank, iso3, score, Tier, n_pos, all_of(pillar_cols))

  out
}

# ---- Table: gt tier list (NO grouping / NO tier ordering) ----
# We keep Tier as a normal column and sort by Rank (already done in make_tierlist()).
gt_tierlist <- function(tier_df, title = NULL) {
  tier_df %>%
    mutate(
      score = round(score, 3),
      across(ends_with("_score"), ~round(.x, 2))
    ) %>%
    gt() %>%
    tab_header(title = md(title %||% "**Tier list (headline year)**")) %>%
    cols_label(
      iso3  = "ISO3",
      score = "Breakout Score",
      n_pos = "# Pillars > 0"
    ) %>%
    fmt_number(columns = c(score), decimals = 3)
}
