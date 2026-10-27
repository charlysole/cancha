# Cancha

Launcher para jugar **PES6** (Pro Evolution Soccer 6 para PC) en cualquier Mac —Intel o Apple Silicon— y
**hostear partidos online entre amigos** sin registrarse en ningún sitio.

- **Jugar**: el juego normal, a pantalla completa y con la resolución adecuada a tu Mac.
- **Hostear partido**: tu Mac hace de servidor (fiveserver adaptado, incluido en la app), abre los puertos
  del router por UPnP y te muestra la dirección para pasarle a tu amigo.
- **Unirse**: escribís la dirección del que hostea y entrás directo a su lobby.
- Mandos de PlayStation, Xbox y similares por Bluetooth o USB.

> **Aviso.** Cancha es un proyecto independiente y gratuito. No está afiliado a Konami ni lo respalda Konami.
> "Pro Evolution Soccer" y "PES" son marcas de Konami Digital Entertainment. **La app no incluye el juego ni
> ningún archivo de Konami**: necesitás tu propia copia de PES6 para PC, instalada, con su código de registro.

## Descarga e instalación

### 1. La app

1. Bajá `Cancha.dmg` (firmado y notarizado por Apple).
2. Arrastrá la carpeta **Cancha** a Aplicaciones.

### 2. El juego

Necesitás tu copia de **PES6 para PC** ya instalada: la carpeta que tiene `PES6.exe`. El instalador es de
Windows, así que se instala en una PC con Windows y la carpeta se copia a la Mac (por ejemplo, con un pendrive).

- Anotá el **código de registro** (número de serie) que pusiste al instalar: la app lo pide y tiene que ser el
  mismo.
- Cancha está probada con PES6 y el parche **Phoenix 2025/26** de la comunidad
  [PES6.ES](https://www.pes6.es) (con su `kitserver`). Con otras instalaciones de PES6 puede funcionar, pero no
  está probado.

### 3. Juntar todo

1. Copiá la carpeta del juego **adentro de «Cancha», al lado de Cancha.app**. Si la tenés en otro lado, la app
   te la pide la primera vez.
2. Abrí Cancha.app. En Apple Silicon puede pedir instalar Rosetta (una sola vez).
3. La primera vez tarda un poco más (prepara Wine) y te pide el **código de registro** de tu copia.

No hace falta modificar nada del juego a mano: la app prepara todo al arrancar (registro de Windows, ajustes de
pantalla, servidor online). El `PES6.exe` original no se toca; para el online se usa una copia (`PES6_mac.exe`)
que solo cambia la dirección del servidor al que se conecta.

Si venís de la versión 1.3 o anterior (cuando la app se llamaba «PES6 Mac»), Cancha muda sola tus datos
(código de registro, ajustes y entorno de Wine) la primera vez que la abrís.

## Jugar online con un amigo

- **El que hostea** toca **Hostear partido**: la app levanta el servidor, abre los puertos del router (UPnP) y
  muestra una dirección. Se la pasa al amigo.
- **El que se une** toca **Unirse** y escribe esa dirección.
- En el juego: menú **Red → Conectar**, elegí el servidor y entrá al lobby. La contraseña puede ser cualquiera:
  la cuenta se crea sola en el servidor del que hostea. No hace falta registrarse en pes6.es.
- Los dos tienen que tener **la misma instalación** (mismas plantillas y misma versión del parche). Si son
  distintas, el servidor no deja entrar a la sala o el partido se desincroniza.

**Amigo con Windows y la misma instalación (con kitserver)**: puede unirse creando `kitserver\roster.cfg` en su carpeta del juego con:

```
server = "<IP del host>"
stun-server = "<IP del host>"
```

(y borrándolo después para volver a jugar en pes6.es).

## Problemas frecuentes

- **No arranca / se cierra**: el registro de la última sesión está en
  `~/Library/Application Support/Cancha/ultima_sesion.log` (el del servidor, en `…/Cancha/servidor/servidor.log`).
- **Cierres en partidos largos**: el parche recomienda subir `ReservedMemory` en `kitserver/kload.cfg`
  (100000000 equipos modestos, 300000000 medios, 900000000 potentes). En una Mac con Apple Silicon conviene
  300000000 o más.
- **El botón Conectar está gris**: el código de registro no coincide con el del instalador. Cambialo en
  menú Cancha → *Cambiar código de registro…*
- **El amigo no puede entrar**: el router no tiene UPnP o hay CGNAT. Abrí a mano los puertos de abajo hacia la Mac
  que hostea.

### Puertos (si el router no tiene UPnP)

TCP 10881, 20200-20202 · UDP 3478, 3479, 5739

## Estructura

| Carpeta | Qué hay |
|---|---|
| `app/main.swift` | Ventana de inicio (Swift/AppKit, universal) |
| `herramientas/lanzador.sh` | Arranca el juego con Wine (registro, parche de servidor, `roster.cfg`) |
| `herramientas/crear_app.sh` | Arma `builds/Cancha.app` |
| `herramientas/icono.swift` | Dibuja el icono de la app |
| `herramientas/licencias/` | Licencias de terceros y oferta de código fuente (van dentro de la app) |
| `herramientas/firmar_y_notarizar.sh` | Firma Developer ID, notariza y arma el DMG |
| `servidor/` | [fiveserver](https://github.com/juce/fiveserver) adaptado: SQLite, cuentas automáticas, STUN, UPnP |
| `notas/` | Bitácora técnica del port |

### Compilar

Necesita (no incluidos en el repo):

- `motores/cx24/wswine.bundle`: motor Wine **WS12WineCX24.0.7** de Sikarugir (ex Kegworks), compilado del
  código libre de CrossOver (con el Wine común el juego se cuelga al arrancar).
- `/Applications/Wine Stable.app` (Gcenx) por las dylibs de dependencias.
- `motores/python/`: Python 3.12 x86_64 de python-build-standalone con Twisted, pycryptodome y PyYAML.

```sh
herramientas/crear_app.sh            # app de prueba con firma ad hoc
PUBLICAR_FUENTES=<url> PUBLICAR_CONTACTO=<mail> herramientas/crear_app.sh   # app para publicar
herramientas/firmar_y_notarizar.sh   # Developer ID + notarización + DMG (exige las dos variables de arriba)
```

`PUBLICAR_FUENTES` es dónde se publica el código fuente de Wine y sus librerías (LGPL) junto a la descarga, y
`PUBLICAR_CONTACTO`, a quién pedírselo. Van en `Licencias/LEEME.txt` dentro de la app.

## Créditos y licencias

- Servidor basado en **fiveserver** de juce y reddwarf (BSD-2, ver `servidor/LICENSE`).
- STUN inspirado en **friendPES6** (MIT); offsets del exe de **PES6-EXE-modifier** (lazanet).
- La app incluye **Wine** (LGPL 2.1) compilado a partir del código fuente de CodeWeavers
  ([fuentes](https://www.codeweavers.com/crossover/source)) y empaquetado por Sikarugir, más **MoltenVK**,
  **SDL2** y otras librerías libres. La lista completa, con sus licencias, está en `herramientas/licencias/`.
- Parche Phoenix: Castolo, Stavrello y VillaPilla — comunidad [PES6.ES](https://www.pes6.es).
- PES6, "Pro Evolution Soccer" y "PES" son © y marcas de Konami Digital Entertainment. El parche Phoenix es de
  sus autores. Este proyecto no está afiliado a ninguno de los dos y no distribuye archivos de ninguno.
