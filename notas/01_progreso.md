# PES6 en Mac (Apple Silicon) — progreso

Objetivo real: hostear un partido online y que un amigo se conecte, sin el registro de pes.es.
Plan: 1) PES6.app con Wine  2) servidor propio (fiveserver) con botón Hostear  3) Unirse por IP  4) NAT/relay.

## Paso 1 — PES6.app (2026-10-12)

**Funciona:** `builds/PES6.app` llega a la pantalla de título de Phoenix 25.12, con kitserver (27 DLLs) y música.

Hallazgos:
- PES6.exe: PE32, D3D8 + DirectInput8, SecuROM 7 (secciones age/agis/quod/.rld). Registro necesario
  `HKLM\SOFTWARE\KONAMIPES6\PX25-26` (32 bits): `installdir` (con `\` final), `lang_s`, `CODE` (serial).
  Sin eso: "The game is not properly installed".
- Wine común (11.0 stable y 11.18 devel) NO sirve: se cuelga por las excepciones de SecuROM
  ("nested exception on signal stack" / "Exception frame is not in stack limits").
- Los motores con código de CrossOver sí: CrossOver 26.2 (no redistribuible, solo para diagnóstico) y
  **Kegworks WS12WineCX24.0.7_7** (redistribuible, LGPL) → `motores/cx24/`. Le faltan las dylibs del
  wrapper de Kegworks; se toman de Wine Stable de Gcenx.

Archivos:
- `herramientas/lanzador.sh` → `PES6.app/Contents/MacOS/PES6`. Prefijo en `~/Library/Application Support/PES6 Mac/prefijo`,
  carpeta del juego en `carpeta_juego.txt` (o al lado de la app, o la pide). `--ajustes` abre settings.exe.
  Log: `ultima_sesion.log`.
- `herramientas/crear_app.sh` arma la app (805 MB, firma ad hoc).
- `herramientas/probar.sh <wine> <prefijo> <nombre>` + `captura_ventana` (captura solo la ventana del juego, no el escritorio).

Pendientes del paso 1: pantalla completa / resolución (settings.exe), joystick, videos de intro
(GStreamer no incluido), cortes de audio (dmsynth underrun), icono en alta resolución, copiar las dylibs a
`motores/` para no depender de Wine Stable, firma Developer ID + notarización (solo cuando se pida).

## Paso 2 — servidor propio (2026-10-12)

- `servidor/` = copia de juce/fiveserver (BSD-2) + cambios:
  - `lib/fiveserver/sqlite_pool.py`: SQLite en lugar de MySQL (traduce %s, ON DUPLICATE KEY, LAST_INSERT_ID).
  - `sql/schema6_sqlite.sql`.
  - `servidor_pes6.py`: arranque sin .tac, sin web/admin; **cuentas automáticas** (hash desconocido → cuenta nueva
    `jugador-<hash8>`). Uso: `servidor/.venv/bin/python servidor_pes6.py --ip <IP>`. Datos en `servidor/datos/`.
  - Puertos TCP: 10881 (news/lista de servidores), 20200 main, 20201 network menu, 20202 login.
- Juego → servidor: el lanzador crea `PES6_mac.exe` (clon APFS de PES6.exe) con la IP de `servidor.txt` escrita en
  0x7b48c4 (pes6gate-ec.winning-eleven.net, 30 B) y 0x7b5a1c (we9stun.winning-eleven.net, 26 B). Mismos offsets que
  el exe original (sacados de lazanet/PES6-EXE-modifier). Verificado que arranca con kitserver.
- Teclas: los eventos de System Events llegan al juego (barra espaciadora avanzó la pantalla de título).
- **STUN**: el juego hace una prueba de red RFC 3489 antes del login (UDP 3478, CHANGE-REQUEST, 3479 directo).
  `lib/fiveserver/stun.py` la responde (cambio de IP simulado respondiendo desde 3479, como friendPES6).
- **Phoenix redirige el online a pes.es desde `kitserver/roster.dll`** (servidor + `stun.pes6.es`, en memoria; el
  parche al exe no alcanza). Opciones `server` y `stun-server` en `kitserver/roster.cfg` → el lanzador lo genera
  (marca "# generado por PES6 Mac"; lo borra sin servidor elegido). roster.dll guarda la cuenta de pes.es en
  HKCU\Software\Kitserver "www.pes6.es" (contiene el serial: no mostrarlo en logs/notas).
- **Serial**: el juego compara el código de Conectar con `CODE` del registro → el lanzador lo pide una vez
  (`serial.txt`). Sin serial válido el botón Conectar queda gris (no se genera ni se saltea: protección de Konami).
- Bug SQLite: perfiles con id 0 (MySQL autoincrementa con 0, SQLite no) → "No hay datos". Arreglado en
  `ajustar_id_automatico`.
- **2026-10-12 16:14: login + perfil + lista de servidores + entrada al lobby funcionando** (servidor en 127.0.0.1).
  El servidor ve ip1=127.0.0.1, ip2=192.168.1.100, udpPort1=5739 del jugador.
- **Internet (2026-10-12 16:18)**: `servidor_pes6.py` sin argumentos detecta IP pública (UPnP GetExternalIPAddress,
  o ipify) y abre por UPnP TCP 10881/20200-20202 + UDP 3478/3479/5739 (los cierra al salir; `lib/fiveserver/upnp.py`,
  sin dependencias). Probado con un router doméstico con UPnP, sin CGNAT.
  check-host.net (BG/IL/VN) conectó a TCP 20202 OK.
  - Lista de servidores (0x2003): a juegos de red privada/loopback se les da la IP por la que entraron (no hay hairpin).
  - STUN: a juegos de la red local se les informa MAPPED = IP pública:mismo puerto (UPnP mapea 5739 1:1), para que
    el rival de afuera sepa adónde mandar el partido. SOURCE/CHANGED = IP local para LAN, 127.0.0.1 para loopback.
  - Amigo en Windows con Phoenix: `kitserver\roster.cfg` con server/stun-server = IP pública + su propio serial.

## App nativa, pantalla, calidad, red, firma (2026-10-12 tarde)
- `app/main.swift` (universal): ventana con Jugar / Hostear partido / Unirse (IP) / Controles… (settings.exe),
  casilla Pantalla completa, menú Calidad gráfica, Cambiar código de registro. Hostear corre
  `Resources/python` (python-build-standalone 3.12 x86_64 + Twisted/pycryptodome/PyYAML) con
  `Resources/servidor/servidor_pes6.py`, lee "LISTO… dirección X" del stdout y abre el juego con 127.0.0.1;
  al cerrar el juego manda SIGINT al servidor (cierra puertos UPnP). `herramientas/lanzador.sh` =
  `Resources/lanzar_juego.sh` (env PES6_JUEGO/PES6_SERVIDOR/PES6_EXE).
- settings.dat: 0x02 = suma(bytes 0x04..fin)&0xFF; 0x04 ancho, 0x06 alto (u16 LE); 0x08 1=fullscreen.
  Fullscreen real NO sirve en Wine (ChangeDisplaySettings -2 → cae a 640x480). Solución: modo ventana +
  bloque en kitserver/kload.cfg (CRLF) "# --- PES6 Mac: pantalla …" con dx.window.x/y=0, width/height = modo
  actual de la pantalla, dx.window.style=0x90000000 (WS_POPUP|WS_VISIBLE) → winemac lo muestra a pantalla completa.
- Resolución interna (internal.resolution.* en kload.cfg, la maneja kload.dll) por GPU (ioreg AGXAccelerator
  gpu-core-count): <=8/Intel = pantalla, 9-15 = 1440p, >=16 = 2160p. M4 Pro 16 núcleos → 3840x2160 OK.
- 16:9: lodmixer (kitserver) ya tiene "Automatic aspect ratio" activo; con resolución de pantalla real corrige
  solo. Falta verificar en un partido (si se ve estirado: aspect manual 1.777 en lodmixer.dat).
- Mandos: winebus.so del motor soporta SDL e IOHID; libSDL2 va en la app; el lanzador pone
  HKLM\System\CurrentControlSet\Services\winebus "Enable SDL"=1. Usuario tiene DualShock 4 (sin probar aún).
- Red: settings.exe Online solo tiene "Port (udp)" (Auto) y "Enable UPnP": el ritmo del partido es fijo en el exe
  (P2P directo, sin relay → sin saltos extra). Servidor: TCP_NODELAY en todas las conexiones, SQLite
  synchronous=NORMAL. `sleep` bloqueante de fiveserver no se usa.
- Firma: `herramientas/firmar_y_notarizar.sh` (Developer ID, hardened runtime + entitlements allow-jit,
  unsigned-exec-memory, disable-exec-page-protection, disable-library-validation, dyld-env). Probado: la app
  firmada arranca el juego. `SOLO_FIRMAR=1` para no notarizar. DMG = carpeta "PES6 Mac" (app + LÉEME) +
  alias Aplicaciones. NO incluye los archivos del juego (decisión: no redistribuir PES6/Phoenix).

## Dock / barra de menú y cartel "Iniciando el juego…" (2026-10-13)
- Causa del Dock y la barra encima del juego: winemac sube la ventana de pantalla completa (nivel de shielding+1,
  pantallas capturadas) solo si el juego es la app ACTIVA. Lanzado desde la ventana de inicio no pasaba al frente →
  ventana en nivel 0, con barra de menú (nivel 24) y Dock encima.
- `app/main.swift`: al tocar Jugar/Hostear/Unirse/Controles, cartel centrado (NSPanel HUD con rueda; "La primera vez
  tarda más" si no hay prefijo). Cada 0,5 s busca una ventana >=300x200 del proceso PES6.exe/PES6_mac.exe/settings.exe
  (dueño + tamaño en CGWindowList, sin permiso de grabación) → oculta el cartel, minimiza la ventana de inicio y activa el
  juego (macOS 14+: NSApp.yieldActivation + activate). Hostear muestra "Preparando el partido…" mientras levanta el servidor.
- `lanzador.sh`: HKCU\Software\Wine\Mac Driver CaptureDisplaysForFullscreen=y (refuerzo; el motor CX24 la soporta).
- Probado en M4 Pro (pantalla externa 1920x1080 + interna): cartel visible, juego a los ~17 s, activo, capa
  2147483629 por encima de la barra de menú.
