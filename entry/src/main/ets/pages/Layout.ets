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

import { ThemeManager, ColorTokens } from '../utils/ThemeManager';
import { LocalLibrary } from './LocalLibrary';
import { Mine } from './Mine';
import { MusicStore } from '../services/MusicStore';
import { SongItem } from '../models/music';
import { common } from '@kit.AbilityKit';
import { curves, SymbolGlyphModifier } from '@kit.ArkUI';
import { Motion, springSnappy } from '../common/utils/DesignSystem';
import { image } from '@kit.ImageKit';
import { PreferencesUtil } from '../utils/PreferencesUtil';
import { SettingsStore } from '../utils/SettingsStore';
import { OnboardingSheet } from '../components/OnboardingSheet';
// 3.0.0 起最低平台 API 26：底部导航换用 HdsTabs（@kit.UIDesignKit）+ hdsMaterial 沉浸材质，
// 替代原自绘浮动胶囊 + uiMaterial.ImmersiveMaterial 方案。
import { HdsTabs, HdsTabsController, BlurStrategy, hdsMaterial } from '@kit.UIDesignKit';
import { semanticOf, onMediaOf } from '../tokens/LumioColor';

const PLAYER_COVER_ID: string = 'player_cover';

interface TabItem {
  title: ResourceStr;
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
  @StorageLink('songList') @Watch('refreshPlayerCover') songList: SongItem[] = [];
  @StorageProp('selectIndex') @Watch('refreshPlayerCover') selectIndex: number = 0;
  @StorageProp('topHeight') topHeight: number = 0;
  @StorageProp('bottomHeight') bottomHeight: number = 0;
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('coverRefreshToken') @Watch('onCoverRefreshed') coverRefreshToken: number = 0;
  /** 应用内偏好语言标记：变化时经 .key() 强制整棵内容子树重建，使 $r 以新语言重新解析。 */
  @StorageProp('appLocale') appLocale: string = 'zh-Hans';
  // 首次引导（半蒙面 Sheet）调度：AppStorage('showOnboarding') 由首启逻辑或「关于页-重新查看引导」置 true。
  @StorageLink('showOnboarding') @Watch('onShowOnboarding') showOnboarding: boolean = false;
  @State onboardingVisible: boolean = false;

  private getThemeColors(): ColorTokens {
    return this.isDark ? ThemeManager.darkColors : ThemeManager.lightColors;
  }

  private tabsController: HdsTabsController = new HdsTabsController();
  private store: MusicStore = MusicStore.getInstance();
  private rotateTimer: number = -1;
  @State currentIndex: number = 0;
  @State coverRotation: number = 0;
  // 播放按钮按压缩放
  @State playerScale: number = 1.0;
  // 底部迷你播放条的封面：缓存当前播放歌曲的真实封面（取自 CoverCache；未抽取到时回退默认图），
  // 通过 refreshPlayerCover() 在切歌 / 封面抽取完成（coverRefreshToken）时刷新。
  @State playerCover: Resource | image.PixelMap = $r('app.media.ic_default_cover');

  private tabs: TabItem[] = [
    { title: $r('app.string.music_library'), icon: $r('sys.symbol.music_square_stack_fill') },
    { title: $r('app.string.mine'), icon: $r('sys.symbol.person') }
  ];

  /**
   * 构造底部页签的系统符号图标样式。
   *
   * BottomTabBarStyle 的 icon 参数类型是 ResourceStr | TabBarSymbol：
   * - 传 Resource（即 $r('sys.symbol.*')）会走 ResourceStr 分支，被当作**图片**资源渲染，
   *   而 sys.symbol 不是图片资源，结果为空白 —— 这就是图标不显示的原因；
   * - 只有传 TabBarSymbol（normal / selected 为 SymbolGlyphModifier）才按 SymbolGlyph 渲染系统符号。
   *
   * 另外 BottomTabBarStyle.iconStyle 的 TabBarIconStyle 官方说明「仅对 svg 图源生效」，
   * 对系统符号无效，因此选中态/未选中态的颜色只能由这里的 fontColor 控制。
   */
  private buildTabSymbol(item: TabItem): TabBarSymbol {
    let normal: SymbolGlyphModifier = new SymbolGlyphModifier(item.icon);
    normal.fontColor([this.getThemeColors().secondaryText]);
    let selected: SymbolGlyphModifier = new SymbolGlyphModifier(item.icon);
    selected.fontColor([this.getThemeColors().accent]);
    return { normal: normal, selected: selected };
  }

