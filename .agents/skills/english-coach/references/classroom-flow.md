# 逐题课堂：classroom_version = 1

仅用于返回中明确带有 `prepared_step.classroom_version=1` 的新课程。旧进行中课程保持 [runtime-protocol-v4.md](runtime-protocol-v4.md) 的原动作；恢复时不转换 checkpoint。

## 进入课程

用户要求开始或继续学习时，调用 `Bootstrap -EnterSession -IdempotencyKey <稳定请求编号>`。这一个调用内部先执行 Bootstrap，只有允许开课时才启动新课程；已有课程直接恢复。进度查询、计划讨论等仍使用普通 Bootstrap，不带 EnterSession。

返回 `bootstrap` 表示刚恢复一项事务，继续按返回动作处理。`confirm_next_cycle_plan` 按发布协议处理。不要为了提速越过版本、队首或正式提交检查。

仅处理当前 `next_action`；相同版本且当前上下文已经完整加载的规则可直接沿用。工具返回的 `metrics` 是脚本耗时，不是用户等待时间。

## 准备复习：prepare_review_questions

在任何题目展示前，读取 [review-teaching.md](review-teaching.md)。依据 `prepared_step.review_items` 一次为整个选定切片构造低歧义题，保持项目、顺序、题型阶段和范围。检查题面与反馈是否可能互相泄题。

调用 `PrepareReviewQuestions`：公共参数见 [tracker-actions.md](tracker-actions.md)，payload 为 `{questions:[...]}`。每项只提供 `review_item_id`、`prompt_text`、`task_contract`；契约包含 `question_type,target_scope,target_count=1,scoring_target,answer_key或semantic_scope,allowed_variants,standard_hints,invalid_conditions,content_id,context_id,ambiguity_checked=true,batch_leakage_checked=true,uses_options,uses_word_bank`。程序绑定题号、lane、recipe stage 与权重。

成功标志为 `present_review_question` 和完整 `prepared_step.question`。一次只展示当前题的公开部分，不展示内部答案、剩余题或评分契约。每批开始说明答案后可写 `?` 表示犹豫。题目尚未冻结或契约检查失败时不展示半成品。

## 复习回答与修复

1. 收到普通文本回答后，用已加载的题目和规则立即判断并展示反馈；这段期间不调用工具、不读写文件、不联网。答对简短确认；需要修复时先给最少提示。
2. 反馈展示后，调用一次 `SaveReviewAnswer`。payload 必须有当前 `question_instance_id`、`feedback_shown=true`、简短 `feedback_text`；首答另有 `answer_excerpt,language_validity,target_demonstrated,rating,rating_reason`，invalid 另有 `invalid_reason`。首次评级由 [review-teaching.md](review-teaching.md) 决定。
3. `followup=advance` 表示本题互动已结束；`repair` 表示一次提示后等待修复，必须附 `followup_prompt`。程序最多允许三个 again 项进入互动修复。只有保存回执成功后才呈现下一项需要作答的动作。
4. 返回 `repair_review` 时呈现冻结的 `followup_prompt`。收到修复回答后先反馈，再保存；不再提交 `rating`。修好用 `advance`；仍不会时给最小示范，再以 `followup=reconstruct` 和重构题面保存。
5. 返回 `reconstruct_review` 时让学习者重构一次。其回答反馈后用 `advance` 保存并结束本题，不能继续加重试。修复一直记 guided，首次评级不变。

`language_validity` 用 `pass|fail|not_assessable`；`target_demonstrated` 用 `demonstrated|not_demonstrated|not_assessable`。`feedback_text` 最多 1200 字符，`answer_excerpt` 和 `followup_prompt` 最多 600 字符，保存最小必要片段。

### 跳过、泄题与恢复

- 学习者跳过当前未答题：保存 `control=skip,followup=advance`，不提交评级，不改变 due。技术上当前题已暴露且未答时可用 `control=exposed`。
- 当前反馈暴露后续题：在同一次保存的 `exposed_question_ids` 中列出受影响的冻结题号。题号来自已冻结批次或 `remaining_question_ids`；程序延期这些项目，保持顺序，不临时另抽项目补位。
- 保存失败或响应丢失：使用同一 key 和完全相同 payload 重试。仍不确定时保留题号并报告技术阻塞，不重问首答、不先出下一题。
- 恢复响应会给原题、最近反馈摘要、已冻结首答结果和修复题面。继续其等待动作；已评分首答不重判。
- 若对话已收到首答但存档尚未成功，优先恢复同一次已生成的判断；无法可靠恢复时记 `invalid` 的技术原因 `recovery_uncertain / not_assessable`，不要求重新作答来冒充首答。

## 转主课

最后一题存档后，程序会绑定并校验预备的主课首活动；正常返回 `present_activity`。这时一次加载 [task-contracts.md](task-contracts.md) 与 [teaching-loop.md](teaching-loop.md)，之后沿用当前上下文中的规则，展示 `prepared_step.contract` 的公开题面。

主课材料与题目已经由 core 预备；程序补齐固定字段并调用与 `PrepareActivity` 相同的校验。只有 `prepare_activity` 才进入 [activity-preparation.md](activity-preparation.md) 的人工编译分支，输入在 `prepared_step.preparation`。难度 probe、多义 binding 或尚无完整 core 等情况保持明确分支。

`retry_classroom_transition` 表示复习已经存档、主课准备未完成。可用 `Bootstrap -EnterSession` 恢复一次；再次失败则报告原因并停止正式取证。已答复习不重做。

主课每轮反馈后沿用 `SaveActivityCheckpoint`；返回 `clarify / repair` 时按 [teaching-loop.md](teaching-loop.md#主课修复的保存与恢复) 保存同题后续回答并恢复等待动作。最终总结展示后才 `FinalizeSession`；只有 committed receipt 代表正式结课。退出或跨日保持进行中；只有明确放弃才 `AbandonSession`。

## 数据边界

逐题存档更新同一 pending ReviewBatch，课末才改变正式排程。冻结题目、首次判定、修复、位置和幂等回执保存在同一有界 checkpoint；省略重复参数不会省略评分契约。AI不手改学习档案、不运行全量维护命令。
