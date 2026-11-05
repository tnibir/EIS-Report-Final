library("arrow")
library(here)
df <- read_parquet(file.path(getwd(),"Output/points.parquet")) ## OR
points <- read_parquet(here("Output", "points.parquet"))
paths <- read_parquet(here("Output", "paths.parquet"))

View(paths)
