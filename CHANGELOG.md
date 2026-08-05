# 更新日志 · CHANGELOG

本文件记录 HM Music（鸿蒙音乐播放器）的版本演进。
代码当前 `versionName` 为 `2.1.0`（见 `AppScope/app.json5`）；应用内「关于 / 设置 / 我的」页的版本展示通过 `bundleManager` 运行时读取，**自动跟随该配置**，无需硬编码。下方里程碑按功能迭代划分。

---

## v2.2.0（2026-08-05）· 第二轮增强（代码完成，待 DevEco 真机构建验证）

> 状态：功能 / 修复 / 文档已全部落地；因沙箱拦截 hvigor，release HAP 需在 DevEco Studio 完成构建与真机复验（见 `docs/代码审查报告_第二轮增强.md`）。

### 新增
- **歌单拖拽排序（FR-24）**：歌单详情内长按歌曲经 `ForEach.onMove` 拖动重排，`MusicStore.reorderPlaylistSongs` 持久化顺序。
- **C++ 解析器计划项落地**：MP3 支持 Xing/Info VBR 头精确时长；MP4 支持 64 位 `largesize` 与 v0/v1 `mvhd` 时长；ID3v2 `enc==2`（UTF-16BE 无 BOM）按大端解析，中文不再乱码。

### 优化
- **C++ 兜底路径恢复生效**：`AudioMetaReader` 将同步 NAPI 调用移入 `taskpool`，并发入口改为顶层 `@Concurrent` 具名函数，修复此前闭包写法导致真机静默抛出 10200014、兜底解析从不执行的缺陷。
- **空状态呼吸动画**：歌单页空状态图标由 `setInterval` 改为 `UIContext.animateTo` 循环，并受 `isDisposed` / `pageVisible` 生命周期守卫，避免递归回调泄漏与标志位卡死。
- **C++ 内存安全加固**：`walkAtoms` 畸形 `largesize` 改减法比较防 64 位加法回绕死循环；Latin1/UTF-8 文本分支按缓冲区与帧边界钳制，杜绝越界读。

### 移除
- **下线发现页（FR-21）**：`Find.ets` 经复核为孤儿文件（未注册导航、无引用），已删除，零构建影响。

### 审查与文档
- 经 `code-reviewer` 审查（初版 🔴 驳回 P0×3 + P1×7 + P2×11），全部整改闭环；C++ 以 `g++` 独立 harness 对 3 个真实文件 + 5 个合成样本做改动前后 A/B 对照，零回归。
- PRD / README / 功能模块拆解表 / 本 CHANGELOG 同步回写。

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
