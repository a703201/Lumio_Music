import { curves } from '@kit.ArkUI';
import {
  HdsTabs,
  HdsTabsController,
  hdsMaterial
} from '@kit.UIDesignKit';
import { LocalLibrary } from './LocalLibrary';
import { Mine } from './Mine';
import { AudioRendererController } from '../utils/AudioRendererController';
import { MusicStore } from '../services/MusicStore';
import { SongItem } from '../models/music';

const ACCENT: string = '#FA2759';
const PLAYER_COVER_ID: string = 'player_cover';

@Builder
export function LayoutBuilder() {
  Layout()
}

@Component
struct Layout {
  @Consume('navPathStack') pathStack: NavPathStack;
  @StorageLink('isPlay') isPlaying: boolean = false;
  @StorageLink('songList') songList: SongItem[] = [];
  @StorageLink('selectIndex') selectIndex: number = 0;
  @StorageLink('progress') progress: number = 0;
  @StorageLink('progressMax') progressMax: number = 1;
  @StorageProp('imageColor') imageColor: string = 'rgba(0, 0, 0, 0)';
  @StorageProp('topHeight') topHeight: number = 0;
  @StorageProp('bottomHeight') bottomHeight: number = 0;

  private controller: HdsTabsController = new HdsTabsController();
  private store: MusicStore = MusicStore.getInstance();
  private rotateTimer: number = -1;
  @State currentIndex: number = 0;
  @State coverRotation: number = 0;

  aboutToAppear(): void {
    AppStorage.setOrCreate('songList', this.store.songs);
    this.rotateTimer = setInterval(() => {
      if (this.isPlaying) {
        this.coverRotation = (this.coverRotation + 1.6) % 360;
      }
    }, 40);
  }

  aboutToDisappear(): void {
    if (this.rotateTimer >= 0) {
      clearInterval(this.rotateTimer);
    }
  }

  private togglePlay(): void {
    const arc: AudioRendererController = AudioRendererController.getInstance();
    if (this.isPlaying) {
      arc.pause();
    } else {
      if (arc.getFirst()) {
        arc.play(0);
      } else {
        arc.start();
      }
    }
  }

  // 一镜到底：把进入播放页的压栈包进 animateTo，触发共享元素过渡
  private openPlayer(): void {
    this.getUIContext().animateTo(
      { curve: curves.interpolatingSpring(0, 1, 328, 36) },
      () => {
        this.pathStack.pushPathByName('PlayerPage', null);
      }
    );
  }

  // 自定义底部标签栏（兼容当前 SDK：HdsTabs + CustomBuilder tabBar）
  @Builder
  tabBarItem(index: number) {
    Column({ space: 4 }) {
      SymbolGlyph(index === 0 ? $r('sys.symbol.music_square_stack_fill') : $r('sys.symbol.person'))
        .fontSize(22)
        .fontColor([index === this.currentIndex ? ACCENT : '#8E8E93'])
      Text(index === 0 ? '音乐库' : '我的')
        .fontSize(10)
        .fontColor(index === this.currentIndex ? ACCENT : '#8E8E93')
    }
  }

  @Builder
  tabBuilder() {
    HdsTabs({ controller: this.controller }) {
      TabContent() {
        LocalLibrary()
      }
      .tabBar(this.tabBarItem(0))

      TabContent() {
        Mine()
      }
      .tabBar(this.tabBarItem(1))
    }
    .barOverlap(true)
    .vertical(false)
    .barPosition(BarPosition.End)
    .scrollable(false)
    .onChange((index: number) => {
      this.currentIndex = index;
    })
    .onAttach(() => {
      try {
        this.controller.preloadItems([0, 1]);
      } catch (error) {
        console.error(`HdsTabs preload failed: ${error}`);
      }
    })
    // 沉浸光感 + 智感握姿：悬浮玻璃底栏，自动跟随握持手（需设备支持）
    .barFloatingStyle({
      adaptToHandedness: true,
      barBottomMargin: this.bottomHeight + 12,
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      }
    })
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        // 主内容（HDS 悬浮底栏）
        this.tabBuilder()

        // 迷你播放条：作为"一镜到底"的共享元素（封面带 geometryTransition）
        if (this.songList.length > 0) {
          Column() {
            Row() {
              Stack() {
                Image(this.songList[this.selectIndex].getLabel())
                  .width(46)
                  .height(46)
                  .borderRadius(this.isPlaying ? 23 : 12)
                  .clip(true)
                  .rotate({ angle: this.isPlaying ? this.coverRotation : 0 })
                  .animation({ duration: 40, curve: Curve.Linear })
                  .shadow({
                    radius: 8,
                    color: 'rgba(0, 0, 0, 0.18)',
                    offsetX: 0,
                    offsetY: 2
                  })
                  .geometryTransition(PLAYER_COVER_ID, { follow: true })
              }
              .width(46)
              .height(46)

              Column() {
                Text(this.songList[this.selectIndex].title)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#1C1C1E')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                Text(this.songList[this.selectIndex].singer)
                  .fontSize(12)
                  .fontColor('#8E8E93')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ top: 2 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              .padding({ left: 12 })

              Image(this.isPlaying ? $r('app.media.ic_hm_pause') : $r('app.media.ic_hm_play'))
                .width(34)
                .height(34)
                .fillColor(ACCENT)
                .animation({ duration: 140, curve: Curve.EaseOut })
                .onClick(() => {
                  this.togglePlay();
                })
            }
            .width('100%')
            .height(66)
            .padding({ left: 14, right: 12 })

            Row() {
              Text('')
                .width(`${this.progressMax > 0 ? (this.progress / this.progressMax) * 100 : 0}%`)
                .height(2)
                .backgroundColor(ACCENT)
                .borderRadius(1)
            }
            .width('100%')
            .height(2)
            .backgroundColor('#E5E5EA')
          }
          .width('92%')
          .backgroundColor('rgba(255, 255, 255, 0.82)')
          .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
          .borderRadius(20)
          .shadow({
            radius: 16,
            color: 'rgba(0, 0, 0, 0.10)',
            offsetX: 0,
            offsetY: 6
          })
          .margin({ left: 16, right: 16, bottom: this.bottomHeight + 92 })
          .onClick(() => {
            this.openPlayer();
          })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.White)
    }
    .hideTitleBar(true)
  }
}
