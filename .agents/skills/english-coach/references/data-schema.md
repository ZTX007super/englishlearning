# 学习数据格式：版本路由

先读取 `learner/settings.json` 和当前 session checkpoint，再选择数据规范。数据版本和单次 session 协议必须冻结；同一 session 中不能混用两个版本。

- `schema_version` 缺失或为 `3`：读取 [data-schema-v3.md](data-schema-v3.md)。C0003 的既有、待开始和复盘数据继续使用此规范。
- `schema_version = 4`、v4 激活 receipt 已提交且 session 未冻结旧协议：读取 [data-schema-v4.md](data-schema-v4.md)。
- 恢复中的 session：始终读取 checkpoint 内的 `protocol_version`；缺失时按 v3 legacy session 处理。
- 迁移未完成、激活 payload 无效或 receipt 未提交：保持 v3，不根据新文件是否存在猜测版本。

v4 的 gate 与任务条件分别只引用 [competency-catalog.json](competency-catalog.json) 和 [difficulty-ladders.json](difficulty-ladders.json)。迁移 payload 与启用门只引用 [migration-v4.schema.json](migration-v4.schema.json)。

这些说明本身不授权修改真实学习数据。任何切换必须满足 v4 规范的 dry-run、快照、恢复和激活门。
