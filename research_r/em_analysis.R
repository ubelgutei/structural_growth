# Structural scoring of EM
# Pipeline:
# 1) Load panel (wide)
# 2) Engineer demographic momentum features (5Y changes)
# 3) Normalize indicators: winsorize + sign-flip (bad_if_high) + pooled z-scores
# 4) Aggregate z-scores into 7 pillar scores
# 5) Composite Breakout Scores (missingness-safe variants)
# 6) Export: rankings tables, tier table (CSV + HTML), plots (heatmap + matrix)

# Libraries 
library(tidyverse)
library(arrow)
library(stringr)
library(scales)
library(gt)
library(ggrepel)

utils::globalVariables(".data")

setwd("research_r")

# Source helper functions
source("functions/normalization.R")  # winsorize(), normalize_indicators()
source("functions/scoring.R")        # compute_pillar_scores()

source("functions/plots.R")

# Parameters
year_min <- 2010
year_max <- 2024

winsor_p <- 0.01

# Optional z-score clipping (PLOTTING ONLY)
clip_z <- FALSE
z_cap  <- 3

update_year  <- 2024
exclude_iso3 <- c("TWN")

# Output folders
dir.create("../outputs/tables",  showWarnings = FALSE, recursive = TRUE)
dir.create("../outputs/figures", showWarnings = FALSE, recursive = TRUE)

# 1) Load + feature engineering

panel <- read_parquet("../data_clean/panel_em_wide_baseline_v1.parquet") %>%
  filter(year >= year_min, year <= year_max)

# Demographic momentum features (5Y lags => NA for early years)
panel <- panel %>%
  group_by(iso3) %>%
  arrange(year) %>%
  mutate(
    WA_CAGR_5Y       = 100 * ((SP.POP.1564.TO / lag(SP.POP.1564.TO, 5))^(1/5) - 1),
    WA_SHARE_CHG_5Y  = SP.POP.1564.TO.ZS - lag(SP.POP.1564.TO.ZS, 5),
    URB_CHG_5Y       = SP.URB.TOTL.IN.ZS - lag(SP.URB.TOTL.IN.ZS, 5)
  ) %>%
  ungroup()

# 2) Indicator registry + directionality

raw_indicators <- c(
  # Demographics
  "SP.POP.1564.TO.ZS", "WA_CAGR_5Y", "WA_SHARE_CHG_5Y", "URB_CHG_5Y", "SL.TLF.CACT.FE.ZS",

  # FDI
  "BX.KLT.DINV.WD.GD.ZS",

  # Investment / industrial depth
  "NV.IND.MANF.ZS", "NE.GDI.FTOT.ZS",

  # Trade / demand structure
  "NE.TRD.GNFS.ZS", "NE.CON.PRVT.ZS",

  # Commodities / resource reliance
  "TX.VAL.FUEL.ZS.UN", "NY.GDP.TOTL.RT.ZS",

  # Fiscal / buffers / macro stability
  "FI.RES.TOTL.MO", "PCPIPCH", "GGXWDG_NGDP", "BCA_NGDPD", "GGXONLB_NGDP",

  # Income level anchor
  "NY.GDP.PCAP.KD"
)

indicator_cols <- intersect(raw_indicators, names(panel))

# HIGH is BAD -> will be sign-flipped in normalize_indicators()
bad_if_high <- c(
  "PCPIPCH",
  "GGXWDG_NGDP",
  "TX.VAL.FUEL.ZS.UN",
  "NY.GDP.TOTL.RT.ZS"
)

# 3) Normalize indicators (winsorize + sign-flip + pooled z-score)

panel_norm <- normalize_indicators(
  df = panel,
  indicator_cols = indicator_cols,
  bad_if_high = bad_if_high,
  winsor_p = winsor_p
)

# Plot-only clipped copy (optional)
panel_norm_plot <- panel_norm
if (isTRUE(clip_z)) {
  z_cols <- names(panel_norm_plot)[str_detect(names(panel_norm_plot), "_z$")]
  panel_norm_plot <- panel_norm_plot %>%
    mutate(across(all_of(z_cols), ~pmax(pmin(.x, z_cap), -z_cap)))
}

# 4) Pillars + scoring

pillar_map <- list(
  Demographics = c("WA_CAGR_5Y_z","WA_SHARE_CHG_5Y_z","URB_CHG_5Y_z",
                   "SL.TLF.CACT.FE.ZS_z","SP.POP.1564.TO.ZS_z"),
  Fiscal = c("PCPIPCH_z","GGXWDG_NGDP_z","GGXONLB_NGDP_z","BCA_NGDPD_z","FI.RES.TOTL.MO_z"),
  Investment = c("NE.GDI.FTOT.ZS_z","NV.IND.MANF.ZS_z"),
  FDI = c("BX.KLT.DINV.WD.GD.ZS_z"),
  Trade = c("NE.TRD.GNFS.ZS_z","NE.CON.PRVT.ZS_z"),
  Commodities = c("TX.VAL.FUEL.ZS.UN_z","NY.GDP.TOTL.RT.ZS_z"),
  Income = c("NY.GDP.PCAP.KD_z")
)

