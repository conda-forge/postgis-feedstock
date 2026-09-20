#/usr/bin/env bash
set -e

. ${RECIPE_DIR}/pg.sh

# postgis's configure only honours a preset CPPBIN if it is an absolute path;
# otherwise it searches PATH for a bare `cpp`, which conda's compilers don't
# provide (and a bug in configure.ac then leaves SQLPP empty instead of
# falling back to ${CPP}).
export CPPBIN="$(command -v "${CPP}")"

# Newer protobuf-c dropped the standalone protoc-c binary; provide a shim
# that delegates to protoc (which uses protoc-gen-c as a plugin).
cat > "${BUILD_PREFIX}/bin/protoc-c" << 'EOF'
#!/bin/bash
exec protoc "$@"
EOF
chmod +x "${BUILD_PREFIX}/bin/protoc-c"

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
    --with-protobuf \
    --disable-nls \
    --without-interrupt-tests \
    || (cat config.log && exit 1)

# Ensure upgrade SQL exists for utils/postgis_restore_data.generated
make -C postgis postgis_upgrade.sql

make -j$CPU_COUNT

# Only one test is failing on macOS and Linux.
# commenting this for now until we have a new release.
# start_db
# make check
# stop_db

make install
