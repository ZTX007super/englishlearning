# 评分、支持与证据量表

只在 diagnostic、assessment、正式 probe，或活动 contract 明确需要质量评分时读取。任务是否完成先按 [task-contracts.md](task-contracts.md) 判断；教学问题取舍按 [teaching-loop.md](teaching-loop.md)。

## 共同原则

- 只评价冻结契约实际观察到的内容。结果必须引用 activity/observation/criterion ID 和最小充分表现片段。
- `not_observed`、`not_assessable` 与 `not_met` 分开；歧义、技术问题、条件不可比和不可靠转写不是学习者失败。
- 首答、guided/revised/repair/transfer 分开保存。最后答对不能消除实际帮助，也不能改写首次结果。
- 日常训练不换算精确 TOEFL 分数；任何内部估计都标注“非 ETS 官方成绩”，说明 task、metric、scale、版本和限制。

## 质量维度

按 contract 选取，不要求每次全部评分：

- `range`：能否调动完成任务所需的词汇和结构范围。
- `grammatical_accuracy`：语法控制及错误对理解的影响。
- `vocabulary_control`：词义、搭配、精确度和语域。
- `coherence`：信息组织、连接和逻辑关系。
- `fluency`：连续表达、停顿与自我修复；纯异步文字不得猜测口语流畅度。
- `sociolinguistic_appropriateness`：对象、场景、礼貌与语域适配。
- `phonological_control`：音素、重音、节奏、语调与可懂度；只有可靠音频和实际声音分析时使用。

## 四项能力观察

### 听力

分别记录主线、关键细节、说话者目的、turn/idea relation、推断和复述。报告答对、遗漏、证据位置及下一步，不用总正确率掩盖题型差异。

### 口语

根据活动选择任务回应、组织、语法、词汇、互动、流畅度等质量维度。只有音频条件满足时评价 phonological control；听写文本只作粗略可懂度线索。

### 阅读

分别记录主旨、事实、词义、指代、目的、claim/evidence relation、推断和阅读条件。速度只有实际、可靠计时时记录。

### 写作

根据体裁、受众和目的记录任务完成、组织、语法、词汇、连贯及 source fidelity。先判断是否影响任务和意义，再判断自然度或风格。

## 支持

`support_level` 固定为：

- `none`：没有超出 contract 正常 access condition 的帮助；
- `light_hint`：定位、关键词或不泄露答案的轻提示；
- `heavy_hint`：规则提示、句架、选项或明显缩小答案范围；
- `model`：示范、答案或足以重构答案的完整形式。

`support_kind` 记录实际帮助，例如 `replay | review_source | location | keyword | rule | frame | options | model`。契约内预先允许的准备、回看或重放不自动算提示；超过允许条件后才记录支持。

每个 criterion/loop 保存实际使用的最高 support level 及相关 kinds。使用 model 后，受影响的原题或标准失去独立性；新 activity ID 的新语境按其真实支持重新判断。

## 成本与有效性

`cost_signal` 使用 `normal | high | unknown`。只有 contract 预先定义且可观察的困难指标才能标 high；AI不能仅凭消息间隔、主观印象或学习者一句“很难”推定。

用于长期 A 类的证据必须是有效、可比、首次、独立、未暴露，且支持不超过 contract 的正常允许条件。B/C 分类和长期门槛由 [long-term-state.md](long-term-state.md) 与 tracker reducer 决定，AI不手工升级。

CEFR 能力引用版本化 competency catalog 的现有 `competency_id / indicator_id / anchor_id`。本文件不另建 A2/B1/B1+/B2 描述或四技能平均分；项目只能称 CEFR-aligned/referenced，不能声称官方校准。

## Assessment

- Assessment 前冻结 task、metric、scale、适用材料、access/support 和评分范围，并先保存完整无提示表现。
- 听、说、读、写可以分散到多个计划项；以队列和 assessment contract 为准，不按自然周强制赶完。
- 每项结论列出决定性 evidence、条件、成本、未观察内容和未达到下一门槛的具体原因。
- TOEFL 内部估计只在对应综合 assessment contract 允许时给出。正式考试结构、换算和适用日期必须引用通过 [resource-policy.md](resource-policy.md) 校验的 ETS authority record。
- 语音条件不足时明确写“发音未评估”，不能让 transcript 识别率替代发音、重音、节奏或语调评分。