pillar_report_cols <- c(
  "Demographics_score","Fiscal_score","Investment_score","FDI_score",
  "Trade_score","Commodities_score","Income_score"
)

panel_scored      <- compute_pillar_scores(panel_norm,      pillar_map)
panel_scored_plot <- compute_pillar_scores(panel_norm_plot, pillar_map)

pillar_cols <- paste0(names(pillar_map), "_score")
n_pillars   <- length(pillar_cols)

# 5) Composite scores (missingness-safe)

panel_final <- panel_scored %>%
  mutate(
    Pillars_Available = rowSums(!is.na(pick(all_of(pillar_cols)))),

    Breakout_Score_naive = rowMeans(pick(all_of(pillar_cols)), na.rm = TRUE),
    Breakout_Score_naive = if_else(is.nan(Breakout_Score_naive), NA_real_, Breakout_Score_naive),

    Breakout_Score_penalized = Breakout_Score_naive * (Pillars_Available / n_pillars),

    Breakout_Score_neutral =
      rowSums(
        pick(all_of(pillar_cols)) %>%
          mutate(across(everything(), ~replace_na(.x, 0)))
      ) / n_pillars
  )

# Diagnostics
panel_final %>%
  summarise(
    mean_naive = mean(Breakout_Score_naive, na.rm = TRUE),
    sd_naive   = sd(Breakout_Score_naive, na.rm = TRUE),
    mean_pen   = mean(Breakout_Score_penalized, na.rm = TRUE),
    sd_pen     = sd(Breakout_Score_penalized, na.rm = TRUE)
  ) %>%
  print()

# 6) Pick headline year (max full coverage)

