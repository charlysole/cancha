#!/bin/zsh
# Motor de arranque de PES6 (lo llama la app nativa, Contents/MacOS/Cancha).
# Corre el PES6.exe original con el Wine (código de CrossOver) que va dentro de la app.
#
# Variables que recibe:
#   PES6_JUEGO     carpeta del juego (la que tiene PES6.exe)          [obligatoria]
#   PES6_SERVIDOR  IP/nombre del servidor online ("" = sin servidor propio)
#   PES6_EXE       PES6.exe (por defecto) o settings.exe
# Lee el serial de ~/Library/Application Support/Cancha/serial.txt (lo guarda la app; sin él no arranca).

APP="${0:A:h:h:h}"
WINE="$APP/Contents/SharedSupport/wine/bin/wine"
SOPORTE="$HOME/Library/Application Support/Cancha"
mkdir -p "$SOPORTE"
LOG="$SOPORTE/ultima_sesion.log"
JUEGO="$PES6_JUEGO"
SERVIDOR="$PES6_SERVIDOR"
EXE="${PES6_EXE:-PES6.exe}"

export WINEPREFIX="$SOPORTE/prefijo"
export WINEDEBUG="${WINEDEBUG:-err+all,fixme-all}"
export MVK_CONFIG_LOG_LEVEL=0
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-winemenubuilder.exe=d;mscoree=d;mshtml=d}"
# msync (sincronización con puertos Mach, de CrossOver): además traslada a macOS las prioridades de hilo
# que pide el juego; sin esto, los hilos de audio de CRI ADX corren con la prioridad por defecto.
export WINEMSYNC="${WINEMSYNC:-1}"

