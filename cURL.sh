#!/bin/bash

set -euo pipefail

CURL_VERSION=8.11.0

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

CURL_TARBALL="$CURRENT_DIR/curl-$CURL_VERSION.tar.gz"
SRCDIR="$CURRENT_DIR/src"
CURL_SRC="$SRCDIR/curl-${CURL_VERSION}"
CURL_SRC_CURRENT="$CURL_SRC"

OUTPUT_DIR="$CURRENT_DIR/build/curl/$CURL_VERSION"

MIN_IOS_VERSION=11.0
MIN_TVOS_VERSION=11.0
MIN_MACOS_VERSION=10.8
MIN_MACOS_SILICON_VERSION=11

#===============================================================================
# Functions
#===============================================================================

sdkVersion() {
  FULL_VERSION=$(xcrun --sdk "$1" --show-sdk-version)
  read -ra VERSION <<<"${FULL_VERSION//./ }"
  echo "${VERSION[0]}.${VERSION[1]}"
}

sdkPath() {
  xcrun --sdk "$1" --show-sdk-path
}

doneSection() {
  echo
  echo "Done"
  echo "================================================================="
  echo
}

download_cURL() {
  DOWNLOAD_SRC="https://curl.se/download/curl-$CURL_VERSION.tar.gz"
  if [ ! -s $CURL_TARBALL ]; then
    echo "Downloading cURL $CURL_VERSION from $DOWNLOAD_SRC"
    curl -O $DOWNLOAD_SRC
    doneSection
  else
    echo "cURL $CURL_VERSION tarball already exists -> $CURL_TARBALL"
  fi
}

cd_or_abort() {
  cd "$1" || abort "Could not change directory into \"$1\""
}

unpack_cURL() {
  [ -f "$CURL_TARBALL" ] || abort "Source tarball missing."

  echo Unpacking cURL "$CURL_TARBALL" into "$SRCDIR"...

  [ -d "$SRCDIR" ] || mkdir -p "$SRCDIR"
  [ -d "$CURL_SRC" ] || (
    cd_or_abort "$SRCDIR"
    tar -xzf "$CURL_TARBALL"
  )
  [ -d "$CURL_SRC" ] && echo "    ...unpacked as $CURL_SRC"

  doneSection
}

build() {
  ARCH=$1
  HOST=$2
  SDK=$3
  DEPLOYMENT_TARGET=$4
  SDK_PATH=$(sdkPath $SDK)

  cd_or_abort "$CURL_SRC_CURRENT"

  export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -isysroot ${SDK_PATH} -m${SDK}-version-min=${DEPLOYMENT_TARGET} -fembed-bitcode -Werror=partial-availability"
  export LDFLAGS="-arch ${ARCH} -isysroot ${SDK_PATH}"

  echo "Building variant -> CFLAGS=$CFLAGS"

  echo "Configuring cURL for ${ARCH} ${SDK} with ${HOST}"

  ./configure \
    --host="${HOST}" \
    --prefix "${OUTPUT_DIR}/${ARCH}-${SDK}" \
    --disable-shared --enable-static --with-secure-transport --without-libpsl --without-libidn2 --without-nghttp2 --disable-verbose --disable-dependency-tracking --disable-ldap --disable-ldaps

  jobs=$(sysctl -n hw.logicalcpu_max)

  echo "Building cURL for ${ARCH} ${SDK} with ${jobs} jobs"

  make -j$jobs

  make install
  make clean
}

clean_build() {
  rm -rf "$OUTPUT_DIR"
  mkdir -p "$OUTPUT_DIR"
}

download_cURL
unpack_cURL
clean_build

build_iOS() {
  echo "Building cURL for iOS"
  build arm64 aarch64-apple-darwin iphoneos $MIN_IOS_VERSION

  # Create a universal library
  mkdir -p $OUTPUT_DIR/iphoneos
  lipo -arch arm64 $OUTPUT_DIR/arm64-iphoneos/lib/libcurl.a \
    -create -output $OUTPUT_DIR/iphoneos/libcurl.a

  # Copy headers
  cp -r $OUTPUT_DIR/arm64-iphoneos/include $OUTPUT_DIR/iphoneos

  doneSection
}

