# 学习数据格式

所有日期使用 `YYYY-MM-DD`。TSV 文件必须保持制表符分隔和 UTF-8 编码。

## learner/vocabulary.tsv

列顺序固定：

`id, item, meaning, context, status, level, next_review, last_review, source_session`

- `id`：`V` 加四位数字，如 `V0001`。
- `status`：`active`、`mastered` 或 `paused`。
- `level`：0–5，对应 1、3、7、14、30、60 天复习间隔。
- 新项目从 level 0 开始，`next_review` 通常设为下一天。

## learner/error-log.tsv

列顺序固定：

`id, category, original, corrected, explanation, status, level, next_review, last_review, source_session`

- `id`：`E` 加四位数字。
- `category`：如 `grammar`、`word-choice`、`organization`、`listening`。
- 只记录可能复发、值得间隔复习的问题，不收集一次性笔误。

## sessions

每次会话保存到 `sessions/YYYY/MM/YYYY-MM-DD.md`；同日多次时使用 `-02`、`-03`。YAML frontmatter 至少包含：

- `date`
- `session_type`
- `status`
- `duration_minutes`
- `primary_skill`

正文保存目标、材料来源、学习者表现摘要、最多三个重点反馈、新增/复习项目和下一步。不要保存无关隐私。

## dashboard

至少维护：最后更新日期、诊断状态、当前阶段、四周完成率、四项能力证据、到期项目数、重复错误和下一里程碑。缺失数据写 `尚无证据`，不要猜测。

