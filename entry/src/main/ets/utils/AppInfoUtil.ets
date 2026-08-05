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

import { bundleManager } from '@kit.AbilityKit';

/**
 * 应用信息工具：运行时读取 AppScope/app.json5 中的版本配置，
 * 使页面展示的版本号始终跟随工程配置，无需在各处硬编码。
 */

const BUNDLE_FLAGS: bundleManager.BundleFlag = bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT;

/**
 * 获取应用版本名（versionName），如 "2.1.0"。
 * 读取失败时为兜底返回空字符串。
 */
export function getAppVersionName(): string {
  try {
    const bundleInfo: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(BUNDLE_FLAGS);
    return bundleInfo.versionName;
  } catch (err) {
    return '';
  }
}

/**
 * 获取带品牌前缀的版本展示文案，如 "Lumio Music v2.1.0"。
 */
export function getAppVersionDisplay(): string {
  const versionName: string = getAppVersionName();
  return versionName ? `Lumio Music v${versionName}` : 'Lumio Music';
}
