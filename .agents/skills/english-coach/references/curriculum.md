# 英语能力门槛地图

本文件是学习者可读的课程地图。机器可判定的 gate、indicator、anchor、先修关系和 R/B/E 角色只以 [competency-catalog.json](competency-catalog.json) 为事实源；本文件与目录冲突时以目录为准。任务条件的升降只以 [difficulty-ladders.json](difficulty-ladders.json) 为事实源。

## 长期目标

- 长期方向是让听、说、读、写分别接近稳定的 CEFR-referenced B2，并能迁移到日常、校园、计算机科学和 TOEFL 基础任务。
- CEFR 对齐是项目对官方量表方向的本地操作化，不是官方校准或正式考试成绩。
- 四项能力分别保存状态，不计算会掩盖偏科的平均等级。综合 B2 只表示四项各自的 B2 Required gates 都已稳定。
- 自然时间、学习天数、完成轮数和单次最好表现都不能推动能力晋级。

## 能力阶段

每项技能独立沿下列门槛发展：

| stage_id | 对齐等级 | 人类可读方向 | 稳定条件 |
| --- | --- | --- | --- |
| `STAGE_A2_FOUNDATION` | A2 | 在熟悉、简短、明确的条件下处理直接信息和简单交际目的 | 该技能在 A2 的全部 R gates 为 `stable` |
| `STAGE_B1_INDEPENDENT` | B1 | 在清楚的标准语言条件下连贯处理主要信息、相关细节、理由或简单推断 | 同技能 A2 阶段已稳定，且 B1 的全部 R gates 为 `stable` |
| `STAGE_B2_FLEXIBLE` | B2 | 处理更复杂或延展的内容、隐含关系，并能持续展开和适应对象 | 同技能 B1 阶段已稳定，且 B2 的全部 R gates 为 `stable` |

状态只使用 `not_evidenced / developing / stable`：

- `not_evidenced`：尚无足够、有效、可比的直接证据；不等于不会。
- `developing`：已有直接证据，但尚未满足稳定门槛或仍有未解决冲突。
- `stable`：达到长期 reducer 的证据数量、跨日、跨语境、确认和维护要求。

单个 gate 的细则不在这里复制。日课和复盘只能引用目录中已有的 `gate_id`、`indicator_id` 和 `anchor_id`。

## 四技能 Required 路径

下表只帮助阅读目录；B 和 E gates 仍用于广度、先修和探索，但不参与对应技能阶段的完成条件。

| 技能 | A2 Required | B1 Required | B2 Required |
| --- | --- | --- | --- |
| 听力 | `L_INTERACTION`, `L_ACTION_INFO` | `L_INTERACTION`, `L_ACTION_INFO`, `L_EXTENDED` | `L_INTERACTION`, `L_EXTENDED` |
| 口语 | `S_TRANSACTION`, `S_CONVERSATION` | `S_TRANSACTION`, `S_CONVERSATION`, `S_EXPLAIN`, `S_ARGUMENT` | `S_CONVERSATION`, `S_EXPLAIN`, `S_ARGUMENT` |
| 阅读 | `R_FUNCTIONAL` | `R_FUNCTIONAL`, `R_NARRATIVE`, `R_EXPOSITORY` | `R_EXPOSITORY`, `R_ARGUMENT` |
| 写作 | `W_TRANSACTION` | `W_TRANSACTION`, `W_EXPLAIN`, `W_ARGUMENT` | `W_TRANSACTION`, `W_EXPLAIN`, `W_ARGUMENT`, `W_MEDIATE` |

某一技能领先时，可在该技能使用下一阶段材料或 gate；其他技能不会被自动抬高。某一技能落后时，也不会降低已经由证据支持的其他技能状态。

## 四个教学方向

教学方向用于选择内容，不是按顺序自动解锁的阶段：

1. `DIR_FOUNDATION`：高频交际、基本句法、核心词组、主旨和直接信息。
2. `DIR_B1_TO_B2`：信息关系、推断、持续表达、论证、对象适配和跨情境迁移。
3. `DIR_TOEFL_APPLICATION`：把已有能力映射到当前适用的 TOEFL 任务；不另建一套能力等级。
4. `DIR_INTEGRATED_STABILITY`：在不同材料、对象、模态和时间条件下维持表现，并修复长期薄弱点。

一个轮次可以同时服务多个方向。TOEFL 题型可以提前少量熟悉；正式限时、提速和分数估计仍须满足相应 gate、材料权利和官方规则验证要求。

## 焦点目标

