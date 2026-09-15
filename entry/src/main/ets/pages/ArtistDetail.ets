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
import { SongDataSource } from '../datasource/SongDataSource';
import { ThemeManager, ColorTokens } from '../utils/ThemeManager';
import { MusicStore } from '../services/MusicStore';
import { AudioRendererController } from '../utils/AudioRendererController';
import { Logger } from '../utils/Logger';
import { CoverImageView } from '../components/CoverImageView';
import { SongDetailSheet } from '../components/SongDetailSheet';
import { AddToPlaylistSheet } from '../components/AddToPlaylistSheet';
import { SettingsStore } from '../utils/SettingsStore';
import { semanticOf } from '../tokens/LumioColor';
import { SongRow, SongMenuEntry } from '../components/SongRow';
import { LumioTheme, SpringKind } from '../tokens/LumioTheme';
import { TYPE_SM, SPACE_SM } from '../tokens/LumioScale';
import uiMaterial from '@ohos.arkui.uiMaterial';
import { acquireSheetMaterial, SheetScaffold } from '../common/utils/SheetMaterial';
// NavPathStack 为全局环境声明，无需 import

const TAG: string = 'ArtistDetail';

@Builder
export function ArtistDetailBuilder() {
  ArtistDetail()
}

/**
 * 艺术家详情页（3.0.0）。
 * 入参：路由参数（context.pathInfo.param）传入艺术家名（string），页面内按名从 MusicStore 实时聚合歌曲。
 */
@Component
struct ArtistDetail {
  pathStack: NavPathStack = new NavPathStack();
  store: MusicStore = MusicStore.getInstance();
  @StorageProp('topHeight') topHeight: number = 0;
  @StorageProp('bottomHeight') bottomHeight: number = 0;
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('coverRefreshToken') @Watch('onCoverRefreshed') coverRefreshToken: number = 0;

  @State artist: string = '';
  @State @Watch('onSongsChanged') songs: SongItem[] = [];
  private songsDataSource: SongDataSource = new SongDataSource([]);

  onSongsChanged(): void {
    this.songsDataSource.setData(this.songs);
  }
  @State itemScales: number[] = [];
  @State backScale: number = 1.0;
  @State playAllScale: number = 1.0;
  @State selectedSong: SongItem | undefined = undefined;
  @State sheetOpen: boolean = false;
  /** 半模态面板类型：详情 / 添加到歌单（与 PlaylistDetail 一致，避免长按菜单串面板）。 */
  @State sheetKind: 'detail' | 'add' = 'detail';
  @State material: uiMaterial.Material | undefined = undefined;

  private getThemeColors(): ColorTokens {
    return this.isDark ? ThemeManager.darkColors : ThemeManager.lightColors;
  }

  aboutToAppear(): void {
    acquireSheetMaterial().then((m: uiMaterial.Material | undefined): void => {
      this.material = m;
    });
  }

  onCoverRefreshed(): void {
    this.reload();
  }

  private reload(): void {
    this.songs = this.store.getSongsByArtist(this.artist);
    this.itemScales = this.songs.map(() => 1.0);
  }

