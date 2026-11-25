#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Standalone Linux -> Windows builder. Does not build/install a compiler.
set -Eeuo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FFMPEG_SOURCE=${FFMPEG_SOURCE:-$(dirname "$HERE")}
ROOT=${ROOT:-$HERE/work}
TARGET=x86_64-w64-mingw32
JOBS=${JOBS:-$(nproc)}
MODE=build
REBUILD=0
ONLY=ffmpeg
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
usage() {
    printf '%s\n' 'Usage: windows-build/build.sh [--check|--list|--fetch-only|--deps-only] [--rebuild] [--only NAME[,NAME...]]' \
        '  --rebuild    Rebuild selected recipes even if already installed.' \
        'Environment: ROOT, JOBS, FFMPEG_SOURCE, MINGW_CC, MINGW_CXX, CUDA_CLANG.'
}
while (($#)); do
    case $1 in
        --check) MODE=check ;;
        --list) MODE=list ;;
        --fetch-only) MODE=fetch ;;
        --deps-only) MODE=deps ;;
        --rebuild|--force) REBUILD=1 ;;
        --only) shift; (($#)) || fail '--only needs a name'; ONLY=$1 ;;
        -h|--help) usage; exit 0 ;;
        *) fail "Unknown argument: $1" ;;
    esac
    shift
