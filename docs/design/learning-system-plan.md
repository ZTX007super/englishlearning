# English Coach 改进建议

> 设计依据：原文件名为 `english-coach-improvements.md`。这里保留完整讨论结论，其中部分仍未实现；当前功能范围与阅读入口见 [项目 README](../../README.md)，执行规则以 [SKILL.md](../../.agents/skills/english-coach/SKILL.md) 及其按需协议为准。

## 已达成共识

### 1. 建立能力门槛驱动的长期—阶段—焦点—轮次目标体系

#### 修改前的问题具体体现

- `curriculum.md` 当前用“第 2–12 轮、第 13–24 轮”等轮数划分阶段。项目虽然不绑定自然周，但只要完成指定轮数就会在形式上进入下一阶段，阶段推进尚未由能力证据决定。
- 听、说、读、写共用一个“当前阶段”，无法准确表达偏科状态。弱项可能被平均表现掩盖，强项也可能被整体阶段限制在过低难度。
- `current-plan.md` 只有一条自然语言“本轮目标”，没有结构化事实来源，无法稳定追踪一个目标已经持续几轮、为何被选择、经过哪些复盘或是否重新设计。
- 原方案把可衡量目标放在每一节课，并准备在课末判断 `met / partial / not_met`。这容易把一次当堂表现误认为长期能力，也把每日教学任务和中期学习目标混为一谈。
- “选择分数最低的技能”容易受偶然失误或证据不足影响；“未达成就原样继续”又可能让无效训练连续重复。
- 固定的听说读写排课不能充分响应当前瓶颈；完全围绕弱项排课则可能使其他能力长期缺乏维护。
- 当前数据结构没有把阶段能力、焦点目标、轮次计划和单课证据连起来，脚本也无法检查这些关系。

#### 修改后预期执行时实现的具体效果

- `curriculum.md` 成为全年能力地图。阶段保留“基础、B1/B2 过渡、TOEFL 应用、综合稳定”的教学方向，但取消按日期或轮数晋级，改由听、说、读、写各自的能力门槛决定。
- 学习者分别拥有四项能力状态；整体阶段只描述课程方向。强项可以提前使用下一阶段材料，弱项不会被平均分掩盖。
- 每次轮次复盘根据当前阶段门槛、近期可靠证据、缺口大小和长期影响，提出一个具体的“最高优先级缺口”作为焦点目标，并同时给出依据和一个备选目标，由用户确认。
- 焦点目标预计持续 2–4 个完成轮次，而不是 14–28 个自然日。每完成 6 次训练后进行一次正式判断；自然时间只用于提醒、学习量观察和中断恢复。
- 轮次判断使用 `met / continue / redesign / insufficient_evidence`：达标后更换目标；有明确进步时继续；证据不足时不误判能力；连续两次没有有效进步或达到第 4 轮仍未达标时，必须拆小目标、补先修能力或更换训练方法，不能原样无限延长。
- 下一轮 6 次训练按焦点动态分配：焦点能力作为 2–4 课的主技能，默认 3 课；每项听说读写每轮至少产生一次可评分证据，任一非焦点能力在连续两轮内至少一次成为课程主技能。
- 单课仍有可观察的证据任务，用于组织教学和支持中期判断，但不再把单课结果当作长期目标达标结论。焦点课的证据关联当前目标，维护课的证据用于相应阶段能力。
- 日课四阶段中的到期复习保持独立：焦点目标不能改变其到期时间、抽取内容、顺序或配额；复习结果可以作为延迟证据反哺能力判断，但复习不计入新训练的技能占比。
- 焦点目标和技能占比只在轮次复盘时正式调整。轮次中可以调整当前课程的材料难度、提示量和活动形式，但除非用户明确要求或计划项客观无法执行，不重排严格队列。

#### 建议如何修改

1. 重写 `.agents/skills/english-coach/references/curriculum.md`：
   - 为四个教学阶段设置稳定的 `stage_id`，删除轮数范围和按时间晋级规则。
   - 每个阶段按听、说、读、写列出带 `competency_id` 的可观察能力和必要先修能力。
   - 每项能力使用 `not_evidenced / developing / stable` 状态；所有当前阶段核心门槛稳定后，整体阶段才标记完成。
   - 允许已领先的单项使用下一阶段材料；TOEFL 题型可以早期少量熟悉，正式提速和提分训练仍受相关先修能力约束。
2. 新增 `learner/competency-status.tsv`，作为个人分项能力状态的事实来源。至少记录 `competency_id`、`stage_id`、`skill`、`status`、支撑证据和最近更新时间。
3. 新增 `learner/focus-goals.tsv`，记录 `goal_id`、关联阶段与能力、具体目标、成功标准、最少/最多轮次、开始轮次、状态、版本关系和结束轮次。
4. 新增只追加的 `learner/goal-events.tsv`，记录每轮复盘产生的 `met / continue / redesign / insufficient_evidence` 决定、原因和引用证据，保留目标演变历史。
5. 在 `learner/plan-items.tsv` 增加 `focus_goal_id` 和 `plan_role`。`plan_role` 至少支持 `focus / maintenance / cycle_review`；维护课的 `focus_goal_id` 可以为空。
6. 在 `learner/skill-evidence.tsv` 增加 `competency_id` 和可为空的 `focus_goal_id`。焦点课证据必须关联活跃目标；维护证据只关联相应阶段能力，不伪装成焦点目标证据。
7. 更新 `SKILL.md`、`references/data-schema.md`、日课模板和轮次复盘模板，明确以下层级及边界：
   - curriculum stage：长期能力地图；
   - focus goal：持续 2–4 轮的当前瓶颈；
   - cycle plan：下一轮 6 次训练的动态分配；
   - session evidence task：只采集表现，不逐日宣告长期掌握；
   - due review：独立调度的复习通道。
8. 将焦点选择规则写成可执行流程：只考虑当前阶段未稳定且具有足够近期证据的能力，综合门槛差距、重复程度、对其他能力的阻塞作用和长期目标价值；AI在轮次复盘中给出首选、证据、理由和备选，由用户确认后写入计划。
9. 将焦点目标生命周期写成强制规则：默认观察窗口为 2–4 个完成轮次；每轮必须写入一次决定；连续两次没有有效进步或第 4 轮仍未达标时必须创建新版本并 `redesign`，不能机械续期。
10. 将动态分配规则写入轮次计划生成与校验逻辑：焦点能力每轮占 2–4 个主技能位置，默认 3 个；每项技能每轮至少一条可评分证据；非焦点能力在滚动两轮内至少一次作为主技能。到期复习不参与该计数。
11. 扩展 `tracker.ps1`：
    - `Bootstrap` 返回分项能力状态、活跃焦点目标、当前计划项角色及相关历史决定。
    - 普通训练课的 `FinalizeSession` 只检查本课至少存在一条结构化证据；焦点课还要检查证据是否关联活跃目标，但不要求本课表现必须成功。
    - 轮次复盘的 `FinalizeSession` 检查是否写入焦点目标决定。
    - `Validate` 检查目标、能力、证据和计划项引用，检查焦点分配与技能维护底线，同时保证这些规则不改变严格队列。
12. 焦点目标和技能占比只允许在轮次复盘中改变。轮次内只允许调整当前课的难度、支架和活动；特殊情况下修改尚未开始的计划项时，必须得到用户要求或记录客观不可执行原因，并保存变更事件。
13. 采用非追溯迁移：C0003 按现有队列完成，不修改已完成或待开始项目，也不给历史证据补造目标关系。无法可靠判断的新字段写为空或 `unknown`；在 C0003 轮次复盘中初始化分项状态和首个正式焦点目标，从 C0004 起完整启用新体系。
14. 增加迁移和行为测试，至少验证：阶段不会因日期或轮数自动推进；强项可以使用更高阶段材料；普通课有证据但不产生每日掌握结论；焦点目标不会改变到期复习；动态分配满足维护底线；目标调整不会跳过或重排严格队列。
15. 第一条只建立目标体系、数据关系和最低校验。任务契约、提示依赖与分型纠错已经由第2条确定；固定复习形式、原子项目的长期掌握标准和复习证据边界已经由第3条确定；难度变化下的证据可比性已经由第4条确定，`met`、`stable` 和“明显进步”的精确判据已经由第5条确定。各条通过边界说明和数据引用保持联动。

### 2. 用任务契约、确定性仲裁和分型微循环稳定纠错，并保留提示依赖

> **与其他条目的边界：** 本条使用第1条提供的能力与焦点目标，但不定义长期 `met / stable` 门槛。日课 `review` 阶段的固定形式、题型、评分映射和原子掌握标准已经由第3条确定；已到期的复习内容、顺序和形式不因本课焦点或本条纠错协议而改变。本条只确定主线教学的低延迟边界和需要恢复的数据语义；预加载、缓存、批量持久化、轻量检查点及故障恢复的具体实现见第6条。

#### 修改前的问题具体体现

- 当前技能只规定 `review → input → output → feedback` 四个大阶段，没有为一次可评分活动预先声明“究竟在测什么、什么算通过、允许多少准备或重放、何时纠错”。AI可能看完用户回答后临时增加标准。
- 旧方案把 `task_target_failed`、`target_error`、`recurrent_high_value_error` 和 `incidental_slip` 当作互斥类型，但它们分别描述任务结果、与目标的关系、历史复发性和严重程度，同一问题可能同时命中多类，无法稳定四选一。
- 核心理解错误、表达没有完成任务、影响意思的语言错误、偶发小错和“正确但可以更自然”的表达升级尚未严格分开。简单但正确的回答可能被AI误判为失败。
- 多个问题同时出现时缺少确定的归因与取舍顺序。AI可能按表面错误数量逐项追打，也可能重复处理同一根因造成的不同症状。
- 不同问题共用一个笼统的“讲解—提示—重试—迁移”流程；理解、事实定位、组织、语法、搭配、语用和发音所需的修复动作并不相同。
- 所有小错都启动完整循环会拖慢30分钟课程并打断连续表达；只处理一个问题又可能漏掉同一回答中另外两个真正重要的问题。当前没有同时限制“反馈主题总数”和“完整循环复杂度”。
- “即时纠错”可能污染诊断或测评的无提示证据；“等输出结束再反馈”又不适合某些以准确度纠错为核心的练习。纠错时机尚未由活动用途与模式共同决定。
- `raw / revised` 只能区分修改前后，不能说明用户依靠了哪种提示、是否看过示范、哪个标准受到答案暴露影响，也不能区分当堂引导成功与换题迁移成功。
- 若永久保存每个小错、每次中间失败和全部提示，长期数据会迅速膨胀；若只保存大阶段，又无法在中断后恢复到正在等待的澄清、原句修复或迁移步骤。
- 复杂规则如果要求回答后再扫描历史、读取多份模板、联网或逐条写证据，会让用户等待。教学判定规则与后台持久化之间缺少明确的关键路径边界。

#### 修改后预期执行时实现的具体效果

- 每个可评分活动在出题前冻结一份最多三个标准的任务契约；AI按事先声明的构念和条件判定，不能因看到回答而改变门槛。
- 判定改为正交结构：分别记录任务结果、每条标准结果和可并存的多个问题。技术故障、指令歧义或证据不足使用 `not_assessable`，不算作用户答错。
- “错误”和 `upgrade_opportunity` 分开。正确但简单的英语仍可使任务成功；表达升级只有在确有教学价值时才参与排序，不能把答案降级为失败。
- AI先保全独立作答，再合并同根问题、寻找上游原因并按固定优先级选择。一次回答最多处理三个反馈主题，不凭临场偏好随机挑错。
- 每节30分钟课程允许 `0–3` 个完整微循环，不为凑数制造问题；同时使用总复杂度预算，既允许三个局部问题，也防止多个全局问题吞掉课程。
- 所有循环共享一个稳定骨架，但根据问题机制调用七种不同适配器。Teach-back 只证明规则或概念理解，语言能力仍须由实际产出和新情境迁移验证。
- 第一条反馈消息一次给齐任务／焦点结果、选中的问题、最小解释和原表达修复要求；用户完成修复后，才单独给出新活动或新语境迁移，避免一条消息同时塞入两轮作答。
- `probe / assessment` 优先保存完整无提示表现；流利度活动等整段输出结束后反馈；准确度练习在不破坏独立证据的前提下可以即时纠正。
- 系统能区分无提示、轻提示、明显支架和完整示范，并把答案暴露限制到具体 `criterion_id / loop_id`；看过某处示范不会污染活动中的所有其他能力，但原题不能重新变成独立证据。
- 临时活动状态、长期能力证据和会话／错误日志各自只保存需要的信息。偶发小错不自动进入长期记录，换题迁移使用新的 `activity_id`。
- 普通文本回答后的任务判断、问题仲裁和教学反馈在一次模型响应内完成；计划内不先调用工具、扫全库、联网、重建或完整验证。用户先看到教学反馈，归档和重计算后置。

#### 建议如何修改

1. 新建 `references/task-contracts.md`，只为“会产生评分或能力证据”的活动实例化任务契约。普通澄清、提示和原句修复沿用父活动的 `activity_id`，用 `loop_id` 区分；真正的新题或新语境迁移必须创建新的 `activity_id`。契约至少包含：
   - `activity_id`
   - `activity_family`
   - `modality`
   - `purpose: practice | probe | transfer | assessment`
   - `mode: accuracy | fluency | mixed`
   - `primary_construct`
   - 最多三条 `criteria`，每条标记为 `essential` 或 `required`
   - 内部判定依据、可接受答案或语义范围
   - 正常允许的准备、回看、重放和参考条件
   - `correction_timing`
   - 预选适配器与提示阶梯
   - `transfer_rule`
   - 剩余复杂度预算

   契约必须在题目呈现前冻结；AI可以判断同义表达是否符合原标准，但不能看完回答后新增成功条件。
2. 采用统一的任务结果算法，并逐条保留标准结果：
   - 因技术故障、指令含糊或证据不足而无法公平判断时，`task_result = not_assessable`。
   - 任一 `essential` 标准未满足时，`task_result = failed`。
   - 所有 `essential` 均满足、但至少一个 `required` 未满足时，`task_result = partial`。
   - 所有标准均满足时，`task_result = success`。
   - 每个标准另记 `criterion_result: met | partial | not_met | not_observed`；若上游失败使某标准没有被公平观察，使用 `not_observed`，不能伪记为 `not_met`。
   - 普通语言错误只有在它属于预声明标准或已经阻断／改变意义时才影响任务结果。任务整体可以成功，而当前焦点标准仍为 `partial` 或 `not_met`。
3. 在任务契约中定义八个稳定活动族；TOEFL任务先映射到这些活动族，再叠加限时、材料使用和评分要求，而不是另建一套冲突的判断逻辑：
   - `source_comprehension`：阅读或听力的主旨、事实、态度、指代、意图及关系理解。核心命题相反、关键事实／关系错误或答案无关可构成失败；回答中的非阻断语法错误不使理解任务失败。
   - `retell_summary`：保留预先声明的核心意义单元。中心意思遗漏或反转、因果或人物关系失真／编造可构成失败；未照搬原文措辞不算失败。
   - `opinion_explanation`：完成直接回应、明确立场和所需理由／例子。未回答、立场不可辨或意义无法恢复可构成失败；语言简单但完成要求仍可成功。
   - `interaction_roleplay`：完成请求、确认、澄清、拒绝等预声明交际动作。交际目的未实现或对话无法继续可构成失败；自然度与礼貌只在它们是契约标准时影响结果。
   - `integrated_response`：忠实整合两个及以上来源或材料与观点。歪曲来源、遗漏必需的来源关系或把材料立场说反可构成失败。
   - `controlled_form`：选择、转换或产出指定语法、词义、搭配或句式。目标形式或意义错误直接影响任务结果；与目标无关且不改变答案的小错不影响结果。
   - `extended_writing`：完成预声明的体裁、受众、目的、核心内容及来源要求。跑题、核心信息缺失或中心意思不可理解可构成失败；局部语言质量另按标准与问题记录判断。
   - `oral_imitation`：复现规定内容并保持可懂度。内容严重遗漏或无法辨认可构成失败；只有存在可靠音频证据时才能判断发音特征，否则相应标准为 `not_assessable`。
4. 在 `references/teaching-loop.md` 将旧的互斥四分类替换为正交记录。一个回答可以包含多个 `issues[]`；每项至少记录 `issue_id`、`issue_type`、`affected_criterion`、`focus_relation`、`impact`、`root_cause`、`recurrence_evidence_ids` 以及 `nature: error | upgrade_opportunity`。其中：
   - `upgrade_opportunity` 表示原表达正确但存在确有价值的精确度、搭配、语域或句式提升，不是错误，也不能改变已经成功的 `task_result`。
   - “复发”必须引用 `error-log.tsv`、活跃洞察或既有证据 ID；没有结构化证据时只能记为本次新发现，不能依赖AI印象。
   - 偶发且不影响理解、目标或迁移价值的小错默认为 `incidental_slip`，不进入完整循环，也不自动进入错误日志。
5. 把多问题处理写成确定性仲裁算法：
   1. 先保存完整、无提示的原始作答。
   2. 合并由同一根因造成的多个表面问题；同一问题即使拥有多个标签，也只处理一次。
   3. 优先修复上游原因，避免把它导致的下游表现再次计错。
   4. 对仍然独立的问题按以下顺序排序：沟通阻断；造成 `essential` 失败的根因；改变或严重模糊意义；命中已声明活动标准；命中当前焦点目标；有结构化复发证据或高迁移价值；`upgrade_opportunity`；偶发小错。
   5. `partial` 先获得一次只针对缺失部分的最小补全机会；补全后记为受提示完成，仍无法完成时才与其他问题一起参加循环选择。
   6. 若存在两个独立的核心失败，说明任务负荷或先修能力有问题，应缩小任务或补先修项，不并行展开两个全局循环。
   7. 最终最多选择三个反馈主题，并记录选择或推迟原因；未选中的偶发小错直接忽略。

6. 固定一轮互动的呈现顺序，采用“两段式反馈”：
   - 第一条反馈消息一次完成任务／焦点结果说明、选中的 `1–3` 个教学问题、必要的意义选项或最小解释、不进入完整循环的简短反馈，并要求学习者集中修复原表达或原任务中的受影响部分。
   - 用户完成原表达修复后，才单独给出新活动或新语境迁移；不能把修复要求和迁移题同时塞进第一条消息。
   - 如果学习者原意确实含糊，先给有限的意图选项；若这些选项仍覆盖不了真实意思，必须先澄清再教学，不能猜一个意思后纠正。
7. 为30分钟日课设置双重预算，而不是固定“永远只做一个循环”：
   - 每课允许 `0–3` 个完整微循环；没有高价值问题时为 `0`，不能为凑数虚构错误。
   - 总复杂度预算为 `3`。局部语法、单个词／搭配、局部自然度和单一发音特征各计 `1`；核心理解、任务对齐、篇章组织或交际动作失败等全局问题计 `2`。
   - 每课最多一个全局循环，因此合法组合最多为三个局部循环，或一个全局循环加一个局部循环。
   - 反馈主题总数也不得超过三个。若三个主题都进入完整循环，就不能再附送额外小错；未进入循环的主题只做简短、可一次读完的反馈。
   - 若活动本身就是准确度或纠错训练，微循环属于主活动而非附带打断，但仍受重试上限、复杂度预算和总课程时间限制。
8. 所有问题共用一个状态骨架：

   `独立探测 → 按冻结契约判定 → 归因、合并与排序 → 最少必要帮助 → 修复受影响功能 → 淡出帮助 → 新活动／新语境迁移 → 停止并记录`

   中间教学动作按问题机制调用七种适配器：
   - **意义理解：** 定位文本或音频证据 → 对比可能解释 → 学习者用自己的话复述并指出依据 → 使用一段新的短材料验证。
   - **事实定位：** 明确要寻找的信息槽位 → 提取搜索锚点 → 定位对应句子或音频片段 → 在同类新材料中寻找另一事实。
   - **内容／篇章组织：** 找出缺失的逻辑槽位 → 只给 `2–3` 个关键词或结构框架，不给完整范文 → 重组受影响内容 → 换题且撤去提纲。
   - **语法形式：** 指出出错位置 → 先诱导自我修正 → 必要时给最小规则或对比例 → 改变主语、时间或语境造一个新句。
   - **词汇／搭配／语域：** 先确认想表达的意思 → 区分语义错误、搭配问题和可选升级 → 最多比较两个候选表达 → 在个人化的新语境中使用。
   - **语用／互动：** 指出尚未实现的交际效果 → 给少量功能性表达选择 → 重演关键回合 → 换一个场景完成同类交际动作。
   - **发音可懂度：** 仅在有可靠音频时启用 → 每次只处理一个影响可懂度的特征 → 先感知／听示范，再练词组 → 在新短句中验证；没有可靠音频时记为 `not_assessable`。

   Teach-back 只可检查规则或概念是否理解，不能代替词汇、语法、口语、写作或交际能力的实际迁移证据；“更高级”也不天然等于更好，升级必须服从原意、语境和当前目标。
9. 统一帮助升级和停止规则：
   - 从不泄露答案的最小提示开始，同一问题最多进行两次递增帮助的重试。
   - 两次后仍不会时，给完成当前理解所必需的示范，再把迁移任务简化；若简化迁移仍失败，记录缺失的先修项并结束，不无限追问。
   - 最高提示等级和帮助类型取实际使用过的最高值，不能因最后答对而重置。
   - 建议时长为：局部语法／词汇约 `2–3` 分钟；意义、事实、语用或发音约 `2–4` 分钟；组织问题约 `4–6` 分钟。分钟数只用于节奏提醒，真正硬限制是重试次数、复杂度预算和30分钟总时长。
   - `output + feedback` 合计约15分钟，并优先保护一次完整的独立原始输出。若时间不足以完成迁移，只能记录为 `guided`，明确把迁移留到后续活动，不能假装循环已经完成或能力已掌握。
