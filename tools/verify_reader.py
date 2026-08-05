# -*- coding: utf-8 -*-
"""
EmbeddedLyricReader.ets 的 Python 镜像实现 —— 逐行对齐 ArkTS 版本的分支与偏移，
用真实语料（example_music）回归验证解析算法，避免只能靠真机盲测。

镜像范围：
  readMp3 / parseUsltFrame / parseTxxxLyricFrame / skipTerminatedString / deUnsynchronise
  readFlac / parseVorbisComment
  readMp4 / findTopLevelAtom / scanMp4Boxes / readMp4DataBox / readMp4FreeformBox
  detectAndDecode / normalize / isUsable
"""
import os
import re
import sys
import json
import struct

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'example_music')

MAX_ID3_TAG = 8 * 1024 * 1024
MAX_VORBIS_BLOCK = 4 * 1024 * 1024
MAX_MOOV_BOX = 16 * 1024 * 1024
MAX_LYRIC_CHARS = 512 * 1024


def be32(b, off):
    if off + 4 > len(b):
        return 0
    return (b[off] << 24) | (b[off + 1] << 16) | (b[off + 2] << 8) | b[off + 3]


def le32(b, off):
    if off + 4 > len(b):
        return 0
    return b[off] | (b[off + 1] << 8) | (b[off + 2] << 16) | (b[off + 3] << 24)


def syncsafe(a, b, c, d):
    return ((a & 0x7F) << 21) | ((b & 0x7F) << 14) | ((c & 0x7F) << 7) | (d & 0x7F)


def decode_utf8(bs):
    return bs.decode('utf-8', 'replace')


def decode_utf16le(bs):
    if len(bs) >= 2 and bs[:2] in (b'\xff\xfe', b'\xfe\xff'):
        bs = bs[2:]
    return bs.decode('utf-16-le', 'replace')


def decode_utf16be(bs):
    if len(bs) >= 2 and bs[:2] == b'\xfe\xff':
        bs = bs[2:]
    return bs.decode('utf-16-be', 'replace')


def detect_and_decode(bs):
    if not bs:
        return ''
    if len(bs) >= 2 and bs[0] == 0xFF and bs[1] == 0xFE:
        return decode_utf16le(bs[2:])
    if len(bs) >= 2 and bs[0] == 0xFE and bs[1] == 0xFF:
        return decode_utf16be(bs[2:])
    if len(bs) >= 3 and bs[:3] == b'\xef\xbb\xbf':
        return decode_utf8(bs[3:])
    if len(bs) >= 4 and len(bs) % 2 == 0:
        sample = min(len(bs), 512)
        zodd = zeven = 0
        i = 0
        while i + 1 < sample:
            if bs[i + 1] == 0:
                zodd += 1
            if bs[i] == 0:
                zeven += 1
            i += 2
        pairs = sample // 2
        if pairs > 0 and zodd / pairs > 0.3 and zodd >= zeven:
            return decode_utf16le(bs)
        if pairs > 0 and zeven / pairs > 0.3 and zeven > zodd:
            return decode_utf16be(bs)
    return decode_utf8(bs)


def decode_by_id3(bs, enc):
    if enc == 1:
        return decode_utf16le(bs)
    if enc == 2:
        return decode_utf16be(bs)
    if enc == 3:
        return decode_utf8(bs)
    return detect_and_decode(bs)


def normalize(t):
    s = t.replace('\x00', '')
    s = s.replace('\r\n', '\n').replace('\r', '\n')
    return s.strip()


def usable(t):
    return t is not None and 0 < len(t.strip()) <= MAX_LYRIC_CHARS


def de_unsync(bs):
    out = bytearray()
    i = 0
    while i < len(bs):
        out.append(bs[i])
        if bs[i] == 0xFF and i + 1 < len(bs) and bs[i + 1] == 0x00:
            i += 1
        i += 1
    return bytes(out)


def skip_terminated(frame, frm, enc):
    p = frm
    if enc in (1, 2):
        while p + 1 < len(frame) and not (frame[p] == 0 and frame[p + 1] == 0):
            p += 2
        return p + 2
    while p < len(frame) and frame[p] != 0:
        p += 1
    return p + 1


def parse_uslt(frame):
    if len(frame) < 5:
        return None
    enc = frame[0]
    ts = skip_terminated(frame, 4, enc)
    if ts >= len(frame):
        return None
    return decode_by_id3(frame[ts:], enc)


def parse_txxx(frame):
    if len(frame) < 3:
        return None
    enc = frame[0]
    vs = skip_terminated(frame, 1, enc)
    if vs >= len(frame):
        return None
    desc = decode_by_id3(frame[1:vs], enc).upper()
    if 'LYRIC' not in desc:
        return None
    return decode_by_id3(frame[vs:], enc)


