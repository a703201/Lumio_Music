# 代码审查报告 · PRD 落地批次

| 项目 | Lumio Music |
|---|---|
| 目标平台 | HarmonyOS 6.1.1 / API 24（`compatibleSdkVersion` = 6.1.0(23)） |
| 技术栈 | ArkTS + ArkUI + C++ NAPI |
| 审查范围 | 本轮 12 个改动文件（C++ 原生元数据解析、自建歌单、状态与存储治理、README 权限表、API 弃用迁移） |
| 审查方式 | 静态只读审查（未修改任何业务代码） |
| 审查角色 | code-reviewer |

---

## 1. 结论概览

> ### 结论：**有条件通过**

ArkTS / ArkUI 侧整体质量良好，本项目历史踩过的红线（`build()` 首条语句、全局环境声明误 import、`@Component` 上的 `get` 访问器、裸 `console`/`hilog`、静态方法用 `this`、对象字面量作类型）**本轮全部未复现**。路由注册、权限声明、README 权限表、`menuScales` 下标、资源引用均核对无误。

**阻断点集中在 C++ 侧**：`audio_metadata.cpp` 的三个解析器普遍存在「用 32 位无符号数做长度运算 + 回绕后再做边界检查」的同一类缺陷，构成 5 处可被畸形/截断音频文件触发的堆越界读。同时 MP4 分支存在两个叠加的功能性缺陷，导致 **M4A/MP4/AAC 文本标签 100% 解析不到**，本轮 C++ 能力有 1/3 分支实际无效。

| 级别 | 数量 | 说明 |
|---|---|---|
| 🔴 **P0 阻断项** | **6** | 内存越界 / 未初始化读，全部位于 C++ 侧，需修复后方可发布 |
| 🟡 **P1 重要项** | **10** | 功能失效、数据失真、主线程阻塞、编译/Lint 风险、交互失效 |
| 🔵 **P2 建议项** | **13** | 可读性、性能、一致性、隐私日志 |

**编译层面**：未发现确定性编译失败。`CMakeLists.txt` 已包含 `audio_metadata.cpp`（第 8 行），无需改动 ✅。NAPI 返回字段与 `NativeModule.ets` 的 `AudioMetadata` 接口完全一致 ✅。

**放行建议**：P0 全部修复 + P1-1/P1-2/P1-3/P1-6 修复后可进入真机验证；其余 P1/P2 可排入下一迭代。

---

## 2. 阻断项 P0

> 触发条件说明：P0-1 ~ P0-5 均需要「畸形 / 截断 / 恶意构造」的音频文件触发。考虑到本应用的歌曲来源是**用户通过 `DocumentViewPicker` 自由导入的任意文件**，下载中断的半截 MP3、标签写坏的 FLAC 在真实使用中完全可能出现，因此按阻断项处理。所有 5 处根因相同：**先用 `unsigned int` 做长度加法（回绕），再拿回绕后的结果做边界检查**。

---

### P0-1 · FLAC `vendorLen` 32 位回绕导致堆越界读

**文件**：`entry/src/main/cpp/audio_metadata.cpp:99-105`

**问题**：`vendorLen` 是从文件中直接读出的 32 位小端整数，完全由输入控制。

```cpp
p += 4 + vendorLen;            // ← line 103: unsigned int 加法，可回绕
if (p + 4 <= len) {            // ← line 104: 用回绕后的 p 做检查，检查失效
    unsigned int count = static_cast<unsigned int>(buf[pos + p]) | ...  // line 105
```

**错误现象**：构造 `vendorLen = 0xFFFFFFFB` 时，`4 + vendorLen` 回绕为 `0xFFFFFFFF`；`p + 4` 再次回绕为 `3`，通过 `<= len` 检查。随后 `buf[pos + p]` 中 `p` 被提升为 `size_t`（4294967295），产生约 4GB 偏移的越界读 → SIGSEGV。

**修正**：全部长度运算提升到 `size_t`，并对每一步做上界校验。

```cpp
// 建议：把 p 改为 size_t，并在每次推进前校验
size_t p = 0;
if (static_cast<uint64_t>(p) + 4 + vendorLen > len) {
    break;                     // vendor 串已越界，放弃本块
}
p += 4 + static_cast<size_t>(vendorLen);
if (p + 4 > len) {
    break;
}
```

---

### P0-2 · FLAC 注释项 `clen` 回绕导致 4GB `std::string` 构造

**文件**：`entry/src/main/cpp/audio_metadata.cpp:114-122`

**问题**：

```cpp
unsigned int clen = ...;       // line 114-117: 完全由文件控制
p += 4;                        // line 118
if (p + clen > len) {          // ← line 119: unsigned int 回绕
    break;
}
std::string comment(reinterpret_cast<const char*>(&buf[pos + p]), clen);  // ← line 122
```

**错误现象**：`clen = 0xFFFFFFFF` 时，`p + clen`（模 2³²）= `p - 1`。由于 `p <= len` 恒成立，`p - 1 <= len` 也恒成立 → 检查**100% 被绕过**。随后以 ~4GB 长度构造 `std::string` → 立即越界读 + `std::bad_alloc` / SIGSEGV。这是本批次**最容易触发**的一处。

附带缺陷：当 `clen == 0` 且 `p == len` 时，`&buf[pos + p]` 即 `&buf[buf.size()]`，`std::vector::operator[]` 越界索引属未定义行为。

**修正**：

```cpp
if (static_cast<uint64_t>(p) + clen > len) {
    break;
}
std::string comment;
if (clen > 0) {                // 避免 &buf[buf.size()] 的 UB
    comment.assign(reinterpret_cast<const char*>(&buf[pos + p]), clen);
}
p += clen;
```

---

### P0-3 · MP3 ID3v2.3 帧长回绕导致越界读

**文件**：`entry/src/main/cpp/audio_metadata.cpp:166-198`

**问题**：`ver != 4`（即 ID3v2.3）时，`fsize` 是完整 32 位大端读取，取值可达 `0xFFFFFFFF`；而边界检查两侧都是 `unsigned int`：

