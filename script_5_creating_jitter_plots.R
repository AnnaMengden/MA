
############## SCRIPT 5 ################
### 28.08.2024 ---- by Anna Mengden ####
######### Jitter plots of ##############
### rel. traffic area values and #######
####### green space provision ##########



##### RESULTS 3

########### Verkehrsflächen relativ zur BEBAUTEN FLÄCHE #################
########### und GRÜNFLÄCHEN-VERSORHUNG ##################################


# traffic areas per planning area (PLR or LOR) = "spaces_per_lor_v3"
spaces_per_lor_v3 <- read.csv("C:/Dokumente/MASTER_GEO/Master Thesis/Results_pgAdmin/FINAL/spaces_per_lor_v3.csv")


library(dplyr)
library(ggplot2)
library(ggtext)
library(stringr)



###### Option 1 ######

### max_o_d_per_bebaut (maxmiale decision option pro bebaute Fläche) ###


## Um die PLRs je nach Dichte um ihren x-achsen Wert zu verteilen:

# Berechnung der Dichteverteilung (max_d_o_per_bebaut)
density_df <- density(spaces_per_lor_v3$max_d_o_per_bebaut, adjust = 1)
density_df <- data.frame(x = density_df$x, y = density_df$y)

get_density <- function(value, density_df) {
  approx(density_df$x, density_df$y, xout = value)$y
}

  # Jitter-Funktion basierend auf y-Werten anwenden
jitter_amount <- function(y, density_df) {
  density <- get_density(y, density_df)
  max_jitter <- 0.22  # Maximaler Jitter-Wert
  min_jitter <- 0.02  # Minimaler Jitter-Wert
  jitter_range <- min_jitter + (density / max(density_df$y) * (max_jitter - min_jitter))
  return(runif(1, -jitter_range, jitter_range))
}

  # Berechnung des Jitters für jede Zeile
spaces_per_lor_v3 <- spaces_per_lor_v3 %>%
  rowwise() %>%
  mutate(jitter_x = gruenver_numeric + jitter_amount(max_d_o_per_bebaut, density_df)) %>%
  ungroup()


# Plot erstellen (max. decision option per built-up area)

# minimalen und maximalen traffic area Werte um sie als Grenzwerte für y-achse zu nehmen
y_min <- min(spaces_per_lor_v3$mod_d_o_per_bebaut, na.rm = TRUE)
y_max <- max(spaces_per_lor_v3$max_d_o_per_bebaut, na.rm = TRUE)

# Plot erstellen (max_d_o_per_bebaut)
plot1g <- ggplot(spaces_per_lor_v3, aes(x = jitter_x, y = max_d_o_per_bebaut)) +
  geom_point(color = "#33CC33", alpha = 0.8) +
  labs(
    x = "Green Space Provision",
    y = "Total Traffic Area per Built-up Area",
    title = "Ratio of the total traffic area (<span style='color:black;'>of</span> <span style='color:#33CC33;'>conversion Option 1</span><span style='color:black;'>)</span> relative to the built-up area<br>and the green space provision of each planning area"
  ) +
  theme_minimal() +
  scale_x_continuous(breaks = c(1, 2, 3), labels = c("Good", "Medium", "Poor"), expand = c(0.1, 0)) +
  scale_y_continuous(limits = c(y_min, y_max)) +
  theme(
    panel.grid.major.x = element_blank(),  
    panel.grid.minor.x = element_blank(),
    axis.title.x = element_text(margin = margin(t = 10)),
    axis.title.y = element_text(margin = margin(r = 10)),
    plot.title = element_markdown() 
  )
 

### Um die PLRs mit den höchsten rel. Verkehrsflächenwerten beschriften zu können: 

# Grenzwert im 95. quantil bestimmen für jede grünversorgungskategorie
quantile_thresholds <- spaces_per_lor_v3 %>%
  group_by(gruenver_numeric) %>%
  summarise(quantile_95 = quantile(max_d_o_per_bebaut, 0.95, na.rm = TRUE))

# für jede grünversorgungskategorie sollen die grenzwerte eingebunden werden...
joined_data <- spaces_per_lor_v3 %>%
  inner_join(quantile_thresholds, by = "gruenver_numeric")

# ... um die plrs im 95. Quantil pro grünversorgungskat. festzulegen (top_values)
top_values <- joined_data %>%
  filter(max_d_o_per_bebaut > quantile_95)


# Rang der top_values bestimmen, um die Beschriftung manuell verschieben zu können
top_values <- top_values %>%
  group_by(gruenver_numeric) %>%
  arrange(desc(max_d_o_per_bebaut)) %>%
  mutate(
    rank = row_number()
  )

# checken ob es stimmt und um Werte für Tabelle zu erhalten
print(top_values %>% select(gruenver_numeric, plr_name, max_d_o_per_bebaut, rank))

