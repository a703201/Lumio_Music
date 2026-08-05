# C++ 原生元数据解析器 · 真实音频验证报告

> 验证目标：`entry/src/main/cpp/audio_metadata.cpp` 的 `parseAudioMetadata`
> 验证方式：用 `g++` 编译 standalone harness（不依赖 NAPI/OH 运行时），对真实音频文件运行解析
> 验证日期：2026-08-05

## 1. 背景

沙箱环境无法产出 HAP，上一轮对 C++ 解析器的修复（P0 内存安全、P1 功能性）只能靠静态审查确认。
本轮用户提供了 3 个真实音频文件，且环境具备 `g++`，因此构建独立验证程序，**真正跑一遍解析器**。

## 2. 方法

1. 将 3 个文件复制为 ASCII 文件名（规避 MinGW 对中文/空格路径的编码问题）：
   - `bet_on_me.flac` ← `Walk off the Earth,D Smoke - Bet On Me.flac`
   - `lose_my_mind.m4a` ← `F1 The Album (Cinematic Edition)/01. Lose My Mind (feat. Doja Cat).m4a`
   - `zhou_shen.flac` ← `周深 - 人是_.flac`
2. 编译：`g++ -std=c++17 test_main.cpp audio_metadata.cpp -o meta_test`
3. 运行 `meta_test` 输出 title / artist / album / duration / sampleRate / channels。

## 3. 验证结果（改动前基线 = 改动后，零回归）

| 文件 | 格式 | title | artist | album | 时长 | 采样率 | 声道 |
|---|---|---|---|---|---|---|---|
| bet_on_me.flac | FLAC | Bet On Me | Walk off the Earth/D Smoke | Bet On Me | 2:52 (172983ms) | 192000 Hz | 2 |
| lose_my_mind.m4a | M4A (iTunes) | Lose My Mind (feat. Doja Cat) | Hans Zimmer | F1 The Album (Cinematic Edition) | 3:29 (209051ms) | 44100 Hz | 2 |
| zhou_shen.flac | FLAC (中文 UTF-8) | 人是_ | 周深 | 人是_ | 4:35 (275428ms) | 44100 Hz | 2 |

### 关键结论
- **FLAC VORBIS_COMMENT 解析正确**：英文、中文 UTF-8 标题/艺术家均能正确提取（验证 P1-2 中文乱码修复持续有效）。
- **M4A iTunes atom 解析正确**：`©nam` / `©ART` / `©alb`（`0xA9`+字母的 4 字节原子名）被正确识别——直接验证了上一轮 P1-1/P1-2 修复（此前 100% 解析不到 M4A 标签）。
- **采样率/声道/时长**合理（含 24/192 高解析 FLAC 与 44.1k M4A）。
- 改动前（仅 P0/P1 修复）与改动后（新增 VBR 时长 + 64-bit largesize）输出**逐字节一致**，证明新代码无回归。

## 4. 本轮 C++ 计划项落地

| 计划项 | 状态 | 说明 |
|---|---|---|
| FLAC/MP4/MP3 真实元数据解析 | ✅ | 接入 `AudioMetaReader` 回退路径（上轮已完成） |
| MP3 VBR 时长估算 (P2-10) | ✅ 已实现 | 解析 Xing/Info 头取总帧数 → 精确时长；缺失时回退 CBR 近似 |
| MP4 64-bit largesize (P2-9) | ✅ 已实现 | atom size==1 时读取后续 8 字节真实长度，递归子 box 起点同步修正 |
| 边界/内存安全 (P0/P1) | ✅ 已验证 | 上轮修复，本轮真实文件零崩溃 |

## 5. 已知验证缺口（非阻断）

- **MP3 / VBR 运行时验证未完成**：3 个样本均为 FLAC/M4A，无 MP3 文件；且环境无 `ffmpeg`，无法临时生成 VBR MP3。
  - 缓解：VBR 逻辑遵循 Xing/Info 规范（side info 偏移按 MPEG 版本/层/声道数计算，帧数×每帧采样÷采样率），CBR 路径已在上轮验证。
  - 建议：在真机复验清单中加入一个 VBR MP3 样本（如 LAME `-q 0` 编码），确认 Xing 头解析与精确时长。
- **封面/内嵌歌词抽取**：§5.3 To-Be 曾提及 C++ 抽取封面/歌词，应用层目前由 ArkTS（`CoverCache` / `EmbeddedLyricReader`）负责，C++ 专注文本元数据兜底；本轮明确此职责边界，不重复实现。

## 6. 复现命令

```bash
g++ -std=c++17 -I entry/src/main/cpp \
  test_main.cpp entry/src/main/cpp/audio_metadata.cpp -o meta_test
./meta_test bet_on_me.flac lose_my_mind.m4a zhou_shen.flac
```

---

## 7. 第二轮增强 · 合成样本 A/B 对照（2026-08-05）

为闭环 code-reviewer 提出的 P0/P1，针对无法直接获取的边界样本，用 Python 构造合成文件，对「修复前（buggy）」与「修复后（fixed）」两个版本做对照。

### 7.1 样本与预期

| 样本 | 构造目的 | 预期 |
|---|---|---|
| `sample_vbr.mp3` | MPEG1 Layer III + Xing 头（帧数=5000） | duration≈130612ms（44.1k, 1152 spf） |
| `sample_vbr_mono.mp3` | MPEG1 Layer III + Xing 头（单声道，帧数=3000） | duration≈78367ms（单声道 side info=17） |
| `sample_mvhd_v1.m4a` | `mvhd` version=1，`duration` 存于 64 位低位 (p+28..p+31) | duration≈213456ms |
| `sample_id3_utf16be.mp3` | ID3v2 `enc==2`（UTF-16BE 无 BOM）中文标题 | 标题「中文标题BE」不乱码 |
| `sample_evil2.m4a` | 两个 atom 互指 `largesize` | 修复前死循环（8s 未返回被强杀）；修复后立即返回 duration=0 |

