/*
 * Copyright (c) 2024 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * You may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { Logger } from './Logger';

const TAG = 'EmbeddedLyricReader';

/**
 * 从音频文件中解析内嵌歌词（原始 LRC 文本，可能含「原文 + 翻译」双行）。
 *
 * MediaKit 的 AVMetadata 不暴露歌词字段，因此这里直接按文件格式解析：
 *  - FLAC : VORBIS_COMMENT 块中的 LYRICS / UNSYNCEDLYRICS
 *  - M4A / MP4 / AAC : moov/udta/meta/ilst 下的 '©lyr' (0xA9 6C 79 72) atom
 *  - MP3  : ID3v2 标签中的 USLT 帧
 *
 * 解析出的文本交给 LrcUtils.parseLrcLyric 做时间戳拆分与翻译识别。
 * 结果按 src 缓存，避免每次切换歌曲都重新读取大文件。
 */
export class EmbeddedLyricReader {
  private static cache: Map<string, string | undefined> = new Map();

  static async read(src: string): Promise<string | undefined> {
    if (!src || src.length === 0) {
      return undefined;
    }
    if (EmbeddedLyricReader.cache.has(src)) {
      return EmbeddedLyricReader.cache.get(src);
    }
    let text: string | undefined = await EmbeddedLyricReader.readInternal(src);
    EmbeddedLyricReader.cache.set(src, text);
    return text;
  }

  private static async readInternal(src: string): Promise<string | undefined> {
    let ext = '';
    const dot = src.lastIndexOf('.');
    if (dot >= 0) {
      ext = src.substring(dot).toLowerCase();
    }
    let bytes: Uint8Array | undefined;
    try {
      bytes = EmbeddedLyricReader.readFileBytes(src, ext);
    } catch (e) {
      Logger.debug(TAG, `open/read failed: ${(e as Error).message}`);
      return undefined;
    }
    if (!bytes || bytes.length === 0) {
      return undefined;
    }
    let text: string | undefined;
    try {
      if (ext === '.flac') {
        text = EmbeddedLyricReader.parseFlac(bytes);
      } else if (ext === '.m4a' || ext === '.mp4' || ext === '.aac' || ext === '.mov') {
        text = EmbeddedLyricReader.parseMp4(bytes);
      } else if (ext === '.mp3') {
        text = EmbeddedLyricReader.parseMp3(bytes);
      }
    } catch (e) {
      Logger.debug(TAG, `parse failed: ${(e as Error).message}`);
    }
    if (text && text.trim().length > 0) {
      return text;
    }
    return undefined;
  }