# Beschriftung der PLRs mit grünversorgung 3 (poor) mit manueller Verschiebung
label_coords_3 <- top_values %>%
  filter(gruenver_numeric == 3) %>%
  mutate(
    label_nudge_x = case_when(
      rank == 1 ~ 0.28,
      rank == 2 ~ -0.19,
      rank == 3 ~ 0.22,
      rank == 4 ~ -0.22
    ),
    label_vjust = case_when(
      rank == 1 ~ -0.1,
      rank == 2 ~ 0.1,
      rank == 3 ~ 0.26,
      rank == 4 ~ 0.2
    ),
    label = plr_name
  )

# Beschriftung der PLRs mit grünversorgung 2 (medium)
label_coords_2 <- top_values %>%
  filter(gruenver_numeric == 2) %>%
  mutate(
    # bei den zwei langen PLRs Namen, Beschriftung bei Leerzeichen in zwei Zeilen aufteilen
    label = case_when(
      rank == 1 ~ plr_name,
      rank == 2 ~ ifelse(
        str_detect(plr_name, " "),
        paste(
          str_extract(plr_name, "^[^ ]+"),
          str_remove(plr_name, "^[^ ]+ "),
          sep = "\n"
        ),
        plr_name  # wenn kein Leerzeichen normal
      ),
      rank == 3 ~ plr_name
    ),
    label_nudge_x = case_when(
      rank == 1 ~ 0.29,
      rank == 2 ~ -0.17,
      rank == 3 ~ 0.2
    ),
    label_vjust = case_when(
      rank == 1 ~ -0.1,
      rank == 2 ~ 0.7,
      rank == 3 ~ -0.2
    )
  )

# Beschriftung der PLRs mit grünversorgung 1 (good)
label_coords_1 <- top_values %>%
  filter(gruenver_numeric == 1) %>%
  mutate(
    label_nudge_x = case_when(
      rank == 1 ~ 0.25,
      rank == 2 ~ -0.2
    ),
    label_vjust = case_when(
      rank == 1 ~ -0.2,
      rank == 2 ~ 0.2
    ),
    label = plr_name
  )

# Beschriftungs dfs der drei grün-kategorien in eine df 
label_coords <- bind_rows(label_coords_1, label_coords_2, label_coords_3)


# Plot1 mit Beschriftung der PLRs mit den höchsten verkehrsflächenwerten
plot1g + 
  geom_text(data = label_coords, aes(label = label), size = 3.5, 
            nudge_x = label_coords$label_nudge_x, vjust = label_coords$label_vjust, 
            color = "black") +  # Beschriftungen hinzufügen
  theme(
    panel.background = element_rect(fill = "whitesmoke"),  # Hintergrund der Grafik auf "whitesmoke" setzen
    panel.grid.major.y = element_line(color = "#d0d0d0")
  )




###### Option 2 ######

## mix_d_o_per_bebaut (mixed decision option per built-up area)##


density_df <- density(spaces_per_lor_v3$mix_d_o_per_bebaut, adjust = 1)
density_df <- data.frame(x = density_df$x, y = density_df$y)

get_density <- function(value, density_df) {
  approx(density_df$x, density_df$y, xout = value)$y
}

jitter_amount <- function(y, density_df) {
  density <- get_density(y, density_df)
  max_jitter <- 0.22
  min_jitter <- 0.02
  jitter_range <- min_jitter + (density / max(density_df$y) * (max_jitter - min_jitter))
  return(runif(1, -jitter_range, jitter_range))
}

spaces_per_lor_v3 <- spaces_per_lor_v3 %>%
  rowwise() %>%
  mutate(jitter_x = gruenver_numeric + jitter_amount(mix_d_o_per_bebaut, density_df)) %>%
  ungroup()

# Plot ersellen (mix decision option)
# mit der gleichen y-achse wie bei Option 1

plot2g <- ggplot(spaces_per_lor_v3, aes(x = jitter_x, y = mix_d_o_per_bebaut)) +
  geom_point(color = "#3333CC", alpha = 0.8) +
  labs(
    x = "Green Space Provision",
    y = "Total Traffic area per Built-up Area",
    title = "Ratio of the total traffic area (<span style='color:black;'>of</span> <span style='color:#3333CC;'>conversion Option 2</span><span style='color:black;'>)</span> relative to the built-up area<br>and the green space provision of each planning area"
  ) +
  theme_minimal() +
  scale_x_continuous(breaks = c(1, 2, 3), labels = c("Good", "Medium", "Poor"), expand = c(0.1, 0)) +
  scale_y_continuous(limits = c(y_min, y_max)) +
  theme(
    panel.grid.major.x = element_blank(),
    panel.grid.minor.x = element_blank(),
    axis.title.x = element_text(margin = margin(t = 10)),
    axis.title.y = element_text(margin = margin(r = 10)),
    plot.title = element_markdown()
  )

