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
import { MusicStore } from '../services/MusicStore';
import { SettingsStore } from '../utils/SettingsStore';
import { ThemeManager, ColorTokens } from '../utils/ThemeManager';

interface SettingsCategoryParam {
  category: string;
}

interface CategoryItem {
  id: string;
  title: string;
  subtitle: string;
  icon: ResourceStr;
  iconColor: string;
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

  /** 主题响应式：根据 isDark 取对应令牌。 */
  private getThemeColors(): ColorTokens {
    return this.isDark ? ThemeManager.darkColors : ThemeManager.lightColors;
  }

  /**
   * 设置分类入口。每个分类点击后进入对应的下一级页面（SettingsCategory），
   * 由该页按 category 参数渲染具体设置项。分类结构预置，便于后续扩展新功能。
   */
  private categories(): Array<CategoryItem> {
    return [
      { id: 'playback', title: '播放', subtitle: '自动下一首 · 播放模式', icon: $r('app.media.ic_repeat'), iconColor: '#FF9500' },
      { id: 'appearance', title: '用户界面', subtitle: '深色模式 · 主题', icon: $r('app.media.ic_hm_moon'), iconColor: '#5E5CE6' },
      { id: 'accessibility', title: '无障碍', subtitle: '降低动态效果', icon: $r('app.media.ic_hm_profile'), iconColor: '#007AFF' },
      { id: 'storage', title: '存储', subtitle: '缓存 · 播放历史 · 本地管理', icon: $r('app.media.ic_hm_trash'), iconColor: '#FF9500' },
      { id: 'notification', title: '通知', subtitle: '锁屏/状态栏控制', icon: $r('app.media.ic_bells_o'), iconColor: '#FFCC00' },
      { id: 'privacy', title: '隐私', subtitle: '听歌统计', icon: $r('app.media.ic_favorite'), iconColor: '#FA2759' },
      { id: 'about', title: '关于', subtitle: '版本 · 开发者 · 隐私政策', icon: $r('app.media.ic_hm_settings'), iconColor: '#5856D6' }
    ];
  }

  build() {
    NavDestination() {
      Column() {
        // Header
        Row() {
          Image($r('app.media.ic_hm_back'))
            .width(24)
            .height(24)
            .fillColor(this.getThemeColors().primaryText)
            .onClick(() => {
              this.pathStack.pop();
            })
          Text('设置')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getThemeColors().primaryText)
            .margin({ left: 12 })
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: this.topHeight + 12, bottom: 16 })

        Scroll() {
          Column() {
            Text('设置分类')
              .fontSize(13)
              .fontColor(this.getThemeColors().secondaryText)
              .width('100%')
              .padding({ left: 4, bottom: 10 })

            Column() {
              ForEach(this.categories(), (cat: CategoryItem) => {
                this.buildCategoryItem(cat);
              }, (cat: CategoryItem): string => cat.id)
            }
            .margin({ bottom: 8 })

            Text('Made with HarmonyOS SDK')
              .fontSize(12)
              .fontColor(this.getThemeColors().secondaryText)
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
      .backgroundColor(this.getThemeColors().bg)
    }
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
    .hideTitleBar(true)
  }

  @Builder
  buildCategoryItem(cat: CategoryItem) {
    Row() {
      Stack() {
        Image(cat.icon)
          .width(20)
          .height(20)
          .fillColor(Color.White)
      }
      .width(36)
      .height(36)
      .borderRadius(10)
      .backgroundColor(cat.iconColor)
      .margin({ right: 14 })
      .shadow({
        radius: 6,
        color: `${cat.iconColor}33`,
        offsetX: 0,
        offsetY: 2
      })

      Column() {
        Text(cat.title)
          .fontSize(16)
          .fontColor(this.getThemeColors().primaryText)
          .fontWeight(FontWeight.Medium)
          .margin({ bottom: 4 })
        Text(cat.subtitle)
          .fontSize(13)
          .fontColor(this.getThemeColors().secondaryText)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Image($r('app.media.ic_hm_more'))
        .width(16)
        .fillColor(this.getThemeColors().separator)
    }
    .width('100%')
    .height(64)
    .padding({ left: 16, right: 16 })
    .backgroundColor(this.getThemeColors().cardBg)
    .borderRadius(14)
    .margin({ bottom: 2 })
    .onClick(() => {
      const param: SettingsCategoryParam = { category: cat.id };
      this.pathStack.pushPathByName('SettingsCategory', param);
    })
  }
}
