#!/usr/bin/env bash
#
# Variables to provide:
# CONFIGURATION = Debug | Release
# TARGET_CPU = ...
# PDFium_BRANCH = master | chromium/3211 | ...
# PDFium_V8 = enabled

set -ex

OS=$(uname)
case $OS in
MINGW*)
  OS="windows"
  ;;
*)
  OS=$(echo $OS | tr '[:upper:]' '[:lower:]')
  ;;
esac

# Input
DepotTools_URL='https://chromium.googlesource.com/chromium/tools/depot_tools.git'
DepotTools_DIR="$PWD/depot_tools"
PDFium_URL='https://pdfium.googlesource.com/pdfium.git'
PDFium_SOURCE_DIR="$PWD/pdfium"
PDFium_BUILD_DIR="$PDFium_SOURCE_DIR/out"
PDFium_PATCH_DIR="$PWD/patches"
PDFium_CMAKE_CONFIG="$PWD/PDFiumConfig.cmake"
PDFium_ARGS="$PWD/args/$OS.args.gn"
EMSDK_SOURCE_DIR="$PWD/emsdk"
WASM_SOURCE_DIR="$PWD/src"

# Output
PDFium_STAGING_DIR="$PWD/staging"
PDFium_INCLUDE_DIR="$PDFium_STAGING_DIR/include"
PDFium_LIB_DIR="$PDFium_STAGING_DIR/lib"
PDFium_RES_DIR="$PDFium_STAGING_DIR/res"
PDFium_ARTIFACT_BASE="$PWD/pdfium-$OS"
[ "$OS" == "darwin" ] && [ "$TARGET_CPU" == "" ] && TARGET_CPU=x64
[ "$TARGET_CPU" != "" ] && PDFium_ARTIFACT_BASE="$PDFium_ARTIFACT_BASE-$TARGET_CPU"
[ "$PDFium_V8" == "enabled" ] && PDFium_ARTIFACT_BASE="$PDFium_ARTIFACT_BASE-v8"
[ "$CONFIGURATION" == "Debug" ] && PDFium_ARTIFACT_BASE="$PDFium_ARTIFACT_BASE-debug"
PDFium_ARTIFACT="$PDFium_ARTIFACT_BASE.tgz"

# Prepare directories
mkdir -p "$PDFium_BUILD_DIR"
mkdir -p "$PDFium_STAGING_DIR"
mkdir -p "$PDFium_LIB_DIR"

# Install emsdk
mkdir -p "$EMSDK_SOURCE_DIR"
cd "$EMSDK_SOURCE_DIR"
git clone https://github.com/emscripten-core/emsdk.git . 
./emsdk install 2.0.24
./emsdk activate 2.0.24
export PATH="$PATH:$EMSDK_SOURCE_DIR:$EMSDK_SOURCE_DIR/upstream/emscripten"

# Download depot_tools if not exists in this location or update utherwise
if [ ! -d "$DepotTools_DIR" ]; then
  git clone "$DepotTools_URL" "$DepotTools_DIR"
else 
  cd "$DepotTools_DIR"
  git pull
  cd ..
fi
export PATH="$DepotTools_DIR:$PATH"

# Clone
gclient config --unmanaged "$PDFium_URL"
gclient sync

# Checkout
cd "$PDFium_SOURCE_DIR"
git checkout "${PDFium_BRANCH:-master}"
gclient sync

# Patch
cd "$PDFium_SOURCE_DIR/build"
git apply -v "$PDFium_PATCH_DIR/V4634/pdfium_build.patch"
cd "$PDFium_SOURCE_DIR"
git apply -v "$PDFium_PATCH_DIR/V4634/pdfium.patch"
git apply -v "$PDFium_PATCH_DIR/V4634/pdfium_h.patch"

# Configure
cp "$PDFium_ARGS" "$PDFium_BUILD_DIR/args.gn"

# Generate Ninja files
gn gen "$PDFium_BUILD_DIR"

# Build
ninja -C "$PDFium_BUILD_DIR" pdfium
ls -l "$PDFium_BUILD_DIR"

# Install
cp "$PDFium_CMAKE_CONFIG" "$PDFium_STAGING_DIR"
cp "$PDFium_SOURCE_DIR/LICENSE" "$PDFium_STAGING_DIR"
cp "$PDFium_BUILD_DIR/obj/libpdfium.a" "$PDFium_STAGING_DIR"
cp -R "$PDFium_SOURCE_DIR/public" "$PDFium_INCLUDE_DIR"
cp "$WASM_SOURCE_DIR/custom.cpp" "$PDFium_STAGING_DIR"
cp "$WASM_SOURCE_DIR/function-names.txt" "$PDFium_STAGING_DIR"

# WASM
cd "$PDFium_STAGING_DIR"
em++ -O3 -o pdfium.html -s "EXPORTED_FUNCTIONS=`cat function-names.txt`" -s "EXPORTED_RUNTIME_METHODS=['ccall','cwrap']" custom.cpp libpdfium.a -I./include -s DEMANGLE_SUPPORT=1 -s USE_ZLIB=1 -s USE_LIBJPEG=1 -s WASM=1 -s ASSERTIONS=1 -s ALLOW_MEMORY_GROWTH=1 -std=c++11 -Wall --no-entry

# Pack
cd "$PDFium_STAGING_DIR"
tar cvzf "$PDFium_ARTIFACT" -- *
