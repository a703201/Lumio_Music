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