10. 由活动用途和模式共同决定纠错时机：
    - `probe / assessment` 必须先保全预定的完整独立表现，再给反馈；只有技术故障、指令问题或真正的沟通阻断可以提前中止，此时相应结果为 `not_assessable`，而非学习者失败。
    - `practice + accuracy` 可以在每个独立小题完成后立即纠正。
    - `fluency` 必须等连续口语、复述、角色扮演或自由写作的完整输出结束后统一反馈，小语法错不得中途打断。
    - `mixed` 先判断内容和任务完成度，再在输出结束后处理语言形式。
    - 独立且明确正确时直接前进；只有用户表示不确定、答案明显可能来自猜测，或契约要求迁移验证时，才增加一次辨析或换语境检查。

11. 在 `SKILL.md` 保留一段短而强制的运行协议：可评分活动先冻结任务契约；回答后一次完成判定、归因、仲裁和反馈生成；流利度输出不被小错打断；始终从最少帮助开始；严格执行主题、复杂度与重试上限；原表达修复完成后才给迁移。`SKILL.md` 还必须明确何时读取 `task-contracts.md` 和 `teaching-loop.md`，不能只把规则写进为防激活而改名的 `ai.md`。
12. 在 `references/rubrics.md` 定义统一的支持强度与支持类型：
    - `support_level: none | light_hint | heavy_hint | model`
    - `support_kind` 用于区分重放／回看、定位提示、关键词、规则提示、句架、选项、示范等实际帮助。

    正常契约内允许的准备时间、回看或重放不自动算提示；超出契约后才记录为支持。评分必须保留每个标准或循环实际依赖的最高支持，不能只看最后一次答案是否正确。
13. 扩展 `learner/skill-evidence.tsv` 和 `references/data-schema.md`，在第1条已有的 `competency_id / focus_goal_id` 之外增加 `activity_id`、可为空的 `criterion_id`、`loop_id`、`attempt_no`、`task_result`、`criterion_result`、`support_level`、`support_kind`、`model_exposed` 和 `evidence_kind`。长期只保存：
    - 反馈前的完整 `probe` 原始表现；
    - 被选中问题的最终 `guided` 结果；
    - 使用新 `activity_id` 的新活动／新语境 `transfer`；
    - 对应的任务／标准结果、最高帮助和按 `criterion_id / loop_id` 限定的示范暴露。

    同一原题看过示范后永久失去该循环或标准的独立性，但不会自动污染活动中未受示范影响的其他标准。新迁移题可以重新从 `support_level = none` 开始。不得把完整提示、所有中间失败和全部小错永久写入证据表。
14. 将当前活动的可恢复状态单独保存在 `.state/current-session.json` 的活动区，至少包含：冻结的任务契约；`task_result` 与各项 `criterion_results`；最多三个被选中问题及选择原因；每个 `loop_id` 的适配器与当前阶段；尝试次数；最高 `support_level` 与 `support_kind`；按标准／循环限定的 `model_exposed`；剩余复杂度预算；原始探测是否已保存；当前等待动作 `clarify | repair | transfer`；以及 `pending_persistence`。恢复后必须继续当时的等待动作，不能重置已经给过的提示或让用户重答已经完成的内容。

    本条只定义逻辑字段和恢复语义，不决定是否沿用当前重量级 `Checkpoint`、何时真正落盘或怎样做到常数工作量；这些实现取舍由第6条规定。
15. 修改 session 模板和 `error-log.tsv` 的写入规则：每课只记录最多三个实际处理的问题、选择原因、最终引导结果、迁移结果和后续动作；未选择的偶发小错不记入长期日志。只有已有复发证据，或本次问题明确值得后续间隔复习时才进入错误日志。课程摘要可以说明“还有问题被推迟”，但不能把未教过的小错伪装成已处理。
16. 为反馈关键路径写入可验证的低延迟边界：
    - 在问题展示前准备一个精简活动包，只含冻结契约及最多三个标准、当前焦点、已选适配器和提示阶梯、最多三条相关复发证据、剩余预算，以及 `1–2` 个不含答案的迁移题壳。
    - 不预加载针对学习者尚未作答内容的实际纠正，也不加载全部历史。
    - 收到普通文本回答后、呈现下一条教学反馈前，计划内工具调用为 `0`；不得读取文件、联网、扫描历史、重建 dashboard、执行完整验证或逐条写入证据。
    - `task_result + criterion_results + issues + 仲裁结果 + 适配器反馈` 在同一次模型响应中联合产生，不能拆成多个隐藏代理或多轮后台自审。
    - 用户可见的反馈和下一学习动作优先，长期归档与重计算后置；保存失败时保留 `pending_persistence`，不能要求用户重答或重复已经收到的提示。
    - 需要转写、播放或分析真实音频的活动是明确例外，但仍应预先说明必要步骤并避免无关的历史扫描或联网重试。
    - 不承诺固定秒数；使用工具调用次数、触及文件集合、事件先后关系，以及历史 session 增长后关键路径操作量是否保持不变来验收。

    第6条负责把这些边界实现为轮次 skeleton、滚动 ready cache、按 action 懒加载、全课统一事务、常数工作量的轻量交互检查点、fallback、失败降级和性能测量；只有包含真实工具启动成本的端到端测试仍不达标时，才把 session-scoped helper 作为以后评估项，不能预设常驻过程。
17. 采用非追溯迁移：旧证据缺少新增字段时填空或 `unknown`，不得反向推断为无提示、未看示范或完成迁移；历史 session 不批量补造 `activity_id / loop_id`。新协议启用后的首个可评分活动开始生成完整契约与证据。
18. 增加确定性的教学行为、数据和性能测试，至少覆盖：
    - 阅读或听力理解正确但英语回答有第三人称单数错误时，主任务仍成功，不重做理解主线。
    - 观点口语结构清楚但有若干用词不当和一句中式英语时，任务可以成功；AI先合并根因并选出最多三个主题，在第一条反馈中给齐最小说明和原表达修复要求，修复后才单独给迁移题。
    - 同一形式在它是已声明标准、当前焦点、有复发证据和偶发小错时按固定优先级走不同分支；表达简单但正确不会因存在高级改写而失败。
    - 两个独立核心失败会触发缩小任务或补先修项，不会并行执行两个全局循环。
    - 每课完整循环数为 `0–3`，复杂度预算不超过 `3`，反馈主题总数不超过三个，且最多一个全局循环。
    - `probe / assessment` 不会被过早反馈污染；流利度输出不会被中途小错打断；准确度练习可按契约即时纠错。
    - AI从最小提示开始，最多两次递增重试；Teach-back 不会被当成语言迁移，看过示范后的原题也不会被记作独立成功。
    - 答案暴露只影响对应 `criterion_id / loop_id`；新 `activity_id` 的迁移按其实际支持重新计分。
    - 时间不足而没有进行迁移时只记录 `guided`，不生成虚假的 transfer 或长期掌握结论。
    - 中断后能恢复到准确活动、循环、尝试、最高提示和待完成动作；持久化失败不会让用户重答。
    - 普通文本回答到下一条反馈之间没有计划内文件读取、联网、全库扫描、重建或完整验证，且历史数据增多不会增加该关键路径的操作集合。

### 3. 用低歧义分阶段复习区分当堂修正与跨日长期掌握

> **与其他条目的边界：** 第1条负责长期能力、焦点目标和复习独立性；第2条负责主线教学中的任务判断、纠错与微循环；本条只定义原子知识的间隔复习、评分、调度和长期保持证据。第4条只能调整主线新材料与新任务的难度，第5条负责将多类证据汇总为焦点目标 `met` 或阶段能力 `stable`，第6条负责预加载、批量落盘和低延迟恢复的实现。焦点目标不得改变已激活复习项的到期时间、抽取内容、题型阶段、顺序或配额。

#### 修改前的问题具体体现

- 当前 `raw / revised` 主要记录同一节课内的前后变化。学习者刚看完纠正后答对，可能只是模仿或短时记忆，却容易被误认为已经长期掌握。
- vocabulary 和 error log 同时承担来源记录与复习排程，存在同一概念重复建档、复合错误无法单独评分，以及单词、搭配与篇章组织等宏观能力混在同一队列中的问题。
- 当前只有 `level 0–5`，同时承担复习间隔和题目难度两种含义；`mastered` 又会停止自动复习，无法表达“已经稳定，但仍需低频维护”。
- `ReviewBatch` 只接收项目和评级，没有规定题型、唯一目标、可接受答案和歧义条件。AI可能在看过答案后临时改变标准，也可能因用户使用另一种正确表达而直接跳过真正需要复习的目标。
- `again / hard / good / easy` 缺少统一锚点。首次独立回答、提示后修复、目标外小错、目标内词形错误、明显笔误、自我修正和不可靠语音转写可能被不同AI作出不同判断。
- 固定项目数上限没有考虑题型耗时；每课新增项目过多、历史项目集中到期和旧数据一次性迁移，都可能让约5分钟的复习持续膨胀。
- 主线输出中的自然使用、用户主动加练、自报“我会了”、暂时跳过、暂停或退役等行为，是否应改变正式日程尚无稳定语义。
- 当前历史不足以追溯“当时问了什么、冻结标准是什么、为何如此评分”；出现歧义或误判时难以复核，同时又不应为了审计永久保存完整私密对话。
- dashboard 容易把原子词汇复习、当堂修复和听说读写宏观能力混为一个“掌握率”，无法区分延迟提取、换语境迁移和真正的综合能力。

#### 修改后预期执行时实现的具体效果

- 当堂修复只证明本课反馈有效；跨日首次独立回答才影响正式复习日程，换语境成功与宏观技能探测分别保留独立含义。
- 每个正式复习项只有一个原子目标，并按固定题型从重学、独立提取逐步进入受约束的新语境迁移；难度提高时评分标准不会临时变化。
- AI分开判断“英语整体是否成立”和“指定目标是否被证明”，不会因无关小错把已成功的复习目标判错，也不会把正确同义表达说成坏英语。
- 复习强度与题型阶段分开变化；稳定项目进入最长180天一次的维护，而不是永久消失。反复失败的项目退出普通复习，转入再教学诊断。
- 正常课和恢复课都受时间、容量和项目数约束；新项目经固定闸门筛选，旧数据通过独立 legacy 通道逐步校准，不会瞬间形成虚假积压。
- 主线自然使用可以补充长期证据，但不会随意改变正式到期日；自然误用只触发后续正式复查，不会在主线中直接修改评级。
- 用户可以跳过、暂停、退役、主动加练或质疑评分，每种操作都有稳定且可追溯的效果，不会被误当成掌握或失败。
- dashboard 分开显示当堂修正、首次延迟提取、稳健提取、新语境迁移、维护表现和样本量；原子复习不会单独推动整体能力升级。
- 每次评分保存最小充分审计证据，既能处理歧义和AI误判，又不永久保存完整对话、长篇主线输出或音频。

#### 建议如何修改

1. **把长期复习拆成“原子 SRS”与“宏观技能探测”两条通道。**
   - 日课 `review` 只复习可单独评分的词义、表达和句型。
   - 阅读主旨、听力推断、篇章组织、开放口语互动等能力使用新材料 `skill probe`、轮次复盘或 assessment 判断，不塞入原子复习队列。
   - 同课提示后的修复只记为 `guided` 教学结果，不能单独证明保持或迁移。
   - 到期复习保持独立，不因本轮焦点改变内容、题型、顺序或配额；复习结果可以作为长期判断的一类输入证据。

2. **建立唯一的正式复习事实来源并消除重复排程。**
   - 新增 `learner/review-items.tsv`，统一保存 `review_item_id`、`concept_id`、明确词义、复习家族、目标范围、允许变体、题型阶段、强度、状态、普通到期日和可为空的提前复查日。
   - 正式状态至少区分 `active / maintenance / legacy_unverified / needs_recipe_fix / needs_reteach / paused / retired`；候选池另行区分 `candidate / observed_only`，不能冒充正式复习项。
   - 新增 `learner/review-item-sources.tsv`，允许一个正式项目关联多个 vocabulary、error 和 session 来源。
   - vocabulary 和 error log 继续记录“学过什么、错误从哪里来”，但不再各自拥有正式排程。
   - `review-history.tsv` 保持只追加，记录当时阶段、强度、首次评级、双重判定、修复和后续日期。
   - 同一“形式＋词义”同时最多只有一个正式项目。只需识别时使用 `receptive_meaning`；确实需要主动使用时把原项目升级为 `productive_expression`，创建目标版本并从 `relearn + strength 0` 重新验证，保留旧历史，不并行建立第二条日程。
   - 不同词义或真正独立的句型可以拆成不同概念；复合错误必须拆成各自可评分的原子项目。
   - `skill-evidence.tsv` 不重复抄写每次复习事件；需要形成长期判断时引用 review event 或 review item。结论应能沿“长期判断 → 复习事件 → 正式项目 → 来源记录”追溯。

3. **只允许三类正式复习家族，并为每题声明唯一目标范围。**
   - `receptive_meaning`：判断目标在具体语境中的意义。
   - `productive_expression`：从意义或情境中主动提取指定单词、短语或搭配。
   - `productive_pattern`：正确生成指定结构，例如 `by + V-ing`。
   - 多词选填、辨析题和造句只是上述家族的题型变体，不另建家族。
   - 每题同时声明：
     - `exact_expression`：必须展示指定词或搭配，仅接受预先列出的词形或固定变体；
     - `pattern`：必须展示指定结构，结构中的语义合适填充可以变化；
     - `meaning_or_function`：主要判断意义或交际功能，合理等价表达可接受；目标较宏观时应转为 skill probe。
   - 同一原子项不因文字或语音模态重复建日程；证据必须记录真实模态，文字答对不能被推断为口语流畅或发音证据。
   - 暂不把发音放入正式原子 SRS；只有获得可靠音频条件后再单独设计。

4. **将题目难度固定为三个逐步升级的 `recipe_stage`。**
   - `relearn`：原语境或近似语境，允许不直接泄露答案的明显支架。
   - `recall`：受控题面但不提供答案型提示，要求独立提取目标意义、形式或结构。
   - `constrained_transfer`：新语境、明确要求目标并给出语义约束，不使用毫无限制的自由造句。
   - 三类家族分别采用：
     - `receptive_meaning`
       - relearn：原／近语境中的目标词＋唯一正确的英文释义选择；
       - recall：新短语境中用中文或简单英文说明当前词义，不给选项；
       - constrained transfer：陌生语境中判断词义或正确用法，并指出语境依据。
     - `productive_expression`
       - relearn：原／近语境限制性填空，可给首字母或小型词库；
       - recall：简单英文释义＋必要语境，不给词库，完整提取目标；
       - constrained transfer：在具有明确语义限制的新场景中使用目标表达。
     - `productive_pattern`
       - relearn：原／近语境填空并给词元，如 `by ___ (practise)`；
       - recall：新句子的受控改写，并给结构锚点；
       - constrained transfer：在新的交际意图中独立使用目标句型。
   - 选择题或词库本身不能证明 recall 或 transfer。
   - `contrast_drill` 只能使用真实学过且容易混淆、词性兼容的项目；每空必须有唯一最佳答案，每词只用一次并保留一个未使用干扰项，每空独立评分。它不能单独证明最高阶段。
   - 造句必须包含真实语义限制，不能用 “It is subtle.” 一类几乎无法判断是否理解的句子。

5. **为每个项目和每次题目建立冻结契约，先检查歧义再展示。**
   - 长期项目保存概念、目标词义、复习家族、目标范围、固定可接受变体、已知易混项，以及2–3个语境种子或语义约束。
   - 每次出题前冻结：实际简短题目、当前阶段与题型、唯一评分目标、预期答案或语义范围、允许变体、标准提示和 `invalid` 条件。
   - 展示前检查：只有一个评分目标；是否明确要求指定表达；是否存在未覆盖的常见正确替代；干扰项是否唯一；英文释义是否符合学习者水平；同批题目的题干、语境、选项或词库是否互相泄露答案。
   - 概念重叠或会互相提示的项目不能进入同一批次，低优先级项目应延期。若第一批反馈意外暴露第二批目标，受影响项目当天不能通过换一道题恢复独立性，必须标记为 `exposed`、延期且不评分；只有展示前已经按队列规则冻结的另一个未暴露备用项目可以补位，否则第二批少出一题。
   - 回答后不得增加隐藏标准。若发现题面没有明确要求目标，或存在合理但未覆盖的多解，应判为 `invalid`，而不是惩罚学习者。
   - 同一项目连续两次无法生成低歧义题目时标记 `needs_recipe_fix`，暂离队列；修好题型后再返回，不能修改其评级、强度或到期事实。

6. **只用“首次独立且有效的回答”评级，并分开判断整体语言与目标证明。**
   - 每题分别产生 `language_validity` 与 `target_demonstrated`：前者判断回答整体语言是否成立，后者只判断本题指定目标是否被证明。
   - 评级只由首次独立有效回答决定：
     - `again`：错误、不知道、无法提取，或需要与目标有关的帮助；
     - `hard`：首次回答最低限度正确，但明显费力、不确定、自我修正，或命中下述唯一机械笔误例外；
     - `good`：在当前题型要求下独立、正常地正确完成；
     - `easy`：只允许在 `constrained_transfer` 中使用，且必须有可靠的高要求、流畅和确信证据；异步文字中不得凭感觉臆测 `easy`；
     - `invalid`：题目歧义、生成错误、技术问题或不可靠语音转写，不进入正式排程。
   - 每批题说明学习者可以在答案后自愿加 `?` 表示明显犹豫、费力回忆或不确定；正确且带 `?`，或回答中出现清楚的自我修正，记为 `hard`。AI不得根据消息间隔猜测思考时间。
   - 若题面明确要求 exact expression，而学习者使用另一种正确英语：`language_validity = pass`，但 `target_demonstrated = not_demonstrated`，评级为 `again`；不能说其英语错误。
   - 若题面没有明确要求目标且存在合理替代，题目自身为 `invalid`。
   - 目标已正确展示时，无关的第三人称单数等错误不得把该项目降为 `again`；它只按第2条规则接受简短反馈或进入候选池。只有该错误使目标意义无法判断或破坏已声明语义限制时，才算目标未证明。
   - `receptive_meaning` 只判断当前词义，不额外考察输出词形。
   - productive 项目的必要词形、屈折和结构属于目标，错误通常为 `again`。若拼写不是独立目标，且只有一个显然、不改义、无其他解释的机械笔误，可判 `hard`；形成另一个词、存在多种解释或拼写本身就是目标时仍为 `again`。
   - 给出多个互斥答案却不标明最终选择时判 `again`；明确标出最终答案时只判最终答案，明显自我修正后的正确答案记为 `hard`。
   - 大小写和标点只有在冻结契约明确把它们列为目标时才影响评级。

7. **使用短复习修复协议，不在 review 中展开完整教学循环。**
   - 先锁定首次有效回答的评级；提示后答对不能修改评级、阶段或长期证据。
   - `invalid` 题直接替换且不惩罚。
   - “英语正确但未展示目标”时，先肯定其英语成立，再明确指出本题仍未证明指定目标。
   - 对错误项目最多给一次最小提示和一次修复机会；仍不会时给最简答案或规则，并要求立即重构一次后结束。
   - 一课最多选择三个 `again` 项进入统一的互动修复批次，按原到期顺序处理；其余错误项给简短答案与原因并按规则到期，不延长主线。
   - 修复结果只记录为 `guided`，不冒充首次提取或迁移。

8. **将 `strength_level` 与 `recipe_stage` 分开，并建立确定状态转换。**
   - `strength_level 0–5` 只控制1、3、7、14、30、60天间隔；`recipe_stage` 只控制 `relearn / recall / constrained_transfer` 的题目深度。
   - `invalid`：两者不变，项目仍到期。
   - `again`：strength 归零；单次失败不立刻降低阶段，连续两个不同学习日均为 `again` 才降一个阶段。
   - `hard`：阶段不变，strength 降一级至最低0，避免高等级困难回答仍等待60天。
   - `good`：尚未到最高题型时，阶段升一级并把 strength 设为1，以3天后验证更难阶段；已在 `constrained_transfer` 时，strength 加一级。
   - `easy`：仅在 `constrained_transfer` 可用，strength 加二至最高5，不能跳过题型阶段。
   - 成功会中断“连续 again”计数；降级时保留历史上较高阶段证据，不覆盖旧事实。
   - 连续三个不同学习日为 `again`，或项目在 strength 0 连续五次有效复习仍无一次 `good/easy` 时，进入 `needs_reteach`：
     - 暂离普通到期队列，不能继续占用 review 时间反复讲解；
     - 在触发后的下一次轮次复盘中诊断先修缺失、目标是否过大、题型是否不当及项目是否仍有价值；
     - 结果只能是重教后再激活、修改目标，或由用户确认退役；
     - 重教完成后以 `relearn + strength 0` 恢复，下一学习日正式复查；
     - 这是已有项目的修复，不占新项目激活名额；
     - `needs_reteach` 与题目生成失败造成的 `needs_recipe_fix` 必须分开。

9. **用低频 maintenance 代替“mastered 后永不复习”。**
   - 项目只有同时满足以下条件才进入 maintenance：
     - 已在 `constrained_transfer` 且 strength 5；
     - 至少有两条发生在不同学习日、新语境中的迁移成功证据，其中至少一条必须是正式 `constrained_transfer` 的 `good/easy`，另一条可以是符合第14点条件的 `spontaneous_transfer`；
     - 上述两条证据相隔至少14天；
     - productive 项目至少一次真正无词库输出。
   - 若最后补齐全部门槛的是一次正式 `constrained_transfer good/easy`，项目立即进入 maintenance；若最后补齐迁移证据的是 `spontaneous_transfer`，项目仍保持 active，只动态派生 `maintenance_ready = true`，等待下一次正式 `good/easy` 确认后再进入。
   - `maintenance_ready` 不是独立权威状态或人工写入结论，而是由当前 stage、strength 和有效证据动态计算；后续 `hard/again` 使门槛不再成立时自动消失，`invalid` 不改变它。缓存方式由第6条实现。
   - 进入 maintenance 后，间隔依次为60、120、180天，之后以180天为上限继续低频维护。
   - maintenance 中 `hard` 退出为 `active / strength 4`，30天后复查；`again` 退出为 `active / strength 0`，下一学习日到期；`invalid` 不改变状态。
   - maintenance 只表示某个原子项目稳定，不能等同于听说读写宏观能力 `stable`。