```cpp
fsize = (buf[p+4] << 24) | (buf[p+5] << 16) | (buf[p+6] << 8) | buf[p+7];  // line 170-173
unsigned int bodyStart = p + 10;                                           // line 175
if (bodyStart + fsize > buf.size() || fsize < 1) {   // ← line 176: 先回绕再比较
    break;
}
...
unsigned int txtLen = fsize - 1;                                           // line 181
text.assign(reinterpret_cast<const char*>(&buf[s]), txtOff + txtLen - s);  // ← line 198
```

**错误现象**：`fsize = 0xFFFFFFF0`、`bodyStart = 20` 时，`bodyStart + fsize` 回绕为 `16`，若 `buf.size() > 16` 则检查通过。随后 `txtLen ≈ 0xFFFFFFEF`，`text.assign` 以约 4GB 长度读取 → 崩溃。

**修正**：

```cpp
if (fsize < 1 || static_cast<uint64_t>(bodyStart) + fsize > buf.size()) {
    break;
}
```
同时建议对 ID3v2.3 的 `fsize` 加一个理性上限（例如 `fsize > tagSize` 即视为损坏并 break）。

---

### P0-4 · MP4 `mvhd` 无任何边界检查导致越界读

**文件**：`entry/src/main/cpp/audio_metadata.cpp:270-291`

**问题**：外层 `while` 只保证 `pos + 8 <= buf.size()`（line 261），而 atom 的 `size` 字段**从未与 `buf.size()` 校验**。命中 `mvhd` 后直接读到 `buf[p + 27]`：

```cpp
if (tagEq(t, "mvhd")) {
    unsigned int p = pos + 8;      // ← line 271: 仅保证 pos+8 <= buf.size()
    unsigned char mv = buf[p];     // ← line 272: p 可能正好 == buf.size()
    ...
    mvhdDur = (buf[p + 24] << 24) | ... | buf[p + 27];   // ← line 287-290: 最远读到 p+27
```

**错误现象**：任何在 `mvhd` 头之后被截断的 MP4/M4A（下载中断、拷贝不完整）都会读出缓冲区尾部之外最多 28 字节 → 脏数据或 SIGSEGV。

**修正**：进入分支前统一校验 atom 完整性与所需字段长度。

```cpp
// 建议在 while 循环体开头统一加：
if (static_cast<uint64_t>(pos) + size > buf.size()) {
    break;                        // atom 越过文件尾，视为损坏
}
...
if (tagEq(t, "mvhd")) {
    size_t p = pos + 8;
    size_t need = (buf[p] == 0) ? 20u : 32u;   // v0 需 20 字节，v1 需 32 字节
    if (p + need > buf.size()) {
        break;
    }
    ...
}
```

---

### P0-5 · MP4 `ilst/data` 原子 `ds < 16` 时无符号下溢

**文件**：`entry/src/main/cpp/audio_metadata.cpp:311-318`

**问题**：守卫只有 `if (ds < 8) break;`（line 311），但取值时按固定 16 字节头偏移：

```cpp
unsigned int vp = dpos + 16;                    // line 315
unsigned int vlen = ds - 16;                    // ← line 316: ds ∈ [8,15] 时下溢
if (vp + vlen <= buf.size()) {                  // ← line 317: unsigned int 回绕
    std::string val(reinterpret_cast<const char*>(&buf[vp]), vlen);  // ← line 318
```

**错误现象**：`ds = 8` 时 `vlen = 0xFFFFFFF8`（约 4GB）；`vp + vlen` 回绕后极易通过 `<= buf.size()` 检查 → `std::string` 越界构造 → 崩溃。

**修正**：

```cpp
if (ds < 16) {                 // data 原子至少 16 字节（size+type+version/flags+locale）
    break;
}
size_t vp = dpos + 16;
size_t vlen = ds - 16;
if (vp + vlen > buf.size()) {
    break;
}
std::string val(reinterpret_cast<const char*>(&buf[vp]), vlen);
```

---

### P0-6 · NAPI 入口未初始化 `filePathLen` / 未校验 `argc` 与返回状态

**文件**：`entry/src/main/cpp/napi_init.cpp:25-34`

**问题**：

```cpp
size_t argc = 1;
napi_value args[1];
napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);   // 未检查 argc

char filePath[1024];
size_t filePathLen;                                            // ← line 31: 未初始化
napi_get_value_string_utf8(env, args[0], filePath, sizeof(filePath), &filePathLen);  // 未检查返回值
AudioMetadata metadata = parseAudioMetadata(std::string(filePath, filePathLen));     // ← line 34
```

**错误现象**：若调用方漏传参数（`argc == 0`），`args[0]` 为未初始化内存；若 `napi_get_value_string_utf8` 因类型不符返回非 `napi_ok`，它**不会写入 `filePathLen`** → 以栈上垃圾值作为长度构造 `std::string` → 越界读 / 崩溃。当前 `AudioMeta.ets:38` 总是传合法 string，属潜伏缺陷，但一行即可根治。

**修正**：

```cpp
size_t argc = 1;
napi_value args[1] = { nullptr };
napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

napi_value undefinedVal = nullptr;
napi_get_undefined(env, &undefinedVal);
if (argc < 1 || args[0] == nullptr) {
    return undefinedVal;
}
char filePath[1024] = { 0 };
size_t filePathLen = 0;                                        // ← 显式初始化
if (napi_get_value_string_utf8(env, args[0], filePath, sizeof(filePath), &filePathLen) != napi_ok) {
    return undefinedVal;
}
```

> 同时建议对后续每个 `napi_create_string_utf8` 检查返回值——见 P1-6，非法 UTF-8 会让 `napi_value` 保持未初始化，随后 `napi_set_named_property` 会使用野指针。

---

## 3. 重要项 P1

### P1-1 · MP4 `meta` 是 FullBox，递归起点错误 → `ilst` 永远不可达

**文件**：`entry/src/main/cpp/audio_metadata.cpp:334-336`

`meta` 在 ISO BMFF 中是 **FullBox**：8 字节 box 头之后还有 4 字节 `version + flags`，子 box 从 `pos + 12` 开始。当前代码与 `moov`/`trak`/`udta` 一视同仁地从 `pos + 8` 递归：

