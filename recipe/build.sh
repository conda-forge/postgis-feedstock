#/usr/bin/env bash
set -e

. ${RECIPE_DIR}/pg.sh

if [[ "${target_platform}" == win-* ]]; then
    # Create a cpp wrapper so configure's AC_PATH_PROG([CPPBIN], [cpp]) can find it.
    # Use -xc to force C mode (so .sql.in files are preprocessed) and -nostdinc to
    # avoid injecting MSVC system headers into SQL preprocessing.
    cat > ${SRC_DIR}/cpp <<'CPPEOF'
#!/bin/bash
exec clang.exe -E -xc -nostdinc "$@"
CPPEOF
    chmod +x ${SRC_DIR}/cpp
    export PATH="${SRC_DIR}:${PATH}"
else
    export CPPBIN="${CPP}"
fi

# On Windows, set PKG_CONFIG_PATH so pkg-config can find .pc files in the host prefix
if [[ "${target_platform}" == win-* ]]; then
    export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH}"
fi

# On Windows with clang 21+, using a function as a function pointer (via
# DirectFunctionCall) before PG_FUNCTION_INFO_V1 redeclares it with dllexport
# is a hard error. Many postgis source files have bare forward declarations
# like "Datum foo(PG_FUNCTION_ARGS);" without PGDLLEXPORT. Fix all of them
# so they're consistent with PG_FUNCTION_INFO_V1's dllexport attribute.
if [[ "${target_platform}" == win-* ]]; then
    # Use perl -MFile::Find instead of find -exec to avoid "environment too
    # large for exec()" on Windows: vcvarsall.bat inflates the environment to
    # near the exec() limit, and find's child-exec of perl pushes it over.
    perl -MFile::Find -e '
        my @files;
        find(sub { push @files, $File::Find::name if -f && /\.(c|h)$/ }, "postgis");
        $^I = "";
        @ARGV = @files;
        while (<>) {
            s/^Datum (\w+\(PG_FUNCTION_ARGS\);)$/extern PGDLLEXPORT Datum $1/;
            print;
        }
    '

    # PostGIS defines several functions as 'inline' in .c files but calls them
    # from other translation units. At -O2, clang inlines the body and elides
    # the external symbol, causing link errors. Remove 'inline' so external
    # definitions are always emitted.
    perl -MFile::Find -e '
        my @files;
        find(sub { push @files, $File::Find::name if -f && /\.c$/ }, ".");
        $^I = "";
        @ARGV = @files;
        while (<>) {
            s/^inline ((?:bool|void|int|float|double|static|unsigned|char|size_t|const|struct) )/$1/;
            s/^inline (\w)/$1/;
            print;
        }
    '
fi

./autogen.sh

# OSX seems to be having trouble finding stdc++
# see note at https://postgis.net/docs/manual-3.2/postgis_installation.html#PGInstall
if [[ "${target_platform}" != win-* ]]; then
    export LDFLAGS="-lstdc++ $LDFLAGS"
fi

# On Windows with MSVC/lld-link, there is no separate libm; math functions
# are in the C runtime. Create an empty stub so that -lm succeeds.
if [[ "${target_platform}" == win-* ]]; then
    touch empty.c
    clang.exe -c empty.c -o empty.o
    llvm-lib empty.o -out:${PREFIX}/lib/m.lib
    # stdc++ doesn't exist on MSVC (C++ runtime is in msvcrt).
    # pgcommon/pgport are PostgreSQL internal libs whose symbols are already
    # in postgres.lib. Create empty stubs so -l flags succeed.
    llvm-lib empty.o -out:${PREFIX}/lib/stdc++.lib
    llvm-lib empty.o -out:${PREFIX}/lib/pgcommon.lib
    llvm-lib empty.o -out:${PREFIX}/lib/pgport.lib

    # M_PI and friends are not defined by default on MSVC.
    # strcasecmp/strncasecmp are POSIX, on MSVC they're _stricmp/_strnicmp.
    # __GNUC__ makes PostgreSQL use GCC-style atomics (which clang supports)
    # instead of MSVC atomics that pull in <intrin.h> with broken MMX types.
    # Include PostgreSQL's MSVC compat headers (provides dirent.h, etc.)
    WIN_COMPAT_DEFS="-D_USE_MATH_DEFINES -Dstrcasecmp=_stricmp -Dstrncasecmp=_strnicmp -Dstricmp=_stricmp -Dstrnicmp=_strnicmp -Dstrdup=_strdup -Dgetpid=_getpid -Dgetcwd=_getcwd -DYY_NO_UNISTD_H -I${PREFIX}/include/server/port/win32_msvc"

    # Provide vasprintf/asprintf implementations for MSVC (POSIX, not available natively)
    cat > ${SRC_DIR}/win_compat.h << 'COMPATEOF'
