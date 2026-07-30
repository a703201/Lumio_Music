/*
 * Copyright (c) 2024 Huawei Device Co., Ltd.
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

import { UIAbility, Configuration, ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { display, window } from '@kit.ArkUI';
import { BreakpointConstants } from '../common/constants/BreakpointConstants';
import { MusicStore } from '../services/MusicStore';
import { SettingsStore } from '../utils/SettingsStore';
import { ThemeManager } from '../utils/ThemeManager';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private windowObj?: window.Window;

  onCreate() {
    AppStorage.setOrCreate('context', this.context);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy() {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    await this.initStore();
    // 初始化设置项偏好与主题管理器（需在窗口就绪前完成，供页面与系统栏取色）
    await SettingsStore.getInstance().ensureInitialized(this.context);
    ThemeManager.init();

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err) ?? '');
        return;
      }

      windowStage.getMainWindow().then((data: window.Window) => {
        this.windowObj = data;
        AppStorage.setOrCreate<window.Window>('window', data);

        // Enable full-screen immersive mode；状态栏/导航栏内容色跟随主题
        ThemeManager.applyToWindow();
        data.setWindowLayoutFullScreen(true);

        const uiContext = data.getUIContext();
        AppStorage.setOrCreate('uiContext', uiContext);
        let topArea = this.windowObj!.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        let topHeight = uiContext.px2vp(topArea.topRect.height);
        AppStorage.setOrCreate('topHeight', topHeight);
        let bottomArea = this.windowObj!.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
        let bottomHeight = uiContext.px2vp(bottomArea.bottomRect.height);
        AppStorage.setOrCreate('bottomHeight', bottomHeight);
        this.updateBreakpoint(this.windowObj!.getWindowProperties().windowRect.width);
        this.windowObj!.on('windowSizeChange', (windowSize: window.Size) => {
          this.updateBreakpoint(windowSize.width);
        });
      });

      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  private updateBreakpoint(windowWidth: number): void {
    try {
      let windowWidthVp = windowWidth / display.getDefaultDisplaySync().densityPixels;
      let curBp: string = '';
      if (windowWidthVp < BreakpointConstants.BREAKPOINT_VALUE_NUMBER[1]) {
        curBp = BreakpointConstants.BREAKPOINT_SM;
      } else if (windowWidthVp < BreakpointConstants.BREAKPOINT_VALUE_NUMBER[2]) {
        curBp = BreakpointConstants.BREAKPOINT_MD;
      } else {
        curBp = BreakpointConstants.BREAKPOINT_LG;
      }
      AppStorage.setOrCreate('currentBreakpoint', curBp);
    } catch (e) {
      AppStorage.setOrCreate('currentBreakpoint', BreakpointConstants.BREAKPOINT_SM);
    }
  }

  private async initStore(): Promise<void> {
    try {
      const store: MusicStore = MusicStore.getInstance();
      await store.init(this.context);
      if (store.songs.length === 0) {
        hilog.info(DOMAIN, 'testTag', 'No local songs yet, import from 音乐库');
      } else {
        hilog.info(DOMAIN, 'testTag', `Loaded ${store.songs.length} songs from storage`);
      }
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to init store');
    }
  }

  onConfigurationUpdated(config: Configuration): void {
    hilog.info(DOMAIN, 'testTag', 'Ability onConfigurationUpdated');
    // 同步系统深色模式状态，供 ThemeManager 在「跟随系统」时读取
    const dark: boolean = config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    AppStorage.setOrCreate('systemIsDark', dark);
    // 仅当主题为「跟随系统」时，随系统深色模式刷新
    if (SettingsStore.getInstance().getThemeMode() === 'system') {
      ThemeManager.refreshSystemTheme();
    }
  }

  onWindowStageDestroy() {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground() {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground() {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}