done
[[ $JOBS =~ ^[1-9][0-9]*$ ]] || fail 'JOBS must be a positive integer'
ROOT=$(realpath -m "$ROOT")
PREFIX=$ROOT/prefix
HOST_PREFIX=$ROOT/host
OUT=$ROOT/output
# No whitespace: several upstream configure scripts split compiler/path arguments.
[[ $ROOT != *[[:space:]]* && $FFMPEG_SOURCE != *[[:space:]]* ]] || fail 'Build paths must not contain whitespace'
declare -A URL KIND REF DEPS SELECTED DONE
ORDER=()
register() { local n=$1; KIND[$n]=$2; URL[$n]=$3; REF[$n]=$4; DEPS[$n]=${5:-}; ORDER+=("$n"); }
gh() { register "$1" tar "https://codeload.github.com/$2/tar.gz/$3" "$3" "${4:-}"; }
tarball() { register "$1" tar "$2" "$3" "${4:-}"; }
# Conservative release pins; legacy ports are intentionally pinned with local patches.
gh zlib madler/zlib v1.3.1
tarball bzip2 https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz 1.0.8
tarball iconv https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.17.tar.gz 1.17
gh png pnggroup/libpng v1.6.47 zlib
gh jpeg libjpeg-turbo/libjpeg-turbo 3.1.0
gh expat libexpat/libexpat R_2_7_1
# FreeType without HarfBuzz avoids the circular dependency. HarfBuzz need not use FreeType.
gh freetype freetype/freetype VER-2-13-3 'zlib bzip2 png'
gh harfbuzz harfbuzz/harfbuzz 10.4.0
gh fribidi fribidi/fribidi v1.0.16
tarball fontconfig https://www.freedesktop.org/software/fontconfig/release/fontconfig-2.15.0.tar.xz 2.15.0 'freetype expat iconv'
gh ass libass/libass 0.17.3 'freetype harfbuzz fribidi fontconfig'
gh xml2 GNOME/libxml2 v2.12.10 'zlib iconv'
tarball bluray https://download.videolan.org/pub/videolan/libbluray/1.3.4/libbluray-1.3.4.tar.bz2 1.3.4 'xml2 freetype fontconfig'
tarball bs2b https://downloads.sourceforge.net/project/bs2b/libbs2b/3.1.0/libbs2b-3.1.0.tar.gz 3.1.0
gh flite festvox/flite v2.2
gh gme libgme/game-music-emu 0.6.3 zlib
tarball gsm https://www.quut.com/gsm/gsm-1.0.22.tar.gz 1.0.22
gh ilbc TimothyGu/libilbc v2.0.2
gh modplug Konstanty/libmodplug v0.8.9.2
tarball mpg123 https://www.mpg123.de/download/mpg123-1.32.10.tar.bz2 1.32.10
tarball lame https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz 3.100 mpg123
tarball opencore https://downloads.sourceforge.net/project/opencore-amr/opencore-amr/opencore-amr-0.1.6.tar.gz 0.1.6
tarball voamr https://downloads.sourceforge.net/project/opencore-amr/vo-amrwbenc/vo-amrwbenc-0.1.3.tar.gz 0.1.3
gh opus xiph/opus v1.5.2
gh snappy google/snappy 1.2.1
gh soxr chirlu/soxr 0.1.3
gh ogg xiph/ogg v1.3.5
gh vorbis xiph/vorbis v1.3.7 ogg
gh theora xiph/theora v1.1.1 'ogg vorbis'
gh speex xiph/speex Speex-1.2.1
tarball twolame https://downloads.sourceforge.net/project/twolame/twolame/0.4.0/twolame-0.4.0.tar.gz 0.4.0
gh webp webmproject/libwebp v1.5.0 'zlib png jpeg'
gh zimg sekrit-twc/zimg release-3.0.5
tarball zvbi https://downloads.sourceforge.net/project/zapping/zvbi/0.2.35/zvbi-0.2.35.tar.bz2 0.2.35 'iconv png'
gh mysofa hoene/libmysofa v1.3.4 zlib
gh openjpeg uclouvain/openjpeg v2.5.3
gh leptonica DanBloomberg/leptonica 1.85.0 'zlib png jpeg openjpeg'
gh tesseract tesseract-ocr/tesseract 5.5.0 leptonica
gh openh264 cisco/openh264 v2.5.0
gh vmaf Netflix/vmaf v3.0.0
tarball gmp https://ftp.gnu.org/pub/gnu/gmp/gmp-6.3.0.tar.xz 6.3.0
tarball nettle https://ftp.gnu.org/pub/gnu/nettle/nettle-3.10.1.tar.gz 3.10.1 gmp
tarball tasn1 https://ftp.gnu.org/pub/gnu/libtasn1/libtasn1-4.20.0.tar.gz 4.20.0
tarball unistring https://ftp.gnu.org/pub/gnu/libunistring/libunistring-1.3.tar.xz 1.3 iconv
tarball idn2 https://ftp.gnu.org/pub/gnu/libidn/libidn2-2.3.8.tar.gz 2.3.8 'unistring iconv'
tarball gnutls https://www.gnupg.org/ftp/gcrypt/gnutls/v3.8/gnutls-3.8.9.tar.xz 3.8.9 'nettle tasn1 idn2'
gh srt Haivision/srt v1.5.4 gnutls
gh vulkan KhronosGroup/Vulkan-Headers v1.4.321
gh spirv KhronosGroup/SPIRV-Headers vulkan-sdk-1.4.321.0
gh glslang KhronosGroup/glslang 15.4.0 spirv
gh dav1d videolan/dav1d 1.5.1
gh svt AOMediaCodec/SVT-AV1 v2.3.0
# AOM uses git; its official release tags are not served by GitHub.
register aom git https://aomedia.googlesource.com/aom v3.12.1 ''
gh vpx webmproject/libvpx v1.15.0
gh nvcodec FFmpeg/nv-codec-headers n12.2.72.0
gh amf GPUOpen-LibrariesAndSDKs/AMF v1.5.3
gh mfx lu-zero/mfx_dispatch 1.35.1
gh aribcaption xqq/libaribcaption v1.1.1 'freetype fontconfig'
gh aribb24 nkoriyama/aribb24 v1.0.3 png
gh frei0r dyne/frei0r v2.3.3
gh rubberband breakfastquay/rubberband v3.3.0
# Rubber Band uses its bundled resampler/FFT, so no FFTW licensing/dependency needed.
gh vidstab georgmartius/vid.stab v1.1.1
register x264 git https://code.videolan.org/videolan/x264.git stable ''
register x265 git https://bitbucket.org/multicoreware/x265_git.git 3.6 ''
gh fdk mstorsjo/fdk-aac v2.0.3
gh avisynth AviSynth/AviSynthPlus v3.7.3
tarball xvid https://downloads.xvid.com/downloads/xvidcore-1.3.7.tar.gz 1.3.7
gh davs2 pkuvcl/davs2 1.7
gh xavs2 pkuvcl/xavs2 1.4
register xavs svn https://svn.code.sf.net/p/xavs/code/trunk HEAD ''
gh caca cacalabs/libcaca v0.99.beta20
gh sdl2 libsdl-org/SDL release-2.32.10
ALL_DEPS="${ORDER[*]}"
register ffmpeg local "$FFMPEG_SOURCE" current "$ALL_DEPS"
# The user's full configuration is embedded here; no external flag script is read.
FFMPEG_FLAGS=(
    --pkg-config=pkg-config --pkg-config-flags=--static
    --enable-version3 --disable-debug --disable-w32threads
    --enable-sdl2 --enable-ffplay
    --arch=x86_64 --target-os=mingw32 --cross-prefix=x86_64-w64-mingw32-
    --enable-libcaca --enable-gray --enable-libtesseract --enable-fontconfig
    --enable-gmp --enable-libass --enable-libbluray --enable-libbs2b
    --enable-libflite --enable-libfreetype --enable-libfribidi --enable-libgme
    --enable-libgsm --enable-libilbc --enable-libmodplug --enable-libmp3lame
    --enable-libopencore-amrnb --enable-libopencore-amrwb --enable-libopus
    --enable-libsnappy --enable-libsoxr --enable-libspeex --enable-libtheora
    --enable-libtwolame --enable-libvo-amrwbenc --enable-libvorbis --enable-libwebp
    --enable-libzimg --enable-libzvbi --enable-libmysofa --enable-libopenjpeg
    --enable-libopenh264 --enable-libvmaf --enable-libsrt --enable-libxml2
    --enable-vulkan --enable-libdav1d --enable-cuda-llvm --enable-gnutls
    --enable-libsvtav1 --enable-libvpx --enable-libaom --enable-nvenc --enable-nvdec
    --extra-libs=-lharfbuzz --extra-libs=-lm --extra-libs=-lshlwapi
    --extra-libs=-lmpg123 --extra-libs=-lpthread
    --extra-cflags=-DLIBTWOLAME_STATIC --extra-cflags=-DMODPLUG_STATIC
    --extra-cflags=-DCACA_STATIC
    --enable-amf --enable-libmfx --enable-libaribcaption
    --enable-gpl --enable-nonfree --enable-frei0r --enable-librubberband
    --enable-libvidstab --enable-libx264 --enable-libx265 --enable-libfdk-aac
    --enable-avisynth --enable-libaribb24 --enable-libxvid
    --enable-libdavs2 --enable-libxavs2 --enable-libxavs
    --extra-cflags=-mtune=generic --extra-cflags=-O3
    --enable-static --disable-shared
)
select_recipe() {
    local n=$1 d
    [[ ${KIND[$n]+yes} ]] || fail "Unknown recipe: $n (see --list)"
    [[ ${SELECTED[$n]:-} ]] && return 0
    SELECTED[$n]=1
    for d in ${DEPS[$n]}; do select_recipe "$d"; done
}
IFS=, read -ra requested <<< "$ONLY"
for n in "${requested[@]}"; do select_recipe "$n"; done
if [[ $MODE == list ]]; then
    for n in "${ORDER[@]}"; do
        [[ ${SELECTED[$n]:-} ]] || continue
        printf '%-13s %-20s %s\n' "$n" "${REF[$n]}" "${DEPS[$n]}"
    done
    exit 0