#ifndef WIN_COMPAT_H
#define WIN_COMPAT_H
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <process.h>  /* for _getpid, _spawnv */
#include <io.h>       /* for _setmode etc. */
#include <direct.h>   /* for _getcwd */
static inline int vasprintf(char **strp, const char *fmt, va_list ap) {
    va_list ap2;
    va_copy(ap2, ap);
    int len = _vscprintf(fmt, ap2);
    va_end(ap2);
    if (len < 0) return -1;
    *strp = (char *)malloc(len + 1);
    if (!*strp) return -1;
    return vsprintf(*strp, fmt, ap);
}
static inline int asprintf(char **strp, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int ret = vasprintf(strp, fmt, ap);
    va_end(ap);
    return ret;
}
#endif
COMPATEOF
    WIN_COMPAT_DEFS="${WIN_COMPAT_DEFS} -include ${SRC_DIR}/win_compat.h"
    # __GNUC__ makes PostgreSQL use GCC-style atomics (which clang supports)
    # instead of MSVC atomics that pull in <intrin.h> with broken MMX types.
    # Only set for C (not C++) to avoid conflicts with MSVC C++ STL headers.
    export CFLAGS="${WIN_COMPAT_DEFS} -D__GNUC__=4 ${CFLAGS}"
    # MSVC C++ STL headers require C++14 or later.
    # -mno-mmx prevents __MMX__ from being defined, which stops immintrin.h
    # from including mmintrin.h. Clang 21's mmintrin.h uses GNU C compound
    # vector literals that are not valid C++; on Windows SDK 10.0.26100.0+,
    # wchar.h pulls in intrin.h -> mmintrin.h through the MSVC STL chain
    # (algorithm -> __msvc_heap_algorithms.hpp -> xutility -> cwchar -> wchar.h).
    # PostGIS and FlatBuffers do not use MMX intrinsics directly, so this is safe.
    export CXXFLAGS="${WIN_COMPAT_DEFS} -std=c++17 -mno-mmx ${CXXFLAGS}"
    export CPPFLAGS="${WIN_COMPAT_DEFS} ${CPPFLAGS}"
fi


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

# On Windows, pg_config --cc returns cl.exe and --cflags returns MSVC flags,
# but we're building with clang via autotools_clang_conda. Create a wrapper
# pg_config that overrides --cc and --cflags to use our clang compiler.
if [[ "${target_platform}" == win-* ]]; then
    PG_CONFIG_REAL=${PREFIX}/bin/pg_config
    PG_CONFIG_WRAPPER=${SRC_DIR}/pg_config_wrapper.sh
    cat > ${PG_CONFIG_WRAPPER} <<'PGEOF'
#!/bin/bash
case "$1" in
    --cc)  echo "clang.exe" ;;
    --cflags) echo "$CFLAGS" ;;
    --ldflags) echo "$LDFLAGS" ;;
    *) exec "$PG_CONFIG_REAL" "$@" ;;
esac
PGEOF
    chmod +x ${PG_CONFIG_WRAPPER}
    # Export so the wrapper's inner exec can find the real pg_config
    export PG_CONFIG_REAL
    PG_CONFIG_OPT="--with-pgconfig=${PG_CONFIG_WRAPPER}"
else
    PG_CONFIG_OPT="--with-pgconfig=${PREFIX}/bin/pg_config"
fi

CONFIGURE_EXTRA_ARGS=""
if [[ "${target_platform}" == win-* ]]; then
    # Specify PROJ directory directly to avoid pkg-config dependency chain issues
    CONFIGURE_EXTRA_ARGS="--with-projdir=${PREFIX}"

    # gdal-config was generated for MSVC (uses -LIBPATH: and bare lib names).
    # Create a wrapper that translates output to clang/lld-link compatible flags.
    GDAL_CONFIG_REAL=${PREFIX}/bin/gdal-config.real
    cp ${PREFIX}/bin/gdal-config ${GDAL_CONFIG_REAL}
    # Fix the nested quotes issue in the real script so it can be sourced
    perl -i -pe '
        if (/^(CONFIG_DEP_LIBS|CONFIG_LIBS)=/) {
            s/^([^=]+=)//;
            my $key = $1;
            s/"//g;
            chomp;
            $_ = "${key}\"${_}\"\n";
        }
    ' ${GDAL_CONFIG_REAL}

    GDAL_CONFIG_WRAPPER=${SRC_DIR}/gdal_config_wrapper.sh
    cat > ${GDAL_CONFIG_WRAPPER} <<'GDALEOF'
#!/bin/bash
case "$1" in
    --libs)
        echo "-L${PREFIX}/lib -lgdal"
        ;;
    --dep-libs)
        echo ""
        ;;
    --ogr-enabled)
        echo "yes"
        ;;
    *)
        exec bash "$GDAL_CONFIG_REAL" "$@"
        ;;
esac
GDALEOF
    chmod +x ${GDAL_CONFIG_WRAPPER}
    export GDAL_CONFIG_REAL
    GDAL_CONFIG_OPT="--with-gdalconfig=${GDAL_CONFIG_WRAPPER}"
