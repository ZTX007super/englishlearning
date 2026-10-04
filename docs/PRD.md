# English Learning 项目 PRD

> 文档状态：初版，基于 2026-10-04 对仓库代码、协议文档与真实学习数据的实测分析写成。
> 事实来源优先级：`AGENTS.md` → `MAINTENANCE.md` → `.agents/skills/english-coach/SKILL.md` 与 `references/` → `scripts/lib/*.ps1` 实现 → `learner/`、`sessions/` 真实数据。
> 本文中标注 **[已实现]** 的条目有可执行代码与测试支撑；标注 **[设计中]** 的条目只有文档定义、代码路径尚未接通；标注 **[缺口]** 的条目是实测发现的问题。

---

## 1. 文档目的与阅读入口

| 读者 | 建议入口 |
| --- | --- |
| 学习者（人类） | `README.md` → 本文档第 2、3 节 |
| AI 教练（运行时） | `AGENTS.md` → `SKILL.md` → 本文档第 5 节功能需求 |
| 维护者 | `MAINTENANCE.md` → 本文档第 8 节非功能需求与第 10 节已知缺口 |

本文档不复制协议细则。协议以 `references/` 下文件为事实源；本文档负责说明**产品是什么、为谁解决什么问题、功能边界在哪、当前真实状态如何**。

---

## 2. 项目定位与问题陈述

### 2.1 一句话定位

一个**由 AI 英语教练驱动、以本地文件档案为事实源的单人长期英语学习系统**。AI 负责教学判断与反馈，PowerShell tracker 脚本负责进度记录、复习排程、事务提交与中断恢复。

### 2.2 要解决的问题

传统 AI 对话式英语练习存在四个结构性缺陷，本项目逐条针对：

| 问题 | 本项目的解法 |
| --- | --- |
| AI 每次对话都"从零开始"，不知道自己教过什么、学员弱在哪 | 长期档案 + 能力门槛地图（`competency-catalog.json`）显式追踪听说读写四项状态 |
| AI 看完回答后临时定标准，判定随意且无法复核 | **任务契约出题前冻结**：最多 3 条标准、`essential`/`required` 分级，AI 不得事后加门槛 |
| 学员说"我会了"就算掌握，缺少延迟验证 | **原子 SRS + recipe 三阶段**：当堂修复只算教学结果，跨日首次独立回答才改变正式排程 |
| 长时间学习后能力自然漂移，无人复核 | **焦点目标 + 轮次复盘**：每6 课一次正式判断，四个决定 `met/continue/redesign/insufficient_evidence`，强制拆解不无限延期 |

### 2.3 明确的非目标

- 不做社交、排行榜、账号体系、多用户协作。
- 不做移动端 App、不做前端 UI —— 交互完全发生在 AI 对话中。
- 不追求"每日必学"的强制粘性：未学习的日子不产生 `missed`，不推进轮次，不使目标失败（`curriculum.md:104`）。
- 不把内部估计称为官方成绩：CEFR 对齐是项目本地操作化，TOEFL 内部模拟明确非 ETS 官方计分。

---

## 3. 用户与使用场景

### 3.1 唯一目标用户

**单名学习者（Eddie）**，非公开产品。真实档案见 `learner/profile.md`：

| 维度 | 当前设定 |
| --- | --- |
| 建档日期 | 2026-07-20 |
| 当前水平 | 首轮四项诊断支持综合初步 CEFR B1（**非官方考试结果**） |
| 一年目标 | 综合接近稳定 CEFR B2；TOEFL iBT 内部模拟约 4.0/6.0（旧制参考约 80） |
| 每日时长 | 30 分钟 |
| 优先短板 | 无框架首次口语的实时组织与流利度；冠词、名词数与固定搭配准确性 |
| 教学语言 | 中文解释难点，英文承担主要练习与输出 |
| 兴趣主题 | AI 应用、网页开发、计算机科学（材料选材偏好） |
| 测评节奏 | 每 4 轮小测，每 12 轮分段综合模拟 |
| 正式考试日期 | **未确定**（因此 TOEFL 训练不设倒计时压力） |

### 3.2 核心使用场景

| 场景 | 触发 | 期望结果 |
| --- | --- | --- |
| **S1 每日上课** | "开始今日学习" / "继续学习" | 一次 `Bootstrap -EnterSession` 完成恢复或开课，逐题复习→主课→总结，课末一次正式提交 |
| **S2 中断恢复** | 断线、退出、上下文压缩、跨日 | 回到准确的等待动作，不重问已答题目，不重置已给提示，不创建第二个 session |
| **S3 轮次复盘** | 第 6 次训练后 | 展示证据与限制，讨论焦点目标与下一轮，用户确认后 `PublishCycle` 原子发布 |
| **S4 进度查询** | "查看进度" | 普通 `Bootstrap`（不带 `-EnterSession`），**不开课** |
| **S5 独立批改** | 粘贴一段英语 | 直接进行，不入档（`SKILL.md:13`） |
| **S6 备份迁移** | 换电脑、重要维护前 | `backup.ps1` 生成含 `.state/` 的校验 ZIP，恢复到新目录验证 |

### 3.3 真实使用量（截至 2026-10-04 实测）

| 指标 | 实测值 |
| --- | --- |
| 已完成课次 | 14 节（2026-07-21 ~ 2026-08-12），全部 `completed`、全部 30 分钟 |
| 累计学习时长 | 420 分钟 |
| 轮次进度 | C0001–C0004 全部完成（35 个 plan item），C0005 完成 3/7 |
| 词汇 / 错误记录 | 47 条 / 47 条（`vocabulary` 全部 `active`；`error` 46 `active` + 1 `paused`）。**47 条词汇的 `next_review` 全部已到期**（最晚 2026-09-14） |
| 复习事件 | 186 条：good 92、hard 70、again 21、easy 3（again 占 11.3%）。item_type：error 83、vocabulary 79、review_item 24 |
| 技能证据 | 106 条 × 65 列。v3 格式 96 条 + v4 格式 10 条（`E4-` 前缀）。skill 分布：speaking 50、writing 24、listening 16、reading 9、mixed 7 |
| 连续学习 | 0 天；最近 14 天 4 学习日 / 150 分钟 |

---

## 4. 系统架构与产品边界

### 4.1 三层职责划分

```
┌─────────────────────────────────────────────────┐
│  AI 教练（LLM）                                   │
│  教学判断、反馈生成、材料选择、逐题推进             │
│  职责：呈现 next_action、处理学习者回答、执行动作    │
│  约束：只执行 next_action，不手改档案，不自行计算排程│
└────────────────────┬────────────────────────────┘
                     │ 结构化命令 / JSON 回执
┌────────────────────▼────────────────────────────┐
│  tracker.ps1（唯一入口，纯本地 PowerShell）        │
│  状态机 · 排程reducer · WAL 事务 · 幂等 · 校验      │
└────────────────────┬────────────────────────────┘
                     │ 原子文件写 + 完整性哈希
┌────────────────────▼────────────────────────────┐
│  本地档案（事实源）                                │
│  learner/ 正式事实   .state/ 运行态   sessions/ 课次│
└──────────────────────────────────────────────────┘
```

### 4.2 关键架构决策

| 决策 | 选择 | 理由（来自设计文档） |
| --- | --- | --- |
| 事实源 | TSV/JSON 纯文本文件，追加写 | 可审计、可 diff、可手工修复、无需数据库 |
| 状态机位置 | 全部在脚本，AI 不做状态判断 | 避免 AI 自行计算排程/指纹/枚举 probe |
| 并发控制 | 独占文件锁（2 秒超时）+ owner token + expected revision | 脚本耗时可占 seconds 级，必须防重入 |
| 崩溃恢复 | 单一Bootstrap 入口按固定优先级续跑未完成事务 | 断线是常态，不是异常 |
| 版本迁移 | v3/v4 双轨，v4 门禁通过后原子启用 | 历史审计不能被新协议覆盖 |
| 进程模型 | 无常驻进程、无新数据库、无消息队列 | 第一版明确排除（`runtime-protocol-v4.md:169`） |

