# Small formatting helpers shared by ui/server.

format_duration <- function(minutes) {
  total_min <- round(minutes)
  hours <- total_min %/% 60
  mins <- total_min %% 60
  if (hours > 0) {
    sprintf("%dh %02dm", hours, mins)
  } else {
    sprintf("%dm", mins)
  }
}

format_pace <- function(min_per_km) {
  if (is.na(min_per_km) || is.infinite(min_per_km)) return("-")
  mins <- floor(min_per_km)
  secs <- round((min_per_km - mins) * 60)
  sprintf("%d:%02d /km", mins, secs)
}
