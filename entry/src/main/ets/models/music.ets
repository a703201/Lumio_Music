import { image } from '@kit.ImageKit';
import { CoverCache } from '../utils/CoverCache';

/**
 * Music information entity class.
 * Single source of truth for SongItem across the project.
 */
export class SongItem {
  id: number = 0;
  title: string = '';
  singer: string = '';
  album: string = '';
  author: string = '';
  mark: Resource | undefined = undefined;
  label: Resource | undefined = undefined;
  src: string = '';
  index: number = 0;
  lyric: string = '';
  isDarkBackground: boolean = false;

  getMark(): Resource | image.PixelMap {
    return CoverCache.getInstance().get(this.src) ?? this.mark ?? $r('app.media.ic_default_cover');
  }

  getLabel(): Resource | image.PixelMap {
    return CoverCache.getInstance().get(this.src) ?? this.label ?? $r('app.media.ic_default_cover');
  }
}

export type RepeatMode = 'single' | 'list' | 'random'

export interface Playlist {
  id: string
  name: string
  songIds: number[]
  coverUri?: string
}