fi
# The distro POSIX threading variant supports std::thread/std::mutex. No custom GCC needed.
MINGW_CC=${MINGW_CC:-$TARGET-gcc-posix}
MINGW_CXX=${MINGW_CXX:-$TARGET-g++-posix}
CUDA_CLANG=${CUDA_CLANG:-clang}
preflight() {
    local t missing=() tmp
    if [[ $MODE == fetch ]]; then
        for t in curl git tar sha256sum flock; do command -v "$t" >/dev/null || missing+=("$t"); done
        if [[ ${SELECTED[xavs]:-} ]]; then command -v svn >/dev/null || missing+=(svn); fi
        ((${#missing[@]} == 0)) || fail "Missing download tools: ${missing[*]}"
        return 0
    fi
    for t in make cmake meson ninja nasm autoconf automake libtoolize autoreconf \
        curl git patch python3 perl pkg-config tar xz bzip2 gzip sha256sum flock \
        gcc g++ "$MINGW_CC" "$MINGW_CXX" "$TARGET-ar" "$TARGET-ranlib" "$TARGET-windres" "$TARGET-strip"; do
        command -v "$t" >/dev/null || missing+=("$t")
    done
    if [[ ${SELECTED[xavs]:-} ]]; then command -v svn >/dev/null || missing+=(svn); fi
    if [[ ${SELECTED[fontconfig]:-} || ${SELECTED[caca]:-} ]]; then command -v gperf >/dev/null || missing+=(gperf); fi
    if [[ ${SELECTED[ffmpeg]:-} ]]; then command -v "$CUDA_CLANG" >/dev/null || missing+=("$CUDA_CLANG"); fi
    ((${#missing[@]} == 0)) || fail "Missing host tools: ${missing[*]}. See windows-build/README.md."
    [[ $($MINGW_CC -dumpmachine) == "$TARGET" ]] || fail 'Wrong compiler target'
    [[ $($MINGW_CXX -dumpmachine) == "$TARGET" ]] || fail 'Wrong C++ compiler target'
    if [[ ${SELECTED[ffmpeg]:-} && $MODE == build && -e $FFMPEG_SOURCE/config.h ]]; then
        fail "Run 'make distclean' in $FFMPEG_SOURCE before the out-of-tree FFmpeg build; or use --deps-only for now"
    fi
    tmp=$(mktemp -d)
    printf '#include <thread>\n#include <mutex>\nint main(){ std::thread t([]{}); t.join(); std::mutex m; m.lock(); m.unlock(); }\n' > "$tmp/test.cpp"
    if ! "$MINGW_CXX" -static -pthread "$tmp/test.cpp" -o "$tmp/test.exe"; then
        rm -rf "$tmp"; fail 'MinGW C++ static/threading test failed; use the POSIX compiler variant'
    fi
    if [[ ${SELECTED[ffmpeg]:-} ]]; then
        [[ -x $FFMPEG_SOURCE/configure ]] || fail 'Missing FFmpeg configure'
        printf '__attribute__((global)) void test(void) {}\n' > "$tmp/test.cu"
        if ! "$CUDA_CLANG" -x cuda --cuda-device-only --cuda-gpu-arch=sm_30 -nocudainc -nocudalib -S "$tmp/test.cu" -o "$tmp/test.ptx"; then
            rm -rf "$tmp"; fail 'Clang CUDA/PTX probe failed; install a Clang with the NVPTX backend or set CUDA_CLANG'
        fi
    fi
    rm -rf "$tmp"
    printf 'Host tools and installed MinGW compiler passed preflight.\n'
}
preflight
[[ $MODE != check ]] || exit 0
mkdir -p "$ROOT" "$ROOT"/{downloads,sources,build,logs,stamps} "$PREFIX"/{include,lib/pkgconfig,share/pkgconfig,bin} "$HOST_PREFIX" "$OUT"
exec 9>"$ROOT/.lock"
flock -n 9 || fail "Another build is using $ROOT"
export CC=$(command -v "$MINGW_CC") CXX=$(command -v "$MINGW_CXX")
export AR=$TARGET-ar RANLIB=$TARGET-ranlib RC=$TARGET-windres STRIP=$TARGET-strip
export CFLAGS='-O3 -mtune=generic' CXXFLAGS='-O3 -mtune=generic'
export CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib -static"
PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig"
export PKG_CONFIG_LIBDIR PKG_CONFIG_PATH=
unset PKG_CONFIG_SYSROOT_DIR LIBRARY_PATH CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH
REAL_PKG_CONFIG=$(command -v pkg-config)
# Upstream scripts sometimes insist on using cross-prefix gcc rather than $CC.
mkdir -p "$ROOT/tool-bin"
ln -sfn "$CC" "$ROOT/tool-bin/$TARGET-gcc"
ln -sfn "$CXX" "$ROOT/tool-bin/$TARGET-g++"
# Always resolve static link dependencies (Libs.private and Requires.private).
# Without --static, autotools link lines omit e.g. libpng's zlib and fail with
# undefined deflate* references because static libraries are order-sensitive.
cat > "$ROOT/tool-bin/pkg-config" <<EOF
#!/bin/sh
exec "$REAL_PKG_CONFIG" --static "\$@"
EOF
chmod +x "$ROOT/tool-bin/pkg-config"
export PKG_CONFIG="$ROOT/tool-bin/pkg-config"
export PATH="$ROOT/tool-bin:$HOST_PREFIX/bin:$PATH"
cat > "$ROOT/toolchain.cmake" <<EOF
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR AMD64)
set(CMAKE_C_COMPILER "$CC")
set(CMAKE_CXX_COMPILER "$CXX")
set(CMAKE_RC_COMPILER "$RC")
set(CMAKE_FIND_ROOT_PATH "$PREFIX" "/usr/$TARGET")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
set(CMAKE_EXE_LINKER_FLAGS_INIT "-static")
EOF
cat > "$ROOT/meson.ini" <<EOF
[binaries]
c = '$CC'
cpp = '$CXX'
ar = '$AR'
strip = '$STRIP'
windres = '$RC'
pkg-config = 'pkg-config'
[host_machine]
system = 'windows'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
[properties]
needs_exe_wrapper = true
[built-in options]
c_args = ['-O3', '-mtune=generic', '-I$PREFIX/include']
cpp_args = ['-O3', '-mtune=generic', '-I$PREFIX/include']
c_link_args = ['-L$PREFIX/lib', '-static']
cpp_link_args = ['-L$PREFIX/lib', '-static']
EOF
BASE_HASH=$({ sha256sum "$HERE/build.sh" "$HERE"/patches/*; printf '%s\n' "$PREFIX" "$CC" "$CXX" "$CFLAGS" "$LDFLAGS"; "$CC" --version; "$CXX" --version; } | sha256sum | cut -d' ' -f1)
fetch() {
    local n=$1 dest=$ROOT/sources/$1 archive=$ROOT/downloads/$1.tar tmp
    [[ ${KIND[$n]} != local ]] || return 0
    if [[ -f $dest/.source-lock ]]; then
        if [[ ${KIND[$n]} == tar ]]; then
            (cd "$ROOT/downloads"; sha256sum -c "$dest/.source-lock")
        fi
        return 0
    fi
    # Partial downloads/checkouts are never treated as complete.
    tmp=$dest.partial
    rm -rf "$tmp"
    case ${KIND[$n]} in
        tar)
            curl --fail --location --retry 5 --connect-timeout 30 "${URL[$n]}" -o "$archive.partial"
            mv "$archive.partial" "$archive"
            mkdir -p "$tmp"
            tar -xf "$archive" --strip-components=1 -C "$tmp"
            (cd "$ROOT/downloads"; sha256sum "$n.tar") > "$tmp/.source-lock"
            ;;
        git)
            git clone --depth 1 --branch "${REF[$n]}" "${URL[$n]}" "$tmp"
            git -C "$tmp" submodule update --init --recursive --depth 1
            git -C "$tmp" rev-parse HEAD > "$tmp/.source-lock"
            ;;
        svn)
            svn checkout --non-interactive -r "${REF[$n]}" "${URL[$n]}" "$tmp"
            svn info --show-item revision "$tmp" > "$tmp/.source-lock"
            ;;
    esac
    [[ ! -e $dest ]] || fail "Incomplete source directory already exists: $dest; move it aside"
    mv "$tmp" "$dest"
}
normalize_mtimes() {
    # VirtualBox guests can step the clock backwards mid-build, making freshly
    # generated Makefile.in/configure look like they are from the future. That
    # trips automake's "newly created file is older than distributed files"
    # sanity check. A fixed past timestamp keeps generated files ordered.
    find "${1:-.}" -exec touch -h -d '2000-01-01 00:00:00' {} +
}
auto() {
    local sub=${1:-.}; shift || true
    cd "$WORK/$sub"
    if [[ ! -f configure ]]; then
        # Do not run project autogen scripts: some configure/run host tests automatically.
        # Some trees keep macros in m4/ without advertising them in Makefile.am.
        local -a ar=(autoreconf -fiv)
        [[ ! -d m4 ]] || ar+=(-I m4)
        "${ar[@]}"
    fi
    normalize_mtimes .
    ./configure --build="$(gcc -dumpmachine)" --host="$TARGET" --prefix="$PREFIX" --libdir="$PREFIX/lib" --disable-shared --enable-static "$@"
    make -j"$JOBS"
    make install
}
cm() {
    local sub=${1:-.}; shift || true
    cmake -S "$WORK/$sub" -B "$WORK/_cmake" -G Ninja -DCMAKE_TOOLCHAIN_FILE="$ROOT/toolchain.cmake" \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF "$@"
    cmake --build "$WORK/_cmake" -j "$JOBS"
    cmake --install "$WORK/_cmake"
}
ms() {
    local sub=${1:-.}; shift || true
    meson setup "$WORK/_meson" "$WORK/$sub" --cross-file="$ROOT/meson.ini" --prefix="$PREFIX" --libdir=lib \
        --buildtype=release --default-library=static --wrap-mode=nodownload "$@"
    ninja -C "$WORK/_meson" -j "$JOBS"
    ninja -C "$WORK/_meson" install
}
local_patch() { (cd "$WORK/${2:-.}"; patch --batch --forward -p0 < "$HERE/patches/$1"); }
pc() {
    local name=$1 version=$2 libs=$3 requires=${4:-} cflags=${5:-}
    cat > "$PREFIX/lib/pkgconfig/$name.pc" <<EOF
prefix=$PREFIX
libdir=\${prefix}/lib
includedir=\${prefix}/include
Name: $name
Description: Windows static build of $name
Version: $version
Libs: -L\${libdir} $libs
Requires.private: $requires
Cflags: -I\${includedir} $cflags
EOF
}
recipe() {
    case $1 in
        zlib) cd "$WORK"; ./configure --prefix="$PREFIX" --static; make -j"$JOBS"; make install ;;
        bzip2) cd "$WORK"; make -j"$JOBS" CC="$CC" AR="$AR" RANLIB="$RANLIB" libbz2.a; install -m644 bzlib.h "$PREFIX/include/"; install -m644 libbz2.a "$PREFIX/lib/" ;;
        iconv) auto . --disable-nls ;;
        png) cm . -DPNG_SHARED=OFF -DPNG_STATIC=ON -DPNG_TESTS=OFF -DPNG_TOOLS=OFF ;;
        jpeg) cm . -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DWITH_TOOLS=OFF -DWITH_TESTS=OFF ;;
        expat) cm expat -DEXPAT_SHARED_LIBS=OFF -DEXPAT_BUILD_TOOLS=OFF -DEXPAT_BUILD_EXAMPLES=OFF -DEXPAT_BUILD_TESTS=OFF ;;
        freetype) cm . -DFT_DISABLE_HARFBUZZ=ON -DFT_DISABLE_BROTLI=ON ;;
        harfbuzz) ms . -Dglib=disabled -Dgobject=disabled -Dcairo=disabled -Dicu=disabled -Dfreetype=disabled -Dtests=disabled -Dutilities=disabled ;;
        fribidi) ms . -Ddocs=false -Dtests=false -Dbin=false ;;
        fontconfig) auto . --disable-docs --disable-nls ;;
        ass) auto . --disable-test ;;
        xml2) cm . -DLIBXML2_WITH_PYTHON=OFF -DLIBXML2_WITH_PROGRAMS=OFF -DLIBXML2_WITH_TESTS=OFF -DLIBXML2_WITH_LZMA=OFF -DLIBXML2_WITH_HTTP=OFF -DLIBXML2_WITH_FTP=OFF ;;
        bluray)
            auto . --disable-examples --disable-bdjava-jar
            # libbluray's Windows build leaves BD_PRIVATE symbols global, and
            # its generic dec_init() collides with FFmpeg's fftools dec_init().
            # These are internal to libbluray, so give them a private prefix.
            "$TARGET-objcopy" \
                --redefine-sym dec_init=bluray_dec_init \
                --redefine-sym dec_close=bluray_dec_close \
                --redefine-sym dec_data=bluray_dec_data \
                --redefine-sym dec_disc_id=bluray_dec_disc_id \
                --redefine-sym dec_start=bluray_dec_start \
                --redefine-sym dec_title=bluray_dec_title \
                --redefine-sym dec_application=bluray_dec_application \
                --redefine-sym dec_open_stream=bluray_dec_open_stream \
                "$PREFIX/lib/libbluray.a"
            ;;
        bs2b)
            cd "$WORK"
            # Ancient AC_FUNC_MALLOC misdetects cross malloc and substitutes rpl_malloc.
            python3 - <<'PY'
from pathlib import Path
p = Path('configure.ac')
s = p.read_text().replace('AC_FUNC_MALLOC', '').replace('dist-lzma', 'dist-xz')
check = '''PKG_CHECK_EXISTS([sndfile], [], [
    AC_MSG_ERROR(Please install libsndfile.)
])'''
assert check in s
p.write_text(s.replace(check, ''))
p = Path('src/Makefile.am')
s = p.read_text()
start = s.index('bin_PROGRAMS =')
end = s.index('bs2b_HEADERS =', start)
s = s[:start] + s[end:]
s = s[:s.index('bs2bconvert_LDADD =')]
p.write_text(s)
PY
            autoreconf -fiv
            LIBS=-lm auto .
            ;;
        flite)
            local_patch flite-2.1.0_mingw-w64-fixes.patch
            cd "$WORK"; ./configure --host="$TARGET" --prefix="$PREFIX"
            # Do not build/install target command-line tools; FFmpeg only needs these libraries.
            make -j1
            install -d "$PREFIX/include/flite"
            cp include/*.h "$PREFIX/include/flite/"
            cp build/*/lib/libflite*.a "$PREFIX/lib/"
            ;;
        gme) cm . -DENABLE_UBSAN=OFF -DBUILD_SHARED_LIBS=OFF ;;
        gsm)
            cd "$WORK"; make -j"$JOBS" CC="$CC" AR="$AR" RANLIB="$RANLIB" CFLAGS="-c $CFLAGS -DNeedFunctionPrototypes=1 -DSASR -DWAV49 -I./inc" lib/libgsm.a
            install -m644 inc/gsm.h "$PREFIX/include/"; install -m644 lib/libgsm.a "$PREFIX/lib/"
            ;;
        ilbc) auto . ;;
        modplug) auto . ;;
        mpg123) auto . --disable-components --enable-libmpg123 --disable-programs ;;
        lame)
            # LAME 3.100 contains an obsolete vector API that GCC 13 rejects.
            cd "$WORK"; python3 - <<'PY'
from pathlib import Path
p = Path('configure')
p.write_text(p.read_text().replace('xmmintrin.h', 'lame_disabled_xmmintrin.h'))
PY
            auto . --disable-frontend --disable-nasm
            ;;
        opencore|voamr|zimg|fdk|aribb24) auto . ;;
        opus) cm . -DOPUS_BUILD_PROGRAMS=OFF -DOPUS_BUILD_TESTING=OFF ;;
        snappy) cm . -DSNAPPY_BUILD_TESTS=OFF -DSNAPPY_BUILD_BENCHMARKS=OFF ;;
        soxr) cm . -DWITH_OPENMP=OFF -DBUILD_TESTS=OFF -DBUILD_EXAMPLES=OFF -DHAVE_WORDS_BIGENDIAN_EXITCODE=0 ;;
        ogg) cm . ;;
        vorbis) cm . ;;
        theora) auto . --disable-doc --disable-spec --disable-examples --disable-asm --disable-oggtest --disable-vorbistest ;;
        speex) auto . --disable-binaries ;;
        twolame) auto . --disable-sndfile ;;
        webp) cm . -DWEBP_BUILD_ANIM_UTILS=OFF -DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF -DWEBP_BUILD_GIF2WEBP=OFF -DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF -DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_EXTRAS=OFF ;;
        zvbi)
            local_patch zvbi-win32.patch
            local_patch zvbi-no-contrib.diff
            local_patch zvbi-aarch64.patch
            auto . --disable-dvb --disable-bktr --disable-proxy --disable-nls --without-doxygen --without-libiconv-prefix
            ;;
        mysofa) cm . -DBUILD_TESTS=OFF -DBUILD_SHARED_LIBS=OFF ;;
        openjpeg) cm . -DBUILD_CODEC=OFF -DBUILD_SHARED_LIBS=OFF ;;
        leptonica)
            cm . -DBUILD_PROG=OFF -DSW_BUILD=OFF
            # Leptonica installs lept_Release.pc, but consumers (including
            # tesseract's CMake and our tesseract.pc) ask for 'lept'.
            local lept_pc
            lept_pc=$(find "$PREFIX/lib/pkgconfig" -maxdepth 1 -type f -name 'lept_*.pc' | head -n 1)
            [[ -n $lept_pc ]] || fail 'leptonica did not install a pkg-config file'
            cp -f "$lept_pc" "$PREFIX/lib/pkgconfig/lept.pc"
            ;;
        tesseract)
            cd "$WORK"
            # Upstream hard-codes the Windows import library as Ws2_32; MinGW's
            # case-sensitive cross linker only ships libws2_32.a.
            python3 - <<'PY'
