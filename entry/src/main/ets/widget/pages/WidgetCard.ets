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

/**
 * 桌面音乐播控卡片（ArkTS 动态卡片）。
 * 数据由主应用经 formProvider.updateForm 推送（title / artist / album / duration / position / lyric / isPlaying / isDark /
 * dimension / coverKey），封面经 formImages 以文件描述符跨进程下发。
 * position 与 lyric 由主应用在播放中每秒刷新，实现进度条走动与当前歌词行实时同步；
 * 按钮通过 postCardAction 的 router 事件回拉起 EntryAbility，params.control 回传 'play' / 'pause' / 'next' / 'prev'。
 *
 * 主题跟随：卡片运行在独立渲染进程，无法共享主应用 AppStorage，亦不可 import 完整
 * ThemeManager（其依赖 window/Preferences）。故卡片内自建轻量 getCardColors(isDark) 取色集，
 * 色值直接来自 tokens/LumioColor 的 semanticOf（与主应用 ThemeManager 同源，零 import，Form 进程安全）。
 * isDark 由 FormAbility.onAddForm 写入，并随主应用主题切换经 pushFormUpdate() 自愈重推。
 *
 * 尺寸适配：卡片进程无法自行测量尺寸，档位由创建/推送时下发的 dimension 决定
 * （FormDimension：2=2*2 紧凑 / 3=2*4 中等 / 4=4*4 完整）。三档共用同一取色集，故深色跟随在所有档位生效。
 */
import { semanticOf, CARD_CONTROL_BG_LIGHT, CARD_CONTROL_BG_DARK } from '../../tokens/LumioColor';
import { TYPE_SM, SPACE_SM } from '../../tokens/LumioScale';

interface CardColors {
  cardBg: string;
  titleText: string;
  artistText: string;
  iconColor: string;
  secondaryBtnBg: string;
  playBtnBg: string;
  playIconColor: string;
}

/** 尺寸档位（对应 formInfo.FormDimension 数值）。 */
const DIMENSION_2_2: number = 2;
const DIMENSION_2_4: number = 3;
const DIMENSION_4_4: number = 4;

let storage = new LocalStorage();
@Entry(storage)
@Component
struct WidgetCard {
  @LocalStorageProp('title') title: string = '';
  @LocalStorageProp('artist') artist: string = '';
  @LocalStorageProp('album') album: string = '';
  @LocalStorageProp('duration') duration: number = 0;
  @LocalStorageProp('position') curPosition: number = 0;
  @LocalStorageProp('lyric') lyric: string = '';
  @LocalStorageProp('isPlaying') isPlaying: boolean = false;
  @LocalStorageProp('isDark') isDark: boolean = false;
  @LocalStorageProp('dimension') dimension: number = DIMENSION_2_2;
  // 主应用经 formImages 下发的封面标识；空串表示无真实封面，回落内置默认图。
  @LocalStorageProp('coverKey') coverKey: string = '';

  /**
   * 毫秒 → mm:ss。build() 内禁止 const/let，故以纯方法内联调用。
   */
  private formatDuration(ms: number): string {
    if (ms <= 0) {
      return '00:00';
    }
    const totalSec: number = Math.floor(ms / 1000);
    const min: number = Math.floor(totalSec / 60);
    const sec: number = totalSec % 60;
    const mm: string = min < 10 ? '0' + min.toString() : min.toString();
    const ss: string = sec < 10 ? '0' + sec.toString() : sec.toString();
    return mm + ':' + ss;
  }

  /**
   * 卡片取色集：直接引用 tokens/LumioColor 的 semanticOf（与主应用 ThemeManager 同源）。
   * 背景/文字/图标一律经此取色，禁止硬编码 Color.White 等字面量（取色见 tokens/LumioColor）。
   * Form 卡片进程仅可 import 零依赖的 LumioColor。
   */
  private getCardColors(): CardColors {
    const s = semanticOf(this.isDark);
    return {
      cardBg: s.surfaceRaised,
      titleText: s.label,
      artistText: s.labelSecondary,
      iconColor: s.label,
      secondaryBtnBg: this.isDark ? CARD_CONTROL_BG_DARK : CARD_CONTROL_BG_LIGHT,
      playBtnBg: s.accent,
      playIconColor: s.labelOnAccent
    };
  }

  /**
   * 封面图源：有真实封面时用 memory://<coverKey> 引用主应用经 formImages 下发的 fd 图像；
   * 无封面时回落内置默认图（卡片与主应用同包，资源可直接 $r 引用）。
   */
  private coverSrc(): ResourceStr {
    if (this.coverKey.length > 0) {
      return 'memory://' + this.coverKey;
    }
    return $r('app.media.ic_default_cover');
  }

  private progressValue(): number {
    return this.curPosition > this.duration ? this.duration : this.curPosition;
  }

