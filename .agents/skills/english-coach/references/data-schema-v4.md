# 学习数据格式 v4

本规范只适用于已经通过 [migration-v4.schema.json](migration-v4.schema.json) 全部启用门、并以 committed activation receipt 切换到 `schema_version = 4` 的数据集。C0003 和所有既有 session 继续遵循 [data-schema-v3.md](data-schema-v3.md)。

能力 gate 只引用 [competency-catalog.json](competency-catalog.json)；任务条件和适应状态只引用 [difficulty-ladders.json](difficulty-ladders.json)。文档不得复制一份可独立修改的 gate、anchor 或 ladder。

## 全局格式

- TSV 使用 UTF-8、制表符分隔，列顺序固定。单元格不得含制表符、回车或换行；结构化值使用紧凑 JSON。
- 日期使用 `YYYY-MM-DD`；时间使用带偏移的 ISO 8601 字符串。学习日期和到期日按 `learner/settings.json.study_timezone` 计算。
- JSON 解析必须保留原始偏移；不能让运行环境把 `+08:00` 自动转换成本地时区后再验证。
- 永久 ID、event ID、observation ID、batch ID、transaction ID、receipt ID 和幂等键一经分配不得改变。
- 只追加 ledger 不删除、不覆盖；更正通过 `void / correction` 等新事件引用旧事件。
- 空字符串表示“不适用或尚无值”；`unknown` 表示旧数据无法可靠推断。两者不能被解释为 `false`、`none` 或失败。

## 四类数据

| 类别 | 内容 | 权威性 | 写入时点 |
| --- | --- | --- | --- |
| 正式事实 | session outcome、review event/audit、skill observation、goal/competency/stage/insight event | 唯一历史事实，可重放 | 只在课末统一事务或获准的轮次复盘/测评事务 |
| Pending 草稿 | 当前题面、首答判定、已展示反馈、待提交 review/observation/candidate | 当前未提交 session 的恢复事实 | 展示前 Prepare；反馈展示后一次轻量 checkpoint |
| 派生投影 | review current state、adaptation、competency status、long-term、dashboard、current plan、bootstrap index | 可从正式事实重建，不得反向改写事实 | 事务内部增量更新或显式 Rebuild |
| 可丢缓存 | cycle skeleton、ready package、fallback、外部来源 metadata | 只加速，不决定队列、评分或状态 | 轮次边界或正式提交后 |

`learner/plan-items.tsv` 仍是严格队列与完成状态的权威。缓存、dashboard、current-plan 和任何模型总结都不能创建、跳过、重排或完成计划项。

## learner/settings.json

v4 保留 v3 字段，并增加：

- `schema_version: 4`
- `runtime_protocol_version: 4`
- `activation_id`：引用 committed v4 activation receipt。
- `catalog_version`、`ladder_version`、`contract_version`、`review_schema_version`
- `activated_at`

这些字段在迁移的最后一步一次写入。缺少有效 activation receipt 时，即使新表存在也不能启用 v4。

## 队列与 session

### learner/plan-items.tsv

列顺序固定：

`plan_item_id, plan_id, sequence, title, session_type, primary_skill, required, status, completed_session_id, focus_goal_id, plan_role`

- 前九列沿用 v3 语义。
- `plan_role` 只接受 `focus / maintenance / cycle_review`。v4 的六个训练项使用 focus 或 maintenance，随后一项使用 cycle_review。
- maintenance 的 `focus_goal_id` 可以为空；focus 必须引用当时有效的目标版本。
- v3 与 C0003 行的新增列保持空或 `unknown`；不得反推历史焦点或角色。
- plan role、焦点和六课比例只在轮次复盘或学习者明确调整计划时改变。到期 review 不占计划角色。

### learner/plan-events.tsv

保持 v3 列顺序：

`event_id, occurred_at, study_date, plan_item_id, event, reason`

