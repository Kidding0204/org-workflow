# Sprint 项目管理与每日推进

[文档入口](README.md) · [任务与历史模型](workflow-architecture.md)

Sprint 顶部统一为 **今日／明日／项目**。菜单 p、Sprint P 与
`M-x org-workflow-project-view` 都进入同一项目页，不再打开独立项目 buffer。
今日／明日负责时间安排，项目页负责归属与项目状态；切换保留各自位置。

## 文件与大纲

加入 `org-agenda-files` 的文件名（不含扩展名）就是长期目标，无需 project/area 标签或
登记。一级带 TODO 状态的标题是项目，二级是阶段，三级及其细分是具体任务。
无 TODO 状态的一级组织标题、Inbox、直接 :QA: 节点及简单重复习惯不作为项目；二级普通 Heading 可以显示。
旧 `WORKFLOW_KIND` / `WORKFLOW_GOAL_ID` 不再决定身份或归属；真实 ID 与历史保留。

例如 `AI_Compiler.org`：

```org
* DIVE 编译原理
** DIVE 词法分析
*** TODO 实现最小词法器
*** TODO 为标识符添加边界测试
** TODO 语法分析
*** TODO 实现递归下降分析器
* TODO MLIR 实践
** TODO 环境准备
*** TODO 编译并运行第一个示例
* HOLD SICP
** TODO 第一章习题
*** TODO 完成练习 1.1 并解释求值结果
*** TODO 完成练习 1.2
```

项目归属通过文件组织；使用原生 Org refile 移动整个项目。不会为了新界面自动搬动已有学习内容、
生成课程习题或将原有习惯历史伪造为项目完成记录。需要逐题推进的习惯改写成上述项目
结构；仍然只是同一个动作的重复习惯继续使用 `STYLE: habit`。

## 今日安排

- 完成任务从原时段移到 Sprint 底部的“今日已完成”，保留原文访问和折叠能力。
- 某时段没有未完成任务且当天有完成记录时，正文显示“已完成 n 项任务，共专注 x 时 y 分”。
  按任务所属 A/B/C 时段归组，只累计这些任务当天的直属 CLOCK，不重复计算子节点或昨日投入。
  习惯继续沿用原来的展示，不并入任务完成数量；从未安排任务的时段仍显示“暂无安排”。
- 项目／阶段归属显示大纲前两级，不显示文件名；鼠标提示保留全名。
- 随时区保留自由习惯、Inbox、未安排疑问及各 DIVE 项目前四个未安排任务。
  项目标题继承其他分类的样式并使用斜体；四项跨阶段按源顺序选取，不在承诺下重复预览。
- 双栏左侧显示安排、随时和今日已完成；右侧仍按目标文件过滤项目。
- 明天安排不显示今天的完成栏或时段总结，也不带当天习惯。

## 项目页与每日候选栏

项目页左侧列出统一 Inbox 中全部未完成任务和 QA，包括旧条目和已有日期的条目；
普通想法仍由 Supertag 组织。右侧按 Agenda 文件作为 Area、一级项目、二级 Heading、
三级任务显示，顺序与源文件一致。原有细分任务继续缩进，QA 后代不冒充项目步骤。

普通二级 Heading 不需要 TODO。项目、Heading 和 Area 都可折叠；TODO／HOLD／DONE
项目也能展开查看，折叠不等于暂停。项目进度沿用源 cookie 和现有统计，QA 不计入分母，
无 cookie 时不额外生成进度事实；0/0 不显示。每日右栏复用同一树，保留原周追踪与文件筛选。

点击箭头或 TAB 展开／折叠，RET 或双击访问原文；结构行 t 调整项目／阶段状态，Area 行 t
暂停／恢复整个 Area。普通任务的 t 仍为原生 Agenda TODO。项目页 s／C-u s 设置／移除项目
开始日期，R 显式同步，D 展开／折叠已完成项目。g 刷新，q 沿用 Sprint 返回规则。

### 将 Inbox 归类到项目

单击选择、Ctrl 增减、Shift 连选；拖动已选项会一并移动。可拖到具体二级 Heading，
也可拖到项目标题，后者创建／复用该项目直属的普通二级“未分组”。只有一个同名直属分组
才复用，多于一个会提示先合并。任务根调整为三级，后代相对层级、正文、ID、标签、主题、
显式日期／优先级与 CLOCK 保留；祖先属性的继承继续遵循 Org 原生规则。

勾选后点击目标名称也可归类，箭头始终只折叠；键盘 C 从当前目标归类，或选择目标路径。
树中其他任务、Area 或空白处不是落点，Esc 取消。首期来源限定为 Inbox，不做树内拖动排序。
归类可进入 TODO／DIVE／HOLD 项目，保持其状态；已完成项目／分组须先恢复。归类不安排日期、
不启动计时、不自动补承诺。正在计时的条目需先停止，程序不会代停。

源／目标有未保存编辑、外部版本变化或只读时整批拒绝，先保存／重新读取参与文件再操作。
一批整体提交后先保存目的地再来源，不顺便保存其他文件。若出现“归类已应用，保存未完成”，
条目已在内存中移动，请使用右键“重试保存归类”或 C-c C-s；也可 U 撤销，不要重复拖入。
未处理完这次保存前，本工作台阻止继续写入。操作恢复记录会保留部分写盘状态。

### U 单步撤销

