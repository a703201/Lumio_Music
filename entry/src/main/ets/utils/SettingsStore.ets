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

import { Logger } from './Logger';
import { preferences } from '@kit.ArkData';
import { MusicStore } from '../services/MusicStore';
import { AVSessionController } from './AVSessionController';
import { AudioRendererController } from './AudioRendererController';
import { LumioAudioFade } from '../tokens/LumioMotionSpec';

/**
 * 设置项持久化单例。
 * 使用 @kit.ArkData 的 preferences，独立 PREF_NAME 'app_settings'，
 * 不干扰 MusicStore 的 'music_store'。
 *
 * 主题与换肤由 ThemeManager 负责，本 Store 仅持久化 themeMode 等边际偏好，
 * 并在变更时联动 MusicStore（播放模式）与 AVSession（锁屏媒体控制）。
 */

export type ThemeMode = 'system' | 'light' | 'dark';
export type RepeatModeSetting = 'list' | 'single' | 'random';
/** 音效-淡入淡出档位。off = 不做音量渐变。 */
export type AudioFadeLevel = 'off' | 'short' | 'medium';
/** 应用内偏好语言（映射到资源目录 base/en_US/fr_FR）。zh-Hans 回落 base（中文）。 */
export type AppLanguage = 'zh-Hans' | 'en-Latn-US' | 'fr-Latn-FR';
export const DEFAULT_LANGUAGE: AppLanguage = 'zh-Hans';

const PREF_NAME: string = 'app_settings';
const KEY_AUTO_NEXT: string = 'auto_next';
const KEY_REPEAT_MODE: string = 'repeat_mode';
const KEY_THEME_MODE: string = 'theme_mode';
const KEY_NOTIFICATION_LOCK: string = 'notification_lock_screen';
const KEY_PRIVACY_STATS: string = 'privacy_stats';
const KEY_REDUCE_MOTION: string = 'reduce_motion';
const KEY_SLEEP_TIMER: string = 'sleep_timer';
const KEY_GAPLESS: string = 'gapless';
const KEY_AUDIO_FADE: string = 'audio_fade';
const KEY_LANGUAGE: string = 'language';

export class SettingsStore {
  private static instance: SettingsStore | null = null;
  private pref: preferences.Preferences | null = null;
  private initialized: boolean = false;

  // 默认值
  private autoNext: boolean = true;
  private repeatMode: RepeatModeSetting = 'list';
  private themeMode: ThemeMode = 'system';
  private notificationLockScreen: boolean = true;
  private privacyStats: boolean = true;
  private reduceMotion: boolean = false;
  private sleepTimerMinutes: number = 0;
  private gapless: boolean = true;
  private audioFade: AudioFadeLevel = 'short';
  private language: AppLanguage = DEFAULT_LANGUAGE;

  private constructor() {
  }

  static getInstance(): SettingsStore {
    if (!SettingsStore.instance) {
      SettingsStore.instance = new SettingsStore();
    }
    return SettingsStore.instance;
  }

  /**
   * 幂等初始化：若已被 EntryAbility 初始化过则直接返回。
   * 也可在页面 aboutToAppear 中用宿主 context 注入后再读取。
   */
  async ensureInitialized(context: Context): Promise<void> {
    if (this.initialized) {
      return;
    }
    await this.init(context);
  }

  async init(context: Context): Promise<void> {
    try {
      this.pref = await preferences.getPreferences(context, PREF_NAME);
      this.autoNext = await this.pref.get(KEY_AUTO_NEXT, true) as boolean;

      const rm: string = await this.pref.get(KEY_REPEAT_MODE, 'list') as string;
      this.repeatMode = (rm === 'single' || rm === 'random' || rm === 'list') ? rm as RepeatModeSetting : 'list';

      const tm: string = await this.pref.get(KEY_THEME_MODE, 'system') as string;
      this.themeMode = (tm === 'light' || tm === 'dark' || tm === 'system') ? tm as ThemeMode : 'system';

      this.notificationLockScreen = await this.pref.get(KEY_NOTIFICATION_LOCK, true) as boolean;
      this.privacyStats = await this.pref.get(KEY_PRIVACY_STATS, true) as boolean;
      this.reduceMotion = await this.pref.get(KEY_REDUCE_MOTION, false) as boolean;
      this.sleepTimerMinutes = await this.pref.get(KEY_SLEEP_TIMER, 0) as number;
      this.gapless = await this.pref.get(KEY_GAPLESS, true) as boolean;

      const af: string = await this.pref.get(KEY_AUDIO_FADE, 'short') as string;
      this.audioFade = (af === 'off' || af === 'short' || af === 'medium') ? af as AudioFadeLevel : 'short';

      const lang: string = await this.pref.get(KEY_LANGUAGE, DEFAULT_LANGUAGE) as string;
      this.language = (lang === 'zh-Hans' || lang === 'en-Latn-US' || lang === 'fr-Latn-FR') ? lang as AppLanguage : DEFAULT_LANGUAGE;

      this.initialized = true;
    } catch (err) {
      Logger.error('SettingsStore init failed');
    }
  }