  private toast(message: ResourceStr): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (e) {
      Logger.error(TAG, 'toast failed');
    }
  }

  private playAll(): void {
    if (this.songs.length === 0) {
      this.toast($r('app.string.artist_empty'));
      return;
    }
    AudioRendererController.getInstance().setQueue(this.songs, 0, true);
    this.pathStack.pushPathByName('PlayerPage', null);
  }

  private playAt(index: number): void {
    if (index < 0 || index >= this.songs.length) {
      return;
    }
    AudioRendererController.getInstance().setQueue(this.songs, index, true);
    this.pathStack.pushPathByName('PlayerPage', null);
  }

  private toggleFavoriteSong(song: SongItem): void {
    const isFav: boolean = this.store.isFavorite(song.id);
    this.store.toggleFavorite(song.id);
    try {
      this.getUIContext().getPromptAction().showToast({
        message: isFav ? $r('app.string.unfavorited') : $r('app.string.favorited')
      });
    } catch (e) {
      Logger.error(TAG, 'showToast failed');
    }
  }

  private openAddToPlaylist(song: SongItem): void {
    this.selectedSong = song;
    this.sheetKind = 'add';
    this.sheetOpen = true;
  }

  private openSongDetail(song: SongItem): void {
    this.selectedSong = song;
    this.sheetKind = 'detail';
    this.sheetOpen = true;
  }

  private buildMenuItems(song: SongItem): SongMenuEntry[] {
    return [
      { text: $r('app.string.play'), icon: $r('app.media.ic_lib_play'), action: () => { this.playAt(this.songs.indexOf(song)); } },
      { text: this.store.isFavorite(song.id) ? $r('app.string.unfavorite') : $r('app.string.favorite'), icon: $r('app.media.ic_public_collect'), action: () => { this.toggleFavoriteSong(song); } },
      { text: $r('app.string.add_to_playlist'), icon: $r('app.media.ic_public_add'), action: () => { this.openAddToPlaylist(song); } },
      { text: $r('app.string.details'), icon: $r('app.media.ic_public_detail'), action: () => { this.openSongDetail(song); } }
    ];
  }

  private entryDelay(index: number): number {
    return SettingsStore.getInstance().getReduceMotion() ? 0 : index * 40;
  }

  @Builder
  private coverCollage() {
    Row() {
      ForEach(this.songs.slice(0, 4), (song: SongItem) => {
        CoverImageView({ src: song.src, coverSize: 56, coverRadius: 12 })
          .margin({ right: SPACE_SM.compact })
      }, (song: SongItem): string => `${song.id}`)
    }
    .width('100%')
    .margin({ left: SPACE_SM.base, right: SPACE_SM.base, bottom: SPACE_SM.cozy })
  }

  build() {
    NavDestination() {
      Column() {
        Row() {
          Image($r('app.media.ic_public_arrow_left'))
            .width(24)
            .height(24)
            .fillColor(this.getThemeColors().primaryText)
            .scale({ x: this.backScale, y: this.backScale })
            .animation({ duration: 150, curve: LumioTheme.curve(SpringKind.Crisp) })
            .onClick(() => {
              this.pathStack.pop();
            })
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) {
                this.backScale = 0.8;
              } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.backScale = 1.0;
              }
            })

          Text(this.artist.length > 0 ? this.artist : $r('app.string.artist'))
            .fontSize(TYPE_SM.title1.size)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getThemeColors().primaryText)
            .margin({ left: SPACE_SM.cozy })
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text($r('app.string.songs_count', this.songs.length))
            .fontSize(TYPE_SM.footnote.size)
            .fontColor(this.getThemeColors().accent)
            .backgroundColor(semanticOf(this.isDark).fillAccentSoft)
            .borderRadius(12)
            .padding({ left: SPACE_SM.cozy, right: SPACE_SM.cozy, top: SPACE_SM.tight, bottom: SPACE_SM.tight })
        }
        .width('100%')
        .padding({ left: SPACE_SM.base, right: SPACE_SM.base, top: this.topHeight + 12, bottom: SPACE_SM.cozy })

        if (this.songs.length > 0) {
          this.coverCollage()
        }

        Row() {
          Row() {
            Image($r('app.media.ic_lib_play'))
              .width(20)
              .height(20)
              .fillColor(semanticOf(this.isDark).onAccent)
            Text($r('app.string.play_all'))
              .fontSize(TYPE_SM.subhead.size)
              .fontColor(semanticOf(this.isDark).onAccent)
              .margin({ left: SPACE_SM.compact })
          }
          .layoutWeight(1)
          .height(40)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.getThemeColors().accent)
          .borderRadius(24)
          .scale({ x: this.playAllScale, y: this.playAllScale })
          .animation({ duration: 150, curve: LumioTheme.curve(SpringKind.Crisp) })
          .onClick(() => {
            this.playAll();
          })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.playAllScale = 0.97;
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.playAllScale = 1.0;
            }
          })
        }
        .width('100%')
        .padding({ left: SPACE_SM.base, right: SPACE_SM.base, bottom: SPACE_SM.cozy })

        if (this.songs.length === 0) {
          Column() {
            Image($r('app.media.ic_public_view_list'))
              .width(64)
              .height(64)
              .fillColor(this.getThemeColors().secondaryText)
              .margin({ bottom: SPACE_SM.base })

            Text($r('app.string.artist_empty'))
              .fontSize(TYPE_SM.headline.size)
              .fontColor(this.getThemeColors().secondaryText)
              .fontWeight(FontWeight.Medium)
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List() {
            LazyForEach(this.songsDataSource, (song: SongItem, index: number) => {
              ListItem() {
                SongRow({
                  song: song,
                  index: index,
                  playing: false,
                  showIndex: true,
                  showQuality: true,
                  showRemove: false,
                  coverSize: 48,
                  titleFontSize: 15,
                  rowHeight: 64,
                  leftPadding: 8,
                  animateEntry: true,
                  entryDelayMs: this.entryDelay(index),
                  menuItems: this.buildMenuItems(song),
                  onPlay: () => {
                    this.playAt(index);
                  }
                })
              }
            }, (song: SongItem): string => `${song.id}`)
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .padding({ bottom: this.bottomHeight + 16 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.getThemeColors().bg)
      .bindSheet($$this.sheetOpen, this.sheetContent(), {
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        dragBar: true,
        showClose: true,
        backgroundColor: this.getThemeColors().surfaceOverlay,
        preferType: SheetType.BOTTOM
      })
    }
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const param: Object = context.pathInfo.param as Object;
      if (typeof param === 'string') {
        this.artist = param as string;
      } else {
        Logger.warn(TAG, 'ArtistDetail: invalid route param, expected artist name string');
      }
      this.reload();
    })
    .hideTitleBar(true)
  }

  @Builder
  private sheetContent() {
    if (this.sheetKind === 'add') {
      AddToPlaylistSheet({
        songId: this.selectedSong?.id ?? 0,
        onClose: () => {
          this.sheetOpen = false;
        }
      })
    } else {
      SongDetailSheet({ songId: this.selectedSong?.id ?? 0, pathStack: this.pathStack })
    }
  }
}