  /**
   * 读取文件前若干字节（按格式设上限，避免在超大文件上一次性读满内存）。
   */
  private static readFileBytes(src: string, ext: string): Uint8Array {
    let cap = 32 * 1024 * 1024; // m4a/mp4 等默认 32MB
    if (ext === '.flac') {
      cap = 16 * 1024 * 1024;
    } else if (ext === '.mp3') {
      cap = 4 * 1024 * 1024;
    }
    let file: fileIo.File | undefined;
    try {
      file = fileIo.openSync(src, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(src);
      const len = Math.min(stat.size, cap);
      if (len <= 0) {
        return new Uint8Array(0);
      }
      const buffer = new ArrayBuffer(len);
      fileIo.readSync(file.fd, buffer);
      return new Uint8Array(buffer);
    } catch (e) {
      Logger.debug(TAG, `readFileBytes failed: ${(e as Error).message}`);
      return new Uint8Array(0);
    } finally {
      if (file) {
        try {
          fileIo.closeSync(file);
        } catch (_) {
          // ignore
        }
      }
    }
  }

  // ============================ FLAC ============================

  private static parseFlac(bytes: Uint8Array): string | undefined {
    if (bytes.length < 4 ||
      bytes[0] !== 0x66 || bytes[1] !== 0x4C || bytes[2] !== 0x61 || bytes[3] !== 0x43) {
      return undefined; // 'fLaC'
    }
    let pos = 4;
    while (pos + 4 <= bytes.length) {
      const b = bytes[pos];
      const last = (b & 0x80) !== 0;
      const type = b & 0x7F;
      const size = (bytes[pos + 1] << 16) | (bytes[pos + 2] << 8) | bytes[pos + 3];
      if (type === 4 && pos + 4 + size <= bytes.length) { // VORBIS_COMMENT
        const body = bytes.subarray(pos + 4, pos + 4 + size);
        const val = EmbeddedLyricReader.parseVorbisComment(body);
        if (val) {
          return val;
        }
      }
      pos += 4 + size;
      if (last) {
        break;
      }
    }
    return undefined;
  }

  private static parseVorbisComment(body: Uint8Array): string | undefined {
    if (body.length < 8) {
      return undefined;
    }
    let p = 0;
    const vendorLen = EmbeddedLyricReader.le32(body, p);
    p += 4 + vendorLen;
    if (p + 4 > body.length) {
      return undefined;
    }
    const count = EmbeddedLyricReader.le32(body, p);
    p += 4;
    for (let i = 0; i < count; i++) {
      if (p + 4 > body.length) {
        break;
      }
      const clen = EmbeddedLyricReader.le32(body, p);
      p += 4;
      if (p + clen > body.length) {
        break;
      }
      const raw = body.subarray(p, p + clen);
      p += clen;
      const s = EmbeddedLyricReader.decodeUtf8(raw);
      const eq = s.indexOf('=');
      if (eq > 0) {
        const name = s.substring(0, eq).toUpperCase();
        if (name === 'LYRICS' || name === 'UNSYNCEDLYRICS') {
          return s.substring(eq + 1);
        }
      }
    }
    return undefined;
  }

  // ============================ MP4 / M4A ============================

  /**
   * 探测文本编码并解码：
   *  - UTF-16 LE/BE（带 BOM）
   *  - UTF-8（带 BOM）
   *  - 无 BOM 但奇数位 0x00 占比高 → 视为 UTF-16 LE
   *  - 其余按 UTF-8 处理
   * 末尾统一剔除连续的结尾空字符。
   */
  private static detectAndDecode(textBytes: Uint8Array): string {
    if (!textBytes || textBytes.length === 0) {
      return '';
    }
    // UTF-16 LE BOM
    if (textBytes.length >= 2 && textBytes[0] === 0xFF && textBytes[1] === 0xFE) {
      return EmbeddedLyricReader.decodeUtf16(textBytes.subarray(2)).replace(/\0+$/g, '');
    }
    // UTF-16 BE BOM
    if (textBytes.length >= 2 && textBytes[0] === 0xFE && textBytes[1] === 0xFF) {
      return EmbeddedLyricReader.decodeUtf16be(textBytes.subarray(2)).replace(/\0+$/g, '');
    }
    // UTF-8 BOM
    if (textBytes.length >= 3 && textBytes[0] === 0xEF && textBytes[1] === 0xBB && textBytes[2] === 0xBF) {
      return EmbeddedLyricReader.decodeUtf8(textBytes.subarray(3)).replace(/\0+$/g, '');
    }
    // 无 BOM 但疑似 UTF-16 LE：长度为偶数，且奇数位置 0x00 占比 > 0.3
    if (textBytes.length % 2 === 0) {
      let zeroAtOdd = 0;
      const oddCount = textBytes.length / 2;
      for (let i = 1; i < textBytes.length; i += 2) {
        if (textBytes[i] === 0x00) {
          zeroAtOdd++;
        }
      }
      if (zeroAtOdd / oddCount > 0.3) {
        return EmbeddedLyricReader.decodeUtf16(textBytes).replace(/\0+$/g, '');
      }
    }
    return EmbeddedLyricReader.decodeUtf8(textBytes).replace(/\0+$/g, '');
  }

  private static parseMp4(bytes: Uint8Array): string | undefined {
    const target = [0xA9, 0x6C, 0x79, 0x72]; // '©lyr'
    let idx = EmbeddedLyricReader.indexOfBytes(bytes, target, 0);
    while (idx >= 0) {
      if (idx - 4 < 0) {
        break;
      }
      const size = (bytes[idx - 4] << 24) | (bytes[idx - 3] << 16) | (bytes[idx - 2] << 8) | bytes[idx - 1];
      if (size >= 8 && idx + size <= bytes.length) {
        const content = bytes.subarray(idx + 4, idx + size);
        const text = EmbeddedLyricReader.parseMp4DataAtom(content);
        if (text && text.trim().length > 0) {
          return text;
        }
      }
      idx = EmbeddedLyricReader.indexOfBytes(bytes, target, idx + 4);
    }

    // 兜底：裸 'lyr' atom（部分文件把歌词放在这里，且文本常为 UTF-16）
    const bareTarget = [0x6C, 0x79, 0x72]; // 'lyr'
    let bareIdx = EmbeddedLyricReader.indexOfBytes(bytes, bareTarget, 0);
    while (bareIdx >= 0) {
      if (bareIdx - 4 >= 0) {
        const size =
          (bytes[bareIdx - 4] << 24) | (bytes[bareIdx - 3] << 16) | (bytes[bareIdx - 2] << 8) | bytes[bareIdx - 1];
        // 'lyr' 之后紧跟 'data'（idx+3 起）时，把 data atom 对齐到 content[4..7]，
        // 使 parseMp4DataAtom 命中标准分支、正确取出文本。
        if (bareIdx + 7 <= bytes.length &&
          bytes[bareIdx + 3] === 0x64 && bytes[bareIdx + 4] === 0x61 &&
          bytes[bareIdx + 5] === 0x74 && bytes[bareIdx + 6] === 0x61) {
          const content = bytes.subarray(bareIdx - 1, bareIdx - 4 + size);
          const text = EmbeddedLyricReader.parseMp4DataAtom(content);
          if (text && text.trim().length > 0) {
            return text;
          }
        }
      }
      bareIdx = EmbeddedLyricReader.indexOfBytes(bytes, bareTarget, bareIdx + 3);
    }
    return undefined;
  }

  private static parseMp4DataAtom(content: Uint8Array): string | undefined {
    // 标准结构：4 字节 size + 4 字节 'data' + 4 字节 ver/flags + 4 字节 locale + 文本
    if (content.length >= 16 &&
      content[4] === 0x64 && content[5] === 0x61 && content[6] === 0x74 && content[7] === 0x61) {
      const text = content.subarray(16);
      return EmbeddedLyricReader.detectAndDecode(text).replace(/\0+$/g, '');
    }
    // 兜底：直接当文本解码
    return EmbeddedLyricReader.detectAndDecode(content).replace(/\0+$/g, '');
  }

  // ============================ MP3 (ID3v2) ============================

  private static parseMp3(bytes: Uint8Array): string | undefined {
    if (bytes.length < 10) {
      return undefined;
    }
    if (bytes[0] !== 0x49 || bytes[1] !== 0x44 || bytes[2] !== 0x44) {
      return undefined; // 'ID3'
    }
    const major = bytes[3];
    const tagSize = EmbeddedLyricReader.syncsafe(bytes[6], bytes[7], bytes[8], bytes[9]);
    let pos = 10;
    const end = Math.min(10 + tagSize, bytes.length);
    while (pos + 4 <= end) {
      const id0 = bytes[pos];
      if (id0 === 0) {
        break; // 进入 padding
      }
      let idLen: number;
      let sizeLen: number;
      let syncsafeSize: boolean;
      if (major === 2) {
        idLen = 3; sizeLen = 3; syncsafeSize = false;
      } else {
        idLen = 4; sizeLen = 4; syncsafeSize = (major === 4);
      }
      if (pos + idLen + sizeLen + 2 > end) {
        break;
      }
      const id = EmbeddedLyricReader.readFrameId(bytes, pos, idLen);
      let frameSize: number;
      if (sizeLen === 3) {
        frameSize = (bytes[pos + 3] | (bytes[pos + 4] << 8) | (bytes[pos + 5] << 16));
      } else {
        frameSize = syncsafeSize
          ? EmbeddedLyricReader.syncsafe(bytes[pos + 4], bytes[pos + 5], bytes[pos + 6], bytes[pos + 7])
          : ((bytes[pos + 4] << 24) | (bytes[pos + 5] << 16) | (bytes[pos + 6] << 8) | bytes[pos + 7]) >>> 0;
      }
      const dataStart = pos + idLen + sizeLen + (major === 2 ? 0 : 2);
      const frameEnd = Math.min(dataStart + frameSize, end);
      if (id === 'USLT' && frameSize > 0) {
        const text = EmbeddedLyricReader.parseUsltFrame(bytes.subarray(dataStart, frameEnd));
        if (text && text.trim().length > 0) {
          return text;
        }
      }
      if (frameSize <= 0) {
        break;
      }
      pos = dataStart + frameSize;
    }
    return undefined;
  }

  private static parseUsltFrame(frame: Uint8Array): string | undefined {
    if (frame.length < 4) {
      return undefined;
    }
    const enc = frame[0];
    let p = 1 + 3; // 跳过 encoding + 3 字节 language
    if (p >= frame.length) {
      return undefined;
    }
    // content descriptor 以 null 结尾（utf-16 为双字节 null）
    if (enc === 1 || enc === 2) {
      while (p + 1 < frame.length && !(frame[p] === 0 && frame[p + 1] === 0)) {
        p += 2;
      }
      p += 2;
    } else {
      while (p < frame.length && frame[p] !== 0) {
        p += 1;
      }
      p += 1;
    }
    if (p >= frame.length) {
      return undefined;
    }
    const textBytes = frame.subarray(p);
    let text: string;
    if (enc === 1) {
      text = EmbeddedLyricReader.decodeUtf16(textBytes);
    } else if (enc === 2) {
      text = EmbeddedLyricReader.decodeUtf16be(textBytes);
    } else if (enc === 3) {
      text = EmbeddedLyricReader.decodeUtf8(textBytes);
    } else {
      text = EmbeddedLyricReader.decodeLatin1(textBytes);
    }
    return text.replace(/\0+$/g, '');
  }

  // ============================ 工具方法 ============================

  private static le32(b: Uint8Array, off: number): number {
    return (b[off] | (b[off + 1] << 8) | (b[off + 2] << 16) | (b[off + 3] << 24)) >>> 0;
  }

  private static syncsafe(a: number, b: number, c: number, d: number): number {
    return ((a & 0x7F) << 21) | ((b & 0x7F) << 14) | ((c & 0x7F) << 7) | (d & 0x7F);
  }

  private static indexOfBytes(hay: Uint8Array, needle: number[], from: number): number {
    const n = needle.length;
    for (let i = from; i + n <= hay.length; i++) {
      let ok = true;
      for (let j = 0; j < n; j++) {
        if (hay[i + j] !== needle[j]) {
          ok = false;
          break;
        }
      }
      if (ok) {
        return i;
      }
    }
    return -1;
  }

  private static readFrameId(b: Uint8Array, off: number, len: number): string {
    let s = '';
    for (let i = 0; i < len; i++) {
      s += String.fromCharCode(b[off + i]);
    }
    return s;
  }

  private static decodeUtf8(bytes: Uint8Array): string {
    const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
    return decoder.decodeToString(bytes, { stream: false });
  }

  private static decodeUtf16(bytes: Uint8Array): string {
    let b = bytes;
    if (b.length >= 2 && ((b[0] === 0xFF && b[1] === 0xFE) || (b[0] === 0xFE && b[1] === 0xFF))) {
      b = b.subarray(2);
    }
    try {
      const decoder = util.TextDecoder.create('utf-16le', { ignoreBOM: true });
      return decoder.decodeToString(b, { stream: false });
    } catch (e) {
      return EmbeddedLyricReader.decodeLatin1(b);
    }
  }

  private static decodeUtf16be(bytes: Uint8Array): string {
    let b = bytes;
    if (b.length >= 2 && b[0] === 0xFE && b[1] === 0xFF) {
      b = b.subarray(2);
    }
    try {
      const decoder = util.TextDecoder.create('utf-16be', { ignoreBOM: true });
      return decoder.decodeToString(b, { stream: false });
    } catch (e) {
      return EmbeddedLyricReader.decodeLatin1(b);
    }
  }

  private static decodeLatin1(bytes: Uint8Array): string {
    let s = '';
    for (let i = 0; i < bytes.length; i++) {
      s += String.fromCharCode(bytes[i]);
    }
    return s;
  }
}
