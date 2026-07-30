import { common, Want } from '@kit.AbilityKit';
import { getAppVersionDisplay } from '../utils/AppInfoUtil';
import { MusicStore } from '../services/MusicStore';
import { SettingsStore, ThemeMode, RepeatModeSetting, QualitySetting } from '../utils/SettingsStore';
import { ThemeManager } from '../utils/ThemeManager';
import fs from '@ohos.file.fs';

interface PickerOption {
  label: string;
  value: string;
}

@Builder
export function SettingsBuilder() {
  Settings()
}

@Component
struct Settings {
  pathStack: NavPathStack = new NavPathStack();
  store: MusicStore = MusicStore.getInstance();
  settings: SettingsStore = SettingsStore.getInstance();
  @StorageProp('topHeight') topHeight: number = 0;
  @StorageProp('isDark') isDark: boolean = false;

  @State itemScales: number[] = new Array(24).fill(1.0);
  @State backScale: number = 1.0;
  @State appVersionDisplay: string = 'Lumio Music';

  // 设置项 UI 镜像状态
  @State autoNext: boolean = true;
  @State repeatMode: RepeatModeSetting = 'list';
  @State allowMobileNetwork: boolean = false;
  @State quality: QualitySetting = 'standard';
  @State themeMode: ThemeMode = 'system';
  @State notificationLockScreen: boolean = true;
  @State privacyStats: boolean = true;
  @State cacheSizeText: string = '约 0.0 MB';

  // 当前单选弹窗类型（repeat/quality/theme，空串表示无）
  @State currentPicker: 'repeat' | 'quality' | 'theme' | '' = '';
  pickerController: CustomDialogController = new CustomDialogController({
    builder: this.pickerDialogBuilder,
    autoCancel: true,
    alignment: DialogAlignment.Center
  });

  aboutToAppear(): void {
    this.appVersionDisplay = getAppVersionDisplay();
    // 注入 context 并（幂等）初始化 SettingsStore，随后同步 UI 状态
    const hostCtx: Context | undefined = this.getUIContext().getHostContext();
    if (hostCtx) {
      this.settings.ensureInitialized(hostCtx).then(() => {
        this.syncFromStore();
      });
    } else {
      this.syncFromStore();
    }
    this.refreshCacheSize();
  }

  private syncFromStore(): void {
    this.autoNext = this.settings.getAutoNext();
    this.repeatMode = this.settings.getRepeatMode();
    this.allowMobileNetwork = this.settings.getAllowMobileNetwork();
    this.quality = this.settings.getQuality();
    this.themeMode = this.settings.getThemeMode();
    this.notificationLockScreen = this.settings.getNotificationLockScreen();
    this.privacyStats = this.settings.getPrivacyStats();
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (e) {
      console.error('toast failed');
    }
  }

