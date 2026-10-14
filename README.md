# PES6 Online para Mac

App nativa para jugar **Pro Evolution Soccer 6** (con el parche **Phoenix 2025-2026**) en cualquier Mac
—Intel o Apple Silicon— y **hostear partidos online entre amigos** sin registrarse en ningún sitio.

- **Jugar**: el juego normal, a pantalla completa y con la resolución adecuada a tu Mac.
- **Hostear partido**: tu Mac hace de servidor (fiveserver adaptado, incluido en la app), abre los puertos
  del router por UPnP y te muestra la dirección para pasarle a tu amigo.
- **Unirse**: escribís la dirección del que hostea y entrás directo a su lobby.
- Mandos de PlayStation, Xbox y similares por Bluetooth o USB.

## Descarga e instalación

> ⚠️ **La app NO incluye el juego.** El parche Phoenix trae el juego completo y se baja aparte, gratis, desde
> la comunidad PES6.ES.

### 1. La app

1. Bajá `PES6 Mac.dmg` de [Releases](../../releases) (firmado y notarizado por Apple).
2. Arrastrá la carpeta **PES6 Mac** a Aplicaciones.

### 2. El juego: PES6 Phoenix Patch 2025/26 Final Season

Este repositorio no enlaza ni distribuye el juego ni el parche. Buscá el **PES6 Phoenix Patch 2025/26 Final
Season** en el foro de la comunidad PES6.ES: el hilo oficial del parche (Castolo, Stavrello y VillaPilla) explica
cómo conseguirlo e instalarlo.

- Según el hilo oficial, el **FIX 2.1** ya viene incluido en el parche completo.
- El parche es un **instalador de Windows (.exe)**. Instalalo en una PC con Windows y copiá la carpeta instalada
  (la que tiene `PES6.exe`) a la Mac, por ejemplo con un pendrive.
- Durante la instalación te pide un **número de serie** (el instalador trae uno por defecto). **Anotalo**: la app
  te lo va a pedir para el online y tiene que ser el mismo.
- Opcional: la **traducción al inglés** (ver el hilo oficial) se descomprime adentro de la carpeta del juego.
  En Mac se abre con The Unarchiver o Keka. No se puede deshacer.

### 3. Juntar todo

1. Copiá la carpeta del juego **adentro de «PES6 Mac», al lado de PES6.app**. Si la tenés en otro lado, la app te
   la pide la primera vez.
2. Abrí PES6.app. En Apple Silicon puede pedir instalar Rosetta (una sola vez).
3. La primera vez tarda un poco más (prepara Wine). Para el online te pide el **código de registro**: el serial
   que usaste en el instalador.

No hace falta modificar nada del juego a mano: la app prepara todo al arrancar (registro de Windows, ajustes de
pantalla, servidor online). El `PES6.exe` original no se toca; para el online se usa una copia (`PES6_mac.exe`).

## Jugar online con un amigo

- **El que hostea** toca **Hostear partido**: la app levanta el servidor, abre los puertos del router (UPnP) y
  muestra una dirección. Se la pasa al amigo.
- **El que se une** toca **Unirse** y escribe esa dirección.
- En el juego: menú **Red → Conectar**, elegí el servidor y entrá al lobby. La contraseña puede ser cualquiera:
  la cuenta se crea sola en el servidor del que hostea. No hace falta registrarse en pes6.es.
- Los dos tienen que tener **la misma versión de Phoenix** (con FIX 2.1). Si las plantillas son distintas, el
  partido se desincroniza.

**Amigo con Windows y Phoenix**: puede unirse creando `kitserver\roster.cfg` en su carpeta del juego con:

```
server = "<IP del host>"
stun-server = "<IP del host>"
```

(y borrándolo después para volver a jugar en pes6.es).

## Problemas frecuentes

- **No arranca / se cierra**: el registro de la última sesión está en
  `~/Library/Application Support/PES6 Mac/ultima_sesion.log` (el del servidor, en `…/PES6 Mac/servidor/servidor.log`).
- **Cierres en partidos largos**: el parche recomienda subir `ReservedMemory` en `kitserver/kload.cfg`
  (100000000 equipos modestos, 300000000 medios, 900000000 potentes). En una Mac con Apple Silicon conviene
  300000000 o más.
- **El botón Conectar está gris**: el código de registro no coincide con el del instalador. Cambialo en
  menú PES6 → *Cambiar código de registro…*
- **El amigo no puede entrar**: el router no tiene UPnP o hay CGNAT. Abrí a mano los puertos de abajo hacia la Mac
  que hostea.

### Puertos (si el router no tiene UPnP)

TCP 10881, 20200-20202 · UDP 3478, 3479, 5739

## Estructura

| Carpeta | Qué hay |
|---|---|
| `app/main.swift` | Ventana de inicio (Swift/AppKit, universal) |
| `herramientas/lanzador.sh` | Arranca el juego con Wine (registro, parche de servidor, `roster.cfg`) |
| `herramientas/crear_app.sh` | Arma `builds/PES6.app` |
| `herramientas/firmar_y_notarizar.sh` | Firma Developer ID, notariza y arma el DMG |
| `servidor/` | [fiveserver](https://github.com/juce/fiveserver) adaptado: SQLite, cuentas automáticas, STUN, UPnP |
| `notas/` | Bitácora técnica del port |

### Compilar

Necesita (no incluidos en el repo):

- `motores/cx24/wswine.bundle`: motor Wine **WS12WineCX24.0.7_7** de Kegworks (código libre de CrossOver;
  el Wine común se cuelga con SecuROM).
- `/Applications/Wine Stable.app` (Gcenx) por las dylibs de dependencias.
- `motores/python/`: Python 3.12 x86_64 de python-build-standalone con Twisted, pycryptodome y PyYAML.
- `recursos/iconos/icono_101.ico`: icono sacado de tu `PES6.exe` con `herramientas/icono_exe.py`.

```sh
herramientas/crear_app.sh            # app con firma ad hoc
herramientas/firmar_y_notarizar.sh   # Developer ID + notarización + DMG
```

## Créditos y licencias

- Servidor basado en **fiveserver** de juce y reddwarf (BSD-2, ver `servidor/LICENSE`).
- STUN inspirado en **friendPES6** (MIT); offsets del exe de **PES6-EXE-modifier** (lazanet).
- La app incluye **Wine** (LGPL 2.1) compilado a partir del código fuente de CrossOver
  ([fuentes](https://www.codeweavers.com/crossover/source)) y empaquetado por Kegworks, más **MoltenVK** y **SDL2**.
- Parche Phoenix: Castolo, Stavrello y VillaPilla — comunidad [PES6.ES](https://www.pes6.es).
- PES6 es © Konami. El parche Phoenix es de sus autores. Este proyecto no distribuye archivos de ninguno de los dos.