### 7.2 对照结果

| 修复项 | buggy（修复前） | fixed（修复后） |
|---|---|---|
| P0-3 largesize 回绕 | 8 秒未返回 → 死循环（被 kill -9） | 立即返回，duration=0，无 ANR |
| P1-2 MP3 side info `layer==1` | （沿用 layer 误判） | VBR 帧数命中，时长精确 |
| P1-3 mvhd v1 低位 | 高位字节被当 duration → 时长异常 | 读 p+28..p+31，时长=213456ms |
| P1-7 UTF-16BE 默认大端 | 中文按 LE 解出乱码 | 「中文标题BE」正确 |

### 7.3 真实音频回归（改动前后一致）

| 文件 | 修复前 | 修复后 |
|---|---|---|
| bet_on_me.flac | Bet On Me / 2:52 / 192k / 2ch | 一致 |
| lose_my_mind.m4a | Lose My Mind… / 3:29 / 44.1k / 2ch | 一致 |
| zhou_shen.flac | 人是_ / 周深 / 4:35 / 44.1k / 2ch | 一致 |

**结论**：4 项 P0/P1 缺陷均经 A/B 对照证实修复有效，且真实文件零回归。ArkTS 侧（拖拽 `ForEach.onMove`、呼吸动画守卫、`@Concurrent` taskpool）因沙箱无法出 HAP，采用静态复核 + 类型推导校验，待 DevEco 真机构建复验。

---

## 8. 年代(year)解析验证

> 补充对象：第三轮新增的「年代(year)」全链路解析（对应 PRD FR-28 / 模块 T-04、I-01/I-02）
> 验证日期：2026-08-06 ｜ 方式：基于既有 `g++` standalone harness + 真机复验建议

### 8.1 全链路与验证现状

| 层 | 实现 | 本轮验证覆盖 |
|---|---|---|
| C++ `audio_metadata.cpp` | FLAC `DATE` / MP3 `TYER`(优先)+`TDRC` / MP4 `©day` → 写入 `year` | ⚠️ 代码已落地，但 3 个真实样本均未显式携带对应标签，C++ `year` 分支**未被真实音频执行** |
| NAPI `napi_init.cpp` | 随 `title/artist/...` 一并返回 `year` | ✅ 返回契约已接（`AudioMeta` 可读 `year`） |
| ArkTS `AudioMeta.year` | MediaKit 优先：`AVMetadata.dateTime` → `extractYear` 正则 `/(19|20)\d{2}/`；NAPI 兜底 | ⚠️ `extractYear` 逻辑已实现，但需 MediaKit 实际返回 `dateTime` 的样本方可真机确认 |
| 详情面板 `SongDetailSheet` | 打开时 `AudioMetaReader.read(src)` 异步取 `year` 显示 | ⚠️ 受上游两层的真机数据驱动 |

### 8.2 验证缺口（非阻断，建议补测）

- **FLAC `DATE` 分支**：`bet_on_me.flac` / `zhou_shen.flac` 的 VORBIS_COMMENT 未含 `DATE=YYYY` 字段，C++ 取到的 `year` 为空；需构造带 `DATE` 的 FLAC（如 `metaflac --set-tag=DATE=2021`）复验。
- **MP4 `©day` 分支**：`lose_my_mind.m4a` 的 iTunes `ilst` 未含 `©day` 原子，C++ `year` 为空；需构造带 `©day` 的 M4A 复验。
- **MP3 `TYER`/`TDRC` 分支**：本轮 3 个样本均无 MP3（与 §5 所述 MP3/VBR 缺口同源），C++ `year` 的 MP3 路径**完全未在真实音频上跑过**；建议补一个带 `TYER`（ID3v2.3）与 `TDRC`（ID3v2.4）的 MP3 样本，一并验证 §5 的 VBR 时长缺口。
- **正则 `extractYear`**：`/(19|20)\d{2}/` 对 `AVMetadata.dateTime`（如 `2021-05-01T00:00:00.000Z`）抽 4 位年份，需在真机确认 MediaKit 实际 `dateTime` 格式与命中情况。

### 8.3 复验清单（建议追加）

| # | 验证项 | 期望结果 |
|---|---|---|
| 1 | 带 `DATE` 的 FLAC 经 `meta_test` 解析 | C++ 输出 `year` 等于标签年份 |
| 2 | 带 `©day` 的 M4A 经 `meta_test` 解析 | C++ 输出 `year` 等于标签年份 |
| 3 | 带 `TYER`/`TDRC` 的 MP3 经 `meta_test` 解析 | C++ 输出 `year` 等于标签年份（同时验证 MP3 路径，见 §5 缺口） |
| 4 | 真机打开带年代标签歌曲的详情面板 | 「年代」字段显示正确 4 位年份，旧歌曲（无 `year` 字段）显示空而非崩溃 |
| 5 | 无年代标签的音频 | `year` 为空，面板不显示年代、不报错 |

> 说明：year 设计为「详情面板按需重读」，不落 `SongItem`、不改 `dataPreferences` 既有结构，故上述缺口不影响历史数据与新功能稳定性，仅需在真机补样本确认解析正确性。
