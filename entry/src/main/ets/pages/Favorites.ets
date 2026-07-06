import { SongItem } from '../models/music';
import { MusicStore } from '../services/MusicStore';

@Builder
export function FavoritesBuilder() {
  Favorites()
}

@Component
struct Favorites {
  pathStack: NavPathStack = new NavPathStack();
  store: MusicStore = MusicStore.getInstance();
  @StorageProp('topHeight') topHeight: number = 0;

  @State itemScales: number[] = [];
  @State favScales: number[] = [];
  @State backScale: number = 1.0;
  @State emptyIconScale: number = 1.0;
  @State playingIndex: number = -1;

  aboutToAppear(): void {
    const favs = this.store.getFavoriteSongs();
    this.itemScales = favs.map(() => 1.0);
    this.favScales = favs.map(() => 1.0);
    setInterval(() => {
      if (this.store.getFavoriteSongs().length === 0) {
        this.emptyIconScale = this.emptyIconScale === 1.0 ? 1.08 : 1.0;
      }
      this.playingIndex = this.store.isPlaying ? this.store.currentIndex : -1;
    }, 500);
  }

  @Builder
  buildSongItem(song: SongItem, index: number) {
    Row() {
      // Index number
      Text(`${index + 1}`)
        .fontSize(13)
        .fontColor(this.playingIndex === song.id ? '#FA2759' : '#C7C7CC')
        .width(28)
        .textAlign(TextAlign.Center)

      Stack() {
        Image(song.getMark())
          .width(48)
          .height(48)
          .borderRadius(this.playingIndex === song.id ? 24 : 8)
          .clip(true)
          .animation({ duration: 300, curve: Curve.EaseOut })
      }

      Column() {
        Text(song.title)
          .fontSize(15)
          .fontColor(this.playingIndex === song.id ? '#FA2759' : '#1C1C1E')
          .fontWeight(FontWeight.Medium)
          .margin({ bottom: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .animation({ duration: 200, curve: Curve.EaseOut })

        Text(song.singer)
          .fontSize(13)
          .fontColor('#8E8E93')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 12 })

      // Favorite icon with pulse
      Image($r('app.media.ic_favorite'))
        .width(22)
        .height(22)
        .fillColor('#FA2759')
        .scale({ x: this.favScales[index] ?? 1.0, y: this.favScales[index] ?? 1.0 })
        .animation({ duration: 200, curve: Curve.EaseOut })
    }
    .width('100%')
    .height(64)
    .padding({ left: 8, right: 16 })
    .backgroundColor(this.playingIndex === song.id ? 'rgba(250, 39, 89, 0.05)' : '#F2F2F7')
    .borderRadius(12)
    .margin({ left: 8, right: 8, bottom: 8 })
    .scale({ x: this.itemScales[index] ?? 1.0, y: this.itemScales[index] ?? 1.0 })
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 30 })))
    .animation({ duration: 300, curve: Curve.EaseOut, delay: index * 50 })
    .onClick(() => {
      const globalIndex = this.store.songs.findIndex(s => s.id === song.id);
      if (globalIndex >= 0) {
        this.store.currentIndex = globalIndex;
        AppStorage.setOrCreate('selectIndex', globalIndex);
        AppStorage.setOrCreate('songList', this.store.songs);
      }
      this.pathStack.pushPathByName('PlayerPage', null);
    })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        let scales = [...this.itemScales];
        scales[index] = 0.96;
        this.itemScales = scales;
        // Pulse the heart icon
        let fScales = [...this.favScales];
        fScales[index] = 1.3;
        this.favScales = fScales;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        let scales = [...this.itemScales];
        scales[index] = 1.0;
        this.itemScales = scales;
        let fScales = [...this.favScales];
        fScales[index] = 1.0;
        this.favScales = fScales;
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
            .fillColor('#1C1C1E')
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

          Text('我的收藏')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1C1C1E')
            .margin({ left: 12 })
            .layoutWeight(1)

          // Count badge
          Text(`${this.store.getFavoriteSongs().length} 首`)
            .fontSize(13)
            .fontColor('#FA2759')
            .backgroundColor('rgba(250, 39, 89, 0.1)')
            .borderRadius(12)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: this.topHeight + 12, bottom: 16 })

        if (this.store.getFavoriteSongs().length === 0) {
          Column() {
            Image($r('app.media.ic_favorite'))
              .width(72)
              .height(72)
              .fillColor('#C7C7CC')
              .margin({ bottom: 16 })
              .scale({ x: this.emptyIconScale, y: this.emptyIconScale })
              .animation({ duration: 2000, curve: Curve.EaseInOut })

            Text('暂无收藏歌曲')
              .fontSize(16)
              .fontColor('#8E8E93')
              .fontWeight(FontWeight.Medium)

            Text('在播放页面点击收藏按钮添加')
              .fontSize(13)
              .fontColor('#636366')
              .margin({ top: 8 })
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List() {
            ForEach(this.store.getFavoriteSongs(), (song: SongItem, index: number) => {
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
      .backgroundColor(Color.White)
    }
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
    .hideTitleBar(true)
  }
}
