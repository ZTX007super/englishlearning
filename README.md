# 我的英语学习项目

这是我给自己做的长期英语私教项目：让 AI 帮我安排练习、解释问题、记住表现，再根据学习情况调整后面的课程。优先提高真正能用的英语能力，考试准备是其中一种应用。

AI 负责教学与反馈，项目里的程序负责记录进度、安排复习，以及中断后的恢复。这份 README 是平时使用和找文件的小地图。

## 从这里开始

- **想上课**：在这个项目的对话中说“开始今日学习”或“继续学习”，教练会找到当前进度。
- **想看学得怎样**：说“查看进度”；一轮结束后可以说“开始轮次复盘”。
- **想理解课程流程**：先看下面的“一节课如何运行”，再按需要打开对应文件。
- **想调整一点使用习惯**：看下面的“想按自己的习惯调整”。
- **想备份或换电脑**：读 [备份与恢复说明](maintenance/backup-guide.md)。Git 不包含完整学习状态。

## 一节课如何运行

```text
开始或继续学习
  → 找到上次未完成的课程，或计划中的下一课
  → 有复习题：逐题回答、反馈、保存草稿
  → 主课：独立首答、反馈；需要时澄清或修改
  → 展示总结，完成正式保存
  → 本轮结束时复盘，讨论并确认下一轮
```

目前默认每次约 30 分钟，六次训练加一次复盘算一轮，不一定要在一个自然周内完成。复盘时会讨论目标进展和下一轮安排，确认后再更新计划。

课中保存的是能接着用的草稿，课末保存成功才成为正式记录。暂时退出或断线后，可以继续同一课程；想彻底放弃这节课时再明确告诉教练。

## 想按自己的习惯调整

先直接告诉教练具体想改变什么，例如：

- “这次解释短一点，先让我自己试。”
- “这次练习尽量用校园或计算机相关的话题。”
- “下一轮我想多练口语，请结合这轮表现给建议。”

区分“这次这样做”和“以后都这样做”。对话里提出偏好，不等于它已经永久保存；长期变化要确认记录在哪里，目标和下一轮安排也需要确认后生效。

想自己看看或做一点小修改，可以先从下面的文件地图定位。文字说明与个人偏好容易理解；复习日期、评分结果和课程进度属于学习记录，尽量让教练按流程更新，避免直接改表后前后对不上。拿不准时可以说：“先解释这处修改会影响什么，暂时不要改。”

## 目录里有什么

| 位置 | 用途 |
| --- | --- |
| [README.md](README.md) | 我自己日常使用、了解流程和找文件的入口。 |
| [AGENTS.md](AGENTS.md) | 告诉 AI 现在该上课还是改项目，以及需要遵守的边界。 |
| [MAINTENANCE.md](MAINTENANCE.md) | 真正要改代码时给维护者看的说明，平时上课不用读。 |
| [.agents/skills/english-coach/](.agents/skills/english-coach/SKILL.md) | 教练入口，以及按需读取的规则、脚本和材料。 |
| `learner/` | 我的学习档案、设置、计划、表现与复习记录。 |
| `sessions/` | 各节课的记录，按年、月保存。 |
| `.state/` | 记住当前上到哪里、如何继续，以及预备好的课包；不能当普通缓存清空。 |
| `maintenance/` | 备份工具、维护说明和历史输入示例。 |
| `tests/` | 帮助检查程序改动是否影响原有功能的测试，平时不用操作。 |
| [docs/PRD.md](docs/PRD.md) | 项目为什么做、要做到什么、目前做到哪里。 |
| [docs/design/](docs/design/learning-system-plan.md) | 详细设计、提速方案和待改问题，部分内容还是设想。 |
| `backups/` | 完整备份 ZIP，另存一份到其他存储位置。 |
| `.cache/` | 临时工具文件与隔离演练副本，不是正式学习档案。 |

## 按问题找文件

先找自己关心的问题，不必从头读完整个项目。档案放在 `learner/`，大多数教学规则放在 `.agents/skills/english-coach/references/`。

