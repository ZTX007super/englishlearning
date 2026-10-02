# C0004+ 运行协议

新课程通过 `Bootstrap -EnterSession` 建立 `classroom_version=1`，执行 [classroom-flow.md](classroom-flow.md) 的组合开课与逐题存档。以下独立 StartSession、StageReviewBatch 与手动准备的流水线用于旧进行中 session 和显式返回的兼容分支；恢复不转换版本。事务、证据与正式提交边界继续适用。

只有 `Bootstrap.runtime_version = v4` 且本次 session 未以其他版本开始时读取。复杂状态机由 tracker 执行；AI只呈现 `prepared_step`、处理学习者回答并执行 `next_action`。

## 固定小返回

除版本、协议引用和必要 guard 外，日课只消费：

- `status`：当前可见状态；
- `next_action`：唯一允许的下一动作；
- `receipt`：已完成动作的稳定回执；
- `reason_code`：固定机器原因；转成简短人话，但不改变语义；
- `prepared_step`：与当前 `next_action` 对应的有界输入。`prepare_activity` 时它是 session guard、review slice 与 ready blueprint，不能展示为题；只有 `present_activity` 时才是可展示的完整冻结 capsule。“完整”明确指 [task-contracts.md](task-contracts.md)“展示前冻结”列出的全部字段，而不是下面示例字段的别名或子集。它至少包含 session/activity/contract ID、`activity_family`、`modality`、`purpose`、`mode`、`primary_construct`、全部 criteria 与语义范围/key、normal access、`correction_timing`、当前 adapter、hint/max support、loop/retry/transfer budget、competency/indicator、evidence mode、difficulty/content/context、版本/hash 和 queue guard。只向学习者展示其中公开部分。
- `next_action_contract`：声明下一步是 tracker 动作还是交互动作，并指向 [tracker-actions.md](tracker-actions.md) 的参数来源；参数不能从自然语言猜测。

需要根据材料判定的课步还必须在 capsule 中带有首答后仍可直接使用的有界材料正文、音频判定产物或自包含评分片段及其 hash；单独的路径、URL 或标题不够。音频本身不可放入有界文本 envelope，但在展示前完成的可靠分析产物可以；没有实际声音分析时仍按 `not_assessable` 边界处理。

不得读取 WAL 决定 phase，不自行计算 fingerprint、枚举 probe、选择缓存失效层、判断 lease 接管、重算 due 或拼装恢复路线。可评分 `prepared_step` 缺少任一必需 capsule 字段时不得展示或事后补判，按已有 `next_action` 处理；没有安全动作时停止正式取证。queue guard 仍可确认时，只有 tracker 明确返回的同队首 training 才可继续。

## Bootstrap 恢复顺序

1. 若已由显式 `ActivateV4` 创建合法迁移 intent，先从最后成功 phase 恢复同一迁移；Bootstrap 无权自行创建迁移。
2. 恢复未完成的 start intent，确保不会创建两个 session。
3. 恢复 `pending_finalize / pending_abandon` 等正式事务。
4. 返回仍为 `in_progress` 的 session，并定位到最后一次已保存反馈之后的等待动作。
5. 上述均不存在时，才打开有界 index 中的当前严格队首。

断线、退出、上下文压缩、跨日或长时间未继续不代表放弃。Pending review 使用原冻结顺序、题面、题量、提示和 `answered_at/study_date`；公开 due 尚未变化也不能再次抽取。

当前 index 损坏而上一代 queue guard 一致时，可使用上一代同队首安全包或 fallback 并标 `rebuild_required`。两代都无法确认 queue head 时停止正式取证，不猜测、不跳队列、不创建第二个 session。

## Start 与课包

`StartSession` 必须由 `next_action` 触发，并以稳定 idempotency key 幂等地绑定当前队首课包、分配 session ID、写 stub/checkpoint 与 start receipt。它不全量 Rebuild、Validate、扫描历史或同步编译下一课。

已提交的 start intent 会保留作幂等回执，不需要删除，也不得阻塞后续不同队首。终态由 `phase=committed` 与匹配的 `StartSession` receipt 共同确定；`status` 只是同步标记，历史记录即使误留为 `pending` 也按该终态规则处理。

课包是可丢缓存，不是计划、复习、能力或证据事实。生命周期为：

`skeleton → provisional → ready → prepared → consumed`

失败状态使用 `stale | rebuild_required | rejected`。只有依赖事实和必要 projection 已提交，provisional 才能通过原子指针发布为 ready。包不预分配未来 session ID，不推进 plan，不反向改变 queue。

轮次复盘为已确认的下一轮编译六个 skeleton；每次 session 正式完成后，只滚动完善真实下一队首。第六次训练后只能准备 cycle-review 输入包，不能越过用户复盘确认下一轮。

