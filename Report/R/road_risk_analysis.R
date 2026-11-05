# =============================================================================
# road_risk_analysis.R
#
# Helper functions used by "EIS Pilot Report.Rmd" to link each worker accident
# location to the road it most likely happened on, and to total the number of
# accidents per road corridor.
#
# The report loads this file with source() in its setup chunk. Nothing runs
# when the file is sourced; it only defines the five functions below:
#
#   is_drivable_highway()      - keeps OSM road types that carry vehicles
#   road_class_priority()      - ranks OSM road types from major to minor
#   normalise_corridor_text()  - cleans road refs/names so they can be grouped
#   match_accidents_to_roads() - assigns each accident to its nearest road
#   summarise_road_burden()    - counts matched accidents per road corridor
#
# All inputs must be sf objects in a projected CRS measured in metres (the
# report uses UTM Zone 46N, EPSG:32646), so that distances are in metres.
# =============================================================================


# -----------------------------------------------------------------------------
# is_drivable_highway(x)
#
# Purpose: decide which OpenStreetMap (OSM) road features can carry motor
# traffic. Footpaths, cycle tracks, steps, platforms and roads that are only
# planned or under construction are excluded, so an accident is never matched
# to a footpath that runs beside the real road.
#
# Input:  x - character vector of OSM "highway" values (e.g. "trunk").
# Output: logical vector, TRUE where the road is drivable. Blank or missing
#         values return FALSE.
# -----------------------------------------------------------------------------
is_drivable_highway <- function(x) {
  excluded <- c(
    "footway", "cycleway", "pedestrian", "steps", "bridleway", "path",
    "corridor", "platform", "construction", "proposed", "raceway"
  )
  !is.na(x) & nzchar(trimws(x)) & !(tolower(trimws(x)) %in% excluded)
}


# -----------------------------------------------------------------------------
# road_class_priority(x)
#
# Purpose: give each OSM road type a rank, where 1 is the most important road
# (motorway) and larger numbers are smaller roads. When two roads are almost
# equally close to an accident, the more important road is chosen, because
# major roads carry far more traffic and are the more likely crash location.
#
# Input:  x - character vector of OSM "highway" values.
# Output: integer vector of ranks. Road types not in the list get 20, so they
#         are only chosen when nothing better is available.
# -----------------------------------------------------------------------------
road_class_priority <- function(x) {
  levels <- c(
    motorway = 1L, trunk = 2L, primary = 3L, secondary = 4L,
    tertiary = 5L, unclassified = 6L, residential = 7L,
    living_street = 8L, service = 9L, track = 10L
  )
  answer <- unname(levels[tolower(x)])
  answer[is.na(answer)] <- 20L
  answer
}


# -----------------------------------------------------------------------------
# normalise_corridor_text(x)
#
# Purpose: turn road references and names into a simple key, so that spellings
# such as "N 3", "n3" and "N-3" are all treated as the same corridor ("N3").
#
# Input:  x - character vector (road ref or road name).
# Output: upper-case text with spaces and punctuation removed. Missing values
#         become an empty string.
# -----------------------------------------------------------------------------
normalise_corridor_text <- function(x) {
  x <- toupper(trimws(ifelse(is.na(x), "", x)))
  gsub("[^[:alnum:]]+", "", x)
}


# -----------------------------------------------------------------------------
# match_accidents_to_roads(accidents, roads, ...)
#
# Purpose: find the road each accident point most likely belongs to.
#
# Method, for each accident:
#   1. Measure the distance to every drivable road.
#   2. Take the nearest road. Any other road within `ambiguity_tolerance_m`
#      (5 m) of that distance is treated as an equally good candidate.
#   3. Among the candidates, pick the most important road class; if still
#      tied, the nearer road; if still tied, the lower OSM id (so the result
#      is always the same on every run).
#   4. Label the match:
#        High      - nearest road is within `high_confidence_m` (30 m) and no
#                    other road competes with it.
#        Lower     - within `maximum_m` (50 m) but either further than 30 m or
#                    with a competing road nearby (e.g. a junction or a
#                    service road running alongside a highway).
#        Unmatched - no drivable road within 50 m. Road fields are left empty.
#
# Inputs:  accidents - sf points, one row per accident.
#          roads     - sf lines with at least `osm_id` and `highway` columns.
#          Both must share the same projected (metre-based) CRS.
# Output:  data frame with one row per accident: the original accident columns,
#          the chosen road's attributes, plus `match_distance_m`,
#          `match_confidence` and `ambiguity_reason`.
# -----------------------------------------------------------------------------
match_accidents_to_roads <- function(accidents, roads,
                                     high_confidence_m = 30,
                                     maximum_m = 50,
                                     ambiguity_tolerance_m = 5) {
  # Check the inputs before doing any work
  if (!inherits(accidents, "sf") || !inherits(roads, "sf")) {
    stop("accidents and roads must be sf objects")
  }
  if (sf::st_crs(accidents) != sf::st_crs(roads)) stop("accidents and roads must use the same CRS")
  if (!all(c("osm_id", "highway") %in% names(roads))) stop("roads require osm_id and highway fields")

  # Keep only roads that carry vehicles, then build a distance table:
  # one row per accident, one column per road, values in metres
  usable <- roads[is_drivable_highway(roads$highway), , drop = FALSE]
  if (!nrow(usable)) stop("No drivable roads were supplied")
  distance_matrix <- units::drop_units(sf::st_distance(accidents, usable))
  if (is.null(dim(distance_matrix))) distance_matrix <- matrix(distance_matrix, nrow = nrow(accidents))

  selected <- vector("list", nrow(accidents))
  for (i in seq_len(nrow(accidents))) {
    distances <- distance_matrix[i, ]
    minimum <- min(distances)
    candidates <- which(distances <= minimum + ambiguity_tolerance_m)
    # Only candidates inside the explicit ambiguity tolerance compete on road
    # class; a road outside that band cannot override the materially nearer way.
    chosen <- candidates[order(
      road_class_priority(usable$highway[candidates]),
      distances[candidates],
      as.character(usable$osm_id[candidates])
    )][1]
    ambiguous <- length(candidates) > 1L
    within_limit <- minimum <= maximum_m

    # Combine the accident's own fields with the chosen road's fields. If the
    # nearest road is beyond the 50 m limit, the road fields are set to NA.
    row <- sf::st_drop_geometry(accidents[i, , drop = FALSE])
    road_values <- sf::st_drop_geometry(usable[chosen, , drop = FALSE])
    road_values[] <- lapply(road_values, function(x) if (within_limit) x else x[NA_integer_])
    selected[[i]] <- cbind(
      row,
      road_values,
      match_distance_m = minimum,
      match_confidence = if (!within_limit) "Unmatched" else if (minimum <= high_confidence_m && !ambiguous) "High" else "Lower",
      ambiguity_reason = if (!within_limit) "No drivable road within maximum distance" else if (ambiguous) "Competing road within ambiguity tolerance" else NA_character_,
      stringsAsFactors = FALSE
    )
  }
  dplyr::bind_rows(selected)
}


