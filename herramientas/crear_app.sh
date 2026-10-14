#!/bin/zsh
# Arma builds/PES6.app:
#   Contents/MacOS/PES6                 ventana de inicio (app/main.swift, universal arm64 + x86_64)
#   Contents/Resources/lanzar_juego.sh  arranca el juego con Wine (herramientas/lanzador.sh)
#   Contents/Resources/python           Python 3.12 portátil x86_64 (python-build-standalone) + Twisted…
#   Contents/Resources/servidor         servidor online (fiveserver adaptado)
#   Contents/SharedSupport/wine         motor Kegworks WS12WineCX24 (código libre de CrossOver)
#                                       + dylibs de dependencias (de Wine Stable de Gcenx)
#
# Uso: herramientas/crear_app.sh
set -e
RAIZ="${0:A:h:h}"
MOTOR="$RAIZ/motores/cx24/wswine.bundle"
LIBS="/Applications/Wine Stable.app/Contents/Resources/wine/lib"
APP="$RAIZ/builds/PES6.app"
R="$APP/Contents/Resources"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$R" "$APP/Contents/SharedSupport"

# Motor Wine: las librerías externas van en wine/lib (rpath de los .so: @loader_path/../../)
# y se enlazan en SharedSupport/ (rpath de bin/: @loader_path/../../).
rsync -a --exclude '*.dylib' "$MOTOR/" "$APP/Contents/SharedSupport/wine/"
rsync -a "$LIBS"/*.dylib "$APP/Contents/SharedSupport/wine/lib/"
(cd "$APP/Contents/SharedSupport" && for f in wine/lib/*.dylib; do ln -s "$f" .; done)

# Ventana de inicio
(cd "$RAIZ/app" && for a in arm64 x86_64; do
    swiftc -O -target $a-apple-macos11 main.swift -o "PES6_$a"; done &&
    lipo -create PES6_arm64 PES6_x86_64 -output "$APP/Contents/MacOS/PES6")
install -m 755 "$RAIZ/herramientas/lanzador.sh" "$R/lanzar_juego.sh"
print -r -- "${PES6_SERVIDOR_PREDETERMINADO:-}" > "$R/servidor_predeterminado.txt"

# Python portátil, sin lo que no usa el servidor
rsync -a --delete \
    --exclude '__pycache__' --exclude 'test/' --exclude 'tests/' --exclude 'idlelib/' \
    --exclude 'tkinter/' --exclude 'turtledemo/' --exclude 'ensurepip/' --exclude 'pip/' \
    --exclude 'lib/tcl*' --exclude 'lib/tk*' --exclude 'lib/itcl*' --exclude 'lib/thread*' \
    --exclude 'share/' --exclude 'include/' --exclude 'twisted/test/' --exclude 'twisted/*/test/' \
    --exclude 'Crypto/SelfTest/' \
    "$RAIZ/motores/python/" "$R/python/"

# Servidor (sin base de datos, logs ni entorno de desarrollo)
mkdir -p "$R/servidor/etc/conf" "$R/servidor/sql"
rsync -a --exclude '__pycache__' "$RAIZ/servidor/lib" "$R/servidor/"
install -m 644 "$RAIZ/servidor/servidor_pes6.py" "$R/servidor/"
install -m 644 "$RAIZ/servidor/etc/conf/sixserver.yaml" "$R/servidor/etc/conf/"
install -m 644 "$RAIZ/servidor/sql/schema6_sqlite.sql" "$R/servidor/sql/"
install -m 644 "$RAIZ/servidor/LICENSE" "$R/servidor/LICENSE-fiveserver"

# Icono (el exe solo trae 48x48; queda escalado hasta tener uno mejor)
ICONSET="$(mktemp -d)/PES6.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -s format png -z $s $s "$RAIZ/recursos/iconos/icono_101.ico" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -s format png -z $((s*2)) $((s*2)) "$RAIZ/recursos/iconos/icono_101.ico" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$R/PES6.icns"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>PES6</string>
    <key>CFBundleDisplayName</key><string>PES6</string>
    <key>CFBundleIdentifier</key><string>com.carlossole.pes6mac</string>
    <key>CFBundleExecutable</key><string>PES6</string>
    <key>CFBundleIconFile</key><string>PES6</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.2</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>LSMinimumSystemVersion</key><string>11.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
EOF

# Firma ad hoc para uso local (Developer ID + notarización: herramientas/firmar_y_notarizar.sh)
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
du -sh "$APP"
