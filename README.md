# HM Music · 鸿蒙音乐播放器

<img width="200" height="200" alt="logo" src="https://github.com/user-attachments/assets/bec472ea-0320-4c85-85a5-1c898d9d9aee" />

一款运行在 **HarmonyOS** 平台的本地音乐播放器，基于 **ArkTS + ArkUI + C++ Native** 开发。
主打简洁流畅的本地听歌体验，并已全面接入 **HDS 设计系统** 与 **沉浸光感**，播放器进出采用 **一镜到底** 共享元素动画。

> 完整版本演进见 [CHANGELOG.md](./CHANGELOG.md)。

---

## 功能特性

### 音乐库（核心）
- 由「歌曲」与「音乐库」两个页面 **合并为统一入口**（音乐库页）。
- **导入音乐**：通过系统文件选择器将本地音频导入曲库（导入功能已从原歌曲页迁移至此）。
- **搜索**：顶部搜索栏实时过滤歌曲。
- 歌曲列表、收藏高亮、播放中高亮状态一目了然。
- 空状态提示 + 引导导入。

### 播放体验
- 播放控制：播放 / 暂停 / 上一首 / 下一首。
- **迷你播放器**：底部悬浮卡片显示当前播放歌曲，点击进入播放器页。
- **一镜到底动画**：迷你封面与播放器页通过 `geometryTransition` 共享元素 + `interpolatingSpring` 曲线，实现进出场的顺滑形变。
- **播放器页**：封面大图、歌词显示、播放进度与控制台。

### 我的（个人中心）
- 列表支持 **上下滑动**（Scroll 容器）。
- 听歌统计面板：歌曲数 / 收藏数 / 最近播放数。
- 入口：收藏列表、播放历史、设置。
- 头像呼吸灯、数字滚动等微动效。

### 设置
- **清空播放历史**：一键清除最近播放记录。
- **版本信息**：跳转关于页查看版本与功能特色。
- **开发者**：点击跳转开发者简历网页 `https://www.a703201sworld.top/resume/`（开发者署名：何宇翔）。

### 沉浸与握姿适配
- **HDS 设计系统**：根导航 `HdsNavigation` + 主布局 `HdsTabs`，底部标签栏采用自定义沉浸式样式。
- **沉浸光感**：底部栏 `barFloatingStyle` 启用 `systemMaterialEffect`（ADAPTIVE 材质），与系统视觉融合。
- **智感握姿（底栏自适应）**：底部栏 `adaptToHandedness: true`，根据握持姿态自适应布局。

---

## 技术栈

| 维度 | 选型 |
|------|------|
| 前端框架 | ArkTS + ArkUI（声明式） |
| 原生模块 | C++ (NAPI) 音频元数据解析 |
| 设计系统 | HDS（`@kit.UIDesignKit`） |
| 路由 | Navigation + NavPathStack（HdsNavigation / NavDestination） |
| 开发工具 | DevEco Studio |
| 目标平台 | HarmonyOS **6.1.1 (API 24)**，兼容 6.1.0(23) |
| 目标设备 | phone |

---

## 架构与项目结构

### 导航模型
- `Index.ets`：`HdsNavigation` 根容器，承载 `NavPathStack`，首屏 push `Layout`。
- `Layout.ets`：`HdsTabs` 主布局，内含两个 Tab 子组件 —— **音乐库**（`LocalLibrary`）、**我的**（`Mine`），以及底部的迷你播放器（一镜到底共享元素）。
- **推送页（NavDestination）**：`PlayerPage`、`Settings`、`About`、`Favorites`、`PlayHistory`，通过 `route_map.json` 注册并以 `pushPathByName` 入栈。
- **Tab 子组件**（非独立页面）：`LocalLibrary`、`Mine` 直接作为 `HdsTabs` 的 `TabContent` 内容。

### 目录结构