计划取消、经批准的未开始项修改和队列修复都只追加事件。状态改变必须有非空原因和稳定幂等键；若旧表暂不容纳幂等键，键保存在对应事务 receipt 中。

### sessions

v4 新 session 的 frontmatter 在 v3 字段之外增加：

- `protocol_version: 4`
- `start_receipt_id`
- `finalization_receipt_id`
- `finalization_transaction_id`
- `package_id` 与 `package_hash`

正文只保存必要摘要、来源、最多三个实际处理的反馈主题和下一步，不保存完整对话、完整首答、音频或完整受版权保护材料。

`completed / abandoned` 只有在对应 finalization WAL 为 `committed` 且 receipt 匹配时生效。旧 completed session 没有 v4 receipt，统一视为 `legacy_closed`，绝不重放或补造 receipt。

## 原子复习

### learner/vocabulary.tsv 与 learner/error-log.tsv

两表保留原始列和全部历史，继续说明“学过什么、错误从哪里来”。v4 激活后，旧 `level / next_review / last_review` 只作 legacy 审计，不再是正式排程来源。不得为迁移重写旧行或删除 paused 项。

### learner/review-items.tsv

列顺序固定：

`review_item_id, concept_id, target_version, target_form, target_meaning, review_family, target_scope, allowed_variants_json, known_confusions_json, context_seeds_json, recipe_stage, strength_level, status, next_review, recheck_due, maintenance_interval_days, legacy_level, legacy_due, last_review, maintenance_ready, created_at, updated_at`

- `review_family`：`receptive_meaning / productive_expression / productive_pattern`。
- `target_scope`：`exact_expression / pattern / meaning_or_function`。
- `recipe_stage`：`relearn / recall / constrained_transfer`；`strength_level` 为 0–5。
- 正式状态：`active / maintenance / legacy_unverified / needs_recipe_fix / needs_reteach / paused / retired`。
- `next_review` 是普通到期；`recheck_due` 是主线明确误用触发的可空提前复查日。
- `maintenance_interval_days` 只在 maintenance 使用 60、120 或 180。
- `legacy_level / legacy_due` 只控制 legacy 车道排序与审计，不能证明新 strength、recall、transfer 或 maintenance。
- 身份、目标和允许变体是项目契约；可变状态必须能从有效 review event 重放。一个“形式＋词义＋目标版本”同时最多有一个非终止项目。

### learner/review-item-sources.tsv

列顺序固定：

`source_link_id, review_item_id, source_type, source_id, relation, source_session_id, linked_at`

`source_type` 只接受 `vocabulary / error / session`。同一 review item 可有多个来源。合并不得丢失来源；模糊匹配不得自动合并。

### learner/review-candidates.tsv

列顺序固定：

`candidate_id, concept_key, item_kind, target_form, target_meaning, status, first_seen_at, last_seen_at, source_session_id, source_ids_json, recurrence_count, priority_factors_json, requested_by_user, activated_review_item_id, idempotency_key`

- `status` 只接受 `candidate / observed_only / activated / rejected`。
- candidate 没有正式 due、strength 或 recipe stage，不能进入到期队列。
- 每课最多保存 6 个 encountered/candidate；每六个训练项最多激活 2 个正式项目。

### learner/review-history.tsv

保留 v3 的十一列，避免改写旧事件：

`event_id, reviewed_at, study_date, session_id, item_type, item_id, result, old_level, new_level, previous_due, next_review`

- 历史 `item_type` 为 vocabulary 或 error；v4 新事件使用 `review_item`，`item_id` 引用 review item。
- v4 的 old/new level 表示 strength。recipe stage、双重判定、题面和审计信息在 review-audit 中。
- `result` 只保存 `again / hard / good / easy` 的有效评级；invalid、void 和 control 事实只在 audit 中出现，不能改变排程。

### learner/review-audit.tsv

列顺序固定：

