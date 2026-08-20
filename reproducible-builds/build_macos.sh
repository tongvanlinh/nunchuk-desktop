#!/usr/bin/env bash
set -euo pipefail

: "${BUILD_VERSION:?BUILD_VERSION is required}"
: "${QTPATH:?QTPATH is required}"

PROJECT_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)"
TEMP_ROOT="${RUNNER_TEMP:-/tmp}/nunchuk-macos-build"
DEPS_ROOT="$TEMP_ROOT/deps"
SOURCE_ROOT="$TEMP_ROOT/sources"
BUILD_ROOT="$PROJECT_ROOT/build-reproducible-macos"
APP_PATH="$BUILD_ROOT/Nunchuk.app"
DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-13.0}"
CORES="$(sysctl -n hw.ncpu)"

case "$BUILD_VERSION" in
    ''|*[!A-Za-z0-9._+-]*)
        echo "Invalid build version: $BUILD_VERSION" >&2
        exit 1
        ;;
esac
CMAKE_APP_VERSION="$(sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+).*/\1/' <<< "$BUILD_VERSION")"

for command_name in \
    cmake curl file git install_name_tool make macdeployqt otool python3 shasum tar; do
    command -v "$command_name" >/dev/null || {
        echo "Missing macOS build tool: $command_name" >&2
        exit 1
    }
done

rm -rf -- "$TEMP_ROOT" "$BUILD_ROOT"
mkdir -p "$DEPS_ROOT" "$SOURCE_ROOT" "$BUILD_ROOT"

BOOST_VERSION=1.81.0
BOOST_ARCHIVE="$SOURCE_ROOT/boost_1_81_0.tar.gz"
BOOST_SHA256=205666dea9f6a7cfed87c7a6dfbeb52a2c1b9de55712c9c1a87735d7181452b6
curl --fail --location --silent --show-error \
    --retry 5 --retry-delay 2 --retry-all-errors \
    "https://archives.boost.io/release/$BOOST_VERSION/source/boost_1_81_0.tar.gz" \
    --output "$BOOST_ARCHIVE"
printf '%s  %s\n' "$BOOST_SHA256" "$BOOST_ARCHIVE" | shasum -a 256 -c
tar -xzf "$BOOST_ARCHIVE" -C "$SOURCE_ROOT"
(
    cd "$SOURCE_ROOT/boost_1_81_0"
    ./bootstrap.sh --prefix="$DEPS_ROOT"
    ./b2 install \
        -j"$CORES" \
        variant=release \
        link=static \
        threading=multi \
        cflags=-O2 \
        cxxflags=-O2 \
        --prefix="$DEPS_ROOT"
)

git clone --depth 1 --branch release-2.1.12-stable \
    https://github.com/libevent/libevent.git "$SOURCE_ROOT/libevent"
cmake -S "$SOURCE_ROOT/libevent" -B "$SOURCE_ROOT/libevent/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS_RELEASE="-O2 -DNDEBUG" \
    -DCMAKE_CXX_FLAGS_RELEASE="-O2 -DNDEBUG" \
    -DCMAKE_INSTALL_PREFIX="$DEPS_ROOT" \
    -DCMAKE_OSX_ARCHITECTURES=x86_64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
    -DEVENT__LIBRARY_TYPE=STATIC \
    -DEVENT__DISABLE_BENCHMARK=ON \
    -DEVENT__DISABLE_TESTS=ON \
    -DEVENT__DISABLE_REGRESS=ON \
    -DEVENT__DISABLE_SAMPLES=ON
cmake --build "$SOURCE_ROOT/libevent/build" --parallel "$CORES"
cmake --install "$SOURCE_ROOT/libevent/build"

git clone --depth 1 --branch 3.2.16 \
    https://gitlab.matrix.org/matrix-org/olm.git "$SOURCE_ROOT/olm"
