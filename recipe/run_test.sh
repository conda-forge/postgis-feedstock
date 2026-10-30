#! /usr/bin/env bash
set -e

source pg.sh


test_create_extension()
{
    extensions="postgis
     postgis_raster
     postgis_topology"

   for extension in $extensions; do 
       psql -d postgres -q -c "CREATE EXTENSION $extension"
   done
}

test_mvt()
{
    psql -d postgres -q -c "
        SELECT ST_AsMVT(q, 'test_layer')
        FROM (
            SELECT 1 AS id,
                   ST_AsMVTGeom(ST_MakePoint(0, 0), ST_TileEnvelope(0, 0, 0)) AS geom
        ) q;
    "
}

start_db
test_create_extension
test_mvt
stop_db
