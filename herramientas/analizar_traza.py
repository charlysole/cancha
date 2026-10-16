#!/usr/bin/env python3
# Uso: analizar_traza.py <archivo.trace>
# Lee una traza de Instruments ("Game Performance") y resume la fluidez real en pantalla:
# cuánto tiempo estuvo visible cada cuadro (16,7 ms = perfecto a 60 Hz; 33 ms = cuadro repetido = tirón).
import collections, subprocess, sys
import xml.etree.ElementTree as ET

def tabla(traza, esquema):
    xml = subprocess.run(['xcrun', 'xctrace', 'export', '--input', traza, '--xpath',
                          f'/trace-toc/run[@number="1"]/data/table[@schema="{esquema}"]'],
                         capture_output=True, text=True).stdout
    raiz = ET.fromstring(xml)
    cols = [c.findtext('mnemonic') for c in raiz.iter('col')]
    vistos = {}
    for fila in raiz.iter('row'):
        for el in fila.iter():  # los id pueden estar anidados; ref apunta a cualquiera anterior
            if 'id' in el.attrib:
                vistos[el.attrib['id']] = el
        valores = {}
        for col, el in zip(cols, list(fila)):
            if 'ref' in el.attrib:
                el = vistos[el.attrib['ref']]
            valores[col] = (el.text, el.attrib.get('fmt', ''))
        yield valores

traza = sys.argv[1]
dur, razones, d2d = [], collections.Counter(), collections.Counter()
for f in tabla(traza, 'displayed-surfaces-interval'):
    if f.get('category', ('', ''))[1] != 'Display' or 'PES6' not in f['event-label'][1]:
        continue  # solo la superficie del juego
    dur.append(int(f['duration'][0]) / 1e6)
    d2d[f.get('direct-to-display', ('', '?'))[1]] += 1
    r = f.get('detachment-reason', (None, ''))[1]
    if r:
        razones[r] += 1
def entrega():
    # Envíos del juego a Metal (no depende de que la pantalla los muestre: sirve con la pantalla bloqueada).
    # Con la pantalla visible Metal agrupa los envíos por cuadro; sin pantalla cuenta cada envío (~3 por cuadro).
    # Un hueco > 25 ms sin ningún envío = el juego se frenó.
    primero = {}  # número de cuadro de Metal → primer commit (ns)
    for f in tabla(traza, 'metal-command-buffer-frame-assignment'):
        if 'PES6' in f['process'][1]:
            n, t = f['frame-number'][1], int(f['commit-time'][0])
            primero[n] = min(primero.get(n, t), t)
    ts = sorted(t / 1e6 for t in primero.values())
    if len(ts) < 2:
        return print('entrega: sin datos')
    d = [b - a for a, b in zip(ts, ts[1:])]
    s_ = sorted(d); total = (ts[-1] - ts[0]) / 1000
    print(f'envíos a Metal: {len(ts)} en {total:.1f} s  mediana entre envíos={s_[len(s_)//2]:.1f} ms  '
          f'p99={s_[int(len(s_)*.99)]:.1f} ms  máx={s_[-1]:.1f} ms')
    print(f'  huecos >25 ms: {sum(x > 25 for x in d)}  >50 ms: {sum(x > 50 for x in d)}  >100 ms: {sum(x > 100 for x in d)}'
          f'  ({sum(x > 25 for x in d)/total:.2f} por segundo)')
entrega()
if not dur:
    sys.exit('sin cuadros mostrados (¿pantalla bloqueada o ventana tapada?)')
total = sum(dur)
largos = [d for d in dur if d > 20]
hist = collections.Counter(round(d / 16.667) for d in dur)
s = sorted(dur)
print(f'cuadros={len(dur)} en {total/1000:.1f} s → {len(dur)/(total/1000):.1f} fps en pantalla')
print(f'mediana={s[len(s)//2]:.1f} ms  p99={s[int(len(s)*.99)]:.1f} ms  máx={s[-1]:.1f} ms')
print(f'tirones (cuadro visible >20 ms): {len(largos)} ({len(largos)/(total/1000):.1f} por segundo)')
print('cuadros por cantidad de refrescos:', dict(sorted(hist.items())))
print('direct-to-display:', dict(d2d))
pantallas = collections.Counter(f['display-name'][1] for f in tabla(traza, 'displayed-surfaces-interval')
                               if 'PES6' in f['event-label'][1])
print('pantalla:', dict(pantallas))
gpu = collections.defaultdict(float)
for f in tabla(traza, 'metal-gpu-intervals'):
    if 'PES6' in f['process'][1]:
        gpu[f['frame-number'][1]] += int(f['duration'][0]) / 1e6
g = sorted(gpu.values())
if g:
    print(f'GPU por cuadro: mediana={g[len(g)//2]:.1f} ms  p99={g[int(len(g)*.99)]:.1f} ms  máx={g[-1]:.1f} ms')
cod = collections.defaultdict(float)  # CPU armando comandos de Metal (hilo wined3d_cs), por buffer
for f in tabla(traza, 'metal-application-intervals'):
    if 'PES6' in f['process'][1] and f['event-type'][1] == 'Encoding':
        cod[f['cmdbuffer-id'][1]] = max(cod[f['cmdbuffer-id'][1]], int(f['duration'][0]) / 1e6)
c = sorted(cod.values())
if c:
    print(f'CPU codificando: mediana={c[len(c)//2]:.1f} ms  p99={c[int(len(c)*.99)]:.1f} ms  '
          f'máx={c[-1]:.1f} ms  picos>20ms={sum(x > 20 for x in c)}')
# Espejo: ¿cada refresco de otra pantalla muestra un cuadro nuevo del juego?
juego = sorted(int(f['start'][0]) for f in tabla(traza, 'displayed-surfaces-interval')
               if f['category'][1] == 'Display' and 'PES6' in f['event-label'][1])
otras = collections.defaultdict(list)
for f in tabla(traza, 'displayed-surfaces-interval'):
    if f['category'][1] == 'Display' and 'PES6' not in f['event-label'][1] and \
            f['display-name'][1] not in pantallas:
        otras[f['display-name'][1]].append(int(f['start'][0]))
import bisect
for nombre, ts in otras.items():
    ts.sort()
    idx = [bisect.bisect_right(juego, t) for t in ts if juego[0] < t < juego[-1]]
    saltos = collections.Counter(b - a for a, b in zip(idx, idx[1:]))
    n = sum(saltos.values()) or 1
    print(f'{nombre} (copia): refrescos={n}  cuadro nuevo={saltos[1]/n:.1%}  repetido={saltos[0]/n:.1%}  '
          f'salteado={sum(v for k, v in saltos.items() if k > 1)/n:.1%}')
for r, n in razones.most_common(3):
    print(f'  sin direct-to-display ({n}): {r}')