build_iOSSimulator() {
  echo "Building cURL for iOS Simulator"
  build arm64 aarch64-apple-darwin iphonesimulator $MIN_IOS_VERSION
  build x86_64 x86_64-apple-darwin iphonesimulator $MIN_IOS_VERSION

  # Create a universal library
  mkdir -p $OUTPUT_DIR/iphonesimulator
  lipo -arch x86_64 $OUTPUT_DIR/x86_64-iphonesimulator/lib/libcurl.a \
    -arch arm64 $OUTPUT_DIR/arm64-iphonesimulator/lib/libcurl.a \
    -create -output $OUTPUT_DIR/iphonesimulator/libcurl.a

  # Copy headers
  cp -r $OUTPUT_DIR/x86_64-iphonesimulator/include $OUTPUT_DIR/iphonesimulator

  doneSection
}

build_macOS() {
  echo "Building cURL for macOS"
  build x86_64 x86_64-apple-darwin macosx $MIN_MACOS_VERSION
  build arm64 aarch64-apple-darwin macosx $MIN_MACOS_SILICON_VERSION

  # Create a universal library
  mkdir -p $OUTPUT_DIR/macosx
  lipo -arch x86_64 $OUTPUT_DIR/x86_64-macosx/lib/libcurl.a \
    -arch arm64 $OUTPUT_DIR/arm64-macosx/lib/libcurl.a \
    -create -output $OUTPUT_DIR/macosx/libcurl.a

  # Copy headers
  cp -r $OUTPUT_DIR/x86_64-macosx/include $OUTPUT_DIR/macosx

  doneSection
}

build_tvOS() {
  echo "Building cURL for tvOS"
  build arm64 aarch64-apple-darwin appletvos $MIN_TVOS_VERSION

  # Create a universal library
  mkdir -p $OUTPUT_DIR/appletvos
  lipo -arch arm64 $OUTPUT_DIR/arm64-appletvos/lib/libcurl.a \
    -create -output $OUTPUT_DIR/appletvos/libcurl.a

  # Copy headers
  cp -r $OUTPUT_DIR/arm64-appletvos/include $OUTPUT_DIR/appletvos

  doneSection
}

build_tvOSSimulator() {
  echo "Building cURL for tvOS Simulator"
  build x86_64 x86_64-apple-darwin appletvsimulator $MIN_TVOS_VERSION
  build arm64 aarch64-apple-darwin appletvsimulator $MIN_TVOS_VERSION

  # Create a universal library
  mkdir -p $OUTPUT_DIR/appletvsimulator
  lipo -arch x86_64 $OUTPUT_DIR/x86_64-appletvsimulator/lib/libcurl.a \
    -arch arm64 $OUTPUT_DIR/arm64-appletvsimulator/lib/libcurl.a \
    -create -output $OUTPUT_DIR/appletvsimulator/libcurl.a

  # Copy headers
  cp -r $OUTPUT_DIR/x86_64-appletvsimulator/include $OUTPUT_DIR/appletvsimulator

  doneSection
}

build_iOS
build_iOSSimulator
build_macOS
build_tvOS
build_tvOSSimulator

# Create xcframework
xcodebuild -create-xcframework \
  -library $OUTPUT_DIR/iphoneos/libcurl.a \
  -headers $OUTPUT_DIR/iphoneos/include \
  -library $OUTPUT_DIR/iphonesimulator/libcurl.a \
  -headers $OUTPUT_DIR/iphonesimulator/include \
  -library $OUTPUT_DIR/macosx/libcurl.a \
  -headers $OUTPUT_DIR/macosx/include \
  -library $OUTPUT_DIR/appletvos/libcurl.a \
  -headers $OUTPUT_DIR/appletvos/include \
  -library $OUTPUT_DIR/appletvsimulator/libcurl.a \
  -headers $OUTPUT_DIR/appletvsimulator/include \
  -output $OUTPUT_DIR/curl.xcframework

doneSection

echo "Build completed successfully!"
