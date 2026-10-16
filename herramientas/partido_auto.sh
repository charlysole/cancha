#!/bin/zsh
# Uso: partido_auto.sh <nombre> [segundos_de_grabacion]
# Prueba de fluidez SIN nadie al teclado: abre el juego de pruebas (copia del repo + prefijo_bench), navega con
# teclas.exe hasta un amistoso España-Francia en Old Trafford (con narración), lo mantiene en juego mandando
# "pase" cada 8 s, graba con Instruments (cuadros en pantalla) y deja el resumen en pruebas/auto_<nombre>.txt.
# Variables del entorno (WINEMSYNC, WINEDLLOVERRIDES, PES6_APP...) pasan al juego.
RAIZ="${0:A:h:h}"
N=$1; G=${2:-90}
APP="${PES6_APP:-$RAIZ/builds/PES6.app}"
WINE="$APP/Contents/SharedSupport/wine/bin/wine"
export WINEPREFIX="${WINEPREFIX:-$RAIZ/prefijo_bench}"
export WINEDEBUG="${WINEDEBUG:-err-all,fixme-all,trace+fps}"
export MVK_CONFIG_LOG_LEVEL=0
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-winemenubuilder.exe=d;mscoree=d;mshtml=d}"
JUEGO="$RAIZ/PES6 Phoenix 2025-2026"
# JUEGO_REAL=1: la instalación del usuario tal cual (app de Aplicaciones, su carpeta de juego y su prefijo),
# lanzada con el lanzador de la app (msync, pes6mac.dll, kload.cfg) como cuando toca "Jugar".
if [[ -n "$JUEGO_REAL" ]]; then
    APP="/Applications/PES6 Mac/PES6.app"; WINE="$APP/Contents/SharedSupport/wine/bin/wine"
    JUEGO="/Applications/PES6 Mac/PES6 Phoenix 2025-2026"
    export WINEPREFIX="$HOME/Library/Application Support/PES6 Mac/prefijo" WINEMSYNC=1
fi
EXE="${PES6_EXE:-PES6.exe}"   # p. ej. PES6_prio.exe (copia parcheada)
OUT="$RAIZ/pruebas/auto_$N"
mkdir -p "$OUT"

terminar() {
    "${WINE:h}/wineserver" -k 2>/dev/null; pkill -9 -x PES6.exe; pkill -9 -x "$EXE"; pkill -9 -f 'winetemp-|PES6J.app/Contents/MacOS/|bin/wineserver'
    python3 -c "import time; time.sleep(2)"
}
teclas() { "$WINE" "$RAIZ/herramientas/teclas.exe" "$1" >/dev/null 2>&1; }
foto() {
    "$RAIZ/herramientas/captura_ventana" "*" "$OUT/$1.png" "$EXE" >/dev/null 2>&1 && sips -Z 480 "$OUT/$1.png" >/dev/null
}
espera() { python3 -c "import time; time.sleep($1)"; }

LIBRE_GB=$(( $(df -k /System/Volumes/Data | awk 'NR==2 {print $4}') / 1048576 ))
(( LIBRE_GB >= 8 )) || { echo "poco espacio libre (${LIBRE_GB} GB): no se mide"; exit 1; }

terminar
# CON_PES6MAC=1: agrega kitserver\pes6mac.dll al final de la lista (copia herramientas/pes6mac/pes6mac.dll).
# SIN_MODULO=fserv (o varios separados por coma): saca esos DLL de kitserver solo para esta prueba.
K="$JUEGO/kitserver/kload.cfg"
if [[ -n "$SIN_MODULO$CON_PES6MAC" ]]; then
    cp "$K" "$OUT/kload.cfg.orig"
    trap 'cp "$OUT/kload.cfg.orig" "$K"; mv -f "$JUEGO/kitserver/pes6mac.log" "$OUT/" 2>/dev/null; rm -f "$JUEGO/kitserver/pes6mac.dll"' EXIT
fi
if [[ -n "$CON_PES6MAC" ]]; then
    cp "$RAIZ/herramientas/pes6mac/pes6mac.dll" "$JUEGO/kitserver/"
    python3 - "$K" <<'PY'
import sys, re
p = sys.argv[1]; s = open(p, 'rb').read().decode('latin-1')
n = int(re.search(r'^DLL\.num = (\d+)', s, re.M).group(1))
s = re.sub(r'^DLL\.num = \d+', 'DLL.num = %d' % (n + 1), s, flags=re.M)
s = re.sub(r'(^DLL\.%d = ".*?"\r?\n)' % (n - 1), lambda m: m.group(1) + 'DLL.%d = "kitserver\\pes6mac.dll"\r\n' % n, s, flags=re.M)
open(p, 'wb').write(s.encode('latin-1'))
PY
fi
if [[ -n "$SIN_MODULO" ]]; then
    python3 - "$K" "$SIN_MODULO" <<'PY'
import sys, re
p, fuera = sys.argv[1], sys.argv[2].split(',')
s = open(p, 'rb').read().decode('latin-1')
dlls = [d for d in re.findall(r'^DLL\.\d+ = "(.*?)"\r?$', s, re.M) if not any(f in d for f in fuera)]
bloque = 'DLL.num = %d\r\n' % len(dlls) + ''.join('DLL.%d = "%s"\r\n' % (i, d) for i, d in enumerate(dlls))
s = re.sub(r'^DLL\.\d+ = ".*?"\r?\n', '', s, flags=re.M)
s = re.sub(r'^DLL\.num = \d+\r?\n', lambda m: bloque, s, flags=re.M)
open(p, 'wb').write(s.encode('latin-1'))
PY
fi
cd "$JUEGO" || exit 1
if [[ -n "$JUEGO_REAL" ]]; then
    PES6_JUEGO="$JUEGO" PES6_SERVIDOR="" "$APP/Contents/Resources/lanzar_juego.sh" >/dev/null 2>&1 &
