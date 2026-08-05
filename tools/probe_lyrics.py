# -*- coding: utf-8 -*-
"""
example_music 内嵌歌词探测器（纯标准库，不装第三方依赖）。

目的：为 EmbeddedLyricReader 的算法完善提供实证依据——
真实语料里到底有哪些容器、哪些标签键、什么文本编码承载歌词。

覆盖：
  - MP3 : ID3v2.2/2.3/2.4 的 USLT/ULT（非同步歌词）、SYLT（同步歌词）、TXXX(LYRICS)
  - FLAC: VORBIS_COMMENT 中任意含 LYRIC 的键
  - MP4/M4A: ilst 中的 ©lyr（含 meta FullBox 偏移处理）
输出：每个文件是否有歌词、来源标签、字符编码、是否 LRC 时间戳格式、前两行预览。
"""
import os
import sys
import json
import struct

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'example_music')


def decode_text(raw: bytes, enc_hint: int = -1) -> str:
    """按 BOM / 编码字节 / 启发式判定解码，返回 (text)。"""
    if not raw:
        return ''
    if enc_hint == 0:
        return raw.decode('latin-1', 'replace')
    if enc_hint == 3:
        return raw.decode('utf-8', 'replace')
    if enc_hint in (1, 2):
        if raw[:2] == b'\xff\xfe':
            return raw[2:].decode('utf-16-le', 'replace')
        if raw[:2] == b'\xfe\xff':
            return raw[2:].decode('utf-16-be', 'replace')
        return raw.decode('utf-16-be' if enc_hint == 2 else 'utf-16-le', 'replace')
    # 无提示：BOM 优先
    if raw[:3] == b'\xef\xbb\xbf':
        return raw[3:].decode('utf-8', 'replace')
    if raw[:2] == b'\xff\xfe':
        return raw[2:].decode('utf-16-le', 'replace')
    if raw[:2] == b'\xfe\xff':
        return raw[2:].decode('utf-16-be', 'replace')
    try:
        return raw.decode('utf-8')
    except UnicodeDecodeError:
        return raw.decode('utf-16-le', 'replace')


def detect_encoding_name(raw: bytes, enc_hint: int) -> str:
    if enc_hint == 0:
        return 'ISO-8859-1'
    if enc_hint == 3:
        return 'UTF-8'
    if enc_hint == 1:
        return 'UTF-16(BOM)'
    if enc_hint == 2:
        return 'UTF-16BE'
    if raw[:3] == b'\xef\xbb\xbf':
        return 'UTF-8(BOM)'
    if raw[:2] in (b'\xff\xfe', b'\xfe\xff'):
        return 'UTF-16(BOM)'
    return 'UTF-8?'


def syncsafe(b: bytes) -> int:
    return (b[0] << 21) | (b[1] << 14) | (b[2] << 7) | b[3]


def probe_mp3(path):
    """返回 list[(tagname, encname, text)]"""
    out = []
    with open(path, 'rb') as f:
        head = f.read(10)
        if len(head) < 10 or head[:3] != b'ID3':
            return out
        ver = head[3]
        flags = head[5]
        size = syncsafe(head[6:10])
        body = f.read(size)
    pos = 0
    # 扩展头跳过
    if ver >= 3 and (flags & 0x40):
        if ver == 4:
            ext = syncsafe(body[0:4])
        else:
            ext = struct.unpack('>I', body[0:4])[0] + 4
        pos += ext
    idlen = 3 if ver == 2 else 4
    while pos + idlen + (3 if ver == 2 else 6) <= len(body):
        fid = body[pos:pos + idlen]
        if fid == b'\x00' * idlen or not fid.strip(b'\x00'):
            break
        if ver == 2:
            fsize = (body[pos + 3] << 16) | (body[pos + 4] << 8) | body[pos + 5]
            fdata_start = pos + 6
        else:
            raw_size = body[pos + 4:pos + 8]
            fsize = syncsafe(raw_size) if ver == 4 else struct.unpack('>I', raw_size)[0]
            fdata_start = pos + 10
        if fsize <= 0 or fdata_start + fsize > len(body):
            break
        name = fid.decode('latin-1', 'replace')
        data = body[fdata_start:fdata_start + fsize]
        if name in ('USLT', 'ULT'):
            enc = data[0]
            # 语言 3 字节 + 内容描述符(以终止符结尾) + 正文
            rest = data[4:]
            if enc in (1, 2):
                # 双字节终止符
                idx = 0
                while idx + 1 < len(rest):
                    if rest[idx] == 0 and rest[idx + 1] == 0:
                        break
                    idx += 2
                text_raw = rest[idx + 2:]
            else:
                idx = rest.find(b'\x00')
                text_raw = rest[idx + 1:] if idx >= 0 else rest
            out.append((name, detect_encoding_name(text_raw, enc), decode_text(text_raw, enc)))
        elif name == 'SYLT':
            out.append((name, 'binary-sync', '<SYLT 同步歌词二进制帧>'))
        elif name in ('TXXX',):
            enc = data[0]
            rest = data[1:]
            if enc in (1, 2):
                idx = 0
                while idx + 1 < len(rest):
                    if rest[idx] == 0 and rest[idx + 1] == 0:
                        break
                    idx += 2
                desc = decode_text(rest[:idx], enc)
                val = rest[idx + 2:]
            else:
                idx = rest.find(b'\x00')
                desc = decode_text(rest[:idx], enc) if idx >= 0 else ''
                val = rest[idx + 1:] if idx >= 0 else b''
            if 'LYRIC' in desc.upper():
                out.append(('TXXX:' + desc, detect_encoding_name(val, enc), decode_text(val, enc)))
        pos = fdata_start + fsize
    return out


