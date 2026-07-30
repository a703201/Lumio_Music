# 鸿蒙应用规范审查报告

- 审查目标：`D:/Codes/Project/HM_Player`
- 扫描文件数：61
- compileSdkVersion：None
- compatibleSdkVersion：None
- 声明权限数：4
- 目标设备：phone
- 发现：🔴 ERROR 0 ｜ 🟡 WARNING 0 ｜ 🔵 INFO 2

> 说明：本报告基于内置 `api_matrix.json`（starter 知识库）静态分析生成；`confidence: medium` 的条目及未覆盖 API 建议以华为官方文档为准（见 references/doc_sources.md）。

## 问题清单

| 级别 | 文件:行 | 规则 | API/项 | 说明 | 建议 |
|---|---|---|---|---|---|
| INFO | D:/Codes/Project/HM_Player\entry\src\main\ets\common\utils\BreakpointSystem.ets:46 | api-context | componentSnapshot.get | 无法静态确定调用上下文，请确认是否在允许范围 ['ui-component'] | 可结合源码人工确认，或补充 api_matrix.json 的上下文约束。 |
| INFO | D:/Codes/Project/HM_Player\entry\src\main\ets\common\utils\ColorConversion.ets:106 | api-context | componentSnapshot.get | 无法静态确定调用上下文，请确认是否在允许范围 ['ui-component'] | 可结合源码人工确认，或补充 api_matrix.json 的上下文约束。 |

## 下一步

1. 优先修复所有 ERROR（build 副作用、上下文违规、版本不足、权限缺失、Worker 误用 UI）。
2. 处理 WARNING：核对官方文档、补充权限、迁移废弃 API、修正组件嵌套。
3. INFO 项多为静态无法判定，需结合源码人工确认。
4. 将核实后的新规则回填 `references/api_matrix.json`，扩充覆盖率。