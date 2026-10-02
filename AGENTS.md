# English Learning 项目路由

本文件只分流工作状态并守住数据边界；进入维护状态时按需读取 [`MAINTENANCE.md`](MAINTENANCE.md)。

## 状态路由
1. 英语学习、练习、复习、批改、口语、写作、测评、进度或学习计划输入进入**教师状态**。
2. 架构、代码、测试、文档、schema、tracker、skill、数据维护或迁移输入进入**维护状态**。
3. 混合请求先识别各部分；学习数据写入只发生在用户明确要求的教师流程或获授权的维护操作中。

## 教师状态
- 必须使用项目的 `$english-coach` skill，并先服从 tracker `Bootstrap` 返回的版本、队首和 `next_action`。
- Tracker 入口固定为项目根目录下的 [`.agents/skills/english-coach/scripts/tracker.ps1`](.agents/skills/english-coach/scripts/tracker.ps1)；skill 内相对路径均以其 `SKILL.md` 所在目录为基准。
- 一次只推进当前学习动作；依据、纠错、复习、难度和提交规则由 skill 及其按需 reference 决定。
- 普通学习中不执行代码维护、Git 操作、全量校验或迁移。
- 只有 committed tracker receipt 可以被报告为正式保存或课程完成。

## 维护状态
- 先读取 [`MAINTENANCE.md`](MAINTENANCE.md) 中与任务相关的边界，再按需读取 skill、reference、schema 和测试。
- 把 `learner/`、`sessions/` 与 `.state/` 视为真实用户数据；优先只读检查，修改需有明确任务依据。
- 维护改动与学习记录分开验证；保留用户既有改动，不顺手重建派生视图。

## 数据与迁移门
- C0003 和旧进行中 session 使用 v3；C0004 只在全部门禁通过且用户显式确认后启用 v4。
- `MigrationPlan` 保持只读；`ActivateV4` 必须同时具有 schema 合规清单、幂等键和显式确认。
- Bootstrap 只恢复已经合法创建的迁移事务，不能自行发起迁移。
- v4 激活提交后，从主 `SKILL.md` 移除 v3 分支以缩短上下文；保留 v3 schema/protocol 供历史审计。

## 完成标准
- 修改任务必须完成目标、运行与风险相称的验证，并报告未解决问题。
- 未取得新授权时，保持当前 runtime 和真实学习数据不变。
