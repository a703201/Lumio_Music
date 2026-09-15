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

import { Logger } from '../utils/Logger';
import { SongItem } from '../models/music';
import { MusicStore } from '../services/MusicStore';
import { AudioRendererController } from '../utils/AudioRendererController';
import { ThemeManager, ColorTokens } from '../utils/ThemeManager';
import { semanticOf } from '../tokens/LumioColor';
import { CoverImageView } from '../components/CoverImageView';
import { QualityBadge } from '../components/QualityBadge';
import { SongRow } from '../components/SongRow';
import { SongDataSource } from '../datasource/SongDataSource';
import { DuplicateDetector, DuplicateGroup } from '../utils/DuplicateDetector';
import { LumioTheme, SpringKind } from '../tokens/LumioTheme';
import { TYPE_SM, SPACE_SM } from '../tokens/LumioScale';

interface YearStat {
  year: string;
  plays: number;
}

/**
 * Settings sheet 内嵌子页的统一样式头部：左侧返回箭头 + 大标题 + 右侧占位。
 * onBack 由外层传入（sheet 内关闭 subPage / 主导航栈 pop）。
 */
@Component
export struct SubPageHeader {
  @StorageProp('topHeight') topHeight: number = 0;
  @StorageProp('isDark') isDark: boolean = false;
  title: ResourceStr = '';
  onBack: () => void = () => {};
  rightSlot?: () => void;

  private getThemeColors(): ColorTokens {
    return this.isDark ? ThemeManager.darkColors : ThemeManager.lightColors;
  }

  build() {
    Row() {
      Image($r('app.media.ic_public_arrow_left'))
        .width(24)
        .height(24)
        .fillColor(this.getThemeColors().primaryText)
        .onClick(() => this.onBack()).clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
      Text(this.title)
        .fontSize(TYPE_SM.title2.size)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.getThemeColors().primaryText)
        .margin({ left: SPACE_SM.cozy })
        .layoutWeight(1)
      // 右侧占位（由调用方决定是否提供）
      Row() {
      }
      .width(24)
      .height(24)
    }
    .width('100%')
    .padding({ left: SPACE_SM.base, right: SPACE_SM.base, top: this.topHeight + 12, bottom: SPACE_SM.cozy })
  }
}

/**
 * 本地歌曲管理：列出库内全部歌曲，长按移除。从原 ManageSongs.ets 抽出，与 sheet 内
 * 嵌场景共享同一份渲染逻辑；onBack 由调用方控制（sheet 内切换 subPage 或主栈 pop）。
 */
@Component
export struct ManageSongsBody {
  store: MusicStore = MusicStore.getInstance();
  onBack: () => void = () => {};
  /** sheet 内嵌时由 Settings 传 false 跳过自身表头，避免与 Settings 标题栏重复。 */
  showHeader: boolean = true;
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('coverRefreshToken') @Watch('onCoverRefreshed') coverRefreshToken: number = 0;

  private getThemeColors(): ColorTokens {
    return this.isDark ? ThemeManager.darkColors : ThemeManager.lightColors;
  }

  @State @Watch('onSongsChanged') songs: SongItem[] = [];
  @State itemScales: number[] = [];
  private songsDataSource: SongDataSource = new SongDataSource([]);
  @State emptyIconScale: number = 1.0;
  @State pendingDelete: SongItem | null = null;

  aboutToAppear(): void {
    this.reload();
  }

  private reload(): void {
    this.songs = [...this.store.songs];
    this.itemScales = this.songs.map(() => 1.0);
  }

  onCoverRefreshed(): void {
    this.reload();
  }

  onSongsChanged(): void {
    this.songsDataSource.setData(this.songs);
  }

