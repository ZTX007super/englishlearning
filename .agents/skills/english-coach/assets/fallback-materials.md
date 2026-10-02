# 原创备用材料

这些内容由本项目原创，用于缓存材料不可安全呈现且一次外部替代失败时继续同队首 training。它们不是官方 TOEFL 材料。

[`fallback/manifest.json`](fallback/manifest.json) 是机器索引。只有 manifest 中 `presentable=true` 且全部必需文件与 hash 验证通过的条目才能作为 ready fallback。下列文字条目不是音频；不得用于需要真实听力输入或发音判断的正式活动。

## Campus Club Fair（B1）

Maya planned to visit the campus club fair for only ten minutes, but she stayed for almost an hour. She first spoke with the photography club because she wanted to learn how to take better pictures. Then a student from the volunteer club explained that members helped children with their homework every Saturday. Maya liked both groups, but her class schedule was already busy. She decided to attend one meeting from each club before choosing.

任务：概括主旨；说出 Maya 感兴趣的两个社团；解释她为什么没有立即决定；用 45 秒说明你会选择哪个社团。

## A Better Study Break（B1+）

Many students take breaks by checking short videos, yet this may not help them feel rested. Rapidly changing content continues to demand attention, so the brain receives new information instead of recovering. A short walk, a glass of water, or a few minutes of stretching can create a clearer separation between study periods. The best break is not necessarily the most entertaining one; it is the one that helps a student return with better focus.

任务：找出作者观点和两条支持理由；用自己的话解释 `separation`；给一位沉迷短视频的同学提出建议。

## Interview: Using AI at University（B2）

问题依次提出，不要一次展示全部：

1. How do university students currently use AI in their studies?
2. What is one useful benefit and one serious risk?
3. What rule should a university adopt, and why?
4. Tell me about a situation in which a student should not use AI.

追问重点：具体例子、原因、让步表达和清晰结论。

## 已就绪的原创听力条目

- [Campus Repair Corner](fallback/transcripts/campus-repair-corner.md)：B1，校园公告/对话型输入。
- [A Quiet Change to Study Time](fallback/transcripts/quiet-change-to-study-time.md)：B1+，解释型短讲。

两条 transcript 与 metadata 已冻结，并已使用本机离线 `en-US` 语音生成 WAV。音频与 transcript 的 SHA-256、时长、权利说明和 `presentable=true` 均记录在 manifest；tracker 仍须在每次使用前核对文件与 hash。它们只能作为项目原创 training fallback，不能冒充真人录音或官方 TOEFL 材料。