```cpp
} else if (tagEq(t, "moov") || ... || tagEq(t, "udta") || tagEq(t, "meta")) {
    walkAtoms(buf, pos + 8, pos + size, mvhdDur, mvhdTs, m);   // ← meta 应为 pos + 12
```

**现象**：从 `pos + 8` 读到的是 `00 00 00 00`（version+flags），被当作 atom size = 0 → 命中 `if (size < 8) break;` → 立刻退出，标准 iTunes 布局 `moov → udta → meta → ilst` 中的 `ilst` **永远走不到**。

**修正**：

```cpp
} else if (tagEq(t, "meta")) {
    walkAtoms(buf, pos + 12, pos + size, mvhdDur, mvhdTs, m);   // FullBox：跳过 version+flags
} else if (tagEq(t, "moov") || tagEq(t, "trak") || tagEq(t, "mdia") ||
           tagEq(t, "minf") || tagEq(t, "stbl") || tagEq(t, "udta")) {
    walkAtoms(buf, pos + 8, pos + size, mvhdDur, mvhdTs, m);
}
```

---

### P1-2 · iTunes 版权符原子名写成了 UTF-8 编码，`tagEq` 永不匹配

**文件**：`entry/src/main/cpp/audio_metadata.cpp:320-325`

```cpp
if (tagEq(ct, "\xc2\xa9nam") && m.title.empty()) {          // line 320
} else if ((tagEq(ct, "\xc2\xa9ART") || tagEq(ct, "aART")) ...   // line 322
} else if (tagEq(ct, "\xc2\xa9alb") ...                      // line 324
```

MP4 中 iTunes 原子名是 **4 个字节** `0xA9 'n' 'a' 'm'`（原始 Latin-1 版权符），而 `"\xc2\xa9nam"` 是 © 的 **UTF-8 双字节编码**，实际前 4 字节为 `0xC2 0xA9 'n' 'a'` —— `tagEq` 只比较前 4 字节，**永远不相等**。

**现象**：与 P1-1 叠加，`M4A / MP4 / AAC` 的 title / artist / album **100% 解析失败**，全部回退到文件名。本轮 C++ 三大分支中有一支实际无效。

**修正**：

```cpp
if (tagEq(ct, "\xa9nam") && m.title.empty()) {
    m.title = val;
} else if ((tagEq(ct, "\xa9ART") || tagEq(ct, "aART")) && m.artist == "未知艺术家") {
    m.artist = val;
} else if (tagEq(ct, "\xa9alb") && m.album == "未知专辑") {
    m.album = val;
}
```

> 注意 `"\xa9nam"` 在部分编译器下会因 `\xa9n` 的十六进制转义贪婪解析而告警，最稳妥写法是 `static const char kNam[4] = { '\xa9', 'n', 'a', 'm' };` 再传入。

---

### P1-3 · MP3 比特率表行序颠倒 → 时长严重失真

**文件**：`entry/src/main/cpp/audio_metadata.cpp:240-243`

MPEG 帧头的 layer 位含义为：`3 = Layer I`、`2 = Layer II`、`1 = Layer III`；而 `brTable` 的行顺序是 `{Layer I, Layer II, Layer III}`。当前映射写反了：

```cpp
int layerIdx = layer - 1;      // ← line 241: Layer III(1) → row 0(Layer I 表)
```

**现象**：绝大多数 MP3 是 Layer III（`layer == 1`），会被映射到 **Layer I 的比特率表**。例如 128 kbps 的 MP3，其 `brIdx = 9`，在 Layer I 表中查到 288 → 时长被低估约 2.25 倍。同理 Layer I 文件会查到 Layer III 表。

**修正**：

```cpp
int layerIdx = 3 - layer;      // layer 3(I)→0, 2(II)→1, 1(III)→2
```

---

### P1-4 · MP3 帧同步判据错误：排除了合法 MPEG2.5，放行了保留值

**文件**：`entry/src/main/cpp/audio_metadata.cpp:216`

```cpp
if (buf[i] == 0xFF && (buf[i+1] & 0xE0) == 0xE0 && (buf[i+1] & 0x06) && (buf[i+1] & 0x18)) {
```

`& 0x18` 要求 version 位不为 `00`，但 `00` 恰是**合法的 MPEG 2.5**；反而 `01`（保留值，非法）会被放行，且在 line 240 被 `(ver == 3) ? 0 : (ver == 2 ? 1 : 2)` 误映射到 MPEG2.5 表。

**修正**：

```cpp
unsigned char v1 = buf[i + 1];
int verBits   = (v1 >> 3) & 0x03;
int layerBits = (v1 >> 1) & 0x03;
if (buf[i] == 0xFF && (v1 & 0xE0) == 0xE0 && verBits != 1 && layerBits != 0) {
    break;
}
```

---

### P1-5 · `walkAtoms` 递归无深度上限 → 畸形文件栈溢出

**文件**：`entry/src/main/cpp/audio_metadata.cpp:258, 336`

`walkAtoms` 对 `moov/trak/mdia/minf/stbl/udta/meta` 无条件递归，**没有深度限制**。构造一个由数千层嵌套 `moov`（每层仅 8 字节头）组成的文件，递归深度可达 `文件大小 / 8`；1 MB 即可产生约 13 万层递归 → 栈溢出崩溃。

> 已确认**不存在死循环**：`walkAtoms` 三层循环均有 `size/cs/ds >= 8` 的最小步进保证；`parseFlac` 每轮至少 `pos += 4`；`parseMp3` 的 ID3 帧循环 `fsize >= 1` 保证至少推进 11 字节，MPEG 扫描循环 `i++` 单调递增。风险仅在递归深度。

**修正**：加深度参数。

```cpp
void walkAtoms(const std::vector<unsigned char>& buf, size_t start, size_t end,
               uint32_t& mvhdDur, uint32_t& mvhdTs, AudioMetadata& m, int depth = 0) {
    if (depth > 16) {          // ISO BMFF 实际嵌套远小于此
        return;
    }
    ...
    walkAtoms(buf, pos + 8, pos + size, mvhdDur, mvhdTs, m, depth + 1);
}
```

---

### P1-6 · ID3v2 UTF-16 文本按低字节截断 → 中文标题乱码 / 非法 UTF-8

**文件**：`entry/src/main/cpp/audio_metadata.cpp:190-192`