  aboutToAppear(): void {
    AppStorage.setOrCreate('songList', this.store.songs);
    // R-18/F-13：降低动态效果开启时禁用封面旋转定时器
    if (!SettingsStore.getInstance().getReduceMotion()) {
      this.rotateTimer = setInterval(() => {
        if (this.isPlaying) {
          this.coverRotation = (this.coverRotation + 1.6) % 360;
        }
      }, 40);
    }
    this.maybeShowPermissionGuide();
    this.maybeShowOnboarding();
    this.refreshPlayerCover();
  }

  // 首次启动展示权限用途说明，仅弹一次（持久化标记）
  private maybeShowPermissionGuide(): void {
    const context: common.UIAbilityContext | undefined =
      AppStorage.get('context') as common.UIAbilityContext;
    if (!context) {
      return;
    }
    PreferencesUtil.getInstance().isPermGuideShown(context)
      .then((shown: boolean) => {
        if (shown) {
          return;
        }
        // 延迟一点，避免与首屏转场抢弹窗
        setTimeout(() => {
          this.getUIContext().showAlertDialog({
            title: $r('app.string.perm_guide_title'),
            message: $r('app.string.perm_guide_message'),
            primaryButton: {
              value: $r('app.string.perm_guide_ok'),
              action: () => {
                PreferencesUtil.getInstance().markPermGuideShown(context);
              }
            }
          });
        }, 400);
      })
      .catch(() => {});
  }

  aboutToDisappear(): void {
    if (this.rotateTimer >= 0) {
      clearInterval(this.rotateTimer);
    }
  }

  /** showOnboarding 变化（首启或关于页重入）时同步 Sheet 可见态。 */
  private onShowOnboarding(): void {
    this.onboardingVisible = this.showOnboarding;
  }

  /** 首次启动展示引导（半蒙面 Sheet），仅弹一次（持久化标记）。 */
  private maybeShowOnboarding(): void {
    const context: common.UIAbilityContext | undefined =
      AppStorage.get('context') as common.UIAbilityContext;
    if (!context) {
      return;
    }
    PreferencesUtil.getInstance().isOnboardingShown(context)
      .then((shown: boolean) => {
        if (shown) {
          return;
        }
        setTimeout(() => {
          AppStorage.setOrCreate('showOnboarding', true);
        }, 600);
      })
      .catch(() => {});
  }

  /** 关闭引导：隐藏 Sheet 并持久化已展示标记（避免下次启动重复弹出）。 */
  private closeOnboarding(): void {
    AppStorage.setOrCreate('showOnboarding', false);
    const context: common.UIAbilityContext | undefined =
      AppStorage.get('context') as common.UIAbilityContext;
    if (context) {
      PreferencesUtil.getInstance().markOnboardingShown(context);
    }
  }

  /** 引导 Sheet 内容构建器（bindSheet 要求 CustomBuilder 入参）。 */
  @Builder
  private onboardingContent() {
    OnboardingSheet({ onClose: () => this.closeOnboarding() })
  }

  private onCoverRefreshed(): void {
    // coverRefreshToken 变化（导入/重启后 CoverCache 批量抽取完成）即重读当前播放歌曲的封面。
    this.refreshPlayerCover();
  }

  /**
   * 刷新迷你播放条封面：始终取当前播放歌曲的真实封面（CoverCache 命中时为 PixelMap，否则回退默认图）。
   * 在切歌（selectIndex 变化）、队列变化（songList 变化）、封面抽取完成（coverRefreshToken）时调用。
   */
  private refreshPlayerCover(): void {
    if (this.songList.length === 0 || !this.songList[this.selectIndex]) {
      this.playerCover = $r('app.media.ic_default_cover');
      return;
    }
    this.playerCover = this.songList[this.selectIndex].getLabel();
  }

  private openPlayer(): void {
    // 进入播放页同样包在 animateTo 里，让底部栏封面与播放页封面的
    // geometryTransition('player_cover') 接管「一镜到底」——封面从底部栏位置
    // 平滑飞到播放页位置（spring 曲线）。退出时的 back() 已对称包 animateTo，
    // 此前进入遗漏该上下文，导致进入转场消失、只剩退出转场。
    this.getUIContext().animateTo(
      { curve: curves.interpolatingSpring(0, 1, 342, 38) },
      () => {
        this.pathStack.pushPathByName('PlayerPage', null);
      }
    );
  }

