#!/bin/bash
set -euo pipefail

# Determine version tag
TAG=$(git describe --tags --abbrev=0 || echo "0.0.0")
OUTDIR=nunchuk-linux-v${TAG}/Appdir
mkdir -p "$OUTDIR"

# Deploy with CQtDeployer
EXEC="build/nunchuk-qt"
cqtdeployer -bin "$EXEC" \
    -qmake "$QT_INSTALLED_PREFIX/bin/qmake" \
    -qmlDir . \
    -targetDir "$OUTDIR" \
    -icon "nunchuk-qt.png" \
    noTranslation \
    noStrip

# Bundle libs
mkdir -p "$OUTDIR/lib"
BIN="$OUTDIR/bin/nunchuk-qt"
ldd "$BIN" | awk '{print $3}' | grep -v '^(' | while read lib; do
    [[ -n "$lib" && "$lib" != *"/libQt"* ]] && cp -L "$lib" "$OUTDIR/lib/"
done

# OpenSSL libraries
cp -L $OPENSSL_ROOT_DIR/lib/libssl.so* $OUTDIR/lib/
cp -L $OPENSSL_ROOT_DIR/lib/libcrypto.so* $OUTDIR/lib/

# Patchelf rpath
patchelf --set-rpath '$ORIGIN/../lib' "$BIN"

# Install HWI
wget -q https://github.com/bitcoin-core/HWI/releases/download/3.1.0/hwi-3.1.0-linux-x86_64.tar.gz
mkdir -p hwi-extracted && tar -xzf hwi-3.1.0-linux-x86_64.tar.gz -C hwi-extracted
cp hwi-extracted/hwi "$OUTDIR/bin/"
chmod +x "$OUTDIR/bin/hwi"

# Desktop and AppRun
cat <<EOF > $OUTDIR/nunchuk.desktop
[Desktop Entry]
Type=Application
Name=Nunchuk
Exec=AppRun
Icon=nunchuk-qt
Categories=Utility;
EOF
cp -L "deploy/nunchuk-qt.png" "$OUTDIR"

cat <<'EOF' > $OUTDIR/AppRun
#!/bin/bash
HERE="$(dirname "$(readlink -f "\$0")")"
export QTWEBENGINE_DISABLE_SANDBOX=1
exec "\$HERE/nunchuk-qt.sh" "\$@"
EOF
chmod +x $OUTDIR/AppRun

# Create AppImage
cd nunchuk-linux-v${TAG}
appimagetool Appdir "nunchuk-linux-v${TAG}.AppImage"
