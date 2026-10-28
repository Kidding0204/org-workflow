# org-workflow 全包审查（2026-10-28）

后续已批准的修复与验证见 [修复记录](2026-10-28-org-workflow-repairs.md)。本文件保留审查时的事实。

审查基线：`5b1ff8786caabda714142029da95d26059e18c8e`。
范围为 40 个根目录 Lisp 库，以及 GNOME、shell 客户端、历史网页和构建入口。
按 ub-mode 检查身份、状态、持久化边界、撤销、决策归属和可验证性。
本次只提交审查文档，没有修复实现、改写真实 Org／SQLite 或重载用户会话。

确认 11 类行为问题，其中 4 类为 P1（优先修复的数据／身份问题），7 类为 P2。
这里的 P1 不表示日常每次操作都会失败；各条均列明触发条件和验证边界。
现有测试失败另列，不能把失败数量当作缺陷数量。

## 1. P1：源 marker 漂移后，完成命令会修改另一条任务

位置：`org-workflow-core.el:850` 的 `org-workflow-target--selected-entry`、
`:1031` 的 `org-workflow-target--ordinary-marker`，以及
`org-workflow-items.el:133` 的完成入口。

选择 Tokens 后，剪切它的完整 Org 子树，再刷新并执行“完成当前任务”，
原本未安排的下一项 Parser 被改为 DONE。复现使用公开选择／完成命令与原生
`org-cut-subtree`，不是直接伪造内部对象：

```elisp
;; 采用 test/org-workflow-projects-test.el 的 workflow-project-fixture。
(org-workflow-target-select-marker (workflow-project-at "Tokens"))
(org-with-point-at org-workflow-executing-marker (org-cut-subtree))
(org-workflow-target-refresh t)
(org-workflow-target-complete)
```

根因：marker 只跟踪文本位置。删除原子树后，marker 仍存活且指向下一标题。
手动选择只重新检查当前位置的资格；执行选择甚至只检查 buffer 是否存活，
两者都没有验证“它还是原来选择的任务”。

修复应保存并验证选择时的任务身份，失效时解除选择或拒绝操作。
不要把“marker 存活”继续当作身份校验，也不要在只读刷新中自动补写 ID。

同一身份缺口在键盘归类中另有一个 P2 表现：Sprint 保留旧行时，将源 First 的
标题与 ID 替换为 Replacement／different-task 后保存，旧行的公开 `C` 归类仍移动并
保存新任务。归类只检查它现在还是 Inbox 任务，不对照视图中的来源身份。
位置为 `org-workflow-project-classify.el:81`、`org-workflow-agenda-projects.el:369`。
复现经过真实双栏 Sprint 与公开 classify-selected，仅替换目标选择提示。
普通删除后 marker 落到另一条已显示行的情况可能被 UI 重复行检查拒绝；
本报告不把底层缺口扩大描述成所有删除场景。拖动路径另有标题核对。

## 2. P1：替换每日承诺后 U 只恢复部分事实，责任变成零项

位置：`org-workflow-agenda-plan-undo.el:49`、`:104`，
`org-workflow-agenda-mouse.el:525` 的撤销注册，以及
`org-workflow-commands.el:95` 的每日承诺替换。

在一个 DIVE 项目中，把两项任务安排到今天，首项已是当天承诺。
在 Sprint 用鼠标菜单把承诺换成第二项，然后执行 `U`。
实际结果：旧承诺 SQL 状态恢复为 pending，但旧任务的承诺属性仍被移除；
`project-day:日期:项目` 仍指向已取消的新承诺，旧承诺仍受 `project-superseded` 事件影响。
当天有效责任从 1 项变为 0 项，`history-progress` 返回 `:minimumTotal 0`。

根因：通用安排撤销只记录所选条目的安排属性和 commitment 行。
它假设安排不改变归属，但每日承诺替换同时改变另一任务的关联、项目当日索引和事件语义。

应把承诺替换视为完整的领域操作，撤销时恢复所有受影响关联并追加补偿事实。
不要直接删除历史事件或整文件回退，以免损失后续笔记／CLOCK。
复现经过真实 Sprint 渲染、公开鼠标承诺入口与公开 U 入口；没有模拟物理鼠标事件。

## 3. P1：TODO 操作失败后，文本回滚会丢失正在结束的 CLOCK

位置：`org-workflow-commands.el:151` 对 `org-todo` 的事务包装，
`org-workflow-store.el:280`、`:290` 的执行／文本回滚。

任务已有约 25 分钟的运行中 Org Clock。执行 `org-todo "DONE"`，
在后续 `org-after-todo-state-change-hook` 中注入错误。
原生状态变更已经关闭计时，但事务回滚只恢复 buffer 文本。
结果是 TODO＋开放 CLOCK 文本，同时 `org-clock-is-active` 为 nil，且没有关闭记录。
该段时间无法通过正常的已关闭 CLOCK 统计计入投入。

