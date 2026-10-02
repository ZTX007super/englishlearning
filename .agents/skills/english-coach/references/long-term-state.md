# 长期能力、焦点与教学洞察

仅在轮次复盘、assessment、计划调整、查看进度或证据审计时读取。普通日课只冻结 observation 和固定类型 candidate signal；不运行长期 reducer，也不把当堂修正宣布为长期掌握。

## 权限边界

轮次复盘执行入口：独立 review 结束后，tracker 返回 `evaluate_cycle_review` 和 `prepared_step.evidence_packet`。调用 `EvaluateLongTermState -SessionId <receipt.session_id>`，tracker 自行读取正式证据；无需由 AI 填写 evidence payload。返回 `present_cycle_review_candidates` 后，依据 packet 的证据类别、goal_candidates 和覆盖限制展示复盘，再讨论下一轮建议。总结已展示后可以 `FinalizeSession`，其 `goal_decision` 原样使用该候选的 goal_id、decision、reason、evidence_ids。

当前普通复盘已接通 focus goal 实用判断：按 [goal-review.md](goal-review.md) 解释 `goal_candidates`、覆盖范围和下一步。`evidence_packet.scope=current_cycle_only` 仍表示课堂展示包只列本轮；目标候选由程序另读最近最多四个完成轮次的正式记录。旧契约字段不足、受辅助表现或缺少确认不能算 met。Competency/stage 候选仍未接通，不据目标完成宣布 stable 或阶段升级。复盘提交、下一目标与计划确认后，按 [cycle-publication.md](cycle-publication.md) 发布；轮次复盘本身无需创建可评分活动。

- tracker 的 `EvaluateLongTermState` 根据冻结事实和事件重放产生候选；AI解释候选、指出证据和提出计划，不能凭印象写 `met / stable`。
- 每轮形成一个目标决定；FinalizeSession 在写入前根据正式证据复核候选，重试不增加事件。用户确认下一焦点、计划和可逆教学选择；用户不负责批准或改写客观首答事实和已经满足的门槛。
- 有争议证据进入 `audit_pending`，暂停依赖它的计划变化；核对后追加 correction/void 并重放，不手改最终状态。
- 焦点、难度、review 和 competency 是不同层：任何一层的结果都不得自动级联到另一层。

## 四种长期结论

1. `focus_goal`：持续 2–4 个完成轮次的局部干预目标；轮次决定只能是 `met | continue | redesign | insufficient_evidence`。
2. `competency`：一个 `competency_family × CEFR level` gate；当前状态只能是 `not_evidenced | developing | stable`。
3. 分技能 stage：听、说、读、写分别达成；当前等级全部 Required gate 稳定且无阻塞 flag 才形成候选，不计算四技能平均 CEFR。
4. `learning insight`：仅描述“在什么条件下怎样教可能更有效”，不重复保存能力等级。

`focus_goal met` 不自动使 gate stable；gate stable 也不自动关闭不等价的 focus。Breadth/Extension 不阻塞 stage，也不能抵消 Required 缺口。

## A、B、C 证据

证据等级由 tracker 从冻结的 record kind、evidence mode、purpose、validity、primary/core result、support、model exposure、cost、版本、anchor、学习日和 context 等字段确定。

- **A direct evidence**：有效、可比、首次、独立、未经反馈或答案暴露的 primary；包括当前 anchor 的 target check、预排 capability probe、正式 assessment，以及 difficulty probe 在当前 anchor 上的 core result。必须符合冻结的正常允许条件。
- **B supporting evidence**：答前声明的 secondary、自然出现但非正式 primary 的迁移、去重的原子 review 趋势和用户自报。可支持教学判断或触发确认，不能单独使 goal met、gate stable 或 stage attained。
- **C teaching evidence**：training、guided、revised、retry、repair、示范后表现和支架前后对照。可支持教学方法判断，不能证明独立能力。

invalid、non-comparable、not-assessable、abandoned、重复提交和已 void 的记录不属于有效 A/B/C 结论。Difficulty challenge、promotion、hold、ceiling 不证明 CEFR；原子 review 只证明相应语言项目保持。

