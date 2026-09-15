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
 * 歌曲信息详情半模态面板（Medium 高度）。
 * 显示文件名、歌手、作曲家、合集、年代、添加时间等元数据。
 * 入参只用 songId（@Prop），歌曲实体在内部从 MusicStore 实时取出，避免传递可能为 undefined 的对象。
 */

import { SongItem } from '../models/music';
import { ThemeManager, ColorTokens } from '../utils/ThemeManager';
import { MusicStore } from '../services/MusicStore';
import { fileIo as fs } from '@kit.CoreFileKit';
// 3.0.0 起最低平台 API 26，uiMaterial 模块全平台可用，静态导入。
import uiMaterial from '@ohos.arkui.uiMaterial';
import { acquireSheetMaterial } from '../common/utils/SheetMaterial';
import { TYPE_SM, SPACE_SM } from '../tokens/LumioScale';
import { GroupedSheetContainer, GroupedSheetHairline } from '../common/components/GroupedSheet';
import { Logger } from '../utils/Logger';
import { ShareUtil } from '../utils/ShareUtil';
import { EmbeddedLyricReader } from '../utils/EmbeddedLyricReader';

function getFileName(src: string): string {
  try {
    const decoded = decodeURIComponent(src);
    const idx = decoded.lastIndexOf('/');
    return idx >= 0 ? decoded.substring(idx + 1) : decoded;
  } catch (e) {
    const idx = src.lastIndexOf('/');
    return idx >= 0 ? src.substring(idx + 1) : src;
  }
}

function formatDate(timestamp: number): ResourceStr {
  if (timestamp <= 0) {
    return $r('app.string.unknown');
  }
  const d = new Date(timestamp);
  const y = d.getFullYear();
  const m = d.getMonth() + 1;
  const day = d.getDate();
  const h = d.getHours().toString().padStart(2, '0');
  const min = d.getMinutes().toString().padStart(2, '0');
  return `${y}-${m}-${day} ${h}:${min}`;
}

function getFileModifiedTime(src: string): ResourceStr {
  try {
    const stat = fs.statSync(src);
    // fs.Stat.mtime 为 number 时间戳（秒或毫秒，按官方定义通常为毫秒），此处做兜底兼容
    const t: number = stat.mtime;
    const ts: number = t < 1e12 ? t * 1000 : t;
    return formatDate(ts);
  } catch (e) {
    return $r('app.string.unknown');
  }
}

@Component
export struct SongDetailSheet {
  @StorageProp('isDark') isDark: boolean = false;
  @Prop songId: number = 0;
  @Prop pathStack: NavPathStack = new NavPathStack();
  store: MusicStore = MusicStore.getInstance();
  // 系统材质实例（API 26 经动态 import 注入；API 24 恒为 undefined，走背景色兜底）
  @State material: uiMaterial.Material | undefined = undefined;

  private getThemeColors(): ColorTokens {
    return this.isDark ? ThemeManager.darkColors : ThemeManager.lightColors;
  }

  private getSong(): SongItem | undefined {
    if (this.songId <= 0) {
      return undefined;
    }
    return this.store.songs.find((s: SongItem) => s.id === this.songId);
  }