cmake -S "$SOURCE_ROOT/olm" -B "$SOURCE_ROOT/olm/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS_RELEASE="-O2 -DNDEBUG" \
    -DCMAKE_CXX_FLAGS_RELEASE="-O2 -DNDEBUG" \
    -DCMAKE_INSTALL_PREFIX="$DEPS_ROOT" \
    -DCMAKE_OSX_ARCHITECTURES=x86_64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
    -DBUILD_SHARED_LIBS=OFF \
    -DOLM_TESTS=OFF
cmake --build "$SOURCE_ROOT/olm/build" --parallel "$CORES"
cmake --install "$SOURCE_ROOT/olm/build"

git clone --depth 1 --branch 0.15.0 \
    https://github.com/frankosterfeld/qtkeychain.git "$SOURCE_ROOT/qtkeychain"
cmake -S "$SOURCE_ROOT/qtkeychain" -B "$SOURCE_ROOT/qtkeychain/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS_RELEASE="-O2 -DNDEBUG" \
    -DCMAKE_CXX_FLAGS_RELEASE="-O2 -DNDEBUG" \
    -DCMAKE_INSTALL_PREFIX="$DEPS_ROOT" \
    -DCMAKE_PREFIX_PATH="$QTPATH" \
    -DQt5_DIR="$QTPATH/lib/cmake/Qt5" \
    -DCMAKE_OSX_ARCHITECTURES=x86_64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
    -DBUILD_WITH_QT5=ON \
    -DBUILD_WITH_QT6=OFF \
    -DBUILD_TEST_APPLICATION=OFF \
    -DBUILD_TRANSLATIONS=OFF
cmake --build "$SOURCE_ROOT/qtkeychain/build" --parallel "$CORES"
cmake --install "$SOURCE_ROOT/qtkeychain/build"

# Build the OpenSSL source pinned by the libnunchuk submodule without modifying
# the checked-out source tree.
cp -R "$PROJECT_ROOT/contrib/libnunchuk/contrib/openssl" "$SOURCE_ROOT/openssl"
(
    cd "$SOURCE_ROOT/openssl"
    CFLAGS="-O2" ./Configure darwin64-x86_64-cc \
        no-tests \
        no-shared \
        --prefix="$DEPS_ROOT/openssl"
    make -j"$CORES"
    make install_dev
)

EVENT_LIBRARY="$DEPS_ROOT/lib/libevent.a"
[[ -f "$EVENT_LIBRARY" ]] || {
    echo "Static libevent was not installed at $EVENT_LIBRARY" >&2
    exit 1
}

PREFIX_PATH="$QTPATH;$DEPS_ROOT;$DEPS_ROOT/lib/cmake"
cmake -S "$PROJECT_ROOT" -B "$BUILD_ROOT" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
    -DCMAKE_PREFIX_PATH="$PREFIX_PATH" \
    -DQt5_DIR="$QTPATH/lib/cmake/Qt5" \
    -DOPENSSL_ROOT_DIR="$DEPS_ROOT/openssl" \
    -DBOOST_ROOT="$DEPS_ROOT" \
    -Devent_lib:FILEPATH="$EVENT_LIBRARY" \
    -DUR__DISABLE_TESTS=ON \
    -DNUNCHUK_VERSION="$CMAKE_APP_VERSION" \
    -DCMAKE_OSX_ARCHITECTURES=x86_64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET"
python3 "$PROJECT_ROOT/reproducible-builds/verify_optimization.py" \
    --compile-database "$BUILD_ROOT/compile_commands.json" \
    --project-root "$PROJECT_ROOT" \
    --family unix
cmake --build "$BUILD_ROOT" --config Release --parallel "$CORES"

[[ -d "$APP_PATH" ]] || {
    echo "Nunchuk.app was not produced at $APP_PATH" >&2
    exit 1
}

"$QTPATH/bin/macdeployqt" "$APP_PATH" \
    -executable="$APP_PATH/Contents/MacOS/Nunchuk" \
    -qmldir="$PROJECT_ROOT" \
    -always-overwrite