def read_mp3(f, size):
    f.seek(0)
    header = f.read(10)
    if len(header) < 10 or header[0] != 0x49 or header[1] != 0x44 or header[2] != 0x33:
        return None
    major = header[3]
    tag_flags = header[5]
    tag_size = syncsafe(header[6], header[7], header[8], header[9])
    if tag_size <= 0:
        return None
    read_len = min(tag_size, MAX_ID3_TAG, max(size - 10, 0))
    f.seek(10)
    body = f.read(read_len)
    if not body:
        return None
    if tag_flags & 0x80:
        body = de_unsync(body)

    pos = 0
    if major >= 3 and (tag_flags & 0x40) and len(body) >= 4:
        if major == 4:
            pos += syncsafe(body[0], body[1], body[2], body[3])
        else:
            pos += be32(body, 0) + 4

    id_len = 3 if major == 2 else 4
    fh_len = 6 if major == 2 else 10
    fallback = None
    while pos + fh_len <= len(body):
        if body[pos] == 0:
            break
        fid = ''.join(chr(body[pos + i]) for i in range(id_len))
        if major == 2:
            fsize = (body[pos + 3] << 16) | (body[pos + 4] << 8) | body[pos + 5]
        elif major == 4:
            fsize = syncsafe(body[pos + 4], body[pos + 5], body[pos + 6], body[pos + 7])
        else:
            fsize = be32(body, pos + 4)
        if fsize <= 0:
            break
        ds = pos + fh_len
        de = min(ds + fsize, len(body))
        if ds >= de:
            break
        frame = body[ds:de]
        if fid in ('USLT', 'ULT'):
            t = parse_uslt(frame)
            if usable(t):
                return t
        elif fid in ('TXXX', 'TXX') and fallback is None:
            t = parse_txxx(frame)
            if usable(t):
                fallback = t
        pos = ds + fsize
    return fallback


def parse_vorbis(body):
    if len(body) < 8:
        return None
    p = 0
    vendor = le32(body, p)
    p += 4 + vendor
    if p + 4 > len(body):
        return None
    count = le32(body, p)
    p += 4
    loose = None
    for _ in range(count):
        if p + 4 > len(body):
            break
        ilen = le32(body, p)
        p += 4
        if ilen < 0 or p + ilen > len(body):
            break
        raw = body[p:p + ilen]
        p += ilen
        eq = raw.find(b'=')
        if eq <= 0:
            continue
        key = raw[:min(eq, 64)].decode('latin-1', 'replace').upper()
        if 'LYRIC' not in key:
            continue
        val = decode_utf8(raw[eq + 1:])
        if not usable(val):
            continue
        if key in ('LYRICS', 'UNSYNCEDLYRICS', 'UNSYNCED LYRICS'):
            return val
        if loose is None:
            loose = val
    return loose


def read_flac(f, size):
    pos = 0
    f.seek(0)
    magic = f.read(4)
    if len(magic) < 4:
        return None
    if magic[:3] == b'ID3':
        f.seek(0)
        h = f.read(10)
        if len(h) == 10:
            pos = 10 + syncsafe(h[6], h[7], h[8], h[9])
            f.seek(pos)
            magic = f.read(4)
    if len(magic) < 4 or magic != b'fLaC':
        return None
    pos += 4
    guard = 0
    while pos + 4 <= size and guard < 256:
        guard += 1
        f.seek(pos)
        hdr = f.read(4)
        if len(hdr) < 4:
            break
        is_last = (hdr[0] & 0x80) != 0
        btype = hdr[0] & 0x7F
        bsize = (hdr[1] << 16) | (hdr[2] << 8) | hdr[3]
        if bsize < 0:
            break
        if btype == 4 and 0 < bsize <= MAX_VORBIS_BLOCK:
            f.seek(pos + 4)
            body = f.read(bsize)
            v = parse_vorbis(body)
            if usable(v):
                return v
        pos += 4 + bsize
        if is_last:
            break
    return None


def find_top_atom(f, size, fourcc):
    pos = 0
    guard = 0
    while pos + 8 <= size and guard < 512:
        guard += 1
        f.seek(pos)
        h = f.read(16)
        if len(h) < 8:
            break
        bsize = be32(h, 0)
        hlen = 8
        if bsize == 1:
            if len(h) < 16:
                break
            bsize = be32(h, 8) * 4294967296 + be32(h, 12)
            hlen = 16
        elif bsize == 0:
            bsize = size - pos
        if bsize < hlen or pos + bsize > size:
            break
        if be32(h, 4) == fourcc:
            return (pos + hlen, bsize - hlen)
        pos += bsize
    return None