else
    "$WINE" "$EXE" >"$OUT/wine.log" 2>&1 &
fi
espera 45; foto 0_titulo
teclas "fg w500 ENTER w3500";              foto 1_menu        # título → menú principal
if [[ -n "$SIN_COMENTARIO" ]]; then
    # Opciones → Ajuste sonido → "Frec. de comentario" al mínimo → OK → volver a "Partido Amistoso"
    teclas "DOWN*6 w400 ENTER w3000 DOWN*4 w400 ENTER w3000 DOWN*2 w300 LEFT*4 w500"; foto 1b_sonido
    teclas "UP*2 w300 ENTER w2000 ESC w2500 UP*6 w500";                                foto 1c_menu
fi
teclas "ENTER w3000";                      foto 2_modo        # Partido Amistoso
teclas "ENTER w4000";                      foto 3_personal    # Exhibición
teclas "ENTER w4000";                      foto 4_equipos     # OK (configuración personal)
teclas "ENTER w2500 DOWN*2 RIGHT*3 w400 ENTER w3000"         # Local: Europa A → España
teclas "ENTER w2500 DOWN*3 RIGHT w400 ENTER w4000"; foto 5_uniforme  # Visitante: Francia
teclas "ENTER w4000";                      foto 6_ajustes     # uniformes
# Ajustes generales: la escena de entrada y el estadio se fijan según lo que muestre la captura (ver abajo).
if [[ -z "$NO_AJUSTAR" ]]; then teclas "DOWN w300 RIGHT w300 DOWN*11 w300 RIGHT*${ESTADIO_PASOS:-1} w500"; foto 7a_estadio; teclas "UP*12 w400"; fi
foto 7_ajustes_fijados
teclas "ENTER w5000";                      foto 8_formacion   # A ajustes de formación
teclas "ENTER w25000";                     foto 9_saque       # Comienzo del partido
teclas "ENTER w3000";                                         # saque inicial
# Mantener el partido en juego (saques, laterales, faltas del lado "humano").
( for i in {1..60}; do teclas "ENTER"; espera 8; done ) &
VIVO=$!
( for i in {1..20}; do espera 15; foto "m_$i"; done ) &   # capturas durante la grabación, para saber qué se midió
FOTOS=$!
espera 20
if [[ -n "$PERFIL" ]]; then  # perfilador por muestreo del hilo principal (EIP) desde adentro de Wine
    "$WINE" "$RAIZ/herramientas/perfil.exe" $G 'Z:'"${OUT//\//\\}"'\perfil.txt' >"$OUT/perfil.log" 2>&1
    kill $VIVO 2>/dev/null; terminar; echo "perfil: $OUT/perfil.txt"; exit 0
fi
if [[ -n "$MUESTRA" ]]; then  # en lugar de Instruments: sample (pilas de todos los hilos, texto liviano)
    sample "$(pgrep -x "$EXE" | tail -1)" $G 1 -mayDie -file "$OUT/sample.txt" >/dev/null 2>&1
    kill $VIVO 2>/dev/null; terminar; echo "muestra: $OUT/sample.txt"; exit 0
fi
rm -rf "$OUT/traza.trace"
xcrun xctrace record --instrument Display --instrument 'Metal Application' \
    --attach "$(pgrep -x "$EXE" | tail -1)" --time-limit ${G}s --output "$OUT/traza.trace" >"$OUT/xctrace.log" 2>&1
foto 10_final
kill $VIVO $FOTOS 2>/dev/null
terminar
python3 "$RAIZ/herramientas/analizar_traza.py" "$OUT/traza.trace" > "$RAIZ/pruebas/auto_$N.txt" 2>&1
rm -rf "$OUT/traza.trace"
find "${TMPDIR:-/tmp}" -maxdepth 1 -name "instruments*.ktrace" -delete
[[ -n "$JUEGO_REAL" ]] && cp "$HOME/Library/Application Support/PES6 Mac/ultima_sesion.log" "$OUT/wine.log"
# FPS que genera el juego (canal "fps" de wined3d, promedio cada ~1,5 s) durante la grabación: no depende de la pantalla
python3 - "$OUT/wine.log" "$G" >> "$RAIZ/pruebas/auto_$N.txt" <<'PY'
import re, sys
v = [float(x) for x in re.findall(r'wined3d_cs_exec_present \S+ @ approx ([\d.]+)fps', open(sys.argv[1], errors='ignore').read())]
v = v[-int(int(sys.argv[2]) / 1.5):] if v else []
if v:
    s = sorted(v); print(f'fps generados (wined3d): prom={sum(v)/len(v):.1f} mediana={s[len(s)//2]:.1f} p10={s[len(s)//10]:.1f}  ' + ' '.join(str(round(x)) for x in v[:40]))
else:
    print('fps generados: sin datos (hace falta WINEDEBUG con trace+fps)')
PY
cat "$RAIZ/pruebas/auto_$N.txt"
