# 实施计划 · PRD 落地

> 版本：v2.3.0 | 创建：2026-08-05

## 一、里程碑规划

| 里程碑 | 日期 | 内容 | 状态 |
|--------|------|------|------|
| M1 | 7月上旬 | 基础播放框架 | ✅ |
| M2 | 7月5日 | UI 视觉升级 | ✅ |
| M3 | 7月30日 | HDS 沉浸重构 + C++ 解析器全线 | ✅ |
| M4 | 8月5日 | 交互打磨（FR-25~34） | ✅ |
| M5 | 8月6日 | NFR 品质工程 + 单元测试 | ✅ |

## 二、功能需求实施映射

### M4（交互打磨）
| FR | 功能 | 核心文件 | 状态 |
|----|------|---------|------|
| FR-25 | 长按选项栏 | 5 个页面 bindContextMenu | ✅ |
| FR-26 | 歌曲详情面板 | SongDetailSheet.ets | ✅ |
| FR-27 | 添加到歌单面板 | AddToPlaylistSheet.ets | ✅ |
| FR-28 | 年代全链路解析 | AudioMeta.ets + C++ | ✅ |
| FR-29 | 歌词手动滑动 | LrcView.ets | ✅ |
| FR-30 | 迷你播放器真实封面 | Layout.ets | ✅ |
| FR-31 | 设置子页 | SettingsCategory.ets | ✅ |
| FR-32 | 隐私政策页 | PrivacyPolicy.ets | ✅ |
| FR-33 | 响应式封面组件 | CoverImageView.ets | ✅ |
| FR-34 | 开发辅助脚本 | tools/ 4 个 Python 脚本 | ✅ |

### M5（NFR 品质工程）
| 项 | 文件 | 状态 |
|----|------|------|
| C++ 健壮性 | audio_metadata.cpp | ✅ |
| NAPI 超长路径 | napi_init.cpp | ✅ |
| NAPI 类型声明 | cpp/types/ | ✅ |
| 版本对齐 | app.json5 / CHANGELOG / PRD | ✅ |
| 空间音频移除 | SettingsCategory.ets | ✅ |
| Logger 增强 | Logger.ets | ✅ |
| readFile 优化 | audio_metadata.cpp | ✅ |
| 错误态 UI | LocalLibrary.ets / MusicStore.ets | ✅ |
| 单元测试 | LocalUnit.test.ets | ✅ |

## 三、验收标准

- `bash build_hap.sh` BUILD SUCCESSFUL
- harmonyos-reviewer 0 ERROR / 0 WARNING
- 全 34 个 FR 功能可演示
- 单元测试通过
- 文档与代码一致
