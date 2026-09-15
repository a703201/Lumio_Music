/*
 * Copyright 2026 何宇翔
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
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

/*
 * 音频标签写入器（纯 ArkTS，不依赖 C++ NAPI）。
 *
 * 支持格式：
 *  - FLAC    : 解析 METADATA_BLOCK，定位/新建 VORBIS_COMMENT 块，重写 TITLE/ARTIST/ALBUM/DATE。
 *  - MP3     : 解析/新建 ID3v2.3 标签，写 TIT2/TPE1/TALB/TYER 帧（UTF-8 编码）。
 *  - MP4/M4A : 定位/新建 moov→udta→meta→ilst，写 ©nam/©ART/©alb/©day 文本 atom（UTF-8）。
 *              改写 ilst 会改变 moov 体积；若 moov 位于 mdat 之前，则其后所有字节（含 mdat）
 *              绝对偏移随之平移，故同步修正所有 stco(32-bit)/co64(64-bit) chunk offset 表。
 *  - WAV     : 解析/新建 RIFF 的 LIST/INFO chunk，写 INAM/IART/IPRD/ICRD，维护偶数对齐与 RIFF size。
 * 其余格式（ogg/ape/wma/...）返回 -1（不支持），由 UI 提示「该音频格式暂不支持编辑标签」。
 *
 * 安全策略：写入前先把原文件复制为 `<src>.tagbak` 备份；新内容先写 `<src>.tmptag` 再 rename 覆盖，
 * 任一环节失败均回退（原子性），绝不直接在原文件上 truncate，避免损坏用户音频。
 *
 * 错误码：0 成功；-1 不支持的格式；-2 读取失败；-3 写入失败；-4 备份失败；
 *        -5 容器结构无法安全改写（如 MP4 无 moov、多 mdat、偏移越界），已放弃以避免损坏文件。
 */

import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { Logger } from './Logger';

const TAG: string = 'TagWriter';

export interface TagFields {
  title?: string;
  artist?: string;
  album?: string;
  year?: string;
}

interface FlacBlock {
  type: number;
  data: Uint8Array;
  isLast: boolean;
}

interface VorbisComments {
  vendor: Uint8Array;
  comments: Array<string>;
}

/** MP4 atom 头。 */
interface BoxHeader {
  size: number;
  headerSize: number;
}

/** MP4 atom 在缓冲区内的位置（offset 指向 atom 起始，含头）。 */
interface BoxRef {
  offset: number;
  size: number;
  headerSize: number;
}

export class TagWriter {
  /** 写入文本标签；fields 只填要更新的字段。返回错误码（见文件头）。 */
  static async writeTags(src: string, fields: TagFields): Promise<number> {
    const data: Uint8Array | undefined = await TagWriter.readAll(src);
    if (!data) {
      return -2;
    }
    const fmt: string = TagWriter.detectFormat(data);
    if (fmt === 'flac') {
      const out: Uint8Array | undefined = TagWriter.buildFlac(data, fields);
      if (!out) {
        return -1;
      }
      return await TagWriter.atomicWrite(src, out);
    } else if (fmt === 'mp3') {
      const out: Uint8Array | undefined = TagWriter.buildMp3(data, fields);
      if (!out) {
        return -1;
      }
      return await TagWriter.atomicWrite(src, out);
    } else if (fmt === 'mp4') {
      const out: Uint8Array | undefined = TagWriter.buildMp4(data, fields);
      if (!out) {
        return -5;
      }
      return await TagWriter.atomicWrite(src, out);
    } else if (fmt === 'wav') {
      const out: Uint8Array | undefined = TagWriter.buildWav(data, fields);
      if (!out) {
        return -5;
      }
      return await TagWriter.atomicWrite(src, out);
    }
    return -1;
  }

  /**
   * 依据扩展名粗判该文件是否可能可编辑（UI 预检用，避免用户白填一顿再失败）。
   * 仅对「已知不支持」的容器返回 false；扩展名缺失或未知一律返回 true，最终由内容探测裁决。
   */
  static isEditableFormat(src: string): boolean {
    const lower: string = src.toLowerCase();
    const dot: number = lower.lastIndexOf('.');
    if (dot < 0) {
      return true;
    }
    const ext: string = lower.substring(dot);
    const unsupported: Array<string> = ['.ogg', '.oga', '.opus', '.ape', '.wma', '.wv',
      '.aiff', '.aif', '.m4p', '.mp2', '.amr', '.mpc', '.tak', '.dsf', '.dff', '.aac'];
    return unsupported.indexOf(ext) < 0;
  }

  // ============================ 文件 I/O ============================

  private static async readAll(src: string): Promise<Uint8Array | undefined> {
    let file: fs.File | undefined;
    try {
      file = fs.openSync(src, fs.OpenMode.READ_ONLY);
      const size: number = fs.statSync(src).size;
      if (size <= 0) {
        return undefined;
      }
      const buf: ArrayBuffer = new ArrayBuffer(size);
      let offset: number = 0;
      while (offset < size) {
        const read: number = fs.readSync(file.fd, buf, { offset: offset, length: size - offset });
        if (read <= 0) {
          break;
        }
        offset += read;
      }
      return new Uint8Array(buf, 0, offset);
    } catch (e) {
      Logger.error(TAG, 'readAll failed: ' + (e as Error).message);
      return undefined;
    } finally {
      if (file) {
        try {
          fs.closeSync(file);
        } catch (_) {
          // ignore
        }
      }
    }
  }

