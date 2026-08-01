import { SongItem } from '../models/music';
import { MusicStore } from '../services/MusicStore';
import { AudioRendererController } from '../utils/AudioRendererController';

@Component
export struct Find {
  @Consume('navPathStack') pathStack: NavPathStack;
  @StorageProp('coverRefreshToken') @Watch('onCoverRefreshed') coverRefreshToken: number = 0;
  store: MusicStore = MusicStore.getInstance();

  @State cardScales: number[] = [];
  @State emptyIconScale: number = 1.0;
  @State recentSongs: SongItem[] = [];
  @State allSongs: SongItem[] = [];

  aboutToAppear(): void {
    this.recentSongs = [...this.store.recentlyPlayed];
    this.allSongs = [...this.store.songs];
    this.updateCardScales();
    setInterval(() => {
      if (this.store.recentlyPlayed.length === 0 && this.store.songs.length === 0) {
        this.emptyIconScale = this.emptyIconScale === 1.0 ? 1.08 : 1.0;
      }
    }, 2000);
  }

  onCoverRefreshed() {
    this.recentSongs = [...this.store.recentlyPlayed];
    this.allSongs = [...this.store.songs];
    this.updateCardScales();
  }

  updateCardScales(): void {
    const total = this.recentSongs.length + this.allSongs.length;
    this.cardScales = [];
    for (let i = 0; i < total; i++) {
      this.cardScales.push(1.0);
    }
  }

  @Builder
  buildSongCard(song: SongItem, globalIndex: number) {
    Row() {
      Stack() {
        Image(song.getMark())
          .width(56)
          .height(56)
          .borderRadius(8)
          .clip(true)
      }

      Column() {
        Text(song.title)
          .fontSize(15)
          .fontColor('#1C1C1E')
          .fontWeight(FontWeight.Medium)
          .margin({ bottom: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(song.singer)
          .fontSize(13)
          .fontColor('#8E8E93')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 12 })
    }
    .width('100%')
    .height(72)
    .padding({ left: 16, right: 16 })
    .backgroundColor('#F2F2F7')
    .borderRadius(12)
    .margin({ bottom: 8 })
    .scale({ x: this.cardScales[globalIndex] ?? 1.0, y: this.cardScales[globalIndex] ?? 1.0 })
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 30 })))
    .animation({ duration: 300, curve: Curve.EaseOut, delay: globalIndex * 50 })
    .onClick(() => {
      const index: number = this.store.songs.findIndex(s => s.id === song.id);
      if (index >= 0) {
        this.store.currentIndex = index;
        AudioRendererController.getInstance().playFromList(this.store.songs, index);
        this.pathStack.pushPathByName('PlayerPage', null);
      }
    })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        let scales = [...this.cardScales];
        scales[globalIndex] = 0.96;
        this.cardScales = scales;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        let scales = [...this.cardScales];
        scales[globalIndex] = 1.0;
        this.cardScales = scales;
      }
    })
  }

  build() {
    Column() {
      Text('发现')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1C1C1E')
        .margin({ bottom: 20, left: 16, right: 16 })
        .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -20 })))
        .animation({ duration: 400, curve: Curve.EaseOut })

      Scroll() {
        Column() {
          if (this.recentSongs.length > 0) {
            Text('最近播放')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor('#1C1C1E')
              .margin({ bottom: 12, left: 16, right: 16 })

            List() {
              ForEach(this.recentSongs, (song: SongItem, index: number) => {
                ListItem() {
                  this.buildSongCard(song, index)
                }
              })
            }
            .width('100%')
            .height('auto')
            .scrollBar(BarState.Off)
          }

          if (this.allSongs.length > 0) {
            Text('全部歌曲')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor('#1C1C1E')
              .margin({ top: 20, bottom: 12, left: 16, right: 16 })

            List() {
              ForEach(this.allSongs, (song: SongItem, index: number) => {
                ListItem() {
                  this.buildSongCard(song, this.recentSongs.length + index)
                }
              })
            }
            .width('100%')
            .height('auto')
            .scrollBar(BarState.Off)
          }

          if (this.recentSongs.length === 0 && this.allSongs.length === 0) {
            Column() {
              Image($r('app.media.ic_music'))
                .width(64)
                .fillColor('#8E8E93')
                .margin({ bottom: 16 })
                .scale({ x: this.emptyIconScale, y: this.emptyIconScale })
                .animation({ duration: 2000, curve: Curve.EaseInOut })

              Text('暂无内容')
                .fontSize(15)
                .fontColor('#8E8E93')

              Text('前往歌曲页面导入音乐')
                .fontSize(13)
                .fontColor('#636366')
                .margin({ top: 8 })
            }
            .width('100%')
            .height(300)
            .justifyContent(FlexAlign.Center)
          }
        }
        .width('100%')
        .padding({ bottom: 80 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.White)
  }
}