```cpp
for (unsigned int i = s; i + 1 < txtOff + txtLen; i += 2) {
    text.push_back(static_cast<char>(buf[i]));   // ← 只取 UTF-16 码元的低字节
}
```

对 ASCII 恰好可用（UTF-16LE 下低字节即 ASCII），但对中文（U+4E00 及以上）低字节是任意值，产出的是**非法 UTF-8 字节串**。同时该循环未区分 LE / BE：line 187 识别出 BE BOM 后仍按 LE 取低字节，BE 文件会全部取到高位字节。

**下游后果**（`napi_init.cpp:40`）：`napi_create_string_utf8` 遇非法 UTF-8 可能返回错误，此时 `title` 这个 `napi_value` **保持未初始化**，紧接着 `napi_set_named_property(env, result, "title", title)` 就会使用野指针。

**修正**：记录字节序并实现 UTF-16 → UTF-8 转换；同时在 NAPI 侧检查每个 `napi_create_string_utf8` 的返回值，失败则回退空串。

```cpp
bool isBE = false;
unsigned int s = txtOff;
if (txtLen >= 2 && buf[s] == 0xFF && buf[s + 1] == 0xFE) { s += 2; isBE = false; }
else if (txtLen >= 2 && buf[s] == 0xFE && buf[s + 1] == 0xFF) { s += 2; isBE = true; }
for (unsigned int i = s; i + 1 < txtOff + txtLen; i += 2) {
    uint16_t u = isBE ? ((buf[i] << 8) | buf[i + 1]) : ((buf[i + 1] << 8) | buf[i]);
    if (u == 0) break;
    if (u < 0x80) {
        text.push_back(static_cast<char>(u));
    } else if (u < 0x800) {
        text.push_back(static_cast<char>(0xC0 | (u >> 6)));
        text.push_back(static_cast<char>(0x80 | (u & 0x3F)));
    } else {                    // 未处理代理对，中日韩常用区已覆盖
        text.push_back(static_cast<char>(0xE0 | (u >> 12)));
        text.push_back(static_cast<char>(0x80 | ((u >> 6) & 0x3F)));
        text.push_back(static_cast<char>(0x80 | (u & 0x3F)));
    }
}
```

---

### P1-7 · 元数据补扫在 UI 线程做同步全文件 I/O → 卡顿 / ANR 风险

**文件**：`entry/src/main/ets/services/MusicStore.ets:233-253`、`entry/src/main/cpp/audio_metadata.cpp:11-25`

三个因素叠加：

1. `refreshMetadataIfNeeded()` 对全库歌曲**串行** `await`（line 233-253），曲库越大耗时线性增长；
2. 回退路径 `NativeUtils.getInstance().parseAudioMetadata(src)`（`AudioMeta.ets:38`）是**同步 NAPI 调用**，会阻塞调用它的线程直到解析完成；
3. `readFile`（`audio_metadata.cpp:11-25`）把**整个文件**读入 `std::vector`——单个无损 FLAC 可达数十 MB。

**现象**：首次升级启动时，若 MediaKit 对部分文件取不到标题，会逐个走同步原生解析，每首都是一次全量文件读 → 主线程长时间阻塞、内存峰值飙高，极端情况触发 ANR。

**修正建议**（任选其一或组合）：
- C++ 侧只读所需前缀：FLAC / MP3 的标签都在文件头部，读前 1 MB 足够；MP4 的 `moov` 可能在尾部，可先读头 1 MB，未命中再读尾 1 MB；
- NAPI 改为 `napi_create_async_work` 异步实现，或在 ArkTS 侧用 `taskpool` 派发；
- `refreshMetadataIfNeeded` 分批处理（如每批 20 首后 `await` 一次微任务让出）并加进度反馈。

---

### P1-8 · `PlaylistDetail` 勾选框事件双触发，点击 Checkbox 本体选不中

**文件**：`entry/src/main/ets/pages/PlaylistDetail.ets:201-213`

```ets
Checkbox()
  .select(this.selectedIds.includes(song.id))
  .onChange(() => { this.toggleSelect(song.id); })      // ← line 204-206
...
.onClick(() => { this.toggleSelect(song.id); })          // ← line 211-213（父 Row）
```

`Checkbox` 的点击事件会**冒泡**到父 `Row` 的 `onClick`，于是 `toggleSelect` 被调用两次，一次选中一次取消，**净效果为不变** —— 用户直接点勾选框时无法选中，只有点行的其它区域才生效。

> 对照 `Settings.ets:735-746` 的 `Radio` 也有同样的双绑定，但 `onSelect(opt.value)` 是幂等赋值，所以不暴露问题；`toggleSelect` 是**翻转**语义，因此这里会出错。

**修正**（推荐：勾选框只做视觉呈现，统一由行点击驱动）：

```ets
Checkbox()
  .select(this.selectedIds.includes(song.id))
  .selectedColor('#FA2759')
  .hitTestBehavior(HitTestMode.None)    // 不接收点击，交给父 Row 统一处理
```

或者保留 `onChange` 而去掉父 `Row` 的 `onClick`（但会牺牲「点整行选中」的手感）。

---

### P1-9 · `getParam()` 用 `ESObject` 中转并赋值给 `string`，触碰 `arkts-limited-esobj`

**文件**：`entry/src/main/ets/pages/PlaylistDetail.ets:458-461`

```ets
const param: ESObject = context.pathStack.getParam();
if (typeof param === 'string') {
  this.playlistId = param;                 // ← ESObject → string 赋值
}
```

ArkTS 的 `arkts-limited-esobj` 规则限定 `ESObject` 只用于跨语言互操作场景，且**不允许把 `ESObject` 值赋给具体类型的变量**。本项目其它处的 `ESObject` 用法（`AVSessionController.ets:412`）是纯粹的方法调用透传，不涉及赋值，性质不同。这里存在编译器 / code-linter 报错风险。

**修正**：不引入 `ESObject`，直接对返回值做类型守卫。

```ets
const param = context.pathStack.getParam();
if (typeof param === 'string') {
  this.playlistId = param as string;
} else {
  Logger.warn(TAG, 'PlaylistDetail: invalid route param, expected playlist id string');
}
this.reload();
```

---

