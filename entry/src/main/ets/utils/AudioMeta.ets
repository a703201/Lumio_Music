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

import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { taskpool } from '@kit.ArkTS';
import { Logger } from './Logger';
import { NativeUtils } from './NativeModule';

const TAG = 'AudioMetaReader';

/**
 * 从音频文件中读取文本元数据（标题 / 艺术家 / 专辑 / 作者）。
 *
 * 说明：MediaKit 的 AVMetadata 接口并不暴露内嵌歌词字段（lyric 仅存在于
 * AVSession 的元数据中，用于锁屏展示）。因此歌词仍走应用原有的 rawfile
 * LRC 资源流程，本工具只负责标题 / 艺术家 / 专辑 / 作者。
 *
 * 解析策略（双路）：
 * 1) 优先 MediaKit AVMetadataExtractor（覆盖最广、最稳定）；
 * 2) MediaKit 失败或关键字段（标题）缺失时，回退到 C++ NAPI 原生解析
 *    （parseAudioMetadata，支持 FLAC/MP3/MP4 的标题/艺术家/专辑/时长/采样率/声道）。
 */
export interface AudioMeta {
  title?: string;
  artist?: string;
  album?: string;
  author?: string;
  year?: string;
}

/**
 * taskpool 并发任务入口。
 *
 * 关键约束：taskpool 只接受 @Concurrent 装饰、且定义在文件顶层的具名函数。
 * 之前写成 `new taskpool.Task(() => {...})` 的闭包形式，运行时会抛 10200014
 * （Concurrent function is not a valid function），异常被外层 catch 静默吞掉，
 * 结果是 C++ 原生兜底解析在真机上「一次都没真正执行过」。
 *
 * 并发函数不能捕获外部作用域变量，所需入参必须显式传递；返回值也必须是可跨线程
 * 序列化的纯数据对象，故这里只回传三个字符串字段。
 */
@Concurrent
function parseMetaOnWorker(src: string): AudioMeta | undefined {
  const raw: ESObject = NativeUtils.getInstance().parseAudioMetadata(src);
  if (!raw) {
    return undefined;
  }
  const title: string = raw.title as string;
  const artist: string = raw.artist as string;
  const album: string = raw.album as string;
  const rawYear: string = raw.year as string;
  let year: string = '';
  if (rawYear) {
    const m: RegExpMatchArray | null = rawYear.match(/(19|20)\d{2}/);
    if (m) {
      year = m[0];
    }
  }
  const result: AudioMeta = {
    title: title,
    artist: artist,
    album: album,
    year: year
  };
  return result;
}

export class AudioMetaReader {
  static async read(src: string): Promise<AudioMeta | null> {
    if (!src) {
      return null;
    }
    const fromKit: AudioMeta | null = await AudioMetaReader.readViaMediaKit(src);
    if (fromKit && fromKit.title) {
      return fromKit;
    }
    // MediaKit 失败或标题缺失：回退 C++ NAPI 原生解析。
    // 该调用是同步 NAPI，会阻塞调用线程；放到 taskpool 工作线程执行，避免主线程卡顿 / ANR。
    // 任意异常（含 worker 线程 NAPI 不可用）均回退到 MediaKit 结果，保证不降级为失败。
    try {
      const native: AudioMeta | undefined = await taskpool.execute(parseMetaOnWorker, src) as AudioMeta | undefined;
      if (native && native.title) {
        const merged: AudioMeta = {
          title: native.title,
          artist: native.artist ? native.artist : undefined,
          album: native.album ? native.album : undefined,
          year: native.year ? native.year : (fromKit ? fromKit.year : undefined)
        };
        return merged;
      }
    } catch (err) {
      // P2-13：日志脱敏，只打印文件名，避免完整沙箱路径（含用户歌曲名）进 hilog
      Logger.debug(TAG, `native parse failed for ${AudioMetaReader.sanitize(src)}: ${(err as Error).message}`);
    }
    return fromKit;
  }

  // P2-13：日志脱敏——只保留文件名，避免完整沙箱路径（含用户歌曲名）明文进 hilog
  private static sanitize(path: string): string {
    const idx = path.lastIndexOf('/');
    return idx >= 0 ? path.substring(idx + 1) : path;
  }

  /**
   * 从 MediaKit 的 dateTime 字符串（如 "2019"、"2019-03-02"、"2019-03-02T08:00:00Z"）
   * 中提取 4 位年份。无有效年份时返回 undefined。
   */
  private static extractYear(dateTime?: string): string | undefined {
    if (!dateTime) {
      return undefined;
    }
    const m: RegExpMatchArray | null = dateTime.match(/(19|20)\d{2}/);
    return m ? m[0] : undefined;
  }

  private static async readViaMediaKit(src: string): Promise<AudioMeta | null> {
    let extractor: media.AVMetadataExtractor | undefined;
    let file: fileIo.File | undefined;
    try {
      extractor = await media.createAVMetadataExtractor();
      file = fileIo.openSync(src, fileIo.OpenMode.READ_ONLY);
      extractor.fdSrc = { fd: file.fd, offset: 0, length: -1 } as media.AVFileDescriptor;
      const metadata = await extractor.fetchMetadata();
      return {
        title: metadata.title,
        artist: metadata.artist,
        album: metadata.album,
        author: metadata.author,
        year: AudioMetaReader.extractYear(metadata.dateTime)
      };
    } catch (err) {
      // P2-13：日志脱敏，只打印文件名
      Logger.debug(TAG, `read failed for ${AudioMetaReader.sanitize(src)}: ${(err as Error).message}`);
      return null;
    } finally {
      if (extractor) {
        try {
          await extractor.release();
        } catch (_) {
          // ignore
        }
      }
      if (file) {
        try {
          fileIo.closeSync(file);
        } catch (_) {
          // ignore
        }
      }
    }
  }
}
