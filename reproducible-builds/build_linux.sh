#!/bin/bash
set -euo pipefail

TAG="${TAG:-0.0.0}"
CMAKE_APP_VERSION="$(sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+).*/\1/' <<< "$TAG")"

# Build project
mkdir -p build && cd build

export LDFLAGS="-L$OPENSSL_ROOT_DIR/lib -lssl -lcrypto -static-libgcc -static-libstdc++"
export CPPFLAGS="-I$OPENSSL_ROOT_DIR/include"

cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
    -DUR__DISABLE_TESTS=ON \
    -DNUNCHUK_VERSION="$CMAKE_APP_VERSION" \
    -DCMAKE_PREFIX_PATH="$OPENSSL_ROOT_DIR;$QT_INSTALLED_PREFIX" \
    -DQt5_DIR=$QT5_DIR

python3 ../reproducible-builds/verify_optimization.py \
    --compile-database compile_commands.json \
    --project-root .. \
    --family unix

make -j$(nproc)

# After build, call package script
cd ..
/project/reproducible-builds/package_linux.sh