### P1-10 · `MusicStore` 歌单反序列化零校验，脏数据会打崩歌单页

**文件**：`entry/src/main/ets/services/MusicStore.ets:303-304`

```ets
const playlistStr = await this.preferences.get(KEY_PLAYLISTS, '[]') as string;
this.playlists = JSON.parse(playlistStr) as Playlist[];      // ← 无字段校验
```

`as Playlist[]` 只是编译期断言，运行时不做任何校验。若持久化数据来自旧版本 schema 或被写坏（缺 `songIds`），`Playlists.ets:178` 的 `playlist.songIds.length` 与 `:197` 会在 `undefined` 上取 `.length` → 直接崩在 `build()` 里。

> 对照：同一函数中 `songs` / `recentlyPlayed` 都做了逐字段映射与 `?? ''` 兜底（line 270-301），歌单是唯一没做的。

**修正**：

```ets
const rawPlaylists = JSON.parse(playlistStr) as Playlist[];
this.playlists = (Array.isArray(rawPlaylists) ? rawPlaylists : [])
  .filter((p: Playlist) => p !== null && p !== undefined && typeof p.id === 'string')
  .map((p: Playlist) => {
    const item: Playlist = {
      id: p.id,
      name: p.name ?? '未命名歌单',
      songIds: Array.isArray(p.songIds) ? p.songIds.filter((n: number) => typeof n === 'number') : []
    };
    return item;
  });
```

---

## 4. 建议项 P2

| # | 文件:行 | 问题 | 建议 |
|---|---|---|---|
| P2-1 | `Playlists.ets:52-56`, `:330` | `setInterval` 周期 1000 ms 与 `.animation({ duration: 2000 })` 不匹配，缩放动画永远播不完，观感抖动；且列表非空后定时器仍在空转 | 改用 `this.getUIContext().animateTo()` 驱动，或把 duration 降到 ≤ 800 ms，并在 `playlists.length > 0` 时清除定时器 |
| P2-2 | `Playlists.ets:71-72` | `reload()` 每次都整体重建 `itemScales`，会打断正在进行的按压动画（`onShown` + `@Watch` 都会触发） | 仅在长度变化时重建，否则复用旧数组 |
| P2-3 | `MusicStore.ets:92` | `id: Date.now().toString()` 同一毫秒内连续创建会产生重复 id，`deletePlaylist(id)` 会一次删掉两个 | `` `${Date.now()}_${Math.floor(Math.random() * 1e6)}` `` |
| P2-4 | `AudioMeta.ets:20-25`, `:40-44` | C++ 已解析出 `duration / sampleRate / channels`，ETS 侧全部丢弃，能力浪费 | `AudioMeta` 接口增加 `durationMs?: number`，供列表页展示时长 |
| P2-5 | `AudioMeta.ets:52-85` | 每首歌都 `createAVMetadataExtractor` + `release` 一次，全库补扫时开销可观 | 批量场景复用同一个 extractor 实例，扫描结束再统一 release |
| P2-6 | `entry/src/main/cpp/`（缺失） | **没有 `types/**/index.d.ts`**，`import nativeModule from 'libnative_module.so'`（`NativeModule.ets:1`）无类型声明，NAPI 字段契约靠人工维护 | 补 `cpp/types/libnative_module/index.d.ts` + `oh-package.json5`，把契约交给编译器守护。**本次已人工核对：NAPI 返回 `title/artist/album/duration/sampleRate/channels`（`napi_init.cpp:41-61`）与 `NativeModule.ets:3-10` 完全一致 ✅** |
| P2-7 | `audio_metadata.cpp:228-239` | `int brTable[3][3][16]` 与 `srTable` 是函数内局部变量，每次调用都要在栈上初始化 576+ 字节 | 提升为 `static const` |
| P2-8 | `audio_metadata.cpp:23` | `f.read(...)` 返回值未检查，短读时后半段是 `resize` 补的 0，解析结果不可信 | 用 `f.gcount()` 校验实际读取字节数并按实际长度 `resize` |
| P2-9 | `audio_metadata.cpp:266` | `size == 1` 表示 64 位 `largesize`，当前直接 `break`，大体积 MP4 不支持 | 读取随后的 8 字节 `largesize`，或至少注释说明该限制 |
| P2-10 | `audio_metadata.cpp:244-251` | MP3 时长按 CBR 估算，VBR 文件误差可达 30%+ | 解析 `Xing` / `VBRI` 头拿总帧数后精确计算 |
| P2-11 | `audio_metadata.cpp:271`, `:315` | `unsigned int p = pos + 8;` / `unsigned int vp = dpos + 16;` 把 `size_t` 窄化为 32 位 | 统一用 `size_t`，与 P0-4 / P0-5 一并修复 |
| P2-12 | `napi_init.cpp:30` | 路径超过 1023 字节被静默截断，无任何提示 | 先用 `napi_get_value_string_utf8(env, args[0], nullptr, 0, &len)` 探长度再动态分配 |
| P2-13 | `AudioMeta.ets:47`, `:67` | 失败日志打印完整沙箱路径（含用户文件名），而 `Logger` 固定用 `'%{public}s'`（`Logger.ets:23`）→ 文件名明文进 hilog | 只打印扩展名或文件名哈希；或为 Logger 增加 `%{private}s` 变体 |

**一致性小结（非缺陷，供参考）**

- `Playlists.ets` 有 `.onShown()` 刷新，`PlaylistDetail.ets` 没有。当前详情页数据变更都由自身操作触发 + `@Watch('coverRefreshToken')` 兜底，逻辑上够用，但两页风格不一致。
- `AVSessionController.ets:191` 已经解引用 `this.songList[this.musicIndex].label`，而 `:194` 才做 `SongItem | undefined` 判空——**该守卫是死代码**，songList 为空时 191 行先抛异常（被 217 行 catch 吞掉）。建议把取 song 的逻辑提到 191 之前并前置判空，让本轮新增的 `assetId` 逻辑真正生效。
- `PlaylistNameDialog:412` 的 `TextInput({ text: this.inputName })` 是单向绑定 + `onChange` 回写，输入中文时可能出现光标跳动；可考虑 `text: $$this.inputName`。

---

## 5. 权限与隐私合规核对

