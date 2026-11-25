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
ignore the stamps for the selected recipes (and their prerequisites). To make a
single recipe eligible again without forcing its dependencies, remove
`work/stamps/NAME`. To change a source version, edit its registration and use a
new `ROOT` (or remove `work/sources/NAME` and `work/downloads/NAME.tar`), because
existing source locks are not updated implicitly. Do not move an existing
prefix: `.pc` files and build systems contain absolute paths.

## Compatibility and verification

I haven't performed extensive testing of the resulting ffmpeg build but it seems
to work fine for making h264/aac mp4's.

The feature set includes deprecated `libmfx` and legacy XAVS/DAVS2/XAVS2/Xvid/ZVBI
libraries. `libmfx` is deliberately retained rather than replaced with libvpl;
FFmpeg may emit a deprecation warning. ZVBI and Flite use pinned releases plus
compatibility patches. Tesseract requires trained language data on the runtime
machine; this builder only builds the library.

**Licensing:** the requested `--enable-gpl --enable-version3 --enable-nonfree`
combination (in particular FDK-AAC) produces an FFmpeg binary that FFmpeg labels
nonredistributable. Do not treat its output as a distributable GPL binary.
Review dependency/plugin licenses separately.

## Patch provenance

The patches in `patches/` were copied from the popular
`ffmpeg-windows-build-helpers` reference (Roger Pack and contributors), whose
build script is GPLv3. The standalone builder is GPL-3.0-or-later. The Flite
patch originally targeted 2.1; its hunks also apply to the pinned 2.2 source.
These build scripts' licenses do not replace the licenses of FFmpeg or its
external dependencies.
