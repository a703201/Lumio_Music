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

import { SPACE_SM } from '../../tokens/LumioScale';
import { Logger } from '../../utils/Logger';
// 3.0.0 起最低平台为 API 26，@ohos.arkui.uiMaterial（API 26 整模块新增）在本应用支持的
// 全部设备上均存在，故直接静态导入 + 直接构造，不再保留低版本动态加载的双路径。
import uiMaterial from '@ohos.arkui.uiMaterial';

const TAG = 'SheetMaterial';

/**
 * 获取系统材质（沉浸毛玻璃）。
 *
 * 静态构造 `ImmersiveMaterial({ style: REGULAR })`；仅在构造抛异常时兜底 resolve(undefined)，
 * 调用方据此在 SheetScaffold 中二选一：有值走 systemMaterial，否则走纯色 surfaceOverlay 兜底。
 *
 * 保留 Promise 形态是为了不打断既有 9 处 `acquireSheetMaterial().then(...)` 调用点的
 * @State material 赋值时序（值就绪后触发一次重渲染）。
 */
export function acquireSheetMaterial(): Promise<uiMaterial.Material | undefined> {
  return new Promise<uiMaterial.Material | undefined>(
    (resolve: (value: uiMaterial.Material | undefined) => void): void => {
      try {
        resolve(new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR }));
      } catch (e) {
        Logger.error(TAG, 'construct ImmersiveMaterial failed, fall back to solid color');
        resolve(undefined);
      }
    }
  );
}

/**
 * 半模态根容器脚手架（@Component + @BuilderParam 内容槽，ArkTS 内容槽标准机制）。
 *
 * - 材质就绪：根 Column 启用 systemMaterial 系统级毛玻璃（自适应深浅色与算力档位）；
 * - 材质未就绪（构造失败）：根 Column 用纯色 fallbackColor 兜底。
 *
 * ⚠️ 硬规则（设计文档 §2.5.5）：两分支互斥，绝不同时在同一 Column 上设 systemMaterial + backgroundColor。
 * 两个 if/else 分支各自只设置其一。
 *
 * 统一内距：左右 roomy(20) / 底 loose(24)（与 SongDetailSheet 既有写法一致，顶距由内容自行控制）。
 */
@Component
export struct SheetScaffold {
  /** 系统材质实例：由 acquireSheetMaterial() 注入；构造失败为 undefined（走纯色兜底）。 */
  @Prop material: uiMaterial.Material | undefined = undefined;
  /** 材质未就绪时的纯色兜底（通常传 surfaceOverlay）。 */
  @Prop fallbackColor: ResourceColor = '#FFFFFF';
  /** 内容槽：由宿主组件以尾随 builder 传入，捕获宿主 this 上下文（方法/状态）。 */
  @BuilderParam content: () => void;

  build() {
    if (this.material !== undefined) {
      Column() {
        this.content();
      }
      .width('100%')
      .padding({ left: SPACE_SM.roomy, right: SPACE_SM.roomy, bottom: SPACE_SM.loose })
      .systemMaterial(this.material);
    } else {
      Column() {
        this.content();
      }
      .width('100%')
      .padding({ left: SPACE_SM.roomy, right: SPACE_SM.roomy, bottom: SPACE_SM.loose })
      .backgroundColor(this.fallbackColor);
    }
  }
}
