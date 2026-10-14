"""
Apertura automática de puertos en el router por UPnP (IGD), sin depender de librerías externas.

    router = buscar_router()                    # SSDP en la red local
    router.ip_externa()                         # IP pública según el router
    router.abrir('TCP', 20200, '192.168.1.100') # redirige el puerto a esta Mac
    router.cerrar('TCP', 20200)

Si el router no tiene UPnP (o está apagado) buscar_router() devuelve None y hay que abrir los
puertos a mano.
"""
import re
import socket
import urllib.parse
import urllib.request

_SSDP = ('239.255.255.250', 1900)
_SERVICIOS = ('urn:schemas-upnp-org:service:WANIPConnection:1',
              'urn:schemas-upnp-org:service:WANIPConnection:2',
              'urn:schemas-upnp-org:service:WANPPPConnection:1')
DESCRIPCION = 'PES6 Mac'


class ErrorUPnP(Exception):
    pass


class Router:

    def __init__(self, url_control, servicio, ip_local):
        self.url_control = url_control
        self.servicio = servicio
        self.ip_local = ip_local

    def _soap(self, accion, **argumentos):
        cuerpo = ''.join('<%s>%s</%s>' % (k, v, k) for k, v in argumentos.items())
        xml = ('<?xml version="1.0"?>'
               '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
               's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>'
               '<u:%s xmlns:u="%s">%s</u:%s></s:Body></s:Envelope>'
               % (accion, self.servicio, cuerpo, accion))
        pedido = urllib.request.Request(self.url_control, data=xml.encode(), headers={
            'Content-Type': 'text/xml; charset="utf-8"',
            'SOAPAction': '"%s#%s"' % (self.servicio, accion)})
        try:
            return urllib.request.urlopen(pedido, timeout=5).read().decode('utf-8', 'replace')
        except urllib.error.HTTPError as e:
            detalle = e.read().decode('utf-8', 'replace')
            codigo = re.search(r'<errorDescription>([^<]*)', detalle)
            raise ErrorUPnP('%s: %s' % (accion, codigo.group(1) if codigo else e))

    def ip_externa(self):
        respuesta = self._soap('GetExternalIPAddress')
        m = re.search(r'<NewExternalIPAddress>([^<]*)<', respuesta)
        return m.group(1) if m else None

    def abrir(self, protocolo, puerto, ip_interna=None):
        self._soap('AddPortMapping', NewRemoteHost='', NewExternalPort=puerto,
                   NewProtocol=protocolo, NewInternalPort=puerto,
                   NewInternalClient=ip_interna or self.ip_local, NewEnabled=1,
                   NewPortMappingDescription=DESCRIPCION, NewLeaseDuration=0)

    def cerrar(self, protocolo, puerto):
        self._soap('DeletePortMapping', NewRemoteHost='', NewExternalPort=puerto,
                   NewProtocol=protocolo)


def _ip_local_hacia(ip):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect((ip, 9))
        return s.getsockname()[0]
    finally:
        s.close()


def buscar_router(espera=3):
    pedido = ('M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: "ssdp:discover"\r\n'
              'MX: 2\r\nST: urn:schemas-upnp-org:device:InternetGatewayDevice:1\r\n\r\n')
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(espera)
    try:
        s.sendto(pedido.encode(), _SSDP)
        while True:
            datos, _ = s.recvfrom(4096)
            m = re.search(r'(?im)^location:\s*(\S+)', datos.decode('utf-8', 'replace'))
            if m:
                router = _leer_descripcion(m.group(1))
                if router:
                    return router
    except (socket.timeout, OSError):
        return None
    finally:
        s.close()


def _leer_descripcion(url):
    try:
        xml = urllib.request.urlopen(url, timeout=5).read().decode('utf-8', 'replace')
    except OSError:
        return None
    for tipo, control in re.findall(
            r'<serviceType>([^<]+)</serviceType>.*?<controlURL>([^<]+)</controlURL>', xml, re.S):
        if tipo.strip() in _SERVICIOS:
            host = urllib.parse.urlparse(url).hostname
            return Router(urllib.parse.urljoin(url, control.strip()), tipo.strip(),
                          _ip_local_hacia(host))
    return None