10. **限制正式项目的进入速度，区分“见过、候选、正式复习”。**
    - 每课最多把6个值得保留的内容记为 encountered/candidate；恢复课仍受既定的新内容缩减规则限制。真正进入正式 SRS 的 vocabulary/error 项，每六次训练合计最多两个。
    - 在每轮第3和第6次训练后设置候选闸门：第一次最多激活1项；第二次补足本轮最多2项，若第一次未使用名额，第二次可以激活2项。
    - 候选必须原子化、去重、词义明确且能生成低歧义题目。
    - 排序固定为：用户明确要求 ＞ 跨任务或跨日期结构性复发 ＞ 对表达或理解影响更大 ＞ 可复用范围更广 ＞ 首次出现更早。
    - 第一次未入选者保留至第二次；普通候选在轮次结束仍未入选则转为 `observed_only`，以后再次复发可重新成为候选。
    - 用户指定项目占用同一名额，不额外突破上限；用户固定保留的候选可等待下一次可用闸门。“现在加入长期复习”只能占用尚未使用的名额，不能绕过积压保护。
    - `active + maintenance` 的真实到期负担超出正常容量，或进入既定恢复模式时，暂停自动激活；仍可教学和保存候选。
    - 新激活项目从 `relearn + strength 0` 开始，下一学习日到期。

11. **按题型成本而非只按项目数量限制每课复习。**
    - 用户可见容量单位为 `relearn = 1`、`recall = 1.5`、`constrained_transfer = 2`；内部用整数权重 `2 / 3 / 4`，避免浮点误差。
    - 正常课容量上限6（内部12）、最多6项、目标约5分钟；恢复课容量上限10（内部20）、最多10项、目标约8分钟。
    - 按既定队列依次选择；下一项放不下时结束选择，不越过它另找更轻的项目填缝。未选择或未作答的项目继续保持到期，不能记为失败。
    - 正常课把预先冻结的编号题目作为一个批次，一次收取回答，再进行至多一次合并补答／修复；恢复课最多两个预先冻结的题批，再进行一次合并修复。
    - 每批一次完成全批评分，不得逐题读取文件、调用工具或提交正式状态。批次反馈展示后，把该批冻结的评级、审计事实、稳定 batch／event ID 和幂等键作为一个 pending `ReviewBatch` payload 写入轻量 checkpoint；普通日课和专门复习课都等到本次 session 的终局反馈／总结后，由第6条的统一事务一次正式提交全部待处理题批。
    - 漏答只追问漏答项；达到时间预算后完成当前互动即进入主课。已经展示但仍未作答的项目不评分并保持到期。
    - 用户单独要求“复习到期内容”时，可以把约30分钟全部用于复习。容量6／10和项目数6／10改为每个选择批次的上限，而不是整节专用复习课的总上限；每完成一批的判定、修复与 checkpoint 封存后，若仍有时间和到期项目才选择下一批，直到约30分钟、到期队列为空或用户主动停止。不能一次抛出全部到期题。
    - 完整预生成批次只保存在临时 session state，不能全部写入长期档案。

12. **使用 active、maintenance、legacy 三通道公平队列。**
    - `active`：新体系中的巩固项目、最近 `again` 和到期 recheck。
    - `maintenance`：已经稳定的低频维护项目。
    - `legacy`：旧数据迁移出的、尚未用新题型定位的项目。
    - 每课先执行保护轮 `active → maintenance → legacy`，每通道依次取一个队首；剩余容量再按 `active → legacy → maintenance` 循环。空通道跳过，当前轮到的队首放不下时结束选择，不搜索更便宜的后项。
    - active 内先处理到期 recheck 和最近 `again`；其余通道内部按到期日、strength、ID排序。焦点目标不得改变车道、顺序或题型。
    - legacy 的历史到期不算“真实积压”，不触发恢复模式，也不暂停新项目激活；但它仍通过保护轮获得公平检查份额，并可使用其他车道未用完的容量。
    - 暂停、修题、再教学或用户操作移出的项目不堵塞其他到期项目。

13. **采用保守 legacy 迁移和统一的首次定位检查。**
    - 迁移前保存快照，不改写原 vocabulary、error 或 review-history，也不补造历史题型、支持程度或迁移证据。
    - 只有完全相同的概念和词义才能自动合并；保留所有来源链接，合并状态采用更早到期日和更低 strength。
    - 复合错误拆分后不得把一条旧评级复制给所有子项目。
    - 篇章组织、听力推断等非原子内容转入 skill evidence 或 learning insight。
    - 含糊匹配进入人工处理，不做模糊自动合并。
    - 旧历史不能证明新的 recall 或 transfer；迁移项统一标为 `legacy_unverified`，旧高 level 也不能直接进入 maintenance。旧 level 和到期日只用于 legacy 内排序与审计。
    - legacy 首次检查固定使用无答案提示的 `recall` 定位题：
      - `again → active / relearn / strength 0`
      - `hard → active / recall / strength 0`
      - `good → active / constrained_transfer / strength 1`
      - 首次定位禁用 `easy`
      - `invalid`、漏答或技术问题仍留在 legacy，不改变状态。
    - 若迁移时的静态检查已经确认旧记录缺少可恢复的原子目标或评分契约，它在进入队列前直接进入 `needs_recipe_fix`；这不算一次出题失败。已经通过迁移检查并进入队列的 legacy 项，仍须连续两次无法生成低歧义题才进入 `needs_recipe_fix`。一次定位无论多好都不能直接进入 maintenance。
    - 完成迁移校验并确认新事实表可重建后，vocabulary/error 中的旧排程字段才停止作为事实来源；原记录继续保留用于审计。

14. **严格限制主线自然表现对复习日程的影响。**
    - 只有原始首次回答、未要求或暗示目标、本课此前未暴露答案、不是照抄，且形式、意义和语境均正确时，才可记录 `spontaneous_transfer`；同一概念每课最多一条。
    - 它可以替代 maintenance 所需的两条迁移证据中的一条，但另一条必须来自正式 `constrained_transfer`。
    - 自然成功不直接改变 strength、stage、status 或 due。`spontaneous_transfer` 作为 `skill-evidence.tsv` 中带 `review_item_id` 的独立证据保存；只有当它使项目满足除“再次正式确认”外的全部 maintenance 门槛时，才动态派生 `maintenance_ready = true`。它不替换 `active` 状态，也不改变排队；下一次正式 `constrained_transfer` 获得 `good/easy` 后才能进入 maintenance。
    - 主线中的明确误用不直接写 `again`，只设置下一学习日的 `recheck_due`；实际抽取日取普通到期日与提前复查日中较早者，正式复查后才修改日程。
    - 只有本课实际选中并明确告知学习者的最多三个反馈主题可以触发 recheck；学习者必须确实尝试了该目标且发生明确误用，同一概念每课最多一次。
    - 未选择的问题只作观察或候选，课程总结应说明已经安排的 recheck。
    - 没有尝试目标、使用正确同义表达、主线中自行修正、意图不明、不可靠ASR、引导练习或已经看过示范，均不得触发自然误用 recheck。
    - 独立、无支持、提前冻结契约的主线任务可以触发 recheck；普通 guided practice 只能作为教学证据。正式 review 中的自我修正仍按 `hard`，与“主线自我修正不触发 recheck”是两个场景。

15. **定义跳过、暂停、退役、自报掌握和主动练习的控制语义。**
    - `skip`：仅本课不再展示，不评级、不改 due，并继续处理其他项目；明确回答“不会／想不起来”仍属于一次有效失败，不等于 skip。
    - `pause`：可逆地移出自动队列，保留原阶段、强度和全部历史；恢复后按原状态重新进入，不得算作 mastered。
    - `retire`：停止自动排程但保留历史，不算 mastered 或 maintenance；只有用户可以确认退役，显式恢复时从 `relearn + strength 0` 重新验证。
    - 用户说“我会了”不能直接跳级、进入 maintenance 或退役；可以安排一次不泄题的正式验证。
    - AI不得因队列拥挤、项目困难或主观判断擅自退役项目。
    - 非到期主动练习默认属于 `practice`，反馈学习效果但不改正式 stage、strength 或 due。因为用户已经点名目标，练习成功也不能冒充无提示延迟证据。
    - 用户主动报告“这个我忘了”或描述刚刚误用，只设置下一学习日 recheck，不直接写 `again`；正式复查决定评级。

16. **在 dashboard 中分开呈现原子保持与宏观能力。**
    - 最近28天只统计有效首次回答，并同时展示样本数：
      - recall 独立提取率：`(hard + good) / recall 有效回答`；
      - recall 稳健提取率：`good / recall 有效回答`；
      - constrained transfer 成功率：`(hard + good + easy) / transfer 有效回答`；
      - constrained transfer 稳健率：`(good + easy) / transfer 有效回答`；
      - maintenance 保持率、退出数量与当前到期数量；
      - legacy 定位进度单列为“已验证／待验证”，不混入保持率。
    - `relearn`、`invalid`、同课 repair、未答、skip、答案暴露和 legacy 首次定位不进入正式保持率。
    - 当堂修正表现从主线 skill evidence 单独显示，不与跨日复习分数合并。
    - 证据不足时明确写“证据不足”，不能只显示看似精确的百分比。
    - 一条原子复习成功不能直接升级 competency 或判定 focus goal 达标；第5条只能把一段时间的复习汇总与 skill probe、assessment 等证据共同使用。28日窗口只用于描述趋势，不构成按时间晋级规则。

17. **保存最小充分审计记录，并用只追加事件处理申诉。**
    - 每个实际展示的 `question_instance` 都必须永久保存一条最小充分审计记录；未展示的预生成题壳不生成永久实例。`review-history.tsv` 继续作为排程事件账本；若现有TSV不适合安全容纳简短原文和结构化契约，则新增与 `event_id / question_instance_id` 关联的审计表。每条记录必须包含：实际展示的简短题目、冻结契约、首次有效回答中足以判分的最短片段、`language_validity`、`target_demonstrated`、评级及简短理由、`invalid` 原因和 repair 最终结果。
    - 复习题默认使用非私人的人工语境。只有无法用短片段判断时才保存必要整句；答案含个人信息时只保留目标所在片段并脱敏；口语只保存最短必要转写，不保存音频。不得保存完整对话、完整主线输出、无关隐私或整个预生成题批。
    - `invalid` 也保留为非计分审计事件，用于识别反复失败的题型，但绝不改变日程。
    - 评分展示后无需让用户逐项确认；用户或AI可以当场或事后发起复核，但用户不能直接指定评级。
    - 复核只能依据当时冻结契约：题面有未覆盖的合理答案、泄题或技术故障时，追加 `void` 事件并恢复答题前状态；AI只是按既有契约判错时，依据原首次回答追加 `correction` 事件并改为正确评级；用户事后才想起答案或补交新答案时，只能算 repair，不能改写首次表现。
    - 原历史不得删除或覆盖。若更正发生后已经存在后续事件，应按时间顺序重放全部有效事件，重算当前 stage、strength、due 和 dashboard；复核成立或不成立都向用户说明简短依据。
    - 临时 `review_state` 至少保存选中顺序、车道、权重、冻结契约、已经展示的批次、首次判定、`exposed / invalid`、repair 状态、待提交批次和 `pending_persistence`。恢复时不得重问已完成项目或重置提示。

18. **同步更新运行规则、验证和测试；性能实现由第6条统一规定。**
    - 修改 `SKILL.md`、`references/rubrics.md`、`references/data-schema.md`、session 模板、dashboard 生成和 tracker，使上述题型、评分、状态、车道、容量及用户控制成为强制协议。
    - 每个完成题批在反馈时冻结一个 `ReviewBatch` payload，包含全部有效评级、invalid、申诉更正和控制事件，并预分配稳定幂等键；它在课中只进入 pending checkpoint，由 `FinalizeSession / AbandonSession` 的统一事务正式提交。当前状态必须能从正式有效事件重建。
    - 本条只要求题目预先冻结、同批一次判定、用户先看到结果、无逐题正式持久化，以及中断后不重答；第6条负责持久 checkpoint、整课一次正式提交、`pending_persistence` 失败降级和延迟测量。
    - 至少增加以下行为测试：
      - 原语境填空、无选项 recall 和新语境 transfer 按阶段切换；
      - 正确替代表达在“明确要求目标”和“未明确要求目标”下分别得到 `again` 与 `invalid`；
      - 目标正确但有无关小错时不误判目标失败；
      - 必需词形错误、唯一机械笔误、多候选答案、自我修正和不可靠ASR按固定规则评分；
      - repair 不修改首次评级，`?` 只把正确但费力的回答标为 `hard`；
      - stage、strength、maintenance、`needs_reteach` 和 `needs_recipe_fix` 转换准确；
      - spontaneous evidence 补齐门槛时只产生 `maintenance_ready`，随后正式 `good/easy` 才进入 maintenance，`hard/again` 会使不再成立的 ready 自动消失；
      - 容量权重、项目数上限、三通道公平性和 legacy 非积压语义正确；
      - 候选闸门每轮不超过两个正式新项目，同一形式与词义不产生双重日程；
      - spontaneous success、自然误用 recheck、主动练习、skip、pause、retire 和“我会了”不会越权修改日程；
      - legacy 定位不会使用 `easy` 或直接进入 maintenance；
      - legacy 静态缺少原子契约时直接进入 `needs_recipe_fix`，已入队项目只有连续两次题型生成失败才进入，漏答和技术故障不计入该阈值；
      - invalid、AI误判及已有后续事件的申诉都可通过追加事件重建正确状态；
      - 长期记录足以复核评分，但不保存完整私密内容；
      - 同批题目不会互相泄露；跨批反馈暴露目标时原项目延期，仅允许预冻结且未暴露的其他项目补位；恢复后不会重问、重复评分或重复提交已经完成的项目。

### 4. 在不改变队列的前提下，实现 CEFR 对齐、基于证据的课内难度自适应

> **与第1、2、3、5、6条的边界：** 第1条决定长期阶段、焦点目标和六课轮次队列；本条只能在当前队首已经预编译的活动内改变一个任务条件，不得跳过、增加或重排计划项。第2条定义八种 activity_family、活动契约、首次回答判定和纠错微循环；本条定义十五种 competency_family。两类 family 是正交字段，全文必须写明所指，不能混称。第3条的 review 是完全独立的到期复习通道：其抽取、顺序、题型、recipe_stage、评级、到期日和结果均不进入本条的适应证据、计数、状态或难度选择，本条也不得以焦点或难度为由改变 review。第5条独占 focus goal 的 met、CEFR competency 的 stable、gate 达标和阶段完成判定；本条由第6条实现更深的预加载、缓存和持久化提速，但不得改变本条的状态语义。

#### 修改前的问题具体体现

- 当前“约 70%–85% 可理解”和“两次连续测评后提高难度”只是原则，没有区分长期 CEFR 能力、材料属性、任务条件和一次表现，容易把某次发挥好误认为能力升级。
- 听、说、读、写的难度由篇幅、信息密度、推断要求、准备时间、输出范围、互动轮次、来源数量和提示等共同决定，目前没有固定阶梯、相邻台阶或调节顺序。
- AI需要临时阅读 dashboard 和多份历史 session 决定难度，既慢又容易受最近一次表现影响；相同证据也可能得到不同建议。
- 一次同时改变多个变量后，成功或失败无法归因；某一维度被暂停时，AI还可能换一个名字相近的维度继续加压。
- 普通教学、当前目标检查和正式 stretch 没有清楚分开；提示后重答、歧义题、技术故障或不可比材料可能被错误计为成功或失败。
- 综合任务可能同时暴露听力、口语、语法、词汇和连贯性。如果全部计分，会把一次回答复制成多次能力证据；如果完全不记录，又浪费真实旁证。
- “多次上升失败后暂缓”尚未落实为跨日门槛、hold、恢复和重新探测协议，能力瓶颈可能被频繁重新挑战。
- 六课轮次如何兼顾焦点、Required、Breadth、Extension、听说读写覆盖和状态修复没有确定性容量规则。
- 若把完整规则留给日课 AI 临时推演，会增加等待时间，无法满足开始学习后的交互体验。

#### 修改后预期执行时实现的具体效果

- curriculum 继续以 CEFR 对齐的听、说、读、写能力为长期地图；课内难度只表示同一能力下一个任务条件台阶，不会直接把 B1 改成 B2。
- 每次活动都在用户回答前冻结“测什么、在什么条件下测、什么算通过”；正式证据只来自未经反馈的首次独立回答。
- 正常教学使用 scaffolded、target、stretch 三个活动带；每课至多一次难度实验，每次只提高一个相邻条件。
- 用户跨日、跨新语境稳定成功后才获得挑战资格；一次最好表现不触发继续升级。反复 probe 未达或一次 overload 会进入 hold，反复 target 失败则进入 target_unstable；两者都须经跨日恢复，不能频繁冲击能力瓶颈。
- 提示、修改后答案、普通 training、secondary、review、技术故障和歧义题不会污染难度状态。
- 一轮六课在焦点、四技能维护和 R/B/E 轮换之间有固定容量，但不为了填满证据配额把课程变成连续测验。
- tracker 负责状态归约，AI只读取当前小课包、检查至多一个预授权 probe 候选、执行契约并提交一次批量结果；日课不扫描历史、完整目录或其他候选，也不重算全局状态。
- “开始今日学习”到首个可作答步骤在项目可控路径内正常不超过 30 秒、硬预算不超过 90 秒；Bootstrap 含适应查表的端到端本地路径不超过 5 秒。异常时安全降级到同一队首的 ready fallback training，不惩罚学习者。

#### 建议如何修改

1. **分开五个层级，禁止互相越权。**
   - competency stage／gate：长期 CEFR 对齐能力，只由第5条在轮次复盘或测评中更新。
   - material profile：来源本身的篇幅、语速、体裁、信息密度、语言复杂度和主题熟悉度。
   - activity band：scaffolded、target、stretch，只描述本次活动相对当前 target 的位置。
   - adaptation state：同一 adaptation key 在固定任务条件阶梯上的进度与保护状态，由 tracker 归约；它不等于长期能力状态。
   - quality profile：range、grammatical_accuracy、vocabulary_control、coherence、fluency、sociolinguistic_appropriateness、phonological_control，描述结果质量而非难度旋钮。只有获得可靠音频时才评价 phonological_control。
   - activity band 的失败不能降低 CEFR 能力；CEFR gate 稳定也不能批量抬高所有任务条件。

2. **建立 CEFR 对齐的薄能力目录。**
   - 新建版本化 references/competency-catalog.json，第一版只覆盖 A2、B1、B2。
   - 保留 15 个稳定 competency_family，每个等级各有一个 gate，共 45 个薄 gate。这里的 competency_family 是长期能力分类；第2条的八种 activity_family 是任务做法分类，两者是正交字段，不能混用或互相替代。
   - 每个 gate 只含一条本地 can-do 和默认两条 observable indicator；互动或调解等确实无法覆盖时才允许第三条。
   - indicator 使用跨 A2/B1/B2 复用的 indicator_thread；等级差异写在 level_anchor，不为每级新造近义指标。
   - 一次 primary observation 只预声明一个 primary_indicator_id 和 level_anchor，结果只能为 met、not_met 或 not_assessable；不得一次判完整个 gate。
   - 来源链固定为：CEFR Companion Volume 2020 官方 scale／level → 项目 competency_family → indicator thread → level anchor → activity contract。
   - 官方描述被拆分、合并或具体化时标记 project_operationalization；项目只能称 CEFR-referenced／aligned，不能声称官方校准。B1+ 只有在所选官方 scale 确有 plus descriptor 时才可引用；项目自建过渡点使用本地名称。
   - curriculum.md 作为用户可读目标，由目录生成或接受一致性校验；AI只能引用已有 ID 和版本，日课不得临时创造能力或指标。

3. **采用以下 15 个 competency_family 和两条默认 indicator thread。**

   | Skill | Competency family | 对齐的 CEFR scale 方向 | 默认 indicator threads |
   | --- | --- | --- | --- |
   | Listening | L_INTERACTION | Understanding interaction between other people | speaker_intent_tracking；turn_relation_tracking |
   | Listening | L_ACTION_INFO | Understanding announcements and instructions | required_action；conditions_constraints |
   | Listening | L_EXTENDED | Understanding audio media and recordings／live audience | main_line；idea_relation |
   | Speaking | S_TRANSACTION | Goal-oriented co-operation／obtaining goods and services／information exchange | goal_completion；repair_negotiation |
   | Speaking | S_CONVERSATION | Conversation／informal discussion | responsive_contribution；turn_management |
   | Speaking | S_EXPLAIN | Sustained monologue: giving information／describing experience | message_sequence；detail_development |
   | Speaking | S_ARGUMENT | Sustained monologue: putting a case | position_relevance；support_development |
   | Reading | R_FUNCTIONAL | Reading correspondence／instructions／orientation | purpose_action；constraint_navigation |
   | Reading | R_NARRATIVE | Reading as a leisure activity | event_relation；attitude_implication |
   | Reading | R_EXPOSITORY | Reading for information and argument 的信息分支 | main_structure；detail_relation |
   | Reading | R_ARGUMENT | Reading for information and argument 的论证分支 | claim_relation；evidence_inference |
   | Writing | W_TRANSACTION | Written interaction／correspondence／notes, messages and forms | communicative_completion；reader_fit |
   | Writing | W_EXPLAIN | Written production／reports and essays 的解释分支 | explanation_sequence；supporting_detail |
   | Writing | W_ARGUMENT | Reports and essays 的论证分支 | position_structure；support_integration |
   | Writing | W_MEDIATE | Processing／relaying／explaining text in writing | source_fidelity；selection_synthesis |

   - A2 anchor 以熟悉、简短、明确、直接信息和简单交际功能为核心。
   - B1 anchor 以清楚的标准语言、连贯处理主要信息和相关细节、给出理由或简单推断为核心。
   - B2 anchor 以较复杂或延展内容、处理隐含关系、持续展开并根据对象调整为核心。
   - 每个具体 anchor 仍须按 competency_family 写成可观察标准，不能只复制上述通用句。
   - 用户界面继续只显示听、说、读、写；内部用 cefr_mode 和 cefr_scale_id 区分 scale。口语 production 与 interaction 分开存，mediation 只作内部 tag，不建立第五个总分。综合任务只有一个 primary competency 驱动适应。