  // ===== 外跳网页（无 ArkWeb，使用 startAbility）=====
  private openUrl(url: string): void {
    try {
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: url
      };
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      context.startAbility(want).catch((err: Error) => {
        console.error('Failed to open url:', err);
        this.toast('无法打开网页');
      });
    } catch (err) {
      console.error('Failed to open url:', err);
      this.toast('无法打开网页');
    }
  }

  private openDeveloper(): void {
    this.openUrl('https://www.a703201sworld.top/resume/');
  }

  private openPrivacyPolicy(): void {
    this.openUrl('https://www.a703201sworld.top/privacy/');
  }

  // ===== 缓存估算与清理 =====
  private refreshCacheSize(): void {
    this.cacheSizeText = this.computeCacheSize();
  }

  private computeCacheSize(): string {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      let total: number = 0;
      total += this.dirSize(ctx.cacheDir);
      const downloadDir: string = ctx.filesDir + '/download';
      total += this.dirSize(downloadDir);
      const mb: number = total / (1024 * 1024);
      return `约 ${mb.toFixed(1)} MB`;
    } catch (e) {
      return '约 0.0 MB';
    }
  }

  private dirSize(path: string): number {
    let size: number = 0;
    try {
      if (!fs.accessSync(path)) {
        return 0;
      }
      const files: string[] = fs.listFileSync(path);
      for (const f of files) {
        const full: string = path + '/' + f;
        try {
          const stat = fs.statSync(full);
          if (stat.isDirectory()) {
            size += this.dirSize(full);
          } else {
            size += stat.size;
          }
        } catch (e) {
          // skip unreadable entry
        }
      }
    } catch (e) {
      // skip
    }
    return size;
  }

  private async clearCache(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.deleteDirContents(ctx.cacheDir);
      const downloadDir: string = ctx.filesDir + '/download';
      this.deleteDirContents(downloadDir);
    } catch (e) {
      // ignore
    }
    this.refreshCacheSize();
  }

  private deleteDirContents(path: string): void {
    try {
      if (!fs.accessSync(path)) {
        return;
      }
      const files: string[] = fs.listFileSync(path);
      for (const f of files) {
        const full: string = path + '/' + f;
        try {
          fs.rmdirSync(full);
        } catch (e) {
          try {
            fs.unlinkSync(full);
          } catch (e2) {
            // ignore
          }
        }
      }
    } catch (e) {
      // ignore
    }
  }

  // ===== 标签 =====
  private repeatModeLabel(): string {
    switch (this.repeatMode) {
      case 'list': return '列表循环';
      case 'single': return '单曲循环';
      case 'random': return '随机播放';
      default: return '列表循环';
    }
  }

  private qualityLabel(): string {
    return this.quality === 'high' ? '高品' : '标准';
  }

  private themeModeLabel(): string {
    switch (this.themeMode) {
      case 'system': return '跟随系统';
      case 'light': return '浅色';
      case 'dark': return '深色';
      default: return '跟随系统';
    }
  }

  // ===== 单选弹窗 =====
  private pickerTitle(): string {
    switch (this.currentPicker) {
      case 'repeat': return '播放模式';
      case 'quality': return '默认音质';
      case 'theme': return '外观';
      default: return '';
    }
  }

  private currentPickerOptions(): PickerOption[] {
    switch (this.currentPicker) {
      case 'repeat':
        return [
          { label: '列表循环', value: 'list' },
          { label: '单曲循环', value: 'single' },
          { label: '随机播放', value: 'random' }
        ];
      case 'quality':
        return [
          { label: '标准', value: 'standard' },
          { label: '高品', value: 'high' }
        ];
      case 'theme':
        return [
          { label: '跟随系统', value: 'system' },
          { label: '浅色', value: 'light' },
          { label: '深色', value: 'dark' }
        ];
      default:
        return [];
    }
  }

  private currentPickerValue(): string {
    switch (this.currentPicker) {
      case 'repeat': return this.repeatMode;
      case 'quality': return this.quality;
      case 'theme': return this.themeMode;
      default: return '';
    }
  }

  private applyPicker(value: string): void {
    const picker = this.currentPicker;
    this.currentPicker = '';
    if (picker === 'repeat') {
      this.repeatMode = value as RepeatModeSetting;
      this.settings.setRepeatMode(value as RepeatModeSetting);
    } else if (picker === 'quality') {
      this.quality = value as QualitySetting;
      this.settings.setQuality(value as QualitySetting);
    } else if (picker === 'theme') {
      this.themeMode = value as ThemeMode;
      ThemeManager.setThemeMode(value as ThemeMode);
    }
  }

  // ===== 通用卡片（箭头/可点击）=====
  @Builder
  buildSettingItem(icon: ResourceStr, title: string, subtitle: string = '', index: number = 0,
    iconColor: string = '#FA2759', onClick: () => void = () => {}) {
    Column() {
      Row() {
        Stack() {
          Image(icon)
            .width(20)
            .height(20)
            .fillColor(Color.White)
        }
        .width(36)
        .height(36)
        .borderRadius(10)
        .backgroundColor(iconColor)
        .margin({ right: 14 })
        .shadow({
          radius: 6,
          color: `${iconColor}33`,
          offsetX: 0,
          offsetY: 2
        })

        Column() {
          Text(title)
            .fontSize(16)
            .fontColor(ThemeManager.getColors().primaryText)
            .fontWeight(FontWeight.Medium)
            .margin({ bottom: subtitle ? 4 : 0 })

          if (subtitle) {
            Text(subtitle)
              .fontSize(13)
              .fontColor(ThemeManager.getColors().secondaryText)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Image($r('app.media.ic_hm_more'))
          .width(16)
          .fillColor(ThemeManager.getColors().separator)
      }
      .width('100%')
      .height(60)
      .padding({ left: 16, right: 16 })
      .onClick(onClick)
    }
    .width('100%')
    .backgroundColor(ThemeManager.getColors().cardBg)
    .borderRadius(14)
    .margin({ bottom: 2 })
    .scale({ x: this.itemScales[index] ?? 1.0, y: this.itemScales[index] ?? 1.0 })
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 20 })))
    .animation({ duration: 300, curve: Curve.EaseOut, delay: index * 60 })
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

  // ===== 开关卡片（右侧 Toggle，点击不 push）=====
  @Builder
  buildToggleItem(icon: ResourceStr, title: string, subtitle: string = '', index: number = 0,
    iconColor: string = '#FA2759', isOn: boolean = false, onToggle: (isOn: boolean) => void = () => {}) {
    Column() {
      Row() {
        Stack() {
          Image(icon)
            .width(20)
            .height(20)
            .fillColor(Color.White)
        }
        .width(36)
        .height(36)
        .borderRadius(10)
        .backgroundColor(iconColor)
        .margin({ right: 14 })
        .shadow({
          radius: 6,
          color: `${iconColor}33`,
          offsetX: 0,
          offsetY: 2
        })

        Column() {
          Text(title)
            .fontSize(16)
            .fontColor(ThemeManager.getColors().primaryText)
            .fontWeight(FontWeight.Medium)
            .margin({ bottom: subtitle ? 4 : 0 })

          if (subtitle) {
            Text(subtitle)
              .fontSize(13)
              .fontColor(ThemeManager.getColors().secondaryText)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: isOn })
          .selectedColor(ThemeManager.getColors().accent)
          .onChange((value: boolean) => {
            onToggle(value);
          })
      }
      .width('100%')
      .height(60)
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .backgroundColor(ThemeManager.getColors().cardBg)
    .borderRadius(14)
    .margin({ bottom: 2 })
    .scale({ x: this.itemScales[index] ?? 1.0, y: this.itemScales[index] ?? 1.0 })
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 20 })))
    .animation({ duration: 300, curve: Curve.EaseOut, delay: index * 60 })
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

  // ===== 单选弹窗（CustomDialog，本 SDK AlertDialog 不支持自定义 builder）=====
  @Builder
  pickerDialogBuilder() {
    PickerDialog({
      controller: this.pickerController,
      title: this.pickerTitle(),
      options: this.currentPickerOptions(),
      currentValue: this.currentPickerValue(),
      onSelect: (v: string) => {
        this.applyPicker(v);
        this.pickerController.close();
      }
    })
  }

  build() {
    NavDestination() {
      Column() {
        // Header
        Row() {
          Image($r('app.media.ic_hm_back'))
            .width(24)
            .height(24)
            .fillColor(ThemeManager.getColors().primaryText)
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

          Text('设置')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeManager.getColors().primaryText)
            .margin({ left: 12 })
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: this.topHeight + 12, bottom: 16 })

        Scroll() {
          Column() {
            // ===== 播放 =====
            Text('播放')
              .fontSize(13)
              .fontColor(ThemeManager.getColors().secondaryText)
              .width('100%')
              .padding({ left: 4, bottom: 10 })

            Column() {
              this.buildToggleItem(
                $r('app.media.ic_auto'),
                '自动下一首',
                '',
                0,
                '#34C759',
                this.autoNext,
                (isOn: boolean) => {
                  this.autoNext = isOn;
                  this.settings.setAutoNext(isOn);
                }
              )
              this.buildSettingItem(
                $r('app.media.ic_repeat'),
                '播放模式',
                this.repeatModeLabel(),
                1,
                '#FF9500',
                () => { this.currentPicker = 'repeat'; this.openPicker(); }
              )
              this.buildToggleItem(
                $r('app.media.ic_download'),
                '允许蜂窝网络播放',
                '',
                2,
                '#5856D6',
                this.allowMobileNetwork,
                (isOn: boolean) => {
                  this.allowMobileNetwork = isOn;
                  this.settings.setAllowMobileNetwork(isOn);
                }
              )
              this.buildSettingItem(
                $r('app.media.ic_music'),
                '默认音质',
                this.qualityLabel(),
                3,
                '#FF2D55',
                () => { this.currentPicker = 'quality'; this.openPicker(); }
              )
            }
            .margin({ bottom: 8 })

            // ===== 外观 =====
            Text('外观')
              .fontSize(13)
              .fontColor(ThemeManager.getColors().secondaryText)
              .width('100%')
              .padding({ left: 4, top: 16, bottom: 10 })

            Column() {
              this.buildSettingItem(
                $r('app.media.ic_hm_moon'),
                '深色模式',
                this.themeModeLabel(),
                4,
                '#5E5CE6',
                () => { this.currentPicker = 'theme'; this.openPicker(); }
              )
            }
            .margin({ bottom: 8 })

            // ===== 存储 =====
            Text('存储')
              .fontSize(13)
              .fontColor(ThemeManager.getColors().secondaryText)
              .width('100%')
              .padding({ left: 4, top: 16, bottom: 10 })

            Column() {
              this.buildSettingItem(
                $r('app.media.ic_hm_trash'),
                '清除缓存',
                this.cacheSizeText,
                5,
                '#FF9500',
                () => { this.showClearCacheDialog(); }
              )
              this.buildSettingItem(
                $r('app.media.ic_hm_list'),
                '清空播放历史',
                `共 ${this.store.recentlyPlayed.length} 首`,
                6,
                '#FF9500',
                () => {
                  this.store.clearRecentlyPlayed();
                  this.toast('已清空播放历史');
                }
              )
              this.buildSettingItem(
                $r('app.media.ic_hm_folder'),
                '本地歌曲管理',
                '',
                7,
                '#FA2759',
                () => {
                  this.pathStack.pushPathByName('ManageSongs', null);
                }
              )
            }
            .margin({ bottom: 8 })

            // ===== 通知 =====
            Text('通知')
              .fontSize(13)
              .fontColor(ThemeManager.getColors().secondaryText)
              .width('100%')
              .padding({ left: 4, top: 16, bottom: 10 })

            Column() {
              this.buildToggleItem(
                $r('app.media.ic_bells_o'),
                '锁屏/状态栏控制',
                '',
                8,
                '#FFCC00',
                this.notificationLockScreen,
                (isOn: boolean) => {
                  this.notificationLockScreen = isOn;
                  this.settings.setNotificationLockScreen(isOn);
                }
              )
            }
            .margin({ bottom: 8 })

            // ===== 隐私 =====
            Text('隐私')
              .fontSize(13)
              .fontColor(ThemeManager.getColors().secondaryText)
              .width('100%')
              .padding({ left: 4, top: 16, bottom: 10 })

            Column() {
              this.buildToggleItem(
                $r('app.media.ic_favorite'),
                '启用听歌统计',
                '',
                9,
                '#FA2759',
                this.privacyStats,
                (isOn: boolean) => {
                  this.privacyStats = isOn;
                  this.settings.setPrivacyStats(isOn);
                }
              )
              this.buildSettingItem(
                $r('app.media.ic_hm_trash'),
                '清除统计数据',
                '',
                10,
                '#FF9500',
                () => { this.showClearStatsDialog(); }
              )
            }
            .margin({ bottom: 8 })

            // ===== 关于 =====
            Text('关于')
              .fontSize(13)
              .fontColor(ThemeManager.getColors().secondaryText)
              .width('100%')
              .padding({ left: 4, top: 16, bottom: 10 })

            Column() {
              this.buildSettingItem(
                $r('app.media.ic_hm_settings'),
                '版本信息',
                this.appVersionDisplay,
                11,
                '#5856D6',
                () => {
                  this.pathStack.pushPathByName('About', null);
                }
              )
              this.buildSettingItem(
                $r('app.media.ic_hm_profile'),
                '开发者',
                '何宇翔',
                12,
                '#34C759',
                () => {
                  this.openDeveloper();
                }
              )
              this.buildSettingItem(
                $r('app.media.ic_review'),
                '隐私政策',
                '',
                13,
                '#007AFF',
                () => {
                  this.openPrivacyPolicy();
                }
              )
            }
            .margin({ bottom: 8 })

            Text('Made with HarmonyOS SDK')
              .fontSize(12)
              .fontColor(ThemeManager.getColors().secondaryText)
              .margin({ top: 24, bottom: 20 })
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 40 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ThemeManager.getColors().bg)
    }
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
    .hideTitleBar(true)
  }

  private showClearCacheDialog(): void {
    this.getUIContext().showAlertDialog({
      title: '清除缓存',
      message: `确定清除 ${this.cacheSizeText} 的缓存文件？`,
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '清除',
        action: () => {
          this.clearCache().then(() => {
            this.toast('已清除缓存');
          });
        }
      }
    });
  }

  private showClearStatsDialog(): void {
    this.getUIContext().showAlertDialog({
      title: '清除统计数据',
      message: '将清空播放历史等统计数据，且不可恢复。是否继续？',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '清除',
        action: () => {
          this.store.clearRecentlyPlayed();
          this.toast('已清除统计数据');
        }
      }
    });
  }

  private openPicker(): void {
    this.pickerController.open();
  }
}

