# HM_Player · PRD 落地实施计划

> 规划角色：harmonyos-pm ｜ 依据：`docs/PRD_HM_Player.md` + `docs/功能模块拆解表.md` + 工程现状源码
> 目标版本：在 v2.1.0 基础上完成 5 项 PRD 改进，产出可上架/可继续迭代的工程增量。

## 1. 范围与验收总览

| 编号 | 工作流 | 验收标准 | 优先级 |
|---|---|---|---|
| W1 | C++ 原生音频元数据解析 | `parseAudioMetadata` 能解析 FLAC/MP3/MP4 的标题/艺术家/专辑/时长/采样率/声道；`AudioMetaReader` 接入 NAPI 作为 MediaKit 回退 | P1 |
| W2 | 自建播放列表 Playlist | 「我的」可建/删歌单、查看歌单、一键播放、向歌单加歌；接入导航 | P1 |
| W3 | 状态与存储治理 | 收藏统一收口到 `MusicStore`，不再写入 `PreferencesUtil.formIds`；Favorites 页与锁屏收藏读 `MusicStore` | P0 |
| W4 | README + 文档更新 | README 权限表=实际 3 权限；C++/Find/歌单状态与已知限制同步；PRD/拆解表状态回写 | P1 |
| W5 | 关键技术风险 | `promptAction.showToast`/`getContext` 等弃用 API 迁移至 `UIContext`；主动握姿标注为已知限制 | P2 |

## 2. 模块改动点（按文件）

### W1 C++ 原生解析
- `entry/src/main/cpp/audio_metadata.h`：保留 `AudioMetadata` 结构（title/artist/album/durationMs/sampleRate/channels）。
- `entry/src/main/cpp/metadata_parser.cpp`（新增）：实现 `parseFlac` / `parseMp3` / `parseMp4` 真实解析。
- `entry/src/main/cpp/audio_metadata.cpp`：`parseAudioMetadata` 按扩展名/魔数分发到上述解析，失败回退文件名。
- `entry/src/main/cpp/CMakeLists.txt`：新增 `metadata_parser.cpp`。
- `entry/src/main/ets/utils/AudioMeta.ets`：`AudioMetaReader.read` 先试 MediaKit，失败时再用 `NativeUtils.parseAudioMetadata` 补充（NAPI 路径）。

### W2 播放列表
- `entry/src/main/ets/services/MusicStore.ets`：已有 `addPlaylist/deletePlaylist/getPlaylistSongs/playlists`，新增 `removeSongFromPlaylist`。
- `entry/src/main/ets/pages/Playlists.ets`（新增）：歌单列表 + 创建对话框 + 删除 + 进入详情。
- `entry/src/main/ets/pages/PlaylistDetail.ets`（新增）：歌曲列表 + 播放全部（`AudioRendererController.setQueue`）+ 移除 + 加歌（从库选择）。
- `entry/src/main/resources/base/profile/route_map.json`：注册 `Playlists`/`PlaylistDetail`。
- `entry/src/main/ets/pages/Mine.ets`：新增「我的歌单」入口。

### W3 存储治理
- `entry/src/main/ets/utils/AVSessionController.ets`：收藏状态改读/写 `MusicStore`（按 song.id），移除 `PreferencesUtil.getFormIds` 收藏用法；`setAVMetadata` 的 `assetId` 改用 `song.id`。
- `entry/src/main/ets/pages/Favorites.ets`：数据源改为 `MusicStore.getFavoriteSongs()`。

### W4 文档
- `README.md`：权限表、技术栈 C++ 描述、已知限制、发现页/歌单状态。
- `docs/PRD_HM_Player.md` / `docs/功能模块拆解表.md`：回写完成状态。

### W5 API 迁移
- 全局检索 `promptAction.showToast` / `getContext()` 弃用用法，迁移到 `this.getUIContext().getPromptAction().showToast(...)`；无 `UIContext` 上下文的工具类维持原样并标注。

## 3. 里程碑

| 阶段 | 内容 | 产出 |
|---|---|---|
| M1 | W3 存储治理（阻断性风险优先） | 收藏统一、Favorites/锁屏联调 |
| M2 | W1 C++ 原生解析 + 接入 | NAPI 真解析可用 |
| M3 | W2 播放列表 UI + 导航 | 歌单可建可播 |
| M4 | W4 README + W5 API 迁移 | 文档与告警收敛 |
| M5 | 代码审查（harmonyos-reviewer）+ 文档回写 | 审查报告 + 整改 |

## 4. 风险与对策
- **C++ 真机/模拟器无法在本环境出包**：解析逻辑以「失败回退文件名」兜底，保证不崩；最终需在 DevEco 真机验证格式兼容。
- **收藏 assetId 语义**：原为队列索引（易漂移），改为 song.id，需同步 `toggleFavorite` 与锁屏回写。
- **歌单 UI 范围**：首版聚焦「建/删/查看/播放/加歌」，暂不做拖拽排序与云同步。
- **API 迁移范围**：仅迁移有明确 `UIContext` 上下文的页面/组件；工具类静默注解，避免误改。