fi

if [[ "${target_platform}" != win-* ]]; then
    GDAL_CONFIG_OPT="--with-gdalconfig=${PREFIX}/bin/gdal-config"
fi

# On Windows, patch PGXS Makefile.global to use clang instead of cl.exe
# and remove MSVC-specific compiler flags
if [[ "${target_platform}" == win-* ]]; then
    pgxs_makefile="${PREFIX}/lib/pgxs/src/Makefile.global"
    if [[ -f "${pgxs_makefile}" ]]; then
        # Replace cl.exe with clang.exe and convert MSVC-style flags to clang
        perl -i.bak -pe '
            s/^CC = cl\.exe/CC = clang.exe/;
            s/^CFLAGS_SL =.*/CFLAGS_SL =/;
            # Remove MSVC-specific flags
            s| /wd\d+||g;
            s| /MD||g;
            s| /nologo||g;
            # Convert /D defines to -D
            s| /D(\S+)| -D$1|g;
            # Convert /I includes to -I
            s| /I(\S+)| -I$1|g;
            # Remove MSVC link flags
            s| /INCREMENTAL:NO||g;
            s| /STACK:\d+||g;
            s| /NOEXP||g;
        ' "${pgxs_makefile}"
    fi
fi

if [[ "${CONDA_BUILD_CROSS_COMPILATION:-0}" == "1" ]] || [[ -n "${build_platform:-}" && -n "${target_platform:-}" && "${build_platform}" != "${target_platform}" ]]; then
    pg_config_wrapper="${SRC_DIR:-$PWD}/pg_config.wrapper"
    pgxs_makefile="${PREFIX}/lib/pgxs/src/Makefile.global"

    cp ${RECIPE_DIR}/pg_config.wrapper "${pg_config_wrapper}"

    chmod +x "${pg_config_wrapper}"
    PG_CONFIG_OPT="--with-pgconfig=${pg_config_wrapper}"

    if [[ ! -f "${pgxs_makefile}" ]]; then
        echo "PGXS Makefile not found at ${pgxs_makefile}" >&2
        exit 1
    fi

    pgxs_global="${pgxs_makefile}"
    pgxs_mk="${PREFIX}/lib/pgxs/src/makefiles/pgxs.mk"

    awk '
        $0 ~ /^-?include[[:space:]].*Makefile\.port/ { next }
        { print }
        END { print "include ${PREFIX}/lib/pgxs/src/Makefile.port" }
    ' "${pgxs_global}" > "${pgxs_global}.tmp"
    mv "${pgxs_global}.tmp" "${pgxs_global}"

    echo "==== PGXS Makefile.global (start) ===="
    sed -n '1,140p' "${pgxs_global}"
    echo "==== PGXS Makefile.global (end) ===="
    if [[ -f "${pgxs_mk}" ]]; then
        echo "==== pgxs.mk (start) ===="
        sed -n '1,140p' "${pgxs_mk}"
        echo "==== pgxs.mk (end) ===="
    fi
fi

./configure \
    --prefix=${PREFIX} \
    --libdir=${PREFIX}/lib \
    --includedir=${PREFIX}/include \
    --with-geosconfig=$PREFIX/bin/geos-config \
    ${PG_CONFIG_OPT} \
    ${GDAL_CONFIG_OPT} \
    --with-xml2config=${PREFIX}/bin/xml2-config \
    --with-libiconv-prefix=${PREFIX} \
    --with-libintl-prefix=${PREFIX} \
    --with-gettext \
    --with-raster \
    --with-topology \
    --disable-nls \
    --without-interrupt-tests \
    --without-protobuf \
    ${CONFIGURE_EXTRA_ARGS} \
    || (cat config.log && exit 1)

# On Windows, libtool produces liblwgeom.lib instead of liblwgeom.a, but the
# Makefiles hardcode the .a extension. Fix references in all generated Makefiles.
if [[ "${target_platform}" == win-* ]]; then
    # Avoid find | xargs sed for the same exec() size reason
    perl -MFile::Find -e '
        my @files;
        find(sub { push @files, $File::Find::name if -f && $_ eq "Makefile" }, ".");
        $^I = "";
        @ARGV = @files;
        while (<>) {
            s|liblwgeom/\.libs/liblwgeom\.a|liblwgeom/.libs/liblwgeom.lib|g;
            print;
        }
    '
fi
# Ensure upgrade SQL exists for utils/postgis_restore_data.generated
make -C postgis postgis_upgrade.sql

make -j$CPU_COUNT

# Only one test is failing on macOS and Linux.
# commenting this for now until we have a new release.
# start_db
# make check
# stop_db

# Unset SCRIPTS to prevent conda's SCRIPTS env var from being interpreted
# by PGXS's pgxs.mk as a list of scripts to install.
unset SCRIPTS
make install