coverage_by_year <- panel_final %>%
  filter(!iso3 %in% exclude_iso3) %>%
  group_by(year) %>%
  summarise(
    n_countries = n_distinct(iso3),
    n_full7     = sum(Pillars_Available == 7, na.rm = TRUE),
    n_ge6       = sum(Pillars_Available >= 6, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(desc(n_full7), desc(n_ge6), desc(year))

print(coverage_by_year, n = 50)

headline_year <- max(coverage_by_year$year[coverage_by_year$n_full7 == max(coverage_by_year$n_full7)])
cat("HEADLINE_YEAR =", headline_year, "\n")

# 7) Ranking tables (headline + update) + missing pillars

add_ranks <- function(df, score_col = "Breakout_Score_penalized") {
  df %>%
    mutate(
      Rank_all = dense_rank(desc(.data[[score_col]])),
      complete = Pillars_Available == 7
    ) %>%
    group_by(complete) %>%
    mutate(
      Rank_complete = if_else(complete, dense_rank(desc(.data[[score_col]])), NA_integer_)
    ) %>%
    ungroup() %>%
    select(year, iso3, Pillars_Available, Rank_all, Rank_complete, all_of(score_col), all_of(pillar_report_cols))
}

panel_headline <- panel_final %>%
  filter(year == headline_year, !iso3 %in% exclude_iso3)

panel_update <- panel_final %>%
  filter(year == update_year, !iso3 %in% exclude_iso3)

headline_table <- add_ranks(panel_headline) %>% arrange(Rank_all)
update_table   <- add_ranks(panel_update)   %>% arrange(Rank_all)

missing_pillars_update <- panel_update %>%
  filter(Pillars_Available < 7) %>%
  select(iso3, all_of(pillar_report_cols)) %>%
  pivot_longer(-iso3, names_to = "pillar", values_to = "val") %>%
  filter(is.na(val)) %>%
  arrange(iso3, pillar)

write_csv(headline_table, sprintf("../outputs/tables/exhibit1_headline_rankings_%s.csv", headline_year))
write_csv(update_table,   sprintf("../outputs/tables/exhibit_update_rankings_%s.csv", update_year))
write_csv(missing_pillars_update, sprintf("../outputs/tables/exhibit_missing_pillars_%s.csv", update_year))

# 8) Tier table (CSV + HTML)
# IMPORTANT: make_tierlist() in functions/plots.R must use commodity logic:
# commodity-exposed = LOW Commodities_score tail (because commodities indicators were sign-flipped).

tier_headline <- make_tierlist(
  df = panel_final,
  year = headline_year,
  exclude_iso3 = exclude_iso3,
  score_col = "Breakout_Score_penalized"
) %>%
  arrange(Rank)

write_csv(tier_headline, sprintf("../outputs/tables/exhibit_tiers_%s.csv", headline_year))

tier_gt <- gt_tierlist(
  tier_headline,
  title = sprintf("Tier list (%s, headline year)", headline_year)
)
gtsave(tier_gt, sprintf("../outputs/tables/exhibit_tiers_%s.html", headline_year))

# 9) Plot 1 — “Quality of Growth” Matrix

quality_df <- tier_headline %>%
  transmute(
    iso3,
    Tier,
    score,
    Fiscal = Fiscal_score,
    Investment = Investment_score
  ) %>%
  mutate(
    Tier_label = str_replace(Tier, "^Tier\\s*\\d+\\s*—\\s*", ""),
    Tier_label = factor(
      Tier_label,
      levels = c("High-Score Leaders","Mixed-Score Middle","Commodity-Exposed Profiles","High-Risk Profiles")
    )
  )

label_iso3 <- c("ARE","KOR","MYS","CHN","IDN","TUR","EGY","BRA","CZE","IND","MEX")

p_quality <- ggplot(quality_df, aes(x = Investment, y = Fiscal)) +
  geom_hline(yintercept = 0, linewidth = 0.4) +
  geom_vline(xintercept = 0, linewidth = 0.4) +
  geom_point(aes(color = Tier_label), size = 3, alpha = 0.85) +
  ggrepel::geom_text_repel(
    data = quality_df %>% filter(iso3 %in% label_iso3),
    aes(label = iso3),
    size = 3.5,
    max.overlaps = Inf
  ) +
  annotate("label", x = -Inf, y = -Inf, label = "(Low Inv, Bad Fiscal)",
           hjust = -0.05, vjust = -0.1, label.size = 0) +
  annotate("label", x =  Inf, y = -Inf, label = "(High Inv, Bad Fiscal)",
           hjust =  1.05, vjust = -0.1, label.size = 0) +
  annotate("label", x = -Inf, y =  Inf, label = "(Low Inv, Good Fiscal)",
           hjust = -0.05, vjust =  1.1, label.size = 0) +
  annotate("label", x =  Inf, y =  Inf, label = "(High Inv, Good Fiscal)",
           hjust =  1.05, vjust =  1.1, label.size = 0) +
  labs(
    title = sprintf('“Quality of Growth” Matrix (%s)', headline_year),
    x = "Investment / Industrial Strength",
    y = "Fiscal Sustainability Score",
    color = NULL
  ) +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom")

ggsave(
  sprintf("../outputs/figures/fig_quality_of_growth_matrix_%s.png", headline_year),
  p_quality,
  width = 10, height = 7, dpi = 300
)

# 10) Plot 2 — Headline heatmap

make_heat_df <- function(df, pillar_report_cols) {
  df %>%
    arrange(desc(Breakout_Score_penalized)) %>%
    mutate(iso3 = factor(iso3, levels = unique(iso3))) %>%
    select(iso3, all_of(pillar_report_cols)) %>%
    pivot_longer(-iso3, names_to = "pillar", values_to = "val") %>%
    mutate(
      pillar = str_replace(pillar, "_score$", ""),
      pillar = factor(pillar, levels = c("Demographics","Fiscal","Investment","FDI","Trade","Commodities","Income"))
    )
}

plot_heat_score <- function(heat_df, title, cap = 1.5) {
  ggplot(heat_df, aes(x = pillar, y = iso3, fill = val)) +
    geom_tile(color = "white", linewidth = 0.25) +
    scale_fill_gradient2(
      low = "#b2182b",
      mid = "#f7f7f7",
      high = "#1a9641",
      midpoint = 0,
      limits = c(-cap, cap),
      oob = squish,
      na.value = "grey85"
    ) +
    labs(title = title, x = NULL, y = NULL, fill = "Pillar score") +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))
}

panel_headline_plot <- panel_scored_plot %>%
  filter(year == headline_year, !iso3 %in% exclude_iso3) %>%
  left_join(
    panel_headline %>% select(iso3, year, Breakout_Score_penalized),
    by = c("iso3", "year")
  )

heat_headline <- make_heat_df(panel_headline_plot, pillar_report_cols)

p_heat_headline <- plot_heat_score(
  heat_headline,
  sprintf("Pillar heatmap (%s) — score", headline_year),
  cap = 1.5
)

ggsave(
  sprintf("../outputs/figures/fig_ex1_heatmap_headline_%s.png", headline_year),
  p_heat_headline,
  width = 9,
  height = 7,
  dpi = 300
)