### 4.3 数据分层

| 层 | 位置 | 语义 |
| --- | --- | --- |
| 正式事实 | `learner/*.tsv`、`sessions/**` | 只追加、可重放，是唯一权威 |
| Pending 草稿 | `.state/current-session.json` | 课中恢复所需，**不是**学习事实 |
| 派生投影 | `learner/dashboard.md`、`current-plan.md`、`competency-status.tsv` | 可重建，不得反写事实 |
| 可丢缓存 | `.state/activity-packages/`、`.state/classroom-templates/` | 只为加速，丢了能从骨架重建 |

---

## 5. 功能需求

### FR-1 状态机与动作路由（教师状态入口）

**需求**：任何学习请求先经`Bootstrap -EnterSession -IdempotencyKey <稳定编号>` 定位唯一合法下一动作，AI 只执行该动作。

| 要素 | 规格 |
| --- | --- |
| 唯一入口 | `.agents/skills/english-coach/scripts/tracker.ps1` |
| 动作集 | 25 个 `Action`（v3 legacy 专属 7 + v4 专属 9 + 共享 9） |
| 返回体 | 固定七字段：`status` / `next_action` / `receipt` / `reason_code` / `prepared_step` / `runtime_version` / `next_action_contract` |
| 动作契约 | `kind ∈ {tracker, interaction, maintenance_or_router}` + `required_parameters` + `values_from` + `reference` |
| 幂等 | 每次写动作一个新稳定 key；同 key 同 payload 返回原receipt，同 key 异 payload **拒绝** |
| 并发 | `ExpectedRevision` 严格比对；owner token 每次写续约 |

**验收**：
- `reason_code` 映射为简短人话时**不改变语义**。
- `-EnterSession` 缺 `IdempotencyKey` 时不得创建第二个 session。
- 版本缺失或冲突时停止正式动作并报告技术阻塞，**不得**猜测继续。

**状态**：[已实现] `classroom-runtime.ps1:198`、`session-runtime.ps1:800`

---

### FR-2 逐题课堂流程（classroom_version = 1）

**需求**：把课拆成"一题一存档"的确定性流程，消除课中往返与重复生成。

| 阶段 | 动作 | 成功标志 |
| --- | --- | --- |
| 组合开课 | `Bootstrap -EnterSession` | 内部完成检查→恢复→启动→首活动准备，返回一个可执行动作 |
| 复习出题 | `PrepareReviewQuestions` | 一次冻结整个切片，返回 `present_review_question` + 完整题面 |
| 逐题作答 | `SaveReviewAnswer` | 反馈已展示后一次存档，直接返回下一动作 |
| 转主课 | 末题保存内联完成 | 同一工具调用内绑定并校验主课首活动，返回 `present_activity` |
| 主课推进 | `SaveActivityCheckpoint` | 每轮反馈后一次存档，可同时返回下一 prepared step |
| 正式结课 | `FinalizeSession` | committed receipt 是唯一"正式保存"凭证 |

**关键约束**：
- **反馈先展示，之后存档**。未取得成功或可恢复 receipt 前不得呈现下一道需作答任务。
- 已首答且反馈已展示的活动**不重问、不重判、不重置提示**。
- `retry_classroom_transition` 表示复习已存档、主课准备未完成 → 恢复准备一次，不重做复习。
- 有到��� review 时 `present_review` 优先但保持独立；未作答则保持原 due，不伪造完成。

**验收**：题批位置、修复状态、首答评级三者冻结在 checkpoint；同一题只允许一次 prompted repair；主课每问题最多 2 次 repair 回答，每活动最多 12 个后续回合。

**状态**：[已实现] `classroom-runtime.ps1`、`tests/classroom-latency.cases.ps1`（19 例）

---

### FR-3 任务契约与评分

**需求**：每个可评分活动在**展示题面之前**冻结契约，AI 不得看完回答后新增成功条件。

| 字段 | 规格 |
| --- | --- |
| 判据条数 | 1 ≤ criteria ≤ 3（硬校验） |
| 重要性 | `essential`（未满足即 failed）/ `required` |
| `task_result` | `not_assessable` \| `failed` \| `partial` \| `success` |
| `criterion_result` | `met` \| `partial` \| `not_met` \| `not_observed` |
| `purpose` | `practice` \| `probe` \| `transfer` \| `assessment` |
| `mode` | `accuracy` \| `fluency` \| `mixed` |

**判定算法**（顺序固定，`reducers.ps1:37-63`）：
1. 技术故障/指令含糊/证据不足 → `not_assessable`
2. 任一 `essential` 为 `partial`/`not_met` → `failed`
3. 任一标准 `not_observed`（上游失败导致未被公平观察）→ `not_assessable`
4. 任一 `required` 未满足 → `partial`
5. 其余 → `success`

**八种 activity_family**：`source_comprehension`、`retell_summary`、`opinion_explanation`、`interaction_roleplay`、`integrated_response`、`controlled_form`、`extended_writing`、`oral_imitation`。TOEFL 题型先映射到family，不另建判断逻辑。

**关键约束**：
- "英语整体是否成立"与"指定目标是否被证明"**分开**判定（`language_validity` × `target_demonstrated`）。
- 要求 `exact_expression` 但用了另一种正确英语 → `pass + not_demonstrated`，**不得**说成坏英语。
- 正确但可更自然 = `upgrade_opportunity`，**不改变**已成功的 `task_result`。
- `not_observed` 不得伪记为 `not_met`。

**状态**：[已实现] `task-contracts.md`、`reducers.ps1:37-63`；TOEFL 映射 **[设计中]**

---

### FR-4 纠错微循环

**需求**：把"纠错"从自由发挥变成有预算、有顺序、可停止的确定流程。

**状态骨架**：
```
独立探测 → 按冻结契约判定 → 归因合并排序 → 最少必要帮助
  → 修复受影响功能 → 淡出帮助 → 新活动/新语境迁移 → 停止并记录
```

**双重预算**：

| 预算 | 上限 | 说明 |
| --- | --- | --- |
| 完整微循环数 | 0–3 / 课 | 没有高价值问题时为 0，不为凑数虚构错误 |
| 复杂度预算 | 3 / 课 | 局部问题各计 1，全局问题各计 2；**每课最多 1 个全局循环** |
| 反馈主题数 | 3 / 课 | 三个主题若全进循环，不得再附送额外小错 |
| 递增帮助重试 | 2 次 / 问题 | 之后给最小示范 → 简化迁移；仍失败记录缺失先修并结束 |

**仲裁顺序**（8 级，确定性）：沟通阻断 > essential 失败根因 > 改变/严重模糊意义 > 命中冻结标准 > 命中当前焦点 > 有复发证据/高迁移价值 > `upgrade_opportunity` > 偶发小错。

**七种适配器**：意义理解、事实定位、内容/篇章组织、语法形式、词汇/搭配/语域、语用/互动、发音可懂度。

**两段式反馈**：
1. 第一条消息一次给齐：结果 + 选中 1–3 个问题 + 最小解释 + 简短小错反馈 + **只要求修复原表达**。
2. 修复完成后**才单独**给新 `activity_id` 的迁移题。

**纠错时机**（由 `purpose` × `mode` 决定）：

| 组合 | 时机 |
| --- | --- |
| `probe` / `assessment` | 先保全完整独立表现，再反馈（仅技术故障/真实阻断可提前中止，记 `not_assessable`） |
| `practice` + `accuracy` | 每个独立小题后可即时纠正 |
| `fluency` |整段输出结束后统一反馈，小语法错不得中途打断 |
| `mixed` | 先内容与任务完成度，输出结束后处理语言形式 |

**状态**：[已实现] 仲裁与预算；提示阶梯 **部分实现**（设计 3 级，`classroom-runtime.ps1:52` 只有 2 级）；adapter 映射 **部分实现**（仅 `controlled_form → grammar_form` 显式，其余 6 种靠自由文本）

