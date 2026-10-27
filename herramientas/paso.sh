#!/bin/zsh
# Uso: paso.sh "<teclas>" <nombre-captura> [espera_s]
# Manda teclas al juego de pruebas (prefijo_bench) con teclas.exe y captura su ventana después.
RAIZ="${0:A:h:h}"
WINE="${PES6_APP:-$RAIZ/builds/Cancha.app}/Contents/SharedSupport/wine/bin/wine"
export WINEPREFIX="${WINEPREFIX:-$RAIZ/prefijo_bench}" WINEDEBUG=-all
[[ -n "$WINEMSYNC_BENCH" ]] && export WINEMSYNC=1
"$WINE" "$RAIZ/herramientas/teclas.exe" "$1" 2>&1 | grep -v '^$' | head -3
python3 -c "import time; time.sleep(${3:-2})"
mkdir -p "$RAIZ/pruebas/pasos"
"$RAIZ/herramientas/captura_ventana" "*" "$RAIZ/pruebas/pasos/$2.png" PES6.exe >/dev/null 2>&1 &&
    sips -Z 640 "$RAIZ/pruebas/pasos/$2.png" >/dev/null && echo "captura: pruebas/pasos/$2.png" || echo "sin captura"
