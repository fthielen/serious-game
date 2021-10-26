library("tidyverse")
options(scipen = 999,
        digits = 6)

df_res <- read_sheet(ss = g_sheet, sheet = "responses") %>% 
  filter(!is.na(wg)) %>% 
  replace(is.na(.), 0) %>% 
  pivot_longer(cols = starts_with("r"),
               names_prefix = "r*",
               names_to = "round", values_to = "val") %>% 
  mutate(type = str_sub(round, 2, 3),
         round = str_sub(round, 1, 1)) %>% 
  pivot_wider(names_from = type, values_from = val) %>% 
  mutate(round = as.numeric(round))

df_set <- read_sheet(ss = g_sheet, sheet = "settings")


# Point functions ---------------------------------------------------------

pt_fun_lm <- function(val_lo, val_hi, pts_lo, pts_phi, val_new){
  
  x <- c(val_lo, val_hi)
  y <- c(pts_lo, pts_phi)
  
  predict(lm(y ~ x), data.frame(x = val_new))[[1]]
}


pt_fun_log <- function(val, pts, val_new){
  
  round(predict(lm(pts ~ log(val)), data.frame(val = val_new))[[1]], 0)
}


# Calculations ------------------------------------------------------------


res <- df_res %>% 
  left_join(., df_set, by = "round") %>% 
  mutate(n_pat_tx = n1 + n2  + n3,
         n_pat_notx =  n_pats - n_pat_tx,
         budget_impact = n1 * p1 + n2 * p2 + n3 * p3,
         gov_balance = gov_max_budget - budget_impact,
         qalys_gained = n_pat_tx * qaly_yr,
         crowd_out = (gov_max_budget - budget_impact)/wtp,
         crowd_out = ifelse(crowd_out > 0, 0, crowd_out),
         qaly_balance = qalys_gained + crowd_out,
         qaly_max_loose = -(list_price * n_pats - gov_max_budget) / wtp,
         qaly_max_gain = n_pats * qaly_yr) %>% 
  rowwise() %>% 
  mutate(pts_qaly_gov = pt_fun_lm(val_lo = qaly_max_loose,
                                  val_hi = qaly_max_gain,
                                  pts_lo = -10,
                                  pts_phi = 10,
                                  val_new = qaly_balance),
         pts_pop_gov = pt_fun_lm(val_lo = 0,
                                 val_hi = n_pats,
                                 pts_lo = 0,
                                 pts_phi = 10,
                                 val_new = n_pat_tx),
         pts_man_sales = pt_fun_lm(val_lo = n_pats * wtp,
                                   val_hi = n_pats * list_price,
                                   pts_lo = 0,
                                   pts_phi = 10,
                                   val_new = budget_impact),
         pts_man_expected = pt_fun_log(val = c(n_pats * wtp,
                                               n_pats * list_price * sales_expect,
                                               n_pats * list_price),
                                       pts = c(0, 10, 12),
                                       val_new = budget_impact
                                       )) %>% 
  ungroup() %>% 
  mutate(gov_total = round(
    pts_qaly_gov * 0.6 + pts_pop_gov * 0.4, 1),
    man_total = round(pts_man_sales * 0.6 + pts_man_expected * 0.4, 1),
    gov_total = case_when(gov_total < 0 ~ 0,
                          gov_total > 10 ~ 10),
    man_total = case_when(man_total < 0 ~ 0,
                          man_total > 10 ~ 10)) %>%
  data.frame()

res



# Analysis ----------------------------------------------------------------


dat_plot <- res %>% 
  pivot_longer(c(gov_total, man_total),
               names_to = "Institution",
               values_to = "Points") %>% 
  mutate(Institution = ifelse(Institution == "gov_total",
                              "Government",
                              "Pharma"))

# Overall
ggplot(data = dat_plot, aes(x = Points, y = Institution)) +
  geom_boxplot() +
  theme_bw() +
  ggtitle("Overall distribution of points")

# Per tutor group
ggplot(data = dat_plot, aes(x = Points, y = Institution)) +
  geom_boxplot() +
  theme_bw() +
  facet_wrap(~ wg) +
  ggtitle("Overall distribution of points per tutor group")

# Per subgroup
ggplot(data = dat_plot, aes(x = Points, y = Institution)) +
  geom_boxplot() +
  theme_bw() +
  facet_wrap(~ gr) +
  ggtitle("Overall distribution of points by subgroup")

# Per case
ggplot(data = dat_plot, aes(x = Points, y = Institution)) +
  geom_boxplot() +
  theme_bw() +
  facet_grid(round ~ gr) +
  ggtitle("Overall distribution of points by case")

res %>% 
  arrange(gr) %>% 
  select(gr, gov_total, man_total)

# ROUDN toevoegen

# Which group did overspend the government budget?
res %>% 
  filter(gov_balance < 0) %>% 
  group_by(gr) %>% 
  summarise(n = n()) 

# Not treated
res %>% 
  filter(n_pat_notx > 0) %>% 
  select(gr, round, n_pat_notx)

# Crowding out
res %>% 
  filter(crowd_out < 0) %>% 
  select(gr, crowd_out)


# Average price
res %>% 
  mutate(ppp = budget_impact / n_pat_tx) %>% 
  group_by(gr) %>% 
  summarise(mean = mean(ppp, na.rm = T),
            min = min(ppp, na.rm = T),
            max = max(ppp, na.rm = T))

res %>% 
  filter(round == 1) %>% 
  mutate(ppp = budget_impact / n_pat_tx) %>% 
  group_by(gr) %>% 
  summarise(mean = mean(ppp, na.rm = T),
            min = min(ppp, na.rm = T),
            max = max(ppp, na.rm = T))

dat_cohort %>% 
  filter(round == 2) %>% 
  mutate(ppp = `Budget.impact./.sales` / Patients.treated) %>% 
  group_by(Group) %>% 
  summarise(mean = mean(ppp),
            min = min(ppp),
            max = max(ppp))