---

### FR-5 复习系统（原子 SRS）

> **重要**���本项目**不使用 SM-2**。实际算法为固定间隔表 + recipe三轴正交。

**需求**：区分"当堂修正"与"跨日长期掌握"，防止"看完纠正就以为掌握"。

**双通道分离**：
- **原子 SRS**：可单独评分的词义、表达、句型 → `review-items.tsv`
- **宏观技能探测**：阅读主旨、听力推断、篇章组织 → 新材料 probe / 复盘 / assessment，**不入**原子队列

**三家族**：`receptive_meaning`（识别意义）、`productive_expression`（主动提取）、`productive_pattern`（生成结构）。
**三目标范围**：`exact_expression`（须展示指定词）、`pattern`（须展示结构）、`meaning_or_function`（判断意义/功能）。

**recipe_stage 三阶段**（与 `strength_level` 是**两条独立轴**）：

| 阶段 | 特征 | 有效题型限制 |
| --- | --- | --- |
| `relearn` | 原/近语境 + 明显支架 | 选择题/词库可用 |
| `recall` | 受控题面、**无答案型提示**、独立提取 | **选择题/词库不能证明 recall** |
| `constrained_transfer` | 新语境 + 明确要求 + 真实语义限制 | 自由造句不可证明 transfer |

**排程算法**：
- 间隔表固定 `strength_level 0..5` → `1 / 3 / 7 / 14 / 30 / 60` 天。**无EF 增长因子、无 difficulty 因子、无 success/failure 相乘。**
- 评级影响：再次 `again` → strength=0；连续两个**不同学习日** again 才降一级 recipe stage；`hard` → recipe 不变、strength 降 1；`good` → 升一级 recipe 并把 strength 设 1；`easy` → **仅限** `constrained_transfer`，strength +2。
- 成功中断 again 连击。

**七种正式状态**：`active` / `maintenance` / `legacy_unverified` / `needs_recipe_fix` / `needs_reteach` / `paused` / `retired`。`candidate` / `observed_only` 是候选池，**不是**排程状态。

**退出与降级**：
- `needs_reteach`：连续三个不同学习日 again，或 strength 0 的五次有效复习仍无 good/easy → 暂离普通队列，重教后以 `relearn + strength 0` 恢复。
- `maintenance` 升级：constrained_transfer ∧ strength 5 ∧ 两条不同学习日新语境迁移成功（至少一条正式）∧ 相隔 ≥14 天 ∧ productive 词族至少一次真正无词库输出 → 间隔 60→120→180 天封顶。
- `needs_recipe_fix`：连续两次无法生成低歧义题（**修题不改评级/strength/due**）。

**四评级锚点**：

| 评级 | 判定 |
| --- | --- |
| `again` | 错误 / 不知道 / 无法提取 / 需目标相关帮助 |
| `hard` | 最低限度正确但明显费力、不确定、自我修正；唯一机械笔误例外 |
| `good` | 按当前 recipe 独立正常正确 |
| `easy` | **仅限** `constrained_transfer`，需可靠的高要求 + 流畅 + 确信证据；异步文字不能凭感觉判|
| `invalid` | 歧义/生成错误/技术故障/不可靠转写，**不进入排程** |

答案后写 `?` 且正确 → `hard`。AI **不得**按消息间隔猜思考时间。

**followup 三态**：`advance`（本题结束）/ `repair`（一次提示后修复，须附冻结 `followup_prompt`）/ `reconstruct`（给最小示范后立即重构一次，其回答只能 `advance` 结束）。修复一律记 `guided`，**首答评级不变**。

**控制**：`skip`（跳过本课，不评级不改 due）、`exposed`（反馈泄题 → 延期，不产生评分/片段/history）。泄题延期集合**不跨学习日沿用**。

**队列车道轮转**：保护轮 `active → maintenance → legacy` 各取一个；剩余按 `active → legacy → maintenance` 循环。正常批 ≤6 容量单位/ ≤6 项/ 约 5 分钟；恢复批 ≤10 单位 / ≤10 项/ 约 8 分钟。

**独立性与容量**：每课最多记录 6 个 candidate；正式 SRS 每六次训练最多激活 2 个。

**状态**：[已实现] reducer 全链路、车道选择器、maintenance 升降级、双重判定 + followup 三态 + control

---

### FR-6 轮次、焦点目标与复盘

**需求**：把长期目标变成"当前这一个瓶颈"，并强制它必须被复核。

**六课 + 一复盘结构**（`settings.json: training_sessions_per_cycle = 6`）：
- 焦点能力占**2–4 个** lead 主技能位，默认 3
- 每项听/说/读/写**至少**一次可评分 primary 机会
- 任一非焦点技能在**滚动两个完成轮次内**至少一次成为 lead
- 正常一轮约 8 个 evidence-bearing primary，**硬上限 9**
- 队列只因完成、明确放弃或带理由的用户批准而推进

**焦点目标生命周期**：
- 绑定明确 `competency_id` + 可选 activity family / quality focus，**不能**写"提高口语"这类无法验收的愿望
- 默认持续 **2–4 个完成轮次**（未完成的自然周与中断天数不计入）
- 一次只能有**一个** `active` 主焦点

**四种决定**（每完成轮次恰好一次）：

| 决定 | 精确条件 |
| --- | --- |
| `met` | ≥2 完成轮次 + ≥3 条去重 A 类成功 + 跨 ≥2 学习日 + 跨 ≥2 个真正不同 context + 每个必要标准 ≥2 条 A 覆盖 + ≥1 条预排 focus confirmation 且 `cost_signal=normal` + 确认后无未解决同 anchor A 类 not-met + guardrail 未退化 |
| `insufficient_evidence` | 本轮 <2 个与 focus 直接相关、预排且有效的 A 类 opportunity。**不得**用以前轮次数量填补 |
| `continue` | 未 met 且出现新 progress marker；或证据充分但无新 marker（下一轮只改一个教学变量） |
| `redesign` | 连续两个证据充分轮次无 marker；或达最大完成轮次仍未met。第 4 轮仍证据不足 → **重设取证设计，不无限延期** |

**progress marker 三种**：`criterion_acquired`（必要标准从未达到→跨日独立达到）、`support_withdrawal`、`context_transfer`。单次做对、guided 变好、难度晋级、主观印象、平均分变化**均不算**。

**A / B / C 证据分级**：
- **A**：有效可比、首次独立、未反馈未暴露的 primary
- **B**：答前声明secondary、自然迁移、去重原子 review 趋势、用户自报
- **C**：training / guided / revised / retry / repair / 示范后表现
- **无效**：invalid、non-comparable、not-assessable、abandoned、重复、已 void

**轮次发布（`PublishCycle`）强制校验**：
- 必须有 `user_confirmed=true` + `confirmation_ref`（**不能代用户确认**）
- `from_cycle_id` → `to_cycle_id` 必须形如 `C0003` → `C0004` 且相邻
- 必须在 `from_cycle` 的 cycle_review 课中，且 `plan_id` 匹配
- 恰 7 个 plan item（6 focus/maintenance + 1 cycle_review）+ 7 个 ready 包，ID 不可复用
- 决定为 `met` 或 `redesign` 时**必须**包含已确认的下一目标
- 事务 7 阶段：`intent → goals_written → packages_written → plans_written → evidence_archived → index_written → committed`

**状态**：[已实现] 四决定判定、PublishCycle 全部校验与幂等、目标版本演进
**注意**：`Get-PracticalGoalDecision` 的 `Markers` / `Streak` 分支几乎不可达（`session-runtime.ps1:557-583`），实际多落`first_cycle_without_marker`——**[缺口]**

---

### FR-7 长期能力状态（competency / stage）

**需求**：分技能追踪听说读写，不允许平均分掩盖偏科。