  /** 进度条 + 时间（播放中 position 由主应用每秒推送）。 */
  @Builder
  ProgressBlock() {
    Column() {
      Progress({
        value: this.progressValue(),
        total: this.duration > 0 ? this.duration : 1,
        type: ProgressType.Linear
      })
        .width('100%')
        .height(4)
        .color(this.getCardColors().playBtnBg)
        .backgroundColor(this.getCardColors().secondaryBtnBg)
        .borderRadius(2)
      Row() {
        Text(this.formatDuration(this.progressValue()))
          .fontSize(TYPE_SM.caption2.size)
          .fontColor(this.getCardColors().artistText)
        Text(this.formatDuration(this.duration))
          .fontSize(TYPE_SM.caption2.size)
          .fontColor(this.getCardColors().artistText)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .margin({ top: SPACE_SM.compact })
    }
    .width('100%')
  }

  /** 播放控制按钮组（仅 4*4 完整档展示，紧凑档不占用卡片空间）。 */
  @Builder
  Controls() {
    Row() {
      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.ic_public_play_last'))
          .width(24)
          .height(24)
          .fillColor(this.getCardColors().iconColor)
      }
      .width(40)
      .height(40)
      .backgroundColor(this.getCardColors().secondaryBtnBg)
      .accessibilityText($r('app.string.previous'))
      .onClick(() => {
        postCardAction(this, { action: 'router', abilityName: 'EntryAbility', params: { control: 'prev' } });
      })

      Button({ type: ButtonType.Circle }) {
        Image(this.isPlaying ? $r('app.media.ic_lib_pause') : $r('app.media.ic_lib_play'))
          .width(28)
          .height(28)
          .fillColor(this.getCardColors().playIconColor)
      }
      .width(56)
      .height(56)
      .backgroundColor(this.getCardColors().playBtnBg)
      .margin({ left: SPACE_SM.base, right: SPACE_SM.base })
      .accessibilityText(this.isPlaying ? $r('app.string.pause') : $r('app.string.play'))
      .onClick(() => {
        postCardAction(this, { action: 'router', abilityName: 'EntryAbility', params: { control: this.isPlaying ? 'pause' : 'play' } });
      })

      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.ic_public_play_next'))
          .width(24)
          .height(24)
          .fillColor(this.getCardColors().iconColor)
      }
      .width(40)
      .height(40)
      .backgroundColor(this.getCardColors().secondaryBtnBg)
      .accessibilityText($r('app.string.next'))
      .onClick(() => {
        postCardAction(this, { action: 'router', abilityName: 'EntryAbility', params: { control: 'next' } });
      })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  /** 2*2 紧凑档：仅封面 + 标题/艺术家。 */
  @Builder
  CompactLayout() {
    Column() {
      Image(this.coverSrc())
        .width(64)
        .height(64)
        .borderRadius(12)
        .objectFit(ImageFit.Cover)
      Text(this.title)
        .fontSize(TYPE_SM.headline.size)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.getCardColors().titleText)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: SPACE_SM.cozy })
      Text(this.artist)
        .fontSize(TYPE_SM.caption1.size)
        .fontColor(this.getCardColors().artistText)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: SPACE_SM.hair })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(SPACE_SM.base)
  }

  /** 2*4 中等档：封面 + 标题/艺术家 + 进度。 */
  @Builder
  MediumLayout() {
    Column() {
      Row() {
        Image(this.coverSrc())
          .width(44)
          .height(44)
          .borderRadius(8)
          .objectFit(ImageFit.Cover)
          .margin({ right: SPACE_SM.cozy })
        Column() {
          Text(this.title)
            .fontSize(TYPE_SM.headline.size)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getCardColors().titleText)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(this.artist)
            .fontSize(TYPE_SM.caption1.size)
            .fontColor(this.getCardColors().artistText)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: SPACE_SM.hair })
          if (this.album.length > 0) {
            Text(this.album)
              .fontSize(TYPE_SM.caption2.size)
              .fontColor(this.getCardColors().artistText)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .margin({ top: SPACE_SM.hair })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      this.ProgressBlock()
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    .padding(SPACE_SM.base)
  }

  /** 4*4 完整档：封面 + 标题/艺术家/专辑 + 进度 + 当前歌词 + 控制。 */
  @Builder
  FullLayout() {
    Column() {
      Row() {
        Image(this.coverSrc())
          .width(56)
          .height(56)
          .borderRadius(10)
          .objectFit(ImageFit.Cover)
          .margin({ right: SPACE_SM.cozy })
        Column() {
          Text(this.title)
            .fontSize(TYPE_SM.headline.size)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getCardColors().titleText)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(this.artist)
            .fontSize(TYPE_SM.caption1.size)
            .fontColor(this.getCardColors().artistText)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: SPACE_SM.hair })
          if (this.album.length > 0) {
            Text(this.album)
              .fontSize(TYPE_SM.caption2.size)
              .fontColor(this.getCardColors().artistText)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .margin({ top: SPACE_SM.hair })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      this.ProgressBlock()

      if (this.lyric.length > 0) {
        Text(this.lyric)
          .fontSize(TYPE_SM.caption1.size)
          .fontColor(this.getCardColors().titleText)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: SPACE_SM.tight })
      }

      this.Controls()
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    .padding(SPACE_SM.base)
  }

  build() {
    Column() {
      if (this.dimension === DIMENSION_4_4) {
        this.FullLayout()
      } else if (this.dimension === DIMENSION_2_4) {
        this.MediumLayout()
      } else {
        this.CompactLayout()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.getCardColors().cardBg)
  }
}
