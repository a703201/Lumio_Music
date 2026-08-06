# 更新日志 · CHANGELOG

本文件记录 Lumio Music（鸿蒙音乐播放器）的版本演进。
许可证：[Apache-2.0](./LICENSE)，Copyright © 2026 何宇翔。
代码当前 `versionName` 为 `2.3.0`（见 `AppScope/app.json5`）；应用内「关于 / 设置 / 我的」页的版本展示通过 `bundleManager` 运行时读取，**自动跟随该配置**，无需硬编码。下方里程碑按功能迭代划分。

---

## v2.3.0（2026-08-06）· 交互打磨与 NFR 品质提升

> Lumio Music 的交互深度优化与非功能需求品质工程批次。全部改动经 `harmonyos-reviewer` 审查 **0 ERROR / 0 WARNING**，`bash build_hap.sh` 稳定产出签名 HAP。

### 新增
- **长按选项栏替代右侧「更多」按钮**（FR-25）：`bindContextMenu(menu, ResponseType.LongPress)` 长按唤出选项栏，`@Builder buildSongMenu` / `buildPlaylistMenu` 统一渲染；覆盖音乐库、收藏、历史、歌单详情、我的歌单共五处。
- **歌曲详情半模态面板**（FR-26）：`components/SongDetailSheet.ets`，`bindSheet` MEDIUM/LARGE 高度，展示文件名/标题/歌手/作曲家/合集/年代/添加时间。
- **添加到歌单半模态面板**（FR-27）：`components/AddToPlaylistSheet.ets`（Medium），列出自建歌单，支持面板内新建歌单并立即加入。
- **年代全链路解析**（FR-28）：C++ `FLAC DATE` / MP3 `TYER`+`TDRC` / MP4 `©day` → NAPI `year` → ArkTS `AudioMeta.year`（MediaKit 优先、NAPI 兜底）→ 详情面板按需异步取值。year 不落 `SongItem`。
- **歌词手动滑动浏览**（FR-29）：`LrcView.ets` `onTouch` 状态机，滑动时取消模糊，手指静止 5 秒后自动回正。
- **迷你播放器真实封面**（FR-30）：`Layout.playerButton` 经 `CoverCache.getLabel()` 取真实封面，`geometryTransition('player_cover', {follow:true})` 一镜到底两端一致。
- **设置子页**（FR-31）：`pages/SettingsCategory.ets`（`route_map` 注册），按分类渲染设置子项。
- **隐私政策页**（FR-32）：`pages/PrivacyPolicy.ets`（`route_map` 注册）。
- **响应式封面组件**（FR-33）：`components/CoverImageView.ets`，监听 `coverRefreshToken` + `src` 双信号，解决 `ForEach` 复用时 Image 源切换不重渲染。
- **开发辅助脚本**（FR-34）：`tools/` 4 个 Python 脚本（`dump_3files.py` / `probe_lyrics.py` / `verify_reader.py` / `verify_reversal.py`），提供 C++ 解析器与歌词解析器离线验证。
- **统一版权声明**：全部源码文件（`.ets` / `.cpp` / `.h` / `.py`）添加 Apache-2.0 版权头（Copyright 2026 何宇翔）。

### NFR（非功能需求）品质提升
- **C++ 原生解析健壮性补强**：MP3 `&buf[s]` UB 守卫（零长帧不取过尾索引）、MP4 `largesize==0` 延伸至文件尾（ISO 14496-12 合规）、帧同步二次校验（连续 2 帧一致才采信）、CBR 尾部 ID3v1/APE 标签扣除（时长更精确）、`spf` Layer I/II/III 显式区分、`static_assert(sizeof(size_t)>=8)` 固化 64 位前提——全部已在 `audio_metadata.cpp` 落地。
- **NAPI 超长路径动态分配**：`napi_init.cpp` 原 `char filePath[1024]` 固定栈缓冲改为先探长度再 `std::vector<char>` 动态分配，>1023 字节路径不再静默截断。
- **NAPI 类型声明**：新增 `cpp/types/libnative_module/index.d.ts`，把 `parseAudioMetadata` 的 7 字段契约交给编译器守护，IDE 获得自动补全与类型检查。