一条 observation 只保存一次。它可被 focus、gate、insight reducer 分别引用，但每个 reducer 内只能计一次；secondary 不成为第二条 A。A 类必须匹配当前 goal/catalog/indicator/anchor version，无法一对一迁移时保留历史并设 `migration_review_required`。

## Focus goal contract 与决定

每个 goal version 冻结：

- 关联 competency/indicator；
- 一个主要成功标准和最多两个不得退化的 guardrail；
- baseline、适用 activity/context；
- 最少 2、最多 4 个完成轮次；
- 一次预排 focus confirmation；
- 一至两个 `criterion_acquired | support_withdrawal | context_transfer` progress marker。

目标必须狭窄可观察，例如 `S_ARGUMENT + opinion_explanation + coherence`。构念、必要标准或关键情境变化时追加新版本并 `redesign`；不覆盖或事后放宽旧版本。

### `met`

同时满足：

- 已完成至少两个轮次；
- 至少三条去重 A 类成功，跨至少两个学习日和两个真正不同 context instance；
- 每个必要标准至少由两条 A 类覆盖；
- 至少一条来自预排 focus confirmation 且 `cost_signal=normal`；
- 最近决定性证据后无未解决的同 anchor A 类 not-met；
- guardrail 未退化。

只有轮次复盘提交 met。提前满足时，本轮余下焦点课用于迁移和巩固，不轮中换目标或重排队列。Met 后退步创建 maintenance/repair 目标或新版本，不改写历史达成。

### 进步与其他决定

明显进步只允许：

- `criterion_acquired`：必要标准从未达到变为后来跨日独立达到；
- `support_withdrawal`：减少或撤除预声明支架后仍保持；
- `context_transfer`：保持 core/guardrail 时首次在新 context class 独立成功。

单次做对、revised/guided 变好、difficulty promotion、主观印象或平均分变化不算 marker。同一 marker 每轮一次并引用 observation ID。

每轮至少两个与 focus 直接相关、预排且有效的 A 类 opportunity 才足以判断：

- 少于两个：`insufficient_evidence`；不算无进步 streak。
- 未 met 且出现新 marker：`continue`。
- 证据充分但无新 marker：首次 continue 并令 `no_effective_progress_streak=1`；下一轮只改变一个教学变量。
- 连续两个证据充分轮次无 marker，或第 4 个完成轮次仍未 met：`redesign`。
- 第 4 轮仍持续证据不足：重设 evidence/activity contract，不能无限延期。

## Competency、flag 与 stage

`competency-status` 只投影 `not_evidenced | developing | stable`。`watch`、`confirmation_due`、`maintenance_due`、`migration_review_required` 是独立 flag；每次变化引用 observation/event、indicator、anchor 和 catalog version。

一个 gate 的每个必要 indicator 至少需要两条跨学习日、跨 context 的 A 类成功，且至少一条 normal-cost。Gate 还需最近四个完成轮次内一次当前 anchor 的预排 capability probe 或正式 assessment。每个 probe 只证明其 primary indicator；B/C 数量、其他 indicator 或强项不能填补门槛。

### 反证

只有同 competency+indicator+anchor、有效、首次、独立、可比的 A 类 not-met 是直接反证：

1. Stable 后第一次反证：保持 stable，设 watch。
2. 最近三条可比 A 中两条跨日、跨 context not-met：仍保持 stable，设 confirmation_due，并在已有计划位安排确认。
3. 确认 not-assessable：状态与 flag 保留。
4. 确认 normal-cost 成功：清除冲突。
5. 确认仍 not-met：当前状态降为 developing。

Review 失败、secondary、training、guided、revised、retry、局部小错、high-cost 成功、更高等级失败和 stretch challenge 失败都不是直接反证。

### 新鲜度与历史达成

- Stable gate 连续四个完成轮次无新 A，或必要 indicator 连续八个完成轮次无 A，设 maintenance_due；自然停学不推进计数。
- maintenance_due 不降级、不制造 backlog、不插队，也不改变原子 review。
- 利用以后已有 rotation/flex 位安排确认；新 A 成功恢复 current，失败进入反证流程。
- 有 maintenance_due/confirmation_due 的 gate 不参与新的 stage attained 判断，但不撤销历史 attainment。

