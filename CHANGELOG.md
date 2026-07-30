# 更新日志 · CHANGELOG

本文件记录 HM Music（鸿蒙音乐播放器）的版本演进。
代码当前 `versionName` 为 `2.1.0`（见 `AppScope/app.json5`）；应用内「关于 / 设置 / 我的」页的版本展示通过 `bundleManager` 运行时读取，**自动跟随该配置**，无需硬编码。下方里程碑按功能迭代划分。

---

## v2.1.0（2026-07-30）· HDS 沉浸重构

### 新增
- **接入 HDS 设计系统**：根导航 `HdsNavigation` + 主布局 `HdsTabs` 替换传统 `Navigation` / `Tabs` 组件。
- **底部栏沉浸光感**：`barFloatingStyle` 启用 `systemMaterialEffect`（ADAPTIVE 材质），与系统视觉融合。
- **一镜到底动画**：迷你播放器封面与播放器页通过 `geometryTransition` 共享元素 + `interpolatingSpring` 曲线，实现进出场顺滑形变。
- **智感握姿（底栏自适应）**：`barFloatingStyle({ adaptToHandedness: true })`，底部栏布局跟随握持姿态。
- **音乐库与歌曲页合并**：原「歌曲」+「音乐库」合并为单一音乐库页；**导入功能**从歌曲页迁移至音乐库页。
- **我的页上下滑动**：列表包裹 `Scroll` 容器，支持上下滚动浏览。
- **官方图标集成**：引入 13 个 HarmonyOS 官方图标（`ic_hm_*` 系列 SVG）并入项目资源。
- **开发者信息更新**：设置页「开发者」改为 **何宇翔**，点击跳转简历网页 `https://www.a703201sworld.top/resume/`。
- **播放器入口下移**：迷你播放条整体下压并留出底部安全区，避免遮挡 Tab 与页面底部选项。

### 优化
- 各页面功能布局重新梳理，聚焦核心听歌体验。
- 迷你播放条底部边距与列表底部留白联动安全区（`@StorageProp('bottomHeight')`）。

### 移除
- 不可用的**本地扫描功能**（删除 `MusicScanner` 及相关调用）。
- 设置页中**不可调整的播放模式项**。
- 已删除 `Songs.ets` / `Moment.ets`，统一由 `LocalLibrary.ets` 承载。

### 兼容性 / 修复
- 适配本机 SDK **HarmonyOS 6.1.1 (API 24)**：该版本未导出 `BottomTabBarStyle`，改用 `CustomBuilder` 自定义底部标签栏（视觉一致）。
- 当前 6.1.1 SDK 未内置 `@kit.MultimodalAwarenessKit`，移除主动监听 `motion` 的代码，保留底栏 `adaptToHandedness` 自适应（升级 SDK 后可补齐主动感知）。
- `main_pages.json` 精简为仅注册 `Index`，其余页面经 `route_map.json` 以 `NavDestination` 推送。
- 对照官方 `Spatialization` 示例修正 API 用法（`SymbolGlyphModifier` 导入源、`labelStyle` 键名等）。
- 经 `harmonyos-reviewer` 审查：**0 ERROR / 0 WARNING**，release HAP 编译通过。

### 版本
- `AppScope/app.json5` 版本号同步至 **`2.1.0`**（`versionCode` 2010000）。
- 新增 `utils/AppInfoUtil.ets`：通过 `bundleManager.getBundleInfoForSelfSync` 运行时读取 `versionName`，关于页 / 设置页「版本信息」/ 我的页「关于」的版本文案均改为引用该值，**自动跟随工程配置**，不再硬编码。

---

## v2.0（2026-07-05）

### 新增
- 迷你播放器：底部显示当前播放歌曲，点击进入播放器页面。
- 播放器页面入场 / 退场动画。
- 页面交互动效：列表项交错入场、按压缩放反馈、空状态图标脉冲、Tab 栏切换弹跳、头像呼吸灯、数字滚动统计。
- 音乐库统计面板（歌曲数 / 收藏数 / 最近播放数）。
- 分类文件夹彩色图标、歌曲序号显示、播放中歌曲高亮状态、扫描进度条。
- 关于页面功能特色展示。

### 优化
- 整体 UI 视觉升级：统一圆角风格、彩色图标容器、徽章式计数、分组标题设计。
- 各页面头部统一为 20px 粗体标题；返回按钮按压缩放效果；设置页分组优化。
- 版本号更新至 2.0。

### 修复
- C++ 编译 duplicate symbol 错误（拆分 `audio_metadata.h/.cpp`）。
- ArkTS `Object.assign` 受限问题（改用手动属性赋值）。
- `main_pages.json` 中非 `@Entry` 页面注册错误。

---

## v1.1.0

### 新增
- 基础音乐播放功能框架。
- 歌曲列表展示。
- 音乐文件扫描与导入。
- 收藏功能。
- 播放历史记录。
- 播放模式切换（顺序 / 列表循环 / 单曲循环）。
- 设置页面、关于页面。

### 技术
- ArkTS + ArkUI 开发。
- C++ Native 模块（音频元数据解析）。
- Navigation + NavPathStack 页面路由。