  /** 先备份原文件为 .tagbak，再把新内容写 .tmptag 并 rename 覆盖；失败回退。 */
  private static async atomicWrite(src: string, data: Uint8Array): Promise<number> {
    const bak: string = src + '.tagbak';
    try {
      if (!fs.accessSync(bak)) {
        const srcF: fs.File = fs.openSync(src, fs.OpenMode.READ_ONLY);
        const bakF: fs.File = fs.openSync(bak, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
        fs.copyFileSync(srcF.fd, bakF.fd);
        fs.closeSync(srcF);
        fs.closeSync(bakF);
      }
    } catch (e) {
      Logger.error(TAG, 'backup failed: ' + (e as Error).message);
      return -4;
    }
    const tmp: string = src + '.tmptag';
    try {
      const tf: fs.File = fs.openSync(tmp, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(tf.fd, data.buffer);
      fs.closeSync(tf);
      fs.renameSync(tmp, src);
      return 0;
    } catch (e) {
      Logger.error(TAG, 'atomicWrite failed: ' + (e as Error).message);
      return -3;
    }
  }

  // ============================ 格式探测 ============================

  private static detectFormat(data: Uint8Array): string {
    if (data.length >= 4 && data[0] === 0x66 && data[1] === 0x4C && data[2] === 0x61 && data[3] === 0x43) {
      return 'flac';
    }
    if (data.length >= 3 && data[0] === 0x49 && data[1] === 0x44 && data[2] === 0x33) {
      return 'mp3';
    }
    // 无 ID3 头的 MP3：首帧同步位 11111111 1xxxxxxx（0xFF 0xE0~0xFF）
    if (data.length >= 2 && data[0] === 0xFF && (data[1] & 0xE0) === 0xE0) {
      return 'mp3';
    }
    // MP4 / M4A / MOV：首个 box 为 'ftyp'（size 之后紧跟 f t y p）
    if (data.length >= 8 && data[4] === 0x66 && data[5] === 0x74 && data[6] === 0x79 && data[7] === 0x70) {
      return 'mp4';
    }
    // WAV：'RIFF' .... 'WAVE'
    if (data.length >= 12 && data[0] === 0x52 && data[1] === 0x49 && data[2] === 0x46 && data[3] === 0x46 &&
      data[8] === 0x57 && data[9] === 0x41 && data[10] === 0x56 && data[11] === 0x45) {
      return 'wav';
    }
    return 'unknown';
  }

  // ============================ FLAC ============================

  private static findFlacStart(data: Uint8Array): number {
    if (data.length >= 4 && data[0] === 0x66 && data[1] === 0x4C && data[2] === 0x61 && data[3] === 0x43) {
      return 0;
    }
    // 少数文件前导一段 ID3v2，跳过
    if (data.length >= 10 && data[0] === 0x49 && data[1] === 0x44 && data[2] === 0x33) {
      const size: number = TagWriter.syncsafe(data[6], data[7], data[8], data[9]);
      const start: number = 10 + size;
      if (start + 4 <= data.length &&
        data[start] === 0x66 && data[start + 1] === 0x4C && data[start + 2] === 0x61 && data[start + 3] === 0x43) {
        return start;
      }
    }
    return -1;
  }

  private static parseFlacBlocks(data: Uint8Array, start: number): Array<FlacBlock> {
    const blocks: Array<FlacBlock> = [];
    let pos: number = start + 4;
    let guard: number = 0;
    while (pos + 4 <= data.length && guard < 256) {
      guard++;
      const header: number = data[pos];
      const isLast: boolean = (header & 0x80) !== 0;
      const type: number = header & 0x7F;
      const blockSize: number = (data[pos + 1] << 16) | (data[pos + 2] << 8) | data[pos + 3];
      if (blockSize < 0 || pos + 4 + blockSize > data.length) {
        break;
      }
      const blockData: Uint8Array = data.subarray(pos + 4, pos + 4 + blockSize);
      blocks.push({ type: type, data: blockData, isLast: isLast });
      pos += 4 + blockSize;
      if (isLast) {
        break;
      }
    }
    return blocks;
  }

  private static parseVorbis(body: Uint8Array): VorbisComments | undefined {
    if (body.length < 8) {
      return undefined;
    }
    let p: number = 0;
    const vendorLen: number = TagWriter.le32(body, p);
    p += 4;
    if (p + vendorLen > body.length) {
      return undefined;
    }
    const vendor: Uint8Array = body.subarray(p, p + vendorLen);
    p += vendorLen;
    if (p + 4 > body.length) {
      return undefined;
    }
    const count: number = TagWriter.le32(body, p);
    p += 4;
    const comments: Array<string> = [];
    for (let i: number = 0; i < count; i++) {
      if (p + 4 > body.length) {
        break;
      }
      const itemLen: number = TagWriter.le32(body, p);
      p += 4;
      if (itemLen < 0 || p + itemLen > body.length) {
        break;
      }
      comments.push(TagWriter.decodeUtf8(body.subarray(p, p + itemLen)));
      p += itemLen;
    }
    return { vendor: vendor, comments: comments };
  }

  /** 重建 VORBIS_COMMENT 块：丢弃旧 TITLE/ARTIST/ALBUM/DATE，按 fields 重新写入，保留其余注释与 vendor。 */
  private static rebuildVorbis(vendor: Uint8Array, comments: Array<string>, fields: TagFields): Uint8Array {
    const DROP: Array<string> = ['TITLE', 'ARTIST', 'ALBUM', 'DATE', 'TYER', 'TALB', 'TPE1', 'TIT2'];
    const keep: Array<string> = [];
    for (const c of comments) {
      const eq: number = c.indexOf('=');
      const key: string = eq > 0 ? c.substring(0, eq).toUpperCase() : '';
      if (DROP.indexOf(key) >= 0) {
        continue;
      }
      keep.push(c);
    }
    const added: Array<string> = [];
    if (fields.title && fields.title.length > 0) {
      added.push('TITLE=' + fields.title);
    }
    if (fields.artist && fields.artist.length > 0) {
      added.push('ARTIST=' + fields.artist);
    }
    if (fields.album && fields.album.length > 0) {
      added.push('ALBUM=' + fields.album);
    }
    if (fields.year && fields.year.length > 0) {
      added.push('DATE=' + fields.year);
    }
    const all: Array<string> = keep.concat(added);

    const chunks: Array<Uint8Array> = [];
    const vendorBytes: Uint8Array = vendor.length > 0 ? vendor : new Uint8Array(0);
    chunks.push(TagWriter.u32(vendorBytes.length));
    chunks.push(vendorBytes);
    chunks.push(TagWriter.u32(all.length));
    for (const comment of all) {
      const cb: Uint8Array = TagWriter.utf8Bytes(comment);
      chunks.push(TagWriter.u32(cb.length));
      chunks.push(cb);
    }
    return TagWriter.concatBytes(chunks);
  }

  private static buildFlac(data: Uint8Array, fields: TagFields): Uint8Array | undefined {
    const start: number = TagWriter.findFlacStart(data);
    if (start < 0) {
      return undefined;
    }
    const blocks: Array<FlacBlock> = TagWriter.parseFlacBlocks(data, start);
    if (blocks.length === 0) {
      return undefined;
    }
    let idx: number = -1;
    for (let i: number = 0; i < blocks.length; i++) {
      if (blocks[i].type === 4) {
        idx = i;
        break;
      }
    }
    if (idx >= 0) {
      const parsed = TagWriter.parseVorbis(blocks[idx].data);
      if (!parsed) {
        return undefined;
      }
      blocks[idx].data = TagWriter.rebuildVorbis(parsed.vendor, parsed.comments, fields);
    } else {
      const newData: Uint8Array = TagWriter.rebuildVorbis(new Uint8Array(0), [], fields);
      for (let i: number = 0; i < blocks.length; i++) {
        if (blocks[i].isLast) {
          blocks[i].isLast = false;
        }
      }
      blocks.push({ type: 4, data: newData, isLast: true });
    }
    const chunks: Array<Uint8Array> = [new Uint8Array([0x66, 0x4C, 0x61, 0x43])];
    for (const b of blocks) {
      const isLastByte: number = b.isLast ? 0x80 : 0x00;
      const len: number = b.data.length;
      const header: Uint8Array = new Uint8Array([
        (isLastByte | (b.type & 0x7F)) & 0xFF,
        (len >> 16) & 0xFF,
        (len >> 8) & 0xFF,
        len & 0xFF
      ]);
      chunks.push(header);
      chunks.push(b.data);
    }
    return TagWriter.concatBytes(chunks);
  }

  // ============================ MP3 (ID3v2.3) ============================

  private static buildMp3(data: Uint8Array, fields: TagFields): Uint8Array | undefined {
    const hasId3: boolean = data.length >= 10 && data[0] === 0x49 && data[1] === 0x44 && data[2] === 0x33;
    let content: Uint8Array;
    if (hasId3) {
      const size: number = TagWriter.syncsafe(data[6], data[7], data[8], data[9]);
      const audioStart: number = 10 + size;
      if (audioStart > data.length) {
        return undefined;
      }
      content = data.subarray(audioStart);
    } else {
      content = data;
    }

    const frameChunks: Array<Uint8Array> = [];
    const addFrame = (id: string, text: string): void => {
      const tb: Uint8Array = TagWriter.utf8Bytes(text);
      const bodyLen: number = 1 + tb.length;
      const header: Uint8Array = new Uint8Array(10);
      for (let i: number = 0; i < 4; i++) {
        header[i] = id.charCodeAt(i);
      }
      header[4] = (bodyLen >> 24) & 0xFF;
      header[5] = (bodyLen >> 16) & 0xFF;
      header[6] = (bodyLen >> 8) & 0xFF;
      header[7] = bodyLen & 0xFF;
      header[8] = 0x00;
      header[9] = 0x00;
      const body: Uint8Array = new Uint8Array(1 + tb.length);
      body[0] = 0x03; // 编码：UTF-8
      for (let i: number = 0; i < tb.length; i++) {
        body[1 + i] = tb[i];
      }
      frameChunks.push(header);
      frameChunks.push(body);
    };
    if (fields.title && fields.title.length > 0) {
      addFrame('TIT2', fields.title);
    }
    if (fields.artist && fields.artist.length > 0) {
      addFrame('TPE1', fields.artist);
    }
    if (fields.album && fields.album.length > 0) {
      addFrame('TALB', fields.album);
    }
    if (fields.year && fields.year.length > 0) {
      addFrame('TYER', fields.year);
    }

    const frames: Uint8Array = TagWriter.concatBytes(frameChunks);
    const total: number = frames.length;
    const tagHeader: Uint8Array = new Uint8Array(10);
    tagHeader[0] = 0x49; // I
    tagHeader[1] = 0x44; // D
    tagHeader[2] = 0x33; // 3
    tagHeader[3] = 0x03; // 版本 2.3
    tagHeader[4] = 0x00;
    tagHeader[5] = 0x00;
    tagHeader[6] = (total >> 21) & 0x7F;
    tagHeader[7] = (total >> 14) & 0x7F;
    tagHeader[8] = (total >> 7) & 0x7F;
    tagHeader[9] = total & 0x7F;
    return TagWriter.concatBytes([tagHeader, frames, content]);
  }

  // ============================ MP4 / M4A ============================

  /**
   * 重建 MP4/M4A：在 moov→udta→meta→ilst 下写入 ©nam/©ART/©alb/©day。
   * 策略是「定位 moov、就地重建其 udta/meta/ilst 子树、按需修正 stco/co64 绝对偏移」，
   * 从不移动 moov 的顶层位置，因此 moov 在前（faststart）与在 mdat 之后都能处理。
   * 返回 undefined 表示无法安全改写（无 moov、多 mdat、偏移越界等），由调用方映射为 -5。
   */
  private static buildMp4(data: Uint8Array, fields: TagFields): Uint8Array | undefined {
    let moovOff: number = -1;
    let moovSize: number = 0;
    let moovHeader: number = 8;
    let mdatCount: number = 0;
    let mdatStart: number = -1;
    let pos: number = 0;
    while (pos + 8 <= data.length) {
      const h: BoxHeader | undefined = TagWriter.parseBox(data, pos, data.length);
      if (!h) {
        break;
      }
      const t: string = TagWriter.typeAt(data, pos + 4);
      if (t === 'moov') {
        moovOff = pos;
        moovSize = h.size;
        moovHeader = h.headerSize;
      } else if (t === 'mdat') {
        mdatCount++;
        if (mdatStart < 0) {
          mdatStart = pos;
        }
      }
      pos += h.size;
    }
    if (moovOff < 0 || mdatCount > 1) {
      Logger.warn(TAG, 'buildMp4: no moov or ambiguous mdat, refuse to rewrite');
      return undefined;
    }
    const moovBodyStart: number = moovOff + moovHeader;
    const moovBodyEnd: number = moovOff + moovSize;

    // udta（可能不存在）
    const udta: BoxRef | undefined = TagWriter.findBox(data, moovBodyStart, moovBodyEnd, 'udta');
    let udtaBodyStart: number = 0;
    let udtaBodyEnd: number = 0;
    if (udta) {
      udtaBodyStart = udta.offset + udta.headerSize;
      udtaBodyEnd = udta.offset + udta.size;
    }

    // meta（FullBox：子 box 从 body+4 起）
    let metaBodyStart: number = 0;
    let metaBodyEnd: number = 0;
    let metaVF: Uint8Array = new Uint8Array(4);
    if (udta) {
      const meta: BoxRef | undefined = TagWriter.findBox(data, udtaBodyStart, udtaBodyEnd, 'meta');
      if (meta) {
        const mStart: number = meta.offset + meta.headerSize;
        metaVF = data.subarray(mStart, mStart + 4);
        metaBodyStart = mStart + 4;
        metaBodyEnd = meta.offset + meta.size;
      }
    }
    const hasMeta: boolean = metaBodyEnd > metaBodyStart;

    // ilst（可能不存在）
    let ilstBody: Uint8Array = new Uint8Array(0);
    if (hasMeta) {
      const ilst: BoxRef | undefined = TagWriter.findBox(data, metaBodyStart, metaBodyEnd, 'ilst');
      if (ilst) {
        ilstBody = data.subarray(ilst.offset + ilst.headerSize, ilst.offset + ilst.size);
      }
    }
    const newIlst: Uint8Array = TagWriter.makeBox('ilst', TagWriter.buildIlstBody(ilstBody, fields));

    // 重建 meta → udta → moov（自内向外更新各级 size）
    let newMetaChildren: Uint8Array;
    if (hasMeta) {
      const existingMetaChildren: Uint8Array = data.subarray(metaBodyStart, metaBodyEnd);
      newMetaChildren = TagWriter.upsertChild(existingMetaChildren, 'ilst', newIlst);
    } else {
      newMetaChildren = TagWriter.concatBytes([TagWriter.makeHdlrBox(), newIlst]);
    }
    const metaVFBytes: Uint8Array = hasMeta ? metaVF : new Uint8Array(4);
    const newMeta: Uint8Array = TagWriter.makeBox('meta', TagWriter.concatBytes([metaVFBytes, newMetaChildren]));

    let newUdta: Uint8Array;
    if (udta) {
      const existingUdta: Uint8Array = data.subarray(udtaBodyStart, udtaBodyEnd);
      newUdta = TagWriter.makeBox('udta', TagWriter.upsertChild(existingUdta, 'meta', newMeta));
    } else {
      newUdta = TagWriter.makeBox('udta', newMeta);
    }

    const existingMoovBody: Uint8Array = data.subarray(moovBodyStart, moovBodyEnd);
    const newMoov: Uint8Array = TagWriter.makeBox('moov', TagWriter.upsertChild(existingMoovBody, 'udta', newUdta));

    // moov 在 mdat 之前时，moov 体积变化会平移其后全部字节（含 mdat）→ 修正 chunk 偏移
    const delta: number = newMoov.length - moovSize;
    if (delta !== 0 && mdatStart > moovOff) {
      if (!TagWriter.fixChunkOffsets(newMoov, 8, newMoov.length, delta)) {
        Logger.warn(TAG, 'buildMp4: chunk offset fixup failed, refuse to rewrite');
        return undefined;
      }
    }

    const before: Uint8Array = data.subarray(0, moovOff);
    const after: Uint8Array = data.subarray(moovOff + moovSize);
    return TagWriter.concatBytes([before, newMoov, after]);
  }

  /** 重建 ilst：丢弃既有 4 个目标 atom，按 fields 追加非空项，其余条目原样保留。 */
  private static buildIlstBody(existing: Uint8Array, fields: TagFields): Uint8Array {
    const drop: Array<string> = ['\u00A9nam', '\u00A9ART', '\u00A9alb', '\u00A9day'];
    const chunks: Array<Uint8Array> = [];
    let pos: number = 0;
    while (pos + 8 <= existing.length) {
      const h: BoxHeader | undefined = TagWriter.parseBox(existing, pos, existing.length);
      if (!h) {
        break;
      }
      if (drop.indexOf(TagWriter.typeAt(existing, pos + 4)) < 0) {
        chunks.push(existing.subarray(pos, pos + h.size));
      }
      pos += h.size;
    }
    if (fields.title && fields.title.length > 0) {
      chunks.push(TagWriter.makeTextItem('\u00A9nam', fields.title));
    }
    if (fields.artist && fields.artist.length > 0) {
      chunks.push(TagWriter.makeTextItem('\u00A9ART', fields.artist));
    }
    if (fields.album && fields.album.length > 0) {
      chunks.push(TagWriter.makeTextItem('\u00A9alb', fields.album));
    }
    if (fields.year && fields.year.length > 0) {
      chunks.push(TagWriter.makeTextItem('\u00A9day', fields.year));
    }
    return TagWriter.concatBytes(chunks);
  }

  /** 构造 MP4 box：size(4,BE) + type(4) + body。 */
  private static makeBox(type: string, body: Uint8Array): Uint8Array {
    const size: number = 8 + body.length;
    const header: Uint8Array = new Uint8Array(8);
    header[0] = (size >>> 24) & 0xFF;
    header[1] = (size >>> 16) & 0xFF;
    header[2] = (size >>> 8) & 0xFF;
    header[3] = size & 0xFF;
    for (let i: number = 0; i < 4; i++) {
      header[4 + i] = type.charCodeAt(i) & 0xFF;
    }
    return TagWriter.concatBytes([header, body]);
  }

  /** iTunes 元数据 meta 所需的最小 hdlr（handler_type='mdir'，size=33）。 */
  private static makeHdlrBox(): Uint8Array {
    const body: Uint8Array = new Uint8Array(25);
    body[8] = 0x6D; // m
    body[9] = 0x64; // d
    body[10] = 0x69; // i
    body[11] = 0x72; // r
    return TagWriter.makeBox('hdlr', body);
  }

  /** ilst 文本项：item 内含一个 data atom（type indicator=1 表示 UTF-8，locale=0）。 */
  private static makeTextItem(type: string, value: string): Uint8Array {
    const v: Uint8Array = TagWriter.utf8Bytes(value);
    const dataBody: Uint8Array = new Uint8Array(8 + v.length);
    dataBody[3] = 0x01; // type indicator = 1（UTF-8 文本）
    dataBody.set(v, 8);
    return TagWriter.makeBox(type, TagWriter.makeBox('data', dataBody));
  }

  /** 用 child 替换 container 中首个 type 子 box；不存在则追加到末尾；其余子 box 原样保留其顺序。 */
  private static upsertChild(container: Uint8Array, type: string, child: Uint8Array): Uint8Array {
    const chunks: Array<Uint8Array> = [];
    let replaced: boolean = false;
    let pos: number = 0;
    while (pos + 8 <= container.length) {
      const h: BoxHeader | undefined = TagWriter.parseBox(container, pos, container.length);
      if (!h) {
        break;
      }
      if (!replaced && TagWriter.typeAt(container, pos + 4) === type) {
        chunks.push(child);
        replaced = true;
      } else {
        chunks.push(container.subarray(pos, pos + h.size));
      }
      pos += h.size;
    }
    if (!replaced) {
      chunks.push(child);
    }
    if (pos < container.length) {
      chunks.push(container.subarray(pos)); // 保留无法解析的尾部字节，避免潜在数据丢失
    }
    return TagWriter.concatBytes(chunks);
  }

  /** 在 [start,end) 内查找首个 type 子 box。 */
  private static findBox(b: Uint8Array, start: number, end: number, type: string): BoxRef | undefined {
    let pos: number = start;
    while (pos + 8 <= end) {
      const h: BoxHeader | undefined = TagWriter.parseBox(b, pos, end);
      if (!h) {
        return undefined;
      }
      if (TagWriter.typeAt(b, pos + 4) === type) {
        const ref: BoxRef = { offset: pos, size: h.size, headerSize: h.headerSize };
        return ref;
      }
      pos += h.size;
    }
    return undefined;
  }

  /** 解析 box 头：支持 32-bit size、size==1 的 64-bit largesize、size==0 延伸到 limit。 */
  private static parseBox(b: Uint8Array, off: number, limit: number): BoxHeader | undefined {
    if (off + 8 > limit) {
      return undefined;
    }
    const size32: number = TagWriter.be32(b, off);
    let headerSize: number = 8;
    let size: number = size32;
    if (size32 === 1) {
      if (off + 16 > limit) {
        return undefined;
      }
      size = TagWriter.be64(b, off + 8);
      headerSize = 16;
    } else if (size32 === 0) {
      size = limit - off;
    }
    if (size < headerSize || off + size > limit) {
      return undefined;
    }
    const header: BoxHeader = { size: size, headerSize: headerSize };
    return header;
  }

  /**
   * 递归修正 stco(32-bit)/co64(64-bit) chunk 绝对偏移，整体 +delta。
   * 返回 false 表示遇到无法安全表示的偏移（越界），调用方应放弃写入。
   */
  private static fixChunkOffsets(region: Uint8Array, start: number, end: number, delta: number): boolean {
    let pos: number = start;
    while (pos + 8 <= end) {
      const h: BoxHeader | undefined = TagWriter.parseBox(region, pos, end);
      if (!h) {
        return false;
      }
      const t: string = TagWriter.typeAt(region, pos + 4);
      const bodyStart: number = pos + h.headerSize;
      const bodyEnd: number = pos + h.size;
      if (t === 'stco') {
        if (!TagWriter.patchStco(region, bodyStart, bodyEnd, delta)) {
          return false;
        }
      } else if (t === 'co64') {
        if (!TagWriter.patchCo64(region, bodyStart, bodyEnd, delta)) {
          return false;
        }
      } else if (t === 'meta') {
        if (!TagWriter.fixChunkOffsets(region, bodyStart + 4, bodyEnd, delta)) {
          return false;
        }
      } else if (TagWriter.isMp4Container(t)) {
        if (!TagWriter.fixChunkOffsets(region, bodyStart, bodyEnd, delta)) {
          return false;
        }
      }
      pos += h.size;
    }
    return true;
  }

  /** stco：FullBox(4) + entry_count(4) + N×u32 绝对值。 */
  private static patchStco(region: Uint8Array, start: number, end: number, delta: number): boolean {
    if (start + 8 > end) {
      return false;
    }
    const count: number = TagWriter.be32(region, start + 4);
    let p: number = start + 8;
    for (let i: number = 0; i < count; i++) {
      if (p + 4 > end) {
        return false;
      }
      const v: number = TagWriter.be32(region, p);
      const nv: number = v + delta;
      if (nv < 0 || nv > 0xFFFFFFFF) {
        return false; // 32-bit 无法表示：需升级为 co64，超出安全范围，放弃
      }
      region[p] = (nv >>> 24) & 0xFF;
      region[p + 1] = (nv >>> 16) & 0xFF;
      region[p + 2] = (nv >>> 8) & 0xFF;
      region[p + 3] = nv & 0xFF;
      p += 4;
    }
    return true;
  }

  /** co64：FullBox(4) + entry_count(4) + N×u64 绝对值。 */
  private static patchCo64(region: Uint8Array, start: number, end: number, delta: number): boolean {
    if (start + 8 > end) {
      return false;
    }
    const count: number = TagWriter.be32(region, start + 4);
    let p: number = start + 8;
    for (let i: number = 0; i < count; i++) {
      if (p + 8 > end) {
        return false;
      }
      const v: number = TagWriter.be64(region, p);
      const nv: number = v + delta;
      if (nv < 0) {
        return false;
      }
      TagWriter.writeBe64(region, p, nv);
      p += 8;
    }
    return true;
  }

  /** 需要在偏移修正时递归下钻的容器类型（stco/co64 位于其内）。 */
  private static isMp4Container(type: string): boolean {
    return type === 'moov' || type === 'trak' || type === 'mdia' || type === 'minf' ||
      type === 'stbl' || type === 'edts' || type === 'udta' || type === 'mvex' ||
      type === 'moof' || type === 'traf' || type === 'mfra' || type === 'dinf' ||
      type === 'sinf' || type === 'wave' || type === 'ilst';
  }

  // ============================ WAV (RIFF) ============================

  /**
   * 重建 WAV：在 RIFF 的 LIST/INFO 写入 INAM/IART/IPRD/ICRD。
   * 保留 INFO 中其余条目；无 LIST/INFO 时插入到 data chunk 之前（惯用位置）。
   * 维护子 chunk 偶数对齐（奇数长度补 1 字节 pad）并重算外层 RIFF size。
   */
  private static buildWav(data: Uint8Array, fields: TagFields): Uint8Array | undefined {
    if (data.length < 12) {
      return undefined;
    }
    if (!(data[0] === 0x52 && data[1] === 0x49 && data[2] === 0x46 && data[3] === 0x46)) {
      return undefined; // 'RIFF'
    }
    if (!(data[8] === 0x57 && data[9] === 0x41 && data[10] === 0x56 && data[11] === 0x45)) {
      return undefined; // 'WAVE'
    }

    const chunks: Array<Uint8Array> = [];
    let emittedList: boolean = false;
    let pos: number = 12;
    while (pos + 8 <= data.length) {
      const id: string = TagWriter.typeAt(data, pos);
      const size: number = TagWriter.le32(data, pos + 4);
      const contentEnd: number = pos + 8 + size;
      if (contentEnd > data.length) {
        break; // 截断/损坏：保留已解析部分
      }
      const paddedEnd: number = Math.min(contentEnd + (size & 1), data.length);
      const isInfo: boolean = id === 'LIST' && size >= 4 && TagWriter.typeAt(data, pos + 8) === 'INFO';

      if (isInfo && !emittedList) {
        const kept: Array<Uint8Array> = TagWriter.parseInfoEntries(data, pos + 12, pos + 8 + size);
        chunks.push(TagWriter.buildInfoListChunk(kept, fields));
        emittedList = true;
      } else if (id === 'data' && !emittedList) {
        chunks.push(TagWriter.buildInfoListChunk([], fields)); // 无既有 INFO：插入到 data 之前
        emittedList = true;
        chunks.push(data.subarray(pos, paddedEnd));
      } else {
        chunks.push(data.subarray(pos, paddedEnd));
      }
      pos = paddedEnd;
    }
    if (pos < data.length) {
      chunks.push(data.subarray(pos));
    }
    if (!emittedList) {
      chunks.push(TagWriter.buildInfoListChunk([], fields));
    }

    const body: Uint8Array = TagWriter.concatBytes(chunks);
    const riffSize: number = 4 + body.length; // 'WAVE'(4) + 后续所有 chunk
    if (riffSize > 0xFFFFFFFF) {
      return undefined;
    }
    const out: Uint8Array = new Uint8Array(12 + body.length);
    out[0] = 0x52;
    out[1] = 0x49;
    out[2] = 0x46;
    out[3] = 0x46; // RIFF
    out[4] = riffSize & 0xFF;
    out[5] = (riffSize >>> 8) & 0xFF;
    out[6] = (riffSize >>> 16) & 0xFF;
    out[7] = (riffSize >>> 24) & 0xFF;
    out[8] = 0x57;
    out[9] = 0x41;
    out[10] = 0x56;
    out[11] = 0x45; // WAVE
    out.set(body, 12);
    return out;
  }

  /** 构建 LIST/INFO chunk：'INFO' + 保留条目 + 新增 4 项。 */
  private static buildInfoListChunk(kept: Array<Uint8Array>, fields: TagFields): Uint8Array {
    const chunks: Array<Uint8Array> = [];
    chunks.push(new Uint8Array([0x49, 0x4E, 0x46, 0x4F])); // 'INFO'
    for (const e of kept) {
      chunks.push(e);
    }
    if (fields.title && fields.title.length > 0) {
      chunks.push(TagWriter.makeInfoEntry('INAM', fields.title));
    }
    if (fields.artist && fields.artist.length > 0) {
      chunks.push(TagWriter.makeInfoEntry('IART', fields.artist));
    }
    if (fields.album && fields.album.length > 0) {
      chunks.push(TagWriter.makeInfoEntry('IPRD', fields.album));
    }
    if (fields.year && fields.year.length > 0) {
      chunks.push(TagWriter.makeInfoEntry('ICRD', fields.year));
    }
    return TagWriter.makeRiffChunk('LIST', TagWriter.concatBytes(chunks));
  }

  /** INFO 子项：值按惯例以 NUL 结尾。 */
  private static makeInfoEntry(id: string, value: string): Uint8Array {
    const v: Uint8Array = TagWriter.utf8Bytes(value);
    const payload: Uint8Array = new Uint8Array(v.length + 1);
    payload.set(v, 0);
    return TagWriter.makeRiffChunk(id, payload);
  }

  /** RIFF chunk：id(4) + size(4,LE) + payload + 奇数补 1 字节 pad。 */
  private static makeRiffChunk(id: string, payload: Uint8Array): Uint8Array {
    const size: number = payload.length;
    const header: Uint8Array = new Uint8Array(8);
    for (let i: number = 0; i < 4; i++) {
      header[i] = id.charCodeAt(i) & 0xFF;
    }
    header[4] = size & 0xFF;
    header[5] = (size >>> 8) & 0xFF;
    header[6] = (size >>> 16) & 0xFF;
    header[7] = (size >>> 24) & 0xFF;
    if ((size & 1) === 1) {
      const padded: Uint8Array = new Uint8Array(size + 1);
      padded.set(payload, 0);
      return TagWriter.concatBytes([header, padded]);
    }
    return TagWriter.concatBytes([header, payload]);
  }

  /** 解析 INFO 子项，返回「非 4 个目标键」的原始子 chunk 字节（含各自 pad）。 */
  private static parseInfoEntries(data: Uint8Array, start: number, end: number): Array<Uint8Array> {
    const drop: Array<string> = ['INAM', 'IART', 'IPRD', 'ICRD'];
    const keep: Array<Uint8Array> = [];
    let pos: number = start;
    while (pos + 8 <= end) {
      const size: number = TagWriter.le32(data, pos + 4);
      const contentEnd: number = pos + 8 + size;
      if (contentEnd > end) {
        break;
      }
      const paddedEnd: number = Math.min(contentEnd + (size & 1), end);
      if (drop.indexOf(TagWriter.typeAt(data, pos)) < 0) {
        keep.push(data.subarray(pos, paddedEnd));
      }
      pos = paddedEnd;
    }
    return keep;
  }

  // ============================ 字节工具 ============================

  private static concatBytes(chunks: Array<Uint8Array>): Uint8Array {
    let total: number = 0;
    for (const c of chunks) {
      total += c.length;
    }
    const out: Uint8Array = new Uint8Array(total);
    let off: number = 0;
    for (const c of chunks) {
      out.set(c, off);
      off += c.length;
    }
    return out;
  }

  /** 4 字节大端无符号整数。 */
  private static u32(value: number): Uint8Array {
    return new Uint8Array([(value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF]);
  }

  private static le32(b: Uint8Array, off: number): number {
    if (off + 4 > b.length) {
      return 0;
    }
    return ((b[off] | (b[off + 1] << 8) | (b[off + 2] << 16) | (b[off + 3] << 24)) >>> 0);
  }

  /** 4 字节大端无符号整数。 */
  private static be32(b: Uint8Array, off: number): number {
    if (off + 4 > b.length) {
      return 0;
    }
    return ((b[off] << 24) | (b[off + 1] << 16) | (b[off + 2] << 8) | b[off + 3]) >>> 0;
  }

  /** 8 字节大端无符号整数（用 double 承载，2^53 内精确）。 */
  private static be64(b: Uint8Array, off: number): number {
    const hi: number = TagWriter.be32(b, off);
    const lo: number = TagWriter.be32(b, off + 4);
    return hi * 4294967296 + lo;
  }

  /** 写入 8 字节大端无符号整数。 */
  private static writeBe64(b: Uint8Array, off: number, value: number): void {
    const hi: number = Math.floor(value / 4294967296);
    const lo: number = value - hi * 4294967296;
    b[off] = (hi >>> 24) & 0xFF;
    b[off + 1] = (hi >>> 16) & 0xFF;
    b[off + 2] = (hi >>> 8) & 0xFF;
    b[off + 3] = hi & 0xFF;
    b[off + 4] = (lo >>> 24) & 0xFF;
    b[off + 5] = (lo >>> 16) & 0xFF;
    b[off + 6] = (lo >>> 8) & 0xFF;
    b[off + 7] = lo & 0xFF;
  }

  /** 读取 4 字节 fourcc（ASCII / Latin-1，含 MP4 的 0xA9 '©'）。 */
  private static typeAt(b: Uint8Array, off: number): string {
    return String.fromCharCode(b[off] & 0xFF, b[off + 1] & 0xFF, b[off + 2] & 0xFF, b[off + 3] & 0xFF);
  }

  private static syncsafe(a: number, b: number, c: number, d: number): number {
    return ((a & 0x7F) << 21) | ((b & 0x7F) << 14) | ((c & 0x7F) << 7) | (d & 0x7F);
  }

  /** 纯手写 UTF-8 编码（覆盖替代字符 + 代理对），避免依赖 TextEncoder 的 API 差异。 */
  private static utf8Bytes(s: string): Uint8Array {
    const out: Array<number> = [];
    for (let i: number = 0; i < s.length; i++) {
      let code: number = s.charCodeAt(i);
      if (code >= 0xD800 && code <= 0xDBFF && i + 1 < s.length) {
        const low: number = s.charCodeAt(i + 1);
        if (low >= 0xDC00 && low <= 0xDFFF) {
          code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
          i++;
        }
      }
      if (code < 0x80) {
        out.push(code);
      } else if (code < 0x800) {
        out.push(0xC0 | (code >> 6), 0x80 | (code & 0x3F));
      } else if (code < 0x10000) {
        out.push(0xE0 | (code >> 12), 0x80 | ((code >> 6) & 0x3F), 0x80 | (code & 0x3F));
      } else {
        out.push(0xF0 | (code >> 18), 0x80 | ((code >> 12) & 0x3F), 0x80 | ((code >> 6) & 0x3F), 0x80 | (code & 0x3F));
      }
    }
    return new Uint8Array(out);
  }

  private static decodeUtf8(bytes: Uint8Array): string {
    try {
      const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
      return decoder.decodeToString(bytes, { stream: false });
    } catch (e) {
      let s: string = '';
      for (let i: number = 0; i < bytes.length; i++) {
        s += String.fromCharCode(bytes[i]);
      }
      return s;
    }
  }
}
