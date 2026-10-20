"""
Puente UDP para el partido entre el juego de esta Mac y uno de afuera.

El partido va por UDP directo entre juegos, y el que hostea es el que habla primero: el juego
de afuera solo contesta. Si el router (o el firewall de Windows) del amigo no tiene el puerto
abierto, descarta esos paquetes porque vienen de una dirección con la que nunca habló, y el
partido se queda en negro hasta "error de conexión".

Pero el juego del amigo sí le habla a este servidor por UDP 3478 (la prueba STUN, desde su
mismo puerto de juego, también justo antes del partido), así que su router deja pasar lo que
le llegue desde ip_publica:3478. El puente usa ese camino:

  juego de esta Mac -> ip_local:P (un puerto por cada rival) -> 3478 -> rival
  rival -> ip_publica:3478 (lo que no es STUN) -> ip_local:P -> juego de esta Mac

Al rival se le dice que el juego de esta Mac está en ip_publica:3478; al juego de esta Mac,
que el rival está en ip_local:P.
"""
from twisted.internet import protocol

from fiveserver import log


class Puente:

    def __init__(self, reactor, ip_publica, ip_local, salida):
        self.reactor = reactor
        self.ip_publica = ip_publica
        self.ip_local = ip_local
        self.salida = salida        # el _Puerto STUN 3478: lo de afuera entra y sale por ahí
        self.puerto_afuera = salida.numero
        self.puertos = {}           # (ip, puerto) del rival -> _Rival

    def de_esta_casa(self, ip):
        return ip == self.ip_publica

    def puerto_para(self, rival):
        """Puerto local que el juego de esta Mac usa para hablarle a 'rival' (ip, puerto)."""
        r = self.puertos.get(rival)
        if r is None:
            r = _Rival(self, rival)
            self.reactor.listenUDP(0, r, interface='')
            self.puertos[rival] = r
            log.msg('Puente: %s:%d <-> %s:%d' % (
                rival[0], rival[1], self.ip_local, r.transport.getHost().port))
        return r.transport.getHost().port

    def desde_afuera(self, datos, rival):
        r = self.puertos.get(rival)
        if r is not None:
            r.al_juego(datos)


class _Rival(protocol.DatagramProtocol):

    def __init__(self, puente, rival):
        self.puente = puente
        self.rival = rival
        self.juego = ('127.0.0.1', 5739)  # el juego de esta Mac; se corrige con su primer paquete
        self.primero = True

    def datagramReceived(self, datos, origen):
        self.juego = origen
        self.puente.salida.transport.write(datos, self.rival)

    def al_juego(self, datos):
        if self.primero:
            self.primero = False
            log.msg('Puente: llegó el primer paquete de %s:%d' % self.rival)
        self.transport.write(datos, self.juego)
