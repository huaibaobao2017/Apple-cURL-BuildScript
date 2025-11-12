#!/usr/bin/env bash
set -euo pipefail

CURL_VERSION=8.11.0

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
SRCDIR="$CURRENT_DIR/src"
CURL_SRC="$SRCDIR/curl-${CURL_VERSION}"
OUTPUT_DIR="$CURRENT_DIR/build/curl/$CURL_VERSION"

MIN_IOS_VERSION=14.0
MIN_TVOS_VERSION=14.0
MIN_MACOS_VERSION=11
MIN_MACOS_SILICON_VERSION=11
MIN_XROS_VERSION=1.0

abort() { echo "Error: $*" 1>&2; exit 1; }
sdkPath() { xcrun --sdk "$1" --show-sdk-path; }
doneSection() { echo; echo "Done"; echo "================================================================="; echo; }

download_cURL() {
    CURL_TARBALL="$CURRENT_DIR/curl-$CURL_VERSION.tar.gz"
    DOWNLOAD_SRC="https://curl.se/download/curl-$CURL_VERSION.tar.gz"
    if [ ! -s "$CURL_TARBALL" ]; then
        echo "Downloading cURL $CURL_VERSION from $DOWNLOAD_SRC"
        curl -L -o "$CURL_TARBALL" "$DOWNLOAD_SRC"
        doneSection
    else
        echo "cURL $CURL_VERSION tarball already exists -> $CURL_TARBALL"
    fi
}

unpack_cURL() {
    [ -f "$CURL_TARBALL" ] || abort "Source tarball missing."
    echo "Unpacking cURL \"$CURL_TARBALL\"..."
    [ -d "$SRCDIR" ] || mkdir -p "$SRCDIR"
    [ -d "$CURL_SRC" ] || (
        cd "$SRCDIR"
        tar -xzf "$CURL_TARBALL"
    )
    [ -d "$CURL_SRC" ] && echo "    ...unpacked as $CURL_SRC"
    doneSection
}

rm -rf "$CURL_SRC/CMakeCache.txt" "$CURL_SRC/CMakeFiles"

build_curl() {
    PLATFORM=$1
    ARCHS=$2
    DEPLOYMENT_TARGET=$3
    SDK=$4

    for ARCH in $ARCHS; do
        BUILD_DIR="$CURL_SRC/build_${PLATFORM}_${ARCH}"
        rm -rf "$BUILD_DIR"
        mkdir -p "$BUILD_DIR"
        cd "$BUILD_DIR"

        SYSROOT=$(sdkPath "$SDK")
        INSTALL_DIR="$OUTPUT_DIR/${PLATFORM}/${ARCH}"

        echo "Building curl $CURL_VERSION for $PLATFORM ($ARCH)..."

        cmake "$CURL_SRC" \
            -DCMAKE_SYSTEM_NAME=Darwin \
            -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
            -DCMAKE_OSX_SYSROOT="$SYSROOT" \
            -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
            -DCURL_STATICLIB=ON \
            -DCMAKE_EXE_LINKER_FLAGS="-framework SystemConfiguration -framework CoreFoundation -framework Security" \
            -DCURL_USE_SECTRANSPORT=ON \
            -DBUILD_SHARED_LIBS=OFF \
            -DBUILD_CURL_EXE=OFF \
            -DBUILD_TESTING=OFF \
            -DCURL_USE_LIBSSH2=OFF \
            -DCURL_USE_OPENSSL=OFF \
            -DUSE_NGHTTP2=OFF \
            -DUSE_BROTLI=OFF \
            -DCURL_USE_BROTLI=OFF \
            -DCURL_USE_ZLIB=OFF \
            -DCURL_USE_ZSTD=OFF \
            -DCURL_ZSTD=OFF \
            -DUSE_LIBIDN2=OFF \
            -DCURL_USE_LIBIDN2=OFF \
            -DCURL_USE_LIBPSL=OFF \
            -DUSE_LIBPSL=OFF \
            -DCURL_DISABLE_LDAP=ON \
            -DCURL_DISABLE_LDAPS=ON \
            -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR"

        cmake --build . --config Release --target install
    done
}

# Create universal libs and copy headers
create_universal() {
    PLATFORM=$1
    ARCHS=$2
    LIBNAME="libcurl.a"
    UNIVERSAL_DIR="$OUTPUT_DIR/$PLATFORM"
    mkdir -p "$UNIVERSAL_DIR/lib" "$UNIVERSAL_DIR/include"

    LIPO_ARGS=()
    for ARCH in $ARCHS; do
        LIPO_ARGS+=("$OUTPUT_DIR/$PLATFORM/$ARCH/lib/$LIBNAME")
    done

    lipo -create "${LIPO_ARGS[@]}" -output "$UNIVERSAL_DIR/lib/$LIBNAME"

    # Copy headers from first arch
    cp -r "$OUTPUT_DIR/$PLATFORM/$(echo $ARCHS | awk '{print $1}')/include/"* "$UNIVERSAL_DIR/include/"
}

download_cURL
unpack_cURL
rm -rf "$OUTPUT_DIR"

#====================
# Platform builds
#====================
# iOS
build_curl "iphoneos" "arm64" "$MIN_IOS_VERSION" "iphoneos"
build_curl "iphonesimulator" "x86_64 arm64" "$MIN_IOS_VERSION" "iphonesimulator"
create_universal "iphoneos" "arm64"
create_universal "iphonesimulator" "x86_64 arm64"

# macOS
build_curl "macosx" "x86_64 arm64" "$MIN_MACOS_VERSION" "macosx"
create_universal "macosx" "x86_64 arm64"

# tvOS
build_curl "appletvos" "arm64" "$MIN_TVOS_VERSION" "appletvos"
build_curl "appletvsimulator" "x86_64 arm64" "$MIN_TVOS_VERSION" "appletvsimulator"
create_universal "appletvos" "arm64"
create_universal "appletvsimulator" "x86_64 arm64"

# visionOS
build_curl "xros" "arm64" "$MIN_XROS_VERSION" "xros"
create_universal "xros" "arm64"

# visionOS Simulator (xrsimulator)
build_curl "xrsimulator" "arm64" "$MIN_XROS_VERSION" "xrsimulator"
create_universal "xrsimulator" "arm64"

#====================
# Create xcframework
#====================
xcodebuild -create-xcframework \
    -library "$OUTPUT_DIR/iphoneos/lib/libcurl.a" \
    -headers "$OUTPUT_DIR/iphoneos/include" \
    -library "$OUTPUT_DIR/iphonesimulator/lib/libcurl.a" \
    -headers "$OUTPUT_DIR/iphonesimulator/include" \
    -library "$OUTPUT_DIR/macosx/lib/libcurl.a" \
    -headers "$OUTPUT_DIR/macosx/include" \
    -library "$OUTPUT_DIR/appletvos/lib/libcurl.a" \
    -headers "$OUTPUT_DIR/appletvos/include" \
    -library "$OUTPUT_DIR/appletvsimulator/lib/libcurl.a" \
    -headers "$OUTPUT_DIR/appletvsimulator/include" \
    -library "$OUTPUT_DIR/xros/lib/libcurl.a" \
    -headers "$OUTPUT_DIR/xros/include" \
    -library "$OUTPUT_DIR/xrsimulator/lib/libcurl.a" \
    -headers "$OUTPUT_DIR/xrsimulator/include" \
    -output "$OUTPUT_DIR/libcurl.xcframework"

doneSection
echo "Build completed successfully!"
