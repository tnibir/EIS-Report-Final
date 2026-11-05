# EIS Report V4: Employment Injury Scheme (EIS) Accident & Commuting Analysis

Spatial analytics pipeline and interactive visualization for the **Employment Injury Scheme (EIS) Pilot** in Bangladesh, developed for accident location verification and worker commuting road-risk assessment.

**Author:** Tasbiul Islam Nibir  
**Project:** GIZ Final Report 4 / EIS Pilot  

---

## 📌 Overview

This project provides an end-to-end data processing and spatial analysis framework for industrial worker safety, specifically analyzing:
1. **Road Traffic Accidents (RTA):** Geocoded accident incident locations and severity.
2. **Commuting Routes:** Worker commute pathways to and from factory hubs.
3. **Road Risk Assessment:** Proximity and hazard correlation between commuter routes, accident hotspots, and OpenStreetMap (OSM) road networks.

---

## 📂 Project Architecture

```text
├── Data Process/
│   ├── Commuting/                 # Raw KMZ spatial files for commuter routes
│   │   └── Old Map File/          # Historical GPS/KML trace archives
│   ├── RTA/                       # Raw KMZ spatial files for Road Traffic Accidents
│   │   └── mapKMZ/                # Incident geolocations (.kmz)
│   ├── Convert KMZ to Parquet.R   # Core ETL pipeline (KMZ extraction -> Parquet)
│   ├── Explore.R                  # Data discovery and spatial validation
│   └── Output/                    # Processed tabular and spatial Parquet files
│       ├── points.parquet         # Extracted point geometries (accidents & POIs)
│       ├── paths.parquet          # Extracted line/route geometries (commute paths)
│       ├── all_features.parquet   # Unified feature dataset
│       ├── input_manifest.csv     # File catalog of all processed KMZs
│       ├── processing_log.csv     # Detailed ingestion logs
│       └── processing_summary.csv # High-level ETL summary
│
├── Report/
│   ├── interactive_accident_map.Rmd # Interactive Leaflet RMarkdown report
│   ├── interactive_accident_map.html# Standalone compiled HTML interactive report
│   ├── R/
│   │   └── road_risk_analysis.R   # Spatial risk buffering and OSM analysis functions
│   └── data/                      # Analysis-ready datasets
│       ├── points.parquet         # Staged accident points
│       ├── paths.parquet          # Staged commuter routes
│       ├── osm_roads.gpkg         # OpenStreetMap road infrastructure (GeoPackage)
│       └── maptiles_cache/        # Offline basemap tiles cache
│
└── README.md                      # Project documentation
```

---

## ⚙️ Process & Methodology

### 1. Data Processing & ETL Pipeline (`Data Process/`)
- **KMZ Ingestion:** Scans directories (`RTA` and `Commuting`) for `.kmz` files, extracts enclosed `.kml` layers dynamically into temporary environments.
- **Layer & Geometry Parsing:** Parses point, line (`LineString`/`MultiLineString`), and polygon geometries with coordinate reference standardisation (WGS 84 / EPSG:4326).
- **Parquet Export:** Serializes spatial data into Apache Parquet format (`points.parquet` and `paths.parquet`) using `sf` and `arrow`, achieving high compression and fast query speeds.
- **Auditing:** Maintains an execution manifest (`input_manifest.csv`) and per-file status logs (`processing_log.csv`) to track conversion status.

### 2. Spatial Risk Analysis (`Report/R/`)
- Utilizes `osm_roads.gpkg` to represent the surrounding street network.
- Computes buffer zones around accident locations (e.g., default 1,000m risk radius) using metric projections (UTM / EPSG:3857/32646).
- Intersects accident density with worker transit corridors to identify high-risk segments.

### 3. Interactive Visualization (`Report/`)
- Built with **R Markdown**, **Leaflet**, and **DT**.
- Features include:
  - Interactive clustering, heatmaps, and custom markers for accident severity.
  - Commuter line overlays with route metrics.
  - Full-width responsive design with searchable, filterable data tables.
  - Compiled into a self-contained HTML deliverable (`interactive_accident_map.html`) for offline sharing and stakeholder presentations.

---

## 🚀 Getting Started

### Prerequisites

Ensure you have **R (>= 4.1.0)** installed along with the following packages:

```r
install.packages(c(
  "sf",
  "arrow",
  "dplyr",
  "readr",
  "tibble",
  "stringr",
  "leaflet",
  "leaflet.extras",
  "htmltools",
  "DT",
  "rmarkdown",
  "knitr"
))
```

### Running the Pipeline

1. **Step 1: Extract & Process Raw KMZ Files**
   Open R / RStudio in the `Data Process/` folder and run:
   ```r
   source("Convert KMZ to Parquet.R")
   ```
   *Outputs will be saved in `Data Process/Output/`.*

2. **Step 2: Generate the Interactive Report**
   Open `Report/interactive_accident_map.Rmd` in RStudio and click **Knit**, or run from the R console:
   ```r
   rmarkdown::render("Report/interactive_accident_map.Rmd")
   ```
   *This compiles `Report/interactive_accident_map.html`.*

---

## 📄 License & Attribution

Developed under the Employment Injury Scheme (EIS) Pilot Research / GIZ initiatives.
All Rights Reserved © Tasbiul Islam Nibir.