```
HM_Player/
├── AppScope/                     # 应用级配置（包名、版本、图标）
├── entry/src/main/
│   ├── ets/
│   │   ├── entryability/
│   │   │   └── EntryAbility.ets  # 应用入口 Ability
│   │   ├── pages/
│   │   │   ├── Index.ets         # 入口：HdsNavigation 根容器
│   │   │   ├── Layout.ets        # 主布局：HdsTabs + 迷你播放器（一镜到底共享元素）
│   │   │   ├── LocalLibrary.ets  # 音乐库 Tab（合并 Songs+Moment，含导入）
│   │   │   ├── Mine.ets          # 我的 Tab（可滚动）
│   │   │   ├── PlayerPage.ets    # 播放器页（一镜到底目标）
│   │   │   ├── Settings.ets      # 设置：清空历史 / 版本 / 开发者
│   │   │   ├── About.ets         # 关于
│   │   │   ├── Favorites.ets     # 收藏列表
│   │   │   ├── PlayHistory.ets   # 播放历史
│   │   │   └── Find.ets          # 发现页（预留，未接入导航）
│   │   ├── services/
│   │   │   └── MusicStore.ets    # 全局状态与曲库数据（单例）
│   │   ├── models/               # 数据模型（SongItem 等）
│   │   ├── components/           # 通用组件
│   │   └── common/utils/         # 工具类（断点系统、颜色转换等）
│   ├── resources/base/
│   │   ├── media/                # 资源（含 ic_hm_* 图标）
│   │   └── profile/              # main_pages / route_map 等配置
│   └── module.json5              # 权限与 Ability 声明
├── build-profile.json5           # 编译 / SDK 版本
├── cpp/                          # C++ 原生模块（音频元数据）
└── oh-package.json5
```

---

## 设计亮点

- **一镜到底动画**：迷你封面 `geometryTransition('player_cover', { follow: true })` 与播放器页根节点共享同一 ID，进出场 `push/pop` 均包在 `animateTo(interpolatingSpring(0,1,328,36))` 中，过渡连续无跳变。
- **HDS 沉浸光感**：`barFloatingStyle({ systemMaterialEffect: { materialType: ADAPTIVE, materialLevel: ADAPTIVE } })`，底部栏随系统材质自适应。
- **智感握姿（底栏自适应）**：`barFloatingStyle({ adaptToHandedness: true })`，底部栏布局跟随握持姿态。
- **页面合并与减负**：原「歌曲」+「音乐库」合并为单一音乐库页，导入功能下沉至音乐库；**移除不可用的扫描功能**，设置页**移除不可调整的播放模式项**，界面更聚焦。

---

## 权限说明

`module.json5` 中声明了以下权限：

| 权限 | 用途 | 时机 |
|------|------|------|
| `ohos.permission.READ_MEDIA` | 读取本地音乐文件 | inuse |
| `ohos.permission.WRITE_MEDIA` | 导入 / 写入媒体 | inuse |
| `ohos.permission.KEEP_BACKGROUND_RUNNING` | 后台持续播放 | inuse |
| `ohos.permission.DETECT_GESTURE` | 智感握姿（声明预留；主动监听需更高 SDK） | inuse |

---

## 构建与运行

```bash
# 使用 DevEco Studio 打开本项目
# Build > Build Hap(s)/APP(s) > Build Hap(s)
# 或命令行：
hvigorw assembleHap --mode module -p module=entry@default -p product=default -p buildMode=release
```

> 需安装 **HarmonyOS 6.1.x SDK（API 23 / 24）**。当前工程已在 DevEco Studio + 6.1.1 SDK 下验证可成功产出 release HAP。

---

## 已知问题与限制

- **智感握姿主动感知**：当前 6.1.1 SDK 未内置 `@kit.MultimodalAwarenessKit`，因此仅底栏 `adaptToHandedness` 的**自适应布局**生效；若需「主动监听左右手握持」事件（`motion.on('holdingHandChanged')`），需升级到包含该 Kit 的更高版本 SDK。
- **API 弃用告警**：`promptAction.showToast`、`getContext` 等存在 API 24 弃用告警，不影响出包；后续可统一迁移至 `UIContext` 对应接口以达成零告警。
- **发现页（Find.ets）**：已完成基础骨架（最近播放 / 推荐卡片），暂未接入导航，未对用户暴露。
- **音频格式兼容**：播放能力依赖 C++ Native 层，具体格式支持建议在真机验证。

---

## 许可证

仅供学习交流使用。
