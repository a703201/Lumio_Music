# HM_Player 长期规范与架构事实

## ⚠️ ArkTS 红线（违反即编译失败/运行时崩溃）
- `build()`/`@Builder` 体首条语句不能是 `const`/`let`（报 "Only UI component syntax"/"one root node"，错误级联误导）。改行内调用。
- `CustomDialogController`/`DialogAlignment`/`NavPathStack`/`NavDestinationContext` 是全局环境声明，勿从 `@kit.ArkUI` import，裸用。
- `CustomDialogController` 禁 `@State`，只能普通成员 `new CustomDialogController({...})`。
- `@Component`/`@CustomDialog` 上的**普通 `get` 访问器被 ArkUI 变换器整段丢弃**（运行时 `this.x`=undefined→崩溃）。改用普通方法（如 `getThemeColors(): ColorTokens`）。`@State`/`@StorageProp` 访问器保留。
- 禁裸 `console.*`/`hilog`；统一 `utils/Logger.ets`（`Logger.debug/info/warn/error(...args: string[])`，domain 0xFF00 / prefix 'MusicPlay'）。

## 主题与状态响应式
- `ThemeManager` 暴露 `static lightColors/darkColors`(ColorTokens)。页面用 `@StorageProp('isDark') isDark`+普通方法 `getThemeColors()` 取色触发重渲染；勿用 `ThemeManager.getColors()`（内部非响应式读 AppStorage）。
- 窗口已全屏(`setWindowLayoutFullScreen`)；沉浸只需 `expandSafeArea([SYSTEM],[TOP])`+保留 `topHeight`。
- 封面：列表/`getMark()/getLabel()` 返回 `Resource|PixelMap`，读非响应式 `CoverCache` 单例；靠 `AppStorage('coverRefreshToken')`+`@Watch` 刷新。⚠️ 仅 `PlayerInfoComponent` 监听——**列表页须自加 `@StorageProp('coverRefreshToken') @Watch` 才能在导入/重启后重绘封面**。

## SDK 行为与权限（API 24 / 6.1.1）
- 投播(`AVCastPicker`/`AVCastController`,`@kit.AVSessionKit`)≠播控(`AVSession`)。本地文件经 `AVCastController`+独立 fd 投远端；远程控制走 `sendControlCommand({command})`（无直接 play/pause）。设备切换 `AVSession.on('outputDeviceChange')`。`off` 对 playNext/playPrevious 类型重载缺失，经 `(castController as ESObject)?.off(...)` 透传。
- 权限已最小化：`KEEP_BACKGROUND_RUNNING`+`INTERNET`+`GET_NETWORK_INFO`；删 `READ/WRITE_MEDIA`（歌曲来自 preferences+DocumentViewPicker+沙箱，无媒体库访问）。
- 空间音频：`isSpatializationEnabledForCurrentDevice()` 只读；`set` 需系统权限，三方不可做开关。多频段 EQ：无公开 API。
- 桌面卡片：`@kit.FormKit` FormExtensionAbility+`formProvider.updateForm`+`postCardAction`（form 进程独立，回控经 EntryAbility）。

## 构建与沙箱
- 构建：`DEVECO_SDK_HOME=.../DevEco Studio/sdk`，托管 node `.../node/versions/22.12.0/node.exe` 跑 `.../hvigor/bin/hvigorw.js --mode module -p product=default assembleHap`。
- 沙箱 `[safe-delete]` 守卫拦截 hvigor 清理→本会话无法产出 HAP，需在 DevEco 直接构建验证。

## 封面/歌词/元数据管线
- 封面：`CoverCache` 单例经 `AVMetadataExtractor.fetchAlbumCover()` 抽取，启动/导入后 `preload`+bump `coverRefreshToken`。
- 歌词：`EmbeddedLyricReader` 解析 FLAC(VORBIS LYRICS/UNSYNCEDLYRICS)、MP4(`©lyr` atom)、MP3(ID3v2 USLT)；`LrcUtils.parseLrcLyric` 按时间戳拆+LRC/KRC rawfile 兜底。⚠️ MP4 `©lyr` 须做 BOM/UTF-16 探测(UTF-16 LE/BE/UTF-8)，否则 UTF-16 歌词解析为空。
- 歌词渲染：`LrcView`(Canvas) 文字色固定；播放页背景模糊在 `PlayerInfoComponent.getImageColor()` 经 `effectKit` 取色+预模糊。
