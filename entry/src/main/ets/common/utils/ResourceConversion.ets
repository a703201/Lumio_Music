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

import { common } from '@kit.AbilityKit';

export class ResourceConversion {
  private context: common.UIAbilityContext | undefined = undefined;

  constructor() {
    this.context = AppStorage.get('context');
  }

  /**
   * 取字符串资源。显式声明返回 string（失败回退空串），避免调用方拿到 undefined
   * 后被模板字符串渲染成字面量 "undefined"。
   */
  getStringValueFromResource(res: Resource): string {
    if (!this.context) {
      return '';
    }
    try {
      return this.context.resourceManager.getStringSync(res.id);
    } catch (e) {
      return '';
    }
  }
}