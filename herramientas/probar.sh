#!/bin/zsh
# Uso: probar.sh <binario-wine> <prefijo> <nombre-prueba> [segundos]
# Lanza PES6.exe, espera y deja log + captura de la ventana en pruebas/.
RAIZ="${0:A:h:h}"
WINE=$1; export WINEPREFIX=$2; N=$3; S=${4:-35}
export WINEDEBUG=${WINEDEBUG:-err+all,fixme-all} MVK_CONFIG_LOG_LEVEL=0
pkill -f PES6.exe; sleep 1
K='HKLM\SOFTWARE\KONAMIPES6\PX25-26'
"$WINE" reg add "$K" /v installdir /t REG_SZ /d "Z:${RAIZ//\//\\}\\PES6 Phoenix 2025-2026\\" /f /reg:32 >/dev/null 2>&1
"$WINE" reg add "$K" /v lang_s /t REG_SZ /d s /f /reg:32 >/dev/null 2>&1
"$WINE" reg add "$K" /v CODE /t REG_SZ /d AAAAAAAAAAAAAAAAAAAA /f /reg:32 >/dev/null 2>&1
cd "$RAIZ/PES6 Phoenix 2025-2026"
("$WINE" PES6.exe > $RAIZ/pruebas/$N.log 2>&1 &)
python3 -c "import time; time.sleep($S)"
P=$(pgrep -f 'PES6.exe' | head -1)
[ -n "$P" ] && ps -o pid,pcpu,rss,etime -p $P || echo "proceso terminado"
$RAIZ/herramientas/captura_ventana "PES6 Phoenix" $RAIZ/pruebas/$N.png
grep -E "err:|nested" $RAIZ/pruebas/$N.log | grep -v setupapi | sort | uniq -c | head -10
