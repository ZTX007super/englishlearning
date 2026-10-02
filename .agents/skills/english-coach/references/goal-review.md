# Focus goal 实用复盘

本文件定义普通轮次复盘已接通的范围；long-term-state 中完整 competency、stage、insight 与全部 progress marker 规则仍是后续能力，不视为已经实现。

## 执行与完成

1. `evaluate_cycle_review` 时调用 `EvaluateLongTermState -SessionId`。程序只读正式记录，计算同一 goal ID 最近最多四个完成轮次的目标候选；当前轮训练已结束时纳入本次复盘。自然停学不增加轮次。
2. 展示 `goal_candidates` 的 decision、reason、evidence_ids 与 coverage：完成轮数、本轮独立机会、成功次数、是否有确认、被排除记录数、下一证据缺口。区分“能力未达到”“缺少独立检查”“旧目标契约待升级”“证据待审计”。不得把技术或记录缺口说成学习者失败。
3. 总结展示后将候选原样放入 `FinalizeSession.goal_decision`。提交时程序复核 goal_id、decision、reason、evidence_ids、catalog_version、goal_contract_version；不同则重新读取并解释变化，不能强行保存旧候选。只有 committed receipt 表示决定入档。
4. 讨论下一轮：继续目标可沿用 goal ID；更换或重设目标通过 PublishCycle 的 `next_goal` 保存，详见 [cycle-publication.md](cycle-publication.md)。先确认目标内容及计划，取得发布回执后才报告生效。

## 证据与结论

只计完成课程中、与目标 ID、competency、activity family、catalog、indicator、anchor 匹配的独立首次 A 类记录。支持程度必须为 none；契约标准有完整结果，context 和学习日可识别。首答契约身份与 evidence mode 由 PrepareActivity 冻结；SaveActivityCheckpoint 从契约绑定到 observation。修复不增加独立证据。

同一 observation ID 只算一次。重复 ID 或相关 correction/void 使候选提示 `evidence_audit_required`；实用版尚不自动重放这些改正，审计解决前不宣告 met。

- **met**：达到目标最少轮数（至少两轮），至少三次满足全部必要标准及 guardrail 的独立成功，跨至少两天、两个 context；有预先以 `evidence_mode=assessment` 冻结且 normal-cost 的成功确认。确认同日或之后没有失败，本轮没有 guardrail 退化。
- **insufficient_evidence**：本轮有效独立机会少于两次；以前轮次的数量不能填补本轮缺口。旧文字标准没有结构化绑定时返回 `goal_contract_upgrade_required`，不追溯补造标准。
- **continue**：未达到 met，但本轮首次出现从先前失败到跨日独立成功的 criterion_acquired 标记；或首次证据充分但没有新标记。
- **redesign**：连续两个证据充分轮次没有新标记；或达到目标最多完成轮数仍未 met。到上限仍证据不足时也重设取证设计，不无限延期。待审计问题保持 insufficient_evidence。

当前只计算上述保守的 criterion_acquired 标记；support_withdrawal、context_transfer 及更细的反证解决仍待扩展。不会仅因新的 context ID 就声称完成了新情境类别迁移。

`coverage.next_evidence_needed` 是计划建议，不是发布门槛。下一轮通常应安排两次与目标直接相关的独立检查，并在合适课位安排正常条件下的 assessment 确认；材料和标准在首答前冻结，不能答完后把 training 改标成 assessment。保持六课覆盖听说读写，复习排程独立。可以发布尚未满足取证建议的计划，但复盘时必须如实说明因此无法判定的部分。

## 结构化目标契约

沿用 focus-goals.tsv 的 `success_criteria_json` 字段，不修改表头；新目标写入 JSON 对象：

```json
{
  "schema_version": 1,
  "catalog_version": "1.0.0",
  "indicator_id": "S_EXPLAIN.message_sequence.B1",
  "anchor_id": "S_EXPLAIN.B1.ANCHOR",
  "required_criterion_ids": ["CR-S-OPEN", "CR-S-DEVELOP"],
  "guardrail_criterion_ids": ["CR-S-END"],
  "confirmation_evidence_mode": "assessment"
}
```

示例 ID 仅示意，真实值取批准目标、当前目录和活动契约；必要标准 1–4 个，guardrail 最多两个，ID 不重复。目标文字解释这些标准的含义；焦点检查活动使用相同标准 ID。新版本从下一轮开始累计，不能继承旧版成功来凑门槛。旧目标原有文字数组保留为历史，需要确认后新建版本才使用上述结构。