### 优化
- 各页面底部 `bindSheet` 收敛为单一绑定 + `sheetKind` 分发（修复后挂覆盖先挂导致「详细」面板不弹）。
- 一镜到底回退为 Image 放大模糊稳态背景（修复偶发白屏/布局错乱）。
- C++ 兜底路径恢复生效：`AudioMetaReader` 并发入口改为顶层 `@Concurrent` 具名函数（修复真机静默抛 10200014）。
- 空状态呼吸动画由 `setInterval` 改为 `UIContext.animateTo` 循环 + `isDisposed`/`pageVisible` 守卫。
- 迷你封面暂停态叠加 `SymbolGlyph` 图标。

### 版本对齐
- `AppScope/app.json5` → `versionName 2.3.0` / `versionCode 2030000`（此前 `2.1.0` 为合并口径，升版后 CHANGELOG 里程碑与代码完全一致）。
- `route_map.json` 随功能增至 **11 条**（新增 `SettingsCategory`）。
- PRD、本 CHANGELOG、app.json5 版本口径统一为 v2.3.0。

---

## v2.1.0（2026-07-30）· HDS 沉浸重构与功能基线

### 新增
- **接入 HDS 设计系统**：根导航 `HdsNavigation` + 主布局 `HdsTabs` 替换传统 `Navigation` / `Tabs` 组件。
- **底部栏沉浸光感**：`barFloatingStyle` 启用 `systemMaterialEffect`（ADAPTIVE 材质），与系统视觉融合。
- **一镜到底动画**：迷你播放器封面与播放器页通过 `geometryTransition` 共享元素 + `interpolatingSpring` 曲线。
- **智感握姿（底栏自适应）**：`barFloatingStyle({ adaptToHandedness: true })`，底部栏布局跟随握持姿态。
- **音乐库与歌曲页合并**：原「歌曲」+「音乐库」合并为单一音乐库页；导入功能迁移至音乐库页。
- **我的页上下滑动**：列表包裹 `Scroll` 容器，支持上下滚动浏览。
- **官方图标集成**：引入 13 个 HarmonyOS 官方图标（`ic_hm_*` 系列 SVG）。
- **开发者信息更新**：设置页「开发者」改为 **何宇翔**，点击跳转简历网页。
- **播放器入口下移**：迷你播放条下压并留出底部安全区。
- **歌单拖拽排序（FR-24）**：`ForEach.onMove` 长按拖动重排，持久化顺序。
- **C++ 解析器计划项落地**：MP3 支持 Xing/Info VBR 头精确时长；MP4 支持 64 位 `largesize` 与 v0/v1 `mvhd`；ID3v2 `enc==2`（UTF-16BE 无 BOM）按大端解析，中文不再乱码。

### 优化
- 各页面功能布局重新梳理，聚焦核心听歌体验。
- 迷你播放条底部边距与列表底部留白联动安全区（`@StorageProp('bottomHeight')`）。

### 修复
- 适配 API 24，`BottomTabBarStyle` 改用 `CustomBuilder` 自定义底部标签栏。
- 移除 6.1.1 SDK 未提供的 `motion` 主动监听，保留底栏 `adaptToHandedness` 自适应。
- `main_pages.json` 精简为仅注册 `Index`，其余页面经 `route_map.json` 推送。

### 移除
- 不可用的**本地扫描功能**（删除 `MusicScanner` 及相关调用）。
- 设置页中**不可调整的播放模式项**。
- 已删除 `Songs.ets` / `Moment.ets`，统一由 `LocalLibrary.ets` 承载。
- **下线发现页（FR-21）**：`Find.ets` 经复核为孤儿文件（未注册导航、无引用），已删除，零构建影响。

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
