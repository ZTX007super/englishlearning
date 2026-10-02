# C0003 legacy 运行协议

本文件只用于恢复和完成 C0003 或其旧版进行中会话。它不是 C0004 的规则来源。

## 进入条件

- `Bootstrap` 明确返回 v3，或旧 tracker 尚未返回 `runtime_version`。
- 已存在的 v3 checkpoint、session 或 pending review transaction 必须先按旧协议恢复；不得迁移成 v4，也不得补造 v4 证据字段。
- C0003 的严格队列、既有复习排程和已冻结计划保持不变。

## 运行

1. 调用 legacy `Bootstrap`。只使用它返回的 `status`、`checkpoint`、`next_plan_item`、`recovery_mode`、已选择 due items 和 metrics；不自行重算队列或到期日。
2. `status=resume` 时 checkpoint/session 优先于 `recovery_mode` 和新 due selection；`recovery_mode` 只调整旧容量，不改变恢复位置。按 `last_completed_stage` 的下一阶段继续；checkpoint 与 session 不一致时不启动第二课、不自行修补正式数据，先报告技术恢复问题。
3. 按 `review → input → output → feedback → summary` 逐步展示，每次只要求一个当前动作。参考 [legacy session 模板](../assets/session-template-v3.md) 完成同一 session 文件，不创建第二份。
4. v3 review 使用 vocabulary/error 的旧排程和 legacy `ReviewBatch`；该动作会在 review 阶段正式写入。不要改用 v4 review item、pending batch 或课末 WAL，也不要把旧结果补造为 recall/transfer。
5. 每完成 legacy `review / input / output / feedback` 主阶段，调用一次 `Checkpoint` 保存简短摘要。旧 `output` checkpoint 位于 output 与 feedback 之间，这是 C0003 的兼容行为，不享受 v4 的零 I/O 延迟保证，也不得再插入额外工具。恢复时继续未完成阶段，不因跨日、退出或断线自动放弃；只有 checkpoint 而无可靠对话上下文时，不推断首答或反馈已经发生。
6. 可评分活动先保存无提示首答；流利度输出结束后再反馈。最多处理三个重点，语音听写只作可懂度线索。v3 结果不得反推为 v4 contract、support、transfer、A 类证据或 competency 状态。
7. C0003 尚无 ready package 时，允许按旧行为选择一份短、合法、可访问来源；联网失败立即使用 [现有原创文字 fallback](../assets/fallback-materials.md)。这些文字不能冒充真实听力输入。不要为了等待更好来源反复联网。
8. 课程完成后，先按 legacy 模板把同一 session 记为 `completed`，再调用一次 legacy `FinalizeSession`。这个预写终态是旧接口的必要输入，不是 v4 committed receipt；只有动作返回 `status=completed` 才向学习者报告完成。若动作报错，不开始或宣布下一课，不回滚或重放 review，保留稳定 session ID 并报告“保存尚未确认”的技术状态。它按 v3 实际接口重建和校验；成功后不额外调用 Rebuild/Validate。
9. 只有学习者明确放弃时，先把 legacy session 记为 `abandoned`，再调用 `AbandonSession`。不要混入 v4 receipt、WAL、ready package 或新 review 语义。

轮次复盘仍使用 [weekly-review-template.md](../assets/weekly-review-template.md)；legacy assessment 使用 [assessment-template-v3.md](../assets/assessment-template-v3.md)。这些模板只为完成 C0003，不能用于创建 C0004 事实。

## 迁移边界

- C0003 轮次复盘可以准备 C0004 所需的新目录、空投影和计划候选，但只有用户确认下一轮且 v4 启用门通过后才能切换。
- 同一 session 从开始到终局只使用一个 runtime version。
- 旧历史保持原样；未知字段为空或 `unknown`，不能通过推断回填。