4. **固定 R/B/E 角色，不用平均分掩盖偏科。**
   - 每个 competency_family＋level gate 的 role 只能是 required、breadth 或 extension，只能在 curriculum 更新或轮次复盘时改变，日课不得为方便排课降级角色。
   - required 是完成该技能阶段必须稳定的 gate；breadth 用于覆盖或维持广度，当前 gate 不必稳定，但持续 core failure 会成为修复缺口；extension 为可选探索，不能抵消 required。
   - 听、说、读、写分别完成自己的阶段，不计算会掩盖弱项的四项平均分。

   | Competency family | A2 | B1 | B2 |
   | --- | --- | --- | --- |
   | L_INTERACTION | R | R | R |
   | L_ACTION_INFO | R | R | B |
   | L_EXTENDED | B | R | R |
   | S_TRANSACTION | R | R | B |
   | S_CONVERSATION | R | R | R |
   | S_EXPLAIN | B | R | R |
   | S_ARGUMENT | E | R | R |
   | R_FUNCTIONAL | R | R | B |
   | R_NARRATIVE | B | R | B |
   | R_EXPOSITORY | B | R | R |
   | R_ARGUMENT | E | B | R |
   | W_TRANSACTION | R | R | R |
   | W_EXPLAIN | B | R | R |
   | W_ARGUMENT | E | R | R |
   | W_MEDIATE | E | B | R |

5. **将 TOEFL 题型同时映射到 activity_family 和 competency_family，而不是另建能力体系。**
   - 每个 TOEFL 适配任务必须同时保存第2条的一种 activity_family 和本条的一种 competency_family。例如 Email 是 `extended_writing + W_TRANSACTION`，Academic Discussion 是 `opinion_explanation` 或 `extended_writing + W_ARGUMENT`，Interview 是 `interaction_roleplay + S_CONVERSATION` 或 `opinion_explanation + S_ARGUMENT`；具体映射由题目实际构念决定，不能只凭题型名称猜测。
   - Complete the Words 是词汇／语境辅助任务，Build a Sentence 是句法辅助任务，Listen and Repeat 是听觉保持、形式和可懂度辅助任务；它们本身不是 competency_family。
   - Complete the Words 和 Build a Sentence 通常使用 `controlled_form`；Listen and Repeat 使用 `oral_imitation`。各听力题型先选择 `source_comprehension` 等 activity_family，再映射相应 listening competency_family。
   - 听后口头复述／解释以 S_EXPLAIN 为 primary 并带 mediation tag；书面总结和整合归 W_MEDIATE。来源输入可以产生辅助观察，但不能同时推动两个适应状态。
   - grammar、vocabulary、coherence 等 quality profile 可以与 competency_family 组成焦点，例如 S_ARGUMENT＋coherence；具体时态、搭配和词项进入第2条反馈与第3条 review，不成为 CEFR competency node。

6. **建立固定、相邻、版本化的任务条件阶梯。**
   - 新建 references/difficulty-ladders.json，分为 dimension_registry、ladder_template 和 family_ladder_binding。
   - 每个 difficulty dimension 只有 3–5 个稳定 step_id，记录可检查的原始范围、增难方向和 load_axis_id；正式 stretch 只能移动到相邻一步，一次只改变一个维度。
   - 第一版采用五种公共模板。family_ladder_binding 以 competency_family、activity_family、modality 和 construct 的组合为键，避免把“练什么能力”和“用什么活动练”混成同一字段。为控制复杂度，每个绑定只启用一个默认维度和最多一个备用维度；第三维度不属于首版，未来只能通过带迁移方案的目录版本升级另行评审。一节课仍只可预授权一个候选。

   | Ladder template | 默认维度与四个相邻台阶 | 最多一个首版备用维度 |
   | --- | --- | --- |
   | receptive_single_source | input_span：短／中短／中长／延展；听力和阅读分别使用数值 adapter | relation_load：直接定位／跨句连接／单一推断／多重或隐含关系 |
   | spoken_monologue | discourse_moves：1／2／3／4 个同一构念内的交际动作 | preparation_time：60／45／30／15 秒 |
   | spoken_interaction | interaction_turns：2／4／6／8 个有效轮次 | predictability：完全可预期／熟悉变化／一个意外条件／动态协商 |
   | independent_writing | required_moves：1／2／3／4 个同一构念内的写作动作 | output_scope：约 50／80／120／160 词 |
   | source_based_mediation | integration_distance：直接转述／跨段选择／整合一致来源／协调有差异来源 | source_span：短／中短／中长／延展 |

   - modality adapter 可以补充听力语速、说话人数、阅读导航等条件，但不能复制整套阶梯或改变核心 construct。
   - 标准化 access condition，例如预先规定的重放次数，可以作为冻结条件；AI临场给出的提示、句型或答案线索属于 instructional support，不是正式难度台阶。
   - 正确率、语法质量、词汇质量、流利度、连贯性、用户当天状态和 CEFR 等级都不是 difficulty dimension。
   - 改变活动做法或交际任务类型必须切换 activity_family；改变长期核心 construct 还必须切换 competency_family。两者都不能冒充原 binding 的升难；binding-specific 阶梯只有公共模板确实不适用时才能新增，并须有版本、迁移表和测试。
   - 梯顶只标记 ceiling_reached；梯底不稳定进入诊断和 scaffolded 流程。AI不得临时发明台阶。

7. **在轮次复盘时预编译六课活动骨架，在展示前冻结最终实例。**
   - 每个下一轮 plan item 预存一个小型 activity package，至少给出 lead primary，按需要给出 auxiliary primary 和 secondary；每课至多包含一个 `preauthorized_probe_candidate`。
   - 轮次复盘冻结 competency_id、competency_family、activity_family、indicator_id、level_anchor、template_id、最多三个 criterion_id、planned／allowed access profile、允许的 material constraints、`max_evidence_mode` 和是否允许 probe。它只按第19项的固定优先级预选一个 probe 候选，不提前冻结会受轮内新证据影响的最终 evidence_mode、target_step、planned_step 或 planned_band。
   - Bootstrap 只检查这个预授权候选和对应的小型状态投影；若仍满足条件，就在用户答题前解算并冻结最终 evidence_mode、target_step、planned_step、planned_band 和 changed_dimension。若不再满足条件，只能保守降为 target_check 或 training，不能扫描或改选其他候选。轮中后来产生的新资格只保存在状态中，等待后续已经预授权的兼容活动或下一次轮次复盘。
   - 运行时选定材料后，由版本化 catalog／adapter 的确定性 `ResolveActivityInstance` 在用户看到题目前补齐 content_id、context_id、material profile、presented_step、原始条件值和评分阈值；AI不得自由改写阈值。此时冻结 planned／allowed support，回答后另记 actual_support；超出许可即视为 guided 或 not_assessable。
   - 完整契约和题面在展示前以 prepared 状态写入当前 session 检查点。用户尚未作答时恢复可原样重显同一题；一旦已有首次回答则不得重问，也不得新增标准、改变 evidence_mode 或把普通练习追认为证据。
   - 每个 package 必须同时包含一个 `ready_fallback_activity`：它具有已知 metadata、完整题面、契约、criterion、答案／评分要点，可以不经再次联网或规划直接展示；fallback 固定为同一队首的 training。
   - 必须同时保存 target_step、planned_step、presented_step 和原始条件值。scaffolded 可以使用预定义的较易 step，但不自动降低 target；多步降难或多种帮助后的结果统一视为 guided。
   - 每个正式 stretch 契约同时冻结 core_floor 和 challenge_floor，避免把“没有完成新增挑战”误判为“原能力整体失败”。

8. **使用可计算的 task fingerprint 判断可比性。**
   - adaptation key 固定为 competency_id＋activity_family＋difficulty_dimension；hold 同时绑定 load_axis_id，不能换近义维度绕过。
   - fingerprint 至少包含 catalog／ladder／contract 版本、day_id、construct、modality、template、indicator＋anchor、criterion set、response format、context class、material band、comparability_group、content_id、context_id、support_level、access profile 和全部 condition steps。
   - “新材料／新语境”只要求 content_id 和 context_id 相对于当前状态保存的固定大小比较窗口及本轮已预编译实例不重复；不得为证明终身从未出现而扫描全部历史。context class、体裁、模态、核心要求、评分标准、comparability_group 和支持程度必须保持可比。
   - target check 要求所有条件仍在同一 target step；stretch 只允许预声明维度相邻上升一级，其余冻结字段相同。
   - 未被调节的篇幅、语速、轮次等数值必须落在 adapter 规定的容差；无法可靠取得 metadata、多变量同时变化、先修缺口、提示污染、答案暴露或技术问题时，将 validity 记为 non_comparable／invalid，并把能力结果记为 not_assessable。用户主动中断且尚未完成时只保留 pending checkpoint；明确放弃时记 abandoned，二者都不是 invalid 或能力失败。
   - 同一 adaptation key 每个学习日最多一条正式证据；invalid、guided、重试和没有相关活动的日子既不计数，也不打断、清零或使资格过期。

9. **给每次回答设置一个 primary、有限 secondary 和严格的证据预算。**
   - 一个 observation 是“一份预冻结契约＋一次未经反馈的首次独立回答”，使用唯一 observation_id，只存一次事实，不把投影复制成多次独立表现。
   - 每个 observation 必须恰有一个 primary indicator，最多一个答题前声明的 secondary indicator。
   - 一节正常日课最多两个 primary，通常分别来自 input 和 output；全课最多一个 secondary，因此 CEFR 层面的观察总数不超过三。
   - 只有 primary 可以更新 target、stretch、promotion、hold、unstable 和 condition step。secondary 只是第5条可引用的长期旁证，不得触发升难、清除 hold、单独完成 required gate、替代焦点证据或算成另一天／另一语境／另一任务。
   - secondary 必须自然共现、无需用户追加回答、答前冻结标准并可独立归因。答完后“顺便发现”不得追记；若 primary 失败使原因无法区分，secondary 记 not_assessable。
   - 如果两个能力都需要正式证据，拆成两个反馈前的独立首次回答，各自作为 primary。例如先做听力理解，再在内容反馈前口头复述。只有一次复述时，不能反推听力成功或失败。
   - quality profile 和具体知识点附着在原 observation 上，不占 secondary 名额。

10. **在答题前固定 primary 的 evidence_mode。**
    - training：学习、尝试方法或接受支架；可以记录教学观察、quality profile 和知识点，但不更新适应状态。
    - target_check：在当前 target 条件下完成首次独立回答；可以更新 target 稳定性、stretch 资格、promotion 中间巩固和 unstable 恢复。
    - difficulty_probe：用于 stretch、promotion confirmation 或获准后的 hold re-probe；每课最多一个。
    - 同一课的两个不同 adaptation key 可以各有一个 target_check；其中只有 lead primary 能成为 difficulty_probe，auxiliary 即使获得资格也要等以后排成 lead。
    - 原定正式检查若受到提示、歧义、技术故障或不可比条件影响，保留为教学观察，正式结果记 not_assessable，不算用户失败。
    - review、secondary、提示后答案、revised、guided 和普通 training 都没有修改适应状态的权限。
    - 契约校验器必须定义第2条 purpose 与 evidence_mode 的兼容表：practice 不得成为 difficulty_probe，assessment／capability_probe 不得更新 adaptation；非法组合在展示前降为 training 或停止正式取证，不能临场猜测。

11. **同时记录 task、core、challenge 和成本，不因挑战失败或局部小错否定原能力。**
    - 第2条的 task_result 继续使用 success、partial、failed、not_assessable；本条不改写该结果。所有 essential criterion 满足时 task_result 才不为 failed，全部 criterion 满足时才为 success。
    - core_result 统一为 met、not_met、not_assessable：预声明 core_floor 均满足时为 met；任一 core essential 未满足时为 not_met；task_result 无法公平判断或评分本身不确定时为 not_assessable，并记录 invalid_reason＝scoring_uncertain。`uncertain` 不再作为 core_result。
    - validity 单独使用 valid、invalid、non_comparable；non_comparable 只描述证据不可比，不作为 core_result 或 challenge_result。
    - stretch 的 challenge_result 只使用 stretch_met、stretch_not_ready、stretch_overload、not_assessable。stretch_not_ready 表示 core_result＝met、但相邻新增 challenge_floor 未满足；stretch_overload 只在预声明 overload 条件成立，且有效表现证明唯一升高维度导致 core_floor 崩溃或无法在允许支持内独立完成时使用。普通 challenge 未达不能升级为 overload；用户仅表达负荷过大或要求停止时，应按情况设置 user_hold、保留 pending 或记 abandoned，不能单独证明 overload。
    - 局部第三人称单数、冠词、搭配或其他语言小错不使 core 失败；只有它命中预声明 core_floor 中的 essential criterion，或已经改变、严重模糊意义时，才可使 core_result＝not_met。命中其他 criterion 只影响 task_result、criterion_result、quality profile、焦点反馈或第3条 review。
    - challenge 未达而 core 保持时，不再做 target 重测；core_result＝not_met 或 not_assessable 时，如时间允许只用一项全新、未暴露的旧 target 任务确认一次。
    - 同课 target 重测只可帮助决定即时支架，永远不能确认 promotion、退出 hold 或形成跨日证据；guided／revised 结果不改变难度结论。时间不足时保留原 baseline。
    - cost_signal 使用 normal、high、unknown。high 只可来自用户明确表示“非常吃力”、可选难度评分为 5/5，或契约答前声明且确实观测到的客观信号；禁止依据异步回复间隔、模型等待时间或用户多久才发送消息推断。在冻结条件内独立完成且没有 high 信号时记 normal；只有支持记录缺失、成本信号冲突或无法可靠判断时才记 unknown。只有 normal 满足后文的 normal 配额，unknown 不能冒充 normal。

12. **用 tracker 归约一个进度轴和少量覆盖层，AI不得手工改状态。**
    - 每个 adaptation key 的 progress_state 只有 target_building、probe_ready、confirmation_building、promotion_hold。
    - target_unstable 是可与任一 progress_state 共存的布尔覆盖层；进入时保存 resume_progress_state，并暂停其原进度。学习 flags 只使用 user_hold、ceiling_reached；migration_review_required 作为版本迁移保护，不属于学习状态。
    - promotion_hold 另有 hold_phase＝recovering、release_ready、first_probe_met、confirmation_ready，用于完整表达“恢复三次 → 获授权再探测 → 中间 target → 第二次 probe”。是否具备重探资格只以 hold_phase 为事实源，不再另存同义布尔 flag。
    - 旧术语只作迁移映射：target → target_building，stretch_eligible → probe_ready，promotion_pending → confirmation_building，confirmation_ready → confirmation_building 中 `required_next=difficulty_probe`，reprobe_ready → promotion_hold＋hold_phase＝release_ready。旧的 `*_pending` 不再作为状态；是否能够排入 probe 由预授权活动决定。
    - promoted 不是长期状态：promotion 成立时 target_step 相邻上移，随后立即进入 target_building，并要求新 step 的后续巩固。
    - 状态投影只保存 target step、最近有效 target／probe 的固定大小窗口、跨日和语境计数、normal 数量、中间巩固、hold／unstable 恢复计数、相关日期与 observation ID。
    - AI只提交冻结契约、首次结果、validity 和 cost_signal；所有窗口、连续次数和状态迁移由 tracker 的确定性 reducer 完成，相同事件序列必须得到相同状态。

13. **只有跨日、跨语境的 target 成功才进入 probe_ready。**
    - 当前 adaptation key 和当前 step 最近两条有效 target 首答都成功，且来自至少两个学习日和两个新 context_id，才将 progress_state 设为 probe_ready。
    - invalid、guided、retry 和不相关课程忽略，不打断序列，也不因自然时间或轮次流逝而过期。
    - 如果最新成功为 high 或 unknown，已有成功证据保留，但必须再取得一条新的 normal target 成功才允许 probe。
    - probe 只在以后一个经过预授权的兼容队列活动中执行，不在刚取得资格的同一课追加。
    - 最好成绩、峰值表现和一次意外超常发挥都不能单独触发升难。

14. **升难需要两次 stretch 成功和中间一次 target 巩固。**
    - 第一次有效 stretch_met 将 progress_state 设为 confirmation_building、`required_next=target_check`，不立即升级。
    - 两次 stretch_met 必须来自不同学习日和新语境；两者之间必须有一项新的有效 target 成功，且两次 stretch 中至少一次 cost_signal＝normal。
    - 完成中间 target 后仍处于 confirmation_building，但把 `required_next` 改为 difficulty_probe；第二次 probe 仍要等待以后一个预授权的兼容 lead 活动。
    - 第二次 stretch_met 后，proposed step 从下一项相关活动起成为新 target，progress_state 回到 target_building。
    - promotion 后必须在另一个新语境取得一次该新 target 的 consolidation，才能为下一次升级重新累计资格。
    - 一次用户主动要求的高难练习不自动 promotion；只有它被预先声明为合格的正式 lead probe、满足全部统一证据条件时才可进入相同状态机。

15. **对 probe 失败实行逐级冷却，并禁止频繁冲击瓶颈。**
    - 第一次 stretch_not_ready 将 progress_state 设回 target_building；再次进入 probe_ready 前仍须重新取得两条跨日、跨新语境的有效 target 成功。
    - 同一 proposed step 最近三次有效 probe 中有两次未达，包括 F-S-F，将 progress_state 设为 promotion_hold、hold_phase＝recovering。
    - 一次 stretch_overload 立即进入 promotion_hold／recovering。
    - invalid 或 non_comparable 不进入三次窗口，也不得同日重试；guided、同题重做或同课旧 target 回测都不能清除失败或 hold。
    - hold 绑定原 adaptation key、proposed step 和 load axis，不能改 dimension、step 名称或 competency_family 绕过。

16. **promotion_hold 只有长期恢复并经轮次复盘授权后才可完成升级。**
    - hold 不按日期或轮次自动到期；整个流程中 progress_state 始终为 promotion_hold，直至真正 promotion。
    - hold_phase＝recovering 时，在原 target、无额外支持条件下，需要连续三条有效独立成功，分布在三个学习日和至少两个新语境，其中至少两条 cost_signal＝normal。
    - target 失败会重置该恢复序列；invalid、guided 和 scaffolded 忽略。
    - 满足门槛后只把 hold_phase 设为 release_ready；下一次轮次复盘才可把该 key 写为以后一个兼容活动的 preauthorized_probe_candidate，不能当课或复盘中立即挑战。
    - 该再探测 stretch_met 后设 hold_phase＝first_probe_met；随后必须取得一条新的有效 target 成功，才设 hold_phase＝confirmation_ready；之后仍须等待另一个预授权 probe。第二次 stretch_met 才真正 promotion 并解除 hold，完整保留“两次 stretch＋中间 target”的门槛。
    - 任一 hold probe 的 stretch_not_ready 会回到 hold_phase＝recovering 并重置恢复累计；stretch_overload 同样重新开始 recovering。用户提前主动要求的高难题不计入恢复或 hold probe。
    - recovery mode 中精确原 target 的有效证据可以累计，并可使 hold_phase 进入 release_ready，但 recovery 覆盖层仍禁止 probe；恢复结束后也必须经轮次复盘预授权。

17. **把当前 target 不稳与“下一台阶尚未准备好”分开。**
    - 一次 target 失败不改变 baseline，只等待新题确认。
    - 最近三条有效 target 首答中有两次失败，并跨至少两个学习日，设置 target_unstable＝true、保存 resume_progress_state；停止所有 stretch，下一项相关活动改为预定义 scaffolded。若 resume_progress_state＝promotion_hold，归档尚未完成的重探链，把 hold_phase 重置为 recovering，并以 unstable 恢复序列重新累计，不能保留 first_probe_met 或 confirmation_ready 后直接续接。
    - scaffolded 成功只是教学结果，不能证明 target 恢复；连续两次 scaffolded 失败时保持 unstable，并在轮次复盘诊断先修缺口、任务设计和契约，不得无限向下调。
    - 退出 unstable 需要原 target、无额外支持下连续两条有效独立成功，来自不同学习日和新语境，且至少一条 cost_signal＝normal；target 失败重置，invalid 忽略。
    - 若 resume_progress_state＝promotion_hold，清除 unstable 后恢复 promotion_hold／recovering；两条 unstable 恢复成功作为 hold 三条恢复证据中的前两条，之后仍须补足第三条及 normal 配额，不能恢复进入 unstable 前的 first_probe_met 或 confirmation_ready。
    - 若此前没有 hold，清除 unstable 后把 progress_state 设为 target_building，清除旧 probe／confirmation 进度，并令 `target_building.required_next=post_unstable_target_check`；必须再取得一条更晚的新语境有效 target 成功，才可重新按第13项检查 probe_ready。
    - 尚未完成的 stretch 证据归档但不 promotion。recovery mode 中达到上述恢复门槛时仍保持 target_unstable，等恢复结束后的相关队列活动再清除，不创造新的 pending 状态。

