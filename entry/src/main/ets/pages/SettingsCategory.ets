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

import { Logger } from '../utils/Logger';
import { common, Want } from '@kit.AbilityKit';
import { getAppVersionDisplay } from '../utils/AppInfoUtil';
import { MusicStore } from '../services/MusicStore';
import { SettingsStore, ThemeMode, RepeatModeSetting, AudioFadeLevel, AppLanguage } from '../utils/SettingsStore';
import { LocaleManager } from '../utils/LocaleManager';
import { ThemeManager, ColorTokens } from '../utils/ThemeManager';
import { fileIo as fs } from '@kit.CoreFileKit';
import { TYPE_SM, SPACE_SM } from '../tokens/LumioScale';

interface SettingsCategoryParam {
  category: string;
}

interface CategorySelectOption {
  value: ResourceStr;
}

@Builder
export function SettingsCategoryBuilder() {
  NavDestination() {
    SettingsCategoryRoute()
  }
  .hideTitleBar(true)
}

/** 路由包装：从 path param 读取分类并渲染详情（保留 SettingsCategory 路由兼容）。 */
@Component
struct SettingsCategoryRoute {
  pathStack: NavPathStack = new NavPathStack();
  @State category: string = '';

  build() {
    NavDestination() {
      SettingsCategoryDetail({
        category: this.category,
        onNavigate: (name: string) => {
          this.pathStack.pushPathByName(name, null);
        }
      })
    }
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const param: Object = context.pathInfo.param as Object;
      if (param !== undefined && param !== null && typeof param === 'object') {
        const cat: string = (param as SettingsCategoryParam).category;
        if (cat !== undefined && cat !== null && cat.length > 0) {
          this.category = cat;
        }
      }
    })
    .hideTitleBar(true)
  }
}

@Component
export struct SettingsCategoryDetail {
  store: MusicStore = MusicStore.getInstance();
  settings: SettingsStore = SettingsStore.getInstance();
  @StorageProp('topHeight') topHeight: number = 0;
  @StorageProp('isDark') isDark: boolean = false;

  /** 由上层（Settings / 路由包装）传入的分类 id。 */
  @Prop category: string = '';
  /** 返回上一级（sheet 内二级导航）。 */
  onBack: () => void = () => {};
  /** 跳转更深页（ManageSongs / PrivacyPolicy）：交由上层决定（sheet 内关闭 sheet + 主导航栈）。 */
  onNavigate: (name: string) => void = () => {};

  @State autoNext: boolean = true;
  @State repeatMode: RepeatModeSetting = 'list';
  @State themeMode: ThemeMode = 'system';
  @State notificationLockScreen: boolean = true;
  @State privacyStats: boolean = true;
  @State reduceMotion: boolean = false;
  @State gapless: boolean = true;
  @State audioFade: AudioFadeLevel = 'short';
  @State appLanguage: AppLanguage = 'zh-Hans';
  @State cacheSizeText: string = '';
  @State appVersionDisplay: string = 'Lumio Music';

  private getThemeColors(): ColorTokens {
    // 跟随应用浅色/深色主题（sheet 内页面与全局一致，不强制灰底白字）
    return this.isDark ? ThemeManager.darkColors : ThemeManager.lightColors;
  }

  aboutToAppear(): void {
    this.appVersionDisplay = getAppVersionDisplay();
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
    this.themeMode = this.settings.getThemeMode();
    this.notificationLockScreen = this.settings.getNotificationLockScreen();
    this.privacyStats = this.settings.getPrivacyStats();
    this.reduceMotion = this.settings.getReduceMotion();
    this.gapless = this.settings.getGapless();
    this.audioFade = this.settings.getAudioFade();
    this.appLanguage = this.settings.getLanguage();
  }