对照实验关闭 Workflow 存储包装，执行相同操作与同一失败 hook，
原生 Org 保留 DONE 和已关闭 CLOCK。差异来自 Workflow 的文本事务边界。

根因：文本变更组可以回退文本，不能回退 Org Clock／Focus Timer 的运行状态和外部副作用。
修复应像现有 step 入口一样，明确结束计时与可回滚变更的先后边界，
或完整协调运行状态；不能仅增加一个捕获错误的 guard。

## 4. P1：SQLite 提交与内部提交标记之间的中断会清空正确的恢复映像

位置：`org-workflow-store.el:285` 至 `:291`。

在真实 SQLite COMMIT 完成后、`committed` 尚未设为 t 的边界注入 quit：
数据库已有 1 项新承诺，但 buffer 被撤销；operations 被改成 rolled-back，
before／after 映像同时清空。随后启动恢复无法再用这些映像修复分歧。

根因：持久提交和 Lisp 标记不是一个不可中断的短临界区。
清理逻辑只依据未更新的标记，错误地把已提交操作当成未提交操作。
history 的结算／习惯同步已经用 `inhibit-quit` 保护相应短边界，通用 store 操作没有。

应保护提交与内存状态切换的短临界区，在提交结果不确定时保留恢复事实。
本条通过确定性故障注入验证；未在真实 GUI 中碰撞 C-g 时机，也未测量其发生频率。

## 5. P2：事务内保存后再失败，会留下磁盘／buffer／数据库三方分歧

位置：`org-workflow-store.el:277` 至 `:295`。

在状态变更 hook 中先 `save-buffer`，再由后续 hook 报错。
公开 `org-todo` 路径实测：磁盘为 DONE，buffer 回退为 TODO，承诺 SQL 状态为 pending。
更小的 store 操作复现中，磁盘保留了新的承诺 ID，但数据库没有对应承诺，
恢复映像仍被清空。

根因：禁止事务内 checkpoint 不等于禁止源文件落盘。
当前回滚仅处理 SQLite 和内存变更组，没有处理已保存的文件。

应明确受支持的事务内保存策略：在可控入口延迟保存，或识别已落盘状态并保留可恢复事实。
不要在异常处理里无条件覆盖磁盘，以免覆盖并发的外部编辑。
本条的触发需要会保存源文件的 hook／调用者，不声称默认完成命令必然执行该保存。

## 6. P2：祖先 HOLD 后，子任务离开队列却仍然是当前执行对象

位置：`org-workflow-core.el:1031`、`:1273`。

选择项目下的 Tokens，再通过公开项目状态命令将 Compiler 设为 HOLD 并刷新。
Tokens 已从执行队列消失，current-item 却仍返回位于 HOLD 子树中的 Tokens。

根因：状态 hook 只在改变的标题与 executing-marker 完全相等时释放执行选择，
读取当前对象时又只验证 marker 存活，没有检查祖先状态。

应在祖先状态变更时统一协调执行对象，并在动作入口验证执行资格。
不能只隐藏队列行；那会保留可执行但不可见的对象。
复现验证 current-item 与队列分歧，没有据此声称实际计时器已经停止或继续。

## 7. P2：DONE 分支的执行资格与每日责任取决于不同规则

位置：`org-workflow-core.el:310`、`org-workflow-projects.el:205`，
对照 `core.el:288` 的 `org-workflow-target--execution-blocked-p`。

将含有今日 TODO 任务的阶段 Lexing 设为 DONE 后，Tokens 仍进入执行队列，
而共享的 execution-blocked-p 明确认为它不可执行。
已有的当日责任仍为 pending；关闭阶段后才首次同步则不会给它建立责任。
同一最终状态产生不同准入结果，取决于先前是否同步。

根因：队列及已有责任协调使用 HOLD-only 检查，首次责任选择使用 DONE／HOLD 检查。
应在明确的领域入口统一关闭分支政策，或拒绝仍有未完成任务的关闭动作。
“阶段 DONE 后必须自动撤回责任”是可选择的修复政策，本审查不替用户决定；
已确认的问题是当前多个路径的规则分歧。

## 8. P2：当前完成策略下，HOLD 又被计入阶段达标

位置：`org-workflow-core.el:634`，对照 `org-workflow-history.el:84`。

新 completion-floor 策略关闭旧 attempt 策略。
stage-progress 把“旧 attempt 未启用”误当成“适用最早的 held／ready 达标规则”，
于是新策略也重新计入 HOLD。
没有 DONE 任务的临时案例返回 `(:stageSatisfied 1 :stageTotal 2)`。

应显式区分历史策略边界，并复用当前 DONE 完成语义。
不能用“某个旧策略未启用”来代表唯一的另一种策略。
已验证公开 status 使用此字段；没有声称已观察到当前 GNOME 的具体视觉结果。

## 9. P2：同文件、同标题、无 ID 的习惯共享可操作身份

位置：`org-workflow-items.el:64`、`org-workflow-panel.el:294`。

