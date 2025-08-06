@echo off
setlocal enabledelayedexpansion

REM Set necessary environment variables
set "POSTGIS_DISABLE_STATS=1"

REM Convert paths for MSYS2
set "PREFIX_UNIX=%PREFIX:\=/%"
set "LIBRARY_PREFIX_UNIX=%LIBRARY_PREFIX:\=/%"

REM Run the build through MSYS2 bash
bash -c "./autogen.sh"
if errorlevel 1 exit 1

REM Configure PostGIS
bash -c "./configure --prefix=\"%LIBRARY_PREFIX_UNIX%\" --libdir=\"%LIBRARY_PREFIX_UNIX%/lib\" --includedir=\"%LIBRARY_PREFIX_UNIX%/include\" --with-pgconfig=\"%LIBRARY_PREFIX_UNIX%/bin/pg_config\" --with-geosconfig=\"%LIBRARY_PREFIX_UNIX%/bin/geos-config\" --with-gdalconfig=\"%LIBRARY_PREFIX_UNIX%/bin/gdal-config\" --with-xml2config=\"%LIBRARY_PREFIX_UNIX%/bin/xml2-config\" --with-projdir=\"%LIBRARY_PREFIX_UNIX%\" --with-libiconv-prefix=\"%LIBRARY_PREFIX_UNIX%\" --with-libintl-prefix=\"%LIBRARY_PREFIX_UNIX%\" --with-gettext --with-raster --with-topology --disable-nls --without-interrupt-tests --without-protobuf"
if errorlevel 1 exit 1

REM Build PostGIS
bash -c "make -j%CPU_COUNT%"
if errorlevel 1 exit 1

REM Install PostGIS
bash -c "make install"
if errorlevel 1 exit 1

REM Copy PostGIS extensions to PostgreSQL share directory
xcopy /E /Y "%LIBRARY_PREFIX%\share\extension\*" "%PREFIX%\share\extension\"
if errorlevel 1 exit 1

REM Copy PostGIS libraries to PostgreSQL lib directory
xcopy /E /Y "%LIBRARY_LIB%\postgis*.dll" "%PREFIX%\lib\"
if errorlevel 1 exit 1

REM Copy PostGIS executables to bin directory
xcopy /Y "%LIBRARY_BIN%\shp2pgsql.exe" "%PREFIX%\Scripts\"
if errorlevel 1 exit 1
xcopy /Y "%LIBRARY_BIN%\pgsql2shp.exe" "%PREFIX%\Scripts\"
if errorlevel 1 exit 1
xcopy /Y "%LIBRARY_BIN%\raster2pgsql.exe" "%PREFIX%\Scripts\"
if errorlevel 1 exit 1

REM Create activation scripts
set ACTIVATE_DIR=%PREFIX%\etc\conda\activate.d
set DEACTIVATE_DIR=%PREFIX%\etc\conda\deactivate.d
mkdir "%ACTIVATE_DIR%"
mkdir "%DEACTIVATE_DIR%"

REM Create activation script
echo @echo off > "%ACTIVATE_DIR%\postgis-activate.bat"
echo set "POSTGIS_GDAL_ENABLED_DRIVERS=ENABLE_ALL" >> "%ACTIVATE_DIR%\postgis-activate.bat"
echo set "POSTGIS_ENABLE_OUTDB_RASTERS=1" >> "%ACTIVATE_DIR%\postgis-activate.bat"

REM Create deactivation script
echo @echo off > "%DEACTIVATE_DIR%\postgis-deactivate.bat"
echo set "POSTGIS_GDAL_ENABLED_DRIVERS=" >> "%DEACTIVATE_DIR%\postgis-deactivate.bat"
echo set "POSTGIS_ENABLE_OUTDB_RASTERS=" >> "%DEACTIVATE_DIR%\postgis-deactivate.bat"