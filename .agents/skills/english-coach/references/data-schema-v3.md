# 学习数据格式

所有学习日期使用 `YYYY-MM-DD`。TSV 文件必须保持制表符分隔和 UTF-8 编码。除非显式传入测试日期，日期、到期和连续学习天数都按 `learner/settings.json` 中的学习时区计算。

## learner/settings.json

- `schema_version`：当前数据结构版本；队列模型为 3。
- `schedule_mode`：固定为 `queue`，表示按顺序推进而非按日历排课。
- `study_timezone`：IANA 时区；本项目固定为 `Asia/Shanghai`。
- `windows_timezone_id`：PowerShell 对应时区 `China Standard Time`。
- `week_starts_on`：仅供周日提醒等日历功能使用，不影响队列。
- `daily_target_minutes`、`progress_window_days`：日课目标分钟与学习量统计窗口。
- `training_sessions_per_cycle`：每轮训练项数量，当前为 6；其后才是轮次复盘。
- `recovery_gap_days`：触发恢复模式的中断天数，当前为 7。

不得使用 Codex 运行环境的本地日期替代学习时区日期。

## learner/plan-items.tsv

列顺序固定：

`plan_item_id, plan_id, sequence, title, session_type, primary_skill, required, status, completed_session_id`

- 每个队列课次占一行，`plan_item_id` 永久唯一；一轮共享一个 `plan_id`，如 `C0001`。
- 同一轮按 `sequence` 严格取最早的非终止项；未来项目不能因日历日期而跳过。
- `required` 只能是 `true` 或 `false`；`status` 只能是 `planned`、`in_progress`、`completed` 或 `cancelled`，不存在 `missed`。
- `completed` 必须引用真实存在、且 frontmatter 中反向引用该计划项的 `session_id`。
- `cancelled` 只能通过 `CancelPlanItem` 写入，原因追加到 `learner/plan-events.tsv`。

## learner/plan-events.tsv

列顺序固定：

`event_id, occurred_at, study_date, plan_item_id, event, reason`

这是计划状态的重要历史记录。取消队首项目时必须保存非空原因；不得为了跳过队列而直接改 TSV。

## learner/vocabulary.tsv

列顺序固定：

`id, item, meaning, context, status, level, next_review, last_review, source_session`

- `id`：`V` 加四位数字，如 `V0001`。
- `status`：`active`、`mastered` 或 `paused`。
- `level`：0–5，对应 1、3、7、14、30、60 天复习间隔。
- 新项目从 level 0 开始，`next_review` 通常设为下一天。
- `source_session` 必须是引入该项目的 `session_id`，不能只写日期。

## learner/error-log.tsv

列顺序固定：

`id, category, original, corrected, explanation, status, level, next_review, last_review, source_session`

- `id`：`E` 加四位数字。
- `category`：如 `grammar`、`word-choice`、`organization`、`listening`。
- 只记录可能复发、值得间隔复习的问题，不收集一次性笔误。
- `source_session` 必须引用真实 session。

## learner/review-history.tsv

列顺序固定：

`event_id, reviewed_at, study_date, session_id, item_type, item_id, result, old_level, new_level, previous_due, next_review`

- 此表只追加，不覆盖也不手工改写历史事件。
- `item_type` 为 `vocabulary` 或 `error`；`result` 为 `again`、`hard`、`good` 或 `easy`。
- `reviewed_at` 包含上海时区偏移；最新事件应与当前词汇表/错误表的 level、last_review、next_review 一致。
- 每个复习环节优先通过追踪器的 `ReviewBatch` 一次提交。追踪器先写入 `.state/review-transaction.json`，再追加历史并更新当前状态；中断后由 `Bootstrap` 幂等恢复。单项 `Review` 仅保留兼容性。
- `Bootstrap` 默认从全部到期项目中按到期日、等级和 ID 选择最多 6 项；恢复模式最多 10 项。返回值中的 `due_counts` 保留完整数量，`due_vocabulary` 与 `due_errors` 只包含本课选择。仅在确实需要完整清单时传入 `-IncludeAllDue`；兼容动作 `Due` 始终返回完整清单。正常启动不重写持久数据；只有会话记录与计划状态不一致时才原子修复计划表，并以 `plan_state_reconciled` 报告。