  @Builder

  private playerButton() {
    Stack() {
      if (this.songList.length > 0) {
        // 一镜到底共享元素：与播放页同用 getLabel() 取到的真实封面，两端内容一致、过渡更稳
        Image(this.playerCover)
          .width(48)
          .height(48)
          .borderRadius(16)
          .clip(true)
          .shadow({
            radius: 6,
            color: this.getThemeColors().separator,
            offsetX: 0,
            offsetY: 2
          })
          .geometryTransition(PLAYER_COVER_ID, { follow: true })

        // 封面中央播放状态指示（非交互，点击由 playerButton 打开播放页）。
        // 用可靠位图资源，避免 SymbolGlyph 在部分设备渲染不确定导致图标错乱/误导。
        // 注意：AppStorage('isPlay') 在本入口的运行时绑定与播放态相反（与播放页主按钮一致），
        // 故采用反相映射——实际播放中显示「开始/播放」三角(ic_hm_play)，停止时显示「暂停」双竖条(ic_hm_pause)。
        if (this.isPlaying) {
          this.playStateOverlay($r('app.media.ic_hm_pause'))
        } else {
          this.playStateOverlay($r('app.media.ic_hm_play'))
        }
      } else {
        Image($r('app.media.ic_hm_play'))
          .width(24)
          .height(24)
          .fillColor(semanticOf(this.isDark).onAccent)
      }
    }
    .width(56)
    .height(56)
    .backgroundColor(this.getThemeColors().accent)
    .borderRadius(16)
    .margin({ bottom: this.bottomHeight + 72, right: 16 })
    .shadow({
      radius: 12,
      color: semanticOf(this.isDark).fillAccentMuted,
      offsetX: 0,
      offsetY: 4
    })
    .scale({ x: this.playerScale, y: this.playerScale })
    .animation({ curve: springSnappy(), duration: Motion.tap })
    .onClick(() => {
      this.openPlayer();
    })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.playerScale = 0.9;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.playerScale = 1.0;
      }
    })
  }

  /** 封面中央播放状态遮罩图标（不可交互，点击交由 playerButton 打开播放页）。 */
  @Builder
  private playStateOverlay(icon: ResourceStr) {
    Column() {
      Image(icon)
        .width(22)
        .height(22)
        .fillColor(onMediaOf(true).primary)
        .hitTestBehavior(HitTestMode.None)
    }
    .width(48)
    .height(48)
    .borderRadius(16)
    .backgroundColor(onMediaOf(true).scrim)
    .justifyContent(FlexAlign.Center)
    .hitTestBehavior(HitTestMode.None)
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        HdsTabs({ controller: this.tabsController }) {
          TabContent() {
            LocalLibrary()
          }
          .tabBar(BottomTabBarStyle.of(this.buildTabSymbol(this.tabs[0]), this.tabs[0].title)
            .labelStyle({ selectedColor: this.getThemeColors().accent, unselectedColor: this.getThemeColors().secondaryText }))

          TabContent() {
            Mine()
          }
          .tabBar(BottomTabBarStyle.of(this.buildTabSymbol(this.tabs[1]), this.tabs[1].title)
            .labelStyle({ selectedColor: this.getThemeColors().accent, unselectedColor: this.getThemeColors().secondaryText }))
        }
        .barPosition(BarPosition.End)
        .barMode(BarMode.Fixed)
        .barOverlap(true)
        .scrollable(false)
        .animationDuration(200)
        .blurStrategy(BlurStrategy.ADAPTIVE)
        .barFloatingStyle({
          barBottomMargin: this.bottomHeight + 8,
          barSideMargin: 12,
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.IMMERSIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
          },
          thermoCtrl: true
        })
        .onChange((index: number) => {
          this.currentIndex = index;
        })
        .backgroundColor(this.getThemeColors().bg)

        // 播放按钮悬浮在 tabBar 右上方（FAB 风格），不挤占 tab 项空间
        this.playerButton()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.getThemeColors().bg)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .key(this.appLocale)
      .bindSheet($$this.onboardingVisible, this.onboardingContent(), {
        detents: ['90%'],
        dragBar: true,
        showClose: true,
        backgroundColor: this.getThemeColors().surfaceOverlay,
        onDisappear: () => {
          this.closeOnboarding();
        }
      })
    }
    .hideTitleBar(true)
  }
}
