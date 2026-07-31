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

### 投播（AVCastPicker）与播控（AVSession）架构事实（已诊断）
- **投播 ≠ 播控，二者解耦**：`TopAreaComponent.ets:37` 的 `AVCastPicker`（`@kit.AVSessionKit`）走 CastEngine 把"可投流"推到远端；播控（通知/控制中心/锁屏卡片）由本地 `AVSessionController` 的 `AVSession` 经 metadata/playbackState 驱动。CastEngine 拒绝投播只在投播通道弹提示，**不调用 activate/deactivate，不触碰本地已激活会话**，故"投播内容受版权加密保护"**不会导致播控失效**。
- 本地音乐经 `AudioRendererController` 用 `media.AVPlayer` + `fdSrc({fd})` 播放。CastEngine 需要"远端可拉取的媒体"（http/HLS），`fdSrc` 是进程内句柄无法被远端重开，系统遂以"版权加密保护"兜底替代"源不支持投播"——属**误导性措辞，非真实 DRM**。
- **本地播放器无需投播**，`AVCastPicker` 在此是误导入口；建议移除或按 `@State castEnabled` 条件隐藏（仅可投源存在时显示）。
- 真正让播控失效的高危点：`AVSessionController.registerSessionListeners()` 在 initAVSession 与 bindAudioRendererController 两处按需注册，构造顺序下常不同时成立 → 监听永不注册 → 系统卡片 play/pause/seek 无响应（仅展示不可控）；另需排查 AVSession 创建/激活失败日志、notificationLockScreen 被关（false→deactivate）、playbackState 未设置。
