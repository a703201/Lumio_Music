import { SongItem } from '../models/music';
import { ThemeManager, ColorTokens } from '../utils/ThemeManager';
import { MusicStore } from '../services/MusicStore';
import { AudioRendererController } from '../utils/AudioRendererController';
import { CoverImageView } from '../components/CoverImageView';

@Builder
export function PlayHistoryBuilder() {
  PlayHistory()
}

@Component
struct PlayHistory {
  pathStack: NavPathStack = new NavPathStack();
  store: MusicStore = MusicStore.getInstance();
  @StorageProp('topHeight') topHeight: number = 0;
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('coverRefreshToken') @Watch('onCoverRefreshed') coverRefreshToken: number = 0;

  private getThemeColors(): ColorTokens {
    return this.isDark ? ThemeManager.darkColors : ThemeManager.lightColors;
  }

  @State itemScales: number[] = [];
  @State recentSongs: SongItem[] = [];
  @State backScale: number = 1.0;
  @State emptyIconScale: number = 1.0;
  @State playingIndex: number = -1;

  aboutToAppear(): void {
    this.recentSongs = [...this.store.recentlyPlayed];
    this.itemScales = this.recentSongs.map(() => 1.0);
    setInterval(() => {
      if (this.store.recentlyPlayed.length === 0) {
        this.emptyIconScale = this.emptyIconScale === 1.0 ? 1.08 : 1.0;
      }
      this.playingIndex = this.store.isPlaying ? this.store.currentIndex : -1;
    }, 500);
  }

  onCoverRefreshed() {
    this.recentSongs = [...this.store.recentlyPlayed];
    this.itemScales = this.recentSongs.map(() => 1.0);
  }

  @Builder
  buildSongItem(song: SongItem, index: number) {
    Row() {
      // Index number
      Text(`${index + 1}`)
        .fontSize(13)
        .fontColor(this.playingIndex === song.id ? '#FF9500' : this.getThemeColors().secondaryText)
        .width(28)
        .textAlign(TextAlign.Center)

      Stack() {
        CoverImageView({ src: song.src, coverSize: 48, coverRadius: this.playingIndex === song.id ? 24 : 8 })
      }

      Column() {
        Text(song.title)
          .fontSize(15)
          .fontColor(this.playingIndex === song.id ? '#FF9500' : this.getThemeColors().primaryText)
          .fontWeight(FontWeight.Medium)
          .margin({ bottom: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .animation({ duration: 200, curve: Curve.EaseOut })

        Text(song.singer)
          .fontSize(13)
          .fontColor(this.getThemeColors().secondaryText)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 12 })

      // Time indicator
      Text('')
        .fontSize(12)
        .fontColor(this.getThemeColors().secondaryText)
    }
    .width('100%')
    .height(64)
    .padding({ left: 8, right: 16 })
    .backgroundColor(this.playingIndex === song.id ? 'rgba(255, 149, 0, 0.05)' : this.getThemeColors().cardBg)
    .borderRadius(12)
    .margin({ left: 8, right: 8, bottom: 8 })
    .scale({ x: this.itemScales[index] ?? 1.0, y: this.itemScales[index] ?? 1.0 })
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 30 })))
    .animation({ duration: 300, curve: Curve.EaseOut, delay: index * 50 })
    .onClick(() => {
      const globalIndex = this.store.songs.findIndex(s => s.id === song.id);
      if (globalIndex >= 0) {
        this.store.currentIndex = globalIndex;
        AudioRendererController.getInstance().playFromList(this.store.songs, globalIndex);
      }
      this.pathStack.pushPathByName('PlayerPage', null);
    })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        let scales = [...this.itemScales];
        scales[index] = 0.96;
        this.itemScales = scales;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        let scales = [...this.itemScales];
        scales[index] = 1.0;
        this.itemScales = scales;
      }
    })
  }

  build() {
    NavDestination() {
      Column() {
        // Header
        Row() {
          Image($r('app.media.ic_back'))
            .width(24)
            .height(24)
            .fillColor(this.getThemeColors().primaryText)
            .scale({ x: this.backScale, y: this.backScale })
            .animation({ duration: 150, curve: Curve.EaseOut })
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

          Text('播放历史')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getThemeColors().primaryText)
            .margin({ left: 12 })
            .layoutWeight(1)

          // Count badge
          Text(`${this.recentSongs.length} 首`)
            .fontSize(13)
            .fontColor('#FF9500')
            .backgroundColor('rgba(255, 149, 0, 0.1)')
            .borderRadius(12)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: this.topHeight + 12, bottom: 16 })

        if (this.recentSongs.length === 0) {
          Column() {
            Image($r('app.media.ic_list'))
              .width(72)
              .height(72)
              .fillColor(this.getThemeColors().secondaryText)
              .margin({ bottom: 16 })
              .scale({ x: this.emptyIconScale, y: this.emptyIconScale })
              .animation({ duration: 2000, curve: Curve.EaseInOut })

            Text('暂无播放记录')
              .fontSize(16)
              .fontColor(this.getThemeColors().secondaryText)
              .fontWeight(FontWeight.Medium)

            Text('播放歌曲后将在这里显示')
              .fontSize(13)
              .fontColor(this.getThemeColors().secondaryText)
              .margin({ top: 8 })

          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List() {
            ForEach(this.recentSongs, (song: SongItem, index: number) => {
              ListItem() {
                this.buildSongItem(song, index)
              }
            })
          }
          .width('100%')
          .height('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.getThemeColors().bg)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
  }
}
