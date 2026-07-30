# HM_Player 项目长期记忆

## 关键 SDK 行为（HarmonyOS 6.1.1 / API 24，本机 DevEco SDK）

### ArkTS 编译规则
- **`build()` 与 `@Builder` 方法体内，首条语句不能是 `const`/`let` 声明**。例如 `const colors = ThemeManager.getColors();` 会报 `10905209 Only UI component syntax` / `10905210 one root node`（错误会级联到后续 `@Builder`/`build` 并报到参数行或 opener 行，极具误导性）。正确写法：行内调用 `ThemeManager.getColors().xxx`（About/Favorites 早已如此）。
- `CustomDialogController` / `DialogAlignment` 是 `build-tools/ets-loader/declarations/` 下的**全局环境声明**，不从 `@kit.ArkUI` 导出（误 `import` 报 10311006）。`CustomDialogController` 在框架 `forbiddenUseStateType` 列表，**禁止 `@State` 修饰**，只能作普通成员 `new CustomDialogController({ builder: this.xxxBuilder, autoCancel: true, alignment: DialogAlignment.Center })`。
- `AlertDialog.show({...})` 的联合类型**不支持 `builder`/`radios`**（无自定义内容能力）；自定义单选弹窗改用 `@CustomDialog struct` + `CustomDialogController`（builder 传 `@Builder` 方法）。

### 构建命令（本机验证可用）
- `DEVECO_SDK_HOME="D:/Program Files/Huawei/DevEco Studio/sdk"`，用托管 node `C:/Users/a7032/.workbuddy/binaries/node/versions/22.12.0/node.exe` 跑 `D:/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.js --mode module -p product=default assembleHap`。
- product=`default`，签名已就绪，SDK 版本 `6.1.1(24)`。

### 沙箱注意
- 本会话迭代构建多次后，沙箱 `[safe-delete]` 守卫（turn 级、阈值 50 文件）会拦截 hvigor 的 `.cxx`/cmake 缓存/报告批量清理，导致 assembleHap 在末段 FAIL，**无法在本会话产出 HAP**。该守卫只拦 hvigor 子进程批量删除；用户直接在 DevEco 构建正常。代码层编译请用 BuildNativeWithCmake/BuildNativeWithNinja/CompileArkTS 三段是否 Finished 判定。
