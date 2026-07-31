# 日志规范统一迁移到 hilog — 完成总结

## 目标
把分散的 `console.error`、裸 `hilog` 调用统一收敛到项目已有的 `Logger` 封装，实现全工程唯一日志出口。

## 关键修复：Logger 实现 bug
`utils/Logger.ets` 原实现有隐藏缺陷：
```ts
// 旧（有 bug）：args 被整体当单个参数传入，format 又写死成 '%{public}s, %{public}s'
hilog.error(Logger.domain, Logger.prefix, Logger.format, args);
```
导致 `Logger.error(TAG, 'msg')` 输出成脏的 `[TAG, msg]`。
```ts
// 新（修复）：多参数 join 成单条消息，单占位符
hilog.error(Logger.domain, Logger.prefix, '%{public}s', args.join(' '));
```
统一 `domain = 0xFF00`、`prefix = 'MusicPlay'`。

## 改动清单
| 文件 | 改动 |
|---|---|
| `entry/src/main/ets/utils/Logger.ets` | 重写实现，修 args 未展开 bug |
| `entry/src/main/ets/services/MusicStore.ets` | 8 处 `console.error` → `Logger.error` + 补 import |
| `entry/src/main/ets/utils/SettingsStore.ets` | 4 处 `console.error` → `Logger.error` + 补 import |
| `entry/src/main/ets/utils/ThemeManager.ets` | 1 处 `console.error` → `Logger.error` + 补 import |
| `entry/src/main/ets/pages/LocalLibrary.ets` | 1 处 `console.error` → `Logger.error` + 补 import |
| `entry/src/main/ets/pages/ManageSongs.ets` | 1 处 `console.error` → `Logger.error` + 补 import |
| `entry/src/main/ets/pages/Settings.ets` | 3 处 `console.error` → `Logger.error`（90/94 行 `err` 对象转成 `(err as Error).message`）+ 补 import |
| `entry/src/main/ets/entryability/EntryAbility.ets` | 14 处裸 `hilog` → `Logger`；删 hilog import 与 `const DOMAIN` |
| `entry/src/main/ets/entrybackupability/EntryBackupAbility.ets` | 2 处裸 `hilog` → `Logger`；删 hilog import 与 `const DOMAIN` |
| `MediaService/src/main/ets/utils/Logger.ets` | 同步修同样的 args 未展开 bug，与 entry 模块对齐 |

## 验证结果
- 全工程（entry + MediaService）`console.*` **零残留**
- 裸 `hilog.` 调用**仅存在于两份 `Logger.ets` 封装内部**，业务代码全部走 `Logger`
- harmonyos-reviewer 复扫：**🔴 ERROR 0 ｜ 🟡 WARNING 0**（2 个 INFO 为 `componentSnapshot` 误报，已确认无此调用）

## 备注
- `MediaService` 模块与 `entry` 各有一份 `AudioRendererController.ets`（UI 实际引用 entry 副本）。本次仅统一了两份 `Logger`，若该模块确为冗余，后续可整体清理，避免双份维护。
- 请在 DevEco Studio 重新出包验证真机日志输出（沙箱 hvigor 末段会被 `[safe-delete]` 守卫拦截，无法在本环境产出 HAP）。
