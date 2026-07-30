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
