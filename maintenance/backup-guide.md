# 备份与恢复学习项目

Git 保存代码版本，不是这个项目的完整学习备份。`.state/` 被 Git 忽略，其中却有运行版本、课程草稿和恢复事务；换电脑时只拉取仓库不足以接着学习。

## 哪些内容需要保留

| 内容 | 用途与备份策略 |
| --- | --- |
| `learner/`、`sessions/` | 正式学习档案与课程记录，完整备份。 |
| `.state/` | 包含运行版本、进行中课程、提交回执、恢复事务、旧版本迁移快照，以及程序当前依赖的索引和课包；完整备份，包含 `.previous` 上一代文件。 |
| `.agents/`、维护脚本、说明文档及项目内材料 | 与数据一起保存当前实际文件，包括未提交到 Git 的代码，避免恢复时代码与记录不匹配。 |
| `.cache/`、`*.tmp`、`*.lock` | 临时缓存、写入中间文件和进程锁，不备份。 |
| `.git/`、`backups/` | Git 历史另由 Git 保存；排除已有备份，避免备份套备份。 |

课包、索引和展示视图在概念上可以重建，但项目目前没有完整的“一键重建全部状态”流程，因此恢复时也保留它们。`downloads/`、`generated-audio/` 若存在会随项目备份，避免正在使用的本地材料丢失。项目外的文件和外部网址内容不在备份范围内。

## 创建备份

暂停学习与代码编辑，在项目根目录的 PowerShell 中运行：

```powershell
.\maintenance\backup.ps1 -Action Backup
```

成功返回 `backed_up` 和 ZIP 路径，默认位于 `backups/`。备份包含逐文件 SHA-256 校验清单；程序取得 v4 写入锁，并复查复制期间文件是否变化。遇到正在写入或文件变化，请等操作结束后重新备份。旧版工具不共享该锁，因此仍需暂停使用。

把成功生成的 ZIP 另存到移动硬盘或你自己的其他存储位置；只留在当前硬盘上的副本不能应对硬盘损坏。可以在重要维护前、完成一轮学习后各备份一次。这里没有自动上传或定时任务。

## 校验与恢复

将示例 ZIP 路径替换成实际路径；恢复目录必须是尚不存在的新文件夹。

```powershell
.\maintenance\backup.ps1 -Action Verify -ArchivePath '.\backups\你的备份.zip'
.\maintenance\backup.ps1 -Action Restore -ArchivePath '.\backups\你的备份.zip' -Destination 'D:\projectfile\englishlearning-restored'
```

`Verify` 返回 `verified` 才表示全部文件与清单一致。`Restore` 会先做同样检查，再写入新目录，返回 `restored`；已有目录一律拒绝，不提供覆盖选项。校验能发现意外损坏，不代表外来 ZIP 值得信任；只恢复你自己保存的备份。

在恢复目录运行以下检查，确认返回的版本、队首和等待动作符合备份时的状态：

```powershell
Set-Location 'D:\projectfile\englishlearning-restored'
.\.agents\skills\english-coach\scripts\tracker.ps1 -Action Bootstrap
```

Bootstrap 可能完成备份中未结束的合法事务，所以先在恢复副本上检查。确认成功后，把恢复目录作为项目打开并继续学习；原项目仍保持原样。恢复副本不含 Git 历史，需要时单独连接原仓库。

若连维护脚本也丢失，可以先用系统解压工具把自己保存的 ZIP 解压到新的临时目录，再用其中的 `maintenance/backup.ps1` 对原 ZIP 执行 Verify 和 Restore。不要直接在尚未验证的临时解压目录开始学习。

## 失败处理

备份失败可能留下 `.partial` 文件；它不是可用备份。恢复时磁盘空间不足等错误可能留下部分目录；保留原 ZIP，解决原因后改用另一个新目录重试。工具不自动删除目录，也不修改当前 runtime、排程或学习记录。链接文件或目录会明确拒绝，避免悄悄漏掉指向项目外的材料。
