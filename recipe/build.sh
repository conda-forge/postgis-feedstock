#/usr/bin/env bash
set -e

. ${RECIPE_DIR}/pg.sh

export CPPBIN="${CPP}"

./autogen.sh

./configure \
    --prefix=${PREFIX} \
    --libdir=${PREFIX}/lib \
    --includedir=${PREFIX}/include \
    --with-geosconfig=$PREFIX/bin/geos-config \
    --with-pgconfig=${PREFIX}/bin/pg_config \
    --with-gdalconfig=${PREFIX}/bin/gdal-config \
    --with-xml2config=${PREFIX}/bin/xml2-config \
    --with-libiconv-prefix=${PREFIX} \
    --with-libintl-prefix=${PREFIX} \
    --with-gettext \
    --with-raster \
    --with-topology \
    --disable-nls \
    --without-interrupt-tests

make

start_db
make check
stop_db

make install
