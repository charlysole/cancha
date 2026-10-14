"""
Servidor online de PES6 para jugar entre amigos (basado en fiveserver/sixserver).

Diferencias con el sixserver original:
  - base de datos SQLite en un archivo (no hace falta MySQL)
  - cuentas automáticas: cualquier serial/contraseña entra; la primera vez se crea la cuenta
  - sin web de registro ni panel de administración

Uso:
    python servidor_pes6.py [--ip auto|<IP pública>] [--sin-upnp] [--datos <carpeta>]

Detecta la IP pública y abre los puertos en el router por UPnP (los cierra al salir).
El juego de esta Mac se conecta a 127.0.0.1; el de un amigo, a la IP pública.
"""
import argparse
import ipaddress
import os
import socket
import sys
import urllib.request

RAIZ = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(RAIZ, 'lib'))

from twisted.internet import reactor, defer  # noqa: E402

from fiveserver import log, data6, logic, errors, storagecontroller  # noqa: E402
from fiveserver.config import FiveServerConfig, YamlConfig  # noqa: E402
from fiveserver.protocol import PacketServiceFactory, pes6  # noqa: E402
from fiveserver.sqlite_pool import SQLitePool  # noqa: E402
from fiveserver.stun import ServidorSTUN  # noqa: E402
from fiveserver import upnp  # noqa: E402


class ConfigBaseSQLite:
    """Lo que FiveServerConfig espera de DatabaseConfig, pero con SQLite."""

    def __init__(self, ruta):
        self.pool = SQLitePool(ruta, os.path.join(RAIZ, 'sql', 'schema6_sqlite.sql'))

    def getReadPool(self):
        return [self.pool]

    def getWritePool(self):
        return [self.pool]


def activar_cuentas_automaticas(config):
    """Si el hash de serial+contraseña no existe, se crea la cuenta en el momento."""
    getUser_original = config.getUser

    @defer.inlineCallbacks
    def getUser(hash):
        if isinstance(hash, bytes):
            hash = hash.decode('ascii')
        try:
            usr = yield getUser_original(hash)
        except errors.UnknownUserError:
            nombre = 'jugador-%s' % hash[:8]
            log.msg('Cuenta nueva automática: %s' % nombre)
            yield config.createUser(nombre, '', hash, None)
            usr = yield getUser_original(hash)
        defer.returnValue(usr)

    config.getUser = getUser


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--ip', default='auto',
                   help='IP pública que se anuncia a los juegos de afuera (auto = la detecta)')
    p.add_argument('--sin-upnp', action='store_true',
                   help='no abrir puertos en el router automáticamente')
    p.add_argument('--datos', default=os.path.join(RAIZ, 'datos'),
                   help='carpeta para la base de datos y el log')
    p.add_argument('--escuchar', default='', help='interfaz donde escuchar (vacío = todas)')
    p.add_argument('--nombre', default='PES6 Mac', help='nombre del servidor')
    p.add_argument('--debug', action='store_true')
    a = p.parse_args()

    os.makedirs(a.datos, exist_ok=True)
    os.environ['FSROOT'] = RAIZ
    from twisted.python import log as twlog
    twlog.startLogging(sys.stdout)
    twlog.addObserver(twlog.FileLogObserver(
        open(os.path.join(a.datos, 'servidor.log'), 'a')).emit)

    router = None if a.sin_upnp else upnp.buscar_router()
    ip_publica = a.ip if a.ip != 'auto' else detectar_ip_publica(router)
    ip_local = router.ip_local if router else ip_local_principal()
    log.msg('IP pública: %s | IP local: %s | UPnP: %s' % (
        ip_publica, ip_local, 'sí' if router else 'no'))

    scfg = YamlConfig(os.path.join(RAIZ, 'etc', 'conf', 'sixserver.yaml'))
    scfg.ServerIP = ip_publica
    scfg.ListenOn = a.escuchar
    scfg.ServerName = a.nombre
    scfg.Debug = a.debug
    scfg.Lobbies = ['Partidos', {'name': 'Entrenamiento', 'type': 'noStats'}]
    scfg.Greeting = {'text': 'Bienvenido a %s.\nServidor propio: no hace falta registrarse.' % a.nombre}
    log.setDebug(a.debug)

    base = ConfigBaseSQLite(os.path.join(a.datos, 'pes6.sqlite'))
    controlador = storagecontroller.StorageController(base.getReadPool(), base.getWritePool())
    userData = data6.UserData(controlador)
    profileData = data6.ProfileData(controlador)
    matchData = data6.MatchData(controlador)
    profileLogic = logic.ProfileLogic(matchData, profileData)
    config = FiveServerConfig(scfg, base, userData, profileData, matchData, profileLogic)
    activar_cuentas_automaticas(config)

    servicios = []
    for _juego, puerto in scfg.GamePorts.items():
        factory = PacketServiceFactory(config)
        factory.protocol = pes6.NewsProtocol
        factory.protocol.GREETING['text'] = scfg.Greeting['text']
        factory.protocol.SERVER_NAME = scfg.ServerName
        servicios.append((puerto, factory))
    for protocolo, puerto in [
            (pes6.MainService, scfg.NetworkServer['mainService']),
            (pes6.NetworkMenuService, scfg.NetworkServer['networkMenuService']),
            (pes6.LoginServicePES6, scfg.NetworkServer['loginService']['pes6'])]:
        factory = PacketServiceFactory(config)
        factory.protocol = protocolo
        servicios.append((puerto, factory))
    for puerto, factory in servicios:
        reactor.listenTCP(puerto, factory, interface=a.escuchar)
        log.msg('Escuchando en TCP %d (%s)' % (puerto, factory.protocol.__name__))
    ServidorSTUN(ip_publica, ip_local).escuchar(reactor, a.escuchar)
    if router:
        abrir_puertos(router, scfg)

    log.msg('LISTO. Tu amigo tiene que usar la dirección %s' % ip_publica)
    reactor.run()


