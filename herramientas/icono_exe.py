# Extracts the icons of a Windows .exe (PE resources RT_GROUP_ICON/RT_ICON)
# as .ico files, one per icon group.
#
# usage: python3 -I icono_exe.py <file.exe> <output dir>
import os
import struct
import sys

data = open(sys.argv[1], 'rb').read()
out = sys.argv[2]
pe = struct.unpack_from('<I', data, 0x3c)[0]
nsec = struct.unpack_from('<H', data, pe + 6)[0]
optsize = struct.unpack_from('<H', data, pe + 20)[0]
opt = pe + 24
magic = struct.unpack_from('<H', data, opt)[0]
ddir = opt + (96 if magic == 0x10b else 112)
rsrc_rva = struct.unpack_from('<I', data, ddir + 2 * 8)[0]
secs = pe + 24 + optsize


def rva_to_off(rva):
	for i in range(nsec):
		s = secs + i * 40
		vsize, va, rawsize, raw = struct.unpack_from('<IIII', data, s + 8)
		if va <= rva < va + max(vsize, rawsize):
			return rva - va + raw
	raise ValueError(hex(rva))


base = rva_to_off(rsrc_rva)


def entries(off):
	named, ids = struct.unpack_from('<HH', data, base + off + 12)
	for i in range(named + ids):
		name, target = struct.unpack_from('<II', data, base + off + 16 + i * 8)
		yield name, target


def leaf(target):
	"""first data entry under a directory (or the entry itself)"""
	while target & 0x80000000:
		target = next(entries(target & 0x7fffffff))[1]
	rva, size = struct.unpack_from('<II', data, base + target)
	return data[rva_to_off(rva):rva_to_off(rva) + size]


types = dict(entries(0))
icons = {}
for name, target in entries(types[3] & 0x7fffffff):
	icons[name] = leaf(target)
for name, target in entries(types[14] & 0x7fffffff):
	grp = leaf(target)
	_, _, count = struct.unpack_from('<HHH', grp, 0)
	items = [struct.unpack_from('<BBBBHHIH', grp, 6 + i * 14) for i in range(count)]
	header = struct.pack('<HHH', 0, 1, count)
	offset = 6 + 16 * count
	dirs, blobs = b'', b''
	for w, h, colors, res, planes, bits, size, iid in items:
		blob = icons[iid]
		dirs += struct.pack('<BBBBHHII', w, h, colors, res, planes, bits, len(blob), offset + len(blobs))
		blobs += blob
		print('group %s: %dx%d %d bits' % (name, w or 256, h or 256, bits))
	open(os.path.join(out, 'icono_%s.ico' % name), 'wb').write(header + dirs + blobs)
