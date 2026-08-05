# Lumio Music — 六项体验修复交付概览

> HarmonyOS 6.1.1 / API 24，ArkTS/ArkUI。本会话由「鸿蒙全流程专家团」编排：`code-developer` 实现 → `code-reviewer` 静态合规审查 → 主理人复核并落地两处优化。沙箱禁 hvigor，**未在本地构建**，请在 DevEco 执行 `hvigor assembleHap` 验收。

## 1. 歌词只显示两个样例歌曲（Issue 1）
- **根因**：`EmbeddedLyricReader.parseMp4DataAtom` 仅 `decodeUtf8`，UTF‑16 编码的 `©lyr` 被解成乱码（无 `[mm:ss]` 时间戳）→ `parseLrcLyric` 返回空。
- **修复**：
  - 新增 `detectAndDecode()`：依次处理 UTF‑16 LE/BE（含 BOM）、UTF‑8（含 BOM），无 BOM 但奇数位 `0x00` 占比 >0.3 推断为 UTF‑16 LE，其余按 UTF‑8。
  - `parseMp4DataAtom` 两处解码改用 `detectAndDecode`。
  - `parseMp4` 增加裸 `lyr` atom 兜底（并收紧末端偏移，避免 4 字节尾噪）。
  - `LyricsComponent.getLrcEntryList` 增加诊断日志（`embeddedLen` / `finalLyricCount`），便于确认修复效果。

## 2. “词”图标作为翻译开关（Issue 4）
- `LyricsComponent`：`@State showTranslation`，图标 `onClick` 切换 + 关闭时 `.opacity(0.4)`，传入两个 `LrcView`。
- `LrcView`：`@Prop showTranslation @Watch('onTranslationToggled')`，关闭时不绘制翻译并收起其间距（`getLineHeight`/`getOffset` 同步门控）。

## 3. 原歌词与翻译间隔加大（Issue 3）
- `LrcView` 新增 `mTranslateGap = 14`vp，`drawLyricLine` 与 `getLineHeight` 翻译块均加入该间隔，绘制与滚动偏移一致。

## 4. 歌词颜色随背景自适应（Issue 2）
- `PlayerInfoComponent.getImageColor()` 计算封面主色相对亮度，`AppStorage.setOrCreate('lyricBgDark', lum<=0.5)`。
- `LyricsComponent` 增加 `@StorageProp('lyricBgDark')` 并传入 `LrcView`。
- `LrcView`：`@Prop backgroundIsDark @Watch('onBgChanged')` + `applyColorScheme()`，深底用浅字（原默认）、浅底用深字，渐变随之适配。

## 5. 播放页背景强高斯模糊（Issue 5）
- `PlayerConstants.IMAGE_BLUR` 15 → 60。
- `PlayerInfoComponent` 背景 `Image` 在 `.opacity(0.5)` 后追加 `.blur(IMAGE_BLUR)`（对预模糊 PixelMap 与 Resource 兜底均生效）。

## 6. 导入/重启后封面不刷新（Issue 6）
- **根因**：`getMark()/getLabel()` 读非响应式 `CoverCache` 单例，仅 `PlayerInfoComponent` 监听 `coverRefreshToken`。
- **修复**：`LocalLibrary`/`Favorites`/`PlayHistory`/`Find`/`ManageSongs`/`Layout` 均增加 `@StorageProp('coverRefreshToken') @Watch`，handler 重新赋值 `@State` 歌曲数组触发重绘；不改封面抽取管线。`LocalLibrary` 的 handler 额外保留当前搜索过滤与 `itemScales`。

## 合规审查结论
- `code-reviewer` 确认：**无阻塞性问题**。ArkTS 红线（build/@Builder 首语句非 const/let、无普通 `get` 访问器、统一 `Logger`、无 `instanceof PixelMap`、无对象字面量类型注解）均符合；装饰器与 `@Watch` 处理方法正确；裸 `lyr` 对齐无越界。
- 已消化的两条优化：裸 `lyr` 末端偏移收紧、`LocalLibrary` 刷新时保留搜索过滤。

## 验收步骤（DevEco）
1. `hvigor assembleHap` 构建通过（本机会话无法代验）。
2. 导入若干 UTF‑16 内嵌歌词的 m4a/mp4，确认歌词显示（看 Log `embeddedLen>0`、`finalLyricCount>0`）。
3. 歌词页右下角“词”图标点击 → 翻译显隐切换。
4. 切换深浅封面歌曲，确认歌词文字明暗自适应、可读。
5. 观察原文/翻译之间间距明显。
6. 播放页背景明显高斯模糊。
7. 导入歌曲后立即看到封面；重启应用后各列表页封面正常显示（不再回退默认）。
