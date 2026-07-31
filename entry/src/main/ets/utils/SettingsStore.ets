import { Logger } from './Logger';
import { preferences } from '@kit.ArkData';
import { MusicStore } from '../services/MusicStore';
import { AVSessionController } from './AVSessionController';

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

const PREF_NAME: string = 'app_settings';
const KEY_AUTO_NEXT: string = 'auto_next';
const KEY_REPEAT_MODE: string = 'repeat_mode';
const KEY_THEME_MODE: string = 'theme_mode';
const KEY_NOTIFICATION_LOCK: string = 'notification_lock_screen';
const KEY_PRIVACY_STATS: string = 'privacy_stats';

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