from pathlib import Path
p = Path('CMakeLists.txt')
s = p.read_text()
old = 'set(LIB_Ws2_32 Ws2_32)'
assert old in s
p.write_text(s.replace(old, 'set(LIB_Ws2_32 ws2_32)'))
PY
            # leptonica's exported CMake config references undefined WebP/OpenJPEG
            # targets; force pkg-config. No libtiff is built, so disable TIFF.
            cm . -DSW_BUILD=OFF -DBUILD_TRAINING_TOOLS=OFF -DBUILD_TESTS=OFF -DDISABLE_CURL=ON -DDISABLE_ARCHIVE=ON -DOPENMP_BUILD=OFF \
                -DCMAKE_DISABLE_FIND_PACKAGE_Leptonica=ON -DDISABLE_TIFF=ON -DLEPT_TIFF_RESULT=1
            pc tesseract 5.5.0 '-ltesseract -lstdc++ -lws2_32' lept
            # CMake names the archive libtesseract55.a; pkg-config/FFmpeg ask
            # for -ltesseract.
            if [[ ! -e "$PREFIX/lib/libtesseract.a" ]]; then
                local tlib
                tlib=$(find "$PREFIX/lib" -maxdepth 1 -type f -name 'libtesseract*.a' | head -n 1)
                [[ -n $tlib ]] || fail 'tesseract did not install a static library'
                ln -s "${tlib##*/}" "$PREFIX/lib/libtesseract.a"
            fi
            ;;
        openh264)
            cd "$WORK"; make -j"$JOBS" OS=mingw_nt ARCH=x86_64 CC="$CC" CXX="$CXX" AR="$AR" ASM=nasm PREFIX="$PREFIX" install-static
            ;;
        vmaf) ms libvmaf -Denable_tests=false -Denable_docs=false -Denable_avx512=false ;;
        gmp) CC_FOR_BUILD=gcc CPP_FOR_BUILD=cpp auto . ABI=64 --disable-cxx ;;
        nettle) auto . --disable-openssl --disable-documentation ;;
        tasn1) auto . --disable-doc --disable-gtk-doc --disable-tools ;;
        unistring|idn2) auto . --disable-doc ;;
        gnutls)
            auto . --disable-doc --disable-tools --disable-cxx --disable-tests --disable-nls --disable-guile --without-p11-kit --disable-libdane --with-default-trust-store-pkcs11= --with-included-unistring=no
            ;;
        srt)
            cm . -DUSE_ENCLIB=gnutls -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DENABLE_APPS=OFF -DENABLE_TESTING=OFF
            pc srt 1.5.4 '-lsrt -lstdc++ -lws2_32 -liphlpapi' gnutls
            ;;
        vulkan|spirv) cm . ;;
        glslang)
            # Build a Linux executable, NOT a Windows shader compiler.
            env -u CC -u CXX -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS \
                cmake -S "$WORK" -B "$WORK/_host" -G Ninja -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ \
                -DCMAKE_INSTALL_PREFIX="$HOST_PREFIX" -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF \
                -DENABLE_OPT=OFF -DENABLE_GLSLANG_BINARIES=ON -DGLSLANG_TESTS=OFF
            cmake --build "$WORK/_host" -j "$JOBS"; cmake --install "$WORK/_host"
            ;;
        dav1d) ms . -Denable_tests=false -Denable_tools=false ;;
        svt) cm . -DBUILD_APPS=OFF -DBUILD_DEC=OFF ;;
        aom) cm . -DENABLE_TESTS=OFF -DENABLE_EXAMPLES=OFF -DENABLE_TOOLS=OFF -DAOM_TARGET_CPU=x86_64 ;;
        vpx)
            cd "$WORK"; CROSS="$TARGET-" ./configure --target=x86_64-win64-gcc --prefix="$PREFIX" --enable-static --disable-shared --disable-examples --disable-tools --disable-docs --disable-unit-tests --enable-vp9-highbitdepth
            make -j"$JOBS"; make install
            ;;
        nvcodec) make -C "$WORK" PREFIX="$PREFIX" install ;;
        amf)
            # Replace rather than merge so a version bump cannot leave stale headers.
            rm -rf "$PREFIX/include/AMF"
            mkdir -p "$PREFIX/include/AMF"
            cp -a "$WORK/amf/public/include/." "$PREFIX/include/AMF/"
            ;;
        mfx) auto . ;;
        aribcaption) cm . -DARIBCC_BUILD_TESTS=OFF ;;
        frei0r) cm . -DWITHOUT_OPENCV=ON ;;
        rubberband) ms . -Dfft=builtin -Dresampler=builtin -Dtests=disabled -Dcmdline=disabled -Dladspa=disabled -Dlv2=disabled -Dvamp=disabled ;;
        vidstab) cm . -DUSE_OMP=OFF ;;
        x264)
            cd "$WORK"; ./configure --host="$TARGET" --cross-prefix="$TARGET-" --prefix="$PREFIX" --enable-static --disable-cli --disable-opencl --bit-depth=all
            make -j"$JOBS"; make install
            ;;
        x265)
            # All three bit depths, with a single combined archive for FFmpeg.
            local bits extra
            for bits in 12 10; do
                extra=OFF; [[ $bits != 12 ]] || extra=ON
                cmake -S "$WORK/source" -B "$WORK/b$bits" -G Ninja -DCMAKE_TOOLCHAIN_FILE="$ROOT/toolchain.cmake" \
                    -DCMAKE_BUILD_TYPE=Release -DENABLE_SHARED=OFF -DENABLE_CLI=OFF -DHIGH_BIT_DEPTH=ON -DMAIN12="$extra" -DEXPORT_C_API=OFF
                cmake --build "$WORK/b$bits" -j "$JOBS"
            done
            cmake -S "$WORK/source" -B "$WORK/b8" -G Ninja -DCMAKE_TOOLCHAIN_FILE="$ROOT/toolchain.cmake" \
                -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_BUILD_TYPE=Release -DENABLE_SHARED=OFF -DENABLE_CLI=OFF \
                -DLINKED_10BIT=ON -DLINKED_12BIT=ON "-DEXTRA_LIB=$WORK/b10/libx265.a;$WORK/b12/libx265.a"
            cmake --build "$WORK/b8" -j "$JOBS"
            mv "$WORK/b8/libx265.a" "$WORK/b8/libx265_main.a"
            (cd "$WORK/b8"; "$AR" -M <<EOF
CREATE libx265.a
ADDLIB libx265_main.a
ADDLIB $WORK/b10/libx265.a
ADDLIB $WORK/b12/libx265.a
SAVE
END
EOF
            )
            cmake --install "$WORK/b8"
            pc x265 3.6 '-lx265 -lstdc++ -lm -lpthread'
            ;;
        avisynth)
            # In headers-only mode version.h is generated by a custom target that
            # is not part of the default build, yet install() expects it.
            cmake -S "$WORK" -B "$WORK/_cmake" -G Ninja -DCMAKE_TOOLCHAIN_FILE="$ROOT/toolchain.cmake" \
                -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_BUILD_TYPE=Release \
                -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF -DHEADERS_ONLY=ON
            cmake --build "$WORK/_cmake" --target VersionGen
            cmake --install "$WORK/_cmake"
            ;;
        xvid)
            local_patch xvidcore-1.3.7_static-lib.patch build/generic
            cd "$WORK/build/generic"; ./configure --host="$TARGET" --prefix="$PREFIX"
            make -j"$JOBS"; make install
            ;;
        davs2|xavs2)
            cd "$WORK/build/linux"; ./configure --host="$TARGET" --cross-prefix="$TARGET-" --prefix="$PREFIX" --enable-pic
            make -j"$JOBS"; make install
            ;;
        xavs)
            cd "$WORK"; ./configure --host="$TARGET" --cross-prefix="$TARGET-" --prefix="$PREFIX"
            make -j"$JOBS" CC="$CC" AR="$AR" RANLIB="$RANLIB"; make install
            ;;
        sdl2)
            # Static SDL2 + SDL2main so ffplay.exe needs no SDL2.dll at runtime.
            cm . -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TEST=OFF -DSDL_TESTS=OFF \
                -DSDL_INSTALL_TESTS=OFF -DSDL2_DISABLE_SDL2MAIN=OFF
            ;;
        caca)
            cd "$WORK"
            # Static build: without CACA_STATIC the public headers use dllimport
            # and even libcaca's own noinst programs fail to link. caca0.h lacks
            # the CACA_STATIC check that caca.h has.
            python3 - <<'PY'