**三层**：
- **stage**：3 个（`STAGE_A2_FOUNDATION` / `STAGE_B1_INDEPENDENT` / `STAGE_B2_FLEXIBLE`）
- **family**：15 个（听力 3 / 口语 4 / 阅读 3 / 写作 5）
- **gate**：45 个（A2/B1/B2 各 15），R/B/E 角色 = 30/11/4，合计 90 个 observable indicator
- **gate 状态**：`not_evidenced`（≠ 不会）/ `developing` / `stable`

**`stable` 判定**：每个必要 indicator ≥2 条跨学习日跨 context 的 A 类成功且至少一条 normal-cost；gate 还需最近 4 个完成轮次内一次当前 anchor 的预排 capability probe 或正式 assessment。每个 probe 只证明其 primary indicator，B/C 数量不能填补。

**`stage_attained`**：某技能当前等级全部 Required gate stable 且无阻塞 flag → 追加不可变 `stage_attained` 事件。Breadth/Extension 不阻塞。

**不变量**（`competency-catalog.json` `evidence_contract`）：
- `one_primary_indicator_per_observation: true`
- `time_or_cycle_count_promotes_gate: false`
- `four_skill_average_allowed: false`
- gate 更新只在 `cycle_review` 或 `assessment`

**状态**：**[设计中]** `Get-CompetencyCandidate` / `Get-StageAttainmentCandidates` / `Select-FocusGap` 代码存在（`reducers.ps1:671-905`）但**无调用方**；`Invoke-V4CycleReviewEvaluation` 硬编码 `competency_candidates=@(); stage_candidates=@()`（`session-runtime.ps1:606`）。`competency-events.tsv` / `stage-events.tsv` / `learning-insights.tsv` / `long-term-projection.json` 全项目仅在迁移时被写为空。

---

### FR-8 难度阶梯与课包缓存

**需求**：难度变化必须可解释、可比较，且不破坏证据可比性。

**9 个难度维度** × 4 步：`input_span`、`relation_load`、`discourse_moves`、`preparation_time`、`interaction_turns`、`predictability`、`required_moves`、`output_scope`、`integration_distance`；15 条family 绑定。

**不变量**（`difficulty-ladders.json:6-15`）：
- 正式 stretch 只能沿**一个预授权维度**相邻升一级
- 每次绑定**最多 2 个**维度
- 每课**最多 1 个** probe 候选
- 换 competency 或 activity family 必须**新绑定**
- `support_is_not_a_difficulty_dimension: true`（支持强度不是难度）
- **明确排除**为难度维度：accuracy、grammatical accuracy、vocabulary control、coherence、fluency、user mood、CEFR level、model latency

**设计中的课包生命周期**：`skeleton → provisional → ready → prepared → consumed`，失败态 `stale | rebuild_required | rejected`。

**queue_guard** = sha256(canonical JSON of `plan_id, next_plan_item_id, queue_revision, package_hash, focus_goal_id`)，写入 index 尾部自校验；不符即 `queue_guard_mismatch`。

**解析三级候选**：`published_exact` → `compatible_previous` → `local_fallback`，逐级校验文件存在、≤256KB、sha256 一致、完整性、manifest `schema_version=1 && status='ready'`、6 个版本字段逐字段相等、权利白名单、skeleton 数量 1–3、core 状态 `ready`。

**状态**：**[缺口]** 生命周期 5 态只有 `ready` 落地；`provisional/prepared/consumed/stale/rebuild_required/rejected` 在代码中**无任何写入或状态机**；无自动构建器与失效矩阵；`compatible_previous_package_path` 每轮被清空（`transaction-runtime.ps1:552-553`），该分支实为死代码。

---

### FR-9 材料政策与降级

**需求**：材料必须可访问、真实、合法；失败时降级而非排障循环。

**优先级**：**缓存优先、真实来源优先于 fallback**。优先最近一代安全完整、与 queue guard 和冻结契约兼容的旧缓存。自然时间本身**不使材料失效**，不为"更新"联网刷新。

**可安全呈现门（5 条全过）**：
1. 正文/音频/transcript/题面/答案完整可访问
2. 内容与 metadata、content/context ID、hash 一致
3. 事实无已知错误（历史性内容可标 `as_of` 用于 training，**不能**当当前事实评分）
4. 涉及当前考试规则时 authority record 对本次 `test_date` 仍适用
5. 来源/许可/原创声明足以支持展示与本地保存

**来源选择**：免费、合法、无需登录的教育机构/大学/公共媒体/官方发布者；同等质量下选有可靠音频 + transcript + 长度合适者。

**一次外部替代**：仅在主材料未过门时；不递归搜索、不连续换站、不在课中排障；新材料一律 `training`（**不得**为保正式证据资格而降标准）。硬截止 `min(start + 60s, deadline - 20s)`；超时立即用同队首本地 fallback。

**fallback 要求**：每个可发布 skeleton 必须有同队首、同核心 construct 的**自包含** fallback。阅读需原创/公共领域/许可清晰；听力必须有可播放本地音频 + 准确 transcript + hash + 权利记录，只有文字则 `presentable=false`。URL-only / 需登录 / 仅流媒体 / 缺评分范围 / 权利不明**不能**作为 ready fallback。fallback 固定 training，不冒充官方 TOEFL 材料或真实来源录音。

**必须降级为 training**：已暴露或可比性不足但仍可安全教学的材料、`as_of` 历史内容、无法确认的"当前官方"说法、任何替代新材料。`training` **不豁免** misinformation 或版权；权利失败**禁止展示**。

**状态**：[已实现] fallback 资产 3 组（音频 + transcript + manifest，含 sha256）

---

### FR-10 课末正式事务（WAL）

**需求**：正式记录只有一种产生方式——committed 事务。

**唯一入口**：`FinalizeSession` / `AbandonSession` 复用一个有界 WAL，8 阶段：
```
intent → validated → facts_appended → projections_updated
  → terminal_receipt_written → plan_queue_updated → bootstrap_index_updated → committed
```

**保证**：
- 只有对应 WAL committed，`completed` / `abandoned` 终态才生效
- 任一步中断从最后 phase 继续
- 同 key + 同 payload 返回原 receipt；同 key + 异 payload 拒绝
- 响应丢失**不能**重复事实或推进队列

**Finalize 校验**：按 session contract 校验必需阶段、已展示活动终止状态、queue guard、实际触及引用；**不跑全库 Validate**。`plan_role=cycle_review` 以 feedback + `goal_decision` 收口；普通 `session_type=review` 才要求 review 阶段。到期 review 未作答保持原 due，**不因此把已完成的 integrated 主线判为失败**。有效/invalid/not-assessable 都可如实终止；归档**不要求**学习者答对或一定产生 A 类证据。

**Abandon 范围**：仅提交已收到首答、判断已冻结且反馈已展示的原子事实。Session 转abandoned，当前 plan item 回 `planned` 并保持队首；不增加completed/cycle 计数，不发布下一队首 cache。已提交事实标 `source_session_outcome=abandoned` 并保留 exposure，防止重做时把同一暴露冒充新 A 类。

**尾部预加载**：Finalize 提交后才可构建下一队首 provisional package；发布前重新校验 guard，失配即丢弃 candidate。失败只标 `preload_pending`，**不回滚本课**。

**降级不阻断**：Dashboard/current-plan 全量视图失败只标 `rebuild_required`；next-cache 失败只标 `preload_pending`。

**状态**：[已实现] 8 阶段 WAL、幂等、故障注入 8 点

---

### FR-11 中断恢复与耐久 checkpoint

**需求**：断线是常态。`.state/current-session.json` 是课中pending 状态的**唯一权威**。

**恢复优先级**（严格顺序）：
1. 已由显式 `ActivateV4` 创建的合法迁移 intent（Bootstrap 无权自行创建迁移）
2. 未完成的 start intent（确保不创建两个 session）
3. `pending_finalize` / `pending_abandon`
4. 仍 `in_progress` 的 session，定位到最后一次已保存反馈之后的等待动作
5. 都不存在时才打开 index 中的当前**严格队首**

**极小窗口中断**（"回答已收到、反馈尚未展示"）：优先从当前对话恢复已生成反馈；无法可靠恢复时记 `recovery_uncertain / not_assessable`，**不强迫重答，也不伪造已展示反馈**。

