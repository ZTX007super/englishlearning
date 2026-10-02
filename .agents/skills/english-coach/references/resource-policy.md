# 材料、缓存与权利规范

只有在编译课包、检查可呈现性、处理材料局部失效，或用户明确询问当前考试规则时读取。本文件定义安全边界；正常缓存命中的日课不在开课时重新查页。

## 缓存优先

永远优先最近一代**安全、完整、与当前 queue guard 和冻结契约兼容**的旧缓存。自然时间本身不使普通语言材料失效，也不为了更“新”而在线替换。

兼容性与新鲜度分开：

- 日期或 review revision 变化只重绑 review。
- 已暴露或可比性不足但仍可安全教学的材料，只能降为同构念 `training`。
- 内容、考试 adapter、权利或 asset 层可以局部失效，不连带丢弃其他安全层。
- Queue、用户确认计划、focus、policy、catalog、ladder、contract、checksum 或权利边界不符时硬拒绝。

## 可安全呈现门

材料在展示前必须同时满足：

1. 本次需要的正文/音频、transcript、题面、答案或评分范围完整且可访问。
2. 内容与 metadata、content/context ID、hash 一致。
3. 事实没有已知错误。历史性内容可以标记 `as_of` 后用于 training，但不能当作当前事实评分。
4. 涉及当前官方考试结构、规则或换算时，authority record 对本次 `test_date` 仍适用。
5. 来源、许可或项目原创声明足以支持本次展示和本地保存。

`training` 不能豁免错误信息或版权。权利状态不清或明确禁止展示时，受影响材料不可用。

## 编译期选择

日常与学术英语优先免费、合法、无需登录的教育机构、大学、公共媒体和官方发布者。同等质量下选择有可靠音频与 transcript、长度适合当前 contract、并满足冻结 material constraints 的来源。

在轮次边界或滚动编译时验证：

- 标题、发布者、URL、访问/验证日期；
- 内容发布日期及 `as_of`；
- 近似 level/material profile，但不把材料等级等同于学习者 CEFR；
- content/context ID、checksum；
- 权利状态、许可说明及允许保存的范围；
- 可用 modality、音频、transcript、题面与 scoring key。

会话正式记录只保存必要 metadata、使用片段的引用和自行设计的练习；不复制完整受版权保护文章、字幕或音频。用户提供并明确要求保留的材料仍受其授权范围限制。

## 当前考试规则

TOEFL 结构、题型、评分和换算只使用 ETS 当前官方页面或用户提供的官方材料。不要把某次核验结果永久写成无日期规则。

Authority record 至少保存：

- URL、`verified_at`、内容 hash；
- `effective_from / effective_to`；
- `applies_to_test_date`；
- `revalidate_after`；
- 当前包实际引用的 claim。

只有轮次/测评编译、用户要求当前规则或 authority record 到达明确复核条件时联网核验；普通日课启动不重复核验。无法确认时移除“当前官方”说法，使用版本中立 training；内部估计始终标注非 ETS 官方。

## 一次外部替代

只有缓存主材料未通过可呈现门时，才允许一次有界 search/parse：

- 不递归搜索、不连续换站、不在课中排障。
- 新材料必须通过同一来源、权利、metadata 和冻结 contract 检查。
- 新材料一律为 `training`，不能为了维持正式证据资格而降低标准。
- 最迟在 `min(request_started_at + 60 秒, deadline_at - 20 秒)` 停止；迟到结果只可供未来课包。
- 超时或仍不合格时，立即使用 tracker 返回的同队首本地 fallback。

## 本地 fallback

[fallback manifest](../assets/fallback/manifest.json) 是机器索引，[fallback-materials.md](../assets/fallback-materials.md) 是人类可读目录。

每个可发布 skeleton 必须有同队首、同核心 construct 的自包含 fallback：

- 阅读文本可本地保存原创、公共领域或许可清晰的必要内容。
- 听力必须有可播放本地音频、准确 transcript、内容 hash 和权利记录；只有文字或待生成音频时 `presentable=false`。
- URL-only、登录后可用、仅流媒体、缺失评分范围或权利不明的条目不能作为 ready fallback。

Fallback 固定为 training，不惩罚学习者，也不能冒充官方 TOEFL 材料或真实来源录音。
