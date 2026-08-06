# Lumio Music — 项目交付概览

> HarmonyOS 6.1.1 / API 24，ArkTS + ArkUI + C++ NAPI。
> 版本 `2.1.0`（`AppScope/app.json5`），bundleName `com.Lumio.music`。
> 许可证 Apache-2.0，Copyright 2026 何宇翔。

## 1. 项目定位

Lumio Music 是一款运行在 HarmonyOS 平台的**纯本地**音乐播放器，不依赖云端曲库，所有歌曲由用户通过系统文件选择器导入到应用沙箱。主打「简洁流畅的本地听歌体验」，深度接入华为 **HDS 设计系统**与沉浸光感，播放器进出采用「一镜到底」共享元素动画。

## 2. 核心功能（FR-01 ~ FR-34）

| 领域 | 功能 | 状态 |
|------|------|------|
| 音乐库 | 导入（DocumentViewPicker）、列表/搜索、空状态引导 | ✅ |
| 播放 | 播放控制、迷你播放器+一镜到底、播放器页、歌词（含翻译/明暗自适应/手动滑动）、封面抽取与缓存 | ✅ |
| 歌单 | 自建歌单（建/删/改名/加歌/移出/播放全部/拖拽排序） | ✅ |
| 歌曲操作 | 长按选项栏（替代右侧「更多」按钮）、详情半模态面板（含年代）、添加到歌单半模态面板 | ✅ |
| 系统集成 | 锁屏/通知中心媒体控制、投播（Cast）、桌面播控卡片、后台持续播放 | ✅ |
| 设计 | HDS 沉浸光感、智感握姿底栏自适应、主题（系统/浅/深） | ✅ |
| 元数据 | C++ NAPI 原生解析（FLAC/MP3/MP4）+ MediaKit 双路、年代全链路解析 | ✅ |
| 设置 | 设置主页+子页、清空历史、版本信息、隐私政策、开发者跳转 | ✅ |
| 基础设施 | 响应式封面组件（CoverImageView）、IDataSource 懒加载、数据备份恢复 | ✅ |
| 开发辅助 | Python 验证脚本（C++/歌词解析器离线验证） | ✅ |

## 3. 技术架构

```
┌──────────────────────────────────────────────────────────────┐
│                      ArkTS / ArkUI 前端                       │
│  HdsNavigation + HdsTabs  │  Navigation + NavPathStack 路由  │
│  11 条 NavDestination 路由（route_map.json）                 │
├──────────────────────────────────────────────────────────────┤
│  业务层        │ LocalLibrary / Mine / PlayerPage / Settings  │
│                │ SettingsCategory / About / PrivacyPolicy    │
│                │ Favorites / Playlists / PlaylistDetail       │
│                │ PlayHistory / ManageSongs                    │
│  组件层        │ PlayerInfo / Lyrics / LrcView / CoverImageView│
│                │ ControlArea / TopArea / SongDetailSheet       │
│                │ AddToPlaylistSheet / MusicInfo               │
│  数据层        │ MusicStore（单例）│ SongDataSource            │
│                │ SongItemBuilder │ SettingsStore              │
│  工具层        │ AudioRendererController │ AVSessionController │
│                │ AudioMeta（MediaKit+NAPI 双路）│ CoverCache   │
│                │ EmbeddedLyricReader │ ThemeManager │ Logger   │
├──────────────────────────────────────────────────────────────┤
│              C++ NAPI 原生层（libnative_module.so）           │
│  audio_metadata.cpp: FLAC/MP3/MP4 真实元数据解析（兜底路径）  │
│  napi_init.cpp: NAPI 模块注册                                │
└──────────────────────────────────────────────────────────────┘
```

## 4. 权限（最小化，3 项）

| 权限 | 用途 | 时机 |
|------|------|------|
| `KEEP_BACKGROUND_RUNNING` | 后台持续播放 | inuse |
| `INTERNET` | 关于页网页跳转 / 投播设备网络发现 | always |
| `GET_NETWORK_INFO` | 查询网络状态 | always |

> 无 `READ_MEDIA`/`WRITE_MEDIA`/`DETECT_GESTURE` — 歌曲经 DocumentViewPicker 选择后拷入沙箱，不访问系统媒体库。

## 5. 构建与验证状态

| 项 | 状态 |
|------|------|
| `bash build_hap.sh` 产出签名 HAP | ✅ BUILD SUCCESSFUL |
| `harmonyos-reviewer` 审查 | ✅ 0 ERROR / 0 WARNING |
| C++ 解析器真实音频验证（g++ harness） | ✅ 3 个真实文件 + 5 个合成样本 A/B 对照 |
| C++ 内存安全（P0×6 + P1 修复） | ✅ 全部修复（size_t + uint64 边界校验） |
| ArkTS 红线（build 首语句/get 访问器等） | ✅ 零复现 |
| 权限与 README 一致性 | ✅ 3 项逐项核对一致 |

产物路径：`entry/build/default/outputs/default/entry-default-signed.hap`

## 6. 文档体系

| 文档 | 路径 | 说明 |
|------|------|------|
| README | `README.md` | 用户/开发者入口文档 |
| CHANGELOG | `CHANGELOG.md` | 版本演进日志 |
| PRD | `docs/PRD_Lumio_Music.md` | 产品需求文档（FR-01~FR-34） |
| 模块拆解 | `docs/功能模块拆解表.md` | 模块→文件映射（A~W 共 23 个一级模块） |
| 审查报告 1 | `docs/代码审查报告_PRD落地.md` | PRD 落地批次（P0×6/P1×10/P2×13） |
| 审查报告 2 | `docs/代码审查报告_第二轮增强.md` | 第二轮增强（P0×3/P1×7/P2×11） |
| 实施计划 1 | `docs/实施计划_PRD落地.md` | W1~W5 + 第三轮 F1~F7 |
| 实施计划 2 | `docs/实施计划_第二轮增强.md` | A~E + 第三轮交互打磨 |
| C++ 验证 | `docs/C++解析器真实音频验证.md` | 真实音频 + 合成样本验证报告 |

## 7. 已知限制

- **智感握姿主动感知**：6.1.1 SDK 无 `@kit.MultimodalAwarenessKit`，仅底栏布局自适应生效。
- **空间音频 / 多频段 EQ**：`setSpatializationEnabled` 需系统权限，多频段 EQ 无公开 API，设置页仅只读展示。
- **歌单云同步**：无账号体系，仅支持本地歌单（含手动拖拽排序）。
- **音频格式真机矩阵**：C++ 解析器已做「失败回退文件名」兜底不崩，冷门编码分支需真机复验。