  private toast(message: ResourceStr): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (e) {
      Logger.error('toast failed');
    }
  }

  private confirmDelete(song: SongItem): void {
    this.pendingDelete = song;
    this.showDeleteDialog();
  }

  private showDeleteDialog(): void {
    if (!this.pendingDelete) {
      return;
    }
    const title: string = this.pendingDelete.title;
    this.getUIContext().showAlertDialog({
      title: $r('app.string.remove_song'),
      message: `确定从本地库中移除「${title}」？`,
      primaryButton: { value: $r('app.string.cancel'), action: () => { this.pendingDelete = null; } },
      secondaryButton: { value: $r('app.string.remove'), action: () => { this.doDelete(); } }
    });
  }

  private doDelete(): void {
    if (this.pendingDelete) {
      const id: number = this.pendingDelete.id;
      this.store.removeSong(id);
      AudioRendererController.getInstance().reconcileWithLibrary(this.store.songs);
      this.pendingDelete = null;
      this.reload();
      this.toast($r('app.string.song_removed'));
    }
  }

  

  build() {
    Column() {
      if (this.showHeader) {
        SubPageHeader({ title: $r('app.string.local_songs_mgmt'), onBack: () => this.onBack() })
      }

      Text(`${this.songs.length} 首`)
        .fontSize(TYPE_SM.footnote.size)
        .fontColor(this.getThemeColors().accent)
        .backgroundColor(semanticOf(this.isDark).fillAccentSoft)
        .borderRadius(12)
        .padding({ left: SPACE_SM.cozy, right: SPACE_SM.cozy, top: SPACE_SM.tight, bottom: SPACE_SM.tight })
        .margin({ left: SPACE_SM.base, bottom: SPACE_SM.cozy })
        .visibility(this.songs.length > 0 ? Visibility.Visible : Visibility.Hidden)

      if (this.songs.length === 0) {
        Column() {
          Image($r('app.media.ic_public_albums'))
            .width(72)
            .height(72)
            .fillColor(this.getThemeColors().secondaryText)
            .margin({ bottom: SPACE_SM.base })
            .scale({ x: this.emptyIconScale, y: this.emptyIconScale })
            .animation({ duration: LumioTheme.duration(700), curve: LumioTheme.curve(SpringKind.Crisp) })
          Text($r('app.string.no_local_songs'))
            .fontSize(TYPE_SM.headline.size)
            .fontColor(this.getThemeColors().secondaryText)
            .fontWeight(FontWeight.Medium)
          Text($r('app.string.local_songs_hint'))
            .fontSize(TYPE_SM.footnote.size)
            .fontColor(this.getThemeColors().secondaryText)
            .margin({ top: SPACE_SM.compact })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          LazyForEach(this.songsDataSource, (song: SongItem, index: number) => {
            ListItem() {
              SongRow({
              song: song,
              playing: false,
              showQuality: true,
              coverSize: 48,
              titleFontSize: 15,
              rowHeight: 64,
              leftPadding: 16,
              showRemove: true,
              animateEntry: false,
              menuItems: [],
              onPlay: () => {},
              onRemove: () => {
                this.confirmDelete(song);
              }
            })
            }
          }, (song: SongItem): string => song.id.toString())
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.getThemeColors().bg)
  }
}

/**
 * 重复歌曲清理体：从 DuplicateSongs.ets 抽出供 sheet 复用。
 */
@Component
export struct DuplicateSongsBody {
  store: MusicStore = MusicStore.getInstance();
  onBack: () => void = () => {};
  /** sheet 内嵌时由 Settings 传 false 跳过自身表头，避免与 Settings 标题栏重复。 */
  showHeader: boolean = true;
  @StorageProp('topHeight') topHeight: number = 0;
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('coverRefreshToken') coverRefreshToken: number = 0;

  private getThemeColors(): ColorTokens {
    return this.isDark ? ThemeManager.darkColors : ThemeManager.lightColors;
  }

  @State groups: DuplicateGroup[] = [];
  @State backScale: number = 1.0;
  @State itemScales: number[] = [];

  aboutToAppear(): void {
    this.refresh();
  }

  private refresh(): void {
    this.groups = DuplicateDetector.findDuplicates(this.store.songs);
    this.itemScales = this.groups.map((_: DuplicateGroup, i: number) => this.itemScales[i] ?? 1.0);
  }

  private duplicateCount(): number {
    let n: number = 0;
    this.groups.forEach((g: DuplicateGroup) => {
      n += Math.max(0, g.songs.length - 1);
    });
    return n;
  }

  private removeOne(song: SongItem): void {
    this.store.removeSong(song.id);
    this.refresh();
  }

  private removeAllDuplicates(): void {
    this.groups.forEach((g: DuplicateGroup) => {
      for (let i = 1; i < g.songs.length; i++) {
        this.store.removeSong(g.songs[i].id);
      }
    });
    this.refresh();
    try {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.dup_cleaned') });
    } catch (e) {
      Logger.error('DuplicateSongs', 'toast failed');
    }
  }

  @Builder
  buildGroupCard(group: DuplicateGroup, index: number) {
    Column() {
      Row() {
        Text(group.key)
          .fontSize(TYPE_SM.headline.size)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getThemeColors().primaryText)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${group.songs.length} 个文件`)
          .fontSize(TYPE_SM.caption1.size)
          .fontColor(this.getThemeColors().accent)
          .backgroundColor(semanticOf(this.isDark).fillAccentSoft)
          .borderRadius(12)
          .padding({ left: SPACE_SM.compact, right: SPACE_SM.compact, top: SPACE_SM.tight, bottom: SPACE_SM.tight })
      }
      .width('100%')
      .padding({ left: SPACE_SM.base, right: SPACE_SM.base, top: SPACE_SM.cozy, bottom: SPACE_SM.compact })

      ForEach(group.songs, (song: SongItem, i: number) => {
        Row() {
          Stack() {
            CoverImageView({ src: song.src, coverSize: 40, coverRadius: 8 })
          }
          Column() {
            Text(song.title)
              .fontSize(TYPE_SM.subhead.size)
              .fontColor(this.getThemeColors().primaryText)
              .fontWeight(FontWeight.Medium)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(song.singer)
              .fontSize(TYPE_SM.caption1.size)
              .fontColor(this.getThemeColors().secondaryText)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .padding({ left: SPACE_SM.cozy })
          if (i === 0) {
            Text($r('app.string.keep'))
              .fontSize(TYPE_SM.caption1.size)
              .fontColor(this.getThemeColors().secondaryText)
              .backgroundColor(this.getThemeColors().secondaryBg)
              .borderRadius(12)
              .padding({ left: SPACE_SM.cozy, right: SPACE_SM.cozy, top: SPACE_SM.tight, bottom: SPACE_SM.tight })
          } else {
            Text($r('app.string.remove'))
              .fontSize(TYPE_SM.footnote.size)
              .fontColor(this.getThemeColors().accent)
              .fontWeight(FontWeight.Medium)
              .onClick(() => {
                this.removeOne(song);
              }).clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
          }
        }
        .width('100%')
        .padding({ left: SPACE_SM.base, right: SPACE_SM.base, top: SPACE_SM.compact, bottom: SPACE_SM.compact })
      }, (song: SongItem) => 'dup_' + song.id.toString())
    }
    .width('100%')
    .margin({ left: SPACE_SM.compact, right: SPACE_SM.compact, bottom: SPACE_SM.cozy })
    .backgroundColor(this.getThemeColors().cardBg)
    .borderRadius(16)
  }

  build() {
    Column() {
      if (this.showHeader) {
        Row() {
          Image($r('app.media.ic_public_arrow_left'))
            .width(24)
            .height(24)
            .fillColor(this.getThemeColors().primaryText)
            .onClick(() => this.onBack()).clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
          Text($r('app.string.duplicate_songs'))
            .fontSize(TYPE_SM.title2.size)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getThemeColors().primaryText)
            .margin({ left: SPACE_SM.cozy })
            .layoutWeight(1)
          if (this.duplicateCount() > 0) {
            Text($r('app.string.clean_all'))
              .fontSize(TYPE_SM.subhead.size)
              .fontColor(this.getThemeColors().accent)
              .fontWeight(FontWeight.Medium)
              .onClick(() => {
                this.removeAllDuplicates();
              }).clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
          }
        }
        .width('100%')
        .padding({ left: SPACE_SM.base, right: SPACE_SM.base, top: this.topHeight + 12, bottom: SPACE_SM.cozy })
      }

      if (this.groups.length === 0) {
        Column() {
          Image($r('app.media.ic_public_view_list'))
            .width(64)
            .height(64)
            .fillColor(this.getThemeColors().secondaryText)
            .margin({ bottom: SPACE_SM.base })
          Text($r('app.string.no_dupes'))
            .fontSize(TYPE_SM.headline.size)
            .fontColor(this.getThemeColors().secondaryText)
            .fontWeight(FontWeight.Medium)
          Text($r('app.string.dup_explain'))
            .fontSize(TYPE_SM.footnote.size)
            .fontColor(this.getThemeColors().secondaryText)
            .margin({ top: SPACE_SM.compact })
            .width('70%')
            .textAlign(TextAlign.Center)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.groups, (group: DuplicateGroup, index: number) => {
            ListItem() {
              this.buildGroupCard(group, index)
            }
          }, (group: DuplicateGroup) => 'group_' + group.key)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.getThemeColors().bg)
  }
}

/**
 * 我的听歌报告体：从 Wrapped.ets 抽出供 sheet 复用。
 * 行为简化：sheet 内不再 push 玩家（保留点击 toast 提示），主导航栈独立保留完整 Wrapped 体验。
 */
@Component
export struct WrappedBody {
  store: MusicStore = MusicStore.getInstance();
  onBack: () => void = () => {};
  /** sheet 内嵌时由 Settings 传 false 跳过自身表头，避免与 Settings 标题栏重复。 */
  showHeader: boolean = true;
  @StorageProp('isDark') isDark: boolean = false;

  private getThemeColors(): ColorTokens {
    return this.isDark ? ThemeManager.darkColors : ThemeManager.lightColors;
  }

  @State totalPlays: number = 0;
  @State totalMs: number = 0;
  @State topSongs: SongItem[] = [];
  @State yearStats: YearStat[] = [];
  @State hasData: boolean = false;

  aboutToAppear(): void {
    const summary = this.store.getStatsSummary();
    this.totalPlays = summary.totalPlays;
    this.totalMs = summary.totalMs;
    this.topSongs = summary.topSongs;
    this.yearStats = this.computeYearStats();
    this.hasData = this.totalPlays > 0 && this.store.songs.length > 0;
  }

  private computeYearStats(): YearStat[] {
    const map: Map<string, number> = new Map<string, number>();
    this.store.playCounts.forEach((plays: number, songId: number) => {
      const song: SongItem | undefined = this.store.songs.find((s: SongItem) => s.id === songId);
      const year: string = (song && song.year) ? song.year : (this.getUIContext().getHostContext()?.resourceManager.getStringSync($r('app.string.unknown_year').id) ?? '');
      map.set(year, (map.get(year) ?? 0) + plays);
    });
    const arr: YearStat[] = [];
    map.forEach((plays: number, year: string) => {
      arr.push({ year, plays });
    });
    arr.sort((a: YearStat, b: YearStat) => b.plays - a.plays);
    return arr.slice(0, 6);
  }

  private formatDuration(ms: number): ResourceStr {
    const minutes: number = Math.floor(ms / 60000);
    const hours: number = Math.floor(minutes / 60);
    const days: number = Math.floor(hours / 24);
    if (days > 0) {
      const remHours: number = hours - days * 24;
      return `${days} 天 ${remHours} 小时`;
    }
    if (hours > 0) {
      const remMin: number = minutes - hours * 60;
      return `${hours} 小时 ${remMin} 分钟`;
    }
    if (minutes > 0) {
      return `${minutes} 分钟`;
    }
    return $r('app.string.under_1_min');
  }

  private maxYearPlays(): number {
    let m: number = 1;
    this.yearStats.forEach((y: YearStat) => {
      if (y.plays > m) {
        m = y.plays;
      }
    });
    return m;
  }

  @Builder
  buildHero() {
    Column() {
      Text($r('app.string.report_title'))
        .fontSize(TYPE_SM.footnote.size)
        .fontColor(this.getThemeColors().accent)
        .fontWeight(FontWeight.Medium)
        .letterSpacing(1)
        .margin({ bottom: SPACE_SM.cozy })
      Text(`${this.totalPlays}`)
        .fontSize(56)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.getThemeColors().primaryText)
      Text($r('app.string.plays_count'))
        .fontSize(TYPE_SM.body.size)
        .fontColor(this.getThemeColors().secondaryText)
        .margin({ top: SPACE_SM.hair, bottom: SPACE_SM.roomy })
      Row() {
        Column() {
          Text($r('app.string.total_listen'))
            .fontSize(TYPE_SM.caption1.size)
            .fontColor(this.getThemeColors().secondaryText)
            .margin({ bottom: SPACE_SM.tight })
          Text(this.formatDuration(this.totalMs))
            .fontSize(TYPE_SM.title3.size)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getThemeColors().primaryText)
        }
        .layoutWeight(1)
        Column() {
          Text($r('app.string.total_songs'))
            .fontSize(TYPE_SM.caption1.size)
            .fontColor(this.getThemeColors().secondaryText)
            .margin({ bottom: SPACE_SM.tight })
          Text(`${this.store.songs.length}`)
            .fontSize(TYPE_SM.title3.size)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getThemeColors().primaryText)
        }
        .layoutWeight(1)
      }
      .width('100%')
    }
    .width('100%')
    .padding(24)
    .backgroundColor(this.getThemeColors().cardBg)
    .borderRadius(24)
    .margin({ left: SPACE_SM.compact, right: SPACE_SM.compact, bottom: SPACE_SM.base })
  }

  @Builder
  buildTopSongs() {
    Column() {
      Text($r('app.string.most_played'))
        .fontSize(TYPE_SM.title3.size)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.getThemeColors().primaryText)
        .width('100%')
        .padding({ left: SPACE_SM.cozy, bottom: SPACE_SM.cozy })
      ForEach(this.topSongs, (song: SongItem, index: number) => {
        Row() {
          Text(`${index + 1}`)
            .fontSize(TYPE_SM.body.size)
            .fontWeight(FontWeight.Bold)
            .fontColor(index < 3 ? this.getThemeColors().accent : this.getThemeColors().secondaryText)
            .width(28)
            .textAlign(TextAlign.Center)
          Stack() {
            CoverImageView({ src: song.src, coverSize: 44, coverRadius: 8 })
          }
          Column() {
            Text(song.title)
              .fontSize(TYPE_SM.body.size)
              .fontColor(this.getThemeColors().primaryText)
              .fontWeight(FontWeight.Medium)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(song.singer)
              .fontSize(TYPE_SM.caption1.size)
              .fontColor(this.getThemeColors().secondaryText)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .padding({ left: SPACE_SM.cozy })
          Text(`${this.store.getPlayCount(song.id)} 次`)
            .fontSize(TYPE_SM.footnote.size)
            .fontColor(this.getThemeColors().secondaryText)
        }
        .width('100%')
        .height(58)
        .padding({ left: SPACE_SM.cozy, right: SPACE_SM.base })
        .backgroundColor(this.getThemeColors().cardBg)
        .borderRadius(12)
        .margin({ left: SPACE_SM.compact, right: SPACE_SM.compact, bottom: SPACE_SM.compact })
      }, (song: SongItem) => 'top_' + song.id.toString())
    }
    .margin({ bottom: SPACE_SM.base })
  }

  @Builder
  buildYearChart() {
    Column() {
      Text($r('app.string.by_release_year'))
        .fontSize(TYPE_SM.title3.size)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.getThemeColors().primaryText)
        .width('100%')
        .padding({ left: SPACE_SM.cozy, bottom: SPACE_SM.cozy })
      ForEach(this.yearStats, (y: YearStat) => {
        Row() {
          Text(y.year)
            .fontSize(TYPE_SM.footnote.size)
            .fontColor(this.getThemeColors().secondaryText)
            .width(64)
          Stack() {
            Row()
              .width(`${Math.max(8, (y.plays / this.maxYearPlays()) * 100)}%`)
              .height(14)
              .backgroundColor(this.getThemeColors().accent)
              .borderRadius(7)
          }
          .width('100%')
          .height(14)
          .backgroundColor(this.getThemeColors().secondaryBg)
          .borderRadius(7)
          .margin({ left: SPACE_SM.compact })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ bottom: SPACE_SM.cozy })
      }, (y: YearStat) => 'year_' + y.year)
    }
    .width('100%')
    .padding({ top: SPACE_SM.base, left: SPACE_SM.base, right: SPACE_SM.base, bottom: SPACE_SM.base })
    .backgroundColor(this.getThemeColors().cardBg)
    .borderRadius(24)
    .margin({ left: SPACE_SM.compact, right: SPACE_SM.compact, bottom: SPACE_SM.base })
  }

  build() {
    Column() {
      if (this.showHeader) {
        SubPageHeader({ title: $r('app.string.listen_report'), onBack: () => this.onBack() })
      }

      if (!this.hasData) {
        Column() {
          Image($r('app.media.ic_public_music_public_filled'))
            .width(64)
            .height(64)
            .fillColor(this.getThemeColors().secondaryText)
            .margin({ bottom: SPACE_SM.base })
          Text($r('app.string.not_enough_data'))
            .fontSize(TYPE_SM.headline.size)
            .fontColor(this.getThemeColors().secondaryText)
            .fontWeight(FontWeight.Medium)
          Text($r('app.string.more_data_hint'))
            .fontSize(TYPE_SM.footnote.size)
            .fontColor(this.getThemeColors().secondaryText)
            .margin({ top: SPACE_SM.compact })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column() {
            this.buildHero()
            this.buildTopSongs()
            if (this.yearStats.length > 0) {
              this.buildYearChart()
            }
            Text($r('app.string.local_only_stats'))
              .fontSize(TYPE_SM.caption1.size)
              .fontColor(this.getThemeColors().secondaryText)
              .margin({ top: SPACE_SM.compact, bottom: SPACE_SM.loose })
          }
          .width('100%')
          .padding({ bottom: SPACE_SM.loose })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.getThemeColors().bg)
  }
}

/**
 * 隐私政策体：从 PrivacyPolicy.ets 抽出供 sheet 复用。
 * 仅做静态排版——sheet 内的 stack-overflow 安全（不再注册 pathStack）。
 */
@Component
export struct PrivacyPolicyBody {
  onBack: () => void = () => {};
  /** sheet 内嵌时由 Settings/About 传 false 跳过自身表头，避免与外层标题栏重复。 */
  showHeader: boolean = true;
  @StorageProp('topHeight') topHeight: number = 0;
  @StorageProp('isDark') isDark: boolean = false;

  private getThemeColors(): ColorTokens {
    return this.isDark ? ThemeManager.darkColors : ThemeManager.lightColors;
  }

  @Builder
  buildSection(title: ResourceStr, body: ResourceStr) {
    Column() {
      Text(title)
        .fontSize(TYPE_SM.title3.size)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.getThemeColors().primaryText)
        .width('100%')
        .margin({ bottom: SPACE_SM.compact })
      Text(body)
        .fontSize(TYPE_SM.subhead.size)
        .fontColor(this.getThemeColors().secondaryText)
        .width('100%')
        .lineHeight(22)
    }
    .width('100%')
    .margin({ bottom: SPACE_SM.loose })
  }

  build() {
    Column() {
      if (this.showHeader) {
        SubPageHeader({ title: $r('app.string.privacy_policy'), onBack: () => this.onBack() })
      }

      Scroll() {
        Column() {
          this.buildSection(
            $r('app.string.overview'),
            $r('app.string.privacy_overview')
          )
          this.buildSection(
            $r('app.string.info_collected'),
            $r('app.string.info_collected_desc')
          )
          this.buildSection(
            $r('app.string.storage_location'),
            $r('app.string.storage_location_desc')
          )
          this.buildSection(
            $r('app.string.permissions_title'),
            (this.getUIContext().getHostContext()?.resourceManager.getStringSync($r('app.string.perm_intro').id) ?? '') +
            (this.getUIContext().getHostContext()?.resourceManager.getStringSync($r('app.string.perm_bg').id) ?? '') +
            (this.getUIContext().getHostContext()?.resourceManager.getStringSync($r('app.string.perm_internet').id) ?? '')
          )
          this.buildSection(
            $r('app.string.cast_title'),
            $r('app.string.cast_desc')
          )
          this.buildSection(
            $r('app.string.third_party_title'),
            $r('app.string.third_party_desc')
          )
          this.buildSection(
            $r('app.string.logs_title'),
            $r('app.string.logs_desc')
          )
          this.buildSection(
            $r('app.string.commitment_title'),
            $r('app.string.commitment_desc')
          )
          this.buildSection(
            $r('app.string.rights_title'),
            (this.getUIContext().getHostContext()?.resourceManager.getStringSync($r('app.string.rights_desc').id) ?? '') +
            (this.getUIContext().getHostContext()?.resourceManager.getStringSync($r('app.string.contact_hint').id) ?? '') +
            (this.getUIContext().getHostContext()?.resourceManager.getStringSync($r('app.string.contact_entity').id) ?? '') +
            (this.getUIContext().getHostContext()?.resourceManager.getStringSync($r('app.string.contact_email').id) ?? '')
          )
        }
        .width('100%')
        .padding({ left: SPACE_SM.base, right: SPACE_SM.base, bottom: SPACE_SM.block })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.getThemeColors().bg)
  }
}