# Puertos que hay que abrir en el router para que un amigo de afuera juegue:
#   TCP 10881 + 20200-20202: lista de servidores, lobby y login
#   UDP 3478-3479: STUN (prueba de red del juego)
#   UDP 5739: partido (el juego de esta Mac recibe ahí los datos del rival)
PUERTOS_UDP = [3478, 3479, 5739]


def abrir_puertos(router, scfg):
    puertos = ([('TCP', p) for p in sorted(set(
        list(scfg.GamePorts.values())
        + [scfg.NetworkServer['mainService'], scfg.NetworkServer['networkMenuService'],
           scfg.NetworkServer['loginService']['pes6']]))]
        + [('UDP', p) for p in PUERTOS_UDP])
    abiertos = []
    for protocolo, puerto in puertos:
        try:
            router.abrir(protocolo, puerto)
            abiertos.append((protocolo, puerto))
        except (upnp.ErrorUPnP, OSError) as e:
            log.msg('UPnP: no pude abrir %s %d (%s)' % (protocolo, puerto, e))
    log.msg('UPnP: abiertos %s' % ', '.join('%s %d' % x for x in abiertos))

    def cerrar():
        for protocolo, puerto in abiertos:
            try:
                router.cerrar(protocolo, puerto)
            except (upnp.ErrorUPnP, OSError):
                pass
        log.msg('UPnP: puertos cerrados')
    reactor.addSystemEventTrigger('before', 'shutdown', cerrar)


def detectar_ip_publica(router):
    if router:
        try:
            ip = router.ip_externa()
            if ip and not ipaddress.ip_address(ip).is_private:
                return ip
        except (upnp.ErrorUPnP, OSError):
            pass
    for url in ('https://api.ipify.org', 'https://ifconfig.me/ip'):
        try:
            return urllib.request.urlopen(url, timeout=5).read().decode().strip()
        except OSError:
            pass
    return ip_local_principal()


def ip_local_principal():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(('1.1.1.1', 9))
        return s.getsockname()[0]
    finally:
        s.close()


if __name__ == '__main__':
    main()