18. **把 user hold、recovery、梯顶和 capability probe 作为保守隔离规则。**
    - 用户说“暂时不要增加某项难度”时立刻设置 dimension／load-axis 级 user_hold，不算失败、不改变能力。只有用户明确解除，或用户在轮次复盘接受 AI 的解除建议时才可清除，AI不得静默解除。
    - 主观难度可以单独阻止挑战，但不能单独证明成功、失败或能力等级。
    - recovery mode 禁止 stretch、confirmation probe 和 hold probe；progress_state、flags、hold_phase 及其证据原样保留，不随时间失效。
    - recovery 中只有“精确原 target、无额外支持的首次独立回答”可用于稳定、巩固或恢复累计；scaffolded 仍只作教学。
    - 恢复结束后从原严格队列的下一个兼容活动继续，不重排、不补课。
    - ceiling_reached 只表示该 task-condition ladder 已到顶，不等于 CEFR gate stable。
    - capability_probe 只能由 cycle plan 或 assessment plan 预先安排，日课 AI不得临时发起。
    - capability_probe 不能与 condition stretch 出现在同一个 activity；若要同时观察长期能力和局部任务条件，必须拆为不同活动。
    - capability_probe 不读写本条 adaptation progress_state；其结果只进入第5条长期证据，用于 competency／gate 判断，不直接改变 task-condition step。

19. **由轮次复盘预授权唯一 probe，运行时不得扫描候选。**
    - 严格队列和周期计划先锁定 primary competency、competency_family、activity_family、indicator 和至多一个 preauthorized_probe_candidate；难度引擎不能为了寻找可升难项目更换任一 family 或改变本课重点。
    - 轮次复盘先排除 recovery、target_unstable、user_hold、hold_phase 尚未到 release_ready 的 promotion_hold、缺少中间 target、不可生成新可比任务或同一 load axis 被暂停的对象；再按“promotion_hold 且 hold_phase＝release_ready → confirmation_building 且 required_next＝difficulty_probe → progress_state＝probe_ready”排序。
    - 同级冲突只在轮次复盘按等待最久、curriculum 固定维度优先级、稳定 adaptation key ID 破同分，最终最多预授权一个；同一 load axis 的兄弟维度不能绕过 hold 或 unstable。
    - Bootstrap 只验证这一候选当前仍合法，不重新枚举或改选。候选失效时本课保守降为 target_check 或 training；轮中后来出现的 probe_ready 或 hold_phase＝release_ready 只保留到后续已经预授权的活动或下一轮，不算错过、不失效。
    - 不能因用户意外表现很好而事后新增候选、改变 evidence_mode 或升难。

20. **一节课只能有一个 lead primary，并限制辅助证据。**
    - 每个 training plan item 必须且只能有一个 lead_primary；它决定该课属于听、说、读、写中的哪个主技能位、为何进入计划，以及焦点的 2–4 课计数。
    - 最多再有一个 auxiliary_primary；它必须拥有独立、反馈前的首次回答，可以提供有效 target evidence，但不能把一节课算成两个焦点课，也不能满足“非焦点技能连续两轮内至少一次成为 lead”的要求。
    - 每课仍最多一个 difficulty_probe，而且只能属于 lead primary；另一个 primary 最多为 target_check。
    - “每轮听说读写各至少一条可评分证据”可以由有效 lead 或 auxiliary 的 target_check／difficulty_probe 满足；training、secondary、提示后回答和 not_assessable 均不满足。
    - 轮次复盘不属于六个 training item，不占主技能位，也不补这些比例。

21. **把 focus 作为覆盖在 R/B/E 之上的临时计划属性。**
    - 自动焦点依次选择：当前阶段最薄弱或阻塞最大的 Required；明显阻碍 Required 或即将在下一阶段成为 Required 的 Breadth；不自动选择 Extension。
    - Breadth 只有在妨碍当前交流、构成下一阶段先修或直接服务当前小目标时才能成为焦点；其 role 仍为 breadth，不能伪装成 required。
    - Extension 只有用户明确选择，或 TOEFL 等长期目标确需提前准备且轮次复盘明确安排时，才成为 user_focus_override 或 future_goal_focus；它不能替代当前 Required。
    - quality profile 焦点必须依附具体 competency_family／activity_family 组合，例如 S_ARGUMENT＋opinion_explanation＋coherence，不能只写“提高词汇”。
    - focus 和 role 只允许在轮次复盘或用户明确调整计划时改变。

22. **在轮次复盘冻结焦点强度。**
    - 默认 focus_intensity＝standard＝3 个 lead 主技能位。
    - light＝2 只用于基本解决后的跨情境巩固、Breadth 前置探索、用户选择的 Extension，或尚未造成 task_target_failed 的窄缺口。
    - intensive＝4 只有同时满足以下条件才可使用：两条跨日有效首次回答指向同一 core bottleneck；影响至少两个情境或阻塞 Required 先修；已经找到可教学原因与干预；四课使用不同材料或活动形式。
    - 多次 stretch 失败、一次极差表现、主观困难、AI尚不理解原因或为了收集升难证据，都不能单独升为 4。
    - 若四个焦点 lead 会破坏本轮四技能有效证据底线，或让某非焦点宏观技能连续两轮不能成为 lead，则自动降为 3，并用 auxiliary 补充，而不是破坏覆盖规则。
    - 强度只在轮次复盘生成下一轮时确定。轮中提前达成则把剩余焦点课用于迁移和巩固；表现恶化只改支架和任务条件，不增删或重排队列。

23. **按 R/B/E 控制自动适应权限。**
    - 三类 gate 使用相同任务标准，不因 role 放宽评分。
    - Required 非焦点和 Required 焦点均可执行 target check；兼容的未来 lead 可按状态机自动 stretch。
    - Breadth 非焦点可以 target check；达到资格后可把 progress_state 设为 probe_ready，但本轮不得临时生成 probe，由轮次复盘决定是否把它预授权为以后一个 lead probe。
    - Breadth 成为 focus 后启用完整状态机，但不能抵消 Required 缺口。
    - Extension 普通探索最多一项预声明检查，不形成自动 challenge 链，也不因失败产生长期 hold；只有正式 focus 才启用完整 target、stretch 和 hold。
    - B/E 焦点结束后保留状态但停止自动调度；以后再次启用时继续原状态。
    - Required 的 hold 只暂停升难，不停止原 target 教学和检查；不得转练同负荷轴的 B/E 来绕过。

24. **为六课轮次设置上限而非强制填满的证据机会包。**
    - 正常一轮约 8 个 evidence-bearing primary，正式 primary 的硬上限为 9，不把理论上的 12 个 primary 位置全部变成测验。以下 focus、R、B、修复和 E 都是对同一组唯一 primary slot 的用途标记，按 observation_id 去重，绝不把各行额度相加成 10 个以上。
    - 预留 2 个 focus evidence，分布在不同课；其余 focus 课可用于 training、支架撤除和迁移。尚不具备独立检查条件时可转为 training 并顺延，不能硬测。
    - 最多 4 个 non-focus Required rotation 位：优先让未被焦点覆盖的听、说、读、写各获一次 Required primary，再给等待最久的 Required competency_family。正常情况下非焦点 Required 最迟约四个完成轮次获得一次 primary。
    - 最多 2 个到期 Breadth rotation 位，不为填满位置制造任务；正常情况下约五个 Breadth competency_family 在三轮内各获一次 primary。
    - 另有 0–1 个状态修复／必要后续弹性用途。非焦点 Extension 没有额外容量，只能在没有到期 R/B、没有修复任务且总数低于 9 时，替代一个原本未使用的 rotation／弹性 slot；每轮至多一次。
    - 状态修复优先使用弹性位，不能让同一反复失败 competency_family 持续占用普通轮换位并饿死其他 competency_family。
    - 同一 role 内按“从未有有效 primary → 距上次最久 → curriculum 固定顺序 → competency_family_id”排序；除状态修复外，其他 eligible competency_family 未获机会前不得重复占位。
    - 有效首次回答无论成功或失败都表示已经获得轮换机会；not_assessable、技术故障、不可归因、提示后回答和未完成任务不推进游标。
    - 机会按完成的学习轮次计算，不按自然日；长期没学习不会积压。

25. **将 secondary 固定为低成本诊断雷达。**
    - 每个六课轮次预排 0–2 个 secondary，硬上限为 2，不是必须填满的配额；每课仍最多一个，不得增加额外回答或延长活动。
    - 选择优先级为：焦点先修／已知瓶颈 → 当前 Required 自然旁证 → 与小目标有关的 Breadth → 用户或长期目标明确关注的 Extension。
    - secondary 只记录 observed_secondary、met／not_met／not_assessable、最近观察轮次和供第5条使用的 observation ID。
    - secondary 不满足每轮四技能证据底线，不推进 R/B 的 primary 轮换游标，不替代两个 focus evidence，不更新任何 adaptation 状态。
    - secondary_met 不能清除 primary 缺口或推迟正式检查；secondary_not_met 只生成 needs_primary_confirmation 计划提示，最早在轮次复盘利用现有机会包确认。
    - 多次 secondary 失败也不能累积成 target_unstable。没有充分暴露能力或不可归因时记 not_assessable，不补题、不形成 carry-over。

26. **把无效证据与真实失败彻底分开。**
    - 歧义、技术／媒体故障、不可归因、条件不可比、提示污染或答案暴露，统一记 not_assessable 和 invalid_reason；不改变状态、不推进轮换。用户中断或未完成按本项最后一条单独处理，不归为 invalid。
    - 用户尚未看到或回答题目时，可更换一次等价 fallback；若能力、模态或条件改变，替代活动只能是 training。
    - 用户已经回答或得到提示后，不追加一道题“抢救证据”；正常反馈并继续课程。
    - 无效证据不阻止当前课或轮次完成；复盘只能写“证据不足、维持原状态”，不能推断退步。
    - 同一 competency_family 和目的的缺证折叠为一个 coverage_due，不复制旧课或形成欠课。下一轮最多一个全局 coverage_recovery，占既有弹性位。
    - 弹性位顺序固定为：target_unstable／获准 re-probe → 缺失 focus evidence → Required → Breadth → Extension。
    - 一次有效失败不触发模板处罚。相同 template、indicator 和 step 最近两次生成均不可评分，或最近三次中两次因系统原因无效时，进入 needs_contract_fix；只暂停该 template binding 的正式 evidence，不暂停整个 competency_family，后续改用已验证模板。
    - 用户中断且尚未完成时保留 pending checkpoint，不生成 observation 结果；明确放弃记 abandoned，不算失败、invalid 或模板故障。

27. **采用简化、可重建的数据实现。**
    - 扩展 learner/skill-evidence.tsv，使其成为 append-only observation／audit 事实表；一次首次回答只写一个 observation，不新增 activity-events.jsonl。
    - 每行必须显式保存 record_kind、event_seq、recorded_at、observation_id、ref_observation_id、idempotency_key、plan_item_id、activity_id、lead_or_auxiliary、evidence_mode、catalog／ladder／contract version、competency_id、competency_family、activity_family、indicator_id、anchor_id、role、focus_goal_id、template_id、adaptation_key、load_axis_id、planned／target／presented step、changed_dimension、task_fingerprint、day_id、comparability_group、content_id、context_id、primary_result、criterion_results_json、secondary_projection_json、task_result、core_result、challenge_result、validity、invalid_reason、cost_signal、planned／allowed／actual support、access profile 和必要的最短证据摘要。secondary_projection_json 只保存可为空的一项 secondary indicator、结果及其证据边界，不另写一条伪独立 observation。
    - record_kind 至少支持 observation、void、correction。void／correction 通过 ref_observation_id 引用原 observation，不覆盖历史；event_seq 决定同一 observation 的重放顺序，idempotency_key 防止重复提交。
    - learner/adaptation-state.json 是由 skill-evidence 重建的当前投影，不是第二份事实来源；只保存第12项的小状态、固定大小窗口和 projection_revision，Bootstrap 正常只读当前 key。
    - 取消单独的 .state/activity-transaction.json；`.state/current-session.json` 是课中 pending 状态的唯一权威，在有界 `pending_activity_batch` 中保存待提交 observation、幂等键和“待应用的投影变化”。真正独立的 WAL 只允许由第6条的 FinalizeSession／AbandonSession 在课末创建。
    - `.state/current-session.json` 同时保存 prepared activity package、题面哈希、是否已有首次回答、首次结果和 pending_persistence。`PrepareActivity` 在展示前只做一次轻量原子写；prepared 但无回答时可原样重显，有回答后不得重问。
    - 用户回答后，AI在同一次模型响应中先给出针对该回答的反馈；反馈前不得读写文件或调用工具。反馈后、进入下一个需要用户作答的步骤前，最多执行一次轻量 SaveActivityCheckpoint 保存 pending observation，不进行全量归约。
    - 一课结束只通过第6条统一的 FinalizeSession／AbandonSession 事务正式提交全部 observation；RecordActivityBatch 只能是该事务内部的幂等 phase，不能在活动 session 中被单独调用或形成第二个正式提交边界。用户已先获得反馈，归档失败只保留 pending_persistence，不要求重答。

28. **把 90 秒要求变成可验收的运行预算。**
    - 新增派生索引 `.state/bootstrap-index.json`，只由第6条统一 session 事务、轮次复盘或相关配置维护原子更新；ReviewBatch／RecordActivityBatch 只能作为统一事务的内部 phase，不能在课中独立更新索引。索引有界保存 queue head、next package 路径与哈希、按到期顺序排列的最多 10 个 review 候选及完整 due counts、当前 projection revision 和版本指纹。日期变化只在这个有界索引上推进到期游标，不扫描完整 vocabulary、error-log 或 review-history。
    - 指纹至少包含 next_plan_item_id、cycle_package_hash、adaptation_projection_revision、policy／catalog／ladder version、review_index_revision、study day 和 recovery flag。Bootstrap 只校验 checksum、指纹和 queue guard，再返回当前包、至多一个 preauthorized probe candidate 对应的 adaptation state 和有限到期 review；不得扫描 plan 历史、session、完整 skill-evidence、45 个 gate 或其他候选。
    - `.state/bootstrap-index.json` 采用原子替换，并保留一个上一代校验通过的有界副本。当前索引损坏、过期、projection 无法读取，或配置／目录／阶梯版本不匹配时，Bootstrap 不在启动关键路径重放历史或尝试迁移：只有上一代副本的 queue guard 仍与当前队首一致时，才使用其中同队首的 ready fallback training 并标记 rebuild_required；两个 guard 都无法确认时立即停止正式取证并报告维护需要，不能猜测或跳队列。
    - tracker 必须把 switch 前的全局 Read-AllData 改为按 action 懒加载；StartSession 只分配 ID、写 session stub／checkpoint、绑定课包骨架，不得同步 Rebuild、Validate、全历史归约或完整测试。PrepareActivity 再在展示前锁定最终实例。
    - 日课固定为六步：① Bootstrap／StartSession 锁包；② 到期 review；③ input；④ output；⑤ focused feedback／必要 retry；⑥ summary＋一次批量归档。每次用户回答到针对该回答的下一条反馈之间，计划内工具调用、文件读写、联网、历史搜索和第二次模型判断均为 0；状态归约和长期写入不能插入这条关键路径。
    - 用户可见反馈只说明本题是否完成、最重要的问题、帮助和下一动作；默认隐藏内部 progress_state、hold_phase、计数、fingerprint 和 CEFR gate 细节。只有用户主动查看进度或进行轮次复盘／测评时才解释必要的长期状态。
    - 收到“开始今日学习”时记录 request_started_at 和 deadline_at。项目可控路径的正常目标是首个可作答步骤不超过 30 秒，硬预算为 90 秒；Bootstrap 含适应查表的端到端本地路径不超过 5 秒，课末 reducer 另有不超过 5 秒的独立预算。
    - 外部材料在 `min(request_started_at＋60 秒, deadline_at－20 秒)` 仍未完成，或 metadata 不能验证时，立即展示已预编译的 ready_fallback_activity；不得再次联网、重新规划或继续等待，也不得把降级算作用户失败。平台调度、模型服务和用户网络等仓库不可控耗时单列 uncontrolled_latency_ms，不把不可控制因素伪装成代码可保证的上限。
    - 持久化超过约 10 秒时，用户应已看到反馈；只发送简短保存进度，不重复反馈或提前要求下一份作答。第6条负责进一步预加载与后台批处理，但不能改变本条证据语义。
    - 记录 bootstrap_latency_ms、material_ready_latency_ms、decision_latency_ms、persistence_latency_ms、uncontrolled_latency_ms、fallback_used 和 fallback_reason，用于发现退化。

29. **采用非追溯迁移，并固定启用边界。**
    - C0003 的已完成、进行中和待开始计划项全部不动，旧 session 继续按旧语义完成。
    - 在 C0003 轮次复盘建立目录版本、R/B/E role、默认 target step、`progress_state=target_building`、target_unstable＝false、user_hold／ceiling_reached 两个学习 flags 均为 false 的空投影，以及 C0004 六课活动包和 bootstrap index；从 C0004 起完整启用。
    - 不给历史 evidence 补造 task fingerprint、target 成功、stretch、hold、promotion 或 focus 关系；历史仍可由第5条用于长期分析。
    - 旧条件能一对一可靠映射时可保留 step；无法可靠判断时使用该 competency_family＋activity_family binding 的默认 target，并标记 migration_unknown，不推断成功或失败。
    - 目录／阶梯升级只有明确一对一映射才自动迁移；无法映射时保留旧状态并设 migration_review_required，禁止自动升降，待轮次复盘处理。

30. **按依赖顺序落地，避免一次重写全部系统。**
    1. 先建立并校验 competency catalog、R/B/E matrix、difficulty ladder、正交的 competency_family／activity_family binding，以及版本化 adaptation policy。
    2. 再扩展 data schema、单行 observation／secondary projection、追加式 correction／void、adaptation reducer、双轴投影重建和幂等批次。
    3. 先只定义并测试 cycle activity package、唯一 preauthorized probe candidate 和 ready fallback 的 schema／纯编译契约；此时不生成或发布运行缓存。
    4. 本步服从第6条第33点的正确性顺序：先完成 StartSession、ReviewBatch、FinalizeSession／AbandonSession 的统一事务与恢复边界，再实现并原子维护 `.state/bootstrap-index.json`，把 tracker 顶层 Read-AllData 改成按 action 懒加载，删除 StartSession 的同步 Rebuild，让 Bootstrap／StartSession 只读取当前有界小包。
    5. 上述正确性与懒加载测试通过后，再给 cycle plan 接入预编译 activity package、唯一 preauthorized probe candidate 和完整 ready fallback activity。
    6. 然后更新 SKILL.md、curriculum、rubrics、session／cycle review 模板和 dashboard 展示，并落实固定日课六步与用户可见信息边界。
    7. 最后迁移 C0003 复盘数据、生成 C0004 包和索引，并在启用前完成全套行为、恢复和性能测试。
    8. 第4条落地完成后，按第5条的既定规则将这些原子证据归约为 met／stable，并由第6条优化预加载和后台持久化。

31. **增加以下最低测试与验收。**
    - 目录 ID 唯一；15 个 competency_family、45 个 gate、每 gate 2–3 indicator、R/B/E matrix、官方来源及 project_operationalization 标记一致；第2条八个 activity_family 与 competency_family 分字段保存，TOEFL adapter 必须同时映射二者。
    - ladder 每维 3–5 阶、单调、只允许相邻变化；每个 competency_family＋activity_family binding 首版最多两个维度；共享 load axis 无法换名绕过。
    - 契约引用全部有效，ResolveActivityInstance 只能按版本化 adapter 派生阈值；用户看到题目后无法修改 criteria、mode、support 上限或 fingerprint。
    - 一课最多一个 preauthorized probe candidate；Bootstrap 只验证该候选、不枚举替补。轮中新增 probe_ready 或 hold_phase＝release_ready 不触发临时 probe，失效候选只会降为 target_check／training。
    - task_result 与第2条映射一致；core_result 只接受 met／not_met／not_assessable，scoring_uncertain 转为 not_assessable，non_comparable 只出现在 validity。局部三单、冠词或搭配错误只有命中预声明 core_floor 中的 essential criterion，或影响意义时才使 core 失败。
    - stretch_not_ready 必须 core met 且 challenge 未达；stretch_overload 必须由有效表现命中预声明客观 overload 条件，用户主观停止单独不能成立。两条 target 成功必须跨日／跨语境；high 延后 probe，unknown 不满足 normal 配额；同日重复、guided、revised、secondary、invalid 和 non_comparable 不计数。
    - progress_state 只接受 target_building、probe_ready、confirmation_building、promotion_hold；旧 pending 状态不会重新出现。第一次 stretch、两次 stretch＋中间 target、promotion 后 consolidation 的转换准确。
    - probe 的 F-S-F 进入 promotion_hold，overload 立即 hold；hold 三次成功必须跨三日、两语境、至少两次 normal，并须轮次复盘预授权。hold_phase 完整覆盖 recovering → release_ready → first_probe_met → confirmation_ready → 第二次 probe。
    - target 最近三次中跨日两败只设置 target_unstable 覆盖层并保存 resume_progress_state。若它打断 promotion_hold，旧 first_probe_met／confirmation_ready 不得恢复，hold_phase 必须重置为 recovering；两条跨日／跨语境的 unstable 恢复成功只作为 hold 三条恢复证据中的前两条。无 hold 时还必须通过一条更晚的新语境 target，才能重新检查 probe_ready。
    - user_hold、recovery、ceiling、自然时间不失效和一课最多一个 probe 正确。cost_signal 不可由异步消息间隔推断。
    - capability_probe 只能来自 cycle／assessment plan，不能与 condition stretch 共用 activity，不读写 adaptation state，其结果只流向第5条长期证据。
    - purpose／evidence_mode 兼容表会拒绝 practice→difficulty_probe、assessment／capability_probe→adaptation 等非法组合。
    - primary／auxiliary／secondary 上限、单行 secondary_projection_json、综合任务不复制证据、focus lead 计数、四技能底线和 R/B/E 权限正确；observation／void／correction 可按 event_seq 确定性重放且幂等。
    - opportunity package 各用途按 observation_id 去重而非相加，正常约 8、正式 primary 硬上限 9；Extension 只能替代未用 slot，R/B 轮换与公平性正确。
    - not_assessable 不罚用户、不推进游标；用户中断保持 pending 而不是 invalid；fallback 降为同队首 training；模板反复无效只隔离模板。
    - PrepareActivity、SaveActivityCheckpoint 和 FinalizeSession／AbandonSession 内部的 RecordActivityBatch phase 幂等；prepared 无回答可原样重显，已有回答不重问、不重复计数；重放 skill-evidence 得到相同 adaptation-state。
    - `.state/bootstrap-index.json` 及其上一代校验副本只含有界 queue head、next package、最多 10 个 review 候选和版本指纹；文件读取 spy 证明 Bootstrap 不访问历史 plan、session、完整 skill-evidence、vocabulary、error-log、review-history、dashboard、完整 catalog 或其他候选。配置版本不匹配时，只有副本 queue guard 一致才选择同队首 ready fallback training；否则快速停止正式取证。
    - C0003 不变、历史不回填、C0004 才启用；未知版本映射不会自动升降。
    - 端到端启动测试包含 CLI 进程开销：Bootstrap 含适应查表不超过 5 秒；fast fake provider 下首题不超过 30 秒；虚拟时钟＋永不返回的 provider 会在绝对截止前选择预编译 fallback，项目可控逻辑时间不超过 90 秒。课末 reducer 单独不超过 5 秒。
    - 固定日课六步准确；任一普通文本回答到反馈之间无工具、文件、网络、全库扫描、第二次模型或状态归约。持久化延迟不阻塞已经生成的反馈，用户界面默认不暴露内部 state、count、fingerprint 或 gate。
    - 任一难度状态变化都不改变 next_plan_item，也不改变 review 的题目、评级、到期或队列。