  private toast(message: ResourceStr): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (e) {
      Logger.error('toast failed');
    }
  }

  // ===== Select 选项 =====
  private repeatOptions(): CategorySelectOption[] {
    return [
      { value: $r('app.string.repeat_list') },
      { value: $r('app.string.repeat_one') },
      { value: $r('app.string.shuffle') }
    ];
  }

  private repeatIndex(): number {
    const order: RepeatModeSetting[] = ['list', 'single', 'random'];
    return order.indexOf(this.repeatMode);
  }

  private themeOptions(): CategorySelectOption[] {
    return [
      { value: $r('app.string.theme_system') },
      { value: $r('app.string.theme_light') },
      { value: $r('app.string.theme_dark') }
    ];
  }

  private themeIndex(): number {
    const order: ThemeMode[] = ['system', 'light', 'dark'];
    return order.indexOf(this.themeMode);
  }

  private audioOptions(): CategorySelectOption[] {
    return [
      { value: $r('app.string.off') },
      { value: $r('app.string.short') },
      { value: $r('app.string.medium') }
    ];
  }

  private audioIndex(): number {
    const order: AudioFadeLevel[] = ['off', 'short', 'medium'];
    return order.indexOf(this.audioFade);
  }

  private localized(res: Resource): string {
    const ctx: Context | undefined = this.getUIContext().getHostContext();
    if (!ctx) {
      return '';
    }
    try {
      return ctx.resourceManager.getStringSync(res.id);
    } catch (e) {
      return '';
    }
  }

  private languageOptions(): CategorySelectOption[] {
    const ctx: Context | undefined = this.getUIContext().getHostContext();
    if (!ctx) {
      return [{ value: $r('app.string.lang_zh') }, { value: $r('app.string.lang_en') }, { value: $r('app.string.lang_fr') }];
    }
    try {
      const rm = ctx.resourceManager;
      return [
        { value: rm.getStringSync($r('app.string.lang_zh').id) },
        { value: rm.getStringSync($r('app.string.lang_en').id) },
        { value: rm.getStringSync($r('app.string.lang_fr').id) }
      ];
    } catch (e) {
      return [{ value: $r('app.string.lang_zh') }, { value: $r('app.string.lang_en') }, { value: $r('app.string.lang_fr') }];
    }
  }

  private languageIndex(): number {
    const order: AppLanguage[] = ['zh-Hans', 'en-Latn-US', 'fr-Latn-FR'];
    return order.indexOf(this.appLanguage);
  }

  // ===== 外跳网页 =====
  private openUrl(url: string): void {
    try {
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: url
      };
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      context.startAbility(want).catch((err: Error) => {
        Logger.error('Failed to open url: ' + (err as Error).message);
        this.toast($r('app.string.cannot_open_web'));
      });
    } catch (err) {
      Logger.error('Failed to open url: ' + (err as Error).message);
      this.toast($r('app.string.cannot_open_web'));
    }
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
      return '';
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

  // ===== 通用卡片 @Builder =====
  @Builder
  buildSectionLabel(text: ResourceStr) {
    Text(text)
      .fontSize(TYPE_SM.footnote.size)
      .fontColor(this.getThemeColors().secondaryText)
      .width('100%')
      .padding({ left: SPACE_SM.tight, top: SPACE_SM.base, bottom: SPACE_SM.cozy })
  }

  @Builder
  buildToggleItem(icon: ResourceStr, title: ResourceStr, subtitle: ResourceStr, index: number,
    iconColor: string, isOn: boolean, onToggle: (v: boolean) => void) {
    Row() {
      Image(icon)
        .width(24)
        .height(24)
        .fillColor(iconColor)
        .margin({ right: SPACE_SM.base })

      Column() {
        Text(title)
          .fontSize(TYPE_SM.headline.size)
          .fontColor(this.getThemeColors().primaryText)
          .fontWeight(FontWeight.Medium)
          .margin({ bottom: subtitle ? 4 : 0 })
        if (subtitle) {
          Text(subtitle)
            .fontSize(TYPE_SM.footnote.size)
            .fontColor(this.getThemeColors().secondaryText)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .selectedColor(this.getThemeColors().accent)
        .onChange((value: boolean) => {
          onToggle(value);
        })
    }
    .width('100%')
    .height(60)
    .padding({ left: SPACE_SM.base, right: SPACE_SM.base })
    .backgroundColor(this.getThemeColors().cardBg)
    .borderRadius(16)
    .margin({ bottom: SPACE_SM.hair })
  }

  @Builder
  buildSelectItem(icon: ResourceStr, title: ResourceStr, options: CategorySelectOption[], selectedIndex: number,
    index: number, iconColor: string, onSelect: (i: number) => void) {
    Row() {
      Image(icon)
        .width(24)
        .height(24)
        .fillColor(iconColor)
        .margin({ right: SPACE_SM.base })

      Column() {
        Text(title)
          .fontSize(TYPE_SM.headline.size)
          .fontColor(this.getThemeColors().primaryText)
          .fontWeight(FontWeight.Medium)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Select(options)
        .selected(selectedIndex)
        .value(options[selectedIndex]?.value ?? '')
        .optionFont({ size: 14, weight: FontWeight.Normal })
        .selectedOptionFont({ size: 14, weight: FontWeight.Medium })
        // 主题适配：浅色模式灰底白底/深色模式深底浅字；避免默认值在深色模式下文字不可见。
        .fontColor(this.getThemeColors().primaryText)
        .selectedOptionFontColor(this.getThemeColors().primaryText)
        .optionFontColor(this.getThemeColors().primaryText)
        .selectedOptionBgColor(this.getThemeColors().secondaryBg)
        .optionBgColor(this.getThemeColors().cardBg)
        .onSelect((i: number, text: string) => {
          onSelect(i);
        })
        .width(140)
    }
    .width('100%')
    .height(60)
    .padding({ left: SPACE_SM.base, right: SPACE_SM.base })
    .backgroundColor(this.getThemeColors().cardBg)
    .borderRadius(16)
    .margin({ bottom: SPACE_SM.hair })
  }

  @Builder
  buildNavItem(icon: ResourceStr, title: ResourceStr, subtitle: ResourceStr, index: number,
    iconColor: string, onClick: () => void) {
    Row() {
      Image(icon)
        .width(24)
        .height(24)
        .fillColor(iconColor)
        .margin({ right: SPACE_SM.base })

      Column() {
        Text(title)
          .fontSize(TYPE_SM.headline.size)
          .fontColor(this.getThemeColors().primaryText)
          .fontWeight(FontWeight.Medium)
          .margin({ bottom: subtitle ? 4 : 0 })
        if (subtitle) {
          Text(subtitle)
            .fontSize(TYPE_SM.footnote.size)
            .fontColor(this.getThemeColors().secondaryText)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Image($r('app.media.ic_public_more'))
        .width(16)
        .fillColor(this.getThemeColors().separator)
    }
    .width('100%')
    .height(60)
    .padding({ left: SPACE_SM.base, right: SPACE_SM.base })
    .backgroundColor(this.getThemeColors().cardBg)
    .borderRadius(16)
    .margin({ bottom: SPACE_SM.hair })
    .onClick(() => {
      onClick();
    }).clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
  }

  // ===== 各分类内容 =====
  @Builder
  buildPlaybackGroup() {
    this.buildSectionLabel($r('app.string.play'))
    Column() {
      this.buildToggleItem(
        $r('app.media.ic_public_quickstart'), $r('app.string.auto_next'), '', 0, this.getThemeColors().secondaryText, this.autoNext,
        (v: boolean) => { this.autoNext = v; this.settings.setAutoNext(v); }
      )
      this.buildSelectItem(
        $r('app.media.ic_public_list_cycle'), $r('app.string.play_mode'), this.repeatOptions(), this.repeatIndex(), 1, this.getThemeColors().secondaryText,
        (i: number) => {
          const order: RepeatModeSetting[] = ['list', 'single', 'random'];
          this.repeatMode = order[i];
          this.settings.setRepeatMode(order[i]);
        }
      )
      this.buildToggleItem(
        $r('app.media.ic_public_order_play'), $r('app.string.gapless'), $r('app.string.gapless_desc'), 2, this.getThemeColors().secondaryText, this.gapless,
        (v: boolean) => { this.gapless = v; this.settings.setGapless(v); }
      )
    }
    .margin({ bottom: SPACE_SM.compact })
  }

  @Builder
  buildAudioGroup() {
    this.buildSectionLabel($r('app.string.sound_effects'))
    Column() {
      this.buildSelectItem(
        $r('app.media.ic_public_sound'), $r('app.string.crossfade'), this.audioOptions(), this.audioIndex(), 0, this.getThemeColors().secondaryText,
        (i: number) => {
          const order: AudioFadeLevel[] = ['off', 'short', 'medium'];
          this.audioFade = order[i];
          this.settings.setAudioFade(order[i]);
        }
      )
      Text($r('app.string.fade_desc'))
        .fontSize(TYPE_SM.footnote.size)
        .fontColor(this.getThemeColors().secondaryText)
        .width('100%')
        .padding({ left: SPACE_SM.base, right: SPACE_SM.base, top: SPACE_SM.cozy })
    }
    .margin({ bottom: SPACE_SM.compact })
  }

  @Builder
  buildAppearanceGroup() {
    this.buildSectionLabel($r('app.string.ui'))
    Column() {
      this.buildSelectItem(
        $r('app.media.ic_public_themes'), $r('app.string.dark_mode'), this.themeOptions(), this.themeIndex(), 0, this.getThemeColors().secondaryText,
        (i: number) => {
          const order: ThemeMode[] = ['system', 'light', 'dark'];
          this.themeMode = order[i];
          ThemeManager.setThemeMode(order[i]);
        }
      )
      this.buildSelectItem(
        $r('app.media.ic_public_translate_c2e'), this.localized($r('app.string.language')), this.languageOptions(), this.languageIndex(), 1, this.getThemeColors().secondaryText,
        (i: number) => {
          const order: AppLanguage[] = ['zh-Hans', 'en-Latn-US', 'fr-Latn-FR'];
          this.appLanguage = order[i];
          LocaleManager.getInstance().setLanguage(order[i]);
        }
      )
    }
    .margin({ bottom: SPACE_SM.compact })
  }

  @Builder
  buildAccessibilityGroup() {
    this.buildSectionLabel($r('app.string.accessibility'))
    Column() {
      this.buildToggleItem(
        $r('app.media.ic_public_face'), $r('app.string.reduce_motion'), $r('app.string.reduce_motion_desc'), 0, this.getThemeColors().secondaryText, this.reduceMotion,
        (v: boolean) => { this.reduceMotion = v; this.settings.setReduceMotion(v); }
      )
    }
    .margin({ bottom: SPACE_SM.compact })
  }

  @Builder
  buildStorageGroup() {
    this.buildSectionLabel($r('app.string.storage'))
    Column() {
      this.buildNavItem(
        $r('app.media.ic_public_delete'), $r('app.string.clear_cache'), this.cacheSizeText, 0, this.getThemeColors().secondaryText,
        () => { this.showClearCacheDialog(); }
      )
      this.buildNavItem(
        $r('app.media.ic_public_view_list'), $r('app.string.clear_history'), `共 ${this.store.recentlyPlayed.length} 首`, 1, this.getThemeColors().secondaryText,
        () => {
          this.store.clearRecentlyPlayed();
          this.toast($r('app.string.history_cleared'));
        }
      )
      this.buildNavItem(
        $r('app.media.ic_public_folder'), $r('app.string.local_songs_mgmt'), '', 2, this.getThemeColors().secondaryText,
        () => { this.onNavigate('ManageSongs'); }
      )
      this.buildNavItem(
        $r('app.media.ic_public_view_list'), $r('app.string.dup_cleanup'), '', 3, this.getThemeColors().secondaryText,
        () => { this.onNavigate('DuplicateSongs'); }
      )
    }
    .margin({ bottom: SPACE_SM.compact })
  }

  @Builder
  buildNotificationGroup() {
    this.buildSectionLabel($r('app.string.notifications'))
    Column() {
      this.buildToggleItem(
        $r('app.media.ic_public_donotdisturb'), $r('app.string.lockscreen_control'), '', 0, this.getThemeColors().secondaryText, this.notificationLockScreen,
        (v: boolean) => { this.notificationLockScreen = v; this.settings.setNotificationLockScreen(v); }
      )
    }
    .margin({ bottom: SPACE_SM.compact })
  }

  @Builder
  buildPrivacyGroup() {
    this.buildSectionLabel($r('app.string.privacy'))
    Column() {
      this.buildToggleItem(
        $r('app.media.ic_public_favor_filled'), $r('app.string.enable_stats'), '', 0, this.getThemeColors().secondaryText, this.privacyStats,
        (v: boolean) => { this.privacyStats = v; this.settings.setPrivacyStats(v); }
      )
      this.buildNavItem(
        $r('app.media.ic_public_music_public_filled'), $r('app.string.listen_report'), '', 1, this.getThemeColors().secondaryText,
        () => { this.onNavigate('Wrapped'); }
      )
      this.buildNavItem(
        $r('app.media.ic_public_delete'), $r('app.string.clear_stats'), '', 2, this.getThemeColors().secondaryText,
        () => { this.showClearStatsDialog(); }
      )
    }
    .margin({ bottom: SPACE_SM.compact })
  }

  build() {
    Scroll() {
      Column() {
        if (this.category === 'playback') {
          this.buildPlaybackGroup();
        } else if (this.category === 'audio') {
          this.buildAudioGroup();
        } else if (this.category === 'appearance') {
          this.buildAppearanceGroup();
        } else if (this.category === 'accessibility') {
          this.buildAccessibilityGroup();
        } else if (this.category === 'storage') {
          this.buildStorageGroup();
        } else if (this.category === 'notification') {
          this.buildNotificationGroup();
      } else if (this.category === 'privacy') {
        this.buildPrivacyGroup();
      } else {
          Text($r('app.string.select_category'))
            .fontSize(TYPE_SM.subhead.size)
            .fontColor(this.getThemeColors().secondaryText)
            .width('100%')
            .padding({ left: SPACE_SM.tight, top: SPACE_SM.base })
        }
      }
      .width('100%')
      .padding({ left: SPACE_SM.base, right: SPACE_SM.base, bottom: SPACE_SM.block })
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  private showClearCacheDialog(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.clear_cache'),
      message: `确定清除 ${this.cacheSizeText} 的缓存文件？`,
      primaryButton: { value: $r('app.string.cancel'), action: () => {} },
      secondaryButton: {
        value: $r('app.string.clear'),
        action: () => {
          this.clearCache().then(() => {
            this.toast($r('app.string.cache_cleared'));
          });
        }
      }
    });
  }

  private showClearStatsDialog(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.clear_stats'),
      message: $r('app.string.clear_stats_confirm'),
      primaryButton: { value: $r('app.string.cancel'), action: () => {} },
      secondaryButton: {
        value: $r('app.string.clear'),
        action: () => {
          this.store.clearRecentlyPlayed();
          this.toast($r('app.string.stats_cleared'));
        }
      }
    });
  }
}
