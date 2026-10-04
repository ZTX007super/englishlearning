# 我的英语学习项目

这是一个由 AI 英语教练和本地学习档案组成的应用项目。AI 负责教学与反馈，tracker 脚本负责记录进度、安排复习，以及中断后的恢复。

## 从这里开始

- **想上课**：在项目对话中说“开始今日学习”或“继续学习”，由 english-coach 技能按当前进度启动。
- **想理解课程流程**：先看下面的“一节课如何运行”，再按需要打开对应文件。
- **想修改项目**：先读 [MAINTENANCE.md](MAINTENANCE.md) 的维护边界，再用“按问题找文件”定位。
- **想备份或换电脑**：读 [备份与恢复说明](maintenance/backup-guide.md)。Git 不包含完整学习状态。

## 一节课如何运行

```text
开始或继续学习
  → Bootstrap 找到当前课程／下一课
  → 有复习题：逐题回答、反馈、保存草稿
  → 主课：独立首答、反馈；需要时澄清或修改
  → 展示总结，FinalizeSession 正式保存
  → 本轮结束时复盘，讨论并确认下一轮
```

课中保存的是可恢复草稿；课末提交成功才成为正式记录。断线或退出后，继续同一课程。当前流程使用 v4，新课堂带 `classroom_version=1`；v3 文件保留给历史审计和兼容测试。

## 目录里有什么

| 位置 | 用途 |
| --- | --- |
| [README.md](README.md) | 给人看的入口、流程和文件地图。 |
| [AGENTS.md](AGENTS.md) | AI 自动读取的工作分流与数据边界。 |
| [MAINTENANCE.md](MAINTENANCE.md) | 维护时按需读取的项目约束。 |
| [.agents/skills/english-coach/](.agents/skills/english-coach/SKILL.md) | 教练入口，以及按需读取的规则、脚本和材料。 |
| `learner/` | 学习者设置、计划、正式证据与复习记录。 |
| `sessions/` | 各节课的记录，按年、月保存。 |
| `.state/` | 当前课程草稿、运行版本、事务恢复信息、索引和课包；不是纯缓存。 |
| `maintenance/` | 备份工具、维护说明和历史输入示例。 |
| `tests/` | 自动测试；`*.cases.ps1` 由 v4 测试入口加载。 |
| [docs/design/](docs/design/learning-system-plan.md) | 长篇设计依据与提速方案，包含尚未实现的设想。 |
| `backups/` | 完整备份 ZIP，另存一份到其他存储位置。 |
| `.cache/` | 临时工具文件与隔离演练副本，不是正式学习档案。 |

## 按问题找文件

下面的规则文件都位于 `.agents/skills/english-coach/references/`。按当前问题阅读即可，无需一次读完。

| 想了解或修改什么 | 先看哪份说明 |
| --- | --- |
| AI 收到请求后如何选择下一步 | [SKILL.md](.agents/skills/english-coach/SKILL.md) |
| 新课堂的开课、逐题复习与转主课 | [classroom-flow.md](.agents/skills/english-coach/references/classroom-flow.md) |
| 主课题目与评分标准 | [task-contracts.md](.agents/skills/english-coach/references/task-contracts.md)、[activity-preparation.md](.agents/skills/english-coach/references/activity-preparation.md) |
| 答错后怎样反馈、修改与恢复 | [teaching-loop.md](.agents/skills/english-coach/references/teaching-loop.md) |
| 复习怎样出题与评级 | [review-teaching.md](.agents/skills/english-coach/references/review-teaching.md) |
| 复习排程及旧批次协议 | [review-protocol.md](.agents/skills/english-coach/references/review-protocol.md) |
| tracker 调用参数、课中保存与正式结课 | [tracker-actions.md](.agents/skills/english-coach/references/tracker-actions.md)、[runtime-protocol-v4.md](.agents/skills/english-coach/references/runtime-protocol-v4.md) |
| 跨轮判断目标、下一轮换目标 | [goal-review.md](.agents/skills/english-coach/references/goal-review.md)、[cycle-publication.md](.agents/skills/english-coach/references/cycle-publication.md) |
| 更完整的长期能力设计及实现范围 | [long-term-state.md](.agents/skills/english-coach/references/long-term-state.md) |
| 数据表字段与历史版本 | [data-schema.md](.agents/skills/english-coach/references/data-schema.md) |

代码统一从 [tracker.ps1](.agents/skills/english-coach/scripts/tracker.ps1) 进入。要读实现，可按下面定位到 `scripts/lib/`，不用从第一行顺序读完整项目。

| 实现文件 | 主要职责 |
| --- | --- |
| [classroom-runtime.ps1](.agents/skills/english-coach/scripts/lib/classroom-runtime.ps1) | 新课堂逐题流程、主课预备与返回下一步。 |
| [session-runtime.ps1](.agents/skills/english-coach/scripts/lib/session-runtime.ps1) | 开课、恢复、主课草稿和轮次目标判断。 |
| [transaction-runtime.ps1](.agents/skills/english-coach/scripts/lib/transaction-runtime.ps1) | 正式结课、事实写入与中断恢复。 |
| [cycle-runtime.ps1](.agents/skills/english-coach/scripts/lib/cycle-runtime.ps1) | 已确认目标与下一轮计划的发布。 |
| [reducers.ps1](.agents/skills/english-coach/scripts/lib/reducers.ps1) | 从输入记录计算复习、难度和能力候选的函数。 |
| [state-io.ps1](.agents/skills/english-coach/scripts/lib/state-io.ps1)、[v4-schema.ps1](.agents/skills/english-coach/scripts/lib/v4-schema.ps1) | 文件读写、校验、字段定义和动作契约。 |

## 当前收尾状态

截至 2026-10-02，已补上主课修改作答的保存与恢复、完整备份恢复、跨轮目标判断和确认后的目标更换。接下来按正常进度上课，验证实际等待时间和复盘体验。

已知后续事项：跨日复习名单刷新暂按用户决定保持原样；当前旧文字目标需要在后续复盘确认结构化新版本；完整能力等级／阶段升级、更多进步标记和更正记录的自动重算仍待扩展。这里的“已实现”不代表长篇设计方案已全部完成。

## 维护与测试

在项目根目录运行现有 PowerShell/Pester 测试入口：

```powershell
Invoke-Pester -Script tests/tracker.Tests.ps1,tests/tracker-v4.Tests.ps1,tests/backup.Tests.ps1
```

测试在隔离目录使用样例数据。普通上课无需运行测试、迁移或重建命令。`.previous` 是上一代恢复文件，v3 文档和 fixtures 是兼容依据，均不当作无用重复文件删除。

历史方案：[学习系统设计](docs/design/learning-system-plan.md)、[课堂提速方案](docs/design/classroom-latency-plan.md)。历史发布输入位于 [maintenance/examples/c0005-publication.json](maintenance/examples/c0005-publication.json)，用于阅读和测试，不能直接作为新的已确认计划执行。