**有界存档内容**：revision、package hash、queue guard、stage/等待动作、已展示内容 hash、冻结契约、首答最小片段、冻结判断、反馈是否已展示、repair/retry/exposure/actual support、pending review batches、vocabulary/error candidates、correction、稳定 event/batch/finalization ID、幂等键、pending persistence phase。
**不保存**：完整对话、音频、外部材料、无关推理。

**落盘机制**：`Write-DurableJson` = 完整性哈希 + tmp + `File.Replace` + `.previous` 回退；读侧先 current 再 `.previous`，靠 `integrity_sha256` 判定。

**状态**：[已实现] `state-io.ps1:170-255`
**[缺口]** owner token **无TTL、无过期、无抢占**，token 泄漏即 session 永久锁死

---

### FR-12 版本迁移（v3 → v4）

**需求**：新协议不能覆盖历史审计；旧数据不得补造证据。

**C0004 启用门（10 项全过）**：C0003 存在且全部终态；C0003 恰 1 个 review 且 completed；无 in_progress checkpoint；`.state/review-transaction.json` 非 pending；3 个必需资源（`competency-catalog.json` / `difficulty-ladders.json` / `migration-v4.schema.json`）存在且合法；fallback manifest 全部 presentable + rights + 资产 sha256 校验通过；`tests/tracker-v4.Tests.ps1` 必须存在。

**ActivateV4 前置**：`-ConfirmActivation` 开关 + `user_confirmed` + `from_cycle_id='C0003'` → `to_cycle_id='C0004'`（硬编码）+ 7 个 C0004 plan_item 唯一 + manifest schema 校验 + `migration_id == M4-sha256(key|C0003|C0004)` 与 idempotency_key 一致 + boundary 三元组匹配 + 恰 1 个 cycle_review + `Test-CycleAllocation` + 每 plan 一个 ready 包且版本为 `policy 4.0.0 / catalog 1.0.0 / ladder 1.0.0 / contract 4.0.0` + 权利白名单 + skeleton 1–3 且必填 7 字段 + 恰好 1 个 active focus_goal。

**迁移 phase（9 步）**：`intent → snapshot_verified → packages_written → schema_written → projections_written → index_written → settings_written → runtime_switched → committed`。运行时指针 `runtime.json` **最后写**。

**非追溯原则**：v3 vocabulary/error → `RI-LEG-*` review items，`status=legacy_unverified`、`stage=recall`、`level=0`、`relation='migrated_without_evidence_backfill'`。**明确不回填历史证据**，不补造 contract、支持程度、迁移或高等级证据。旧 session 不批量补造 `activity_id / loop_id`。

**状态**：[已实现] 迁移器、9 阶段、幂等键
**[缺口]** 迁移硬编码 `C0003 → C0004` 与四个版本号（`migration-runtime.ps1:151-152,211-215`）；`post_activation_maintenance` 仅是回执里的字符串提示，**无执行代码**

---

### FR-13 备份与恢复

| 内容 | 策略 |
| --- | --- |
| `learner/`、`sessions/` | 完整备份 |
| `.state/` | 完整备份，含 `.previous` 上一代文件 |
| `.agents/`、维护脚本、文档、材料 | 与数据一起保存当前**实际文件**，含未提交代码 |
| `.cache/`、`*.tmp`、`*.lock` | **不备份** |
| `.git/`、`backups/` | 另由 Git 保存；排除已有备份 |

- `backup.ps1 -Action Backup` 返回 `backed_up` + ZIP 路径，含逐文件 SHA-256 清单；程序取得 v4 写入锁并复查复制期间文件是否变化。
- `Verify` 返回 `verified` 才表示全部文件与清单一致。
- `Restore` 先同样检查再写入新目录，返回 `restored`；**已有目录一律拒绝，不提供覆盖**。
- 链接文件/目录明确拒绝，避免悄悄漏掉指向项目外的材料。
- 恢复后须在新目录跑 `Bootstrap` 验证版本、队首、等待动作，再切换。

**状态**：[已实现] `maintenance/backup.ps1`、`tests/backup.Tests.ps1`（5 例：字节级备份/校验/恢复、拒绝覆盖项目或已存在归档、损坏内容在建目录前拒绝、拒绝 `../` 越界、tracker 持锁时不快照）

---

### FR-14 提醒与自动化

- 周日 20:30（Asia/Shanghai）提醒，**仅提醒，不推进计划**、不改变队列/目标/复习/能力状态。
- 测评节奏：每 4 个完成轮次一次分段小测，每 12 个完成轮次一次跨多课综合模拟。它们是**计划边界，不是自动晋级条件**。
- 轮次复盘后自动创建本地 Git 快照，**不推送**。

---

### FR-15 隐私与数据边界

| 边界 | 规则 |
| --- | --- |
| 记录范围 | 只记录与英语学习直接相关的信息。**不记录**账号、联系方式、身份号码、私人聊天、无关生活细节 |
| 正式档案 | 只保留必要表现片段与引用。**不保存**完整私密对话、完整音频或无关个人信息 |
| 可重建性 | 事件账本与 committed receipt 是事实；dashboard、current plan、长期 projection、bootstrap index、课包缓存均为**可重建派生物** |
| 外部动作 | 不安装全局依赖；不自动推送远程仓库 |
| 能力声明 | 内部估计不称为 ETS 官方成绩；CEFR 对齐是本地操作化 |

---

## 6. AI 教练行为规范

### 6.1 回答顺序（强制）

1. 一次只呈现**当前要求**的作答动作。出题前须具备完整题面、材料、判定范围、帮助边界与停止条件。
2. 普通文本首答到首次实质反馈之间，在**同一次回复**完成判定和反馈，**不调用工具、不读写文件、不联网、不做第二次模型判断**。
3. 先展示反馈，再按协议保存。取得成功或可恢复的同幂等键回执后，才展示下一项需作答动作。**正确回答简短确认；最多处理三个高价值反馈主题。**
4. 流利度任务完整输出后反馈；准确度按当前契约纠正。

### 6.2 硬性禁止

- 不得自行重置旧计划、重放 `ActivateV4`、清空旧证据
- 不得跳过 `PublishCycle` 直接开课
- **不得**手改 `learner` 表、session、排程、长期状态或计划
- 不得在普通学习/课中运行全量校验、重建、测试、Git 或迁移
- 不得把内部 pending 存档报告为正式保存
- 不得按消息间隔猜思考时间
- 不得把 pending、缓存失败或技术降级写成学习者失败

### 6.3 边界情形

- 缺少可靠音频和实际声音分析时，发音/重音/节奏/语调一律记 `not_assessable`
- 复习的日期、顺序、题型和首次评级**保持独立**，不随主课焦点改变
- 主课选择依赖复习结果时按明确规则选预备变体，**不预先假定**学习者表现
- 原意确实含糊时先给有限意图选项；选项覆盖不了真实意思则**先澄清再教学**，不能猜一个意思后纠正

---

## 7. 数据模型

### 7.1 四类数据分层

| 层 | 语义 | 规则 |
| --- | --- | --- |
| 正式事实 | 只追加、可重放 | 唯一权威 |
| Pending 草稿 | 课中恢复所需 | 不是学习事实 |
| 派生投影 | 可重建 | 不得反写事实 |
| 可丢缓存 | 只为加速 | 丢了能从骨架重建 |

### 7.2 `learner/` 数据表

