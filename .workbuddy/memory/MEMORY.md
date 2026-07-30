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