### 5. 建立证据分级、可回退的长期能力与教学洞察层

> **与其他条目的边界：** 第1条定义课程阶段、焦点目标、六课轮次、R/B/E 角色和需要用户确认的计划变化；第3条只管理独立的原子复习及其描述性趋势；第4条负责预冻结活动契约、生成一次回答的原子 observation，并独占课内任务条件难度状态。本条只在轮次复盘或正式测评中汇总这些既有事实，形成焦点目标决定、CEFR gate 当前状态、技能阶段达成事件和可执行教学洞察。第6条进一步优化预加载和持久化，但不得改变本条的证据语义、权限和判定门槛。

#### 修改前的问题具体体现

- `sessions/` 记录课程过程，`skill-evidence.tsv` 记录细粒度表现，但系统尚未明确多条证据何时足以证明焦点目标达标或某项 CEFR 能力稳定。
- “一次做对”“提示后改对”“原子知识仍记得”和“能在新语境独立完成宏观任务”容易被混为同一种掌握，可能造成过早换目标或升阶段。
- dashboard 的教师备注承担了部分长期判断，但没有固定的证据门槛、反证处理、版本关系和可审计的取代机制。
- 单次失误、挑战更高难度失败或一段时间没有学习，可能被错误解释为能力退步；反过来，大量低质量旁证也可能掩盖 Required 门槛中的真实缺口。
- AI选择下一焦点时缺少“能力缺口、证据缺口、先修阻塞和长期价值”的稳定排序，容易受最近一次表现影响。
- 为决定怎样教，AI可能需要扫描大量旧 session 和备注，既拖慢日课，也容易因上下文不同得出不一致结论。
- 当前没有明确区分“客观能力状态”和“如何教学的洞察”；如果洞察越权，可能静默改变复习、队列、难度或长期计划。

#### 修改后预期执行时实现的具体效果

- 系统形成单向、可追溯的判断链：原子 observation → 焦点目标／competency gate 状态 → 教学洞察与下一轮建议，不允许后层凭印象改写前层事实。
- 焦点目标达标、CEFR gate 稳定、技能阶段达成和“怎样教更有效”成为四种不同结论，不再自动互相推出。
- 只有跨学习日、跨语境、首次独立且满足冻结条件的直接证据可以形成 `met / stable`；复习、提示后答案和支架练习各自在适当边界内发挥作用。
- 一次失败只触发观察，稳定能力只有经过重复反证和正式确认后才会降级；历史达成永久保留，当前需要修复的能力单独显示。
- 轮次复盘能稳定地区分确认的能力缺口与证据不足，给出下一焦点首选、依据和备选，由用户确认计划变化。
- 教学洞察可以自动改善支架、反馈和等价材料选择，但不能越权改变严格队列、复习、CEFR 状态、R/B/E 或难度状态。
- 普通日课不扫描长期历史、不运行长期归约，也不在用户回答到反馈之间增加工具调用或第二次模型判断。

#### 建议如何修改

1. **固定四种长期结论，禁止自动级联。**
   - `focus_goal` 是持续 2–4 个完成轮次的局部干预目标，轮次决定只能是 `met / continue / redesign / insufficient_evidence`。
   - 一个 `competency_id` 就是一个 `competency_family × CEFR level` gate；当前状态只能是 `not_evidenced / developing / stable`，不得再建立语义重复的“gate stable”和“competency stable”。
   - 听、说、读、写分别拥有技能阶段。只有某技能当前等级全部 Required gate 均为 `stable`，且没有阻塞本次达成判断的确认或维护标记，才产生该技能的阶段达成候选。
   - `learning insight` 只描述“在什么条件下怎样教可能更有效”，不得重复保存“学习者已经是 B1”之类能力结论。
   - `focus_goal met` 不自动使 gate `stable`；gate `stable` 也不自动关闭标准或情境并不等价的焦点目标。
   - Breadth 和 Extension 不阻塞阶段达成，也不能抵消任何 Required 缺口；不计算掩盖偏科的听说读写平均 CEFR。

2. **让 tracker 根据冻结事实确定证据等级，AI不得凭印象分类。**
   - 长期 reducer 从第4条 observation 的 `record_kind`、`evidence_mode`、`purpose`、`validity`、`primary_result`、`core_result`、`lead_or_auxiliary`、`support`、`model_exposed`、`cost_signal`、版本、anchor、day 和 context 等字段确定 `evidence_class`。
   - 证据必须引用唯一 `observation_id`；没有证据 ID 的 session 总结、教师印象或 dashboard 文字不能进入客观状态归约。
   - `void / correction` 通过事件重放修正结论，不覆盖原事实，也不允许人工直接改最终状态来绕过 reducer。

3. **采用 A、B、C 三类证据，并限制各自能证明什么。**
   - **A 类 direct evidence：** 有效、可比、首次、独立、未经反馈或答案暴露的 primary 表现；包括当前 anchor 的 `target_check`、预排 `capability_probe`、正式 assessment，以及 `difficulty_probe` 在当前 anchor 上的 `core_result`。A 类必须符合冻结的正常允许条件；超出允许支架后只能降为 C 类或 not assessable。
   - **B 类 supporting evidence：** 答前声明的 secondary、自然出现但不是正式 primary 的迁移表现、原子 review 的去重趋势和用户自报。B 类可以支持教学判断或触发 primary confirmation，但不能单独形成 `focus_goal met`、gate `stable` 或阶段达成。
   - **C 类 teaching evidence：** `training`、guided、revised、retry、repair、示范后表现和支架前后对照。C 类可以证明某种教法是否可能有效，但不能证明独立能力。
   - invalid、non-comparable、not assessable、abandoned、重复提交和已 void 的记录不属于有效 A/B/C 结论。
   - `difficulty_probe` 的 challenge 成败、promotion、hold 或 ceiling 不能成为 CEFR 升降依据；只有其当前 anchor 的 core 表现可能成为一条 A 类证据。
   - 第3条 review 只证明词汇、搭配或结构等原子项目的保持；即使长期趋势很好，也不能单独证明宏观听、说、读、写 gate。

4. **为每个焦点目标冻结一个窄而可测的 goal contract。**
   - `focus-goals.tsv` 的每个版本记录关联 competency／indicator、一个主要成功标准、最多两个不得退化的 guardrail、baseline、适用 activity/context、最少 2 轮、最多 4 轮、一次预排 focus confirmation 和 1–2 个 progress marker。
   - 目标必须能在具体任务中观察，例如 `S_ARGUMENT + opinion_explanation + coherence`，不能只写“提高口语”或“增加词汇”。
   - 目标版本激活后不能事后放宽标准；若构念、必要标准或关键情境改变，追加新版本并记录 `redesign`，不覆盖旧目标。

5. **采用保守的焦点目标达标门槛。**
   - 目标至少已经完成 2 个轮次。
   - 至少有 3 条去重的 A 类成功证据，分布在至少 2 个学习日和 2 个不同 context instance；换人名或表面词汇不算新语境。
   - 每个必要标准至少被两条 A 类证据覆盖；同一 observation 可以同时观察已冻结的多个必要标准，但对同一 reducer 只能计数一次。
   - 至少一条来自预排的 focus confirmation，且 `cost_signal=normal`；high 或 unknown 可以保留为表现，但不能承担最终确认。
   - 最近的决定性证据之后不存在未解决的同 anchor A 类 `not_met`，guardrail 没有退化。
   - 只有轮次复盘可以提交 `met`；提前出现足够表现时，本轮剩余焦点课用于迁移和巩固，不在轮中换目标或重排队列。
   - `met` 使当前 goal version 成为终态。以后退步时创建新的 maintenance／repair 目标或版本，不重开并改写历史达成事件。

6. **把“明显进步”限定为预声明的可复核变化。**
   - `criterion_acquired`：同一必要标准从未达到变为后来跨日独立达到。
   - `support_withdrawal`：减少或撤除一个预声明支架级别后，目标表现仍保持。
   - `context_transfer`：在保持 core 和 guardrail 的前提下，首次在新的 context class 独立成功。
   - 单次做对、revised 变好、guided 成功、难度 promotion、主观印象或平均分小幅变化都不能单独叫“明显进步”。
   - 同一个 progress marker 对同一轮次只计一次，必须引用对应 observation ID。

7. **确定 `continue / redesign / insufficient_evidence` 的算法。**
   - 每轮至少要有 2 个与焦点目标直接相关、预先安排的有效 A 类 opportunity，才足以判断本轮进展。
   - 少于 2 个有效机会时记 `insufficient_evidence`；歧义题、技术故障、not assessable 和计划未执行不能算作用户没有进步。
   - 未达标但出现新的 progress marker 时记 `continue`。
   - 证据充分但没有新 marker 时，第一次记 `continue` 和 `no_effective_progress_streak=1`，下一轮只改变一个教学变量，便于判断干预是否有效。
   - 连续两个证据充分的轮次没有明显进步，或到第 4 个完成轮次仍未 `met`，必须 `redesign`：拆小目标、补先修、换教学方法或修复取证设计，不能原样续期。
   - `insufficient_evidence` 不计入无进步连续次数，但到第4轮仍持续证据不足时也必须重设 evidence/activity contract，不能无限延期。

8. **将 gate 当前状态与确认／维护标记分开。**
   - `competency-status.tsv` 只保存 `not_evidenced / developing / stable` 的当前投影。
   - `watch`、`confirmation_due`、`maintenance_due` 和 `migration_review_required` 是独立 flags，不是第四、第五种能力状态。
   - 每个状态或 flag 变化必须引用决定性 observation／event ID、indicator、anchor 和 catalog version。
   - 缺少证据是 `not_evidenced`，存在直接但尚不足的证据是 `developing`；不得把“没有测到”写成失败。

9. **采用逐 indicator 的 gate stable 门槛。**
   - Gate 的每个必要 indicator 至少需要 2 条 A 类成功，来自不同学习日和不同 context instance，且至少一条 `cost_signal=normal`。
   - Gate 整体还必须至少有一次当前 anchor 上预先安排的 `capability_probe` 或正式 assessment；该确认应来自最近 4 个完成轮次。
   - 一次 capability probe 只证明它实际测量的 primary indicator，不能一题宣布整个 gate 或整项技能稳定。
   - 其他 indicator 的兼容证据可以在当前 catalog／anchor 版本内逐步积累，不因短窗口机械清空，但不能存在未解决冲突、确认到期或迁移不明。
   - B/C 类数量再多也不能填补任一 A 类门槛；不同 indicator、强项或技能之间不得通过加权平均互相抵消。

10. **使用两步确认处理反证，避免一次失误夺走 stable。**
    - 只有同 `competency_id + indicator_id + anchor_id`、有效、首次、独立且条件可比的 A 类 `not_met` 才是直接反证。
    - stable 后第一次出现直接反证：保持 `stable`，设置 `watch`。
    - 同一 indicator 最近 3 条可比 A 类证据中有 2 条跨学习日、跨语境 `not_met`：仍保持 `stable`，设置 `confirmation_due`，在未来已有计划位中安排一次 capability confirmation。
    - 确认 not assessable 时保持原状态和 flag；确认成功且成本 normal 时清除冲突；确认仍 `not_met` 时当前状态才降为 `developing`。
    - review 失败、secondary、training、guided、revised、retry、局部语言小错、high-cost 成功、更高等级任务失败以及 stretch 的 challenge 失败都不能作为当前 gate 的直接反证。
    - 一条 correction／void 使关键证据失效时，通过重放重新生成候选状态，不手工修补计数。

11. **按完成轮次维护证据新鲜度，不按自然时间惩罚停学。**
    - stable gate 连续 4 个完成轮次没有新的 A 类证据，或其某个必要 indicator 连续 8 个完成轮次没有 A 类证据时，设置 `maintenance_due`；没有学习的自然日不推进计数。
    - `maintenance_due` 不立即降级、不制造 backlog、不插入当前严格队列，也不改变第3条 review 的到期和抽取。
    - 后续轮次只利用既有 rotation／flex capacity 安排一个确认机会；多个到期 gate 按 Required、阻塞性和等待轮次轮换，不能持续挤占正常训练。
    - 新的有效 A 类成功可以恢复 current；新的失败进入第10项冲突流程，而不是一次直接降级。
    - 有 `maintenance_due` 或 `confirmation_due` 的 gate 不参与新的阶段达成判断，但不会撤销既有历史 attainment。

12. **把当前回退与历史达成分开保存。**
    - 某技能当前等级全部 Required gate 稳定且 flags 不阻塞时，tracker 产生 `stage_attained_candidate`；轮次复盘校验证据后直接追加不可变的 `stage_attained` 客观事件，并另行产生 `next_stage_plan_ready` 建议。用户确认只决定是否采用下一阶段计划，不决定或改写已经满足门槛的客观达成事实。
    - 后续某 gate 降回 `developing` 只更新该 gate 的当前状态，界面显示“曾达到该阶段，当前有待修复的 gate”。
    - 不删除旧 `stage_attained`，不自动降低第4条 condition step，不改变 R/B/E role，不把其他 gate 一并降级，也不回滚或重排严格队列。
    - 回退只在轮次复盘形成 maintenance／repair focus 建议；用户未确认计划变化前，继续执行原队首。

13. **禁止重复计数和跨版本偷渡。**
    - reducer 使用至少 `observation_id + projection_kind + competency_id + indicator_id` 去重。
    - 同一 observation 可以分别被 focus、gate 和 insight reducer 引用，但在每个 reducer 内只能计一次；由总结或 projection 生成的二手行不能再冒充一条独立表现。
    - 同一次回答的 primary 与 secondary 仍是一个 observation；secondary 不能变成第二条 A 类证据。需要两条 A 类时必须有两个独立回答边界。
    - Review trend 只引用 review event ID，不把相同结果复制到 `skill-evidence.tsv`。
    - A 类证据必须匹配当前 goal／catalog／indicator／anchor version。只有明确的一对一映射可以继续保持资格；无法映射时保留历史并设置 `migration_review_required`。
    - 更高 CEFR anchor 上的成功不会自动回填低级 gate；第4条相邻 condition step 的结果也不会自动推出 CEFR 等级。

14. **先区分能力缺口、潜在缺口和证据缺口。**
    - 同一 indicator 至少有两条跨日、跨语境 A 类 `not_met`，才称为 `confirmed_ability_gap`。
    - 只有一条直接失败，或主要依据 B/C 类信号时，只能称为 `potential_gap`，先建议 primary confirmation，不能直接宣称它是“最薄弱项”。
    - `not_evidenced`、`maintenance_due`、大量 invalid 或缺少可比任务属于 `evidence_gap`；它们获得 coverage／probe 机会，但不能伪装成能力失败。
    - 如果没有证据充分的能力缺口，下一轮使用 diagnostic focus 或继续当前目标补证，不按最低小样本分数选弱项。

15. **使用字典序而不是加权总分选择最高优先级缺口。**
    - 第一层：当前阶段 Required gate 的已确认回退或正式确认失败。
    - 第二层：明确阻塞一个或多个 Required gate 的先修缺口，包括确实承担先修作用的 Breadth。
    - 第三层：其他当前 Required 的 confirmed ability gap。
    - 第四层：Required 的 evidence／maintenance coverage。
    - 第五层：其他 Breadth；Extension 只有用户或长期目标已经授权时才进入候选。
    - 同层依次比较：沟通影响与 core 严重度、阻塞的下游 Required 数量、跨任务／语境复发广度、证据质量和新鲜度、等待轮次、curriculum 固定顺序和稳定 ID。
    - 轮次复盘展示首选、引用证据、选择原因和一个备选；用户确认的是下一焦点和计划，不是通过选择结果改写客观 evidence 或 gate 状态。
    - 本算法只生成下一轮建议，不改变正在执行的六课严格队列。

16. **第一版只允许四类狭窄、可证伪的教学洞察。**
    - `bottleneck`：一个上游问题反复阻碍多个相关活动。
    - `support_effect`：某种具体支架在什么条件下有效或无效。
    - `transfer_pattern`：能力在哪些任务／情境可迁移，在哪些边界仍不稳定。
    - `cost_pattern`：学习者可以成功，但某种冻结条件持续产生 high cost。
    - Insight scope 只使用已有的 skill、competency、indicator、activity_family、quality dimension、context class 和 support profile；必须选择能解释证据的最窄范围。
    - 禁止“视觉型学习者”“不擅长语法”“在压力下总是不好”等宽泛人格标签，也不把一次覆盖知识点写成长期洞察。

17. **建立版本化、只追加的 insight 生命周期。**
    - `learner/learning-insights.tsv` 至少记录 `insight_id`、`insight_key`、`version`、type、scope、claim、evidence IDs、counterevidence IDs、teaching implication、status、freshness、created／last confirmed cycle 和 supersedes 关系。
    - 状态使用 `candidate / active / watch / superseded / retired`。普通日课只能产生 candidate signal；只有轮次复盘或 assessment 可以激活、质疑、取代或退役。
    - `insight_key = claim_type + scope + target`；同 key 的新证据合并到同一版本，同一时刻最多一个 active 版本。claim、scope 或教学含义实质改变时追加新版本，不能覆盖旧行。
    - bottleneck、transfer 和 cost 洞察至少需要两条跨学习日的相关证据；support effect 至少需要两组可比的“无／低支架表现与使用同一明确支架后的表现”，并包含一次支架减少或撤除后的结果，不能从一次提示后成功推出。
    - 一条可信反例使 active insight 进入 `watch` 并暂停自动使用；两条跨日可比反例或经审计确认的用户纠正，才创建更窄／相反版本并 supersede。
    - Candidate 连续 2 个完成轮次没有新证据时 retired；active 连续 4 个完成轮次没有支持证据时转为 stale watch、停止自动注入，但不宣告原 claim 错误。自然时间不推进这些窗口。
    - 第一版最多保留 12 条 active、每个 competency 最多 2 条；每轮最多处理 3 项 insight 状态变化，超出者按相关性顺延而不是丢弃。

18. **只让 active insight 自动改变低风险、可逆的教学选择。**
    - 在既有 activity contract 和已批准计划内，active insight 可以选择允许的训练支架、反馈 adapter／优先级，以及满足同一约束的材料主题或等价情境。
    - 每条 directive 必须记录 action code、参数、适用条件、不适用条件和来源 insight version；冻结的 target／probe contract 永远优先，冲突时忽略 directive 或降为 training。
    - 每个相关 activity package 最多编译 3 条 directive；不把完整洞察库塞入日课上下文。
    - Insight 不得自动改变严格队列、review 内容／评级／到期、focus goal、技能占比和强度、CEFR 状态、R/B/E、长期目标、condition step／hold，也不得临时发起 assessment 或 capability probe。
    - 焦点变化、目标 redesign、阶段方向、显著技能占比、Extension 焦点、R/B/E／curriculum 变化和额外 capability probe，必须由轮次复盘给出首选、证据和备选，经用户确认后才生效。

19. **由确定性 reducer 产生状态候选，AI只解释和提出计划。**
    - 新增 `EvaluateLongTermState`，只在 cycle review 或 assessment 收尾运行；它根据事件重放产生 `met_candidate`、`stable_candidate`、`confirmation_due`、`maintenance_due`、conflict、stage transition 和 insight candidate。
    - AI不能凭自然语言印象直接写 `met / stable`。轮次复盘先校验证据有效性和版本，再提交客观状态事件。
    - 用户无需逐条批准客观证据归约，但界面必须展示决定、关键门槛、evidence IDs 和反证；用户可以请求审计或纠正事实。
    - 用户自报不能制造 `stable`。用户可以拒绝升阶段、换焦点或改变计划；拒绝只影响计划采用，不改写证据和客观状态。
    - 用户质疑证据时设置 `audit_pending`，暂停依赖争议证据的计划变化；核对后通过 correction／void 重放，不手工编辑事实或最终状态。

