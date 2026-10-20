"""
Servidor STUN mínimo (RFC 3489 "clásico") para la prueba de red de PES6.

Antes de loguearse, el juego hace una prueba de red contra we9stun (UDP 3478):
  1. Binding Request normal              -> respuesta desde 3478
  2. Binding Request con CHANGE-REQUEST  -> respuesta desde "otra IP/puerto"
  3. Binding Request directo a 3479      -> respuesta desde 3479
Si alguna no llega, muestra "error de verificación" o "no se puede usar el puerto UDP".

Con una sola IP, "cambiar IP+puerto" se resuelve respondiendo desde el puerto 3479
(friendPES6 comprobó que el juego lo acepta).

Respuesta: MAPPED-ADDRESS (IP:puerto con que vemos al cliente), SOURCE-ADDRESS (desde dónde
respondemos) y CHANGED-ADDRESS (la "otra" dirección: ip_anunciada:3479).
"""
import ipaddress
import socket
import struct

from twisted.internet import protocol

from fiveserver import log

BINDING_REQUEST = 0x0001
BINDING_RESPONSE = 0x0101
MAPPED_ADDRESS = 0x0001
CHANGE_REQUEST = 0x0003
SOURCE_ADDRESS = 0x0004
CHANGED_ADDRESS = 0x0005
SOFTWARE = 0x8022
NOMBRE = b'PES6 Mac STUN'

PUERTO_PRINCIPAL = 3478
PUERTO_ALTERNATIVO = 3479


def _atributo_direccion(tipo, ip, puerto):
    valor = struct.pack('!BBH', 0, 1, puerto) + socket.inet_aton(ip)
    return struct.pack('!HH', tipo, len(valor)) + valor


def _atributos(datos):
    resultado, pos = {}, 20
    while pos + 4 <= len(datos):
        tipo, largo = struct.unpack('!HH', datos[pos:pos + 4])
        resultado[tipo] = datos[pos + 4:pos + 4 + largo]
        pos += 4 + largo
    return resultado


class ServidorSTUN:
    """Dos sockets UDP (3478 y 3479) que comparten la lógica de respuesta."""

    def __init__(self, ip_anunciada, ip_local=None):
        self.ip_anunciada = ip_anunciada
        self.ip_local = ip_local or ip_anunciada
        self.principal = _Puerto(self, PUERTO_PRINCIPAL)
        self.alternativo = _Puerto(self, PUERTO_ALTERNATIVO)
        self.puente = None          # puente.Puente: el tráfico de partido que entra por 3478

    def escuchar(self, reactor, interfaz=''):
        reactor.listenUDP(PUERTO_PRINCIPAL, self.principal, interface=interfaz)
        reactor.listenUDP(PUERTO_ALTERNATIVO, self.alternativo, interface=interfaz)
        log.msg('STUN escuchando en UDP %d y %d' % (PUERTO_PRINCIPAL, PUERTO_ALTERNATIVO))

    def ip_para(self, ip_cliente):
        """La IP de este servidor que el cliente puede alcanzar (misma máquina, red local o internet)."""
        ip = ipaddress.ip_address(ip_cliente)
        if ip.is_loopback:
            return '127.0.0.1'
        if ip.is_private:
            return self.ip_local
        return self.ip_anunciada

    def direccion_vista(self, cliente):
        """MAPPED-ADDRESS: cómo ve internet al juego. Es la dirección que el servidor les pasa a los
        demás para el partido (UDP directo entre juegos). Un juego de esta red sale a internet con la
        IP pública y, gracias al mapeo UPnP, con el mismo puerto; uno de afuera, tal como llega."""
        if ipaddress.ip_address(cliente[0]).is_private and self.ip_anunciada:
            return self.ip_anunciada, cliente[1]
        return cliente

    def respuesta(self, id_transaccion, cliente, puerto_origen):
        ip = self.ip_para(cliente[0])
        cuerpo = (_atributo_direccion(MAPPED_ADDRESS, *self.direccion_vista(cliente))
                  + _atributo_direccion(SOURCE_ADDRESS, ip, puerto_origen)
                  + _atributo_direccion(CHANGED_ADDRESS, ip, PUERTO_ALTERNATIVO)
                  + struct.pack('!HH', SOFTWARE, len(NOMBRE)) + NOMBRE)
        return struct.pack('!HH', BINDING_RESPONSE, len(cuerpo)) + id_transaccion + cuerpo

    def recibido(self, puerto, datos, cliente):
        if len(datos) < 20:
            if self.puente and puerto is self.principal:
                self.puente.desde_afuera(datos, cliente)
            return
        tipo, _largo = struct.unpack('!HH', datos[:4])
        if tipo != BINDING_REQUEST:
            if self.puente and puerto is self.principal:
                self.puente.desde_afuera(datos, cliente)
            return
        id_transaccion = datos[4:20]
        cambio = _atributos(datos).get(CHANGE_REQUEST, b'\0\0\0\0')
        pide_cambio = len(cambio) >= 4 and struct.unpack('!I', cambio[:4])[0] & 0x06
        salida = self.alternativo if (puerto is self.principal and pide_cambio) else puerto
        salida.transport.write(self.respuesta(id_transaccion, cliente, salida.numero), cliente)
        log.msg('STUN %s:%d -> respuesta desde %d%s' % (
            cliente[0], cliente[1], salida.numero, ' (cambio pedido)' if pide_cambio else ''))


class _Puerto(protocol.DatagramProtocol):

    def __init__(self, servidor, numero):
        self.servidor = servidor
        self.numero = numero

    def datagramReceived(self, datos, cliente):
        self.servidor.recibido(self, datos, cliente)
