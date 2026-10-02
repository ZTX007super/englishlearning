# 从 ready blueprint 到 prepared activity

只有 `next_action = prepare_activity` 时读取。本文件规定如何把 tracker 返回的有界蓝图编译成完整任务；它不定义评分和纠错规则。

逐题课堂正常由程序补齐预备 core 并复用 PrepareActivity 校验，直接返回 `present_activity`。只有返回人工准备分支才执行本文步骤；`classroom_version=1` 时下述准备输入位于 `prepared_step.preparation`，session/owner/revision 仍取外层最新回执。其他形状保持原位。

轮次复盘例外：`plan_role=cycle_review` 的蓝图是复盘议程，不是可评分的英语 activity。使用 `evaluate_cycle_review → EvaluateLongTermState -SessionId` 和 [long-term-state.md](long-term-state.md)；不解析难度 binding，不创建 `cycle_review` 的 PrepareActivity 契约，也不产生新能力 observation。

## 三种状态

- cycle skeleton：轮次复盘确认的技能、能力与课型意图，不能直接展示。
- ready blueprint：tracker 已校验队首、版本、权利与 checksum 的可丢缓存；`package_blueprint.activity_skeletons` 是允许使用的活动边界，但可以尚未绑定完整题面。
- prepared activity：`PrepareActivity` 已绑定当前 session/activity ID、queue guard、难度、证据模式和完整任务契约；只有这个状态可以展示和评分。

`ready` 不是 `prepared` 的同义词。路径或 skeleton 本身都不是题面，也不能在学习者回答后再补齐标准。

## 确定性构造顺序

1. 只选 `prepared_step.package_blueprint.activity_skeletons` 中尚未使用的一项；不得换能力、family、indicator、anchor 或 template。`core_status=ready` 时，题面、材料、criteria 与 semantic scope 必须原样取自 `package_blueprint.core`，不得重新创作；带外部材料的课若 core 缺失或校验失败则停止正式取证。若有复习，先处理 `prepared_step.review_items`，不要把复习改造成当前焦点训练。
2. 用 skeleton 的 `competency_family + activity_family + template_id` 在 [difficulty-ladders.json](difficulty-ladders.json) 中解析唯一 binding。零个或多个匹配都停止正式取证；不凭印象选择。
3. 难度使用 tracker 已冻结的 probe/target（若有）；否则使用该 binding 的默认 target，`changed_dimension=none`，并受 `evidence_mode_cap` 限制。只允许一个 lead 和至多一个 auxiliary。
   core 明确给出 `evidence_mode`、purpose、access_profile 与 planned_support 时，正式主包原样沿用这些预排条件；同队首 fallback/旧包仍以 training 为上限。独立检查必须先收无提示首答，再反馈；不足跨日条件时如实记录日期，不补造第二个学习日。
4. 按 [task-contracts.md](task-contracts.md) 对应 activity family 补齐 core 尚未冻结的 normal access、adapter、hint/support、loop/retry/transfer/complexity budget；core 已提供的题面、1–3 个 criteria、semantic scope/answer key 和材料不可改写。不得引入蓝图没有提供的外部材料。
5. 绑定响应给出的 `session_id`、`package_hash`、`queue_guard` 和版本，生成稳定 activity/contract/content/context ID；随后调用 `PrepareActivity`。
6. 只有 tracker 返回 `status=prepared`、`next_action=present_activity` 且完整 contract 原样回显，才展示其公开字段。失败时不展示半成品，不自行降低评分标准。

## Review 与 integrated 边界

- `review_first=true` 时先按 [review-protocol.md](review-protocol.md) 出低歧义题；未作答的 review 保留原 due，不伪造完成，也不因主线焦点改变。
- `integrated` 是 session 编排类型。`primary_skill=listening|reading` 对应 `input`；`speaking|writing` 对应 `output`；`integrated|mixed` 对应 `input + output`。
- `integrated_response` 是任务 family，只有 skeleton 明确指定且确实有两个以上来源时才使用，不能由 session 类型推断。
