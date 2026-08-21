# Strava Runs — R Shiny Map App

## Context

The folder contains a full Strava data export (`Strava_260517/export_71201777/`): `activities.csv` (772 rows: 739 Run, 20 Ride, 13 Walk, Apr 2021–Sep 2022) plus a matching GPX file per activity in `activities/` (557 MB total, one file per Activity ID, containing lat/lon/ele/time trackpoints). There is no existing code in this directory — this is a greenfield build. Goal: an R Shiny app that plots runs on an interactive map, shows a density heatmap of where you run most, lets you filter by week/month/year, and shows summary stats (distance, time) for the selected period.

Decisions already made with the user:
- **Heatmap approach**: point-density heatmap (leaflet.extras `addHeatmap` over raw GPS points), not OSM street-segment matching. Simpler, no external OSM dependency, fast to filter.
- **Scope**: Runs only (739 activities), not Rides/Walks.

## Environment setup

R is not installed on this machine. Before anything can run:
- `brew install --cask r` (or `brew install r` for CLI-only — cask gives R.app too; CLI-only is sufficient for Shiny dev)
- Install packages once R is present: `shiny`, `bslib`, `sf`, `leaflet`, `leaflet.extras`, `dplyr`, `lubridate`, `tidyr`, `plotly`

## Architecture

Two-stage design: an offline **data prep** step that parses the 557 MB of GPX once into a small cached R object, and a **Shiny app** that only ever reads the cache (so the app launches in seconds, not minutes).

```
Strava_runs/
  data_prep/
    build_cache.R        # one script: reads activities.csv + all GPX, writes cache/*.rds
  app/
    app.R                # ui + server in one file (simple enough not to split)
    R/
      helpers.R           # small formatting helpers (pace, duration) shared by ui/server
  cache/
    runs_sf.rds           # one row per run: sf LINESTRING + date/distance/time metadata
    heatmap_points.rds    # downsampled lat/lon points per run, for the heatmap layer
  README.md                # how to run build_cache.R and then the app
```

### `data_prep/build_cache.R`

1. Read `Strava_260517/export_71201777/activities.csv`, filter `Activity Type == "Run"`.
2. Keep: Activity ID, Activity Date (parsed to POSIXct), Activity Name, Distance, Moving Time, Elapsed Time, Average Heart Rate, Filename.
3. For each `Filename`, use `sf::st_read(path, layer = "tracks")` (GDAL's GPX driver — no manual XML parsing needed) to get one LINESTRING per run, and `layer = "track_points"` to get the raw points for the heatmap. Skip + warn on any file that fails to parse rather than aborting the whole batch.
4. Build `runs_sf`: `sf` object, one row per run, geometry = LINESTRING, columns = date, distance_km, moving_time_min, avg_pace, year/month/week (precomputed via `lubridate` for fast filtering).
5. Build `heatmap_points`: data frame of `run_id, lat, lon, date`. Downsample per run (keep every Nth point, target ~150–300 points/run) so the combined heatmap layer stays responsive in the browser — still dense enough for a street-level pattern.
6. Save both with `saveRDS()` to `cache/`.
7. This script is run manually once, and re-run only when new activities are added — not on every app start.

### `app/app.R`

- **UI** (`bslib::page_sidebar`):
  - Sidebar: date-range filter (defaults to full range), quick-select buttons/radio for Year / Month / Week granularity, a toggle for map layer (Heatmap / Individual routes / Both).
  - Main panel: full-height `leafletOutput`, with a row of stat cards below/beside it (total distance, total moving time, number of runs, average pace) and a small `plotly` weekly/monthly mileage bar chart for context.
- **Server**:
  - `filtered_runs()` reactive: subsets `runs_sf` by the selected date range.
  - `filtered_points()` reactive: subsets `heatmap_points` by the same run IDs.
  - `renderLeaflet`: base map once (CartoDB Positron tiles, centered/zoomed to data bounds), updated via `leafletProxy` on filter change — clear + re-add heatmap layer (`leaflet.extras::addHeatmap`) and/or polylines (`addPolylines`) depending on the layer toggle, using `addLayersControl` so the user can switch without a full redraw.
  - Stat outputs computed directly from `filtered_runs()` metadata columns (no GPX re-parsing at runtime).

## Verification

1. `Rscript data_prep/build_cache.R` — confirm it completes without errors and `cache/runs_sf.rds` / `cache/heatmap_points.rds` are created, with row counts sane (~739 runs).
2. `Rscript -e "shiny::runApp('app')"` (or open in RStudio/`shiny::runApp` from the console) — app should launch in a browser tab.
3. Manually verify in-browser: map renders with your run tracks/heatmap over the right geographic area, zooming in shows denser heatmap on frequently-run streets, switching Year/Month/Week filters updates both the map and the stat cards, and stats (distance/time/pace) look plausible against a couple of rows spot-checked in `activities.csv`.
