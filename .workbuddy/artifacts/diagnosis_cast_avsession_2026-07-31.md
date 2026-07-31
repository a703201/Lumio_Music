# 投播版权提示 vs 播控失效 — 架构诊断

> 诊断对象：Lumio Music（本地音乐播放器，HarmonyOS 6.1.1 / API 24）
> 结论：**"投播内容受版权加密保护"不会导致控制中心播控组件失效**，二者是解耦的两套子系统。

## 1. 两套子系统各自是什么

| 子系统 | 入口/驱动 | 代码位置 |
|--------|-----------|----------|
| 投播（Cast） | 播放页右上角系统组件 `AVCastPicker`（`@kit.AVSessionKit`）→ CastEngine 把"可投流"推到远端设备 | `TopAreaComponent.ets:37` |
| 播控（控制中心/锁屏媒体卡片） | 本地 `AVSession` 经 metadata / playbackState 驱动 | `AVSessionController.ets`（`createAVSession` + `activate` + `setAVMetadata` + `setPlayState` + `registerSessionListeners`） |

`AVCastPicker` 与 `AVSession` 同属 `@kit.AVSessionKit`，但**运行时互不写状态**：CastEngine 拒绝投播只在投播通道弹提示，它不会调用 `activate/deactivate`，也不触碰已激活的本地会话。所以投播失败 ≠ 播控不可用，没有因果。

## 2. 为什么本地音乐会报"版权加密保护"

播放内核 `AudioRendererController`（类名误导，实际用 `media.AVPlayer`）通过 `fdSrc = { fd: file.fd }` 播放本地文件。
CastEngine 需要"远端可拉取的媒体"（http / HLS 等），而 `fdSrc` 是进程内文件句柄、无法被远端设备重开，系统遂以 **"受版权加密保护"兜底替代"源不支持投播"** —— 这是误导措辞，本地 MP3/FLAC 无 DRM。

## 3. 播控真正失效的排查清单（按匹配度排序）

1. **监听注册竞态（高危，最匹配"无法调用"）**：`registerSessionListeners()` 仅在 `initAVSession`（controller 已存在时）与 `bindAudioRendererController`（AVSession 已存在时）调用；构造顺序下二者常不同时成立 → 监听永不注册 → 系统卡片 play/pause/seek 指令**无响应（仅展示、不可控）**。
2. **AVSession 创建/激活失败**：`initAVSession` 中 `createAVSession/activate` 抛错即 return，`this.AVSession` 恒 undefined，后续 setAVMetadata/setPlayState/setProgressState 因 `if(this.AVSession)` 全失效 → 卡片不显示。查日志 `AVSession create/activate failed`。
3. **锁屏被关**：设置里"锁屏/状态栏控制"关掉 → `setLockScreenControl(false)` → `this.AVSession.deactivate()` → 卡片消失（默认 true，仅切换时触发）。
4. **playbackState 未设置**：`fdSrc` 打开失败（仅日志）或 AVPlayer error，无 `setPlayState(true)` → 无状态卡片。
5. **未真正播放**：`loadAndPlay` 失败则无 `stateChange/timeUpdate`，进度与状态不更新。

## 4. 处置建议

- **本地播放器无需投播**：建议移除或按 `@State castEnabled` 条件隐藏 `AVCastPicker`，消除误导提示。
- 若要真正支持投播：需本地 HTTP 媒体服务（或 `url` 替代 `fdSrc`）提供可投源 + 通过会话注册可投资产，工作量大，MVP 不宜。
- 顺带修监听竞态：`bindAudioRendererController` 在 AVSession 激活完成后再 `registerSessionListeners`；播放前显式 `setAVPlaybackState({state})`。

## 5. developer 后续改动清单

- `TopAreaComponent.ets`：移除或条件隐藏 `AVCastPicker`。
- `AVSessionController.ets`：修复监听竞态；补 activate 结果日志；播放前显式 setPlaybackState。
- `AudioRendererController.ets`：`fdSrc` 失败显式报错；`start()` 确保 `setPlayState(true)`。
- `SettingsStore.ets`：保持默认 true，可在 `init` 末尾 `setLockScreenControl(true)` 兜底激活。
