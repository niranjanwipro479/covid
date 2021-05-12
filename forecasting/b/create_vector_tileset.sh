#!/bin/bash

# this script takes geojson district data and creates a vector tileset for pushing to mapbox.
# this requires tippecanoe and tile-join, which are installed in ~/iec/local/share/tippecanoe/

# note: --generate-ids option is required for referencing feature ids in
# e.g. hover effects. from Mapbox: "mapbox/tippecanoe#615 adds the most
# basic --generate-ids option (using the input feature sequence for the
# ID), with the disclaimer that the IDs are not stable and that their
# format may change in the future."

# create district tileset with zoom range defined (cost saver)
~/iec/local/share/tippecanoe/tippecanoe --force -z9 -Z5 -o $TMP/covid_data.mbtiles --read-parallel --simplification=10 --coalesce-smallest-as-needed --detect-shared-borders --generate-ids $IEC/covid/forecasting/district.geojson