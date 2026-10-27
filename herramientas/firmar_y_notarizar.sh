#!/bin/zsh
# Firma builds/Cancha.app con Developer ID (hardened runtime), la notariza y arma builds/Cancha.dmg
# (también firmado, notarizado y "stapled").
#
# El DMG lleva la app y un LÉEME. NO lleva archivos del juego: cada uno pone su propia copia de PES6.
#
# Uso: herramientas/firmar_y_notarizar.sh [perfil-notarytool]   (por defecto: VideoGrabber)
set -e
RAIZ="${0:A:h:h}"
PERFIL="${1:-VideoGrabber}"
APP="$RAIZ/builds/Cancha.app"
DMG="$RAIZ/builds/Cancha.dmg"
# Lo que se publica tiene que llevar la oferta de código fuente completa (ver crear_app.sh)
if grep -q '{{' "$APP/Contents/Resources/Licencias/LEEME.txt"; then
    echo "falta PUBLICAR_FUENTES o PUBLICAR_CONTACTO: rearmá la app con crear_app.sh" >&2; exit 1
fi
IDENTIDAD=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)
[[ -n "$IDENTIDAD" ]] || { echo "no hay identidad Developer ID Application" >&2; exit 1; }
echo "firmando como: $IDENTIDAD"

# Temporales en una sola carpeta que se borra al terminar (la copia del DMG y el zip pesan ~1 GB).
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT

# Wine traduce código x86 y genera código en memoria; Python y Wine cargan librerías propias.
PERMISOS="$TEMP/permisos.plist"
cat > "$PERMISOS" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-jit</key><true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
    <key>com.apple.security.cs.disable-executable-page-protection</key><true/>
    <key>com.apple.security.cs.disable-library-validation</key><true/>
    <key>com.apple.security.cs.allow-dyld-environment-variables</key><true/>
</dict>
</plist>
EOF
firmar() { codesign --force --options runtime --timestamp --entitlements "$PERMISOS" --sign "$IDENTIDAD" "$@"; }

# 1. Todo Mach-O de adentro hacia afuera (librerías primero, ejecutables después, la app al final)
LISTA="$TEMP/lista"
find "$APP/Contents" -type f ! -path "*/MacOS/Cancha" -print0 | while IFS= read -r -d '' f; do
    file -b "$f" | grep -q "Mach-O" && print -r -- "$f"
done > "$LISTA"
echo "$(wc -l < "$LISTA" | tr -d ' ') binarios"
grep -E '\.(dylib|so)$' "$LISTA" | while IFS= read -r f; do firmar "$f" >/dev/null; done
grep -v -E '\.(dylib|so)$' "$LISTA" | while IFS= read -r f; do firmar "$f" >/dev/null; done
firmar "$APP"
codesign --verify --deep --strict --verbose=1 "$APP"
[[ -n "$SOLO_FIRMAR" ]] && { echo "firmada (sin notarizar)"; exit 0; }

# 2. Notarizar la app y "staplear" el ticket
ZIP="$TEMP/Cancha.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PERFIL" --wait
xcrun stapler staple "$APP"

# 3. DMG: carpeta "Cancha" (app + LÉEME) para arrastrar a Aplicaciones
ESCENARIO="$TEMP/escenario"
mkdir -p "$ESCENARIO/Cancha"
ditto "$APP" "$ESCENARIO/Cancha/Cancha.app"
cp "$RAIZ/herramientas/LEEME.txt" "$ESCENARIO/Cancha/LÉEME.txt"
ln -s /Applications "$ESCENARIO/Aplicaciones"
rm -f "$DMG"
hdiutil create -volname "Cancha" -srcfolder "$ESCENARIO" -fs HFS+ -format ULFO "$DMG" >/dev/null
codesign --force --timestamp --sign "$IDENTIDAD" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PERFIL" --wait
xcrun stapler staple "$DMG"
spctl -a -t open --context context:primary-signature -v "$DMG"
ls -lh "$DMG"
