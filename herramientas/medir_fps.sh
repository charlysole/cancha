#!/bin/zsh
# Uso: medir_fps.sh <nombre> [segundos]
# Lanza PES6.exe (copia del repo, prefijo de pruebas), deja que corra la demo de la pantalla de título
# y registra los FPS de wined3d (canal "fps", promedio cada ~1,5 s) en pruebas/fps_<nombre>.log.
# Variables extra (WINEDLLOVERRIDES, WINEMSYNC, etc.) se pasan por el entorno.
RAIZ="${0:A:h:h}"
N=$1; S=${2:-150}
APP="${PES6_APP:-$RAIZ/builds/PES6.app}"
WINE="$APP/Contents/SharedSupport/wine/bin/wine"
export WINEPREFIX="${WINEPREFIX:-$RAIZ/prefijo_bench}"
export WINEDEBUG="${WINEDEBUG:-err-all,fixme-all,trace+fps}"
export MVK_CONFIG_LOG_LEVEL=${MVK_CONFIG_LOG_LEVEL:-0}
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-winemenubuilder.exe=d;mscoree=d;mshtml=d}"
JUEGO="$RAIZ/PES6 Phoenix 2025-2026"
LOG="$RAIZ/pruebas/fps_$N.log"

terminar() {  # el juego y todo Wine (SecuROM relanza el exe desde winetemp)
    "${WINE:h}/wineserver" -k 2>/dev/null; pkill -9 -x PES6.exe; pkill -9 -f 'winetemp-|PES6J.app/Contents/MacOS/|wineserver'; sleep 2
}
terminar
# Instruments escribe ~1,3 GB por grabación en la carpeta temporal: no arrancar con poco disco.
LIBRE_GB=$(( $(df -k /System/Volumes/Data | awk 'NR==2 {print $4}') / 1048576 ))
(( LIBRE_GB >= 6 )) || { echo "poco espacio libre (${LIBRE_GB} GB): no se mide"; exit 1; }
[[ -n "$TRAZA" ]] && (( S < ${TRAZA_DESDE:-60} + 70 )) && S=$(( ${TRAZA_DESDE:-60} + 70 ))  # la grabación (60 s + 45 s + guardado) debe terminar antes de cerrar
K='HKLM\SOFTWARE\KONAMIPES6\PX25-26'
"$WINE" reg add "$K" /v installdir /t REG_SZ /d "Z:${JUEGO//\//\\}\\" /f /reg:32 >/dev/null 2>&1
cd "$JUEGO"
"$WINE" PES6.exe >"$LOG" 2>&1 &
# TRAZA=1: a los TRAZA_DESDE s (60 por defecto) graba 45 s con Instruments (cuadros en pantalla + trabajo de Metal) → analizar_traza.py
if [[ -n "$TRAZA" ]]; then
    ( python3 -c "import time; time.sleep(${TRAZA_DESDE:-60})"
      rm -rf "$RAIZ/pruebas/traza_$N.trace"
      xcrun xctrace record --instrument Display --instrument 'Metal Application' --instrument GPU \
          --attach "$(pgrep -x PES6.exe | head -1)" --time-limit 45s --output "$RAIZ/pruebas/traza_$N.trace" >/dev/null 2>&1 ) &
fi
# Capturas solo de la ventana del juego (dueño exacto PES6.exe, la más grande), cada 20 s.
for (( t = 20; t <= S; t += 20 )); do
    python3 -c "import time; time.sleep(20)"
    "$RAIZ/herramientas/captura_ventana" "*" "$RAIZ/pruebas/fps_${N}_$t.png" PES6.exe >>"$LOG.capturas" 2>&1
done
P=$(pgrep -x PES6.exe | head -1)
[[ -n "$P" ]] && ps -o pid,pcpu,rss,etime -p $P
terminar
# Resumen: descarta los primeros 40 s (carga + menú) y da promedio, mínimo y percentil 10.
python3 - "$LOG" <<'EOF'
import re, sys
v = [float(m) for m in re.findall(r'wined3d_cs_exec_present \S+ @ approx ([\d.]+)fps', open(sys.argv[1], errors='ignore').read())]
v = v[27:]  # ~40 s
print(' '.join(str(round(x)) for x in v))
if not v: print("sin datos de fps"); sys.exit()
s = sorted(v)
print(f"muestras={len(v)} prom={sum(v)/len(v):.1f} min={s[0]:.1f} p10={s[len(s)//10]:.1f} max={s[-1]:.1f}")
EOF
wait
if [[ -d "$RAIZ/pruebas/traza_$N.trace" ]]; then
    python3 "$RAIZ/herramientas/analizar_traza.py" "$RAIZ/pruebas/traza_$N.trace" | tee "$RAIZ/pruebas/traza_$N.txt"
    rm -rf "$RAIZ/pruebas/traza_$N.trace"  # pesa cientos de MB; queda el resumen
fi
find "${TMPDIR:-/tmp}" -maxdepth 1 -name "instruments*.ktrace" -delete  # Instruments deja ~1,5 GB por grabación