| 表 | 状态 | 关键字段 |
| --- | --- | --- |
| `settings.json` | v3+v4 | `schema_version`、`runtime_protocol_version`、`activation_id`、`catalog_version`、`ladder_version`、`contract_version`、`review_schema_version`、`training_sessions_per_cycle: 6`、`recovery_gap_days: 7` |
| `plan-items.tsv` | **权威队列** | 11 列（v4 新增 `focus_goal_id`、`plan_role ∈ {focus, maintenance, cycle_review}`） |
| `plan-events.tsv` | v3 保留 | `event_id`、`occurred_at`、`study_date`、`plan_item_id`、`event`、`reason` |
| `skill-evidence.tsv` | 已扩列 | **65 列**：v3 原 9 列在前，其后 v4 新增 `record_kind`、`observation_id`、`criterion_results_json`、`task_result`、`validity`、`cost_signal`、`support_level/kind`、`model_exposed`、`evidence_mode/kind`、`competency_id`、`activity_family`、`indicator_id`、`anchor_id`、`day_id`、`context_id`、`source_session_outcome` 等 |
| `vocabulary.tsv` / `error-log.tsv` | 保留全部历史 | v4 激活后旧 `level/next_review/last_review` **只作 legacy 审计**，不再是正式排程来源 |
| `review-items.tsv` | **v4 新增** | 21 列，**唯一正式排程表** |
| `review-item-sources.tsv` | **v4 新增** | `review_item_id` ↔ `vocabulary`/`error`/`session` 来源多对多 |
| `review-candidates.tsv` | **v4 新增** | `status ∈ {candidate, observed_only, activated, rejected}` |
| `review-audit.tsv` | **v4 新增** | 26 列；`record_kind ∈ {rating, invalid, void, correction, control}` |
| `review-history.tsv` | v3 保留 11 列 | v4 新事件 `item_type=review_item`；`result` 只存 again/hard/good/easy，invalid/void/control 只在 audit |
| `focus-goals.tsv` | **v4 新增** | `goal_id`、`version`、`supersedes_goal_id`、`success_criteria_json`、`min/max_completed_cycles`、`status ∈ {proposed, active, met, redesigned, superseded, retired}`。**一次只能一个 active** |
| `goal-events.tsv` | **v4 新增** | `decision ∈ {met, continue, redesign, insufficient_evidence}`、`reason`、`evidence_ids_json`、`replacement_goal_id` |
| `competency-status.tsv` | **v4 新增（派生投影）** | `status ∈ {not_evidenced, developing, stable}`、`decisive_event_ids_json`、`flags_json` |
| `competency-events.tsv` | **v4 新增** | `event_type ∈ {developing, stable, watch, confirmation_due, maintenance_due, downgrade, restore, correction, void}` |
| `stage-events.tsv` | **v4 新增** | `stage_attained` 不可删除 |
| `learning-insights.tsv` | **v4 新增** | `insight_type ∈ {bottleneck, support_effect, transfer_pattern, cost_pattern}` |
| `adaptation-state.json` / `long-term-projection.json` | 派生投影 | 每key 至多最近 6 条 primary 摘要 |
| `dashboard.md` / `current-plan.md` | 派生视图 | 带 `<!-- AUTO:* -->` 标记，由 Rebuild 生成 |

### 7.3 `.state/` 运行态

| 文件 | 用途 |
| --- | --- |
| `runtime.json` | 运行时版本指针（**迁移最后写**） |
| `current-session.json` | v4 唯一 pending 权威 |
| `current-cycle-evidence.json` | ≤6 课 × 3 引用、≤12 唯一 primary |
| `bootstrap-index.json` + `.previous.json` | 双代有界index |
| `session-transaction.json` | 8 阶段 WAL |
| `start-transaction.json` / `long-term-transaction.json` / `migration-v4-transaction.json` | 启动/长期/迁移事务 |
| `activity-packages/{plan_item_id}.json` | ready 课包 + `-fallback.json` |
| `classroom-templates/` | 派生课堂模板缓存 |
| `cycle-skeletons/` | 下一轮六个骨架 |
| `cycle-evidence/<cycle>.json` | 上轮短证据归档 |

### 7.4 版本路由规则

读 `settings.json` 与 checkpoint：`schema_version` 缺失或 3 → v3；`= 4` + 激活 receipt 已提交 + session 未冻结旧协议 → v4；**恢复中的 session 始终读 checkpoint 的 `protocol_version`**；迁移未完成或 receipt 未提交 → 保持 v3。**不根据新文件是否存在猜版本。**

---

## 8. 非功能需求

### 8.1 性能

| 指标 | 目标 | 当前基线（用户报告） |
| --- | --- | --- |
| 本地 Bootstrap | ≤ 5 秒 | 263 毫秒（单样本内部计时） |
| 已有上下文开课 | ≤ 25 秒 | **45 秒** |
| 普通正确回答后复习题间 | ≤ 15 秒 | **40 秒** |
| 复习转主课 | ≤ 20 秒 | **85 秒** |
| 新对话首次完整首题 | ≤ 60 秒 | 常超 120 秒 |
| 反馈后 checkpoint 内部 | ≤ 0.5 秒 | — |
| 用户可见阶段切换 | ≤ 10 秒 | — |
| 课末必要事务 + 短projection | ≤ 5 秒（超 10 秒时学员应已看到反馈） | — |
| 外部替代硬截止 | `min(start + 60s, deadline - 20s)` | — |
| **回答 → 反馈的计划内工具/I/O/联网/第二模型** | **0** | — |

> 上述目标是**工程目标，不是已有测试结果**。每类场景尽量收集 ≥10 个样本，报告均值/中位数/最大值/样本量；样本不足须明确说明。

**[缺口]** `model_wait_ms` / `user_visible_wait_ms` **恒为 null**；`performance.*_latency_ms` 多为 0，只有 bootstrap/checkpoint 两处真实赋值。无法获得的指标标未知，**不用零代替**。

### 8.2 可靠性

- 全部写动作经 `Invoke-WithFileLock`（独占 `FileStream` + `FileShare::None`，2 秒超时抛 `State is busy`）
- 幂等 receipts LRU 上限 64 条
- TSV 层`Add-TsvRowsIdempotent` 按 IdColumn 去重，内容不同则 `Idempotency conflict`
- 故障注入点共 **28 个**：StartSession 5、Finalize/Abandon 8、PublishCycle 7、迁移 9（另 `cycle_goals`）
- 状态收敛要求：`Write-DurableJson` 原子替换 + 保留一个校验通过的上一代

### 8.3 可测性

**测试入口**（唯一）：
```powershell
Invoke-Pester -Script tests/tracker.Tests.ps1,tests/tracker-v4.Tests.ps1,tests/backup.Tests.ps1
```

| 文件 | Describe | 源码It 数 | 覆盖 |
| --- | --- | --- | --- |
| `tracker.Tests.ps1` | 4 | 14 | v3 队列：断点续做、长间隔恢复、Due 完整列表、中断对账、上海午夜日期、队列头阻塞、缺 stage 拒绝 finalize、复习批次只写一次、Rebuild 幂等 |
| `tracker-v4.Tests.ps1` | 4 | 30（含 12 处 foreach 展开） | 纯 reducer（review 权重、criterion→task_result、A/B/C 分级、lane 独立性、跨日晋级）+ 幂等重放 + 故障注入参数化用例（StartSession 5 / Finalize 8 / 迁移 9）+ Abandon 范围 + 证据延迟提交 + fallback 强制 training + 未预授权 probe 拒绝 |
| `backup.Tests.ps1` | 1 | 5 | 字节级备份/校验/恢复、拒绝覆盖、损坏前置拒绝、拒绝 `../` 越界、持锁不快照 |
| `classroom-latency.cases.ps1` | 1 | 19 | 逐题持久恢复：同活动修复恢复、重放一次、重试上限、免复习单请求、逐题只保存一次、首次评级冻结、过期 revision/错误题号/隐藏反馈拒绝、泄题延后、legacy 兼容、队首变化、材料失效、弃课保留曝光 |
| `cycle-publication.cases.ps1` | 1 | 2（foreach 展开 7 阶段） | 7 阶段恢复 |
| `goal-review.cases.ps1` | 2 | 7（foreach 展开） | 跨轮 focus 达成判定与伪造拒绝、无确认继续/停滞后重设、不用旧/被支持/作废/重复证据膨胀、legacy 文本契约不臆造标准、反证不复用旧版本 |

