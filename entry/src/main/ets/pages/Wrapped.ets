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

import { SongItem } from '../models/music';
import { MusicStore } from '../services/MusicStore';
import { AudioRendererController } from '../utils/AudioRendererController';
import { curves } from '@kit.ArkUI';
import { WrappedBody } from '../components/SettingsSubPageBodies';
import { ShareUtil } from '../utils/ShareUtil';
import { ThemeManager, ColorTokens } from '../utils/ThemeManager';
import { TYPE_SM, SPACE_SM } from '../tokens/LumioScale';

@Builder
export function WrappedBuilder() {
  NavDestination() {
    Wrapped()
  }
  .hideTitleBar(true)
}

@Component
struct Wrapped {
  pathStack: NavPathStack = new NavPathStack();
  store: MusicStore = MusicStore.getInstance();
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('topHeight') topHeight: number = 0;

  private getThemeColors(): ColorTokens {
    return this.isDark ? ThemeManager.darkColors : ThemeManager.lightColors;
  }

  /** 构建年度记录文本摘要用于分享（离线文本卡片，不传输文件）。 */
  private buildSummary(): string {
    const summary = this.store.getStatsSummary();
    const lines: Array<string> = [];
    lines.push(this.getUIContext().getHostContext()?.resourceManager.getStringSync($r('app.string.wrapped_title').id) ?? '');
    lines.push(`总播放：${summary.totalPlays} 次`);
    const minutes: number = Math.floor(summary.totalMs / 60000);
    lines.push(`总时长：${minutes} 分钟`);
    lines.push(`曲库：${summary.songCount} 首`);
    if (summary.topSongs.length > 0) {
      lines.push(this.getUIContext().getHostContext()?.resourceManager.getStringSync($r('app.string.most_played_label').id) ?? '');
      summary.topSongs.slice(0, 5).forEach((s: SongItem, i: number) => {
        lines.push(`${i + 1}. ${s.title} - ${s.singer}`);
      });
    }
    return lines.join('\n');
  }

  /** 主导航栈版本：点击 TopSongs 进入播放页（一镜到底）。Body 内简化。 */
  build() {
    NavDestination() {
      Stack() {
        Column() {
          WrappedBody({ onBack: () => this.pathStack.pop() })
        }
        .width('100%')
        .height('100%')

        // 右上角分享按钮（悬浮于 Body 之上）
        Image($r('app.media.ic_public_share'))
          .width(24)
          .height(24)
          .fillColor(this.getThemeColors().primaryText)
          .position({ top: this.topHeight + 12, right: SPACE_SM.base })
          .onClick(() => {
            ShareUtil.shareText(this.buildSummary(), this.getUIContext().getHostContext()?.resourceManager.getStringSync($r('app.string.year_record').id) ?? '');
          })
      }
      .width('100%')
      .height('100%')
    }
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
    .hideTitleBar(true)
  }
}
