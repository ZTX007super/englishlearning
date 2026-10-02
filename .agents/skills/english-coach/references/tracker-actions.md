# Tracker 动作与参数契约

本文件是 v4 动作参数的唯一说明。入口固定为本 skill 目录下的 `scripts/tracker.ps1`；从项目根目录调用时是 `.agents/skills/english-coach/scripts/tracker.ps1`。所有响应都返回 `next_action_contract`，其中 `kind=tracker` 才表示立刻调用 tracker；`interaction` 表示先与学习者交互。

## 共同规则

- 开始/继续学习用 `Bootstrap -EnterSession -IdempotencyKey <稳定请求编号>`；进度或计划查询用普通 Bootstrap。新 session 标记 `classroom_version=1`，旧 session 不转换。逐题课堂参数见下表及 [classroom-flow.md](classroom-flow.md)。

- 只执行响应中的 `next_action`。每次写动作都使用新的、稳定且能描述逻辑动作的 `IdempotencyKey`；同一动作重试复用原 key 和完全相同的 payload。
- `SessionId`、`OwnerToken`、`ExpectedRevision` 取自最近一次响应的 `receipt` 或 `prepared_step`；revision 每次成功写入后使用新回执值，不能猜。
- `PayloadJson` 是相应 reference 定义的完整 JSON 对象经序列化后的字符串，不是文件路径。
- `SourceType` 表示**调用者为本次启动声明的材料取得来源**：`network | user-provided | fallback | none`。它不表示 tracker 最终解析到哪个缓存；实际解析结果只看 `prepared_step.package_source`，fallback 降级只看 `evidence_mode_cap` 和 `reason_code`。正常命中项目缓存时传 `none`。

## 动作表

| `next_action` | `-Action` | 必需参数 | 参数来源与完成标志 |
| --- | --- | --- | --- |
| `bootstrap` | `Bootstrap` | 无 | 成功后服从新的 `next_action`。 |
| `prepare_review_questions` | `PrepareReviewQuestions` | `SessionId, OwnerToken, ExpectedRevision, IdempotencyKey, PayloadJson` | payload=`{questions:[{review_item_id,prompt_text,task_contract}]}`，覆盖冻结切片且顺序一致；成功返回第一题。 |
| `present_review_question / repair_review / reconstruct_review` | 先交互，后 `SaveReviewAnswer` | 同上 | 先展示反馈，payload 只含题号、首答结果或修复变化，详见 classroom-flow；回执同时返回下一动作，最后一题正常直接返回主课。 |
| `retry_classroom_transition` | `Bootstrap -EnterSession` | `IdempotencyKey` | 恢复已存复习后的主课准备；一次恢复仍失败则报告阻塞。 |
| `start_session` | `StartSession` | `IdempotencyKey` | 可选 `PlanItemId=prepared_step.next_plan_item_id`、`SourceType`；成功回执给出 session、owner、revision。 |
| `confirm_next_cycle_plan` | 先确认计划，再 `PublishCycle` | `IdempotencyKey, PayloadJson` | 已确认的计划无需重复询问；按 [cycle-publication.md](cycle-publication.md) 编译 payload，committed receipt 后 Bootstrap。 |
| `prepare_activity` | `PrepareActivity` | `SessionId, OwnerToken, ExpectedRevision, IdempotencyKey, PayloadJson` | 前三项来自最近回执；payload 按 [activity-preparation.md](activity-preparation.md) 构造。完成标志是 `next_action=present_activity` 且返回完整 contract。 |
| `present_review` | 无 | 无 | 使用冻结的 `prepared_step.review_items` 出题并先收答；随后调用 `StageReviewBatch`。 |
| — | `StageReviewBatch` | `SessionId, OwnerToken, ExpectedRevision, IdempotencyKey, PayloadJson` | 只提交已展示、已作答、已反馈的一批；成功回执给出新 revision 和下一动作。 |
| `present_activity / await_answer / clarify / repair` | 先交互，后 `SaveActivityCheckpoint` | `SessionId, OwnerToken, ExpectedRevision, IdempotencyKey, PayloadJson` | 每轮反馈后保存一次；首答冻结，后续只存修改。payload 与恢复规则见 [teaching-loop.md](teaching-loop.md#主课修复的保存与恢复)。 |
| `show_transfer` | `PrepareActivity` | 同上 | 使用新 activity ID 准备完整迁移契约；成功后展示。 |
| `finalize_session` | `FinalizeSession` | `SessionId, OwnerToken, ExpectedRevision, IdempotencyKey, PayloadJson` | payload 至少含 `feedback_shown=true`、非空 `session_summary`、`duration_minutes`；cycle review 另含 `goal_decision`。只有 committed receipt 才算结课。 |
| — | `AbandonSession` | 同 Finalize | 仅用户明确放弃；payload 保存可提交的已反馈事实。 |
| `evaluate_cycle_review` | `EvaluateLongTermState` | `SessionId` | 当前复盘回执给出 ID；tracker 加载有界正式证据并返回候选。无需 PayloadJson。 |
| `present_cycle_review_candidates` | 无 | 无 | 展示证据、候选与覆盖限制，讨论计划；总结展示后按候选填写 goal_decision 并 FinalizeSession。 |
| — | `EvaluateLongTermState` | `PayloadJson` | 原有 assessment/reducer 接口；普通轮次复盘使用上面的 SessionId 接口。 |
| — | `Validate` | 无 | 维护态使用；普通学习不调用。 |

## PowerShell 形状示例

新逐题课堂不用 StageReviewBatch；该接口仅供旧 session，避免重复写同一复习切片。返回 metrics 中 `script_elapsed_ms` 只测 tracker 调用内部，`response_bytes_without_metrics` 是压缩后的主体大小；未知模型/用户等待为 null。性能字段不改变教学判断。

```powershell
$tracker = Join-Path $ProjectRoot '.agents\skills\english-coach\scripts\tracker.ps1'
& $tracker -Action StartSession -PlanItemId $boot.prepared_step.next_plan_item_id `
  -SourceType none -IdempotencyKey 'start-P2026W37-D2-v1'

& $tracker -Action PrepareActivity -SessionId $start.receipt.session_id `
  -OwnerToken $start.receipt.owner_token -ExpectedRevision $start.receipt.revision `
  -IdempotencyKey 'prepare-SESSION-lead-v1' -PayloadJson $contractJson
```

示例只说明取值关系；真实调用始终使用当前响应中的值，不能照抄示例 ID。
