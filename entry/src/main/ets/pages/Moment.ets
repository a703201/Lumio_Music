import { SongItem } from '../models/music';
import { MusicStore } from '../services/MusicStore';

interface FolderItem {
  name: string;
  count: number;
  icon: ResourceStr;
  targetPage: string;
  songs: SongItem[];
  color: string;
}

@Component
export struct Moment {
  @Consume('navPathStack') pathStack: NavPathStack;
  store: MusicStore = MusicStore.getInstance();
  @StorageProp('topHeight') topHeight: number = 0;

  @State folders: FolderItem[] = [];
  @State itemScales: number[] = [1.0, 1.0, 1.0];
  @State statsScale: number[] = [0.8, 0.8, 0.8];
  @State statsOpacity: number[] = [0, 0, 0];

  aboutToAppear(): void {
    this.updateFolders();
    // Staggered stats animation
    for (let i = 0; i < 3; i++) {
      setTimeout(() => {
        let newScales = [...this.statsScale];
        let newOpacities = [...this.statsOpacity];
        newScales[i] = 1.0;
        newOpacities[i] = 1.0;
        this.statsScale = newScales;
        this.statsOpacity = newOpacities;
      }, 100 + i * 100);
    }
  }

  updateFolders(): void {
    this.folders = [
      { name: '我的收藏', count: this.store.getFavoriteSongs().length, icon: $r('app.media.ic_favorite'), targetPage: 'Favorites', songs: this.store.getFavoriteSongs(), color: '#FA2759' },
      { name: '本地音乐', count: this.store.songs.length, icon: $r('app.media.ic_music'), targetPage: 'LocalLibrary', songs: [...this.store.songs], color: '#34C759' },
      { name: '最近播放', count: this.store.recentlyPlayed.length, icon: $r('app.media.ic_list'), targetPage: 'PlayHistory', songs: [...this.store.recentlyPlayed], color: '#FF9500' }
    ];
  }

  @Builder
  buildFolderItem(folder: FolderItem, index: number) {
    Row() {
      Row() {
        // Icon container with color
        Stack() {
          Image(folder.icon)
            .width(24)
            .height(24)
            .fillColor(Color.White)
        }
        .width(48)
        .height(48)
        .borderRadius(14)
        .backgroundColor(folder.color)
        .margin({ right: 14 })
        .shadow({
          radius: 8,
          color: `${folder.color}33`,
          offsetX: 0,
          offsetY: 4
        })

        Column() {
          Text(folder.name)
            .fontSize(16)
            .fontColor('#1C1C1E')
            .fontWeight(FontWeight.Medium)
            .layoutWeight(1)
            .textAlign(TextAlign.Start)

          if (folder.count > 0) {
            Text(`最近: ${folder.songs[0]?.title ?? '无'}`)
              .fontSize(12)
              .fontColor('#8E8E93')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 2 })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        // Count badge
        Text(`${folder.count}`)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(folder.color)
          .backgroundColor(`${folder.color}15`)
          .borderRadius(14)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      }
      .layoutWeight(1)
      .height('100%')
      .onClick(() => {
        this.pathStack.pushPathByName(folder.targetPage, null);
      })
    }
    .width('100%')
    .height(76)
    .padding({ left: 16, right: 16 })
    .backgroundColor('#F2F2F7')
    .borderRadius(16)
    .margin({ bottom: 12 })
    .scale({ x: this.itemScales[index] ?? 1.0, y: this.itemScales[index] ?? 1.0 })
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 30 })))
    .animation({ duration: 350, curve: Curve.EaseOut, delay: index * 80 })
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
    Column() {
      Text('音乐库')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1C1C1E')
        .width('100%')
        .padding({ left: 16, right: 16, top: this.topHeight + 8, bottom: 16 })
        .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -20 })))
        .animation({ duration: 400, curve: Curve.EaseOut })

      // Stats cards
      Row() {
        Column() {
          Text(`${this.store.songs.length}`)
            .fontSize(32)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FA2759')
            .animation({ duration: 400, curve: Curve.EaseOut })
          Text('首歌曲')
            .fontSize(13)
            .fontColor('#8E8E93')
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .scale({ x: this.statsScale[0], y: this.statsScale[0] })
        .opacity(this.statsOpacity[0])
        .animation({ duration: 400, curve: Curve.EaseOut })

        Column() {
          Text(`${this.store.getFavoriteSongs().length}`)
            .fontSize(32)
            .fontWeight(FontWeight.Bold)
            .fontColor('#34C759')
            .animation({ duration: 400, curve: Curve.EaseOut })
          Text('已收藏')
            .fontSize(13)
            .fontColor('#8E8E93')
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .scale({ x: this.statsScale[1], y: this.statsScale[1] })
        .opacity(this.statsOpacity[1])
        .animation({ duration: 400, curve: Curve.EaseOut })

        Column() {
          Text(`${this.store.recentlyPlayed.length}`)
            .fontSize(32)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FF9500')
            .animation({ duration: 400, curve: Curve.EaseOut })
          Text('最近播放')
            .fontSize(13)
            .fontColor('#8E8E93')
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .scale({ x: this.statsScale[2], y: this.statsScale[2] })
        .opacity(this.statsOpacity[2])
        .animation({ duration: 400, curve: Curve.EaseOut })
      }
      .width('100%')
      .padding({ left: 24, right: 24, bottom: 24 })
      .justifyContent(FlexAlign.SpaceAround)

      // Section header
      Row() {
        Text('分类')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1C1C1E')
        Text(`${this.folders.length} 个分类`)
          .fontSize(13)
          .fontColor('#8E8E93')
          .margin({ left: 8 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 12 })

      List() {
        ForEach(this.folders, (folder: FolderItem, index: number) => {
          ListItem() {
            this.buildFolderItem(folder, index)
          }
        })
      }
      .width('100%')
      .height('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.White)
  }
}
