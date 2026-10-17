# Workflow：任务、执行与历史模型

[文档入口](README.md)（全局快捷键由用户配置，文中的键位为示例） · 维护基线：2026-10-08

本文描述当前规则。CURR 标签、READY、22:00 日日志封存和标签承诺属于历史模型。

## 数据来源

| 来源 | 保存内容 |
| --- | --- |
| Org 项目／领域及周日志 | 任务结构、TODO 状态、SCHEDULED、优先级、标签、ID 与真实 CLOCK |
| `org-workflow-store-file`（默认 `var/org-workflow.sqlite`） | 承诺、事件、已结算每日快照、习惯投影、请假记录与操作恢复映像 |
| 周日志 `journal/weekly/周一日期.org` | 随记及周回顾；旧周目标原文保留，当前目标采用 DIVE + DEADLINE；任务捕获统一到 projects.org/Inbox |
| 原生历史面板 | 直接读取当前后端的只读缓存与视图 |
| 网页 JSON | 已结算事实的导出副本；网页只展示，不重新解释任务规则 |

数据库是持久事实，不是可随意删除的缓存。备份时必须和 Org 源文件一起保存。
当前状态序列为 `TODO / DIVE | DONE / HOLD`；READY 已退役。
DIVE 表示活跃任务组，DONE 表示实际完成，HOLD 将该标题和子树移出当前执行路径。

`QA / LAB / HW` 是平行的 Org 类型状态，用于问题、实验和作业等附属内容，
由 `org-workflow-task-type-keywords` 配置（只填关键字名称，修改后重新启用 Workflow）。
它们在 Org 中可被识别、选择，但不是 Workflow 执行任务，不独立进入执行队列，
不接收父任务的日期下放，也不使父任务失去执行叶子资格。真正的 TODO 后代
无论是否隔着类型标题，仍按任务拆分规则处理。原有任务统计排除类型状态；
仅含类型节点产生的 `[0/0]` 不会自动完成父 TODO。

```org
* DIVE 课程
** TODO Training Part I
SCHEDULED: <2026-10-17 Sat>
*** QA 超平面为什么能划分空间？
*** LAB 实验记录
*** HW 课后练习
```

这里仍以 `Training Part I` 作为执行单位。类型状态使用独立的原生 `type` 集合，
不插入 TODO → DIVE → DONE 的状态序列，也不共用 DONE 作为其结束状态。
文件若已有 `#+TODO`、`#+SEQ_TODO` 或 `#+TYP_TODO`，会按 Org 原生规则覆盖全局定义。
需要本地定义时应同时声明两套状态，避免只声明类型集合后丢失普通 TODO：

```org
#+TODO: TODO(t) DIVE(v) | DONE(d) HOLD(h)
#+TYP_TODO: QA LAB HW |
```

## 任务范围、安排与执行

Workflow 队列读取 Agenda 中具有 project 或 area 文件标签的任务。
未完成叶子直接安排到今天或更早日期后进入队列；未来任务不进入今天执行栈。
习惯及 HOLD 子树排除。当前 DIVE 范围只用于挑选未安排候选，不是队列准入条件。
默认候选要求直接父标题为 DIVE；详见 [DIVE 与每日尝试](dive-and-daily-attempts.md)。

明确安排父标题时，规范化操作把安排转给符合条件的未完成叶子；普通任务查询不改源文件。
时段使用原生 priority A/B/C；`org-workflow-work-periods` 配置独立的工作窗口。
上午开始开放 A，下午开始开放 A+B，晚上开始开放全部。窗口之间保留上一阶段，
空时段不自动开放未来窗口；用户仍可手动选择其他任务。
同父组默认按源标题顺序，组间采用既有优先级、日期和时刻规则。
手动排序只在同一显示日期、同一时段内应用，可跨父组，源标题位置不移动。

执行目标独立于排序建议。开始计时或明确选择后，刷新和重排不改变执行目标；
明确完成、切换或延期负责转换执行状态。Focus Timer 通过标准 Org Clock 记录分钟，
停止后不足默认五分钟的区间取消，其他区间正常 clock-out；手动 Org Clock 不受此规则接管。

## 共用条目与习惯

`org-workflow-items.el` 用现有 `org-workflow-target-entry` 表达两种条目，`kind` 为
task 或 habit；习惯附加当天 occurrence、展示位置和提醒钟点。这里是语义上的任务子类，
不引入类继承框架。原文 marker、ID、标题及正文读取共用一个适配入口。

`org-workflow-current-item` 是唯一当前项解析入口：执行中的 Focus Timer 周期（含休息）
优先，其次是匹配的 Org Clock；空闲时最新待处理习惯提醒优先于普通任务。
提醒、跳过和完成仍遵循原有当日策略，旧提醒不会重新浮现。普通执行选择独立保留，
以便提醒结束后恢复；这不构成第二个界面当前项。

Emacs 状态、桌面命令、原文导航、新图形 frame 和 capture 使用共用条目。
旧任务 mode-line 展示已移除；局部原文查询和定位不使用 Org element cache。
start／complete／visit／save 共用操作，习惯 complete 保留 Org 原生重复日志，skip 仅
抑制当天提醒。推进、前置任务、延期及承诺仍仅适用于普通任务。
两种条目共用直接 CLOCK 和每日完成记录读取；现有持久表、输出语义和封存事实不迁移。

## 承诺与每日兑现

