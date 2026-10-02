# V4 到期复习协议

仅在 v4 `next_action` 进入日课 review 或“复习到期内容”时读取。本协议处理可原子评分的词义、表达和句型；阅读主旨、听力推断、篇章组织和开放互动使用新材料 skill probe、轮次复盘或 assessment，不进入原子 SRS。

到期时间、内容、顺序、题型与容量独立于当前焦点、主技能、难度状态和主线材料。复习结果可以成为长期判断的支持信息，但一条原子项目成功不能直接使宏观 competency 或 focus goal 达标。

## 正式事实

- `learner/review-items.tsv` 是项目当前状态与排程的唯一正式项目表。
- `learner/review-item-sources.tsv` 连接 vocabulary、error、session 等来源；vocabulary/error 只说明学过什么和问题来自哪里，不再各自拥有 v4 排程。
- `learner/review-history.tsv` 是只追加事件账本，保存首次评级、当时 recipe/strength、双重判定、repair、控制或更正事件及后续日期。
- 同一“形式＋词义”同一时刻最多一个正式项目。不同词义或真正独立的句型可拆分；复合问题必须原子化。
- `skill-evidence.tsv` 不复制每次 review event；长期结论通过 event ID 引用。

正式状态为 `active | maintenance | legacy_unverified | needs_recipe_fix | needs_reteach | paused | retired`。`candidate | observed_only` 属于候选池，不是正式排程状态。

## 教学规则

展示复习题之前读取 [review-teaching.md](review-teaching.md)，其中统一定义题面家族、recipe stage、歧义与泄题检查、首次评级及短修复。`classroom_version=1` 的调用与恢复顺序见 [classroom-flow.md](classroom-flow.md)；旧 session 继续下述批次接口。

## 强度、阶段与再教学

`strength_level 0–5` 对应 1、3、7、14、30、60 天；recipe 只控制题型深度。

- invalid：两轴不变，仍到期。
- again：strength 归零；连续两个不同学习日 again 才降一个 recipe stage。
- hard：recipe 不变，strength 降一级，最低为零。
- good：未到最高 recipe 时升一级并把 strength 设为 1，三天后验证；已在 transfer 时 strength 加一。
- easy：只在 transfer，strength 加二至最高 5，不跳 recipe。
- 成功中断连续 again；降级保留历史高阶段事实。

连续三个不同学习日 again，或 strength 0 的五次有效复习仍无 good/easy，进入 `needs_reteach` 并暂离普通到期队列。下一轮复盘诊断先修、目标大小、题型和价值；只能重教后再激活、修改目标，或由用户确认 retired。重教后以 `relearn + strength 0` 恢复，下一学习日复查；它不占新项目名额。`needs_reteach` 与 `needs_recipe_fix` 严格分开。

## Maintenance

只有全部满足才进入 maintenance：

- constrained transfer 且 strength 5；
- 两条不同学习日、新语境的迁移成功，至少一条为正式 transfer good/easy，另一条可为合格 `spontaneous_transfer`；
- 两条相隔至少 14 天；
- productive 项至少一次真正无词库输出。

最后由正式 transfer good/easy 补齐时立即进入；若最后由 spontaneous transfer 补齐，只派生 `maintenance_ready=true`，保持 active，等待下一次正式 good/easy。hard/again 使不再成立的 ready 自动消失；invalid 不影响。

maintenance 间隔依次为 60、120、180 天，之后以 180 天为上限。maintenance 中 hard 退出为 `active/strength 4`，30 天后复查；again 退出为 `active/strength 0`，下一学习日到期；invalid 不改变。原子 maintenance 不等于宏观能力 stable。

## 候选准入

- 每课最多记录六个 encountered/candidate；正式 SRS 每六次训练最多新激活两个。
- 第三次训练后的闸门最多激活一个；第六次补足本轮最多两个，未用名额可结转到第二个闸门。
- 候选必须原子、去重、词义明确且可生成低歧义题。
- 排序：用户明确要求 ＞ 跨任务或跨日结构性复发 ＞ 影响更大 ＞ 复用更广 ＞ 首次出现更早。
- 普通候选轮末未入选转 `observed_only`；再次复发可重新候选。用户指定项占同一名额。
- active+maintenance 到期负担超容量或 recovery mode 时暂停自动激活。
- 新项目从 `relearn/strength 0` 开始，下一学习日到期。

