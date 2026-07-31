# HM_Player 项目长期记忆

## 关键 SDK 行为（HarmonyOS 6.1.1 / API 24，本机 DevEco SDK）

### ArkTS 编译规则
- **`build()` 与 `@Builder` 方法体内，首条语句不能是 `const`/`let` 声明**。例如 `const colors = ThemeManager.getColors();` 会报 `10905209 Only UI component syntax` / `10905210 one root node`（错误会级联到后续 `@Builder`/`build` 并报到参数行或 opener 行，极具误导性）。正确写法：行内调用 `ThemeManager.getColors().xxx`（About/Favorites 早已如此）。
- `CustomDialogController` / `DialogAlignment` / `NavPathStack` / `NavDestinationContext` 都是 `build-tools/ets-loader/declarations/` 下的**全局环境声明**，不从 `@kit.ArkUI` 导出（误 `import` 报 10311006 / 10505001）。切勿 import，直接裸用（`pathStack: NavPathStack = new NavPathStack()`、`.onReady((context: NavDestinationContext) => {...})`）。
- `CustomDialogController` 在框架 `forbiddenUseStateType` 列表，**禁止 `@State` 修饰**，只能作普通成员 `new CustomDialogController({ builder: this.xxxBuilder, autoCancel: true, alignment: DialogAlignment.Center })`。

### ⚠️ ArkUI 会丢弃 @Component/@CustomDialog 类上的普通 `get` 访问器（致命）
- 在 `@Component`/`@CustomDialog` struct 里写 `private get colors() { return this.isDark ? ThemeManager.darkColors : ThemeManager.lightColors; }` 并在 `build()`/`@Builder` 用 `this.colors.bg` —— **本 SDK 的 ArkUI 状态管理变换器会把这条普通 getter 整段丢弃**（编译产物里 `get colors` 定义消失、`this.colors` 仍被引用），运行时 `this.colors` 为 `undefined` → `Cannot read property bg of undefined` 崩溃（必现，首页 Layout 即崩）。
- **证据**：对比 release 编译产物，全部 8 个页面 + PickerDialog 均 `get colors` 定义数为 0、但 `this.colors` 被大量引用。框架生成的 `@State/@StorageProp/@Link` 访问器（如 `get isDark()`）保留，普通自定义 `get` 不保留。
- **正确做法**：改用**普通方法** `private getThemeColors(): ColorTokens { return this.isDark ? ThemeManager.darkColors : ThemeManager.lightColors; }`，调用处 `this.colors.x` → `this.getThemeColors().x`；方法一定被 emit。`ColorTokens` 从 `ThemeManager` 导出，需在 import 加 `ColorTokens`。方法体内读 `this.isDark`（observed）仍能触发主题响应式重渲染，等效于 getter 的初衷。
- `AlertDialog.show({...})` 的联合类型**不支持 `builder`/`radios`**（无自定义内容能力）；自定义单选弹窗改用 `@CustomDialog struct` + `CustomDialogController`（builder 传 `@Builder` 方法）。

### 主题换肤响应式（关键坑）
- `ThemeManager.getColors()` 内部用 `AppStorage.get('isDark')`，是**非响应式**读取。若页面只在内联 `ThemeManager.getColors().xxx` 取色、且 `@StorageProp('isDark') isDark` 声明后**从未被读取**，则切主题不会触发该页面重渲染 → 表现为「切换深色慢 / 返回页面半黑半不黑」。
- **正确做法（已在全工程落地）**：ThemeManager 暴露 `static get lightColors` / `darkColors`（返回 LIGHT_TOKENS/DARK_TOKENS）；每个页面加 `private get colors() { return this.isDark ? ThemeManager.darkColors : ThemeManager.lightColors; }`（依赖 `@StorageProp('isDark') isDark` 触发重渲染），并把页面内 `ThemeManager.getColors()` 全部替换为 `this.colors`。`@CustomDialog struct` 同样加 `@StorageProp('isDark')` + 同名 getter。
- EntryAbility 已 `setWindowLayoutFullScreen(true)` + `applyToWindow()`（状态栏透明、内容色随主题），全应用窗口本就是全屏，页面「沉浸」只需 `expandSafeArea([SafeAreaType.SYSTEM],[SafeAreaEdge.TOP])` 让内容进安全区、保留 `topHeight` 顶距避让状态栏文字。

### 构建命令（本机验证可用）
- `DEVECO_SDK_HOME="D:/Program Files/Huawei/DevEco Studio/sdk"`，用托管 node `C:/Users/a7032/.workbuddy/binaries/node/versions/22.12.0/node.exe` 跑 `D:/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.js --mode module -p product=default assembleHap`。
- product=`default`，签名已就绪，SDK 版本 `6.1.1(24)`。

### 沙箱注意
- 本会话迭代构建多次后，沙箱 `[safe-delete]` 守卫（turn 级、阈值 50 文件）会拦截 hvigor 的 `.cxx`/cmake 缓存/报告批量清理，导致 assembleHap 在末段 FAIL，**无法在本会话产出 HAP**。该守卫只拦 hvigor 子进程批量删除；用户直接在 DevEco 构建正常。代码层编译请用 BuildNativeWithCmake/BuildNativeWithNinja/CompileArkTS 三段是否 Finished 判定。

