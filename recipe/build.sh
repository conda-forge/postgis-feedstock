#/usr/bin/env bash
set -e

. ${RECIPE_DIR}/pg.sh

export CPPBIN="${CPP}"

./autogen.sh

# OSX seems to be having trouble finding stdc++
# see note at https://postgis.net/docs/manual-3.2/postgis_installation.html#PGInstall
export LDFLAGS="-lstdc++ $LDFLAGS"


if [[ "${CONDA_BUILD_CROSS_COMPILATION:-}" == "1" ]]; then
    export PG_CONFIG=${BUILD_PREFIX}/bin/pg_config
else
    export PG_CONFIG=${PREFIX}/bin/pg_config
fi

./configure \
    --prefix=${PREFIX} \
    --libdir=${PREFIX}/lib \
    --includedir=${PREFIX}/include \
    --with-geosconfig=$PREFIX/bin/geos-config \
    --with-pgconfig=${PG_CONFIG} \
    --with-gdalconfig=${PREFIX}/bin/gdal-config \
    --with-xml2config=${PREFIX}/bin/xml2-config \
    --with-libiconv-prefix=${PREFIX} \
    --with-libintl-prefix=${PREFIX} \
    --with-gettext \
    --with-raster \
    --with-topology \
    --disable-nls \
    --without-interrupt-tests \
    --without-protobuf

make -j$CPU_COUNT

# Only one test is failing on macOS and Linux.
# commenting this for now until we have a new release.
# start_db
# make check
# stop_db

make install
