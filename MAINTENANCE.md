# English Learning 维护约束

维护代码、文档或数据时，按需读取本文件中的项目约束。影响课程执行的规则由 [`english-coach` skill](.agents/skills/english-coach/SKILL.md)、其按需引用的协议和 tracker 实现承载。

## 项目定位

本项目保存长期英语学习档案。课程以 CEFR 对齐的可观察能力为长期地图，分别追踪听、说、读、写，并兼顾日常交流与当前 TOEFL iBT 基础准备。阶段、焦点和难度变化依赖证据与轮次复盘，不因自然时间或完成轮数自动发生。

与英语学习、批改、口语、到期复习、测评、进度或计划有关的请求，应使用项目 skill `$english-coach`。该 skill 是 AI 行为的入口；本文件不复制日课、复习、纠错、缓存或提交状态机。

## 安全与数据边界

- 只修改项目内与英语学习直接相关的文件；保留既有 session、事件历史和学习者原始记录。
- 通过与当前 `runtime_version` 兼容的 tracker 动作写入正式学习数据。事件账本与 committed receipt 是事实；dashboard、current plan、长期 projection、bootstrap index 和课包缓存均是可重建派生物。
- `.state/current-session.json` 只保存恢复和最终提交所需的有界草稿。正式档案只保留必要表现片段与引用，不保存完整私密对话、完整音频或无关个人信息。
- 外部材料必须满足可访问性、真实性与权利边界。时间敏感的考试规则以带验证日期和适用考试日期的官方记录为准，不把本项目估计称为 ETS 官方成绩。
- 不安装全局依赖。不要自动推送远程仓库。若轮次复盘允许创建本地学习快照，只暂存该轮学习记录；维护代码、测试和 skill 改动与学习快照分开。
- C0003 与旧进行中会话保持 legacy 语义；C0004 只有在迁移、fallback、恢复与校验门全部通过后才启用新协议。不得给历史记录补造 contract、支持程度、迁移或高等级证据。

## 维护入口

- Agent 路由与共同关键路径：[`SKILL.md`](.agents/skills/english-coach/SKILL.md)
- 人类阅读入口与文件地图：[`README.md`](README.md)。
- 追溯设计理由时读取 [`docs/design/learning-system-plan.md`](docs/design/learning-system-plan.md)；它包含未实现设想，当前执行按 skill 与对应协议。
- 备份、换电脑或恢复学习状态：按 [`maintenance/backup-guide.md`](maintenance/backup-guide.md) 保存包含 `.state/` 与当前代码的完整备份，并先恢复到新目录验证。
- 存储结构、课程地图和运行细节由 skill 根据当前分支与版本渐进加载。
