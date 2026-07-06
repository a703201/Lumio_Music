/**
 * Music information entity class.
 * Single source of truth for SongItem across the project.
 */
export class SongItem {
  id: number = 0;
  title: string = '';
  singer: string = '';
  mark: Resource | undefined = undefined;
  label: Resource | undefined = undefined;
  src: string = '';
  index: number = 0;
  lyric: string = '';
  isDarkBackground: boolean = false;

  getMark(): Resource {
    return this.mark ?? $r('app.media.ic_cd');
  }

  getLabel(): Resource {
    return this.label ?? $r('app.media.ic_cd');
  }
}

export type RepeatMode = 'single' | 'list' | 'none'

export interface Playlist {
  id: string
  name: string
  songIds: number[]
  coverUri?: string
}
