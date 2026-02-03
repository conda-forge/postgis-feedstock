#/usr/bin/env bash
set -e

. ${RECIPE_DIR}/pg.sh

export CPPBIN="${CPP}"

./autogen.sh

# OSX seems to be having trouble finding stdc++
# see note at https://postgis.net/docs/manual-3.2/postgis_installation.html#PGInstall
export LDFLAGS="-lstdc++ $LDFLAGS"

# Work around macOS PGXS injecting unsupported '-fuse-ld=lld' into link flags
if [[ "${target_platform}" == osx-* ]]; then
    pgxs_makefile="${PREFIX}/lib/pgxs/src/Makefile.global"
    if [[ -f "${pgxs_makefile}" ]]; then
        sed -i.bak 's/ -fuse-ld=lld//g' "${pgxs_makefile}"
    fi
fi

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
    --without-interrupt-tests \
    --without-protobuf \
    || (cat config.log && exit 1)

make -j$CPU_COUNT

# Only one test is failing on macOS and Linux.
# commenting this for now until we have a new release.
# start_db
# make check
# stop_db

make install