### 5.1 权限声明一致性

以 `entry/src/main/module.json5:14-39` 为准，与 `README.md` 权限表逐项比对：

| 权限 | module.json5 | README 表格 | `when` 一致 | 结论 |
|---|---|---|---|---|
| `ohos.permission.KEEP_BACKGROUND_RUNNING` | ✅ 已声明（line 16） | ✅ 后台持续播放（长时任务：audioPlayback） | `inuse` = `inuse` | ✅ 一致 |
| `ohos.permission.INTERNET` | ✅ 已声明（line 24） | ✅ 关于页跳转开发者主页 / 投播设备网络发现 | `always` = `always` | ✅ 一致 |
| `ohos.permission.GET_NETWORK_INFO` | ✅ 已声明（line 32） | ✅ 查询网络状态，判断投播可用性 | `always` = `always` | ✅ 一致 |

- **数量一致**：实际声明 3 项，README 声明「实际仅声明以下 3 项」→ ✅ 无虚报、无遗漏。
- **无多余权限**：3 项均有对应功能落地（后台播放 / About 页外链 / 投播设备发现），不存在声明了却用不到的权限。
- **`reason` 字段**：3 项均已配置 `$string:*_reason`，符合上架要求。
- **README 的「为什么没有媒体库权限」论述属实**：全项目未出现 `READ_MEDIA` / `WRITE_MEDIA` / `photoAccessHelper` / `mediaLibrary`，歌曲确实走 `DocumentViewPicker` → 沙箱拷贝 → `dataPreferences` 记录路径的链路。

### 5.2 本轮新增代码的权限影响

| 改动 | 是否引入新权限需求 | 说明 |
|---|---|---|
| `audio_metadata.cpp` 用 `std::ifstream` 读文件 | ❌ 否 | 读的是已拷贝进应用沙箱的路径，不触达系统媒体库，无需 `READ_MEDIA` |
| `AudioMeta.ets` 用 `fileIo.openSync(src, READ_ONLY)` | ❌ 否 | 同上，沙箱内文件 |
| `Playlists.ets` / `PlaylistDetail.ets` | ❌ 否 | 仅读写 `dataPreferences`（应用私有存储） |
| `MusicStore` 歌单增删改 | ❌ 否 | 同上 |

### 5.3 隐私数据外发核查

- **无网络外发**：本轮 12 个改动文件中未出现 `http`、`request`、`fetch`、`upload`、`rcp` 等任何网络调用。歌单、收藏、播放历史、元数据全部只写入 `dataPreferences`（应用沙箱）。
- **无三方 SDK**：未引入任何统计 / 广告 / 崩溃上报依赖。
- **一处轻度隐私建议**（已列为 P2-13）：`AudioMeta.ets:47` 与 `:67` 的失败日志会把**完整文件路径**（含用户自定义歌曲文件名）以 `%{public}s` 打进 hilog。虽不构成外发，但 public 级日志可被同设备其它进程读取，建议脱敏。

> **合规结论：通过。** 权限最小化落实到位，README 权限表与 `module.json5` 完全一致，无多余权限、无隐私数据外发。唯一改进点是日志脱敏（P2-13，非阻断）。

---

## 6. 复验清单（真机验证项）

修复 P0 / P1 后，请在真机按下表逐项验证。

### 6.1 C++ 元数据解析（P0/P1 修复后必验）

| # | 验证项 | 期望结果 |
|---|---|---|
| 1 | 导入带 **UTF-16 中文标签**的 MP3（TIT2/TPE1/TALB） | 标题、艺术家、专辑显示为正确中文，无乱码、无方块 |
| 2 | 导入带 **Latin-1 英文标签**的 MP3 | 文本正常，无尾部乱码 |
| 3 | 导入 **ID3v2.3** 与 **ID3v2.4** 各一个 MP3 | 两者都能读到标签（v2.3 走非 syncsafe 帧长分支） |
| 4 | 导入 **128 kbps CBR MP3**，与系统播放器对比时长 | 误差 < 2%（验证 P1-3 比特率表修复） |
| 5 | 导入 **VBR MP3** | 时长误差可接受（若未做 P2-10，记录实际偏差） |
| 6 | 导入带 VORBIS_COMMENT 的 **FLAC** | 标题/艺术家/专辑正确，时长与采样率正确 |
| 7 | 导入 **M4A / AAC**（iTunes 标签） | **标题/艺术家/专辑能读出**（验证 P1-1 + P1-2 修复；修复前此项必失败） |
| 8 | 导入 **无标签**的 MP3 / FLAC | 回退为文件名（不含扩展名），不崩溃 |
| 9 | 导入**人为截断**的 MP3 / FLAC / M4A（如 `head -c 5000` 截断） | 不崩溃，回退文件名（验证 P0-1 ~ P0-5） |
| 10 | 导入**改坏标签长度字段**的文件（把 vendorLen / clen / fsize 手工改成 `FF FF FF FF`） | 不崩溃（验证回绕修复） |
| 11 | 导入**超大无损文件**（> 50 MB FLAC） | 导入过程 UI 不冻结（验证 P1-7） |
| 12 | 首次升级启动触发 `refreshMetadataIfNeeded` 全库补扫（建议 100+ 首） | 无 ANR，无 OOM；`meta_scanned_v1` 置位后二次启动跳过 |

### 6.2 自建歌单

