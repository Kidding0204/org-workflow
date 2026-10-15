# org-workflow 源码恢复

最初在 `/tmp/emacs-recovery-workflow` 隔离恢复，现已部署到 `~/.config/emacs/user-lisp/org-workflow`；未推送。

基线远程：<https://github.com/Kidding0204/org-workflow.git>；main HEAD
`7691ddadaf13ea468df7f38ec85a6a35c88f1749`，提交日期 `2026-10-11T16:43:36+08:00`。

## 本地附加源码

以下均来自既有 Codex session 的原始工具调用内容，按时间重放，仅将文件目标约束在恢复目录：

- 10/11：GNOME 周指示紧凑样式、琥珀橙请假色、上下几何居中，周日到周六排序及对应包测试。
- 10/12：历史任务读取先判断直接 CLOCK 或当天 CLOSED，再构造条目；保留即时源文件读取行为及回归测试。
- 10/13：单次 status-json 共享任务／进度读取，显式空任务不再重复读取；events(id) 索引；补结算候选和兑现日期复用；GNOME 动作期间刷新合并；对应测试和原验证文档。
- 10/14：桌面选择器复用原生 emacsclient 创建的专用 minibuffer frame，避免依赖 daemon 的显示环境；对应分发／选择测试。

文件的远程／恢复 SHA256、会话文件、工具行号见 `RECOVERY-SOURCES.json`。
原始补丁／命令及隔离重放脚本在 `/tmp/workflow-recovery-evidence`。历史 shell 命令中涉及真实配置、实时 Emacs、外部临时文件、父配置测试的部分没有执行；只重放包目录内原始源码变化。
10/13 原历史命令在追加 attempt 测试后因 panel 测试没有 provide 标记而中断，后续历史调用改为追加 panel 测试；本次同样保留其已写入的 attempt 测试并执行后续追加。

## 未恢复和边界

- 未从无源码证据的运行时 bytecode 编造额外源码；不能证明未出现在 session／远程中的手工改动也已恢复。
- 已扫描 10/13–15 会话中的包相关修改，以及晚于远程 HEAD 的 10/11–12 会话调用；未找到 10/15 对本包源码的新增修改。
- 真实 Org 文件、SQLite 历史、任务事实、GNOME 已安装目录由其他恢复工作单独保全，本 checkout 不读取／导入它们。
- 恢复原有测试缺陷，不自动修复无关逻辑：`workflow-leave-panel-distinguishes-completion-leave-and-unknown` 仍使用周一起点旧索引。原 10/13 记录已在修改前 HEAD 单独复现此失败。
- 原始未推送 Git commit 对象／原暂存区不可由工具文本恢复；此次提交标明为恢复提交。

## 本次验证

- 81 个 Lisp 文件 `check-parens` 通过。
- GNOME `tests/*.test.js` 全部通过（14 个通过消息，含动作刷新合并）。
- `bash -n extras/bin/org-workflow-client`、`git diff --check` 通过。
- 隔离 HOME/XDG 首次 `make test` 因尚未恢复的依赖 `org-super-agenda` 无法加载，未触及真实配置。
- GUI／daemon／桌面会话尚未验收。

## 依赖恢复后的验证

相关 ERT 共 90 项：89 项通过。旧的 weekly document 测试尝试写入默认 ~/org 路径，被只读沙箱阻止；未为此修改原有逻辑。父配置已在独立 batch 进程完成 init.el 加载，GUI/daemon 重启仍未验收。

## 2026-10-15 桌面延迟优化复核

- 按 Codex 原始调用时间核对：10/12 历史标题预筛选、10/13 单请求缓存、空结果复用、events(id) 索引及扩展动作刷新合并已在包源码。宿主 core-optimize.el 的 GCMH 包装亦在。
- 补回仅在父配置扩展中的 10/14 选择菜单与 select 白名单，合并到包的扩展和相应测试。来源为历史索引 calls.rowid 1423（2026-10-14T14:25:35.430Z）和 1431（2026-10-14T14:28:23.740Z）。
- 已安装扩展缺少 10/13 刷新合并，且 workflow-state.js 仍是 10/8 旧逻辑；本次同步合并后的 extension.js、sync.js、workflow-state.js。桥接沿用包的 ~/.local/bin/org-workflow-client，已与宿主 bin 副本逐字核对相同。
- 合并后的全部 GNOME *.test.js 通过（14 条通过消息），包含动作成功、失败、交错刷新和选择动作检查。
- 扩展 ERT 检查 21 项，20 通过。延迟相关的预筛选、空任务单次读取、请求事实／进度共享、读取失败不缓存和源文件行为均通过；另发现既有 org-workflow-select-scope-and-refresh 对 READY “Other” 候选期望失败（实际仅 Scheduled）。本轮未改动 Lisp 或该测试，保留此问题，不扩展修复。
- 本轮不操作真实任务、Org 或 SQLite 数据，不热重载 Emacs、不注销 GNOME；桌面实际点击延迟未重新测量。安装的 JS 文件需在 GNOME 重新加载后才保证生效。
