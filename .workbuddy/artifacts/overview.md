# 底部栏改造：胶囊导航 + 圆形播放入口

## 已完成
- 重写 `entry/src/main/ets/pages/Layout.ets`：
  - 移除原 `HdsTabs` 默认底栏和独立 `MiniBar`。
  - 改用原生 `Tabs` + `.barHeight(0)` 完全隐藏系统底栏。
  - 新增左侧圆角胶囊导航栏：两个 tab（音乐库 / 我的），毛玻璃背景 + 阴影 + 选中高亮。
  - 新增右侧 56×56 圆形按钮：当前歌曲封面（播放时旋转）或播放图标，点击一镜到底进入 `PlayerPage`。
  - `Stack` 应用 `.expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])`，底部导航栏真正延伸到手势条上方。
- 调整 `LocalLibrary.ets`、`Mine.ets` 的底部 padding（`+170` → `+16`），避免与 `Tabs` 内容区底部 padding 双重留空。
- 清理 `Layout.ets` 中不再使用的 `progress`、`progressMax`、`imageColor` 状态以及 `togglePlay()` 方法。

## 审查结果
- harmonyos-reviewer 扫描：0 ERROR / 0 WARNING（2 个无关 INFO）。

## 待验证
- 请在 DevEco Studio 中重新执行 `assembleHap` 出包验证真机效果。
- 当前仅有两个主页面，故胶囊内只保留「音乐库」「我的」两项；如需四个 tab，请提供另外两项对应的页面。