### Um die PLRs mit den höchsten rel. Verkehrsflächenwerten beschriften zu können: 

quantile_thresholds <- spaces_per_lor_v3 %>%
  group_by(gruenver_numeric) %>%
  summarise(quantile_95 = quantile(mix_d_o_per_bebaut, 0.95, na.rm = TRUE))

joined_data <- spaces_per_lor_v3 %>%
  inner_join(quantile_thresholds, by = "gruenver_numeric")

top_values <- joined_data %>%
  filter(mix_d_o_per_bebaut > quantile_95)

sorted_top_values <- top_values %>%
  arrange(gruenver_numeric, desc(mix_d_o_per_bebaut))

# überprüfen
print(sorted_top_values %>% select(gruenver_numeric, plr_name, mix_d_o_per_bebaut))

# plrs mit höchsten verkehrsflächenwerten mit rang für manuelle beschriftung
top_values <- top_values %>%
  group_by(gruenver_numeric) %>%
  arrange(desc(mix_d_o_per_bebaut)) %>%
  mutate(
    rank = row_number()
  )

# überprüfen
print(top_values %>% select(gruenver_numeric, plr_name, mix_d_o_per_bebaut, rank))

# Beschriftung plrs mit grünversorgung 3 (poor)
label_coords_3 <- top_values %>%
  filter(gruenver_numeric == 3) %>%
  mutate(
    label_nudge_x = case_when(
      rank == 1 ~ 0.28,
      rank == 2 ~ -0.22,
      rank == 3 ~ 0.19,
      rank == 4 ~ 0.24
    ),
    label_vjust = case_when(
      rank == 1 ~ -0.1,
      rank == 2 ~ -0,
      rank == 3 ~ 0.1,
      rank == 4 ~ 0.2
    ),
    label = plr_name
  )

# Beschriftung plrs mit grünversorgung 2 (medium)
label_coords_2 <- top_values %>%
  filter(gruenver_numeric == 2) %>%
  mutate(
    label = case_when(
      rank == 1 ~ plr_name,
      rank == 2 ~ ifelse(
        str_detect(plr_name, " "),
        paste(
          str_extract(plr_name, "^[^ ]+"),
          str_remove(plr_name, "^[^ ]+ "),
          sep = "\n"
        ),
        plr_name
      ),
      rank == 3 ~ plr_name
    ),
    label_nudge_x = case_when(
      rank == 1 ~ -0.29,
      rank == 2 ~ 0.17,
      rank == 3 ~ -0.2
    ),
    label_vjust = case_when(
      rank == 1 ~ -0.1,
      rank == 2 ~ 0.7,
      rank == 3 ~ -0.2
    )
  )

# Beschriftung plrs mit grünversorgung 1 (good)
label_coords_1 <- top_values %>%
  filter(gruenver_numeric == 1) %>%
  mutate(
    label_nudge_x = case_when(
      rank == 1 ~ 0.25,
      rank == 2 ~ -0.2
    ),
    label_vjust = case_when(
      rank == 1 ~ -0.2,
      rank == 2 ~ 0.2
    ),
    label = plr_name
  )

label_coords <- bind_rows(label_coords_1, label_coords_2, label_coords_3)

# Plot2 mit Beschriftung
plot2g + 
  geom_text(
    data = label_coords,
    aes(label = label),
    size = 3.5,
    nudge_x = label_coords$label_nudge_x,
    vjust = label_coords$label_vjust,
    color = "black"
  ) +
  theme(
    panel.background = element_rect(fill = "whitesmoke"),  # Hintergrund der Grafik auf "whitesmoke" setzen
    panel.grid.major.y = element_line(color = "#d0d0d0")
  )



###### Option 3 ######

## mod_d_o_per_bebaut (moderate decision option per built-up area) ##

density_df <- density(spaces_per_lor_v3$mod_d_o_per_bebaut, adjust = 1)
density_df <- data.frame(x = density_df$x, y = density_df$y)

get_density <- function(value, density_df) {
  approx(density_df$x, density_df$y, xout = value)$y
}

jitter_amount <- function(y, density_df) {
  density <- get_density(y, density_df)
  max_jitter <- 0.22
  min_jitter <- 0.02
  jitter_range <- min_jitter + (density / max(density_df$y) * (max_jitter - min_jitter))
  return(runif(1, -jitter_range, jitter_range))
}

spaces_per_lor_v3 <- spaces_per_lor_v3 %>%
  rowwise() %>%
  mutate(jitter_x = gruenver_numeric + jitter_amount(mod_d_o_per_bebaut, density_df)) %>%
  ungroup()