def probe_flac(path):
    out = []
    with open(path, 'rb') as f:
        if f.read(4) != b'fLaC':
            return out
        while True:
            hdr = f.read(4)
            if len(hdr) < 4:
                break
            last = hdr[0] & 0x80
            btype = hdr[0] & 0x7F
            blen = (hdr[1] << 16) | (hdr[2] << 8) | hdr[3]
            data = f.read(blen)
            if btype == 4:  # VORBIS_COMMENT
                p = 0
                vlen = struct.unpack('<I', data[p:p + 4])[0]
                p += 4 + vlen
                count = struct.unpack('<I', data[p:p + 4])[0]
                p += 4
                for _ in range(count):
                    if p + 4 > len(data):
                        break
                    clen = struct.unpack('<I', data[p:p + 4])[0]
                    p += 4
                    item = data[p:p + clen].decode('utf-8', 'replace')
                    p += clen
                    if '=' in item:
                        k, v = item.split('=', 1)
                        if 'LYRIC' in k.upper():
                            out.append((k.upper(), 'UTF-8', v))
            if last:
                break
    return out


def probe_mp4(path):
    out = []
    data = open(path, 'rb').read()

    def walk(buf, start, end, depth=0):
        pos = start
        while pos + 8 <= end:
            size = struct.unpack('>I', buf[pos:pos + 4])[0]
            atom = buf[pos + 4:pos + 8]
            if size == 1:
                size = struct.unpack('>Q', buf[pos + 8:pos + 16])[0]
                body = pos + 16
            elif size == 0:
                size = end - pos
                body = pos + 8
            else:
                body = pos + 8
            if size < 8 or pos + size > end:
                return
            if atom in (b'moov', b'udta', b'ilst', b'trak', b'mdia', b'minf', b'stbl'):
                walk(buf, body, pos + size, depth + 1)
            elif atom == b'meta':
                walk(buf, body + 4, pos + size, depth + 1)  # FullBox: 跳 4 字节 version+flags
            elif atom == b'\xa9lyr' or atom == b'lyr ':
                sub = body
                while sub + 8 <= pos + size:
                    dsz = struct.unpack('>I', buf[sub:sub + 4])[0]
                    dnm = buf[sub + 4:sub + 8]
                    if dsz < 8 or sub + dsz > pos + size:
                        break
                    if dnm == b'data':
                        raw = buf[sub + 16:sub + dsz]
                        out.append(('mp4:' + atom.decode('latin-1', 'replace'),
                                    detect_encoding_name(raw, -1), decode_text(raw, -1)))
                    sub += dsz
            pos += size

    walk(data, 0, len(data))
    return out


def is_lrc(text):
    for line in text.splitlines():
        s = line.strip()
        if s.startswith('[') and ':' in s[:8]:
            head = s[1:s.find(']')] if ']' in s else ''
            if head and head[0].isdigit():
                return True
    return False


def main():
    rows = []
    for dirpath, _dirs, files in os.walk(ROOT):
        for fn in sorted(files):
            ext = os.path.splitext(fn)[1].lower()
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, ROOT)
            try:
                if ext == '.mp3':
                    found = probe_mp3(full)
                elif ext == '.flac':
                    found = probe_flac(full)
                elif ext in ('.m4a', '.mp4', '.aac'):
                    found = probe_mp4(full)
                else:
                    continue
            except Exception as e:
                rows.append({'file': rel, 'ext': ext, 'error': repr(e), 'tags': []})
                continue
            tags = []
            for name, enc, text in found:
                t = (text or '').strip()
                tags.append({
                    'tag': name,
                    'enc': enc,
                    'chars': len(t),
                    'lrc': is_lrc(t),
                    'preview': ' / '.join([l.strip() for l in t.splitlines() if l.strip()][:2])[:120],
                })
            rows.append({'file': rel, 'ext': ext, 'tags': tags})
    print(json.dumps(rows, ensure_ascii=False, indent=1))


if __name__ == '__main__':
    main()