@CustomDialog
struct PickerDialog {
  controller: CustomDialogController;
  title: string = '';
  options: PickerOption[] = [];
  currentValue: string = '';
  onSelect: (value: string) => void = () => {};

  build() {
    Column() {
      Text(this.title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeManager.getColors().primaryText)
        .margin({ top: 20, bottom: 12 })
      ForEach(this.options, (opt: PickerOption) => {
        Row() {
          Text(opt.label)
            .fontSize(16)
            .fontColor(ThemeManager.getColors().primaryText)
            .layoutWeight(1)
          Radio({ value: opt.value, group: 'picker_radio' })
            .checked(this.currentValue === opt.value)
            .onChange(() => {
              this.onSelect(opt.value);
            })
        }
        .width('100%')
        .height(48)
        .padding({ left: 24, right: 24 })
        .onClick(() => {
          this.onSelect(opt.value);
        })
      }, (opt: PickerOption): string => opt.value)
      Button('完成')
        .width('90%')
        .margin({ top: 16, bottom: 20 })
        .backgroundColor(ThemeManager.getColors().accent)
        .fontColor(Color.White)
        .onClick(() => {
          this.controller.close();
        })
    }
    .width('100%')
    .backgroundColor(ThemeManager.getColors().cardBg)
    .borderRadius(16)
  }
}
