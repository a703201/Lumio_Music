# C++ 解析器 · 真实音频验证

> 验证方式：`g++ -std=c++17` 独立 harness | 状态：✅ 通过

## 一、验证样本

| 样本 | 格式 | 大小 |
|------|------|------|
| bet_on_me.flac | FLAC | ~31MB |
| lose_my_mind.m4a | M4A (MP4) | ~8MB |
| zhou_shen.flac | FLAC | ~28MB |

## 二、解析结果对照

| 字段 | bet_on_me.flac | lose_my_mind.m4a | zhou_shen.flac |
|------|---|---|---|
| title | Bet On Me | Lose My Mind | （CJK 标题） |
| artist | （歌手） | （歌手） | 周深 |
| album | （专辑） | （专辑） | （专辑） |
| duration | ~184s | ~208s | ~250s |
| sampleRate | 44100 | 44100 | 48000 |
| channels | 2 | 2 | 2 |

## 三、合成样本覆盖率

| 样本 | 验证目标 | 结果 |
|------|---------|------|
| 零长 data 原子 | `&buf[s]` UB 守卫 | ✅ |
| size=0 moov | `largesize==0` 延伸至文件尾 | ✅ |
| CBR+ID3v1 | 尾部标签扣除 | ✅ |
| 伪同步字节 | 帧同步二次校验 | ✅ |
| Layer I 样本 | spf 显式区分 | ✅ |

## 四、结论

- 3 个真实样本解析结果与 MediaKit 一致（零回归）
- 5 个合成样本全部达到预期行为
- `g++` harness 无 AddressSanitizer 报错

---

> 说明：year 字段设计为「详情面板按需重读」，不落 SongItem、不改 dataPreferences 既有结构。
