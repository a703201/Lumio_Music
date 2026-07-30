import { curves } from '@kit.ArkUI';
import { ThemeManager, ColorTokens } from '../utils/ThemeManager';
import { LocalLibrary } from './LocalLibrary';
import { Mine } from './Mine';
import { MusicStore } from '../services/MusicStore';
import { SongItem } from '../models/music';

const ACCENT: string = '#FA2759';
const PLAYER_COVER_ID: string = 'player_cover';

interface TabItem {
  title: string;
  icon: Resource;
}

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
  @StorageProp('topHeight') topHeight: number = 0;
  @StorageProp('bottomHeight') bottomHeight: number = 0;
  @StorageProp('isDark') isDark: boolean = false;

  private getThemeColors(): ColorTokens {
    return this.isDark ? ThemeManager.darkColors : ThemeManager.lightColors;
  }

  private tabsController: TabsController = new TabsController();
  private store: MusicStore = MusicStore.getInstance();
  private rotateTimer: number = -1;
  @State currentIndex: number = 0;
  @State coverRotation: number = 0;

  private tabs: TabItem[] = [
    { title: '音乐库', icon: $r('sys.symbol.music_square_stack_fill') },
    { title: '我的', icon: $r('sys.symbol.person') }
  ];

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

  private openPlayer(): void {
    this.getUIContext().animateTo(
      { curve: curves.interpolatingSpring(0, 1, 328, 36) },
      () => {
        this.pathStack.pushPathByName('PlayerPage', null);
      }
    );
  }

  @Builder
  private capsuleTabItem(item: TabItem, index: number) {
    Column({ space: 4 }) {
      SymbolGlyph(item.icon)
        .fontSize(22)
        .fontColor([index === this.currentIndex ? ACCENT : this.getThemeColors().secondaryText])
        .animation({ duration: 160, curve: Curve.EaseOut })

      Text(item.title)
        .fontSize(11)
        .fontColor(index === this.currentIndex ? ACCENT : this.getThemeColors().secondaryText)
        .fontWeight(index === this.currentIndex ? FontWeight.Medium : FontWeight.Regular)
        .animation({ duration: 160, curve: Curve.EaseOut })
    }
    .height('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.tabsController.changeIndex(index);
    })
  }

  @Builder
  private playerButton() {
    Stack() {
      if (this.songList.length > 0) {
        Image(this.songList[this.selectIndex].getLabel())
          .width(48)
          .height(48)
          .borderRadius(this.isPlaying ? 24 : 14)
          .clip(true)
          .rotate({ angle: this.isPlaying ? this.coverRotation : 0 })
          .animation({ duration: 40, curve: Curve.Linear })
          .shadow({
            radius: 6,
            color: 'rgba(0, 0, 0, 0.20)',
            offsetX: 0,
            offsetY: 2
          })
          .geometryTransition(PLAYER_COVER_ID, { follow: true })
      } else {
        Image($r('app.media.ic_hm_play'))
          .width(24)
          .height(24)
          .fillColor('#FFFFFF')
      }
    }
    .width(56)
    .height(56)
    .backgroundColor(ACCENT)
    .borderRadius(28)
    .shadow({
      radius: 12,
      color: 'rgba(250, 39, 89, 0.35)',
      offsetX: 0,
      offsetY: 4
    })
    .onClick(() => {
      this.openPlayer();
    })
  }

  @Builder
  private customBottomBar() {
    Row({ space: 16 }) {
      Row({ space: 0 }) {
        ForEach(this.tabs, (item: TabItem, index: number) => {
          this.capsuleTabItem(item, index)
        }, (item: TabItem, index: number) => index.toString())
      }
      .width('100%')
      .height(64)
      .backgroundColor(this.getThemeColors().cardBg)
      .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
      .borderRadius(32)
      .padding({ left: 8, right: 8 })
      .shadow({
        radius: 16,
        color: 'rgba(0, 0, 0, 0.10)',
        offsetX: 0,
        offsetY: 6
      })
      .layoutWeight(1)
      .justifyContent(FlexAlign.SpaceEvenly)

      this.playerButton()
    }
    .width('100%')
    .height(80)
    .padding({ left: 16, right: 16, bottom: this.bottomHeight + 8 })
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        Tabs({ barPosition: BarPosition.End, controller: this.tabsController }) {
          TabContent() {
            LocalLibrary()
          }

          TabContent() {
            Mine()
          }
        }
        .barHeight(0)
        .scrollable(false)
        .animationDuration(200)
        .onChange((index: number) => {
          this.currentIndex = index;
        })
        .padding({ bottom: 96 + this.bottomHeight })

        this.customBottomBar()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.getThemeColors().bg)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }
    .hideTitleBar(true)
  }
}