两个有效原生 Org habit 均无 ID、标题相同、提醒时间不同。
备用 key 只哈希“文件＋标题”。点击第二项对应 key 后实际选择第一项，
两行同时显示 selected=t。临时源中请求位置 112，实际解析位置 1。

这是当前习惯读取器接受的输入，不是伪造非法对象。
应让动作身份区分实际源标题，或在用户创建／操作边界明确要求 ID。
保留只读轮询，不在渲染时静默创建 ID。

## 10. P2：当前历史导出无法被自带网页读取

位置：`extras/web/src/history.ts:169`、`:224`，
生产者为 `org-workflow-history.el:268`、`:290`、`:485`。

实际临时 SQLite 结算经正式导出后，真实 TypeScript parser 拒绝
`dailyMinimumMinutes`；删掉三个 dailyFloor 字段后，继续拒绝任务的 `satisfied`。
生产者增加了字段，但严格的 schema-v1 消费者没有同步更新。
原生 history validator 接受同一 payload，所以影响范围是保留的网页配套。

应一起维护生产者与消费者的字段契约，并用真实导出 payload 验证前端解析。
未安装 npm 依赖，也未运行 Vitest／网页渲染；本条直接运行无外部导入的真实 TS parser。

## 11. P2：菜单历史入口绕过已有的终端回退

位置：`org-workflow-weekly.el:240`，对照
`org-workflow-history-panel.el:414` 的公开入口。

菜单 h 直接调用图形 workbench；公开 history-panel 本来会依据图形能力选择终端 tracker。
干净非图形 batch 中，同一有效历史 payload 经菜单目标函数报
`color-rgb-to-hex` 参数错误，经公开 router 则成功进入终端 tracker。

应让公共菜单复用现有路由，将图形／终端决策留在一个位置。
这里验证了非图形 batch 路径，没有声称验证物理终端按键或用户主题下的 daemon。

## 结构判断与建议顺序

现有 Org 源事实、SQLite 历史、只读视图和包生命周期分层值得保留。
本次发现集中在跨层边界：可变位置被当成身份；部分属性撤销被当成完整领域撤销；
文本回滚被当成能回滚计时／磁盘副作用；不同策略中的“完成／暂停”混用。

建议分成小步，每步先固定复现，再改根因：

1. 固定动作身份，避免完成／归类错误对象。
2. 协调 CLOCK、磁盘和 SQLite 的事务边界，保留不确定操作的恢复能力。
3. 补齐承诺替换的完整撤销语义。
4. 统一当前执行、关闭分支和进度的状态判断，同时保留历史策略边界。
5. 修复习惯身份、网页契约和历史菜单路由。
6. 更新过期测试和当前文档，再评估是否需要局部提取函数。

不要先按长度拆文件、增加统一 guard 层或做全包重写。
粗略结构盘点为 40 库、818 个函数／宏定义；最长的函数约 103 行。
长度只用于定位阅读热点，不是缺陷或复杂度分数。
crapper、dryer、mutator 当前均不可用，未产生 CRAP 值、0.8 重复排名或变异测试覆盖率。

## 验证结果及边界

| 检查 | 本次结果 |
| --- | --- |
| 官方 source-staged ERT runner，排除已知缺失 Agenda 文件交互测试 | 774 项执行，761 通过，13 失败 |
| 字节编译 | 通过，包源码无编译警告 |
| 安装 tar／全新 profile require／启停 smoke | 通过 |
| checkdoc | 9 项文档警告，目标失败 |
| package metadata lint | 本机缺 package-lint，未完成 |
| GNOME 纯逻辑 | 14 个 tests/*.test.js 文件通过 |
| shell 客户端测试 | 2 个脚本通过；workflow-client 测试因旧 argv 预期失败 |
| 缺陷复现 | 临时 Org／SQLite；主审独立重跑了执行、Agenda、习惯及导出复现 |
| 真实桌面／GUI／Portal／音频／物理拖动 | 未执行 |

13 个现有 ERT 失败已逐项对照当前契约，均涉及旧预期／旧层级 fixture：
旧 QA 状态序列、旧日志捕获与回顾入口、收集箱改为随时、四个项目步骤、完成栏、
已安排 Inbox 保留归类身份、右栏归类滚动、二级阶段被当作可拖动任务，或当天承诺替换规则。
这些测试需要按当前用户行为重写；不能仅删除断言或把整组测试长期排除。
具体名称、失败形式与命令见 [审查日志](2026-10-28-org-workflow-log.md)。

数据恢复的新文件创建分支仍有验证缺口：官方测试
`workflow-sprint-create-new-file-commit-failure-restores-buffer` 会进入原生
“Non-existent agenda file” 交互提示，本次排除该项。
未把这个未完成的探查列为已确认的恢复缺陷。

文档也有维护漂移：`docs/CONTEXT.md` 最新段落与较早正文并存，旧段仍描述
QA／LAB／HW 状态、完成原位显示、独立项目视图及 modules 配置入口。
后续修复宜合并为一份当前规则，将历史叙述留给 Git。
这属于维护债，不另计为运行时缺陷。
