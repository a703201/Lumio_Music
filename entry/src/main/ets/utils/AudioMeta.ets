import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { Logger } from './Logger';

const TAG = 'AudioMetaReader';

/**
 * 从音频文件中读取文本元数据（标题 / 艺术家 / 专辑 / 作者）。
 *
 * 说明：MediaKit 的 AVMetadata 接口并不暴露内嵌歌词字段（lyric 仅存在于
 * AVSession 的元数据中，用于锁屏展示）。因此歌词仍走应用原有的 rawfile
 * LRC 资源流程，本工具只负责标题 / 艺术家 / 专辑 / 作者。
 */
export interface AudioMeta {
  title?: string;
  artist?: string;
  album?: string;
  author?: string;
}

export class AudioMetaReader {
  static async read(src: string): Promise<AudioMeta | null> {
    if (!src) {
      return null;
    }
    let extractor: media.AVMetadataExtractor | undefined;
    let file: fileIo.File | undefined;
    try {
      extractor = await media.createAVMetadataExtractor();
      file = fileIo.openSync(src, fileIo.OpenMode.READ_ONLY);
      extractor.fdSrc = { fd: file.fd, offset: 0, length: -1 } as media.AVFileDescriptor;
      const metadata = await extractor.fetchMetadata();
      const result: AudioMeta = {
        title: metadata.title,
        artist: metadata.artist,
        album: metadata.album,
        author: metadata.author
      };
      return result;
    } catch (err) {
      Logger.debug(TAG, `read failed for ${src}: ${(err as Error).message}`);
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