Ready package 是已经通过队首、版本、权利与 checksum 检查的 **activity blueprint**，不是已经冻结的 activity。它可以预生成：

- 材料及来源/权利元数据；
- task/prompt、冻结契约骨架、评分 key 或语义范围；
- 不泄题的 hint、有限 variant、迁移题壳；
- 同队首的本地 fallback；
- 相关的有限 focus/gate/directive 摘要。

运行时只绑定：

- 实际 study day、session/activity ID、queue guard；
- 真正到期的 review 切片和 recovery mode；
- 从已编译变体中确定的最终 evidence mode、难度 step/band；
- actual support、首答、task/criterion result、issues、反馈、repair、transfer 与长期候选。

运行时按 [activity-preparation.md](activity-preparation.md) 确定性补齐未绑定字段，再由 `PrepareActivity` 校验并冻结一个实例；不能把 skeleton 直接展示、重新自由设计整课，或预生成未来学习者的回答与纠正。

## Cache guard 与失效

Manifest 绑定 plan/plan item/role/skill/focus、queue revision、package/policy/catalog/ladder/contract 版本、必要 projection/review revision、content/context、source/rights 和 checksum。Bootstrap 只比较有界当前/上一代 index，并返回固定 reason code。

失效矩阵：

- 精确匹配：直接使用。
- 仅日期或 review revision：保留主线，只重绑 review。
- 同队首且短期 projection/probe/insight 漂移仍兼容：选择包内保守 variant；证据可比性不足时降为同构念 training。
- 材料或考试 adapter 局部失效：只替换/降级该层。
- queue head、用户确认计划、focus、policy、catalog、ladder、contract、assessment 类型、checksum 或权利边界不符：硬拒绝。
- 正在恢复的 session 永远使用其已经冻结的当前包；不能串到 next-cache。

永远优先最近的、可安全呈现且兼容的旧代。自然时间本身不使语言材料失效，也不为了“更新颖”而联网刷新。内容已暴露或无法保持证据独立但仍可教学时，只能作为 training。

可呈现门、官方规则和一次外部替代遵守 [resource-policy.md](resource-policy.md)。Training 不能豁免 misinformation 或版权；权利失败禁止展示。

## 独立 review 切片

Skeleton/ready 只缓存有限候选、recipe、低歧义题壳和必要材料。实际学习日由 [review-protocol.md](review-protocol.md) 选择到期项目。日期/review revision 变化只重绑 review，不废弃兼容主线；未展示题壳不创建永久 question instance。

每个完成题批只在 checkpoint 冻结稳定 pending `ReviewBatch`；专门复习 session 也遵守同一课末事务，只是没有普通 input/output 主线。

## 普通日课流水线

1. `Bootstrap` 恢复状态或验证当前队首 ready package。
2. `StartSession` 幂等绑定包并冻结 review 切片；若有到期 review，返回 `present_review`，否则返回 `prepare_activity`。第一个 activity 只有在 `PrepareActivity` 成功后才冻结。
3. 到期 review 优先但保持独立；之后按 session contract 进行主阶段、focused feedback 和 summary。`integrated` 的主阶段由 `primary_skill` 决定：听/读为 input，说/写为 output，mixed/integrated 为 input+output；每次只呈现当前 step。
4. 每个首答后，AI在同一次回复完成判定、仲裁和可见反馈。
5. 可见反馈后、下一道需作答任务前，执行一个逻辑 `SaveActivityCheckpoint`；它可同时返回下一 prepared step。
6. 最终反馈/summary 展示后，执行一次统一 `FinalizeSession`。Next-cache 编译属于提交后的尾部工作。

普通文本回答到即时反馈之间的计划内工具、文件 I/O、联网、历史搜索、第二模型和 reducer 调用均为零。

这里的“可见”是时序要求：首次完整反馈或 summary 通过工具调用前的用户可见消息交付。若宿主只在工具后持久展示 final，final 必须简洁复述同一内容以保持自包含；复述不能改变判定或生成第二份反馈。

## 耐久 checkpoint

`.state/current-session.json` 是课中 pending 状态的唯一权威，原子替换并保留一个校验通过的上一代。它有界保存：

- revision、package hash、queue guard、stage/等待动作；
- 已展示内容 hash、冻结契约；
- 首答最小必要片段、冻结判断、反馈是否已展示；
- repair/retry/exposure/actual support；
- pending review batches、observations、vocabulary/error candidates、correction；
- 稳定 event/batch/finalization ID、幂等键和 pending persistence phase。

不保存完整对话、音频、外部材料或无关推理。Prepared 未答活动可原样重显；已经首答且反馈已展示的活动不重问、不重判、不重置提示。

若在“回答已收到、反馈尚未展示”的极小窗口中断，优先从当前对话恢复已生成反馈；无法可靠恢复时记 `recovery_uncertain / not_assessable`，不强迫重答，也不伪造已展示反馈。