| 想了解或修改什么 | 先看哪份说明 |
| --- | --- |
| 我的目标、时间安排和兴趣偏好写在哪里 | [学习者档案](learner/profile.md)；部分程序设置在 [settings.json](learner/settings.json) |
| 目前计划学什么、进度大致怎样 | [当前计划](learner/current-plan.md)、[进度概览](learner/dashboard.md) |
| 之前上过的课记在哪里 | [sessions/](sessions/)；按年、月找课程记录，不是完整聊天备份 |
| AI 收到请求后如何选择下一步 | [SKILL.md](.agents/skills/english-coach/SKILL.md) |
| 开课后为什么先复习，再进入主课 | [classroom-flow.md](.agents/skills/english-coach/references/classroom-flow.md) |
| 主课题目与评分标准 | [task-contracts.md](.agents/skills/english-coach/references/task-contracts.md)、[activity-preparation.md](.agents/skills/english-coach/references/activity-preparation.md) |
| 答错后怎样反馈、修改与恢复 | [teaching-loop.md](.agents/skills/english-coach/references/teaching-loop.md) |
| 复习怎样出题与评级 | [review-teaching.md](.agents/skills/english-coach/references/review-teaching.md) |
| 为什么某个词或表达又被安排复习 | [review-protocol.md](.agents/skills/english-coach/references/review-protocol.md) |
| 跨轮判断目标、下一轮换目标 | [goal-review.md](.agents/skills/english-coach/references/goal-review.md)、[cycle-publication.md](.agents/skills/english-coach/references/cycle-publication.md) |
| 更完整的长期能力设计及实现范围 | [long-term-state.md](.agents/skills/english-coach/references/long-term-state.md) |
| 之前发现的问题、准备改什么 | [课堂可靠性待修改清单](docs/design/classroom-reliability-followups.md) |
| 为什么要这样设计整个项目 | 先看 [PRD](docs/PRD.md)，需要详细理由时再看 [学习系统设计](docs/design/learning-system-plan.md) |

## 这些文件是怎么配合的

可以把它们理解为四部分：

1. **SKILL 和 references 是教练手册**：告诉 AI 怎样出题、反馈、复盘。
2. **scripts 是记录与排程程序**：从 [tracker.ps1](.agents/skills/english-coach/scripts/tracker.ps1) 进入，处理进度和保存。
3. **learner、sessions、.state 是学习档案与课堂现场**：让下次学习能接上。
4. **docs 是项目说明和改进笔记**：帮助我理解方向，也方便以后交给别人维护。

教练说了什么、程序保存了什么，需要配合起来看。只改手册不一定会改变程序行为；改了档案也不一定代表计划已经正确更新。

## 使用中遇到问题

- **中途退出了**：回到项目中说“继续学习”。新开对话也应按保存的进度恢复。
- **题目有歧义，或者提前给了答案**：直接指出问题，保留那条回复，方便核查；不要把照着答案写对当成独立掌握。
- **不知道有没有保存成功**：让教练说明保存结果；只说了课程总结，不等于已经正式保存。
- **等待明显变长**：记下卡在开课、题间、转主课还是结课，以及大致时长。保留例子比只说“变慢了”更容易定位。
- **要换电脑或改重要内容**：先按 [备份说明](maintenance/backup-guide.md) 保存完整备份，并另存一份。只复制 Git 仓库可能遗漏课堂恢复状态。

## 目前还在改进什么

截至 2026-10-06，已经能保存和恢复主课修改作答、跨轮判断局部目标、确认后更新下一轮，也有完整备份工具；当前学习实例已换用结构化目标。

最近使用中发现的漏提醒、提前给答案、备选区别不清楚，已登记但还没修复。跨日复习名单刷新仍暂缓；完整能力等级判断也还没有接通，不能把一次目标完成理解为整个英语等级提升。

更完整的现状和边界看 [PRD](docs/PRD.md)。真正准备改代码时，再转到 [维护说明](MAINTENANCE.md)；平时上课不需要先读它。
