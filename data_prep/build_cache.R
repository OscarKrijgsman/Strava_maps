# Parses the raw Strava export (activities.csv + one GPX per activity) into
# two small cached R objects the Shiny app can load instantly.
#
# Run once from the project root: Rscript data_prep/build_cache.R
# Re-run whenever new activities are added to the export.

library(sf)
library(dplyr)
library(lubridate)

project_root <- getwd()
export_dir <- file.path(project_root, "Strava_260517", "export_71201777")
csv_path <- file.path(export_dir, "activities.csv")
cache_dir <- file.path(project_root, "cache")
dir.create(cache_dir, showWarnings = FALSE)

heatmap_points_per_run <- 250

# --- Read activities.csv -----------------------------------------------
# The bulk export repeats several column names (e.g. "Distance" appears once
# as the user-facing summary and again, later, as the precise value derived
# from the uploaded file). Resolve positions from the raw header instead of
# relying on auto-deduplicated names, which differ across CSV readers.
raw_header <- as.character(read.csv(csv_path, header = FALSE, nrows = 1, stringsAsFactors = FALSE))
col_index <- function(name, occurrence = 1) which(raw_header == name)[occurrence]

raw <- read.csv(csv_path, header = FALSE, skip = 1, stringsAsFactors = FALSE)

activities <- data.frame(
  activity_id = raw[[col_index("Activity ID")]],
  date_raw = raw[[col_index("Activity Date")]],
  name = raw[[col_index("Activity Name")]],
  type = raw[[col_index("Activity Type")]],
  filename = raw[[col_index("Filename")]],
  distance_m = as.numeric(raw[[col_index("Distance", 2)]]),
  moving_time_s = as.numeric(raw[[col_index("Moving Time")]]),
  avg_hr = as.numeric(raw[[col_index("Average Heart Rate")]]),
  stringsAsFactors = FALSE
)

# "May 17, 2026, 8:17:28 AM" — force the C locale so %B matches English
# month names regardless of the machine's configured locale.
old_locale <- Sys.getlocale("LC_TIME")
Sys.setlocale("LC_TIME", "C")
activities$date <- as.POSIXct(
  strptime(activities$date_raw, format = "%B %d, %Y, %I:%M:%S %p", tz = "UTC")
)
Sys.setlocale("LC_TIME", old_locale)

runs <- activities %>%
  filter(type == "Run", !is.na(filename), filename != "", !is.na(date)) %>%
  mutate(
    distance_km = distance_m / 1000,
    moving_time_min = moving_time_s / 60,
    pace_min_per_km = ifelse(distance_km > 0, moving_time_min / distance_km, NA_real_),
    year = year(date),
    month = floor_date(date, "month"),
    week = floor_date(date, "week", week_start = 1)
  )

message(sprintf("Found %d runs with a linked GPX file.", nrow(runs)))

# --- Parse each GPX file -------------------------------------------------
run_rows <- vector("list", nrow(runs))
point_rows <- vector("list", nrow(runs))
n_failed <- 0

for (i in seq_len(nrow(runs))) {
  row <- runs[i, ]
  gpx_path <- file.path(export_dir, row$filename)

  track <- tryCatch(
    suppressWarnings(st_read(gpx_path, layer = "tracks", quiet = TRUE)),
    error = function(e) NULL
  )
  pts <- tryCatch(
    suppressWarnings(st_read(gpx_path, layer = "track_points", quiet = TRUE)),
    error = function(e) NULL
  )

  if (is.null(track) || nrow(track) == 0 || is.null(pts) || nrow(pts) == 0) {
    warning(sprintf("Skipping activity %s: could not parse %s", row$activity_id, gpx_path))
    n_failed <- n_failed + 1
    next
  }

  geom <- st_cast(st_union(st_geometry(track)), "MULTILINESTRING")
  run_rows[[i]] <- st_sf(
    activity_id = row$activity_id,
    name = row$name,
    date = row$date,
    year = row$year,
    month = row$month,
    week = row$week,
    distance_km = row$distance_km,
    moving_time_min = row$moving_time_min,
    pace_min_per_km = row$pace_min_per_km,
    avg_hr = row$avg_hr,
    geometry = geom,
    crs = st_crs(track)
  )

  coords <- st_coordinates(pts)
  n <- nrow(coords)
  keep <- if (n > heatmap_points_per_run) {
    unique(floor(seq(1, n, length.out = heatmap_points_per_run)))
  } else {
    seq_len(n)
  }
  point_rows[[i]] <- data.frame(
    activity_id = row$activity_id,
    date = row$date,
    year = row$year,
    month = row$month,
    week = row$week,
    lon = coords[keep, "X"],
    lat = coords[keep, "Y"]
  )
}

run_rows <- run_rows[!vapply(run_rows, is.null, logical(1))]
point_rows <- point_rows[!vapply(point_rows, is.null, logical(1))]

runs_sf <- do.call(rbind, run_rows)
heatmap_points <- do.call(rbind, point_rows)

message(sprintf(
  "Cached %d runs (%d skipped) and %d heatmap points.",
  nrow(runs_sf), n_failed, nrow(heatmap_points)
))

saveRDS(runs_sf, file.path(cache_dir, "runs_sf.rds"))
saveRDS(heatmap_points, file.path(cache_dir, "heatmap_points.rds"))