  // ===== 自动下一首 =====
  getAutoNext(): boolean {
    return this.autoNext;
  }

  async setAutoNext(value: boolean): Promise<void> {
    this.autoNext = value;
    await this.putBoolean(KEY_AUTO_NEXT, value);
  }

  // ===== 播放模式（联动 MusicStore）=====
  getRepeatMode(): RepeatModeSetting {
    return this.repeatMode;
  }

  async setRepeatMode(value: RepeatModeSetting): Promise<void> {
    this.repeatMode = value;
    await this.putString(KEY_REPEAT_MODE, value);
    // 同步到 MusicStore 的播放模式
    MusicStore.getInstance().setRepeatMode(value);
  }

  // ===== 深色模式 =====
  getThemeMode(): ThemeMode {
    return this.themeMode;
  }

  async setThemeMode(value: ThemeMode): Promise<void> {
    this.themeMode = value;
    await this.putString(KEY_THEME_MODE, value);
  }

  // ===== 锁屏/状态栏控制（联动 AVSession）=====
  getNotificationLockScreen(): boolean {
    return this.notificationLockScreen;
  }

  async setNotificationLockScreen(value: boolean): Promise<void> {
    this.notificationLockScreen = value;
    await this.putBoolean(KEY_NOTIFICATION_LOCK, value);
    // 联动 AVSession：开启则在锁屏/通知中心展示媒体控制卡片，关闭则隐藏
    try {
      AVSessionController.getInstance().setLockScreenControl(value);
    } catch (e) {
      Logger.error('link AVSession lock screen failed');
    }
  }

  // ===== 启用听歌统计 =====
  getPrivacyStats(): boolean {
    return this.privacyStats;
  }

  async setPrivacyStats(value: boolean): Promise<void> {
    this.privacyStats = value;
    await this.putBoolean(KEY_PRIVACY_STATS, value);
  }

  // ===== 无障碍：降低动态效果 =====
  getReduceMotion(): boolean {
    return this.reduceMotion;
  }

  async setReduceMotion(value: boolean): Promise<void> {
    this.reduceMotion = value;
    await this.putBoolean(KEY_REDUCE_MOTION, value);
  }

  // ===== 睡眠定时（分钟，0 = 关闭）=====
  getSleepTimer(): number {
    return this.sleepTimerMinutes;
  }

  async setSleepTimer(minutes: number): Promise<void> {
    this.sleepTimerMinutes = minutes;
    await this.putNumber(KEY_SLEEP_TIMER, minutes);
  }

  // ===== 无缝播放（Gapless）/ 交叉淡变 =====
  getGapless(): boolean {
    return this.gapless;
  }

  async setGapless(value: boolean): Promise<void> {
    this.gapless = value;
    await this.putBoolean(KEY_GAPLESS, value);
    // 实时联动播放内核：关闭时清理预加载缓冲
    try {
      AudioRendererController.getInstance().onGaplessSettingChanged();
    } catch (e) {
      Logger.error('link gapless failed');
    }
  }

  // ===== 音效：淡入淡出 =====
  getAudioFade(): AudioFadeLevel {
    return this.audioFade;
  }

  /**
   * 档位 → 淡变时长(ms)，0 表示不做渐变。
   * 纯映射函数：播放内核在**每次**渐变启动时调用它读取，因此设置页改动无需额外通知即即时生效
   * （这也是这里没有像 setGapless 那样回调播放内核的原因——没有需要预计算或清理的状态）。
   */
  static audioFadeMs(level: AudioFadeLevel): number {
    if (level === 'off') {
      return LumioAudioFade.off;
    }
    if (level === 'medium') {
      return LumioAudioFade.medium;
    }
    return LumioAudioFade.short;
  }

  async setAudioFade(value: AudioFadeLevel): Promise<void> {
    this.audioFade = value;
    await this.putString(KEY_AUDIO_FADE, value);
  }

  // ===== 应用内偏好语言（独立于系统语言，运行时切换）=====
  getLanguage(): AppLanguage {
    return this.language;
  }

  async setLanguage(value: AppLanguage): Promise<void> {
    this.language = value;
    await this.putString(KEY_LANGUAGE, value);
  }

  private async putNumber(key: string, value: number): Promise<void> {
    if (!this.pref) {
      return;
    }
    try {
      await this.pref.put(key, value);
      await this.pref.flush();
    } catch (err) {
      Logger.error('SettingsStore put failed: ' + key);
    }
  }

  private async putBoolean(key: string, value: boolean): Promise<void> {
    if (!this.pref) {
      return;
    }
    try {
      await this.pref.put(key, value);
      await this.pref.flush();
    } catch (err) {
      Logger.error('SettingsStore put failed: ' + key);
    }
  }

  private async putString(key: string, value: string): Promise<void> {
    if (!this.pref) {
      return;
    }
    try {
      await this.pref.put(key, value);
      await this.pref.flush();
    } catch (err) {
      Logger.error('SettingsStore put failed: ' + key);
    }
  }
}
