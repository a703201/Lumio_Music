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
 * 数据由主应用经 formProvider.updateForm 推送（title / artist / isPlaying）；
 * 按钮通过 postCardAction 的 message 事件回传 'play' / 'pause' / 'next' / 'prev'，
 * 由 FormAbility.onFormEvent 转发给主 EntryAbility 实现回控。
 */
let storage = new LocalStorage();
@Entry(storage)
@Component
struct WidgetCard {
  @LocalStorageProp('title') title: string = '';
  @LocalStorageProp('artist') artist: string = '';
  @LocalStorageProp('isPlaying') isPlaying: boolean = false;

  build() {
    Column() {
      Row() {
        Image($r('app.media.ic_default_cover'))
          .width(44)
          .height(44)
          .borderRadius(8)
          .margin({ right: 12 })
        Column() {
          Text(this.title)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(this.artist)
            .fontSize(12)
            .fontColor('#AAFFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .margin({ top: 16, left: 16, right: 16 })

      Row() {
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ic_prev'))
            .width(22)
            .height(22)
            .fillColor('#FFFFFF')
        }
        .width(40)
        .height(40)
        .backgroundColor('#33000000')
        .onClick(() => {
          postCardAction(this, { action: 'router', abilityName: 'EntryAbility', params: { control: 'prev' } });
        })

        Button({ type: ButtonType.Circle }) {
          Image(this.isPlaying ? $r('app.media.ic_pause') : $r('app.media.ic_play'))
            .width(28)
            .height(28)
            .fillColor('#FFFFFF')
        }
        .width(56)
        .height(56)
        .backgroundColor('#1E88E5')
        .margin({ left: 16, right: 16 })
        .onClick(() => {
          postCardAction(this, { action: 'router', abilityName: 'EntryAbility', params: { control: this.isPlaying ? 'pause' : 'play' } });
        })

        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ic_next'))
            .width(22)
            .height(22)
            .fillColor('#FFFFFF')
        }
        .width(40)
        .height(40)
        .backgroundColor('#33000000')
        .onClick(() => {
          postCardAction(this, { action: 'router', abilityName: 'EntryAbility', params: { control: 'next' } });
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ top: 12, bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#1A1A2E')
  }
}
