# Lumio Music · 文档索引（docs/）

> 本目录为项目文档总入口。2026-09-13 完成「重复/同类型文档合并整理」：将 4 组同类文档非破坏性合并为统一文件，原始文件移入 `archive/` 保留历史（不删除）。合并以「保留全部原始内容（union）」为原则，冲突处以代码 `AppScope/app.json5` 为权威来源。

## 合并后的核心文档（4 个）

| 文件 | 内容 | 由以下原始文档合并 |
|------|------|-------------------|
| `PRD.md` | 产品需求文档（FR/NFR 基线、验收标准、风险、里程碑） | `PRD.md`（主体）+ `PRD_Lumio_Music.md` |
| `设计系统.md` | 设计系统（令牌架构为技术真相来源 + Apple 设计语言 + UI 设计系统） | `UI重设计_设计令牌架构.md` + `design_tokens.md` + `设计系统_Apple.md` + `UI设计系统.md` |
| `审查报告.md` | 审查报告（按 架构 / 合规 / 安全 / 设计 / Sheet / 卡片主题 / 完成度复验 分区） | `review_architecture.md` + `代码审查与API26升级报告.md` + `review_compliance.md` + `review_security.md` + `review_design.md` + `代码审查报告_PRD落地.md` + `代码审查报告_第二轮增强.md` + `UI重设计_Sheet合规审查.md` + `UI重设计_Sheet_apple重设计.md` + `UI重设计_Sheet整改方案.md` + `审查报告_卡片主题修复.md` + `UI重设计_完成度审查与遗漏项.md` + `UI重设计_P0复验清单.md` + `代码排查与UI审查报告_2026-09-12.md` |
| `实施计划.md` | 实施计划（单一时间线，M1~M2 细化到文件级） | `UI重设计_范围与规划.md` + `实施计划_PRD落地.md` + `实施计划_第二轮增强.md` |

## 独立保留的文档（未合并，各具唯一性）

- `功能模块拆解表.md` — 模块→文件映射（A~W 共 23 个一级模块）
- `AI协作复盘报告.md` — AI 协作过程复盘
- `C++解析器真实音频验证.md` — C++ 解析器真实音频验证
- `课程项目总结报告.md` — 课程项目总结（含 PDF `课程项目总结报告.pdf`）
- `课程最终作业提交清单.md` — 课程最终作业提交清单
- `privacy_policy.md` — 隐私政策
- `API.md` — API 参考（方法签名采信自原 `review_architecture.md` §3；原审查报告已并入 `审查报告.md`）
- `feature_opportunities.md` — 特性机会清单
- `2026-08-29-新特性落地小结.md` — API 26 四项新特性落地小结

## 资源文件

- `图标库索引.json` — 图标库索引
- `images/` — 图片资源目录
- `icon_preview.png` — 图标预览
- `课程项目总结报告.pdf` — 课程总结 PDF 版

## 归档（历史保留，勿删）

- `archive/` — 上述 22 个被合并取代的原始文档。因合并为非破坏性（合并文件中以「来源：`原名`」小节完整保留），归档仅用于清理根目录；如需追溯单篇原文可直接查阅 `archive/` 或合并文件内对应小节。

## 口径冲突纪要（需用户确认）

1. **版本号**：代码 `AppScope/app.json5` 实际为 `versionName "3.0.0"` / `versionCode 3000000`，与文档一致 → 采用 **3.0.0**（任务初始假设的「v2.4.0 / 2040000」与代码不符，以代码为准）。PRD 内部里程碑仍沿用 v2.3.1 / v2.4.0 / v2.5.0 / v3.0.0 编号（M1~M4），属规划口径。
2. **包名大小写**：代码 `com.Lumio.music`（L 大写）；部分审查文档写作 `com.lumio.music`（小写），以代码为准（见 PRD OQ-01）。
3. **API 基线**：多数文档目标 API 24 / HarmonyOS 6.1.1；`代码审查与API26升级报告.md` 与 `UI重设计_Sheet整改方案.md` 记录向 **API 26 / HarmonyOS 26.0.0** 升级（动态 import `uiMaterial`，catch 兜底），属演进中工作，予以保留。
4. **令牌文档版本**：`UI重设计_设计令牌架构.md` 为 v2.0，`design_tokens.md` 为 v1.0 奠基版，二者互补；以令牌架构为权威技术来源。

## 仍指向旧文档名的外部引用（待用户处理，未改动代码）

- `README.md`、`overview.md` 的文档树/表格已更新为合并后的文件名。
- `CHANGELOG.md:15` 仍提及 `PRD_Lumio_Music` / `UI 重设计范围` / `设计系统 Apple` 作为版本对齐说明（属历史记录，建议保留或加注）。
- `docs/API.md`（§5/§6/§62/§757）引用 `review_architecture.md` / `review_security.md` / `review_compliance.md` → 现对应合并版 `审查报告.md` 的相关小节。
- `docs/feature_opportunities.md`（§4/§45/§169）引用 `review_design.md` / `design_tokens.md` → 对应 `审查报告.md`（设计小节）/ `设计系统.md`。
- `docs/2026-08-29-新特性落地小结.md:38` 引用 `代码审查与API26升级报告.md` / `UI设计系统.md` → 对应 `审查报告.md` / `设计系统.md`。
- `docs/课程项目总结报告.md`（§55/§182/§184/§185）与 `docs/课程最终作业提交清单.md`（§16/§18/§19）引用多个旧审查/计划文件名 → 对应合并版 `审查报告.md` / `实施计划.md` / `PRD.md`。