`audit_id, event_id, batch_id, question_instance_id, review_item_id, record_kind, ref_event_id, event_seq, recorded_at, answered_at, study_date, session_id, source_session_outcome, idempotency_key, recipe_stage, lane, weight, prompt_text, task_contract_json, answer_excerpt, language_validity, target_demonstrated, rating, rating_reason, invalid_reason, repair_result_json, exposed, model_exposed`

- `record_kind`：`rating / invalid / void / correction / control`。
- 每个实际展示的 question instance 至少一条最小充分审计；未展示的题壳不生成永久记录。
- `prompt_text` 只保存短题面；`answer_excerpt` 只保存足以判分且已脱敏的最短片段。
- `language_validity` 与 `target_demonstrated` 分开；只有 rating 行可关联 review-history event。
- correction/void 引用 `ref_event_id`，按 event_seq 重放，不覆盖原记录。
- `source_session_outcome=abandoned` 的已完成原子事实仍可审计；只有有效 rating 才能改变排程。

## 活动 observation

### learner/skill-evidence.tsv

列顺序固定，原九列保留在前：

`evidence_id, session_id, skill, phase, metric, score, scale, evidence, next_focus, record_kind, event_seq, recorded_at, observation_id, ref_observation_id, idempotency_key, plan_item_id, activity_id, criterion_id, loop_id, attempt_no, lead_or_auxiliary, purpose, evidence_mode, evidence_kind, catalog_version, ladder_version, contract_version, competency_id, competency_family, activity_family, indicator_id, anchor_id, role, review_item_id, focus_goal_id, template_id, adaptation_key, load_axis_id, planned_step, target_step, presented_step, changed_dimension, task_fingerprint, day_id, comparability_group, content_id, context_id, primary_result, criterion_result, criterion_results_json, secondary_projection_json, task_result, core_result, challenge_result, validity, invalid_reason, cost_signal, planned_support_json, allowed_support_json, actual_support_json, support_level, support_kind, model_exposed, access_profile_json, source_session_outcome`

旧行只保留原九列含义；所有新语义字段为空或 `unknown`，不得回填。

新行规则：

- `record_kind` 至少为 `observation / void / correction`；evidence_id 是行事件 ID，observation_id 是一次首次回答的稳定身份。
- 一次 observation 只有一行 primary 事实；secondary 放在 `secondary_projection_json`，不另造第二条 observation。
- `lead_or_auxiliary`：`lead / auxiliary`；每课只能一个 lead，最多一个 auxiliary。
- `purpose`：`practice / probe / transfer / assessment`。
- `evidence_mode`：`training / target_check / difficulty_probe / capability_probe`。
- `evidence_kind` 用于长期分级，如 `direct / supporting / teaching / spontaneous_transfer`；最终 A/B/C eligibility 由冻结字段确定，不能由该标签单独决定。
- `primary_result`：`met / not_met / not_assessable`。
- `task_result`：`success / partial / failed / not_assessable`。
- `core_result`：`met / not_met / not_assessable`。
- `challenge_result`：空或 `stretch_met / stretch_not_ready / stretch_overload / not_assessable`。
- `validity`：`valid / invalid / non_comparable`；`cost_signal`：`normal / high / unknown`。
- `criterion_id / criterion_result` 只用于单标准兼容记录；多标准 observation 的唯一完整结果在 `criterion_results_json`。
- `evidence` 仍是唯一的最短证据摘要；不新增同义摘要列。
- planned/allowed/actual support 使用 JSON 保存强度、类型和作用范围；`support_level / support_kind` 是 actual support 的便捷投影。model_exposed 保存按 criterion/loop 限定的 JSON，而非把整个活动一律污染。
- `source_session_outcome` 只接受 `completed / abandoned`，并在统一课末事务中随 observation 冻结。abandoned session 只有“已收到首答、判定已冻结且反馈已展示”的原子 observation 可以提交；其来源状态必须保留，长期 reducer 不得将其计为 A 类晋级证据。
- score 非空时 scale 必须为正数且 metric 明确；项目内部量表不得冒充官方成绩。