安排到明天自动建立承诺草案，午夜后成为正式责任。今日临时加入的是可选任务。
未来草案提前、取消或重新安排时保留取消事件；已生效承诺的原责任日期不随当前 SCHEDULED 改写。
延期、HOLD 或撤回不删除原日期的承诺和事件。是否继续承担及当天结果由历史模块读取事实判断。
界面中的 promise 标识从事实生成，不读取旧 promise 标签作为承诺规则。

每日兑现和任务完成分开。新规则下，当天正分钟数、已结束的直接 CLOCK，或实际完成，
可以满足每日责任；不会因此把任务自动改为 DONE 或重排日期。
开放时钟、已取消区间和子任务工时不算父任务尝试。
启用日期之前沿用旧规则，已有结算快照不自动重写。

“推进”用于修正任务粒度：直接 CLOCK 和当前承诺可转交新增 TODO 子任务，
数据库保存原范围与调整事件；实际完成后可追溯为调整范围后兑现。
原定日期注释和延期次数累计已移除，当前安排本身仍保存在 SCHEDULED。

## 任务属性

| 属性 | 当前用途 |
| --- | --- |
| `ID` | 稳定任务身份、链接及历史关联 |
| `WORKFLOW_COMMITMENT_ID` | 当前附着承诺的关联键；不以“最近一条历史承诺”替代 |
| `WORKFLOW_ORDER` | 保存时段和排序编号，例如 `A/0`；跨日保留，换时段不应用原值 |
| `Effort` / `WORKFLOW_BOUNDARY` / `WORKFLOW_RESUME` | 可选估时、完成边界和续接提示 |
| `CAPTURED_ON` | 收集／新增时保存的来源日期，独立于安排日期 |

承诺创建时间和承诺日期以 SQLite 为准，不再镜像到 Org。
旧创建时间无法确认时保留数据库空值，不推测历史。
周日志、开工指导、请假条及旧日日志还有各自识别属性，不能一概按 WORKFLOW 前缀删除。

`(require 'org-workflow-cleanup)` 后，`M-x org-workflow-cleanup-properties` 预览；前缀参数执行。
只清理已迁移的当前 Agenda 项目／领域，排除 journal/journal-week 日志。
移除重复承诺日期、延期计数及已退役任务属性，并转换旧范围／编号排序。
承诺关联或排序无法验证时拒绝执行；要求参与缓冲区已保存、可写，待恢复操作已处理。
执行前备份源文件、路径清单及 SQLite 到 `var/workflow-backups/`，再通过现有事务编辑并保存。
重复执行无新变化，旧日志原文与历史事实保留。

## 午夜结算、导出与习惯

每日覆盖本地 00:00 至次日 00:00，跨日 CLOCK 分摊。午夜结算已结束日期；
Emacs 离线时下次启动补结算。已有日期快照直接复用，missing 不等于零投入或 untouch。
`M-x org-workflow-history-recompute` 可明确重算过去统计，不重建承诺集合；
旧快照缺少可靠关联时拒绝重算，保留原数据。请假记录也保留。

习惯使用 `org-workflow-habit-file` 对应的原生 Org repeating headings，默认笔记目录的 habits.org。
完成日志及直接 CLOCK 投影到按日期保存的 habit_days，不加入普通任务责任集合。
保存源文件在前，同步失败可在启动或显式 `org-workflow-history-sync-habits` 时重试。
旧习惯字段未知时显示未知；总投入包含承诺、可选及习惯，承诺兑现不混入习惯。

`WORKFLOW_HABIT_POSITION` 设置上午／下午／晚上各自的初／末；Agenda 将习惯放在
对应时段任务前／后，不参与普通任务排序，保留周完成和连续天数。未设置位置的习惯
保留独立习惯栏。`WORKFLOW_HABIT_REMINDER` 可覆盖工作窗口边界提醒钟点。

panel 每 30 秒检查到点习惯，meta 中 `habit-reminders:YYYY-MM-DD` 保存通知过的习惯、
当天跳过列表和当前最新提醒。每个习惯每天只通知一次，完成的不通知，跨日重置。
非专注且没有 Org clock 时，GNOME v22 显示最新提醒；后来的覆盖前面的，直到完成／
跳过。结束／跳过当前提醒不恢复被覆盖的旧提醒，也不改变普通任务执行选择。

长期追踪直接读取 Emacs 原生历史模型，不再自动生成网页快照。
失败保留旧 JSON，不保证浏览器自动看到最新数据。原生面板不依赖 JSON。
详见 [原生历史面板](workflow-history-panel.md) 和 [网页说明](../extras/web/README.md)。

## 保存、恢复与备份

Org 修改与 SQLite 写入由 `org-workflow-store--operation` 协调。
尚未保存的成功操作保留 before/after 源文件映像；启动只在内容匹配已知版本时恢复到缓冲区。
独立编辑产生冲突时明确报错，不覆盖当前文本。

成功保存某个源文件后，单独清除该文件的待恢复映像，包括 Workflow 操作之后一起保存的手动编辑；
其他未保存文件仍可恢复。操作内部保存会在数据库提交后补检查点。
`restart-emacs-systemd` 先询问保存并检查点；仍有未保存文件或保存失败时取消重启。

迁移和属性清理的源备份使用路径哈希命名，manifest 记录原路径，数据库备份保留当时事实。
恢复冲突应比较当前文件、before 和 after；不要把删除 operations 或数据库当成常规清理。
开发缓存与 Workflow 数据库不同；不要为清理工作区删除数据库或恢复记录。

日常界面见 [Sprint](agenda-planning-workbench.md)、[周日志](daily-journal-inbox.md)、
[规划辅助](workflow-planning.md) 和 [请假条](workflow-leave.md)；代码职责见 [模块边界](gtd-module-layout.md)。