def read_mp4_data_box(buf, start, end):
    pos = start
    while pos + 8 <= end:
        bsize = be32(buf, pos)
        if bsize < 8 or pos + bsize > end:
            return None
        if be32(buf, pos + 4) == 0x64617461 and pos + 16 <= end:
            return detect_and_decode(buf[pos + 16:pos + bsize])
        pos += bsize
    return None


def read_mp4_freeform(buf, start, end):
    pos = start
    is_lyr = False
    while pos + 8 <= end:
        bsize = be32(buf, pos)
        if bsize < 8 or pos + bsize > end:
            return None
        nm = be32(buf, pos + 4)
        if nm == 0x6E616D65 and pos + 12 <= end:
            key = buf[pos + 12:min(pos + bsize, pos + 12 + 64)].decode('latin-1', 'replace').upper()
            if 'LYRIC' in key:
                is_lyr = True
        elif nm == 0x64617461 and is_lyr and pos + 16 <= end:
            return detect_and_decode(buf[pos + 16:pos + bsize])
        pos += bsize
    return None


def scan_mp4(buf, start, end, depth):
    if depth > 8:
        return None
    pos = start
    while pos + 8 <= end:
        bsize = be32(buf, pos)
        hlen = 8
        if bsize == 1:
            if pos + 16 > end:
                return None
            bsize = be32(buf, pos + 8) * 4294967296 + be32(buf, pos + 12)
            hlen = 16
        elif bsize == 0:
            bsize = end - pos
        if bsize < hlen or pos + bsize > end:
            return None
        nm = be32(buf, pos + 4)
        bs, be_ = pos + hlen, pos + bsize
        if nm in (0x75647461, 0x696C7374, 0x6D6F6F76):
            h = scan_mp4(buf, bs, be_, depth + 1)
            if usable(h):
                return h
        elif nm == 0x6D657461:
            h = scan_mp4(buf, bs + 4, be_, depth + 1)
            if usable(h):
                return h
        elif nm in (0xA96C7972, 0x6C797220):
            h = read_mp4_data_box(buf, bs, be_)
            if usable(h):
                return h
        elif nm == 0x2D2D2D2D:
            h = read_mp4_freeform(buf, bs, be_)
            if usable(h):
                return h
        pos += bsize
    return None


def read_mp4(f, size):
    moov = find_top_atom(f, size, 0x6D6F6F76)
    if moov is None or moov[1] <= 0:
        return None
    length = min(moov[1], MAX_MOOV_BOX)
    f.seek(moov[0])
    buf = f.read(length)
    return scan_mp4(buf, 0, len(buf), 0)


def read_embedded(path):
    ext = os.path.splitext(path)[1].lower()
    size = os.path.getsize(path)
    with open(path, 'rb') as f:
        if ext == '.flac':
            return read_flac(f, size)
        if ext == '.mp3':
            return read_mp3(f, size)
        if ext in ('.m4a', '.mp4', '.aac', '.mov', '.m4b'):
            return read_mp4(f, size)
    return None


LRC_LINE = re.compile(r'\[\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?\]')


def main():
    truth = {r['file']: bool(r['tags']) for r in
             json.load(open(os.path.join(os.path.dirname(ROOT), 'tools', 'lyrics_probe.json'), encoding='utf-8'))}
    ok = miss = extra = fail = 0
    problems = []
    stats = {}
    for dp, _d, fs in os.walk(ROOT):
        for fn in sorted(fs):
            ext = os.path.splitext(fn)[1].lower()
            if ext not in ('.mp3', '.flac', '.m4a', '.mp4'):
                continue
            full = os.path.join(dp, fn)
            rel = os.path.relpath(full, ROOT)
            try:
                raw = read_embedded(full)
            except Exception as e:
                fail += 1
                problems.append(('EXC', rel, repr(e)))
                continue
            got = normalize(raw) if usable(raw) else None
            expect = truth.get(rel, False)
            if got and expect:
                ok += 1
                n = len(LRC_LINE.findall(got))
                stats.setdefault(ext, []).append(n)
                if n == 0:
                    problems.append(('NO_TIMESTAMP', rel, got[:60]))
            elif got and not expect:
                extra += 1
                problems.append(('EXTRA', rel, got[:60]))
            elif not got and expect:
                miss += 1
                problems.append(('MISS', rel, ''))
    print('镜像实现回归结果')
    print('  正确提取 :', ok)
    print('  漏取(MISS):', miss)
    print('  多取(EXTRA):', extra)
    print('  异常      :', fail)
    for ext, arr in stats.items():
        print(f'  {ext}: 文件 {len(arr)}，平均 LRC 行数 {sum(arr) // len(arr)}，最少 {min(arr)}')
    if problems:
        print('\n问题明细（前 15）:')
        for p in problems[:15]:
            print('  ', p)


if __name__ == '__main__':
    main()
