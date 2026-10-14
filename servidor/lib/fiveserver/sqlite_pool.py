"""
Reemplazo de MySQL por SQLite para usar el servidor sin instalar nada.

Imita lo que fiveserver usa de twisted.enterprise.adbapi.ConnectionPool
(runQuery / runInteraction, que devuelven Deferreds) y traduce al vuelo
lo poco de SQL que es propio de MySQL:

    %s                          -> ?
    ON DUPLICATE KEY UPDATE     -> ON CONFLICT DO UPDATE SET
    LAST_INSERT_ID()            -> last_insert_rowid()

Todo corre en el hilo del reactor: el volumen de consultas de un servidor
entre amigos es mínimo y así no hay problemas de concurrencia con SQLite.
"""
import os
import re
import sqlite3
from datetime import datetime

from twisted.internet import defer

_RE_UPSERT = re.compile(r'ON DUPLICATE KEY UPDATE', re.I)
_RE_LAST_ID = re.compile(r'LAST_INSERT_ID\(\)', re.I)


def traducir(sql):
    sql = sql.replace('%s', '?')
    sql = _RE_UPSERT.sub('ON CONFLICT DO UPDATE SET', sql)
    sql = _RE_LAST_ID.sub('last_insert_rowid()', sql)
    return sql


def _a_fecha(valor):
    texto = valor.decode('utf-8')
    for formato in ('%Y-%m-%d %H:%M:%S', '%Y-%m-%d %H:%M:%S.%f'):
        try:
            return datetime.strptime(texto, formato)
        except ValueError:
            pass
    return texto


sqlite3.register_converter('timestamp', _a_fecha)
sqlite3.register_adapter(datetime, lambda d: d.strftime('%Y-%m-%d %H:%M:%S'))


_RE_INSERT_CON_ID = re.compile(r'^\s*INSERT INTO \w+ \(id,', re.I)


def ajustar_id_automatico(sql, args):
    """En MySQL, insertar 0 en una columna AUTO_INCREMENT genera el próximo id; en SQLite
    se guardaría 0 literal (y el juego toma un perfil con id 0 como "No hay datos")."""
    args = list(args or ())
    if args and _RE_INSERT_CON_ID.match(sql) and args[0] in (0, -1):
        args[0] = None
    return args


class _Cursor:
    """Cursor que acepta SQL con sintaxis de MySQL."""

    def __init__(self, cursor):
        self._cursor = cursor

    def execute(self, sql, args=()):
        return self._cursor.execute(traducir(sql), tuple(ajustar_id_automatico(sql, args)))

    def fetchall(self):
        return self._cursor.fetchall()

    def fetchone(self):
        return self._cursor.fetchone()

    @property
    def lastrowid(self):
        return self._cursor.lastrowid


class SQLitePool:

    def __init__(self, ruta, esquema):
        nueva = not os.path.exists(ruta)
        self.conexion = sqlite3.connect(
            ruta, detect_types=sqlite3.PARSE_DECLTYPES,
            check_same_thread=False)
        self.conexion.execute('PRAGMA foreign_keys = ON')
        self.conexion.execute('PRAGMA journal_mode = WAL')
        self.conexion.execute('PRAGMA synchronous = NORMAL')   # con WAL es seguro y no espera al disco en cada consulta
        if nueva:
            with open(esquema) as f:
                self.conexion.executescript(f.read())
            self.conexion.commit()

    def _correr(self, funcion, *args, **kwargs):
        try:
            resultado = funcion(*args, **kwargs)
            self.conexion.commit()
            return defer.succeed(resultado)
        except Exception:
            self.conexion.rollback()
            return defer.fail()

    def runQuery(self, sql, args=()):
        def consulta():
            cursor = _Cursor(self.conexion.cursor())
            cursor.execute(sql, args)
            return cursor.fetchall()
        return self._correr(consulta)

    def runInteraction(self, interaccion, *args, **kwargs):
        def transaccion():
            return interaccion(_Cursor(self.conexion.cursor()), *args, **kwargs)
        return self._correr(transaccion)
