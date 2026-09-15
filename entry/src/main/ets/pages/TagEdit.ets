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

import { SongItem } from '../models/music';
import { MusicStore } from '../services/MusicStore';
import { Logger } from '../utils/Logger';
import { ThemeManager, ColorTokens } from '../utils/ThemeManager';
import { TagWriter, TagFields } from '../utils/TagWriter';
// NavPathStack 为全局环境声明，无需 import
import { semanticOf } from '../tokens/LumioColor';
import { TYPE_SM, SPACE_SM } from '../tokens/LumioScale';
import { LumioTheme, SpringKind } from '../tokens/LumioTheme';

const TAG: string = 'TagEdit';

@Builder
export function TagEditBuilder() {
  TagEdit()
}

/**
 * 标签编辑页（NavDestination）。
 * 入参：路由参数 song.id（number）。页面按 id 从 MusicStore 取歌，预填 标题/艺术家/专辑/年份，
 * 保存时调用 TagWriter 写回音频文件，并同步更新内存 SongItem 与持久化。
 */
@Component
struct TagEdit {
  pathStack: NavPathStack = new NavPathStack();
  store: MusicStore = MusicStore.getInstance();
  @StorageProp('topHeight') topHeight: number = 0;
  @StorageProp('bottomHeight') bottomHeight: number = 0;
  @StorageProp('isDark') isDark: boolean = false;

  @State songId: number = 0;
  @State title: string = '';
  @State artist: string = '';
  @State album: string = '';
  @State year: string = '';
  @State saving: boolean = false;
  // 该文件是否属于「可能可编辑」的格式（flac/mp3/m4a/mp4/wav…）；已知不支持格式置 false。
  @State editable: boolean = true;

  private getThemeColors(): ColorTokens {
    return this.isDark ? ThemeManager.darkColors : ThemeManager.lightColors;
  }

  private toast(resource: Resource): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: resource });
    } catch (e) {
      Logger.error(TAG, 'toast failed');
    }
  }

  private toastText(text: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: text });
    } catch (e) {
      Logger.error(TAG, 'toast failed');
    }
  }

  private load(): void {
    const song: SongItem | undefined = this.store.songs.find((s: SongItem) => s.id === this.songId);
    if (song) {
      this.title = song.title;
      this.artist = song.singer;
      this.album = song.album;
      this.year = song.year;
      this.editable = TagWriter.isEditableFormat(song.src);
    }
  }

  private async onSave(): Promise<void> {
    if (this.saving) {
      return;
    }
    const song: SongItem | undefined = this.store.songs.find((s: SongItem) => s.id === this.songId);
    if (!song) {
      this.toastText(this.getUIContext().getHostContext()?.resourceManager.getStringSync($r('app.string.song_not_exist').id) ?? '');
      return;
    }
    if (!this.editable) {
      this.toast($r('app.string.tag_unsupported'));
      return;
    }
    this.saving = true;
    const fields: TagFields = {
      title: this.title,
      artist: this.artist,
      album: this.album,
      year: this.year
    };
    const code: number = await TagWriter.writeTags(song.src, fields);
    this.saving = false;
    if (code === 0) {
      song.title = this.title;
      song.singer = this.artist;
      song.album = this.album;
      song.year = this.year;
      this.store.persistSongs();
      // 联动刷新全局 songList，使列表/详情页同步新标签
      AppStorage.setOrCreate('songList', [...this.store.songs]);
      this.toast($r('app.string.tag_saved'));
      this.pathStack.pop();
    } else if (code === -5) {
      this.toast($r('app.string.tag_container_unsupported'));
    } else if (code === -1) {
      this.toast($r('app.string.tag_unsupported'));
    } else if (code === -4) {
      this.toast($r('app.string.tag_backup_failed'));
    } else {
      this.toast($r('app.string.tag_write_failed'));
    }
  }

  @Builder
  private formRow(label: string, value: string, onChange: (v: string) => void) {
    Column() {
      Text(label)
        .fontSize(TYPE_SM.caption1.size)
        .fontColor(this.getThemeColors().secondaryText)
        .alignSelf(ItemAlign.Start)
        .margin({ bottom: SPACE_SM.hair })
      TextInput({ text: value, placeholder: label })
        .width('100%')
        .height(44)
        .backgroundColor(this.getThemeColors().cardBg)
        .borderRadius(12)
        .fontSize(TYPE_SM.body.size)
        .fontColor(this.getThemeColors().primaryText)
        .onChange((v: string) => {
          onChange(v);
        })
    }
    .width('100%')
    .margin({ bottom: SPACE_SM.cozy })
  }

  build() {
    NavDestination() {
      Column() {
        Row() {
          Image($r('app.media.ic_public_arrow_left'))
            .width(24)
            .height(24)
            .fillColor(this.getThemeColors().primaryText)
            .onClick(() => {
              this.pathStack.pop();
            })

          Text($r('app.string.edit_tags'))
            .fontSize(TYPE_SM.title2.size)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getThemeColors().primaryText)
            .margin({ left: SPACE_SM.cozy })
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: SPACE_SM.base, right: SPACE_SM.base, top: this.topHeight + 12, bottom: SPACE_SM.cozy })

        Scroll() {
          Column() {
            this.formRow(this.getUIContext().getHostContext()?.resourceManager.getStringSync($r('app.string.title').id) ?? '', this.title, (v: string) => {
              this.title = v;
            })
            this.formRow(this.getUIContext().getHostContext()?.resourceManager.getStringSync($r('app.string.artist').id) ?? '', this.artist, (v: string) => {
              this.artist = v;
            })
            this.formRow(this.getUIContext().getHostContext()?.resourceManager.getStringSync($r('app.string.album').id) ?? '', this.album, (v: string) => {
              this.album = v;
            })
            this.formRow(this.getUIContext().getHostContext()?.resourceManager.getStringSync($r('app.string.year_label').id) ?? '', this.year, (v: string) => {
              this.year = v;
            })
          }
          .width('100%')
          .padding({ left: SPACE_SM.base, right: SPACE_SM.base, top: SPACE_SM.cozy })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)

        if (!this.editable) {
          Text($r('app.string.tag_unsupported'))
            .fontSize(TYPE_SM.caption1.size)
            .fontColor(this.getThemeColors().secondaryText)
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ left: SPACE_SM.base, right: SPACE_SM.base, bottom: SPACE_SM.cozy })
        }

        Button($r('app.string.tag_save'))
          .width('100%')
          .height(48)
          .borderRadius(24)
          .fontSize(TYPE_SM.subhead.size)
          .fontWeight(FontWeight.Bold)
          .fontColor(semanticOf(this.isDark).onAccent)
          .backgroundColor(this.getThemeColors().accent)
          .margin({ left: SPACE_SM.base, right: SPACE_SM.base, bottom: this.bottomHeight + SPACE_SM.base })
          .enabled(!this.saving && this.editable)
          .onClick(() => {
            this.onSave();
          })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.getThemeColors().bg)
    }
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const param: Object = context.pathInfo.param as Object;
      if (typeof param === 'number') {
        this.songId = param as number;
      } else if (typeof param === 'string') {
        const n: number = parseInt(param as string, 10);
        this.songId = isNaN(n) ? 0 : n;
      } else {
        Logger.warn(TAG, 'TagEdit: invalid route param, expected song id');
      }
      this.load();
    })
    .hideTitleBar(true)
  }
}
