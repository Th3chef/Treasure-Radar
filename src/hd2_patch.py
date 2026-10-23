import struct
MATERIAL, TEXTURE, UNIT, MAGIC = 0xeac0b497876adedf, 0xcd4238c6a0c69e32, 0xe0a48d0be9a7453f, 0xF0000011

def resource_hash(name):
    data = name.encode('utf-8'); mask, mix = (1 << 64) - 1, 0xC6A4A7935BD1E995
    value = len(data) * mix & mask; end = len(data) // 8 * 8
    for (word,) in struct.iter_unpack('<Q', data[:end]):
        word = word * mix & mask; word ^= word >> 47
        value = (value ^ (word * mix & mask)) * mix & mask
    if data[end:]:
        value = (value ^ int.from_bytes(data[end:], 'little')) * mix & mask
    value ^= value >> 47; value = value * mix & mask; value ^= value >> 47
    return value

def thin_hash(name):  # 32-bit hash used for physics templates/materials and bones
    return resource_hash(name) >> 32

def read_archive(path):
    d = open(path, 'rb').read()
    try: g = open(path + '.gpu_resources', 'rb').read()
    except FileNotFoundError: g = b''
    try: s = open(path + '.stream', 'rb').read()
    except FileNotFoundError: s = b''
    magic, nt, n = struct.unpack_from('<III', d, 0); assert magic == MAGIC, hex(magic)
    out = []
    for i in range(n):
        fid, tid, off, soff, goff, _, _, size, ssize, gsize, _, _, _ = struct.unpack_from('<7Q6I', d, 72 + 32 * nt + 80 * i)
        out.append(dict(fid=fid, tid=tid, data=d[off:off + size], gpu=g[goff:goff + gsize], stream=s[soff:soff + ssize]))
    return out

# header bytes 12..72 of a material/texture patch that loaded in build 25327279 (engine metadata only).
# Cross-check and last resort only (patch-proofing: build from the live game's files). Audio patches need
# their own header (hd2-patch-proofing, Wwise notes); a wrong header installs but does nothing in game.
KNOWN_HEADER_25327279 = bytes.fromhex('00000000ce09f5f400000000a05345216b807fe000af620300000000008f660000000000000000000000000000000000000000000000000000000000')

def write_archive(path, entries, header_from=None):
    """header_from: a patch of the same kind (material/texture/unit) that works on the CURRENT game,
    e.g. the mod's last in-game-tested patch rebuilt from fresh Filediver extracts. Pass it on every build."""
    if header_from:
        src = open(header_from, 'rb').read()
        assert struct.unpack_from('<I', src, 0)[0] == MAGIC, 'header_from is not a patch archive'
        hdr = src[12:72]
        if hdr != KNOWN_HEADER_25327279:
            print('note: archive header differs from build 25327279 (expected after a game patch); using header_from')
    else:
        print('WARNING: no header_from; using the build 25327279 header. Pass a working patch from the current game.')
        hdr = KNOWN_HEADER_25327279
    unknown, unk56 = struct.unpack_from('<I', hdr, 0)[0], hdr[4:60]
    order = [MATERIAL, TEXTURE, UNIT]
    types = sorted({e['tid'] for e in entries}, key=lambda t: order.index(t) if t in order else 9)
    ents = sorted(entries, key=lambda e: types.index(e['tid']))
    head = struct.pack('<IIII', MAGIC, len(types), len(ents), unknown) + unk56
    for t in types: head += struct.pack('<QQQII', 0, t, sum(e['tid'] == t for e in ents), 16, 64)
    cursor = len(head) + 80 * len(ents); rows = body = b''; gpu = bytearray()
    for i, e in enumerate(ents, 1):
        goff = 0
        if e.get('gpu'):
            gpu += b'\0' * (-len(gpu) % 64); goff = len(gpu); gpu += e['gpu']
        rows += struct.pack('<7Q6I', e['fid'], e['tid'], cursor, 0, goff, 0, 0, len(e['data']), 0, len(e.get('gpu', b'')), 16, 64, i)
        body += e['data']; cursor += len(e['data'])
    toc = head + rows + body; toc += b'\0' * max(0, 256 * len(ents) - len(toc))
    open(path, 'wb').write(toc)
    open(path + '.gpu_resources', 'wb').write(bytes(gpu))
    open(path + '.stream', 'wb').write(b'')