**源码字面It 合计 77**；因foreach 参数化，实际执行数高于此值。最近一次记录的回归结果见 `docs/design/classroom-latency-plan.md:220`：**V3/V4 回归合计 71 项通过、0 项失败**（其中新增逐题课堂测试 16 项）。该数字为2026-10-01 实施时的记录，非本次实测。

**注意**：三个 `.cases.ps1` 是通过 dot-source 被 `tracker-v4.Tests.ps1:837-839` 加载的**共享片段**，依赖其定义的 fixture 函数，**不能独立运行**，Pester 默认也不发现它们。v4 测试不使用 `tests/fixtures/tracker-v3/`（仅 10 个文件），而是在 `$TestDrive` 动态合成。

### 8.4 可维护性

- 每个协议文件单一职责；执行规则以 `SKILL.md` + 按需 reference 承载
- 机器可判定的 gate/indicator/anchor 先修关系**只以** `competency-catalog.json` 为事实源；`curriculum.md` 与之冲突时以目录为准
- 难度条件升降只以 `difficulty-ladders.json` 为事实源
- 不引入常驻进程、新数据库、消息队列，或正确性依赖的内存服务

### 8.5 兼容性

- C0003与旧进行中 session 保持 v3 legacy 语义；C0004 门禁通过后原子启用
- **同一 session 不混用版本**；恢复不转换 checkpoint 版本
- v4 激活提交后从主 `SKILL.md` 移除 v3 分支以缩短上下文，保留 v3 schema/protocol 供历史审计
- 新写入格式上线前确认旧代码能否恢复；不能读取时不允许直接回退旧代码处理新草稿

---

## 9. 验收标准

### 9.1 功能完成

- [ ] 严格队首、到期选择、题型、容量、首次评级及学习证据语义**保持不变**
- [ ] 反馈先展示，之后存档；普通文本首答到首次实质反馈之间**零**工具调用、文件读取、联网
- [ ] 每个需存档互动完成后**至多一次**正常保存往返；重试沿用原编号与相同内容
- [ ] 保存确认后才展示下一项需作答任务；保存失败**不要求重答**
- [ ] 相同请求重试不重复记录、不重复推进；相同编号但内容不同应拒绝
- [ ] 主课只有完整契约校验成功才展示；预编译不能绕过运行时保护
- [ ] 课中只写待提交状态，**不提前**改变正式复习日期、强度或长期结论
- [ ] 正式结课依 committed receipt，**不通过**删除必要保护缩短耗时
- [ ] 三个 `.cases.ps1` 的用例随 `tracker-v4.Tests.ps1` 入口执行（源码字面 28 个 It）

### 9.2 数据完整性（**当前不通过，见第 10 节**）

- [ ] `sessions/` 中每个 `plan-items.tsv` 引用的 `completed_session_id` 都存在对应文件
- [ ] `plan-events.tsv` 记录全部队列生命周期事件
- [ ] `learner/summaries/` 覆盖所有已完成月份
- [ ] `dashboard.md` 的到期计数与实测一致
- [ ] `.state/runtime.json` 存在且与 `settings.json` 的 `activation_id` 匹配

### 9.3 性能（**未验收**）

- [ ] 开课 ≤25 秒、复习题间 ≤15 秒、转主课 ≤20 秒，每类 ≥10 样本
- [ ] `model_wait_ms` / `user_visible_wait_ms` 不再恒为 null，或明确标注为平台不可控
- [ ] 新对话首次进入 ≤60 秒，超 120 秒者逐次解释

### 9.4 文档一致性

- [ ] `README.md`「当前收尾状态」的陈述与实测数据一致
- [ ] `README.md`「按问题找文件」表中每份 reference 确实承载所述职责
- [ ] `AGENTS.md` 状态路由与 `SKILL.md` 教学分支表无冲突

---

## 10. 已知缺口与风险（实测结论）

### 10.1 数据完整性缺口（最高优先级）

| # | 缺口 | 证据 |
| --- | --- | --- |
| **D1** | **14 个悬空 session_id**：`plan-items.tsv` 引用 S20260818-01、S20260830-01、S20260901-01、S20260903-01、S20260906-01/-02、S20260907-01（v3 格式）+ S20260913 ~ S20260930 共 12 个（v4 格式），但 `sessions/` 只有 07 月 9 个 + 08 月 5 个，**无 09 月目录** | `plan-items.tsv:16-36` vs `sessions/2026/` |
| **D2** | **`.state/` 整体不存在**：`runtime.json`、`current-session.json`、索引、课包、WAL 全部缺失，但 `settings.json` 声明 `schema_version: 4` + `activation_id: M4-43904e5a67cd1acd6b5a8c56` | `Glob .state/**` 无结果 |
| **D3** | **v4 正式表全部未落盘**：`review-items.tsv`、`review-item-sources.tsv`、`review-candidates.tsv`、`review-audit.tsv`、`focus-goals.tsv`、`goal-events.tsv`、`competency-status.tsv`、`competency-events.tsv`、`stage-events.tsv`、`learning-insights.tsv` 均不存在 | `Glob learner/**` |
| **D4** | **`plan-events.tsv` 为空**（仅表头 0 数据行），v4 生命周期事件流从未写入 | `plan-events.tsv:1` |
| **D5** | **8 月 / 9 月 summaries 缺失**，仅 `summaries/2026-07.md` | `Glob learner/summaries/**` |
| **D6** | **dashboard 陈旧**：显示"到期词汇 43 / 到期错误 41"，实测 47 / 46；"当前轮次 C0003 已完成 7 共 7"，实际 C0004 已完成、C0005 完成 3/7 | `dashboard.md:14,17,18` |
| **D7** | **`current-plan.md` 只渲染 C0003**，滞后两个轮次 | `current-plan.md:9-21` |
| **D8** | **混合代数据**：`skill-evidence.tsv` 96 条 v3 格式 + 10 条 v4 格式；`review-history.tsv` 163 条 v3 + 24 条 v4（`RI-LEG-*`） | 两表line 98-107 / 164-187 |

> **风险**：`learner/`、`sessions/`、`.state/` 三者均在 `.gitignore` 中。`.state/` 缺失 + `backup-guide.md:15` 明说"项目目前没有完整的一键重建全部状态流程" → **当前状态无法从 Git 恢复**。D1–D8 需在继续上课前确认是否可从 `backups/` 的 ZIP 恢复。

### 10.2 功能缺口

| # | 缺口 | 位置 |
| --- | --- | --- |
| F1 | **competency / stage 长期 reducer 无调用方**，返回硬编码空数组 | `session-runtime.ps1:606` |
| F2 | **progress marker 只实现 1/3**（仅 `criterion_acquired`），`support_withdrawal` / `context_transfer` 标注待扩展 | `goal-review.md:23` |
| F3 | **learning insight 全流程未接线**（状态机、反例降级、directive 编译） | `reducers.ps1` 无调用方 |
| F4 | **课包生命周期 5 态只落地 `ready`**，无自动构建器与失效矩阵 | 见 FR-8 |
| F5 | **owner token 无 TTL / 无抢占** | `session-runtime.ps1:759` |
| F6 | **提示阶梯 3 级设计 → 实现 2 级** | `classroom-runtime.ps1:52` |
| F7 | **adapter 7 种仅 1 种显式映射**，其余靠自由文本 | `classroom-runtime.ps1:43` |
| F8 | **迁移硬编码** C0003→C0004 与四个版本号 | `migration-runtime.ps1:151-152,211-215` |
| F9 | **v4 无 Rebuild / CancelPlanItem / MonthlySummary / QuarterlySummary 实现**，v4 指针存在时直接抛错 | `tracker.ps1:65-67` |
| F10 | **`review_batch_refs` 从不写入**，循环复盘包里恒空 | `session-runtime.ps1:383` |
| F11 | **`Get-PracticalGoalDecision` 的 Markers/Streak 分支几乎不可达** | `session-runtime.ps1:557-583` |
| F12 | **审计重放未实现**：`evidence_audit_required` 会暂停 met 判定但不自动重放改正 | `goal-review.md:16` |
| F13 | **复盘包遇 correction/void 直接抛错**，而非降级处理 | `session-runtime.ps1:466` |
| F14 | **`post_activation_maintenance` 无执行代码** | `migration-runtime.ps1:421` |

