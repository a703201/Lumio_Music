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

import { i18n } from '@kit.LocalizationKit';
import { Logger } from './Logger';
import { SettingsStore, AppLanguage } from './SettingsStore';

/**
 * 应用内偏好语言管理器。
 * - 通过 i18n.System.setAppPreferredLanguage 切换资源上下文（API 17+/HarmonyOS 5+，本应用最低 API 26）。
 * - 切换后 $r('app.string.xxx') 会以新语言解析；并写入 AppStorage('appLocale')，
 *   根组件 Layout 以 .key(appLocale) 强制整棵内容子树重建，确保所有已挂载页面即时刷新。
 * - 偏好持久化于 SettingsStore（preferences 'app_settings'），冷启动经 EntryAbility 重新应用。
 */
export class LocaleManager {
  private static instance: LocaleManager | null = null;
  private current: AppLanguage = 'zh-Hans';

  static getInstance(): LocaleManager {
    if (!LocaleManager.instance) {
      LocaleManager.instance = new LocaleManager();
    }
    return LocaleManager.instance;
  }

  /** 应用启动时调用（需在窗口内容加载前）：读取已保存偏好并应用到资源上下文。 */
  init(): void {
    const saved: AppLanguage = SettingsStore.getInstance().getLanguage();
    this.apply(saved);
  }

  getCurrent(): AppLanguage {
    return this.current;
  }

  private apply(code: AppLanguage): void {
    try {
      i18n.System.setAppPreferredLanguage(code);
      this.current = code;
      // 触发全树重渲染：根组件（Layout）读取该 StorageProp 并以 .key() 重建子树。
      AppStorage.setOrCreate('appLocale', code);
    } catch (e) {
      Logger.error('LocaleManager apply failed: ' + (e as Error).message);
    }
  }

  /** 用户切换语言：持久化 + 应用偏好 + 触发重渲染。 */
  setLanguage(code: AppLanguage): void {
    SettingsStore.getInstance().setLanguage(code);
    this.apply(code);
  }
}