  private toast(resource: Resource): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: resource });
    } catch (e) {
      Logger.error('SongDetailSheet', 'toast failed');
    }
  }

  /**
   * 手动重新匹配同名 .lrc 外挂歌词：清空缓存后重新探测，并提示结果。
   * EmbeddedLyricReader 默认已自动加载同名歌词，本入口用于用户主动「重扫」或验证。
   */
  private onMatchLyric(song: SongItem): void {
    EmbeddedLyricReader.evict(song.src);
    EmbeddedLyricReader.read(song.src)
      .then((text: string | undefined) => {
        if (text && text.trim().length > 0) {
          this.toast($r('app.string.lyric_matched'));
        } else {
          this.toast($r('app.string.no_lyric_file'));
        }
      })
      .catch(() => {
        this.toast($r('app.string.no_lyric_file'));
      });
  }

  aboutToAppear(): void {
    // 与其余半模态面板统一走 acquireSheetMaterial()（静态构造）；构造失败回落 undefined，
    // 由 build() 走纯色 surfaceOverlay/cardBg 兜底。
    acquireSheetMaterial().then((m: uiMaterial.Material | undefined): void => {
      this.material = m;
    });
  }

  @Builder
  private infoRow(label: ResourceStr, value: ResourceStr) {
    Row() {
      Text(label)
        .fontSize(TYPE_SM.subhead.size)
        .lineHeight(TYPE_SM.subhead.lineHeight)
        .letterSpacing(TYPE_SM.subhead.tracking)
        .fontColor(this.getThemeColors().secondaryText)
        .width(80)

      Text(value)
        .fontSize(TYPE_SM.subhead.size)
        .lineHeight(TYPE_SM.subhead.lineHeight)
        .letterSpacing(TYPE_SM.subhead.tracking)
        .fontColor(this.getThemeColors().primaryText)
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: SPACE_SM.compact, bottom: SPACE_SM.compact })
  }

  @Builder
  private navInfoRow(label: ResourceStr, value: ResourceStr, route: string, param: string) {
    Row() {
      Text(label)
        .fontSize(TYPE_SM.subhead.size)
        .lineHeight(TYPE_SM.subhead.lineHeight)
        .letterSpacing(TYPE_SM.subhead.tracking)
        .fontColor(this.getThemeColors().secondaryText)
        .width(80)
      Text(value)
        .fontSize(TYPE_SM.subhead.size)
        .lineHeight(TYPE_SM.subhead.lineHeight)
        .letterSpacing(TYPE_SM.subhead.tracking)
        .fontColor(this.getThemeColors().primaryText)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: SPACE_SM.compact, bottom: SPACE_SM.compact })
    .onClick(() => {
      if (param && param.length > 0) {
        this.pathStack.pushPathByName(route, param);
      }
    })
  }

  build() {
    if (this.material !== undefined) {
      // 鸿蒙 uiMaterial（沉浸系统材质）：半模态根容器启用系统级毛玻璃，
      // 自动适配深浅色与设备算力档位，与苹果风系统材质一致。
      Column() {
        this.SheetBody()
      }
      .width('100%')
      .padding({ left: SPACE_SM.roomy, right: SPACE_SM.roomy, bottom: SPACE_SM.loose })
      .systemMaterial(this.material)
    } else {
      // 材质构造失败：用主题卡片背景色兜底，保证面板可用。
      Column() {
        this.SheetBody()
      }
      .width('100%')
      .padding({ left: SPACE_SM.roomy, right: SPACE_SM.roomy, bottom: SPACE_SM.loose })
      .backgroundColor(this.getThemeColors().cardBg)
    }
  }

  @Builder
  private SheetBody() {
    Text($r('app.string.song_info'))
      .fontSize(TYPE_SM.title3.size)
      .fontWeight(FontWeight.Bold)
      .lineHeight(TYPE_SM.title3.lineHeight)
      .letterSpacing(TYPE_SM.title3.tracking)
      .fontColor(this.getThemeColors().primaryText)
      .margin({ top: SPACE_SM.roomy, bottom: SPACE_SM.base })

    if (this.getSong()) {
      this.songContent(this.getSong()!)
    } else {
      Text($r('app.string.no_song_selected'))
        .fontSize(TYPE_SM.subhead.size)
        .fontColor(this.getThemeColors().secondaryText)
    }
  }

  @Builder
  private songContent(song: SongItem) {
    GroupedSheetContainer() {
      this.infoRow($r('app.string.file_name'), getFileName(song.src))
      GroupedSheetHairline(this.getThemeColors().separator)
      this.infoRow($r('app.string.title'), song.title.length > 0 ? song.title : $r('app.string.unknown'))
      GroupedSheetHairline(this.getThemeColors().separator)
      this.navInfoRow($r('app.string.singer'), song.singer.length > 0 ? song.singer : $r('app.string.unknown'), 'ArtistDetail', song.singer)
      GroupedSheetHairline(this.getThemeColors().separator)
      this.infoRow($r('app.string.composer'), song.author.length > 0 ? song.author : $r('app.string.unknown'))
      GroupedSheetHairline(this.getThemeColors().separator)
      this.navInfoRow($r('app.string.collection'), song.album.length > 0 ? song.album : $r('app.string.unknown'), 'AlbumDetail', song.album)
      GroupedSheetHairline(this.getThemeColors().separator)
      this.infoRow($r('app.string.era'), song.year.length > 0 ? song.year : $r('app.string.unknown'))
      GroupedSheetHairline(this.getThemeColors().separator)
      this.infoRow($r('app.string.added_time'), getFileModifiedTime(song.src))

      Row({ space: SPACE_SM.base }) {
        Button($r('app.string.edit_tags'))
          .layoutWeight(1)
          .onClick(() => {
            this.pathStack.pushPathByName('TagEdit', song.id);
          })
        Button($r('app.string.share'))
          .layoutWeight(1)
          .onClick(() => {
            ShareUtil.shareSong(song);
          })
      }
      .margin({ top: SPACE_SM.base })

      Button($r('app.string.match_lyric'))
        .width('100%')
        .height(42)
        .borderRadius(21)
        .fontSize(TYPE_SM.body.size)
        .fontColor(this.getThemeColors().secondaryText)
        .backgroundColor(this.getThemeColors().secondaryBg)
        .margin({ top: SPACE_SM.cozy })
        .onClick(() => {
          this.onMatchLyric(song);
        })
    }
  }
}