[[ -f "$JUEGO/PES6.exe" ]] || { echo "no está PES6.exe en '$JUEGO'" >>"$LOG"; exit 2; }
echo "=== $(date) — $EXE en $JUEGO, servidor '${SERVIDOR:-ninguno}'" >"$LOG"
# Siempre el serial de la copia del usuario: no hay uno por defecto.
SERIAL=""
[[ -f "$SOPORTE/serial.txt" ]] && SERIAL="$(<"$SOPORTE/serial.txt")"
[[ ${#SERIAL} -eq 20 ]] || { echo "falta el código de registro (serial.txt)" >>"$LOG"; exit 3; }

# --- 1. Prefijo de Wine (la primera vez) ---
if [[ ! -f "$WINEPREFIX/system.reg" ]]; then
    "$WINE" wineboot -i >>"$LOG" 2>&1
fi
# Mandos: SDL (incluido en la app) reconoce DualShock/DualSense/Xbox/8BitDo, etc.
grep -q '"Enable SDL"=dword:00000001' "$WINEPREFIX/system.reg" 2>/dev/null || \
    "$WINE" reg add 'HKLM\System\CurrentControlSet\Services\winebus' /v "Enable SDL" /t REG_DWORD /d 1 /f >>"$LOG" 2>&1
# Pantalla completa: con la ventana del juego activa y del tamaño de la pantalla, el driver de Mac de
# Wine "captura" las pantallas: tapa la barra de menú y el Dock aunque el Dock esté fijo.
grep -q '"CaptureDisplaysForFullscreen"="y"' "$WINEPREFIX/user.reg" 2>/dev/null || \
    "$WINE" reg add 'HKCU\Software\Wine\Mac Driver' /v CaptureDisplaysForFullscreen /t REG_SZ /d y /f >>"$LOG" 2>&1

# --- 2. Clave de registro que crea el instalador de Windows ---
# Sin ella: "The game is not properly installed". CODE = serial (el juego lo compara con el de Conectar).
K='HKLM\SOFTWARE\KONAMIPES6\PX25-26'
"$WINE" reg add "$K" /v installdir /t REG_SZ /d "Z:${JUEGO//\//\\}\\" /f /reg:32 >>"$LOG" 2>&1
"$WINE" reg add "$K" /v lang_s /t REG_SZ /d s /f /reg:32 >>"$LOG" 2>&1
"$WINE" reg add "$K" /v CODE /t REG_SZ /d "$SERIAL" /f /reg:32 >>"$LOG" 2>&1

# --- 3. Servidor online ---
# (a) El exe trae grabados los nombres del servidor de Konami: se usa una copia (PES6_mac.exe, clon APFS
#     instantáneo) con la dirección escrita encima. El PES6.exe original no se toca.
parchear_texto() {  # archivo offset largo_maximo texto_esperado texto_nuevo
    local actual
    actual="$(dd if="$1" bs=1 skip=$2 count=${#4} 2>/dev/null)"
    if [[ "$actual" != "$4" ]]; then
        echo "parche: en $2 no está '$4' (hay '$actual')" >>"$LOG"
        return 1
    fi
    { printf '%s' "$5"; head -c $(( $3 - ${#5} )) /dev/zero; } | \
        dd of="$1" bs=1 seek=$2 conv=notrunc 2>/dev/null
}
if [[ "$EXE" == PES6.exe && -n "$SERVIDOR" && ${#SERVIDOR} -le 26 ]]; then
    rm -f "$JUEGO/PES6_mac.exe"
    cp -c "$JUEGO/PES6.exe" "$JUEGO/PES6_mac.exe" 2>/dev/null || cp "$JUEGO/PES6.exe" "$JUEGO/PES6_mac.exe"
    if parchear_texto "$JUEGO/PES6_mac.exe" $((0x7b48c4)) 30 pes6gate-ec.winning-eleven.net "$SERVIDOR" &&
       parchear_texto "$JUEGO/PES6_mac.exe" $((0x7b5a1c)) 26 we9stun.winning-eleven.net "$SERVIDOR"; then
        EXE=PES6_mac.exe
    fi
fi
# (b) Phoenix trae kitserver/roster.dll, que en memoria cambia servidor y STUN por los de pes.es.
#     Sus opciones "server" y "stun-server" se leen de kitserver/roster.cfg: lo generamos.
#     Solo se borra si lo creó esta app (marca en la primera línea).
CFG="$JUEGO/kitserver/roster.cfg"
MARCA="# generado por PES6 Mac"  # nombre viejo de la app: así se reconocen los cfg de versiones anteriores
if [[ -n "$SERVIDOR" ]]; then
    if [[ ! -f "$CFG" || "$(head -1 "$CFG")" == "$MARCA" ]]; then
        printf '%s\nserver = "%s"\nstun-server = "%s"\n' "$MARCA" "$SERVIDOR" "$SERVIDOR" > "$CFG"
    fi
elif [[ -f "$CFG" && "$(head -1 "$CFG")" == "$MARCA" ]]; then
    rm -f "$CFG"
fi

# --- 4. pes6mac.dll: arreglos para Mac que carga kitserver ---
# fserv.dll (caras HD) carga cada cara con una D3DX que usa matemática x87: bajo Rosetta tarda 60-400 ms por
# textura y el juego se traba (al nombrar jugadores el comentarista, en repeticiones). pes6mac.dll desvía esa
# carga a una versión rápida. Se copia a kitserver/ y se agrega una sola vez a la lista de kload.cfg.
agregar_pes6mac() {  # kload.cfg dll_origen
    local KL=$1 ORIG=$2 n
    [[ -f "$KL" && -f "$ORIG" && -f "${KL:h}/fserv.dll" ]] || return 0
    cp -f "$ORIG" "${KL:h}/pes6mac.dll"
    grep -aq 'pes6mac.dll' "$KL" && return 0
    n=$(grep -a '^DLL.num' "$KL" | tr -dc '0-9')
    [[ -n "$n" ]] || return 0
    NOMBRE='kitserver\pes6mac.dll' awk -v n="$n" '
        /^DLL\.num = / { sub(/= [0-9]+/, "= " (n + 1)) }
        { print }
        index($0, "DLL." (n - 1) " = ") == 1 { printf "DLL.%d = \"%s\"\r\n", n, ENVIRON["NOMBRE"] }
    ' "$KL" > "$KL.nuevo" && mv -f "$KL.nuevo" "$KL"
    echo "pes6mac.dll agregada a kload.cfg" >>"$LOG"
}
[[ "$EXE" != settings.exe ]] && agregar_pes6mac "$JUEGO/kitserver/kload.cfg" "${0:A:h}/pes6mac.dll"

# --- 5. Lanzar y esperar a que termine ---
cd "$JUEGO" || exit 1
"$WINE" "$EXE" >>"$LOG" 2>&1
"$WINE" wineserver -w >/dev/null 2>&1