## 容量与三车道

可见容量单位：relearn `1`、recall `1.5`、transfer `2`；tracker 内部使用 `2/3/4`。

- 正常批次容量上限 6、最多 6 项、目标约 5 分钟。
- 恢复批次容量上限 10、最多 10 项、目标约 8 分钟。
- 依队列取项；下一项放不下即停止，不越过它找更轻项目。
- 正常课一个预冻结题批；恢复课最多两个题批。漏答只追问漏答项。
- 专门复习课把容量视为每批上限；每批完成判定、repair 与 checkpoint 后，有时间才开下一批，直到课程预算、队列为空或用户停止。
- 已展示但未答不评分并保持到期；未选择也不算失败。

队列保护轮为 `active → maintenance → legacy`，各取一个；剩余容量按 `active → legacy → maintenance` 循环。空车道跳过；当前车道队首放不下就停止。active 内 recheck 和最近 again 优先，其他按 due、strength、ID；暂停、修题、再教学和用户移出的项目不堵塞车道。

## Legacy

迁移不改 vocabulary、error 或旧 review history，不补造 recipe、support 或 transfer。只有完全相同的概念和词义可自动合并，并保留全部来源、采用更早 due 和更低 strength；含糊匹配人工处理。

旧项为 `legacy_unverified`，旧 level/due 只供排序与审计，不能证明 recall/transfer 或直接进入 maintenance。首次定位统一使用无答案提示的 recall：

- again → `active/relearn/strength 0`
- hard → `active/recall/strength 0`
- good → `active/constrained_transfer/strength 1`
- 禁用 easy
- invalid、漏答、技术故障继续 legacy

静态迁移已确认无法恢复原子目标或评分契约时，展示前直接 `needs_recipe_fix`；已入队项仍需连续两次生成失败才进入。

## 主线表现与用户控制

主线自然成功只有在首次、未要求或暗示目标、本课未暴露答案、非照抄，且形式、意义、语境均正确时才可记录 `spontaneous_transfer`；同概念每课最多一条。它不直接改变 strength、recipe、status 或 due。

主线明确误用只为下一学习日设置 `recheck_due`；必须是本课选中并告知的最多三个主题、学习者实际尝试且明确误用。同概念每课一次。未尝试、正确同义表达、自我修正、意图不明、不可靠 ASR、guided 或已看示范不得触发。正式复查才改变排程。

- `skip`：只跳过本课，不评级、不改 due。
- `pause`：可逆移出自动队列，保留状态与历史。
- `retire`：仅用户确认，停止排程但不算 mastered；恢复从 relearn/0 验证。
- “我会了”只能触发一次不泄题验证，不能直接跳级或 maintenance。
- 非到期主动练习为 practice，不改变正式状态；主动报告遗忘只设下一学习日 recheck。

## 审计、申诉与正式提交

只有实际展示的 `question_instance` 形成最小审计记录：短题面、冻结契约、首答最小判定片段、language validity、target demonstrated、评级与理由、invalid 原因和 repair 结果。默认使用非私人语境；个人答案只留目标片段并脱敏，口语只留必要转写，不保存音频或整段对话。

申诉不覆盖历史：

- 题面遗漏合理答案、泄题或技术故障：追加 `void`，恢复答前状态。
- AI按原契约判错：追加 `correction`，按原首答改为正确评级。
- 用户事后补交答案：只能算 repair。

存在后续事件时按顺序重放全部有效事件。用户可以要求复核，但不能直接指定评级。

每批反馈展示后，冻结一个带稳定 batch/event/idempotency ID 的 pending `ReviewBatch`，包含有效评级、invalid、更正和控制事件，并保存原 `answered_at/study_date`。课中不正式更新 history、due、strength 或 projection；全部批次由本 session 的 `FinalizeSession`，或明确 `AbandonSession` 的允许范围统一提交。恢复继续原题序、题面、提示和 repair 状态，不重问或重复评分。
