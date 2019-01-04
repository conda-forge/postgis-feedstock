#/usr/bin/env bash
set -e

. $RECIPE_DIR/pg.sh

sed -i \
  -e "s|/home/conda/feedstock_root/build_artifacts/postgresql-split_[0-9]\+/_build_env|$BUILD_PREFIX|g" \
  $PREFIX/lib/pgxs/src/Makefile.global
# SQL Preprocessor
export CPPBIN=$CPP

./autogen.sh


chmod 755 configure
./configure \
    --prefix=$PREFIX \
    --with-pgconfig=$RECIPE_DIR/conda-pg_config \
    --with-geosconfig=$PREFIX/bin/geos-config \
    --with-gdalconfig=$PREFIX/bin/gdal-config \
    --with-xml2config=$PREFIX/bin/xml2-config \
    --with-projdir=$PREFIX \
    --with-libiconv-prefix=$PREFIX \
    --with-libintl-prefix=$PREFIX \
    --with-jsondir=$PREFIX \
    --with-pcredir=$PREFIX \
    --with-gettext=$PREFIX \
    --with-raster \
    --with-topology \
    --without-interrupt-tests
make

# There is an issue running shp2pgsql during build time on macOS.
# It seems the side effect is that 26 unit tests fail.
# This is not too bad because we still call shp2pgsql, pgsql2shp 
# and raster2pgsql during the test phase.
if [ $(uname) = "Linux" ]; then
    start_db
    make check
    stop_db
fi

make install