HWI_ARCHIVE="$SOURCE_ROOT/hwi-3.2.0-mac-x86_64.tar.gz"
HWI_SHA256=d3afb91cdb9084113597b0193bf09c981649551623910844640ec1601f1e4e5b
curl --fail --location --silent --show-error \
    --retry 5 --retry-delay 2 --retry-all-errors \
    https://github.com/nogibi/HWI/releases/download/3.2.0-displayaddress/hwi-3.2.0-mac-x86_64.tar.gz \
    --output "$HWI_ARCHIVE"
printf '%s  %s\n' "$HWI_SHA256" "$HWI_ARCHIVE" | shasum -a 256 -c
mkdir -p "$SOURCE_ROOT/hwi"
tar -xzf "$HWI_ARCHIVE" -C "$SOURCE_ROOT/hwi"
HWI_BINARY="$(find "$SOURCE_ROOT/hwi" -type f -name hwi -print -quit)"
[[ -n "$HWI_BINARY" ]] || {
    echo "HWI executable was not found in the macOS archive" >&2
    exit 1
}
install -m 0755 "$HWI_BINARY" "$APP_PATH/Contents/MacOS/hwi"

# Qt 5.15.2's helper can retain an rpath that points to a Frameworks directory
# inside the helper bundle. Redirect it to the app bundle's Frameworks folder.
HELPER_APP="$APP_PATH/Contents/Frameworks/QtWebEngineCore.framework/Versions/5/Helpers/QtWebEngineProcess.app"
HELPER_EXEC="$HELPER_APP/Contents/MacOS/QtWebEngineProcess"
[[ -x "$HELPER_EXEC" ]] || {
    echo "QtWebEngineProcess was not deployed" >&2
    exit 1
}
if otool -l "$HELPER_EXEC" | grep -Fq '@executable_path/../Frameworks'; then
    install_name_tool -delete_rpath '@executable_path/../Frameworks' "$HELPER_EXEC"
fi
if ! otool -l "$HELPER_EXEC" | grep -Fq '@executable_path/../../../../../../../../Frameworks'; then
    install_name_tool -add_rpath \
        '@executable_path/../../../../../../../../Frameworks' \
        "$HELPER_EXEC"
fi

while IFS= read -r dependency; do
    framework="$(sed -E 's|.*/(Qt[^/]+)\.framework.*|\1|' <<< "$dependency")"
    [[ "$framework" == Qt* ]] || continue
    replacement="@executable_path/../../../../../../../$framework.framework/Versions/5/$framework"
    install_name_tool -change "$dependency" "$replacement" "$HELPER_EXEC"
done < <(otool -L "$HELPER_EXEC" | awk '{print $1}' | grep -E '/Qt[^/]+\.framework/' || true)

MAIN_EXEC="$APP_PATH/Contents/MacOS/Nunchuk"
file -Lb "$MAIN_EXEC" | grep -q 'x86_64' || {
    echo "Nunchuk executable is not x86_64" >&2
    exit 1
}
file -Lb "$APP_PATH/Contents/MacOS/hwi" | grep -q 'x86_64' || {
    echo "HWI executable is not x86_64" >&2
    exit 1
}
otool -L "$MAIN_EXEC" | grep -Fq 'QtNetworkAuth.framework' || {
    echo "Nunchuk is not linked to Qt NetworkAuth" >&2
    exit 1
}
[[ -d "$APP_PATH/Contents/Frameworks/QtNetworkAuth.framework" ]] || {
    echo "Qt NetworkAuth framework was not deployed" >&2
    exit 1
}

while IFS= read -r macho; do
    file -Lb "$macho" | grep -q 'Mach-O' || continue
    file -Lb "$macho" | grep -q 'x86_64' || {
        echo "Non-x86_64 Mach-O in app bundle: $macho" >&2
        exit 1
    }
    while IFS= read -r dependency; do
        case "$dependency" in
            @*|/System/Library/*|/usr/lib/*|"$APP_PATH"/*)
                ;;
            *)
                echo "External Mach-O dependency: $macho -> $dependency" >&2
                exit 1
                ;;
        esac
    done < <(otool -L "$macho" | tail -n +2 | awk '{print $1}')
done < <(find "$APP_PATH" -type f -print)

echo "macOS x86_64 application bundle created: $APP_PATH"