某技能当前等级全部 Required gate stable 且无阻塞 flag 时，tracker 产生 `stage_attained_candidate`。轮次复盘校验证据后追加不可变 `stage_attained` 客观事件，并另提 `next_stage_plan_ready`。用户可以拒绝新阶段计划，但不能删除客观历史。以后 gate 回退只更新当前状态并提出 repair，不降低其他 gate、R/B/E、难度 step 或严格队列。

## 缺口选择

先分类：

- `confirmed_ability_gap`：同一 indicator 至少两条跨日、跨 context A 类 not-met。
- `potential_gap`：只有一条直接失败，或主要来自 B/C；先安排 primary confirmation。
- `evidence_gap`：not_evidenced、maintenance_due、大量 invalid 或缺少可比任务；不能称作能力失败。

没有 confirmed gap 时使用 diagnostic focus 或继续补证，不按小样本最低分选择“最薄弱项”。

焦点候选使用字典序：

1. 当前阶段 Required gate 的已确认回退或正式确认失败；
2. 阻塞 Required 的先修缺口；
3. 其他 Required confirmed gap；
4. Required evidence/maintenance coverage；
5. 其他 Breadth；Extension 只有用户或长期目标授权才进入。

同层依次比较沟通影响与 core 严重度、阻塞下游数、跨任务/context 复发广度、证据质量和新鲜度、等待轮次、curriculum 顺序、稳定 ID。复盘展示首选、evidence IDs、理由和一个备选；用户确认后只改变下一轮计划，不改变正在执行的队列。

## 教学洞察

首版只允许四类狭窄、可证伪洞察：

- `bottleneck`：一个上游问题反复阻碍多个相关活动；
- `support_effect`：具体支架在明确条件下有效或无效；
- `transfer_pattern`：在哪些任务/context 可迁移、边界何处不稳；
- `cost_pattern`：能够成功，但某冻结条件持续带来 high cost。

Scope 使用既有 skill、competency、indicator、activity family、quality dimension、context class 和 support profile；禁止宽泛人格标签。

状态为 `candidate | active | watch | superseded | retired`。普通日课只能产生固定类型 candidate signal；轮次复盘/assessment 才改变状态。

- bottleneck/transfer/cost 至少两条跨日证据。
- support effect 至少两组可比的低/无支架与同一支架表现，并有一次支架减少或撤除。
- 一条可信反例使 active 进入 watch 并暂停自动使用；两条跨日可比反例或审计确认的用户纠正才 supersede。
- Candidate 两个完成轮次无新证据 retired；active 四个完成轮次无支持证据转 stale watch。自然时间不推进。
- 最多 12 条 active、每个 competency 最多两条；每轮最多处理三项状态变化。

Active insight 只能在批准计划和冻结 contract 内选择训练支架、反馈 adapter/优先级及同约束材料主题。每个 activity package 最多编译三条带来源版本的 directive。它不能自动改变 queue、review、focus、技能占比、CEFR、R/B/E、difficulty step/hold，也不能临时发起 probe/assessment。

## 有界输入与输出

一次 cycle review packet 最多：

- 18 个 evidence projection 引用，其中最多 12 个唯一 primary observation ID 和 6 个嵌入式 secondary projection；
- 当前 goal projection；
- 当前等级最多 15 个 competency family 摘要；
- 相关 active/watch insight；
- 原子 review 趋势引用；
- 总序列化大小 64 KB。

Bootstrap 只读取有界 projection。Projection 缺失或版本冲突时不在日课全库重算；queue guard 可确认则继续同队首安全 training 并报告维护状态，否则停止正式取证。

进度界面只显示当前 focus、四技能 Required gate 概况、confirmation/maintenance flag、历史 stage attainment、下一焦点候选及最多三个相关 active insight。证据充分度使用 `insufficient | supported | confirmed` 并显示样本数、跨日/context 和最近确认轮次；不显示平均 CEFR、伪精确置信度或未经校准的 TOEFL 分数。

C0003 及历史材料只作 legacy context 或 B 类规划线索；缺少新 contract、indicator、context、support 和 version 的记录不能回填成 A、met、stable、stage attained 或 active insight。