U 纠正本工作台最后一次安排或归类，批量归类整体还原原位置和顺序。预先存在的分组保留，
只有本操作新建且未改变的“未分组”会一起撤掉。刷新、切页、折叠不覆盖记录；不支持多级
redo 或跨重启撤销。归类后参与文件若有新编辑（包括新 CLOCK），拒绝快照回滚以保留更新，
可用原生 refile 手动归回。其他文件编辑或保存相同文本不影响它。

项目状态、开始日期、Area 暂停／恢复及显式项目同步不纳入 U，完成这些操作会清除旧记录，
防止 U 撤销更早的安排／归类。状态调整继续使用现有项目 API 和暂停批次规则。

维护入口：`agenda-layout` 管切页和每工作台状态，`agenda-projects` 管树与归类命令，
`agenda-mouse` 管同一拖动循环，`project-classify` 管真实移动／保存／归类撤销，
`agenda-plan-undo` 管统一 U 和原安排纠正。旧 `project-view` 只负责入口兼容。

## 状态、开始日期与承诺

- TODO：尚未开始；项目 SCHEDULED 是开始日期，不下放给全部步骤。
- DIVE：每天推进，不需要 SCHEDULED；一天冻结一份承诺。
- HOLD：立即暂停，撤回当天未完成承诺；已完成与已记录 CLOCK 保留。
- DONE：项目完成，不再产生新承诺。

启动／午夜、原生状态／日期操作和 `M-x org-workflow-projects-sync` 同步今日承诺。
直接编辑标题文字后可显式同步；不会补造关闭 Emacs 期间的过去承诺。
系统选择当前推进分支第一个可执行未完成叶子，优先 DIVE 分支，排除 HOLD/DONE 子树、
未来已安排步骤、习惯和空阶段。QA 整个子树不阻塞所属任务。

当天完成后不追加承诺，未完成步骤翌日继续承担一份责任，不累积欠账，也不改写昨天。
已有同日手动承诺复用；旧逾期责任通过带日期的接管事件停止继续携带，旧结算不改。

批量暂停只记住当时 DIVE 的项目；恢复只恢复仍属于该批次的 HOLD 项目，TODO 和原先
HOLD 不动。手动改变项目状态或 refile 会取消原批次资格。暂停阶段也会撤回它下面的
当天未完成承诺，恢复复用同一记录。完成记录永不因暂停而撤回。
暂停期间错过开始日期的 TODO 保持 TODO；重设日期或手动进入 DIVE 才启动。

## 当天底线与历史

完成当天全部有效承诺，或达到全天最低投入；空集合／全部撤回不自动成功。
`org-workflow-daily-minimum-minutes` 默认 60 分钟，可在 Workflow 设置调整。每一天首次
记录的门槛保留，不回写过去标准。统计普通任务和习惯的已结束直接 CLOCK；运行中时长
仍由计时器显示，结束后纳入底线。短区间取消规则保持原样。

顶栏与历史继续区分承诺完成和整体时间底线，任务进展是主要展示，投入作为辅助信息。
Org／SQLite 变更使用既有事务与恢复机制，不自动保存无关编辑，不迁移或重写旧快照。

## 运行验收

测试仅用临时 Org／SQLite，覆盖同／跨文件归类、未分组复用、保存失败、撤销冲突及视图切换。
现有 Emacs 会话局部加载必要模块，不重启。真实拖动手感可用一个可丢弃 Inbox 条目验证：
拖到项目 → 看未分组三级条目 → U 归回；再拖到具体分组，核对标签与正文。

## 本次基线验证记录（2026-10-28）

独立包改动前提交 `5fe45bc` 的完整 runner 复现了以下 10 个旧失败；本功能的针对性测试
另行验证，不把这些失败报告成新功能通过。它们涉及旧承诺日期、旧二级任务 fixture、旧日志
capture／复查和已移除的类型关键词规则：

- `my/org-mouse-batch-commitment-updates-all-and-rolls-back-bad-date`
- `my/org-mouse-drop-batch-undo-restores-source-and-two-panes`
- `my/org-mouse-drop-no-op-keeps-source-and-undo-record`
- `my/org-mouse-mixed-drop-skips-already-correct-task`
- `note-gtd-journal-review-groups-original-items-without-copying`
- `note-gtd-journal-review-refiles-original-and-refreshes`
- `note-gtd-journal-template-install-preserves-current-target`
- `org-workflow-agenda-inbox-complete-refreshes-review-without-copying-content`
- `org-workflow-task-types-use-a-separate-org-type-set`
- `workflow-inbox-excludes-stage-candidates-and-completes-without-focus`

`workflow-sprint-create-new-file-commit-failure-restores-buffer` 在改动前后都停在 Org 的缺失
Agenda 文件交互提示；完整批处理回归排除此项，留给单独交互验收。没有为通过旧测试而恢复
旧关键词、旧 capture 或旧承诺语义。

本次最终完整回归（排除上述交互项）执行 756 项，其中 746 项通过，剩余恰为上述 10 项基线失败。
审查补上的 5 个失败用例已验证 RED→GREEN：原生活动 region 不能扩大选择范围、反向笔记顺序
不改变追加顺序、待保存禁止原生 refile／clock 和旧 Inbox 写入、归类失败恢复当前目标、撤销失败
恢复 ID 的文件定位。身份测试显式启用临时 ID 索引，不再靠跳过断言避开检查。
