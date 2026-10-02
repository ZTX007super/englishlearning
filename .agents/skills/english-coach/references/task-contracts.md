# 可评分活动契约

仅在活动会产生评分、复习结果或能力证据时读取本文件。普通说明、澄清和不计分练习不需要独立契约；它们继承父活动的边界。

## 展示前冻结

每个可评分活动在题面展示前必须拥有稳定 `activity_id` 和冻结契约。契约至少包含：

- `activity_family`、`modality`；
- `purpose: practice | probe | transfer | assessment`；
- `mode: accuracy | fluency | mixed`；
- `primary_construct`；
- 最多三条 `criteria`，每条有稳定 `criterion_id`，并标记 `essential` 或 `required`；
- 内部判定依据及可接受答案或语义范围；
- 正常允许的准备时间、回看、重放、参考和 access condition；
- `correction_timing`；
- 预选的教学 adapter、提示阶梯和最大允许支持；
- `transfer_rule`、重试上限和剩余复杂度预算；
- v4 `prepared_step` 已给出的 competency、indicator、evidence mode、难度条件、content/context 和版本引用。

契约冻结完成的标准是：学习者能从题面知道要完成什么；评分范围覆盖常见合理答案；AI无需看到回答就能说明成功条件；题目、答案、criteria、支持边界和版本引用一致。

AI可以在冻结语义范围内判断一个新同义表达是否成立，但不能在看完回答后新增要求、缩窄语义范围、改变活动用途或把普通练习追认为正式证据。

## 活动与循环标识

- 澄清、提示、原句修复和同一功能的帮助升级沿用 `activity_id`，使用稳定 `loop_id` 区分被处理问题。
- 新题、新材料或新语境迁移必须创建新的 `activity_id`，并重新冻结契约。
- 已看过示范的原活动只在受影响的 `criterion_id / loop_id` 上失去独立性；不能把修复后的同题答案记为新的无提示首答。
- 同一回答只形成一个 observation；primary 与可选 secondary 是该 observation 的不同投影，不是两次独立表现。

## 统一结果算法

按以下顺序计算，保留各 criterion 的单独结果：

1. 技术故障、题意含糊、证据不足或条件不可比导致无法公平判断：`task_result = not_assessable`。
2. 任一 `essential` 未满足：`task_result = failed`。
3. 所有 `essential` 满足，但至少一个 `required` 未满足：`task_result = partial`。
4. 所有标准满足：`task_result = success`。

每条标准使用 `criterion_result: met | partial | not_met | not_observed`。上游失败使标准未被公平观察时使用 `not_observed`，不能写成 `not_met`。

局部语言问题只有在它命中预声明标准，或已经阻断、改变、严重模糊意义时才影响任务结果。因此任务可以 `success`，同时某个焦点质量标准为 `partial`；正确但可更自然的表达属于升级机会，不得把成功改成失败。

## 八种 activity family

### `source_comprehension`

阅读或听力的主旨、事实、态度、指代、意图和关系理解。命题反转、关键事实或关系错误、答案无关可以失败；回答中的非阻断语法错误不使理解任务失败。

### `retell_summary`

保留预声明的核心意义单元。中心意思遗漏或反转、因果或人物关系失真、无依据编造可以失败；没有照搬原文措辞不算失败。

### `opinion_explanation`

完成直接回应、明确立场及要求的理由或例子。未回答、立场不可辨或意义无法恢复可以失败；语言简单但要求完整仍可成功。

### `interaction_roleplay`

完成请求、确认、澄清、拒绝等预声明交际动作。交际目的未实现或对话无法继续可以失败；自然度和礼貌只有列为标准时才影响结果。

### `integrated_response`

忠实整合两个及以上来源，或材料与观点。歪曲来源、遗漏必需的来源关系或说反材料立场可以失败。

### `controlled_form`

选择、转换或产出指定语法、词义、搭配或句式。目标形式或意义错误影响任务结果；与目标无关且不改变答案的小错不影响。

### `extended_writing`

完成预声明的体裁、受众、目的、核心内容与来源要求。跑题、核心信息缺失或中心意思不可理解可以失败；局部语言质量按独立标准记录。

### `oral_imitation`

复现规定内容并保持可懂度。内容严重遗漏或无法辨认可以失败。只有取得可靠音频且工具实际分析声音时才能判断发音特征，否则相应标准为 `not_assessable`。

TOEFL 任务先映射到一种 activity family，再叠加限时、材料、评分和 competency 条件；题型名称本身不创建另一套结果逻辑。

## 交付给教学循环

收到首次回答后，在内存中一次产生：

- `task_result` 与全部 `criterion_results`；
- validity 与未被公平观察的标准；
- 首次回答中最小充分的判定片段；
- 候选 `issues[]`，交给 [teaching-loop.md](teaching-loop.md) 归因和仲裁；
- 实际 access/support、答案暴露与成本信号。

该判断先用于可见反馈，再以同一稳定 ID 冻结进 session checkpoint。课末事务只能提交已经冻结的首答判断，不能根据重试、范文或整课印象重判。
