# Yet another FFmpeg Windows cross-compilation build script

`build.sh` is a complete Linux → 64-bit Windows cross-compilation script. It
downloads and cross-compiles all external dependencies, then builds the FFmpeg
version found in parent folder (including `ffmpeg`, `ffplay`, and `ffprobe`).
It uses the **installed** MinGW-w64 compiler; it does not build a toolchain,
run sudo, or install system packages.

It's largely based off [ffmpeg-build-helpers](https://github.com/rdp/ffmpeg-windows-build-helpers)
with LLM rewriting it to use installed MinGW-w64 and patching the many issues
discovered after like 20 build attempts (I would not have had the patience for
this).


## Basic usage

After installing prerequisites (see below), and ensuring you have **11gb**
of free space, do this to build ffmpeg 9.1 (script tested against 9.1):

```sh
git clone --depth 1 --branch n9.1 https://git.ffmpeg.org/ffmpeg.git ffmpeg
cd ffmpeg
git clone https://github.com/fuzzdeveloper/ffmpeg-windows-builder.git
JOBS=8 ./ffmpeg-windows-builder/build.sh
```

### Static vs shared FFmpeg libraries

By default FFmpeg's own libraries are linked statically into the executables.
Pass `--shared` to build them as DLLs (`avcodec-*.dll`, `avformat-*.dll`, etc.)
instead. External codec libraries are always linked statically. `--shared` is
independent of `--minimal`, so there are four possible builds:

| Command | Feature set | FFmpeg libraries |
| --- | --- | --- |
| `build.sh` | full | static |
| `build.sh --shared` | full | shared DLLs |
| `build.sh --minimal` | minimal | static |
| `build.sh --minimal --shared` | minimal | shared DLLs |

Switching between static and shared (or between profiles) automatically rebuilds
FFmpeg; the external dependencies are reused. Stale artifacts in `work/output`
are removed before the FFmpeg install so the two variants do not mix. Shipped
shared builds need the matching `av*-*.dll` files next to the executables.

### Cut-down GPLv2 build

For a smaller, GPLv2-compatible build, pass `--minimal`:

```sh
JOBS=8 ./ffmpeg-windows-builder/build.sh --minimal
```

This profile builds only `ffmpeg.exe` and `ffprobe.exe`. Add `--shared` to build
FFmpeg's own libraries as DLLs that the two executables share (copy the
executables together with `av*-*.dll` from `work/output/bin`). It includes:

- AviSynth(+) input (`--enable-avisynth`)
- H.264 via libx264, HEVC via libx265, VP8/VP9 via libvpx
- AAC via FFmpeg's built-in encoder, Opus via libopus, Vorbis via libvorbis

It deliberately does **not** use `--enable-version3`, `--enable-nonfree`, or
`--enable-libfdk-aac`. It also omits the Apache-2.0/LGPLv3 dependencies (e.g.
OpenCORE AMR, Tesseract, GMP, libaribb24) that are incompatible with GPLv2.

Static linking remains the default for every profile: a plain `--minimal` build
produces self-contained executables, while `--minimal --shared` produces
executables plus the `av*-*.dll` files. `--minimal` only changes the FFmpeg
dependency set and feature flags, not the library linkage.

## Host prerequisites (Debian/Ubuntu)

On a recent Debian/Ubuntu Linux host, copy and paste this single line to install
the host build tools and the POSIX-threading MinGW compiler variant:

```sh
sudo apt-get update && sudo apt-get install -y build-essential gcc-mingw-w64-x86-64-posix g++-mingw-w64-x86-64-posix binutils-mingw-w64-x86-64 mingw-w64-x86-64-dev git subversion curl ca-certificates pkg-config cmake meson ninja-build autoconf automake libtool libtool-bin autoconf-archive nasm yasm gperf flex bison gettext autopoint texinfo python3 perl patch tar coreutils xz-utils bzip2 gzip util-linux clang llvm
```

These are **host tools**, not Linux builds of FFmpeg's target dependencies. The
builder downloads and builds the Windows dependencies itself.

`--enable-cuda-llvm` needs a **Linux Clang executable with an NVPTX backend**.
The builder probes CUDA-to-PTX compilation; it does not download a proprietary
CUDA toolkit. Set `CUDA_CLANG=clang-18` (or another installed compatible version)
if needed. It also builds a native Linux `glslang` for FFmpeg's Vulkan shaders.
The Windows drivers, CUDA/AMF runtime, and GPU hardware are not build inputs.

Use a recent CMake/Meson and MinGW-w64. The C++ static-link/threading probe checks
that the compiler supports `std::thread` and `std::mutex`. This is why the POSIX
variant is selected instead of the distro's default win32-threading variant.

## Run

From the copied FFmpeg checkout (replace the path below):

```sh
cd /path/to/ffmpeg
chmod +x windows-build/build.sh
./windows-build/build.sh --check

# FFmpeg forbids an out-of-tree build if the source tree is already configured.
# Skip this cleanup automatically for a fresh, unconfigured checkout:
if [ -f config.h ]; then make distclean; fi

JOBS="$(nproc)" ./windows-build/build.sh
```

`make distclean` deletes generated configuration/build files, not source code.
The builder deliberately does not perform this cleanup on your behalf. You can
build dependencies first without cleaning the FFmpeg checkout:

```sh
JOBS=8 ./windows-build/build.sh --deps-only
```

Expect many hours of compilation and tens of GB of free disk space. Reduce
`JOBS` if RAM is limited. No Windows binaries are executed during the build.