def load_var_names(hashlist='hd2sdk/hashlists/shadervariables.txt'):
    names = {}
    try:
        for line in open(hashlist):
            p = line.split()
            if len(p) == 2: names[int(p[1], 16)] = p[0]
    except FileNotFoundError: pass
    return names

def parse_material(m, names=None):
    names = names or {}
    parent, = struct.unpack_from('<Q', m, 24)
    nt, = struct.unpack_from('<I', m, 64); nv, = struct.unpack_from('<I', m, 104)
    o = 136; keys = struct.unpack_from('<%dI' % nt, m, o); o += 4 * nt
    ids = struct.unpack_from('<%dQ' % nt, m, o); o += 8 * nt
    recs = []
    for _ in range(nv):
        klass, _el, vid, off, _st = struct.unpack_from('<5I', m, o); recs.append((klass, vid, off)); o += 20
    base = o; vars_ = []
    for klass, vid, off in recs:
        n = klass + 1 if klass in (0, 1, 2, 3) else 0
        vals = struct.unpack_from('<%df' % n, m, base + off) if n else ()
        vars_.append(dict(name=names.get(vid, '0x%08x' % vid), id=vid, abs=base + off, vals=vals))
    return dict(parent=parent, tex=list(zip(keys, ids)), vars=vars_)

def set_var(buf, info, name, value):  # value: number or function old->new
    v = next(v for v in info['vars'] if v['name'] == name)
    new = [value(x) for x in v['vals']] if callable(value) else [value] * len(v['vals'])
    struct.pack_into('<%df' % len(new), buf, v['abs'], *new)

def set_tex(buf, info, slot_key, texture_id):
    keys = [k for k, _ in info['tex']]
    struct.pack_into('<Q', buf, 136 + 4 * len(keys) + 8 * keys.index(slot_key), texture_id)

def texture_1x1(rgba):
    st = struct.pack('<III', 0, 0, 0xFFFFFFFF) + b'\0' * (15 * 12)
    pf = struct.pack('<II4sIIIII', 32, 0x4, b'DX10', 0, 0, 0, 0, 0)
    hdr = struct.pack('<IIIIIII', 124, 0x1007, 1, 1, 4, 0, 1) + b'\0' * 44 + pf + struct.pack('<IIIII', 0x1000, 0, 0, 0, 0)
    dx10 = struct.pack('<IIIII', 28, 3, 0, 1, 0)
    header = st + b'DDS ' + hdr + dx10; assert len(header) == 340
    return header, bytes(rgba)

def texture_entry(name, rgba):
    h, g = texture_1x1(rgba)
    return dict(fid=resource_hash(name), tid=TEXTURE, data=h, gpu=g)

LUA = 0xa14e8dfa2cd117e2

def lua_resource(src_bytes):
    return struct.pack('<II', len(src_bytes), 2) + src_bytes

def write_lua_archive(path, entries, header12_72):
    """entries: list of (fid, data). Layout matches the Rover/Bingus Lua addon archives."""
    head = struct.pack('<III', MAGIC, 1, len(entries)) + header12_72
    head += struct.pack('<QQQII', 0, LUA, len(entries), 16, 16)
    cursor = len(head) + 80 * len(entries); rows = body = b''
    for i, (fid, data) in enumerate(entries):
        pad = -cursor % 16; body += b'\0' * pad; cursor += pad
        rows += struct.pack('<7Q6I', fid, LUA, cursor, 0, 0, 0, 0, len(data), 0, 0, 16, 16, i)
        body += data; cursor += len(data)
    out = head + rows + body
    out += b'\0' * (-len(out) % 16)   # the archive ends on a 16-byte boundary (as working Lua archives do)
    open(path, 'wb').write(out)
    open(path + '.gpu_resources', 'wb').write(b'')
    open(path + '.stream', 'wb').write(b'')
    return out