# -----------------------------------------------------------------------------
# summarise_road_burden(matches, roads)
#
# Purpose: count how many matched accidents fall on each road corridor.
#
# OSM splits a single road into many short pieces ("ways"). To count accidents
# per road rather than per piece, the pieces are grouped into a corridor:
#   - by road reference (e.g. all pieces with ref "N3"), if one exists;
#   - otherwise by road name;
#   - otherwise each piece is its own corridor (identified by its OSM id).
#
# Inputs:  matches - output of match_accidents_to_roads().
#          roads   - the same sf road lines used for matching.
# Output:  data frame, one row per corridor that has at least one accident,
#          sorted from most to fewest accidents, with:
#            recorded_accidents          - number of matched accidents
#            high/lower_confidence_...   - the same count split by match quality
#            share_of_matched_pct        - % of all matched accidents
#            corridor_length_km          - total length of the corridor in the
#                                          OSM extract
#            accidents_per_km            - accidents divided by that length.
#                                          This shows how tightly packed the
#                                          cases are; it is NOT a crash rate,
#                                          because traffic volume is unknown.
#          Unmatched accidents are left out.
# -----------------------------------------------------------------------------
summarise_road_burden <- function(matches, roads) {
  matched <- matches[!is.na(matches$osm_id), , drop = FALSE]
  if (!nrow(matched)) return(data.frame())

  road_attributes <- sf::st_drop_geometry(roads)
  # OSM extracts may omit some naming fields. Keep the burden summary
  # structurally stable by creating missing optional fields as NA.
  for (field in c("ref", "name", "name_bn")) {
    if (!field %in% names(road_attributes)) road_attributes[[field]] <- NA_character_
  }
  if (!"length_km" %in% names(road_attributes)) {
    road_attributes$length_km <- as.numeric(sf::st_length(roads)) / 1000
  }
  # Give every OSM piece a corridor key: ref first, then name, then its own id
  road_attributes <- road_attributes |>
    dplyr::mutate(
      corridor_id = dplyr::case_when(
        !is.na(ref) & nzchar(trimws(ref)) ~ paste0("ref:", normalise_corridor_text(ref)),
        !is.na(name) & nzchar(trimws(name)) ~ paste0("name:", normalise_corridor_text(name)),
        TRUE ~ paste0("osm:", osm_id)
      )
    )

  # Count accidents per corridor, split by match confidence
  event_counts <- matched |>
    dplyr::left_join(road_attributes[, c("osm_id", "corridor_id")], by = "osm_id") |>
    dplyr::group_by(corridor_id) |>
    dplyr::summarise(
      recorded_accidents = dplyr::n(),
      high_confidence_accidents = sum(match_confidence == "High"),
      lower_confidence_accidents = sum(match_confidence == "Lower"),
      .groups = "drop"
    )

  # Describe each corridor: a label, its road types, total length and OSM ids
  corridor_attributes <- road_attributes |>
    dplyr::group_by(corridor_id) |>
    dplyr::summarise(
      road_label = dplyr::first(stats::na.omit(c(ref, name, name_bn, osm_id))),
      ref = dplyr::first(ref),
      name = dplyr::first(name),
      highway = paste(sort(unique(highway)), collapse = "; "),
      corridor_length_km = sum(length_km, na.rm = TRUE),
      osm_ids = paste(sort(unique(osm_id)), collapse = "; "),
      .groups = "drop"
    )

  # Join counts to descriptions, add share and density, sort by accident count
  event_counts |>
    dplyr::left_join(corridor_attributes, by = "corridor_id") |>
    dplyr::mutate(
      share_of_matched_pct = 100 * recorded_accidents / sum(recorded_accidents),
      accidents_per_km = dplyr::if_else(corridor_length_km > 0, recorded_accidents / corridor_length_km, NA_real_)
    ) |>
    dplyr::arrange(dplyr::desc(recorded_accidents), dplyr::desc(accidents_per_km), road_label)
}