| # | 验证项 | 期望结果 |
|---|---|---|
| 13 | 我的 → 我的歌单 → 新建歌单 | 弹窗标题为「新建歌单」，输入框为空 |
| 14 | 输入空白名 / 纯空格提交 | Toast「歌单名称不能为空」，弹窗不关闭 |
| 15 | 输入已存在的名称 | Toast「已存在同名歌单」，弹窗不关闭 |
| 16 | 长按/点击「···」→ 重命名 | 弹窗标题为「重命名歌单」，**输入框预填当前名称**（验证 `defaultName` 在复用 Controller 下能正确刷新） |
| 17 | 重命名为自身原名 | 允许通过（`hasPlaylistName` 的 `excludeId` 生效） |
| 18 | 「···」→ 删除歌单 → 确认 | 歌单消失，本地库歌曲仍在 |
| 19 | 详情页 → 添加歌曲 → **直接点击勾选框本体** | **能选中**（验证 P1-8 修复；修复前此项必失败） |
| 20 | 详情页 → 添加歌曲 → 点击行的空白区域 | 能选中，「已选 N」计数正确 |
| 21 | 全部歌曲都已在歌单中时点「添加歌曲」 | Toast「本地库的歌曲都已在歌单中」，面板不弹出 |
| 22 | 详情页移出歌曲 → 返回歌单列表 | 列表页歌曲计数同步更新（验证 `.onShown()`） |
| 23 | 歌单播放全部 / 单曲起播 | 播放队列 = 歌单曲目（非全库），锁屏卡片标题正确（验证 `setQueue` → `syncQueue` → `setSongList`） |
| 24 | 在「管理歌曲」中删除一首已加入歌单的歌 | 歌单计数同步减少，不出现悬挂项（验证 `removeSong` 清理逻辑） |
| 25 | 杀进程重启后查看歌单 | 歌单、名称、曲目全部持久化正确 |
| 26 | **升级安装**（保留旧版 preferences 数据） | 歌单页不崩溃（验证 P1-10 反序列化兜底） |

### 6.3 状态治理与弃用迁移

| # | 验证项 | 期望结果 |
|---|---|---|
| 27 | 播放页点收藏 | 图标变红，**不再跳转到收藏页** |
| 28 | 收藏后进入「我的收藏」 | 该歌曲在列表中（验证收藏收口到 MusicStore） |
| 29 | 切歌 / 队列排序 / 移除队列项后再看收藏态 | 收藏图标与实际歌曲对应，不错位（验证 `song.id` 替代队列下标） |
| 30 | 锁屏 / 控制中心点收藏 | 与应用内收藏态双向一致（`onToggleFavorite` → `updateFavoriteState`） |
| 31 | 切换播放模式（顺序/随机/单曲） | Toast 正常弹出且文案正确（验证 `Prompt` → `getUIContext().getPromptAction()` 迁移 + `ResourceConversion` 返回 string 而非 "undefined"） |
| 32 | 我的页 5 个入口逐一点击 | 按压缩放动画都生效、跳转都正确（验证 `menuScales` 索引 0-4 与 5 元素数组匹配） |
| 33 | 投播场景切歌 | 远端 `assetId` 为 song.id，投播正常（验证 `castCurrentSong` 改动） |

### 6.4 构建与静态检查

| # | 验证项 | 期望结果 |
|---|---|---|
| 34 | `hvigorw assembleHap --mode module -p product=default` | 编译通过，无 ArkTS 报错 |
| 35 | `hvigorw codeLinter` | 无新增 `arkts-limited-esobj` / `arkts-no-untyped-obj-literals` 告警（重点看 P1-9） |
| 36 | C++ 侧建议追加 | 用 `-fsanitize=address` 本地编一版，对 6.1 节第 9/10 项的畸形样本跑一遍，确认无 ASan 报错 |

---

## 附录 · 本轮红线项核查结果（全部通过）

| 红线项 | 结果 | 依据 |
|---|---|---|
| `build()` / `@Builder` 首条语句不能是 `const`/`let` | ✅ 通过 | 新增 6 个 build/@Builder（`Playlists.ets:156,168,259,404`；`PlaylistDetail.ets:157,253,319`）首条语句均为 UI 组件；`const` 仅出现在 `onTouch` 等事件闭包内，合规 |
| `CustomDialogController` / `DialogAlignment` / `NavPathStack` / `NavDestinationContext` 不得从 `@kit.ArkUI` import | ✅ 通过 | `Playlists.ets:1-6`、`PlaylistDetail.ets:1-6` 的 import 中均无这些符号，全部按全局环境声明使用 |
| 不得用 `@State` 修饰 `CustomDialogController` | ✅ 通过 | `Playlists.ets:38` 为普通成员属性 |
| `@Component` / `@CustomDialog` 上禁用普通 `get` 访问器 | ✅ 通过 | 新文件中 0 个 `get` 访问器；主题色统一走 `getThemeColors(): ColorTokens` 普通方法（`Playlists.ets:46`、`:396`，`PlaylistDetail.ets:41`），符合项目约定 |
| 禁裸 `console.*` / `hilog` | ✅ 通过 | 新增/修改文件中 0 处，全部走 `utils/Logger.ets` |
| 不用对象字面量作类型注解 | ✅ 通过 | 未发现 `arkts-no-obj-literals-as-types` 违规 |
| 静态方法内不用 `this` | ✅ 通过 | `AudioMetaReader.read` / `readViaMediaKit` 均用 `AudioMetaReader.` 显式限定（`AudioMeta.ets:32`） |
| 不做 `instanceof image.PixelMap` | ✅ 通过 | 未出现 |
| `ForEach` keyGenerator 稳定 key | ✅ 通过 | `Playlists.ets:361` → `playlist.id`；`PlaylistDetail.ets:215,438` → `song.id`，均为稳定主键 |
| `@State` 数组/对象整体重新赋值 | ✅ 通过 | `reload()`、`toggleSelect`、`onTouch` 全部走 `[...arr]` 整体赋值（`Playlists.ets:71,248,252`；`PlaylistDetail.ets:68,139,141`） |
| `NavDestination.onShown()` 在 API 24 可用 | ✅ 通过 | `onShown` 自 API 11 起可用，项目 `compatibleSdkVersion` = 6.1.0(23) ≥ 11，`Playlists.ets:376` 合规 |
| `Checkbox().select(...)` 用法 | ⚠️ 语法正确，**交互有缺陷** | 见 P1-8（事件冒泡双触发） |
| `bindSheet($$this.xxx, ...)` 用法 | ✅ 通过 | `PlaylistDetail.ets:449` 双向绑定 + `this.songPickerBuilder()` 调用形式正确；`detents` / `preferType` 属性名合法，与既有 `ControlAreaComponent.ets:105` 用法一致 |
| `bindMenu` 的 `MenuElement` 数组是否需显式类型 | ✅ 通过 | `Playlists.ets:219-232` 的数组字面量作为**值**传入（非类型注解），不触发 `arkts-no-obj-literals-as-types`；`MenuElement` 是具名接口，目标类型可推导 |
| `CustomDialogController` 的 `builder: this.xxxBuilder` 写法 | ✅ 通过 | 与项目既有可用实现 `Settings.ets:50-54` + `@CustomDialog struct PickerDialog { controller: CustomDialogController; ... }`（`:711-714`）完全同构，有工作先例 |
| 路由注册 | ✅ 通过 | `route_map.json:67-82` 已注册 `Playlists` / `PlaylistDetail`，`buildFunction` 与 `Playlists.ets:11` / `PlaylistDetail.ets:11` 导出的 `@Builder` 函数名一一对应；`pageSourceFile` 路径正确 |
| `Mine.ets` 入口下标 | ✅ 通过 | 5 个菜单项下标 0/1/2/3/4（`:244,256,268,292,304`）与 `menuScales` 的 5 元素数组（`:27`）严格匹配 |
| 新页面引用的媒体资源 | ✅ 通过 | `ic_default_cover` / `ic_song_list` / `ic_play_all` / `ic_hm_more` / `ic_back` / `ic_close` 均已存在于 resources |
| `CMakeLists.txt` 是否需改 | ✅ 无需改动 | `audio_metadata.cpp` 已在 `add_library` 列表中（`CMakeLists.txt:8`） |
| NAPI 字段与 ArkTS 声明一致性 | ✅ 通过 | `napi_init.cpp:41-61` 输出 `title/artist/album/duration/sampleRate/channels`，与 `NativeModule.ets:3-10` 的 `AudioMetadata` 接口逐字段吻合。**注意：项目无 `cpp/types/**/index.d.ts`**，该一致性目前靠人工维护，见 P2-6 |
| 死循环风险（`walkAtoms` / MPEG 帧扫描） | ✅ 无死循环 | 三处循环均有最小步进保证（详见 P1-5 说明）；风险仅在递归深度 |

