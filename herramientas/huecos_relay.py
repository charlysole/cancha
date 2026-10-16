#!/usr/bin/env python3
# Uso: huecos_relay.py <wine.log con +timestamp,+relay>
# Encuentra frenadas del hilo principal del juego (el que más llama a Sleep(0)) y muestra qué llamadas
# de cualquier hilo estaban en curso o empezaron durante cada frenada.
import sys, re, collections
pat = re.compile(r'^(\d+)\.(\d+):([0-9a-f]+):(Call|Ret)\s+([\w.]+)\((.*?)\)(?:.*?retval=(\w+))?')
ev = []
for line in open(sys.argv[1], errors='ignore'):
    m = pat.match(line)
    if m:
        ev.append((int(m[1]) + int(m[2]) / 1000, m[3], m[4], m[5].split('.')[-1], m[6][:40]))
main = collections.Counter(e[1] for e in ev if e[3] == 'Sleep' and e[4] == '00000000').most_common(1)[0][0]
# intervalos de llamadas (Call..Ret) por hilo
pila = collections.defaultdict(list); llamadas = []
for t, tid, k, fn, a in ev:
    if k == 'Call':
        pila[tid].append((fn, t, a))
    else:
        while pila[tid]:
            f0, t0, a0 = pila[tid].pop()
            if f0 == fn:
                llamadas.append((t0, t, tid, fn, a0)); break
mt = [e[0] for e in ev if e[1] == main]
inicio = mt[0] + 70  # saltear carga y menús
gaps = [(a, b) for a, b in zip(mt, mt[1:]) if b - a > 0.035 and a > inicio]
print(f'hilo principal {main}; frenadas >35 ms: {len(gaps)}')
resumen = collections.Counter()
for a, b in gaps:
    enc = [c for c in llamadas if c[0] < b and c[1] > a and (c[1] - c[0]) > 0.010]
    print(f'\nfrenada {1000*(b-a):.0f} ms en {a:.3f}:')
    for t0, t1, tid, fn, arg in sorted(enc, key=lambda c: c[0])[:8]:
        print(f'   {tid} {fn}({arg}) {1000*(t1-t0):.0f} ms desde {t0-a:+.3f}')
        resumen[(tid == main, fn)] += 1
print('\nllamadas largas durante frenadas (es_principal, función):', resumen.most_common(10))