### 日志规范（统一出口，长效约定）
- 全工程日志统一走 `utils/Logger.ets` 封装（`Logger.debug/info/warn/error(...args: string[])` → `hilog.xxx(0xFF00, 'MusicPlay', '%{public}s', args.join(' '))`）。domain=0xFF00、prefix='MusicPlay'。**禁止**在业务代码直接 `console.*` 或裸调 `hilog`（EntryAbility/EntryBackupAbility 已迁到 Logger）。
- Logger 实现用 `args.join(' ')` 把多参数拼成单条消息，兼容 `Logger.error(TAG, 'msg')` 与 `Logger.error('msg')` 两种历史调用约定；模块 TAG 进入消息体，不再作为 hilog 的 tag 字段。
- 两份 Logger（entry/ 与 MediaService/）实现已对齐，行为一致。

### 投播（AVCastPicker/AVCastController）与播控（AVSession）架构事实（已实现）
- **投播 ≠ 播控，二者解耦**：`TopAreaComponent.ets:37` 的 `AVCastPicker`（`@kit.AVSessionKit`）走 CastEngine 把媒体投到远端；播控（通知/控制中心/锁屏卡片）由本地 `AVSessionController` 的 `AVSession` 经 metadata/playbackState 驱动。CastEngine 拒绝投播只在投播通道弹提示，**不调用 activate/deactivate，不触碰本地已激活会话**，故"投播内容受版权加密保护"**不会导致播控失效**（诊断结论仍成立）。
- **本地文件可以投播**：经 `avSession.getAVCastController()` 拿到 `AVCastController`，构造 `avSession.AVQueueItem`（`description.fdSrc = { fd }`，用 `fileIo.openSync` 另开独立 fd，与本地播放 `curFile` 解耦），`castController.prepare(item)` → `castController.start(item)` 即可把本地文件投到局域网远端设备。早期"fdSrc 进程内句柄无法被远端重开"的判断是错的——正确做法是在应用侧另开 fd 交给 castController，由 CastEngine 流式推送。
- **投播态远程控制只能走 `AVCastController.sendControlCommand({command})`**：`command ∈ 'play'|'pause'|'stop'|'playNext'|'playPrevious'|'seek'|'setVolume'|...`，`seek`/`setVolume` 需带 `parameter`。`AVCastController` **没有**直接的 `pause()/play()/stop()/seek()` 方法（仅有 `prepare/start/release` + `on/off`）。本地播放控制（onPlay/onPause/onSeek 等）在 `isCasting` 时改发 `sendControlCommand`，非投播时走本地 `AudioRendererController`。
- **设备切换检测**：`AVSession.on('outputDeviceChange', (state, device) => {})`；`device.devices[0].castCategory === avSession.AVCastCategory.CATEGORY_REMOTE && state === avSession.ConnectionState.STATE_CONNECTED` → 开始投播（暂停本地出声）；否则且 `isCasting` → 结束投播并 `audioRendererController.start()` 续播本地。`AVCastPicker` 仅拉起选择面板（其 `onStateChange` 只报面板显隐，不报选了哪台设备）。切回手机：在系统播控/投播面板取消选择远端设备即触发 outputDeviceChange 非远端 → 自动恢复本地。
- **声明与权限**：激活会后 `AVSession.setExtras({ requireAbilityList: ['url-cast'] })`；`module.json5` 需 `ohos.permission.INTERNET` + `ohos.permission.GET_NETWORK_INFO`（局域网 Cast+/DLNA 发现与流传输）。
- **SDK 类型注意（API 24，avsession.d.ts 不在本机 SDK，已对照官方/Gitee interface_sdk-js 核实）**：`DeviceInfo` **无** `supportedProtocols` 字段（只有 castCategory/deviceId/deviceName/deviceType/ipAddress?/providerId?）；`ProtocolType` **无** `TYPE_DLNA`（仅 LOCAL/CAST_PLUS_MIRROR/CAST_PLUS_STREAM）；`AVMediaDescription` 仅 `assetId` 必填，其余可选；`AVFileDescriptor` 在本 SDK 可只给 `{fd}`（同 AudioRendererController 本地播放写法）。
- **监听竞态已修复**：原 `registerSessionListeners()` 在 initAVSession(`if(audioRendererController)`) 与 bindAudioRendererController(`if(AVSession)`) 两处守门，构造顺序下任一未就绪即跳过 → 系统卡片 play/pause/seek 无响应。改为单一 `ensureListenersRegistered()`：仅当 `AVSession && audioRendererController` 同时就绪才注册、`listenersRegistered` 去重；init 收尾与 bind 收尾都调用。
- **投播状态机要点**：`startCast` 置 `isCasting=true` + `audioRendererController.setCastActive(true)`（让本地 AVPlayer 在 'prepared' 后不自动起播、保持静音）+ `pause()` 本地；`setAVMetadata` 末尾若 `isCasting` 则 `castCurrentSong(0)` 自动重投新曲；`stopCast` 释放 castController/独立 fd、`setCastActive(false)`、`start()` 续播并对齐 `castRemotePositionMs`（来自 `castController.on('playbackStateChange')` 回写）。不调用 `castController.release()`（设备断开后系统回收，避免该 method 在部分 SDK 类型中缺失导致编译失败）。
- **`AVCastController.off` 重载缺口（已踩坑，API 24）**：`off` 的类型重载**未声明** `playNext`/`playPrevious`（但 `on` 有，运行时 `off` 支持注销，纯类型缺失）。直接 `castController.off('playNext', cb)` 报 `10505001 No overload matches / not assignable to 'customDataChange'`。修复：对这两个事件经 `(castController as ESObject)?.off('playNext', cb)` 透传（`ESObject` 是 ArkTS 内置类型，编译期动态调用，无需 import）。`on`/`off` 的 may-throw WARN 用 `try/catch` 包裹清除。