---

*报告生成于代码审查阶段，基于静态只读分析。P0/P1 的行号与代码片段均对应审查时的工作区状态。*

> **2026-08-06 更新**：全部 P0×6 / P1×10 修复已合入并通过 `harmonyos-reviewer` 审查（0 ERROR / 0 WARNING）。`build_hap.sh` 脚本已解决沙箱构建问题，稳定产出签名 HAP（BUILD SUCCESSFUL）。`route_map.json` 现为 **11 条**（新增 `SettingsCategory`）。新增组件 `CoverImageView.ets`（响应式封面）与 `PrivacyPolicy.ets`（隐私政策页）已落地。

> **2026-08-06 NFR 批次更新**：本报告 §8.3 标记为「仍待下迭代」的 P2-6（NAPI 类型声明）、P2-12（NAPI 超长路径动态分配）两项已在本轮落地——新增 `cpp/types/libnative_module/index.d.ts`，`napi_init.cpp` 路径缓冲改为先探长度再动态分配。版本对齐：`AppScope/app.json5` versionName 2.1.0→2.3.0。`bash build_hap.sh` BUILD SUCCESSFUL；harmonyos-reviewer 扫描+审查双脚本 **0 ERROR / 0 WARNING**。完整记录见 `docs/PRD_Lumio_Music.md` §8.5。

---

## 7. 第三轮交互打磨审查补充说明

> 补充对象：第三轮交互打磨（对应 CHANGELOG `v2.3.0`，2026-08-06）
> 审查角色：harmonyos-reviewer ｜ 方式：静态只读审查 ｜ 范围：长按选项栏、两个半模态面板、单一 `bindSheet` 分发、年代全链路、`LrcView` 手动滑动、迷你播放器真实封面

### 7.1 审查结论

- **结论：通过（0 ERROR / 0 WARNING）**。`harmonyos-reviewer` 对第三轮全部改动文件审查结果为 **0 ERROR / 0 WARNING**（另 2 条 INFO 为 `componentSnapshot.get` 既有噪音，非本轮引入）。
- **ArkTS 红线项零复现**：`build()`/`@Builder` 首条语句非 `const`、无普通 `get` 访问器、无裸 `console`/`hilog`、无 `ESObject` 中转赋值、稳定 `ForEach` key、对象字面量非类型注解、`@State` 整体赋值等历史红线项，本轮新增/修改代码均符合。
- **新增组件合规**：`components/SongDetailSheet.ets` / `AddToPlaylistSheet.ets` 仅使用 `@Builder` + `bindSheet` 组合，未引入受控权限；`@Builder sheetContent()` 按 `sheetKind` 分发，单一 `bindSheet` 绑定符合 ArkUI 规范（避免多绑定后者覆盖前者）。

### 7.2 覆盖范围与验证

| 审查点 | 对应 PRD / 拆解表 | 结果 |
|---|---|---|
| 长按 `bindContextMenu(menu, ResponseType.LongPress)` 选项栏（五页） | FR-25 / T-01 | ✅ 0 ERROR / 0 WARNING |
| 单一 `bindSheet` + `sheetKind` + `@Builder sheetContent()` 分发 | FR-26/27 / T-02/T-03 / S-03 | ✅ 红线零复现 |
| `SongDetailSheet.ets` 详情面板（年代异步读） | FR-26 / T-02 / I-01/I-02 | ✅ 合规 |
| `AddToPlaylistSheet.ets` 添加到歌单（去重/新建） | FR-27 / T-03 | ✅ 合规 |
| 年代全链路（C++ `year` → NAPI → `AudioMeta.year` → 面板） | FR-28 / T-04 | ✅ 合规；year 不落 `SongItem` |
| `LrcView.ets` 手动滑动（onTouch 状态机） | FR-29 / K-05 | ✅ 合规 |
| 迷你播放器真实封面（一镜到底两端一致） | FR-30 / F-01 | ✅ 合规；保留 `geometryTransition('player_cover', {follow:true})` |

### 7.3 与既有审查的关系

- 本报告 §1~§6（PRD 落地批次）、`docs/代码审查报告_第二轮增强.md`（第二轮增强批次）的结论与整改均不受影响；本轮改动未触及 C++ 内存安全红线（`audio_metadata.cpp` 仅增量补充 `year` 字段解析，未改既有边界逻辑）。
- ArkTS 红线基线（本报告附录）在第三轮继续保持零复现。