同一 checkpoint key+payload 的重试返回原 receipt；同 key 不同 payload 拒绝。未取得成功或可恢复 receipt 前不得呈现下一道需作答任务。

## 课末唯一正式事务

最终 feedback/summary 之前只冻结，不正式追加 review history/audit/evidence，不改变 review due/strength、adaptation、长期 projection、plan 或 terminal session，也不运行全量 Rebuild/Validate。

`FinalizeSession` 与 `AbandonSession` 复用一个有界 WAL：

1. 持久化 intent、session/checkpoint revision、guard、payload hash、expected revisions 和稳定 ID。
2. 校验草稿、guard、ID 与本次触及的引用。
3. 幂等追加不可变事实。
4. 只更新受影响的短 projection。
5. 写引用 transaction ID 的 terminal receipt。
6. 按 disposition 更新 plan/queue。
7. 更新关键 bootstrap index。
8. 标记 committed。

只有对应 WAL committed，`completed / abandoned` terminal 才生效。任一步中断从最后 phase 继续；同 key+同 payload 返回原 receipt，同 key+不同 payload 拒绝，响应丢失不能重复事实或推进队列。

### Finalize

- 直接消费冻结草稿；调用者不预改正式文件，也不重新判分。
- 按 session contract 校验必需阶段、已展示活动终止状态、queue guard 和实际触及引用，不跑全库 Validate。`plan_role=cycle_review` 以 feedback 与 `goal_decision` 收口；普通 `session_type=review` 才要求 review 阶段。到期 review 若未作答，保持原 due 且不伪造完成，不因此把已完成的 integrated 主线判为失败。
- 有效、invalid、not-assessable 都可如实终止活动；归档不要求学习者答对或一定产生 A 类证据。
- 事实和必要短 projection 成功后才写 completed receipt、推进 plan/queue/index。
- 失败保留 `pending_finalize`；恢复前不开放下一正式 session。
- Dashboard/current-plan 全量视图失败只标 `rebuild_required`；next-cache 失败只标 `preload_pending`，均不回滚课程。

### Abandon

只有用户明确放弃时触发。提交范围仅限已经收到首答、判断已冻结且反馈已展示的原子事实，以及已经满足正式准入的候选；未答、未判、未展示反馈和临时教学笔记不提交。

Session 为 abandoned，当前 plan item 回到 planned 并保持队首；不增加 completed/cycle 计数，不发布下一队首 cache。已提交事实标 `source_session_outcome=abandoned` 并保留 content/context exposure，防止重做时把同一暴露冒充新 A 类。

## 尾部预加载

Finalize 提交后才可构建真实下一队首 provisional package。发布前重新校验 guard；失配即丢弃 candidate，不能改变 queue。已存在安全兼容 generation 时 no-op。

构建或发布失败只标 preload_pending，保留安全旧代、skeleton 和 fallback，不回滚本课，也不是 Finalize 失败条件。

## 延迟与失败

- 本地 Bootstrap 项目内路径目标不超过 5 秒。
- 正常缓存路径从“开始今日学习”到首个完整可作答步骤目标不超过 30 秒；项目可控硬预算不超过 90 秒。
- 外部替代在 `min(request_started_at + 60 秒, deadline_at - 20 秒)` 停止，至少保留 20 秒冻结并展示 fallback。
- 回答到反馈的计划内工具/I/O/联网/第二模型为零。
- 反馈后 checkpoint 内部工作目标不超过 0.5 秒；含现有工具启动的用户可见阶段切换目标不超过 10 秒。
- 课末必要事务和短 projection 目标不超过 5 秒；超过约 10 秒时学习者应已看到反馈，只给一次简短保存进度，可以离开。

记录 bootstrap、material-ready、decision、checkpoint、persistence、cache hit/失效、next-cache compile/publish、fallback 和 uncontrolled latency。指标随 checkpoint/事务批量保存，不额外调用；平台排队、模型服务和用户网络单列。

失败后的方向是恢复或降级，不排障循环：反馈不撤回、不要求重答；非必要网络/cache 一次失败即降级；queue guard 或正式 contract 无法确认时不形成正式 evidence。技术状态不能影响 review 评级或写成学习者失败。

第一版只使用动作白名单懒加载、双代有界 index、一次反馈一次 checkpoint 和一课一次文件事务；不引入常驻进程、新数据库、消息队列或正确性依赖的内存服务。

## 启用门

C0003、旧 session 与旧 review transaction 保持 v3。C0004 只有在事务、恢复、lazy load、catalog/ladder、source policy、六课 skeleton、合法自包含 fallback、迁移演练和完整校验通过后才原子启用。每个 v4 session 必须同时有 start 与 committed finalization/abandon receipt；同一 session 不混用版本。