## 焦点、能力与洞察

### learner/focus-goals.tsv

列顺序固定：

`goal_id, goal_key, version, supersedes_goal_id, stage_id, skill, competency_id, competency_family, activity_family, quality_focus, goal_text, success_criteria_json, min_completed_cycles, max_completed_cycles, start_cycle_id, status, end_cycle_id, created_at, updated_at`

- 一个 goal version 是不可变契约；实质改变必须新建版本并 supersede。
- `min_completed_cycles / max_completed_cycles` 默认 2/4，只计算完成轮次。
- status：`proposed / active / met / redesigned / superseded / retired`。一次只能有一个 active 主焦点；确认更换时已达标旧目标保留 met，否则为 superseded。
- 实用复盘的结构化 `success_criteria_json` 与旧文字数组并存，字段定义见 [goal-review.md](goal-review.md#结构化目标契约)；不重写历史数组，不新增 TSV 列。

### learner/goal-events.tsv

列顺序固定：

`event_id, event_seq, occurred_at, study_date, cycle_id, goal_id, decision, reason, evidence_ids_json, replacement_goal_id, catalog_version, goal_contract_version, idempotency_key`

decision 只接受 `met / continue / redesign / insufficient_evidence`。每个完成轮次对 active goal 恰有一个决定；同一 progress marker 在同一轮次只计一次。

### learner/competency-events.tsv

列顺序固定：

`event_id, event_seq, occurred_at, study_date, cycle_id, session_id, competency_id, indicator_id, anchor_id, event_type, from_status, to_status, evidence_ids_json, reason, catalog_version, idempotency_key`

event_type 至少支持 `developing / stable / watch / confirmation_due / maintenance_due / downgrade / restore / correction / void`。状态变化必须引用决定性 observation/event；没有 ID 的教师印象不能进入 ledger。

### learner/stage-events.tsv

列顺序固定：

`event_id, event_seq, occurred_at, study_date, cycle_id, skill, stage_id, event_type, prerequisite_gate_ids_json, evidence_ids_json, catalog_version, idempotency_key`

`stage_attained` 是不可删除事实；四个 skill 分开记录。用户是否采用下一阶段计划不改写已满足的客观门槛。

### learner/learning-insights.tsv

列顺序固定：

`insight_id, insight_key, version, insight_type, scope_type, scope_id, claim, evidence_ids_json, counterevidence_ids_json, teaching_implication, status, freshness, created_cycle_id, last_confirmed_cycle_id, supersedes_insight_id, created_at, updated_at, idempotency_key`

- status：`candidate / active / watch / superseded / retired`。
- 同一 insight_key 同时最多一个 active version；claim、scope 或教学含义实质变化时追加版本。
- 普通日课只能产生固定类型 candidate signal，不能激活、覆盖或退役 insight。
- 旧教师备注只作 `legacy_context` 或 candidate hypothesis，不自动生成 active insight。

### learner/competency-status.tsv

列顺序固定：

`competency_id, family_id, stage_id, skill, level, role, status, decisive_event_ids_json, evidence_ids_json, flags_json, catalog_version, projection_revision, updated_at`

这是由 observation 与 competency events 重建的当前投影，不是第二份事实 ledger。status 只接受 `not_evidenced / developing / stable`。缺证写 not_evidenced，不写失败。

## 课中 checkpoint

### 逐题课堂扩展（classroom_version=1）

仅通过 `Bootstrap -EnterSession` 新建的 session 启用；旧 checkpoint 保持原流程，缺失或 0 表示兼容模式。新字段为 `classroom_review`：batch_id、完整冻结 questions、cursor、repair_count、最近 feedback_text 与 followup_prompt。题目 disposition 区分 pending、answered、skip、exposed。

PrepareReviewQuestions 在展示前持久化选定切片；SaveReviewAnswer 在反馈后保存当前题结果或修复，并返回下一动作。首次回答只追加到同一个 pending_review_batches 条目；修复更新其 repair_result，保持首答评级与日期。所有写入与题位置一起原子替换，沿用同 key 同 payload 重试。

最后一题保存与主课 PrepareActivity 是同一外部调用内的两个可恢复阶段。前者成功后即使后者失败，复习结果仍在 checkpoint；Bootstrap -EnterSession 恢复准备，不重放复习。cache `.state/classroom-templates/` 仅为派生模板，绑定 package/ladder hash 和 compiler_version，丢失时可由已验证 core 确定性补齐；不保存未来回答。

未作答但目标被反馈暴露的题，课末只追加 `review-audit` 的 control 记录：`rating_reason=deferred_after_answer_exposure`，不生成评分、答题片段或 history。bootstrap index 的 `review_exposures={study_date,item_ids}` 保留当日有界延期集合，新课堂从原选定切片排除这些项目，不另抽题、不改 due；跨学习日不沿用该集合。新接口的 demonstrated/not_demonstrated 在存档时转为既有 reducer 使用的 yes/no。

### .state/current-session.json v4

它是当前未提交 session 的唯一 pending 权威，至少保存：

- `schema_version`、`protocol_version`、单调 `revision`、status。
- session/plan/study date/timezone、start receipt、queue guard、package ID/hash 和版本指纹。
- `required_stages`、当前 stage、最后已完成的可见反馈，以及 `waiting_action: present_review | prepare_activity | await_answer | clarify | repair | transfer | show_summary | finalize_session`。
- prepared activity：冻结任务契约、短题面、题面哈希、criteria、indicator/anchor、evidence mode、target/planned/presented step、support 边界。
- `first_answer_received`、最短必要首答片段、冻结判定、最多三个 issues、`feedback_shown`、repair/transfer/exposure 状态。
- pending review batches、pending observation/candidate/vocabulary/error/correction/void payload。
- 预分配的 event/batch/observation/finalization ID、幂等键、payload hash。
- 剩余主题/复杂度预算、性能指标和 `pending_persistence` phase。

边界：

- 不保存完整对话、完整文章/字幕、音频、全部小错或未展示的完整题库。
- prepared 但未首答可原样重显；已有首答且反馈已展示时不得重问、重判或新增标准。
- feedback 展示前不读写；展示后、下一道需作答任务前，只允许一个逻辑 SaveActivityCheckpoint。
- checkpoint 原子替换并保留上一份校验通过的 generation。响应丢失以同一 key 重试，同一 key 不同 payload 必须拒绝。
- pending review 与 observation 课中不写正式 ledger，也不改 due、strength、adaptation、goal、competency 或 plan。

## WAL 与正式提交

### .state/start-transaction.json

保存 start intent、幂等键、plan/queue guard、预分配 session ID/path、package hash、当前 phase 和 receipt。StartSession 只能创建一个 session；中断后 Bootstrap 继续同一 intent。

终态必须同时满足 `phase=committed`、receipt 的 `operation=StartSession`，且 receipt 的幂等键、session ID 与 plan item ID 和 intent 相同。新提交同时写 `status=committed`；`status` 不是第二套终态判据。已满足终态的历史 intent 即使 `status` 误留为 `pending` 也不是待恢复事务。Committed intent 保留用于同 key 重放，并可被下一队首的新 intent 原子替换，不执行删除式“清理”。

### .state/session-transaction.json

FinalizeSession 与 AbandonSession 共用唯一正式 WAL。至少保存：

- transaction/finalization/idempotency ID、session ID、checkpoint revision、queue guard、payload hash。
- expected projection revisions、待追加正式事实、disposition `completed / abandoned`。
- 当前 phase、已完成 phase receipts、错误、`rebuild_required`、`preload_pending`。

phase 顺序固定：

1. `intent_persisted`
2. `draft_guard_validated`
3. `immutable_facts_appended`
4. `touched_projections_updated`
5. `session_terminal_receipt_written`
6. `plan_queue_updated`
7. `bootstrap_index_updated`
8. `committed`

相同 key＋相同 payload 返回同一 receipt；相同 key＋不同 payload 拒绝。新事务开始前必须恢复或拒绝旧 pending，绝不能覆盖。

FinalizeSession 从 checkpoint payload 生成 session terminal 内容，不要求 AI 先手改 session、evidence 或 plan。AbandonSession 只在用户明确放弃时运行，只提交“已收到首答、判定已冻结且反馈已展示”的原子事实；plan item 回到 planned，队列不推进。

Dashboard、current-plan 全量视图和 next-cache 发布位于 committed 之后；失败只设置 `rebuild_required / preload_pending`，不回滚已提交课程。

### .state/long-term-transaction.json

只在 cycle review 或 assessment 收尾使用，保存 goal/competency/stage/insight 的稳定 event ID、幂等键、输入 evidence packet hash 和 reducer phase。普通日课不得运行该 reducer。

不存在独立 `.state/activity-transaction.json`；活动正式提交只能是 session WAL 内部的幂等 phase。

## 派生投影

- `learner/adaptation-state.json`：每个 adaptation key 的 target step、固定大小 target/probe 窗口、progress state、hold phase、unstable 与 flags。
- `learner/long-term-projection.json`：goal、gate、stage、insight 的有界当前视图；每 key 至多最近 6 条相关 primary 摘要。
- `.state/current-cycle-evidence.json`：本轮最多 6 课×3 projection 引用，不复制证据文本；最多 12 个唯一 primary observation。
- `.state/bootstrap-index.json` 与 `.state/bootstrap-index.previous.json`：queue head、ready package/hash、至多 10 个 review 候选、完整 due counts、必要 projection revision 与版本指纹。
- dashboard/current-plan/summaries：人类可读派生视图。

投影缺失、损坏或版本不匹配时不在日课启动路径全库重放。queue guard 可由上一代确认时使用同队首安全 fallback training 并标记维护；guard 无法确认时停止正式取证，不能猜队首。

## activity package 与缓存

推荐路径：

- `.state/cycle-skeletons/<plan_id>.json`
- `.state/activity-packages/<plan_id>/<plan_item_id>/<generation>.json`
- `.state/activity-packages/published-index.json`

生命周期：`skeleton → provisional → ready → prepared → consumed`；异常状态：`stale / rebuild_required / rejected`。

ready package 可含材料、任务、冻结前契约、评分要点、提示阶梯、迁移题壳、唯一预授权 probe 变体和本地 fallback。运行时只绑定实际日期、到期 review、最终 evidence mode/step、真实 support 与首答结果。

缓存 fingerprint 至少包含 plan/plan item/role/focus/queue revision、package/policy/catalog/ladder/contract version、projection/review revision、content/context、来源/权利和 checksum。自然时间本身不使安全兼容缓存失效。

缓存永远不创建或改变队列、review、focus、R/B/E、gate、ladder 或评分事实。不可安全呈现时只允许一次有硬截止的替代查找；新材料一律 training，超时使用同队首本地 fallback。

## C0004 非追溯迁移

### 永不改写

- C0003 的 completed、in_progress、planned plan item 及其顺序。
- 所有既有 session、review-history event、vocabulary/error 行和教师备注。
- v3 completed checkpoint 与 completed review transaction。
- 历史 evidence 的 activity、support、exposure、focus、fingerprint、A/B/C 或 observation 关系。
- 历史 CEFR 估计不能变成 gate stable、stage_attained 或 active insight。

### 允许的保守迁移

- plan-items 与 skill-evidence 只增加 v4 列；旧列逐字段保持相等，新列为空或 unknown。
- 旧 vocabulary/error 可生成 `legacy_unverified` 或 `needs_recipe_fix` 项及 source links。只有完全相同的概念和词义自动合并；模糊、复合或非原子项不猜测。
- 旧 level/due 写入 legacy_level/legacy_due，仅用于 legacy 排序与审计。首次正式 recall 定位前不产生新 strength、transfer 或 maintenance。
- 初始 gate 为 not_evidenced；旧总结只作 legacy_context。
- adaptation 初始 target 使用明确一对一映射；无法映射时使用 binding 默认并设置 migration_review_required，不推断成败。

### dry-run

迁移器先输出只读 manifest：

- migration/activation ID、计划的 runtime/catalog/ladder/contract/review 版本。
- 每个事实文件的相对路径、字节数、SHA-256、header、row count。
- session、plan、vocabulary、error、review、evidence 计数和 ID/引用检查。
- 当前 queue head、current-session 状态、旧 review transaction 状态。
- legacy review 的 exact merge、needs_recipe_fix、paused/retired 和人工处理清单。
- 所有将创建、扩列、保持不变和拒绝处理的文件。

dry-run 不创建 learner、session、state、projection 或 cache 文件。

### 快照与演练

正式迁移前保存 learner、sessions 和 .state 的原始字节快照及 manifest。快照必须位于 sessions 递归扫描范围之外。重新读取快照，逐文件校验 SHA-256。

先在隔离副本执行完整迁移与 Validate。验收要求：

- immutable 文件 hash 不变；扩列表的旧列逐字段相等。
- 旧行、event、session、ID 和引用计数不减少、不重复。
- C0003 队列与状态不变。
- 新事件 ledger 可重放出相同投影。
- 同一迁移 key 重试返回同一 receipt；逐 phase 中断均可恢复。
- 不存在 in_progress session 或 pending 旧 review transaction。

## v4 启用门

只有同时满足以下条件才能提交 activation：

1. C0003 六个训练项和轮次复盘均按 v3 完成。
2. 学习者确认 C0004 的焦点目标和六课计划。
3. 数据快照、dry-run、隔离迁移、引用校验、故障恢复和幂等测试全部通过。
4. catalog 恰有 15 个 family、45 个 gate，每 gate 2–3 indicator；ladder/binding 引用全部有效。
5. v4 事实表、投影和双代 bootstrap index 可从正式事件重建。
6. C0004 六课 skeleton 与每个本地 fallback 已通过内容、权利、完整性和 checksum 检查；听力 fallback 含可播放音频和 transcript。
7. Start/Finalize/Abandon 的 WAL 与响应丢失测试通过；同一 plan item 不会产生第二个 session。
8. Bootstrap 本地路径、首题、checkpoint、课末 reducer 和90秒硬预算通过端到端测试。
9. 没有 pending migration/start/finalization/long-term transaction。
10. activation payload 完全符合 migration schema，且预期 queue head 是 C0004 第一项。

迁移先写 recoverable intent，再创建/校验新事实和投影，最后原子提交 activation receipt 与 settings version。启用失败时保持 v3；不能仅因看见新文件而部分进入 v4。

## Validate 最低不变量

- 所有 TSV header 精确匹配版本；ID 唯一，引用存在，时间保留学习时区偏移。
- 严格队列只有一个 head；completed plan 与 committed session receipt 双向一致。
- ledger 只追加；correction/void 引用存在且 event_seq 可确定重放。
- 一次首答只有一个 observation；secondary 不产生伪 observation。
- review event 与 audit、review item、session 和当前排程一致；invalid 不改变排程。
- 同一 reducer 内 observation 不重复计数；缺证不写失败。
- R/B/E 与 catalog 一致；四技能分别计算，B/E 不抵消 R。
- difficulty 只相邻改变一个维度；hold 不能通过同 load axis 的近义维度绕过。
- checkpoint/WAL phase、payload hash、幂等 key 和 receipt 一致。
- cache/index/projection 可删除后重建，且删除它们不会删除正式事实或改变队列。