Outputs (default):

- `windows-build/work/output/bin/ffmpeg.exe`, `ffplay.exe`, and `ffprobe.exe`
- with `--shared`, the FFmpeg DLLs in `windows-build/work/output/bin/`
- `windows-build/work/prefix/`: target headers, static libraries and `.pc` files
- `windows-build/work/host/`: native build tools (currently glslang)
- `windows-build/work/logs/NAME.log`: each dependency's full build log
- `windows-build/work/logs/ffmpeg-fetch.log`: FFmpeg step fetch log
- `windows-build/work/build/ffmpeg/ffbuild/config.log`: FFmpeg configure details
- `windows-build/work/logs/NAME-imports.txt`: linked DLL import list per executable

`ffplay.exe` is linked against a **static** SDL2/SDL2main, so it does not need
`SDL2.dll` at runtime. Enabling frei0r builds separate plugin DLLs under the
dependency prefix; plugins are not embedded in FFmpeg. AviSynth is headers-only
at build time and needs AviSynth installed on the Windows machine when used.

## Resuming and individual steps

```sh
# Rerun after fixing a failure; installed recipes are reused by default.
./windows-build/build.sh

# Force rebuilding the selected recipes and their prerequisites.
./windows-build/build.sh --rebuild
./windows-build/build.sh --rebuild --only harfbuzz

# Show releases and dependency graph.
./windows-build/build.sh --list

# Download sources without compiling.
./windows-build/build.sh --fetch-only

# Build an individual library and its prerequisites.
./windows-build/build.sh --only harfbuzz
./windows-build/build.sh --only srt,tesseract

# Put all generated artifacts outside this checkout.
ROOT=/mnt/aaa/ffmpeg-windows JOBS=8 ./windows-build/build.sh
```

The build prefix is isolated from host Linux `.pc` files and library search
paths. CMake and Meson get explicit cross files. Static FFmpeg libraries alone
would not guarantee static external dependencies, so the final link also uses
`-static` and the static MinGW runtimes.

Source archives are downloaded atomically and their SHA-256 checksums saved in
`.source-lock`; subsequent runs check the cached downloads. **These checksums
are recorded on first download, not preverified upstream signatures.** Downloads
use HTTPS. Git and SVN source revisions are recorded and reused without pulling
updates. Most recipes use release tags; x264's `stable` branch and the legacy
XAVS SVN `HEAD` are locked to whatever revision is fetched on the first run.
Keep the source cache/locks for repeatable rebuilds. Tags can change upstream;
this is not a hermetic/reproducible-binary build system.

Build stamps record the builder, local patches, compiler versions, prefix,
source locks, and prerequisite stamps. A non-empty `work/stamps/NAME` is treated
as **already installed** and is skipped even if those inputs changed; this avoids
rebuilding hours of dependencies after a small script edit. Pass `--rebuild` to
ignore the stamps for the selected recipes (and their prerequisites). The FFmpeg
stamp also records the profile/linkage configuration, so changing `--minimal` or
`--shared` rebuilds FFmpeg without touching the dependencies. To make a
single recipe eligible again without forcing its dependencies, remove
`work/stamps/NAME`. To change a source version, edit its registration and use a
new `ROOT` (or remove `work/sources/NAME` and `work/downloads/NAME.tar`), because
existing source locks are not updated implicitly. Do not move an existing
prefix: `.pc` files and build systems contain absolute paths.

## Compatibility and verification

I haven't performed extensive testing of the resulting ffmpeg build but it seems
to work fine for making h264/aac mp4's.

The feature set includes modern Intel oneVPL (`libvpl`), DVD-Video
(`libdvdread`/`libdvdnav`/`libdvdcss`), and legacy XAVS/DAVS2/XAVS2/Xvid/ZVBI
libraries. `libdvdcss` is included so CSS-encrypted commercial DVDs can be
decrypted; review the relevant local laws before distributing it. ZVBI and Flite
use pinned releases plus compatibility patches. Tesseract requires trained
language data on the runtime machine; this builder only builds the library.

**Licensing:** the default full profile requests `--enable-gpl --enable-version3
--enable-nonfree` (in particular FDK-AAC), which produces an FFmpeg binary that
FFmpeg labels nonredistributable. Do not treat its output as a distributable
GPL binary. Review dependency/plugin licenses separately.

The `--minimal` profile is intended for GPLv2 distribution: it uses `--enable-gpl`
without `--enable-version3` or `--enable-nonfree`, so FFmpeg is GPLv2-or-later.
libx264, libx265, and AviSynth are GPLv2-compatible; libvpx, libopus, and
libvorbis are BSD-licensed; the native AAC encoder is LGPLv2.1+. No FDK-AAC is
included. You still have to comply with the GPL when distributing the binaries
(including providing the corresponding source for FFmpeg, libx264 and libx265).
The GPL-3.0-or-later licence of this build script itself does not change the
licence of the binaries it produces; keep the script as a separate build tool and
do not relicense it as GPLv2 if you redistribute it.

## Patch provenance

The patches in `patches/` were copied from the popular
`ffmpeg-windows-build-helpers` reference (Roger Pack and contributors), whose
build script is GPLv3. The standalone builder is GPL-3.0-or-later. The Flite
patch originally targeted 2.1; its hunks also apply to the pinned 2.2 source.
These build scripts' licenses do not replace the licenses of FFmpeg or its
external dependencies.