## learner/skill-evidence.tsv

列顺序固定：

`evidence_id, session_id, skill, phase, metric, score, scale, evidence, next_focus`

- `phase` 为 `raw`、`revised` 或 `assessment`。诊断必须先保存未提示的 `raw` 证据，反馈后的重试另记为 `revised`。
- `score` 可以为空；非空时 `scale` 也必须是正数，并明确 `metric`，不得把内部量表冒充 ETS 官方分数。
- `evidence` 只保存必要表现摘要，不复制完整私密对话；`session_id` 必须引用真实 session。

## sessions

每次会话保存到 `sessions/YYYY/MM/YYYY-MM-DD.md`；同日多次时使用 `-02`、`-03`。YAML frontmatter 至少包含：

- `session_id`
- `date`
- `plan_item_id`（临时加练可写 `none`）
- `session_type`
- `status`
- `duration_minutes`
- `primary_skill`
- `study_timezone`
- `source_type`

`session_type` 为 `daily`、`diagnostic`、`review`、`assessment` 或 `extra`；`status` 为 `in_progress`、`completed` 或 `abandoned`；`source_type` 为 `network`、`user-provided`、`fallback` 或 `none`。正文保存目标、材料来源、学习者表现摘要、最多三个重点反馈、新增/复习项目和下一步。不要保存无关隐私。

## .state/current-session.json

- 这是当前课程的临时检查点，默认不纳入 Git。`StartSession` 在任何复习事件之前同时创建 session stub 和此检查点，避免悬空引用。
- 保存稳定的 `session_id`、`plan_item_id`、上海学习日期、课程类型、主技能、最后完成环节和各环节的简短摘要。
- 每完成 `review`、`input`、`output`、`feedback` 中的一个环节即原子写入一次。
- 完成的 session 归档后由 `FinalizeSession` 校验四个环节、链接计划项、重建并验证，并在返回值的 `archive` 中报告结果。成功后不要再重复运行 `Rebuild` 和 `Validate`。兼容动作 `CloseCheckpoint` 指向同一逻辑。如果明确放弃，则先保存 `status: abandoned` 的 session，再由 `AbandonSession` 标为 `abandoned`；不要以删除文件代表结课或放弃。

## .state/review-transaction.json

- 保存最近一次批量复习事务的事件 ID、目标级别和状态，默认不纳入 Git。
- `pending` 表示需要 `Bootstrap` 继续完成；`completed` 表示事件和当前表均已对齐。
- 恢复时按 `event_id` 去重，因此重复执行不会重复追加复习历史。

## dashboard

能力证据、重复错误和下一里程碑可由教师基于 session 更新。`AUTO:METRICS` 区域由 `Rebuild` 生成，包含上海学习日期、14/28 天学习量、连续天数、当前轮次、下一项、恢复模式和到期项目；不得手工修改。它不计算计划完成率，也不把休息日标成失败。缺失数据写 `尚无证据`，不要猜测。

## 生成视图与周期摘要

- `learner/current-plan.md` 的 `AUTO:PLAN` 区域是 `plan-items.tsv` 的可读视图，不能作为事实来源手工改状态。
- `learner/summaries/YYYY-MM.md` 与 `YYYY-Qn.md` 是独立的日历统计，由原始 session、复习事件和结构化证据汇总；不控制学习队列。允许在“教师分析”中补充判断，但不要改自动统计数字。
- 课程结束使用一次 `FinalizeSession` 完成重建与验证。仅当学习数据在该动作之外发生变化时，才依次运行一次 `Rebuild` 和一次 `Validate`。验证会检查字段、状态、日期、引用和跨文件一致性。