# Plot erstellen (moderate decision option)
# mit der gleichen y-Achse wie bei decision option 1

plot3g <- ggplot(spaces_per_lor_v3, aes(x = jitter_x, y = mod_d_o_per_bebaut)) +
  geom_point(color = "#CC0000", alpha = 0.8) +
  labs(
    x = "Green Space Provision",
    y = "Total Traffic Area per Built-up Area",
    title = "Ratio of the total traffic area (<span style='color:black;'>of</span> <span style='color:#CC0000;'>conversion Option 3</span><span style='color:black;'>)</span> relative to the built-up area<br>and the green space provision of each planning area"
  ) +
  theme_minimal() +
  scale_x_continuous(breaks = c(1, 2, 3), labels = c("Good", "Medium", "Poor"), expand = c(0.1, 0)) +
  scale_y_continuous(limits = c(y_min, y_max)) +
  theme(
    panel.grid.major.x = element_blank(),
    panel.grid.minor.x = element_blank(),
    axis.title.x = element_text(margin = margin(t = 10)),
    axis.title.y = element_text(margin = margin(r = 10)),
    plot.title = element_markdown()
  )

### Um die Planungsräume mit den höchsten relativen Verkehrsflächenwerten herauszufinden:

quantile_thresholds <- spaces_per_lor_v3 %>%
  group_by(gruenver_numeric) %>%
  summarise(quantile_95 = quantile(mod_d_o_per_bebaut, 0.95, na.rm = TRUE))

joined_data <- spaces_per_lor_v3 %>%
  inner_join(quantile_thresholds, by = "gruenver_numeric")

top_values <- joined_data %>%
  filter(mod_d_o_per_bebaut > quantile_95)

sorted_top_values <- top_values %>%
  arrange(gruenver_numeric, desc(mod_d_o_per_bebaut))

# überprüfen
print(sorted_top_values %>% select(gruenver_numeric, plr_name, mod_d_o_per_bebaut))


# höchste verkehrsflächenwerte für beschriftung
top_values <- top_values %>%
  group_by(gruenver_numeric) %>%
  arrange(desc(mod_d_o_per_bebaut)) %>%
  mutate(
    rank = row_number()
  )

# Überprüfen
print(top_values %>% select(gruenver_numeric, plr_name, mod_d_o_per_bebaut, rank))

# Beschriftung plrs mit grünversorgung 3 (poor)
label_coords_3 <- top_values %>%
  filter(gruenver_numeric == 3) %>%
  mutate(
    label_nudge_x = case_when(
      rank == 1 ~ 0.28,
      rank == 2 ~ -0.18,
      rank == 3 ~ 0.23,
      rank == 4 ~ -0.22
    ),
    label_vjust = case_when(
      rank == 1 ~ -0.1,
      rank == 2 ~ -0.2,
      rank == 3 ~ -0.1,
      rank == 4 ~ 0.3
    ),
    label = plr_name
  )

# Beschriftung plrs mit grünversorgung 2 (mediun)
label_coords_2 <- top_values %>%
  filter(gruenver_numeric == 2) %>%
  mutate(
    label = case_when(
      rank == 1 ~ plr_name,
      rank == 2 ~ ifelse(
        str_detect(plr_name, " "),
        paste(
          str_extract(plr_name, "^[^ ]+"),
          str_remove(plr_name, "^[^ ]+ "),
          sep = "\n"
        ),
        plr_name
      ),
      rank == 3 ~ plr_name
    ),
    label_nudge_x = case_when(
      rank == 1 ~ -0.29,
      rank == 2 ~ 0.17,
      rank == 3 ~ -0.2
    ),
    label_vjust = case_when(
      rank == 1 ~ -0.1,
      rank == 2 ~ 0.6,
      rank == 3 ~ 0.1
    )
  )

# Beschriftung plrs mit grünversorgung 1 (good)
label_coords_1 <- top_values %>%
  filter(gruenver_numeric == 1) %>%
  mutate(
    label_nudge_x = case_when(
      rank == 1 ~ 0.25,
      rank == 2 ~ -0.2
    ),
    label_vjust = case_when(
      rank == 1 ~ -0.2,
      rank == 2 ~ 0.2
    ),
    label = plr_name
  )

label_coords <- bind_rows(label_coords_1, label_coords_2, label_coords_3)

# Plot 3 mit Beschriftungen
plot3g + 
  geom_text(
    data = label_coords,
    aes(label = label),
    size = 3.5,
    nudge_x = label_coords$label_nudge_x,
    vjust = label_coords$label_vjust,
    color = "black"
  ) +
  theme(
    panel.background = element_rect(fill = "whitesmoke"),  # Hintergrund der Grafik auf "whitesmoke" setzen
    panel.grid.major.y = element_line(color = "#d0d0d0")
  )




