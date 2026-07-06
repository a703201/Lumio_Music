import { AudioRendererController } from '../utils/AudioRendererController';
import { BreakpointConstants } from '../common/constants/BreakpointConstants';
import { BreakpointSystem } from '../common/utils/BreakpointSystem';
import { PlayerInfoComponent } from '../components/PlayerInfoComponent';
import { MusicStore } from '../services/MusicStore';
import { SongItem } from '../models/music';

@Builder
export function PlayerPageBuilder() {
  PlayerPage();
}

@Component
struct PlayerPage {
  @Consume('navPathStack') pathStack: NavPathStack;
  @StorageLink('selectIndex') selectIndex: number = 0;
  @StorageLink('songList') songList: SongItem[] = [];
  @State isShowPlay: boolean = false;
  @State contentOpacity: number = 0;
  @State contentTranslateY: number = 60;
  @State coverScale: number = 0.85;
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;
  private breakpointSystem: BreakpointSystem = new BreakpointSystem();

  aboutToAppear(): void {
    const store = MusicStore.getInstance();
    const savedIndex = AppStorage.get('selectIndex') as number ?? 0;
    if (savedIndex >= 0 && savedIndex < store.songs.length) {
      store.currentIndex = savedIndex;
    }
    AppStorage.setOrCreate('songList', store.songs);
    AppStorage.setOrCreate('selectIndex', store.currentIndex);
    AudioRendererController.getInstance();
    this.breakpointSystem.register();
    // Entrance animation
    setTimeout(() => {
      this.contentOpacity = 1;
      this.contentTranslateY = 0;
      this.coverScale = 1.0;
    }, 50);
  }

  aboutToDisappear(): void {
    this.breakpointSystem.unregister();
    AudioRendererController.getInstance().release();
  }

  build() {
    NavDestination() {
      PlayerInfoComponent({ isShowPlay: this.isShowPlay })
        .opacity(this.contentOpacity)
        .translate({ y: this.contentTranslateY })
        .scale({ x: this.coverScale, y: this.coverScale })
        .animation({
          duration: 400,
          curve: Curve.EaseOut
        })
    }
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .hideTitleBar(true)
    .onWillDisappear(() => {
      // Exit animation
      this.contentOpacity = 0;
      this.contentTranslateY = 60;
      this.coverScale = 0.85;
    })
  }
}