20. **采用单一事实来源、事件历史和可重建投影。**
    - 保留第1、4条已经确定的 `learner/skill-evidence.tsv`、`learner/focus-goals.tsv`、`learner/goal-events.tsv` 和 `learner/competency-status.tsv`，不改成另一张重复的统一事实表。
    - 新增只追加的 `learner/competency-events.tsv`，保存 gate 的 stable、watch、confirmation、maintenance、downgrade 和 restore 历史。
    - 新增只追加的 `learner/stage-events.tsv`，保存不可删除的分技能 `stage_attained` 事件。
    - `learner/learning-insights.tsv` 保存版本化 insight 历史，不另设一份可手工修改的“当前洞察事实”。
    - `learner/long-term-projection.json` 只是由上述事实重建的当前缓存；每个 focus／competency／indicator key 最多保留最近 6 条相关有效 primary 摘要及固定大小反证窗口。
    - `.state/current-cycle-evidence.json` 只保存本轮最多 6 课 × 每课 3 个 evidence projection 引用、review 原子汇总引用和 projection revision，不复制长文本。每课的上限实际由第4条的最多 2 个 primary observation ID 加最多 1 个嵌入式 secondary projection 构成；secondary 继续引用父 observation，绝不生成第三条伪 observation。
    - `.state/long-term-transaction.json` 保存 decision/event ID、待提交事件和幂等键；中断后恢复不得重复写事件或重复改变状态。

21. **把长期归约移出普通日课关键路径。**
    - 普通回答的 task result、issue 仲裁、即时反馈和可选 `candidate_signal` 在第2条规定的同一次模型响应中完成；candidate signal 只允许 `repeated_bottleneck / support_helped / support_failed / transfer_gap / maintenance_risk` 等固定类型。
    - 用户回答到针对该回答的下一条反馈之间，长期层工具调用、文件读写、联网、历史搜索、第二次模型判断和 reducer 调用均为 0。
    - 一课最多处理第4条允许的 2 个 primary observation 和 1 个嵌入式 secondary projection。`FinalizeSession` 及其内部 `RecordActivityBatch` phase 只增量维护有界投影和本轮 manifest；后者不能在活动 session 中独立正式提交。两者都不生成自然语言洞察、不提交 `met / stable`，也不扫描完整历史。
    - 普通日课默认隐藏内部 gate、flag、计数和 insight 生命周期；只有查看进度、轮次复盘或 assessment 时按需解释。
    - 长期持久化失败使用既有 `pending_persistence` 恢复机制，不能延迟用户反馈、要求重答或改变当前队首。

22. **让轮次复盘和 Bootstrap 只处理有界小包。**
    - 一次 cycle review 的长期 evidence packet 最多包含本轮 18 个 evidence projection 引用（最多 12 个唯一 primary observation ID 加最多 6 个嵌入式 secondary projection）、当前 goal projection、当前等级至多 15 个 competency family 的摘要、相关 active／watch insight 和 review 的原子趋势摘要，序列化硬上限为 64 KB。
    - `EvaluateLongTermState` 每轮只运行一次，每轮最多提交 3 项 insight 状态变化；其余候选保留到以后，不为一次复盘扫描全部 session。
    - 下一轮 activity package 最多包含当前 focus 摘要、与该课直接相关的 gate 状态和 3 条已编译 directive。`Bootstrap` 只从 `bootstrap-index.json` 读取这个有界投影，不打开完整 insight、goal、competency、session 或 skill-evidence 历史，也不扩大第4条既定的 review 候选和唯一预授权 difficulty probe 上限。
    - 长期 projection 缺失、损坏或版本不匹配时，不在启动关键路径全库重算；继续同队首已冻结的安全 fallback training 并标记维护需要，或在 queue guard 无法确认时停止正式取证。
    - 本条不得突破第4条的性能预算；第6条只负责进一步减少预加载和归档等待，不得用提速为理由放宽证据门槛。

23. **让 dashboard 展示结论依据，而不是伪精确总分。**
    - 只展示当前 focus、听说读写各自的 Required gate 概况、confirmation／maintenance 标记、历史 stage attainment、下一焦点候选和最多 3 条最相关 active insight。
    - 不显示听说读写平均 CEFR，不把 internal gate 换算成精确 TOEFL 分数，也不显示没有校准依据的百分比置信度。
    - 证据充分度只使用 `insufficient / supported / confirmed` 等类别，并同时显示决定性样本数、跨日／语境范围和最近确认轮次。
    - 旧教师备注保留为历史文本，不再自动进入 active insight；新结论必须可追溯到事件和 evidence ID。

24. **采用非追溯迁移，并保持 C0003／C0004 边界一致。**
    - C0003 的已完成、进行中和待开始计划项、session、review、队列和第4条状态全部不改写。
    - 在 C0003 轮次复盘创建 competency／stage／insight 事件文件、初始 projection、首个正式 goal contract 和 C0004 的长期 evidence 配置；C0004 起完整启用。
    - 缺少新冻结 contract、indicator、context、support 和 version 字段的历史记录不能回填成 A 类，也不能制造 `met / stable / stage_attained`。
    - 旧 assessment、教师备注和 CEFR 描述只保留为 `legacy_context`、B 类规划线索或 candidate hypothesis，用于安排以后确认，不成为 active insight 或客观稳定状态。
    - 初始 gate 默认为 `not_evidenced`；旧 CEFR 继续标注为“迁移前估计”，直到新协议证据形成当前状态。
    - Catalog／anchor 更新只有一对一映射时才能迁移当前投影；无法映射时保留历史并设置 `migration_review_required`，不自动升级或降级。

25. **按依赖顺序落地，避免一次重写全部系统。**
    1. 先在现有 schema 上补齐长期 evidence 分类、goal contract、competency／stage／insight event 和投影字段。
    2. 实现 A/B/C eligibility、去重、版本迁移、focus、gate、冲突、新鲜度和 insight 的纯 reducer，并用固定 fixtures 验证。
    3. 实现幂等 `EvaluateLongTermState` 和 long-term transaction，再接入 cycle review／assessment；普通日课只增量写 observation 和 candidate signal。
    4. 更新 cycle review 模板、curriculum 状态说明、dashboard 和下一轮 activity package 编译，让用户能看到首选、备选及证据。
    5. 将有界 projection 和最多 3 条 directive 接入 `bootstrap-index.json`，验证日课关键路径没有新增历史扫描或模型调用。
    6. 在 C0003 轮次复盘生成空投影和 C0004 配置，完成迁移验证后再启用。

26. **增加以下最低测试与验收。**
    - A/B/C 分类由冻结字段确定；invalid、void、revised、guided、secondary 和 review 不会误入 A 类，同一 observation 不会重复计数。
    - `difficulty_probe` 只投影当前 anchor core，challenge、promotion 和 hold 不改变 CEFR；capability probe 与 condition stretch 不能共用 activity。
    - Focus 的最少 2 轮、3 条 A、跨日、跨语境、逐标准覆盖、normal-cost confirmation 和无未解决反证条件逐项生效。
    - `met` 不自动 `stable`；gate `stable` 不自动关闭不等价 focus。
    - 每个 indicator 两条 A、跨日／语境、normal 配额和近期 capability／assessment 门槛逐项生效；B/C 和强项不能抵消缺口。
    - 一次反证只 watch；最近三次中两次跨日／语境失败只 confirmation due；正式确认仍失败才 downgrade。历史 attainment、队列、第4条 step 和其他 gate 不回滚。
    - 新鲜度只按完成轮次推进；停学不失败、不积压，maintenance 不直接降级，也不改变 review。
    - Progress marker 只由预声明可比证据触发；证据不足、连续无进步和第4轮未达标分别得到正确决定。
    - 能力缺口、潜在缺口和证据缺口不会混淆；字典序排序可稳定复现，并始终返回首选、备选和 evidence IDs。
    - Insight 的 candidate／active／watch／superseded／retired、scope、版本、反证和 stale 规则准确；support insight 不会被转写成独立能力。
    - 自动 directive 只改变允许的可逆教学选择；任何 insight 都不能改变 review、queue、focus、allocation、CEFR、R/B/E、adaptation 或临时启动 probe。
    - 用户自报不能制造 stable；用户拒绝计划变化不改写客观状态；audit 通过 correction／void 重放得到一致投影。
    - Required 全 stable 且无阻塞 flags 才追加分技能 `stage_attained` 客观事件并提出下一阶段计划；Breadth／Extension 不阻塞也不抵消，不存在四技能平均等级，用户拒绝新计划也不删除客观达成事件。
    - 长期事务中断后幂等恢复；重放事件得到相同 goal、competency、stage 和 insight projection。
    - C0003 不变、历史不回填、C0004 才启用；未知版本映射不会自动升降。
    - 文件读取 spy 证明普通日课不运行长期 reducer、不扫描完整历史，Bootstrap 只读有界 index、每课最多注入 3 条 directive；轮次 evidence packet 不超过 18 个 projection 引用和 64 KB，且最多只引用 12 个唯一 primary observation ID。

### 6. 用滚动预加载、轻量草稿与单次事务消除课程卡顿

> **与其他条目的边界：** 第1条继续独占严格队列、焦点目标、轮次计划和需要用户确认的计划变化；第2条继续独占活动契约、回答判定、问题仲裁和即时反馈；第3条继续独占原子 review 的抽取、题型、评级与长期排程；第4条继续独占 observation、任务条件难度、适应状态、活动包语义和90秒启动预算；第5条继续独占 `met / stable`、CEFR gate 和长期教学洞察。本条只实现预生成、缓存、临时恢复、正式提交、按 action 懒加载、失败降级和性能观测。任何提速都不得改变题目标准、首次判定、证据资格、review 语义、next plan item 或上述权力边界。

#### 修改前的问题具体体现

- 用户输入“开始今日学习”后，进入 review 前常等待约1–2分钟；review 转入 input/output 时还可能再次等待约1–2分钟。
- 课中保存证据有时需要30–60秒，工具或环境错误还会触发重复尝试，持续打断注意力。
- 本次代码审计发现，tracker 在 action 分发前无条件执行全量 `Read-AllData`；即使 `Checkpoint` 只需写一个小文件，也会先读取多张表和全部 session。
- `StartSession` 当前按顺序写 session stub、整张计划和 checkpoint，并同步 `Rebuild`；中途失败可能形成跨文件半状态或重复 session。
- `ReviewBatch` 的幂等性只覆盖原 pending 文件的重放；若调用已经成功但响应丢失，重新调用可能生成新 ID、重复评级或覆盖旧 pending。
- `FinalizeSession` 当前依赖 AI 预先手工修改多份记录，并在完整重建／验证前就更新 plan 和 checkpoint；后段失败后可能出现“队列已前进，但事实没有完整提交”的状态。
- 当前 checkpoint 只保存阶段和短备注，没有保存题面哈希、首次回答判定、已经展示的反馈、repair 等待点和待提交事实，无法可靠做到断线后不重问。
- 当前资源策略要求开课时同步检查网络页面，与“上一课已经准备好下一课”存在延迟冲突。
- 当前数据规模较小时，本地热读取通常远低于一分钟；分钟级卡顿的主要来源是重复工具往返、联网、模型编排和环境失败。只把原有正式写入挪到 feedback，不能单独解决问题。

#### 修改后预期执行时实现的具体效果

- 用户开始学习时优先命中上一节课准备好的同队首缓存；正常路径只做有界校验和运行时绑定，不现场生成整课。
- 每次回答先得到反馈；回答到反馈之间没有文件、工具、联网、历史搜索、第二次模型判断或 reducer。
- Review、input 和 output 在课中只进入可恢复的轻量草稿；最终 feedback／summary 后只发生一次正式学习事务。
- 上下文压缩、断线、工具响应丢失或应用重启后，系统能从准确等待点恢复，不重复题目、评级、提示、证据或队列推进。
- 旧缓存只要仍兼容且能安全呈现就永久优先；不可用时只进行一次有截止时间的替代查找：成功则以 training 使用新材料，失败或到达截止时间才立即使用同队首本地 fallback。
- 用户可以在最终总结后离开；正式归档和 next-cache 编译位于尾部，失败不会撤回反馈或要求重答。
- 本地 Bootstrap 保持不超过5秒，正常缓存路径首个可作答步骤目标不超过30秒，项目可控硬预算不超过90秒。
- 日课对AI只呈现一条固定流水线和少量状态，不要求它临场理解复杂事务、扫描历史或排查环境。

#### 建议如何修改

1. **固定第6条只改变执行方式，不改变教学语义。**
   - Cache、checkpoint、transaction、index 和 projection 都不能成为新的学习事实来源。
   - `plan-items.tsv` 仍是严格顺序与完成状态的权威；第2–5条既有 ledger 仍分别保存 review、observation、目标、能力和洞察事实。
   - 提速只允许减少读取、模型／工具调用和等待，不能放宽冻结契约、有效证据、低歧义 review、难度或长期达标门槛。

2. **将运行数据分为四类，禁止双重真相。**
   - **正式事实：** review event、skill observation、goal／competency／stage／insight event 和 session outcome；使用既有只追加账本或权威表。
   - **Pending 草稿：** 当前 session 已冻结但尚未正式提交的回答结果、反馈状态、review batch 和 observation payload。
   - **派生投影：** 当前 review、adaptation、long-term、dashboard、current-plan 和 bootstrap index；必须可以从事实重建。
   - **可丢缓存：** skeleton、ready package、材料和题目变体；删除或失效不能改变任何学习状态。

3. **先用端到端测量固定真实基线，再按收益排序优化。**
   - 同时测量本地函数、CLI／工具启动、模型决策、联网、checkpoint、正式事务、缓存编译和用户可见阶段切换，不能只测脚本内部运行时间。
   - 先减少工具往返、同步联网和环境失败，再消除全量读取与重复重建；不能把分钟级等待全部错误归因于TSV写盘。
   - 性能测量随既有 checkpoint 或最终事务保存，不为测量新增一次课中调用。

4. **删除 action 分发前的全局 `Read-AllData`，改成白名单懒加载。**
   - `Bootstrap` 只读 settings 的必要字段、start／finalize transaction、当前 session checkpoint、bootstrap index 当前与上一代、准确命中的 package 和有限 review／projection slice。
   - `StartSession` 只读 bootstrap token、queue guard、ID allocator、活动中 session 和当前 package。
   - `PrepareActivity / SaveActivityCheckpoint / StageReviewBatch` 只读写当前有界草稿及上一代副本。
   - `FinalizeSession / AbandonSession` 只读取草稿、事务、实际触及的事实表行、必要投影、当前 plan row 和 index。
   - 完整 `Rebuild`、`Validate`、周期摘要和显式审计才允许扫描全历史；某个无关长期表损坏不得阻止轻量 checkpoint。

5. **把 `StartSession` 改成可恢复、幂等且不重建的控制事务。**
   - 先原子写入 start intent，包含稳定 `session_id`、idempotency key、queue guard、目标 session 路径和 package hash，再创建 stub、锁定当前 plan item 和初始 checkpoint。
   - 任一步中断都由 `Bootstrap` 从 intent 继续；同一 key＋同一 payload 返回同一 receipt，不得为同一 plan item 新建第二个 session。
   - Session ID 使用有界 allocator 或随机稳定 ID，不再递归扫描全部历史 session。
   - `StartSession` 不同步运行 `Rebuild`、完整 `Validate`、长期 reducer、测试或网络请求。
   - 同一学习者同一时刻只允许一个活动中 session；并发请求只能恢复它，不能并行消耗同一队首。这里的锁必须是磁盘上的逻辑 lease／owner token＋expected revision，不能跨整节课持有 PowerShell 文件句柄；lease 到期只允许先恢复并接管原 session，不代表自动 abandon，也不能据此新开一课。

6. **采用“轮次骨架＋逐课滚动完善”的混合预生成。**
   - 用户确认下一轮计划后，轮次复盘为六个 training plan item 按严格顺序生成有界 skeleton，并为每项准备一个完整、同队首的本地 fallback；同时立即完整构建并发布第一严格队首的 ready package。
   - 每节课合法完成后，只根据刚提交的有限投影滚动完善严格下一队首的 ready package；不扫描历史，也不顺手重做其余五包。
   - “下一课”指上一节合法完成课程之后的下一队列项，不绑定“前一天”或自然日；同日连学和隔多日学习使用同一规则。
   - 计划被用户调整时，只重建受影响且尚未展示的包；缓存不能反向修改计划。

7. **守住轮次、复盘与测评边界。**
   - 第六节训练完成后，只预备 cycle review 所需的有界 evidence packet、既有投影引用和候选计算输入；不得提前运行第5条 reducer、生成 `met / stable` 候选或替用户选择下一焦点。
   - 用户完成轮次复盘并确认新焦点与计划后，才生成下一轮六课 skeleton。
   - 下一队首若是 cycle review、assessment 或 diagnostic，只生成该类型已经授权的包，不能越过它预生成后续 training。

8. **把 package 定义为有生命周期的可丢缓存。**
   - 状态固定为 `skeleton → provisional → ready → prepared → consumed`，异常可以进入 `stale / rebuild_required / rejected`。
   - 每个代际保存不可变 manifest、内容哈希、来源、依赖 revision 和 queue guard；published pointer 与构建目录物理分开。
   - 只有其依赖的事实事务和必要投影已经提交，provisional 才能通过原子指针发布为 ready；崩溃遗留半包不得被 Bootstrap 选择。
   - Package 不预分配未来 session ID，不推进 plan，也不能作为 evidence、review 或 adaptation 的事实来源。
   - 缓存数量受限：只保留当前活动包、严格下一队首的有限代际和轮次 skeleton；更旧代际按明确路径逐个清理，不能无限增长。

9. **明确 ready package 中可以完整预生成的内容。**
   - 主线材料或合法本地资产、来源 metadata、题面与题序。
   - 第2、4条已经定义的冻结契约、内部答案／可接受语义范围／评分要点、adapter 和提示阶梯。
   - `1–2` 个不含答案的迁移题壳、唯一预授权 probe 所需的有限安全变体和最多3条已编译 teaching directive。
   - 同队首、同构念且自包含的完整 fallback。
   - 开放任务预存的是标准和可接受范围，不能猜测学习者未来的错误、回答、评分或纠正文字。

10. **明确只能在下一次实际运行时绑定的内容。**
    - 实际 study day、session／activity ID、真正到期的 review 项、当前 recovery mode 和 queue guard 复核。
    - 根据第4条状态从预编译变体中确定最终 evidence mode、target／planned／presented step、changed dimension 和允许支持。
    - Actual support、首次回答、task／criterion 结果、issues、反馈、repair、迁移是否启用及全部长期候选。
    - 运行时只能做确定性选择和冻结一个最终实例，不能重新自由设计整课，也不能生成组合爆炸的所有可能反馈。

11. **把 review 保持为独立的运行时切片。**
    - Skeleton／ready 阶段只缓存有限候选、题型 recipe、低歧义题壳和必要材料；实际学习日仍由第3条按到期顺序、容量、lane、泄漏与题型升级规则选择真正 review 项。
    - 焦点目标、当日主技能、难度状态或主线材料都不能改变 review 的到期时间、抽取顺序和题型语义；只能把已选 review 切片绑定进本课。
    - 仅 study day 或 review revision 变化时，只重绑 review 切片，不废弃仍兼容的主线包；尚未展示的题壳不创建永久 `question_instance`。
    - 每个完成题批只在 session 草稿中冻结带稳定 ID 的 pending `ReviewBatch`；课中不正式改 due、strength、history 或 review projection。
    - 独立的“复习到期内容”会话也使用同一草稿与课末事务规则，只是没有 input／output 主线。

12. **用有界 fingerprint 和 queue guard 判断缓存，不靠 AI 临场猜测。**
    - Manifest 至少绑定 `plan_id`、`plan_item_id`、计划角色、主技能、focus／goal 引用、queue head revision、package／policy／catalog／ladder／contract 版本、必要 projection revision、review revision、content／context ID、来源与权利状态及 checksum。
    - Bootstrap 只比较当前和上一代有界 index 中这些字段；不得为验证缓存而扫描全部计划、session、evidence、review history 或 dashboard。
    - 判断结果必须输出固定枚举和 reason code，供后续恢复、性能分析和测试复现；不能只留下自然语言“看起来可用”。

13. **固定分级失效矩阵。**
    - **精确匹配：** 直接使用并绑定当次 session。
    - **仅日期或 review revision 变化：** 保留主线，仅重新选择和生成 review 切片。
    - **同一队首，但兼容的短期 projection、probe 或 insight directive 漂移：** 从包内选择已准备的保守 variant；若正式可比条件不足，则降为同构念 `training`。
    - **素材／考试 adapter 局部失效：** 只替换或降级受影响层，不连带丢弃仍安全的语言训练。
    - **queue head、用户确认计划、focus、policy、catalog、ladder、contract、assessment 类型、checksum 或权利边界不符：** 硬拒绝该包。
    - **queue guard 无法确认：** 不形成正式 evidence；只有仍能确认同一队首时才允许明确标记的 fallback training，不能猜测或跳队。
    - 正在恢复的 session 永远使用其已冻结 current-session package，不进入 next-cache 的重新选择链。

14. **把“永远优先旧缓存”精确定义为最近的安全兼容代际。**
    - 自然时间经过本身不使缓存失效，也不为了“更时新”或“更优材料”主动联网刷新。
    - 选择顺序固定为：当前精确匹配的 published cache → 最近安全兼容的旧代 → 同队首 skeleton 的保守预编译 variant → 一次临时替代查找 → 本地 fallback。
    - 已重复展示、来源可用性变化或正式可比性丢失，但教学内容仍正确安全时，可以继续使用旧内容，但必须降为 `training`；不能为保留 evidence 资格而临场找新材料。
    - 旧缓存只能影响本次呈现，不能恢复已经失效的证据资格，也不能改写正式状态。

15. **为所有缓存设置最小“可安全呈现”门。**
    - 本次活动需要的正文／音频、transcript、题面、答案或评分范围、来源说明必须自包含或当前可访问，且 checksum 完整。
    - 已有可靠信息表明会变化的事实失实时，必须替换、删除或明确标为带 `as_of` 的历史语境，且不要求用户把它当作当前事实作答；仅自然时间经过或没有新反证，不触发日课联网核验。
    - 涉及当前 TOEFL 官方规则时，必须匹配权威来源和适用考试日期；不能确认就删除当前规则声明，改为版本中立的通用训练。
    - 来源、授权、许可或合理使用边界必须满足项目规则；权利失败时禁止展示该素材，不能用 `training` 标签豁免。
    - 缺少必要音频、transcript、答案范围或 rubric 时，相关活动层失效；不能把“文件能读”误判为“课程可用”。

