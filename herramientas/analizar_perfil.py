#!/usr/bin/env python3
# Uso: analizar_perfil.py <perfil.txt>
# Reparte las muestras de EIP del hilo principal por módulo y busca tramos largos (>35 ms) sin pasar por
# ntdll/win32u (o sea, sin esperar ni dormir): ahí está el trabajo que frena al juego.
import sys, collections
mods, mu = [], []
for l in open(sys.argv[1]):
    if l.startswith('M '):
        _, b, s, n = l.split(maxsplit=3); mods.append((int(b, 16), int(s, 16), n.strip()))
    elif l[0].isdigit():
        t, e = l.split(); mu.append((float(t), int(e, 16)))
def modulo(e):
    for b, s, n in mods:
        if b <= e < b + s: return n, e - b
    return '?', e
espera = {'ntdll.dll', 'win32u.dll', 'wow64cpu.dll'}
c = collections.Counter(modulo(e)[0] for _, e in mu)
print('muestras', len(mu), 'por módulo:', c.most_common(10))
tramos, cur = [], []
for t, e in mu:
    if modulo(e)[0] in espera:
        if cur and cur[-1][0] - cur[0][0] > 35: tramos.append(cur)
        cur = []
    else:
        cur.append((t, e))
print(f'tramos >35 ms sin esperar: {len(tramos)}')
total = collections.Counter(); funcs = collections.Counter()
for tr in tramos:
    for t, e in tr:
        n, off = modulo(e); total[n] += 1; funcs[(n, off & ~0xff)] += 1
print('en esos tramos, por módulo:', total.most_common(8))
print('zonas más calientes (módulo, offset/256):', [(n, hex(o), v) for (n, o), v in funcs.most_common(15)])
for tr in tramos[:6]:
    z = collections.Counter((modulo(e)[0], modulo(e)[1] & ~0xff) for _, e in tr).most_common(3)
    print(f'  {tr[0][0]/1000:.1f}s dura {tr[-1][0]-tr[0][0]:.0f} ms:', [(n, hex(o), v) for (n, o), v in z])
