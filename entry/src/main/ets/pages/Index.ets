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

import { HdsNavigation } from '@kit.UIDesignKit';

@Entry
@Component
struct Index {
  @Provide('navPathStack') pathStack: NavPathStack = new NavPathStack()

  build() {
    HdsNavigation(this.pathStack) {
    }
    .onAppear(() => {
      this.pathStack.pushPathByName('Layout', null, false);
    })
    .hideNavBar(true)
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
  }
}
