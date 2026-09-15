import { hilog } from '@kit.PerformanceAnalysisKit';
import { bundleManager } from '@kit.AbilityKit';
import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';

/**
 * 与产品代码 AppInfoUtil.ets:24/32 使用同一套 API 与同一个 flag，
 * 该调用路径已在「关于 / 设置 / 我的」页运行时验证可用，因此此处断言不会因环境缺失而假失败。
 */
const BUNDLE_FLAGS: bundleManager.BundleFlag = bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT;
/** AppScope/app.json5 的 bundleName；ohosTest/module.json5 未也不能覆盖 bundleName（bundleName 为应用级字段）。 */
const EXPECTED_BUNDLE_NAME: string = 'com.Lumio.music';

export default function abilityTest() {
  describe('ActsAbilityTest', () => {
    // Defines a test suite. Two parameters are supported: test suite name and test suite function.
    beforeAll(() => {
      // Presets an action, which is performed only once before all test cases of the test suite start.
      // This API supports only one parameter: preset action function.
    })
    beforeEach(() => {
      // Presets an action, which is performed before each unit test case starts.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: preset action function.
    })
    afterEach(() => {
      // Presets a clear action, which is performed after each unit test case ends.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: clear action function.
    })
    afterAll(() => {
      // Presets a clear action, which is performed after all test cases of the test suite end.
      // This API supports only one parameter: clear action function.
    })

    it('app_startup_bundle_identifies_lumio', 0, () => {
      const bundleInfo: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(BUNDLE_FLAGS);
      hilog.info(0x0000, 'testTag', '%{public}s', 'bundleName=' + bundleInfo.name);
      // 应用启动后可读到自身 bundle 信息，且 bundleName 与 AppScope/app.json5 一致
      expect(bundleInfo.name.length > 0).assertEqual(true);
      expect(bundleInfo.name).assertEqual(EXPECTED_BUNDLE_NAME);
    })

    it('app_startup_version_metadata_is_readable', 0, () => {
      const bundleInfo: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(BUNDLE_FLAGS);
      hilog.info(0x0000, 'testTag', '%{public}s', 'version=' + bundleInfo.versionName);
      // 不写死具体版本号，避免发布改版本后测试假失败；只校验版本元数据在启动后可读且合法
      expect(bundleInfo.versionName.length > 0).assertEqual(true);
      expect(bundleInfo.versionCode > 0).assertEqual(true);
    })
  })
}