- 每次轮次复盘只提出一个最高优先级缺口，并给出首选、证据、理由和一个备选，由学习者确认。
- 焦点目标绑定明确的 `competency_id`，必要时再绑定 activity family 或 quality focus；不能只写“提高口语”之类无法验收的愿望。
- 一个目标默认持续 2–4 个完成轮次。未完成的自然周和中断天数不计入窗口。
- 每个完成轮次只作一次正式决定：`met / continue / redesign / insufficient_evidence`。
- 连续两个完成轮次没有有效进步，或第 4 个完成轮次仍未达标时，创建新版本并缩小目标、补先修能力或改变干预；不原样无限延长。
- 目标提前出现足够表现时，本轮剩余焦点课用于迁移和巩固；仍等轮次复盘后才正式结束或更换目标。

## 六课轮次与复盘

一个轮次包含 6 个严格排队的训练项，之后是独立的轮次复盘。轮次不绑定自然周。

下一轮计划在复盘时冻结：

- 焦点能力占 2–4 个 lead 主技能位置，默认 3 个。
- 每项听、说、读、写至少获得一次可评分 primary 机会；无效或未完成的任务不伪装成证据。
- 任一非焦点技能在滚动两个完成轮次内至少一次成为 lead 主技能。
- 正常一轮约 8 个 evidence-bearing primary，硬上限 9；每课至多一个 lead、一个 auxiliary 和一个自然共现的 secondary。
- 每课至多预授权一个 difficulty probe；运行时只能验证该候选或保守降级，不能临时扫描替补。
- 队列只因完成、明确放弃或带理由的用户批准变化而推进。能力、焦点和难度状态都不能跳过或重排队首。

轮次内只允许调整当前课的材料、支架和任务条件。焦点、技能占比、R/B/E 角色和下一轮结构只在复盘或学习者明确调整计划时改变。

## 到期复习独立

日课的 review 是独立的原子间隔复习通道：

- 焦点目标不能改变复习项目的到期日、抽取内容、题型阶段、车道、顺序或容量。
- 复习不计入六课的主技能占比，也不被改造成当前弱项的听说读写任务。
- 当堂提示后的修复只属于教学结果；跨日首次独立回答才可改变正式复习状态。
- 复习趋势可以作为长期判断的 B 类支持证据，但单个词或句型答对不能单独使宏观 gate 稳定。

## 证据与晋级

- 日课保存原子 observation；一份预冻结契约加一次反馈前首次回答只形成一条事实。
- 只有有效、可比、独立且符合当前 anchor 的 direct evidence 才能推动 gate。
- 反馈后重试、guided、training、答案暴露、歧义、技术故障和非可比任务不作为晋级证据。
- 普通日课只记录 observation 和有限候选信号；`met`、gate `stable` 和 stage attainment 只在轮次复盘或正式测评中由确定性 reducer 产生。
- 阶段门槛不会因证据自然变旧而自动失效；冲突、确认到期和维护风险按长期规则进入 `watch` 或 maintenance 流程。

## 测评与 TOEFL

- 每 4 个完成轮次安排一次分段测评；每 12 个完成轮次安排跨多个 30 分钟课次的综合模拟。它们是计划边界，不是自动晋级条件。
- TOEFL adapter 必须同时映射一个 activity family 和一个 competency family。Complete the Words、Build a Sentence、Listen and Repeat 等任务形式本身不是宏观能力。
- 日常练习不换算精确 TOEFL 分数。内部估计必须标注非 ETS 官方，并与正式 CEFR gate 状态分开。
- 当前 TOEFL 结构或计分声明必须在适用考试日期前按官方来源重新验证；无法验证时保留版本中立的英语训练。

## 恢复与学习量

- 未学习的日子不产生 `missed`，不推进轮次，不使目标失败，也不形成能力证据。
- 达到配置的中断阈值后进入 recovery mode：缩小当课负荷并继续同一队首；不补课、不重排、不执行难度 probe。
- 恢复课中精确原 target、无额外支持的首次独立回答可以按规则计入稳定或恢复；scaffolded 表现仍只作教学证据。
- 周日提醒只负责提醒，不改变队列、目标、复习或能力状态。

## 完成定义

- gate 完成：目录所列 observable indicators 均满足长期 reducer 的稳定规则，且没有阻塞 flag。
- 单项技能阶段完成：该技能当前等级全部 R gates 稳定，且前一阶段已经完成。
- 综合长期目标完成：四项技能分别完成 `STAGE_B2_FLEXIBLE`；不使用平均分替代任何一项。
- 教学方向完成：没有自动终点，由学习者目标、正式测评和下一阶段计划共同决定。