from pathlib import Path
p = Path('caca/caca0.h')
s = p.read_text()
old = '#elif defined _WIN32 && !defined __LIBCACA__\n'
assert old in s
p.write_text(s.replace(old, '#elif defined _WIN32 && !defined __LIBCACA__ && !defined CACA_STATIC\n', 1))
PY
            export CPPFLAGS="$CPPFLAGS -DCACA_STATIC"
            auto . --disable-csharp --disable-java --disable-cxx --disable-python --disable-ruby --disable-doc --disable-cocoa --disable-ncurses --disable-imlib2 --disable-x11 --disable-gl
            ;;
        ffmpeg) build_ffmpeg ;;
        *) fail "No implementation for $1" ;;
    esac
}
build_ffmpeg() {
    # FFmpeg forbids an out-of-tree build when its source tree contains config.h.
    [[ ! -e $FFMPEG_SOURCE/config.h ]] || fail "Source tree is configured. Run 'make distclean' in $FFMPEG_SOURCE first (this builder will not clean your checkout)."
    cd "$WORK"
    "$FFMPEG_SOURCE/configure" "${FFMPEG_FLAGS[@]}" \
        --enable-cross-compile --cc="$CC" --cxx="$CXX" \
        --nvcc="$CUDA_CLANG" --glslc="$HOST_PREFIX/bin/glslang" \
        --prefix="$OUT" --extra-cflags="-I$PREFIX/include -DOPJ_STATIC -DLIBXML_STATIC -DARIBCC_STATIC" \
        --extra-ldflags="-L$PREFIX/lib -static" \
        --extra-libs='-Wl,--start-group -lharfbuzz -lmpg123 -lstdc++ -lpthread -Wl,--end-group'
    # Explicit --enable options must not be silently dropped.
    python3 - ffbuild/config.mak "${FFMPEG_FLAGS[@]}" <<'PY'
import re, sys
flags = ' '.join(sys.argv[2:])
config = open(sys.argv[1]).read()
missing = []
for feature in re.findall(r'--enable-([a-zA-Z0-9_-]+)', flags):
    if feature in {'version3', 'gpl', 'nonfree', 'static', 'gray', 'cross-compile'}:
        continue
    key = 'CONFIG_' + feature.upper().replace('-', '_')
    if not re.search(r'^' + re.escape(key) + r'=yes$', config, re.M):
        missing.append(feature)
if missing:
    sys.exit('Requested features not enabled: ' + ', '.join(missing))
PY
    make -j"$JOBS"
    make install
    local exe
    for exe in ffmpeg ffplay ffprobe; do
        [[ -f $OUT/bin/$exe.exe ]] || continue
        "$TARGET-objdump" -p "$OUT/bin/$exe.exe" | grep 'DLL Name:' > "$ROOT/logs/$exe-imports.txt"
        # Plugins, GPU drivers and AviSynth are intentionally loaded at runtime.
        if grep -Ei 'DLL Name:.*(libgcc|libstdc\+\+|libwinpthread|libharfbuzz|libmpg123|SDL2)' "$ROOT/logs/$exe-imports.txt"; then
            fail "Unexpected non-system runtime DLL imports in $exe.exe; see $exe-imports.txt"
        fi
    done
}
run_recipe() {
    local n=$1 d signature
    [[ ${DONE[$n]:-} ]] && return 0
    for d in ${DEPS[$n]}; do run_recipe "$d"; done
    DONE[$n]=1
    [[ $MODE != deps || $n != ffmpeg ]] || return 0
    # Successful installs are sticky by default: rerunning after a builder or
    # source change must not redo hours of dependency work. Use --rebuild to
    # deliberately discard stamps and rebuild the selected recipes.
    if [[ $MODE != fetch && $REBUILD == 0 && -f $ROOT/stamps/$n ]]; then
        printf 'Already installed: %s (use --rebuild to force).\n' "$n"
        return 0
    fi
    printf '\n=== %s (%s) ===\n' "$n" "${REF[$n]}"
    fetch "$n" > >(tee "$ROOT/logs/$n-fetch.log") 2>&1
    [[ $MODE != fetch ]] || return 0
    if [[ $REBUILD == 1 ]]; then rm -f "$ROOT/stamps/$n"; fi
    signature=$({
        printf '%s\n' "$BASE_HASH"
        if [[ $n == ffmpeg ]]; then
            git -C "$FFMPEG_SOURCE" rev-parse HEAD
            git -C "$FFMPEG_SOURCE" diff --binary HEAD
        else
            cat "$ROOT/sources/$n/.source-lock"
        fi
        for d in ${DEPS[$n]}; do cat "$ROOT/stamps/$d"; done
    } | sha256sum | cut -d' ' -f1)
    # Only builder-owned working copies are replaced; source cache/user checkout are untouched.
    rm -rf "$ROOT/build/$n"
    mkdir -p "$ROOT/build/$n"
    if [[ $n != ffmpeg ]]; then
        cp -a "$ROOT/sources/$n/." "$ROOT/build/$n/"
        # Resist host clock jumps (common in VirtualBox) shifting file mtimes.
        normalize_mtimes "$ROOT/build/$n"
    fi
    (
        set -Eeuo pipefail
        trap 'rc=$?; printf "FAILED: %s (line %s): %s\\n" "$n" "$LINENO" "$BASH_COMMAND" >&2; exit "$rc"' ERR
        WORK=$ROOT/build/$n
        recipe "$n"
    ) > "$ROOT/logs/$n.log" 2>&1 &
    local pid=$!
    if ! wait "$pid"; then
        tail -n 60 "$ROOT/logs/$n.log" >&2
        fail "$n failed. Full log: $ROOT/logs/$n.log"
    fi
    printf '%s\n' "$signature" > "$ROOT/stamps/$n"
    printf 'Installed. Log: %s/logs/%s.log\n' "$ROOT" "$n"
}
# Recipes run as background subshells and are waited on separately: wrapping
# a function/subshell directly in `if` would disable bash errexit inside it.
for n in "${requested[@]}"; do run_recipe "$n"; done

# Make the result easy to find, including when a rerun skipped existing work.
if [[ $MODE == build && -f $ROOT/stamps/ffmpeg ]]; then
    printf '\nWindows executables:\n'
    for exe in ffmpeg ffplay ffprobe; do
        [[ ! -f $OUT/bin/$exe.exe ]] || printf '  %s\n' "$OUT/bin/$exe.exe"
    done
fi
