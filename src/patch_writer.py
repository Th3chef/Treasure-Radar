"""Treasure Map - writes a Helldivers 2 patch archive (the Lua and texture patches build.py makes).

Layout: a 72-byte header (magic, type count, entry count, then 60 bytes), 32-byte type rows (0, type, count, 16,
alignment), 80-byte entries '<7Q6I' (id, type, data offset, stream offset, gpu offset, 0, 0, size, stream size, gpu size,
16, alignment, index), then the data, each resource 16-byte aligned. GPU and stream data go to their own files, each
resource 64-byte aligned.
- header: the 60 header bytes. None = zeros with the TOC's data size at +32.
- first_index: the entries' index counts from 0.
- pad_toc: pad the TOC to at least 256 bytes per entry (not needed here; check() says so if a patch is ever shorter).
"""
import struct

MAGIC = 0xF0000011


def write(entries, types, header=None, first_index=0, pad_toc=False):
    """entries: (id, type, data, gpu, stream, alignment) in file order. types: (type, alignment) for the type rows, in
    order. Returns (toc, gpu_resources, stream)."""
    n = len(entries)
    cursor = 72 + 32 * len(types) + 80 * n
    rows, body, gpu, stream = [], [], bytearray(), bytearray()
    for i, (rid, tid, data, g, s, align) in enumerate(entries, first_index):
        pad = -cursor % 16
        body.append(b'\0' * pad); cursor += pad
        goff = soff = 0
        if g:
            gpu += b'\0' * (-len(gpu) % 64); goff = len(gpu); gpu += g
        if s:
            stream += b'\0' * (-len(stream) % 64); soff = len(stream); stream += s
        rows.append(struct.pack('<7Q6I', rid, tid, cursor, soff, goff, 0, 0, len(data), len(s), len(g), 16, align, i))
        body.append(data); cursor += len(data)
    if header is None:
        header = b'\0' * 20 + struct.pack('<I', cursor) + b'\0' * 36
    assert len(header) == 60, len(header)
    head = struct.pack('<III', MAGIC, len(types), n) + header
    for tid, align in types:
        head += struct.pack('<QQQII', 0, tid, sum(e[1] == tid for e in entries), 16, align)
    toc = head + b''.join(rows) + b''.join(body)
    if pad_toc:
        toc += b'\0' * max(0, 256 * n - len(toc))
    return toc, bytes(gpu), bytes(stream)


def check(toc, gpu=b'', stream=b''):
    """Reads a patch back and raises ValueError on anything out of layout: magic, type rows that add up, data inside
    the file and 16-byte aligned, gpu/stream data inside their files and 64-byte aligned, and a TOC of at least 256
    bytes per entry. Returns the entries as (id, type, size)."""
    def bad(why): raise ValueError('patch layout: ' + why)
    if len(toc) < 72: bad('shorter than its header')
    magic, nt, n = struct.unpack_from('<III', toc, 0)
    if magic != MAGIC: bad('magic %08x' % magic)
    if len(toc) < 72 + 32 * nt + 80 * n: bad('rows run past the end')
    if len(toc) < 256 * n: bad('TOC %d bytes for %d entries (fewer than 256 a entry)' % (len(toc), n))
    counts = {}
    for k in range(nt):
        _, tid, cnt, _, _ = struct.unpack_from('<QQQII', toc, 72 + 32 * k)
        counts[tid] = cnt
    seen, out = {}, []
    for k in range(n):
        rid, tid, off, soff, goff, _, _, size, ssize, gsize, _, _, _ = struct.unpack_from('<7Q6I', toc, 72 + 32 * nt + 80 * k)
        seen[tid] = seen.get(tid, 0) + 1
        if off % 16 or off + size > len(toc): bad('entry %016x data at %d (+%d)' % (rid, off, size))
        if gsize and (goff % 64 or goff + gsize > len(gpu)): bad('entry %016x gpu data at %d (+%d)' % (rid, goff, gsize))
        if ssize and (soff % 64 or soff + ssize > len(stream)): bad('entry %016x stream data at %d (+%d)' % (rid, soff, ssize))
        out.append((rid, tid, size))
    if seen != counts: bad('type rows %s, entries %s' % (counts, seen))
    return out
