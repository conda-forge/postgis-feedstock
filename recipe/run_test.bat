@echo off

REM Test PostGIS command line tools
echo Testing shp2pgsql...
shp2pgsql test_data\test.shp
if errorlevel 1 exit 1

echo Testing pgsql2shp...
pgsql2shp --help
if errorlevel 1 exit 1

echo Testing raster2pgsql...
raster2pgsql --help
if errorlevel 1 exit 1

echo All tests passed!