### 10.3 风险

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| **R1** `.state/` 缺失且不可重建 | 无法继续上课；无 pending 事务、无课包、无运行版本 | 从 `backups/` ZIP 恢复到新目录验证；若无可用备份，需评估是否需重建 index/课包骨架 |
| **R2** 14 个悬空 session_id | C0003 后半 + C0004 全部 + C0005 前 3 项的课次记录缺失，约占总课次一半 | 确认是否存在于 `backups/`；否则需明确标记为数据缺口而非补造 |
| **R3** 性能目标从未实测 | 用户报告基线（45/40/85 秒）远高于目标（25/15/20） | 下次课堂按 `classroom-latency-plan.md` §2 口径收集数据 |
| **R4** v3 死代码随 skill 分发 | `tracker-v2-legacy.ps1` + `tracker.ps1` 的 v3 分支增加维护面与误用风险 | v4 激活提交后按 `AGENTS.md:26` 移除 v3 分支 |
| **R5** 测试入口单一耦合 | 三个 `.cases.ps1` 无法被 Pester 默认发现，漏跑则其 28 个 It 静默失效 | 在 README 与 CI 中显式标注 dot-source 关系 |

---

## 11. 里程碑与后续

### M0：数据可恢复性（**阻塞一切**）

-确认并恢复 `.state/`（含 `runtime.json`、索引、课包）
- 核对14 个悬空 session_id 与 `backups/` 的一致性
- 补齐 `plan-events.tsv`、8/9 月 summaries
- 重建 `dashboard.md` / `current-plan.md` 派生视图

**验收**：9.2 全部勾选，且 `Bootstrap` 在恢复目录返回正确的版本、队首、等待动作。

### M1：长期状态接线

- 接入 `Get-CompetencyCandidate` / `Get-StageAttainmentCandidates`（F1）
- 补齐 `support_withdrawal` / `context_transfer` 两个 progress marker（F2）
- 打通 `competency-events.tsv` / `stage-events.tsv` 事件写入与投影重算
- 修复 `Markers`/`Streak` 分支不可达问题（F11）

**验收**：某技能连续达标后，`stable` 与 `stage_attained` 事件真实落盘，且不依赖时间或轮数自动晋级。

### M2：课包生命周期

- 实现 `skeleton → provisional → ready → prepared → consumed` 状态机（F4）
- 实现失效矩阵与自动构建器
- 启用 `compatible_previous` 分支（当前为死代码）

**验收**：材料、ladder、policy、contract 任一版本变化时，课包按矩阵精确重绑或硬拒绝，而非全量重建。

### M3：课堂性能验收

- 按 `classroom-latency-plan.md` §2 口径实测三类等待，每类 ≥10 样本
- 补齐 `model_wait_ms` / `user_visible_wait_ms` 或明确标注不可控边界
- 明确提示阶梯 3 级与 adapter 7 种映射（补F6/F7）

**验收**：9.3 全部勾选，或明确报告残余瓶颈在平台/模型而非脚本。

### M4：提示阶梯与 adapter 完整化

- 提示阶梯补至3 级
- 7 种 adapter 全部显式映射到 `activity_family` / `issue_type`
- 审计重放自动化（F12）
- 复盘包遇 correction/void 改为降级处理（F13）

---

## 12. 附录

### 12.1 tracker 动作清单（25 个）

**v4 专属动作（9）**：`PrepareActivity`、`PrepareReviewQuestions`、`SaveReviewAnswer`、`SaveActivityCheckpoint`、`StageReviewBatch`、`EvaluateLongTermState`、`PublishCycle`、`MigrationPlan`、`ActivateV4`

**v4 共享动作（9）**：`Bootstrap`、`StartSession`、`FinalizeSession`、`AbandonSession`、`Validate`、`Due`、`Review`、`Summary`、`ReviewBatch`

**v3 legacy 专属动作（7）**：`Checkpoint`、`CloseCheckpoint`、`AbandonCheckpoint`、`CancelPlanItem`、`Rebuild`、`MonthlySummary`、`QuarterlySummary`

> `Due` / `Review` / `ReviewBatch` / `Summary` 在 `tracker.ps1:65-67` 的 v3 分支仍有实现，但 v4 指针存在时 v4 专属动作的 Rebuild / CancelPlanItem / MonthlySummary / QuarterlySummary 会直接抛错（见 F9）。

### 12.2 关键 reason_code

| reason_code | 含义 |
| --- | --- |
| `queue_guard_mismatch` | 队列头/版本/课包哈希与 index 不符，拒绝正式取证 |
| `idempotent_replay` | 同 key 同 payload，返回原 receipt |
| `Idempotency conflict` | 同 key 异 payload，拒绝 |
| `State is busy` | 文件锁 2 秒超时 |
| `rebuild_required` | 派生视图损坏，需重建（不回滚课程） |
| `preload_pending` | 下一队首课包构建失败（不回滚本课） |
| `evidence_audit_required` | 相关 correction/void 使候选需审计，审计前不宣告 met |
| `recovery_uncertain` | 极小窗口中断无法可靠恢复已生成反馈 |
| `Frozen package changed` | 课中课包被改动 |

### 12.3 能力目录速查（15 family / 45 gate / 90 indicator）

| 技能 | family | A2 Required | B1 Required | B2 Required |
| --- | --- | --- | --- | --- |
| 听力 | `L_INTERACTION`、`L_ACTION_INFO`、`L_EXTENDED` | 2 | 3 | 2 |
| 口语 | `S_TRANSACTION`、`S_CONVERSATION`、`S_EXPLAIN`、`S_ARGUMENT` | 2 | 4 | 3 |
| 阅读 | `R_FUNCTIONAL`、`R_NARRATIVE`、`R_EXPOSITORY`、`R_ARGUMENT` | 1 | 3 | 2 |
| 写作 | `W_TRANSACTION`、`W_EXPLAIN`、`W_ARGUMENT`、`W_MEDIATE` | 1 | 3 | 4 |

**角色分布**：R（required）30 · B（breadth）11 · E（extension）4 = 45 gate，合计 90 个 observable indicator。
**难度维度**：9 个 × 4 步= 36 步；15 条 family 绑定。

### 12.4 相关文件索引

| 主题 | 文件 |
| --- | --- |
| Agent 路由与边界 | `AGENTS.md` |
| 维护约束 | `MAINTENANCE.md` |
| 人类阅读入口 | `README.md` |
| 教练入口与教学分支 | `.agents/skills/english-coach/SKILL.md` |
| 逐题课堂协议 | `references/classroom-flow.md` |
| 任务契约 / 评分标准 | `references/task-contracts.md`、`references/rubrics.md` |
| 纠错微循环 | `references/teaching-loop.md` |
| 复习出题与评级 | `references/review-teaching.md`、`references/review-protocol.md` |
| 排程与长期状态 | `references/long-term-state.md`、`references/goal-review.md`、`references/cycle-publication.md` |
| 能力地图与课程结构 | `references/curriculum.md`、`references/competency-catalog.json`、`references/difficulty-ladders.json` |
| 材料政策 | `references/resource-policy.md`、`assets/fallback/manifest.json` |
| 数据 schema | `references/data-schema.md`、`data-schema-v4.md`、`data-schema-v3.md` |
| 运行协议 | `references/runtime-protocol-v4.md`、`runtime-protocol-v3.md` |
| 设计依据（含未实现设想） | `docs/design/learning-system-plan.md` |
| 提速方案与实施结果 | `docs/design/classroom-latency-plan.md` |
| 备份恢复 | `maintenance/backup-guide.md` |
| 测试 | `tests/tracker.Tests.ps1`、`tracker-v4.Tests.ps1`、`backup.Tests.ps1` + 3 个 `.cases.ps1` |
