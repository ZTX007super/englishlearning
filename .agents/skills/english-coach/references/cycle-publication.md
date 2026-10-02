# 轮次发布

当 Bootstrap 返回 `confirm_next_cycle_plan` 时读取。空队列表示上一轮结束，先沿用复盘中已确认的焦点与计划选择；未确认的实质变化才询问学习者。

1. 依据已提交复盘与确认内容编译下一轮六课和一个轮次复盘，保持听说读写覆盖。每项准备带完整 core 的 ready package；`plan_id` 使用紧邻下一编号，`plan_item_id` 使用唯一 ID。独立检查使用新情境、无答前提示，并事先明确 `evidence_mode=target_check`；复用已暴露材料只形成 training。
2. 调用 `PublishCycle -IdempotencyKey <稳定键> -PayloadJson <下述对象>`。成功标志是 `receipt.status=committed`，随后 Bootstrap 确认新的真实队首；发布本身不开始上课。
3. 调用中断后先 Bootstrap；它只恢复已有 publication intent。同 key 重试必须使用相同 payload。不得自行重置旧计划、重放 ActivateV4 或清空旧证据。

Payload 必需字段：

- `from_cycle_id`、`to_cycle_id`：相邻的 `Cdddd` 编号。
- `user_confirmed=true`、`confirmation_ref`：实际用户确认的消息或已提交复盘记录的引用，不能代用户确认。
- `plan_items`：按 sequence 1–7 排序，字段与 v4 plan 表相同；初始 status=planned、completed_session_id 为空、required=true；前六项为 focus/maintenance，最后为 session_type=review、plan_role=cycle_review。
- `packages`：每个 plan item 一个 schema_version=1、status=ready 的包，身份与版本匹配；包含 activity_skeletons、权利信息、blueprint_path 与 blueprint_sha256。core 必须可解析且通过校验。

沿用目标时省略 `next_goal`。更换或重设目标时附 `next_goal`：提供新的 `goal_id`、`goal_key`、`stage_id`、`skill`、`competency_id`、`competency_family`、`activity_family`、`quality_focus`、`goal_text`、`success_criteria_json`、`min_completed_cycles=2`、`max_completed_cycles=2|3|4`。success_criteria_json 为 [goal-review.md](goal-review.md#结构化目标契约) 中对象序列化后的字符串。所有 focus 和 cycle_review 项及课包关联新的 goal ID。程序分配版本、supersedes_goal_id、起始轮次、状态和时间，忽略调用者对这些派生字段的填写。

已提交决定是 met 或 redesign 时，发布需包含已确认的下一目标。若希望继续巩固，建立说明巩固目的的新目标版本。旧目标的文字与标准保留；已 met 的旧目标保持达成历史，否则标记 superseded。沿用或更换都仍需真实的 user_confirmed 和 confirmation_ref。示例计划输入见项目根目录 `maintenance/examples/c0005-publication.json`；它是沿用旧目标的历史示例，不照抄历史确认。

发布事务依次保存 intent、目标版本（如有）、包、追加计划、归档上一轮短证据并建立空的新轮索引、发布队首、写 committed receipt。中断由 Bootstrap 完成同一事务，各阶段幂等；新旧目标与计划在 committed 前不报告为已生效。既有课程、能力等级和 review 到期日不变。上一轮短证据另存 `.state/cycle-evidence/<from_cycle_id>.json`。
