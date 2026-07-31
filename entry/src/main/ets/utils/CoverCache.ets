import { image } from '@kit.ImageKit';
import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { Logger } from './Logger';

const TAG = 'CoverCache';

/**
 * 音频内嵌封面抽取与缓存。
 *
 * 设计原则：
 * - 单例 Map 缓存 src -> PixelMap，避免重复抽取。
 * - 仅对沙箱真实媒体文件尝试抽取；.pcm / rawfile 资源名直接跳过。
 * - 抽取失败静默处理，不影响播放。
 * - 调用方在 preload 完成后自行刷新 songList / coverRefreshToken。
 */
interface CoverSource {
  src: string;
}

export class CoverCache {
  private static instance: CoverCache | null = null;
  private readonly cache = new Map<string, image.PixelMap>();
  private readonly loading = new Set<string>();

  static getInstance(): CoverCache {
    if (!CoverCache.instance) {
      CoverCache.instance = new CoverCache();
    }
    return CoverCache.instance;
  }

  get(src: string): image.PixelMap | undefined {
    return this.cache.get(src);
  }

  async load(src: string): Promise<image.PixelMap | undefined> {
    if (!src || this.cache.has(src) || this.loading.has(src)) {
      return this.cache.get(src);
    }
    if (!this.isExtractable(src)) {
      return undefined;
    }
    this.loading.add(src);
    try {
      const pixelMap = await CoverCache.extractCover(src);
      if (pixelMap) {
        this.cache.set(src, pixelMap);
      }
      return pixelMap;
    } catch (err) {
      Logger.debug(TAG, `load failed for ${src}: ${(err as Error).message}`);
      return undefined;
    } finally {
      this.loading.delete(src);
    }
  }

  /**
   * 批量抽取封面，限制并发数以避免 I/O 拥塞。
   */
  async preload(songs: CoverSource[], concurrency: number = 4): Promise<void> {
    for (let i = 0; i < songs.length; i += concurrency) {
      const batch = songs.slice(i, i + concurrency);
      await Promise.all(batch.map(s => this.load(s.src).then(() => {
      })));
    }
  }

  private isExtractable(src: string): boolean {
    const lower = src.toLowerCase();
    if (lower.endsWith('.pcm')) {
      return false;
    }
    return src.startsWith('/') || src.startsWith('file://') || src.startsWith('internal://');
  }

  private static async extractCover(src: string): Promise<image.PixelMap | undefined> {
    let extractor: media.AVMetadataExtractor | undefined;
    let file: fileIo.File | undefined;
    try {
      extractor = await media.createAVMetadataExtractor();
      file = fileIo.openSync(src, fileIo.OpenMode.READ_ONLY);
      extractor.fdSrc = { fd: file.fd, offset: 0, length: -1 } as media.AVFileDescriptor;
      await extractor.fetchMetadata();
      return await extractor.fetchAlbumCover();
    } catch (err) {
      Logger.debug(TAG, `extractCover failed for ${src}: ${(err as Error).message}`);
      return undefined;
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