16. **缓存确实不可呈现时，只允许一次有硬截止的外部替代。**
    - 只有主要内容层没有任何安全兼容缓存时才触发；不得因措辞偏好、材料年龄或想追求更佳内容而联网。
    - 全程只允许一次有界搜索／读取和一次解析，不递归排障、重复搜索、重新规划或等待迟到结果。
    - 外部操作截止为 `min(request_started_at + 60秒, deadline_at - 20秒)`；一到截止立即单向降级到本地 fallback。
    - 新找到的材料必须通过来源、权利、必要 metadata 和冻结教学契约检查，并永远标为 `training`；不能在课堂中临时升级为正式 evidence。
    - 截止后才返回的结果只能用于以后构建缓存，不能让当前用户继续等待或从 fallback 重新切回联网路径。

17. **要求每个 skeleton 自带真正可用的本地 fallback。**
    - Fallback 必须与当前严格队首、核心构念和 activity family 一致，并能在没有网络、登录和外部媒体服务时完成。
    - 阅读材料保存合法的本地文本；听力材料保存可播放音频与 transcript；同时保存题面、冻结契约、答案／rubric、来源和权利记录及内容哈希。
    - 只有 URL、依赖登录、只能流式播放、缺少 transcript 或无法评分的材料不能算 fallback。
    - Fallback 默认是 `training`；技术降级不能算学习者失败，也不能降低第3–5条的证据门槛。

18. **把官方考试规则缓存和普通语言材料缓存分开管理。**
    - 官方规则 metadata 至少包含权威 URL、`verified_at`、`effective_from / effective_to`、`applies_to_test_date`、内容哈希和 `revalidate_after`。
    - 只在轮次规划、正式 assessment 或用户明确询问当前规则时校验；普通日课启动不为此同步联网。
    - 无法及时确认时，保留正确的语言练习并改成版本中立 `training`，不声称它复刻当前官方题型。
    - 官方原题或第三方全文只有权利明确时才能进入缓存；否则只保存项目自制任务、必要短引用或链接 metadata。

19. **把普通日课固定成一条短运行流水线。**
    1. Bootstrap 恢复 pending transaction／进行中 session，或验证准确队首的 ready package。
    2. StartSession 幂等绑定 package，并运行时冻结 review 切片与第一个活动实例。
    3. AI 展示任务，用户首次作答后，AI 在同一次回复内完成第2条的判定、取舍和可见反馈。
    4. 可见反馈之后、下一次要求用户作答之前，每次反馈只产生一个逻辑 `SaveActivityCheckpoint` 和一个成功 revision；传输失败或响应丢失可以用同一 key 有界重试，但不得创建第二份逻辑 checkpoint。该动作可以同时返回已预载的下一步，避免额外工具往返。它是下一道需作答任务的恢复门：未取得成功或可恢复 receipt 前不得继续出题。若 payload 最终无法可靠恢复，保留原 activity ID 并标记 `recovery_uncertain / not_assessable`，不评分、不要求重答。
    5. Review、input、output 依次继续，只重复“展示 → 首答 → 同回复反馈 → 一次 checkpoint”，不在阶段切换时正式入账或重建。
    6. 最终 feedback／summary 展示后，运行一次 `FinalizeSession` 正式事务；随后在不改变本课结果的前提下发布或补建下一队首缓存。
    - 回答到针对该回答的反馈之间继续保持零工具、零文件读写、零联网、零历史搜索、零第二次模型判断和零 reducer。
    - Tracker 每个 action 只向 AI 返回小而固定的 `status / next_action / receipt / reason_code / prepared_step`；fingerprint、失效等级、queue guard、WAL phase 和恢复路线均由脚本确定，AI只按 `next_action` 教学或调用下一动作。

20. **把 current-session checkpoint 扩展为耐久、结构化且有界的临时草稿。**
    - 至少保存 checkpoint revision、package hash、queue guard、当前 stage／等待动作、已展示内容哈希、冻结契约、首次回答的最短必要片段、冻结判定、反馈是否已展示、repair／retry／exposure／actual support 状态。
    - 同时保存 pending review batches、pending observations／vocabulary／error／correction、稳定 event／batch／finalization ID、幂等键和 `pending_persistence` phase。
    - 只保存恢复和正式提交所需的最小结构化信息；不得保存完整私密对话、完整音频、整份外部材料或无关推理。
    - 每课设置大小上限，以原子替换写入并保留一个上一代校验通过的副本；损坏时优先恢复最近有效 revision。
    - Prepared 但未回答的活动可以原样重显；已经首次作答且反馈已展示的活动不得重问、重判或重置提示状态。
    - 若在“回答已收到、反馈尚未展示”的极小窗口中中断，优先从当前对话恢复已生成反馈；无法可靠恢复时标记 `recovery_uncertain / not_assessable`，不强迫用户重答，也不伪造已展示反馈。

21. **课中只冻结结果，不正式提交任何学习事实。**
    - 最终 feedback／summary 之前，禁止追加正式 review history／audit／evidence，禁止改变 review strength／due、adaptation、长期投影、plan 或 session 完成状态，也不运行 Rebuild／Validate。
    - 每个 review 题批仍有独立稳定 batch ID 和冻结 payload，但全部由 `FinalizeSession` 或明确的 `AbandonSession` 统一提交。
    - 首次回答的 task／criterion 判定必须在当次即时反馈中冻结；课末事务只能提交它，不能根据 retry、参考答案或整课印象重新判分。
    - Retry／repair／guided 结果按第2–5条另记，不能覆盖首次回答事实。
    - 跨日恢复时，review 排程使用原回答的 `answered_at / study_date`，不能使用后来 Finalize／Abandon 的日期。
    - 磁盘逻辑 session lease 负责阻止另一条命令同时抽取或正式复习同一项目；lease 过期后只能凭 owner token、checkpoint 和 expected revision 接管恢复，不能推断 session 已放弃。公开 due 在事务提交前保持不变。

22. **用一个可恢复 WAL 实现全课唯一正式提交边界。**
    - Transaction intent 保存 transaction ID、稳定 idempotency key、session ID、checkpoint revision、queue guard、输入 payload hash、预期 projection revisions、待追加事实、目标 disposition、当前 phase 和错误状态。
    - `FinalizeSession` 与 `AbandonSession` 复用同一事务原语，只在允许提交的事实范围和最终 session／plan 结果上不同；独立 review 会话也复用它。
    - 固定 phase 为：持久化 intent → 校验草稿／guard／ID／引用 → 幂等追加不可变事实 → 只更新受影响的短投影 → 写 session terminal receipt → 按 disposition 更新 plan／queue → 更新关键 bootstrap index → 标记 committed。
    - Terminal receipt 必须引用 transaction ID；只有对应 WAL 已标记 `committed` 时，`completed / abandoned` 才是对读者生效的权威终态。WAL 尚未 committed 时出现的 terminal、plan 或 index 写入都只是可恢复半状态，Bootstrap／Finalize 必须继续原事务，不能阻止重试或开放下一 session。
    - Dashboard、current-plan 全量视图和 next-cache 发布是提交后的派生工作；失败只能记录 `rebuild_required` 或 `preload_pending`，不能撤销已经提交的事实与课程结果。
    - WAL 只保存本课的有界 payload，不复制全历史；任一步中断都从最后完成的 phase 继续，不靠回滚已落盘的不可变事实恢复。

23. **把幂等性覆盖到工具响应丢失和并发冲突。**
    - 所有幂等键、event ID、observation ID、review batch ID 和 finalization ID 在 session 草稿中预先分配，重试时不得生成新 ID。
    - 同一 key＋同一 payload 返回原 receipt；同一 key＋不同 payload 明确拒绝。
    - 新正式事务开始前必须先恢复或明确拒绝已有 pending transaction，绝不能用新 pending 文件覆盖旧事务。
    - “实际提交成功但调用结果丢失”后重试，不得重复追加 review event、再次提升 level、重复 observation、重复推进 plan 或重复计入轮次。
    - 使用磁盘逻辑 lease／owner token 和 expected revision 处理并发；lease 过期必须先核对并恢复原事务后才能接管，revision 冲突进入可恢复 pending 状态，不能靠静默覆盖解决。

24. **让 FinalizeSession 自己提交 terminal 状态。**
    - 它直接消费已冻结草稿；调用者不再预先手改 session、review、evidence、plan 或 dashboard，也不进行第二次 AI 判分。
    - 提交前按 `session_type` 和展示前冻结的 session contract 校验必需阶段、所有已展示活动的终止状态、最低结构化记录要求、queue guard 和本事务实际触及的引用，不跑全库 Validate。普通日课要求 review／input／output／feedback；独立复习、diagnostic 和 assessment 使用各自契约。预定活动已终止并如实记录 `not_assessable / invalid` 即满足归档结构要求；不要求回答成功、具备 A 类资格或一定产生有效能力证据。
    - 事实和必要短投影成功后，事务才写带 finalization ID 的 `status: completed`，推进当前 plan item 和严格队首，并更新关键 index。
    - 任一步失败保留 `pending_finalize` 和可重试 phase；在它恢复前不能开放下一次正式 session。
    - Next cache 缺失、构建失败或发布失败不是本课 Finalize 失败条件，不能把已经完成的课回滚为未完成。

25. **仅在用户明确放弃时执行 AbandonSession。**
    - 断线、应用退出、上下文压缩、跨日或长时间未继续都仍是 `in_progress`，下次 Bootstrap 从 checkpoint 精确恢复，不自动 abandon。
    - 明确放弃时，冲刷所有“已经收到首次回答、判定已冻结且反馈已展示”的原子审计事实，包括有效 review／observation、`invalid`、correction 和 void；只有有效结果才能改变 review 或能力投影，`invalid` 只保留审计和模板故障信号。
    - 已满足第3条既有激活准入规则的 vocabulary／error 项一并提交；未回答、判定未完成、反馈未展示、只是临时教学笔记或未确认候选的内容不得进入正式账本。
    - Session 记为 `abandoned`；当前 plan item 回到 `planned` 并保持严格队首，不增加 completed session／cycle 计数，也不发布“下一队首”缓存。
    - 已冲刷事实带 `source_session_outcome=abandoned`，其证据资格仍由第3–5条决定；已经展示过的 content／context ID 必须保留，重做时不能把同一暴露冒充新的独立 A 类证据。
    - Abandon 使用与 Finalize 相同的幂等事务；任意 phase 重放都不得重复评级、重复证据或改变队列。

26. **固定 Bootstrap 的恢复优先级。**
    1. 恢复半完成的 start intent。
    2. 恢复 `pending_finalize / pending_abandon` 等正式事务。
    3. 返回尚未明确放弃的 `in_progress` session，并定位到最后一次已保存反馈之后的等待动作。
    4. 只有不存在上述状态时，才从有界 index 打开当前严格队首。
    - Pending review 不因公开 due 尚未更新而被再次抽取；恢复继续使用原冻结顺序、题面、题量和原回答时间。
    - 当前 index 损坏而上一代 queue guard 一致时，使用上一代同队首包或 fallback 并标记 `rebuild_required`。
    - 两代都无法确认 queue head 时停止正式取证；不能猜测、跳过计划项或创建第二个 session。

27. **把下一课缓存的构建和发布分开。**
    - 最终 feedback 的同一次 AI 回复可以在草稿中冻结一个有界的 next-package candidate descriptor，但它不是已编译 package，Bootstrap 看不到它，也不得在本课正式事务前写入 published 代际。
    - Feedback 展示后立即先完成本课正式事务；只有事务 committed、真实下一队首和最终 projection revision 已确定后，才开始 next-cache 工作。
    - 先检查是否已经存在同一真实队首、仍安全兼容的 published generation；有则直接 no-op。没有时才用对应 skeleton 和 candidate descriptor 编译，重新校验 guard 后通过原子指针发布为 ready。
    - Guard 不符就丢弃 candidate，重新使用对应 skeleton；不能让 candidate 反向改变队列。
    - 构建或发布失败只记录 `preload_pending`，保留安全旧代、skeleton 和 fallback；不回滚已完成 session。该尾部工作不是 Finalize 成功条件，也不计入下一课的90秒启动预算。
    - 第六节训练完成后的 candidate 只能是第7点规定的 cycle-review 输入包，不能越过用户复盘和确认去发布下一轮训练课。

28. **把全量 Rebuild、Validate 和长期 reducer 移出日课关键路径。**
    - `Rebuild` 是从不可变事实重建全部 projection、dashboard、current-plan 和 bootstrap index 的显式维护动作；执行前先恢复 pending transaction。
    - 完整 `Validate` 只用于全库引用、历史连续性、projection 一致性和缓存诊断；普通启动、阶段转换、checkpoint 与成功 Finalize 后都不自动运行。
    - Finalize 只做事务结构、queue guard、expected revision、受影响引用和局部投影校验；普通日课只更新第4条允许的短期 adaptation。
    - 第5条 `met / stable`、CEFR gate、焦点决定和长期 insight reducer 仍只在轮次复盘或正式 assessment 运行，预加载不能提前运行。
    - Dashboard／current-plan 派生视图写入失败时设置 `rebuild_required`；只要正式事实、session、plan／queue 和关键 index 已提交，就不回滚课程。

29. **统一失败语义，避免把技术问题转嫁给学习者。**
    - 一旦反馈已经展示，后续 checkpoint、正式事务或 cache 失败都不得撤回反馈、要求重答、重判或重复展示已完成题目。
    - `SaveActivityCheckpoint` 失败或响应丢失时，以同一 key 做有界重试；取得成功或可恢复 receipt 前暂停下一道需作答任务。最终无法恢复原 payload 时，使用原 activity ID 记录 `recovery_uncertain / not_assessable`，不形成评分或正式能力证据。
    - 草稿／WAL 保存稳定 ID、payload 和最后成功 phase；下次 Bootstrap 从该点继续，不能依赖 AI 回忆整段对话重建事实。
    - 非必要网络、素材替换或 cache build 一次失败就单向降级，不在课堂里排障。
    - 无法确认 queue guard 或正式契约时，不形成正式 evidence；可以明确告知技术降级并继续同队首 training。
    - `pending_persistence`、`rebuild_required` 和 `preload_pending` 都是系统状态，不得写成学习者能力失败或影响 review 评级。

30. **沿用第4条预算，并为课中保存增加可验收目标。**
    - 本地 Bootstrap 项目内路径不超过5秒；正常缓存路径从“开始今日学习”到首个完整可作答步骤目标不超过30秒；项目可控路径硬上限不超过90秒。
    - 外部替代最迟在 `min(request_started_at + 60秒, deadline_at - 20秒)` 停止，至少留20秒冻结 fallback 并展示；不能把联网等待延伸到硬上限之后。
    - 回答到即时反馈的计划内工具／I/O／联网／第二模型调用为0；反馈后的单次 checkpoint 内部工作目标不超过0.5秒，含一次现有工具启动的用户可见阶段切换目标不超过10秒。
    - 课末必要短 projection／事务提交目标不超过5秒；next-cache 编译不阻塞最终反馈，超过约10秒只给一次简短保存进度，用户可以离开。若尾部预加载尚未完成，下次启动仍必须在该次独立90秒预算内选择安全兼容旧代、一次替代查找或本地 fallback。
    - 记录 `bootstrap_latency_ms`、`material_ready_latency_ms`、`decision_latency_ms`、`checkpoint_latency_ms`、`persistence_latency_ms`、cache hit／失效原因、next-cache compile／publish、`fallback_used`、`fallback_reason` 和 `uncontrolled_latency_ms`。
    - 指标随下一次 checkpoint 或最终事务批量保存，不为计时新增调用；平台排队、模型服务和用户网络等不可控时间单列，不能用来掩盖项目内超时。

31. **第一版不引入常驻进程或新数据库。**
    - 先使用 action 白名单懒加载、有界双代 index、一反馈一次 checkpoint、一课一次正式事务和减少工具往返，解决已经确认的主要瓶颈。
    - 文件事务仍是恢复与正确性的权威；缓存、内存或 helper 丢失后必须能从磁盘恢复。
    - 只有包含真实工具／进程启动成本的端到端测试仍无法满足第30点时，才评估 session-scoped helper；它不能常驻，也不能成为正确性前提。
    - 不为了提速同时引入数据库、消息队列、后台服务和多套缓存协议，避免让日课规则超过 AI 可稳定执行的复杂度。
    - 所有复杂状态机都封装在 tracker 内；日课 AI 只消费第19点的固定小返回并执行 `next_action`，不得自行计算 fingerprint、选择失效层、推进 WAL phase、判断 lease 接管或拼装恢复路线。

32. **采用从 C0004 起启用的非追溯迁移。**
    - C0003 已完成、进行中和待开始的 plan item、session、review、evidence 和队列语义不改写；现有 pending review transaction 先按旧协议完成。
    - 旧 completed checkpoint 视为 legacy closed state，不能因缺少新 receipt 而重放；历史 session 不补造 transaction、cache fingerprint、权利状态或 A 类证据。
    - 离线建立新版事务 schema、projection、双代 bootstrap index 和校验工具；完整验证后再原子切换 runtime version。
    - C0003 轮次复盘和用户确认 C0004 计划后，生成 C0004 六课 skeleton／fallback；从 C0004 的第一节新 session 起完整使用新协议。
    - C0004 启用门还包括更新 `references/resource-policy.md` 与 `assets/fallback-materials.md`：把普通日课“开课时同步查页”改为编译期／轮次边界校验，并确保每个听力 skeleton 都有合法本地音频、transcript、内容哈希和权利记录；当前仅有文字且明确“不是真实音频”的备用材料不能冒充听力 fallback。
    - 新版 session 必须有 start／finalization receipt；迁移中断时继续使用旧运行版本或上一代已验证 index，不能在同一活动 session 中混用新旧提交语义。

33. **按“先正确、后提速、再缓存”的顺序落地。**
    1. 先为现有行为加入文件读取 spy、端到端计时、写点故障注入和响应丢失重试 fixture，保存基线。
    2. 实现共享的稳定 ID、幂等键、原子文件替换、session lock 和 WAL 原语。
    3. 先重写 `StartSession`，消除跨文件半状态、重复 session、历史 ID 扫描和同步 Rebuild。
    4. 扩展 current-session；增加 `PrepareActivity / SaveActivityCheckpoint / StageReviewBatch`，把课内 ReviewBatch 改成 pending 子批。
    5. 重写 `FinalizeSession / AbandonSession`，确立事实／局部投影在前、session／plan／queue 提交在后、next cache 最后发布的可重入边界。
    6. 正确性测试通过后，再删除全局 `Read-AllData`，实现 action 懒加载、有界 index 和增量短投影。
    7. 最后接入轮次 skeleton、滚动 ready package、可呈现门、分级失效、一次外部替代和本地 fallback。
    8. 更新 `MAINTENANCE.md`、`SKILL.md`、`references/resource-policy.md`、`assets/fallback-materials.md`、其余模板、schema 和命令说明；补齐合法本地听力资产后，通过迁移演练与完整 Validate，作为同一 runtime schema 版本启用。

34. **用以下最低测试决定是否真正完成。**
    - 在 start intent、stub、plan lock、checkpoint、各事实追加、短投影、session terminal、plan／queue、index 和 cache publish 后逐点模拟中断；Bootstrap 最终只能恢复一个 session 和一个确定状态。
    - 同一 key 重试不重复 review event、level／due、observation、projection 计数、plan 推进或轮次计数；同 key 不同 payload 必须拒绝，旧 pending 不得被覆盖。
    - 回答到反馈之间的读取／写入／工具／联网／第二次模型判断为0；checkpoint 的读取 spy 证明不访问完整 session、review、evidence、dashboard 或计划历史。
    - 在“反馈已展示、checkpoint 尚未成功”和 checkpoint 响应丢失处注入故障：下一题不会提前出现，同一 key 重试不重复事实；payload 不可恢复时只形成 `recovery_uncertain / not_assessable`，不评分、不重答。
    - Prepared 未答活动原样重显；已答且已获反馈的活动不重问、不重判；跨日恢复保留原 `answered_at`、题序、题量、提示和 recovery mode。
    - 一课所有 review batches 只在 Finalize／Abandon 事务正式提交；Finalize 不依赖 AI 预改文件，事务失败不留下无法重试的 completed 半状态。
    - 缺少对应 committed WAL 的新版 `completed / abandoned` receipt 不被 Bootstrap 信任；恢复事务后才开放下一 session。
    - Abandon 只冲刷已首答、已冻结判定且反馈已展示的原子事实，session 为 `abandoned`、plan item 仍是队首，并正确去重重复 content／context 暴露。
    - 用户确认新轮计划后，第一严格队首立即拥有完整 ready package；六课 skeleton 均有同队首、自包含、权利合规的 fallback；rolling compiler 只处理严格下一队首；第六课之后不越过 cycle review。
    - 日期／review、projection、考试 adapter、queue、focus、contract、checksum、素材完整性和权利变化分别命中第13点规定的失效层；安全兼容旧缓存不会仅因时间过去而失效。
    - 外部替代最多一次且必为 training；虚拟时钟和永不返回的 provider 都会在截止前进入本地 fallback，迟到结果不影响当前课。
    - 历史数据扩大十倍后，Bootstrap 和轻量 action 的读取文件集合与工作量上限不随历史增长，并满足第30点端到端预算。
    - Tracker 对日课 AI 只返回固定小状态和 `next_action`；测试证明 AI 无须读取 WAL、计算 fingerprint／失效矩阵或自行决定恢复分支。
    - 第1–5条的严格队列、复习独立性、低歧义题型、冻结契约、首次回答证据、完整微循环上限、难度状态、A/B/C 资格、`met / stable` 权限、CEFR gate 和用户确认边界全部保持不变。
