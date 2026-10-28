# Sprint 项目管理实施方案

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 把已确认的项目管理 UI 整合进 Sprint，支持 Inbox 拖动归类、安全单步撤销和旧项目入口统一。

**Architecture:** 扩展现有 Sprint 工作台的视图与两栏角色，复用项目采集、原生 Agenda marker、
原生 refile 与 Org／SQLite operation。把归类写入与反向操作集中于专用实现模块；共享一条
按工作台保存的最新安排／归类记录。旧项目界面转为兼容入口，不并存第二套渲染器。

**Tech Stack:** Emacs Lisp、Org Agenda／refile、现有 SQLite 存储、ERT；不增加运行时依赖。

**Spec:** `docs/superpowers/specs/2026-10-28-sprint-project-management-design.md`

## Global Constraints

- 文件 Area → 一级 Project → 二级 Heading → 三级 Task；现有任务细分原样保留。
- 一级仍要求现有 TODO/DIVE/HOLD/DONE 项目标识；普通二级 Heading 不要求 TODO。
- 项目直属目标自动创建／复用「未分组」，不批量迁移用户 Org。
- Inbox 全部未完成任务／QA 可归类，普通想法留在 Supertag；QA 不计入阻塞／进度分母。
- 每个 Sprint 实例单步撤销安排／归类；状态、开始日期和 Area 暂停操作使旧记录失效。
- 已应用但待保存的归类必须登记自身撤销；参与文件后续修改时拒绝快照回滚，不覆盖新记录。
- 归类不改变显式安排、项目状态和承诺；项目状态操作复用既有事务 API。
- 先预检整批，再执行；提交前不保存半批，提交后先目的地再来源，保留恢复事实。
- 不重启 Emacs，不注销桌面，不提交宿主无关改动，不自行推送。

## Review Focus

- 文件原来未保存／外部变更／只读时必须在修改前拒绝；安排区不能误被项目视图处理。
- 祖先／子节点批量重叠、跨文件重复标题和多个同名未分组不能造成重复／错投。
- 移动中的异常与提交后的部分保存失败不同：前者回滚，后者保留可恢复状态，不重放。
- 后续 CLOCK、状态、其他操作使撤销快照过时时拒绝；同日其他文件编辑不能被覆盖。
- 普通 Heading、QA 子树、暂停项目和当前计时条目不能被新视图误激活或误判为执行叶子。

## 文件职责

| 文件 | 变更职责 |
| --- | --- |
| `org-workflow-agenda-layout.el` | 视图选择、双栏角色、位置恢复、每工作台最新操作记录 |
| `org-workflow-agenda-view.el` | 今日／明日／项目切换控件和按视图渲染分派 |
| `org-workflow-agenda-projects.el` | 统一 Area／Project／Heading／Task 树、普通 Heading 与折叠呈现 |
| 新 `org-workflow-project-classify.el` | 归类目标解析、预检、批量 refile、身份更新与归类撤销 |
| `org-workflow-agenda-mouse.el` | 原拖动循环的目标类型分派、两栏滚动与高亮 |
| `org-workflow-agenda-plan-undo.el` | 保留现有安排纠正，扩展单步记录类型与统一 U 分派 |
| `org-workflow-agenda-inbox.el` | 复用 Inbox 采集；在事务批量 refile 时延迟原自动保存 |
| `org-workflow-store.el` | 提供局部提交后回调，归类 record 在 checkpoint／刷新／保存前登记；复用既有恢复系统 |
| `org-workflow-project-view.el` | 移除独立渲染，公开入口兼容转向 |
| `org-workflow-agenda-console.el`、`org-workflow-weekly.el`、`org-workflow.el` | 命令／帮助、菜单、模块加载 |
| 新及已有相关 `test/*-test.el` | 临时文件／数据库中的行为验证 |
| `docs/project-workbench.md`、`docs/CONTEXT.md` | 当前入口、归类／撤销边界与维护方法 |

---

### Task 1：统一视图、结构采集与项目树

**Files:** 修改 layout、view、agenda-projects；新增 `test/org-workflow-agenda-project-management-test.el`。

**Interfaces:**
- `org-workflow-agenda-select-view (view)`：view 为 `today`／`tomorrow`／`projects`。
- `org-workflow-agenda-projects-render (&optional inbox-role)`：复用统一树，不创建 ID／承诺。
- 项目行带原生 marker 与现有 `org-workflow-agenda-project-role`；新归类目标属性
  `org-workflow-agenda-classify-target` 为 `(:kind project|heading :marker MARKER)`。

- [x] 写 `workflow-project-view-tabs-share-workbench-not-date`：切页不换实例、不改变项目执行日，日期安排命令在项目行不可误用。
- [x] 写 `workflow-project-tree-includes-plain-headings-and-qa`：普通二级标题可见；QA 保留标签且进度排除；DONE/HOLD 可展开；0/0 隐藏。
- [x] 写 `workflow-project-inbox-includes-old-and-scheduled-items`：旧／已安排 TODO 与 QA 可归类，普通想法及 DONE 排除。
- [x] 运行新测试确认失败，再实现 view 状态、角色分派、统一采集和折叠；显示不写源文件／数据库。
- [x] 验证各视图光标／滚动独立、另一工作台不受影响、现有今日／明日渲染测试通过；提交本单元。

### Task 2：可恢复的批量归类

**Files:** 新 `org-workflow-project-classify.el`、`test/org-workflow-project-classify-test.el`；修改 inbox 自动保存边界和加载引用。

**Interfaces:**
- `org-workflow-project-classify (markers target)`：按给定可见顺序移动 Inbox 子树，target 使用 Task 1 属性结构；提交后立即产生归类 record；提交前失败不登记，提交后 checkpoint／刷新／保存失败保留 record 并标记待保存。
- `org-workflow-project-classify-undo (record)`：预检操作后源图像，执行反向恢复并更新 ID 定位。
- store 提供动态局部 `org-workflow-store--after-commit-function`（无参函数，默认 nil），仅在 SQLite 提交并接受源变更后、checkpoint／刷新之前调用；归类在此登记 pending record，不新增全局启用的 hook/advice。
- record 包含 `:kind classify :date :database :before :after :created-heading :identities :save-state`；before/after 是参与文件的源文本和必要文件版本信息。

- [x] 写 `workflow-classify-project-creates-or-reuses-only-direct-ungrouped`：首次建立 `** 未分组`，再次复用；其他项目同名不干扰；直属重名拒绝。
- [x] 写 `workflow-classify-batch-preserves-subtrees-and-source-order`：两项含 QA、主题、ID、显式安排、LOGBOOK 和后代，同文件／跨文件均成为三级根、相对层级保留、无重复。
- [x] 写 `workflow-classify-preflight-rejects-entire-invalid-batch`：过期来源、只读、原有未保存编辑、外部文件修改、DONE 目标、活动 clock、外部拖入都零修改；HOLD 可接收但不启动。
- [x] 写 `workflow-classify-failure-rolls-back-batch` 和 `workflow-classify-save-failure-keeps-recovery`：第二项失败不留下首项／分组；提交后目标保存失败不能先持久化源删除；U 指向本次归类而不是较早安排，待保存可重试保存或撤销，重复拖入不再移动；重读恢复事实无丢失、不重放；注入提交后 checkpoint 异常也必须保留本次 pending record。
- [x] 运行确认缺失功能的失败，再用原生 refile + 既有 operation 实现；批次内抑制原 refile 自动保存，提交后仅保存参与文件；必要时以源文本快照补足 native undo-list 调整下的异常回滚。
- [x] 验证 ID 查找落在新文件、计时／当日固定承诺／历史记录不因归类变更；跑相关 store/refile 回归并提交。

### Task 3：共享的单步撤销

**Files:** 修改 plan-undo、layout、console；新增／扩展归类和 undo 测试。

**Interfaces:**
- 工作台共享字段 `org-workflow-agenda-last-operation` 保存最后成功 record，类型 `plan`／`classify`；归类包含 `:save-state saved|pending`。
- `org-workflow-agenda-undo-last-operation ()` 为 U 的唯一分派；旧 undo-plan 命令作为兼容入口。
- 现有安排 before/after/facts/events 校验继续使用；新增 `org-workflow-agenda-invalidate-last-operation (reason)` 清除记录并保留提示原因，供状态／开始日期／Area 操作在提交后调用。

- [x] 写 `workflow-classify-undo-restores-order-and-created-heading`：同／跨文件批次完整还原；只删除本次新建分组；旧分组保留；ID 定位正确。
- [x] 写 `workflow-classify-undo-rejects-post-edit-or-date-change`：参与文件后续编辑／clock／数据库或日期改变拒绝；另一个文件编辑和相同文本的保存不受影响。
- [x] 写 `workflow-sprint-undo-dispatches-only-most-recent-success`：归类后安排，U 只撤销安排；提交前失败、取消、刷新与折叠不覆盖记录；已提交待保存归类则替换记录；另一个工作台独立。
- [x] 写 `workflow-project-mutations-invalidate-older-undo`：归类后分别改项目状态、改开始日期、暂停／恢复 Area，U 都提示失效而不撤早前归类；失败状态变更不清除旧记录；原暂停所有权与责任处理行为不被新撤销代码改写。
- [x] 运行失败测试，再实现统一记录入口、分派和失效提示，不做状态补偿或通用多级撤销框架，不整体还原数据库。
- [x] 跑现有安排撤销、项目暂停／恢复和新增测试，通过后提交。

### Task 4：鼠标与键盘接入

**Files:** 修改 mouse、console、agenda-projects；扩展 `test/org-workflow-agenda-mouse-test.el` 和新项目视图测试。

**Interfaces:**
- 复用现有 `mouse--target`／`mouse--drop`，按 period 与 classify 目标分派，不复制拖动循环。
- `org-workflow-agenda-classify-selected ()` 为键盘与菜单的同一归类命令，选项包含 Area／Project／Heading 完整路径。

- [x] 写 `workflow-mouse-classify-drops-on-project-and-heading`：跨 pane 项目目标、具体 Heading、折叠项目落点、两栏滚动与高亮使用正确 record。
- [x] 写 `workflow-mouse-classify-cancel-is-read-only`：阈值内单击、Esc、任务／Area／空白落点、其他工作台、批量父子重叠均不误移；选择保持既有含义。
- [x] 写 `workflow-project-keyboard-and-mouse-use-same-classifier`：批量行顺序、目标名称相同但位置不同不串目标，显式归类命令与拖动结果一致。
- [x] 先运行失败，再接入 Task 2 和 Task 3；接入“选择后点击目标名称”与箭头独立折叠，成功后展开目标并刷新两个 pane，保留其他视图位置。
- [x] 跑原拖到上午／下午／晚上和鼠标选择回归，检查 Evil 覆盖图实际绑定，提交。

### Task 5：替换旧项目视图并验收

**Files:** 修改 project-view、weekly、console、org-workflow；修改相关测试和当前使用文档。

**Interfaces:**
- `org-workflow-project-view ()` 委托 `org-workflow-agenda-select-view 'projects`；没有 Sprint 时创建同一工作台。
- 保留公开入口与原状态／开始日期／Area 暂停等能力，但仅有一套树与操作分派。

- [x] 写 `workflow-old-project-entry-reuses-sprint`：M-x／菜单 p／Sprint P 进入同一项目页，不新建旧特殊 buffer；关闭／返回沿用工作台生命周期。
- [x] 写 `workflow-daily-candidates-share-project-tree`：每日候选栏继续受自己的筛选控制，不影响完整项目页；普通 Heading 可见，日期命令与树角色不冲突。
- [x] 跑失败后替换旧入口／删除重复渲染和键图，保留 API 所需兼容包装；同步按键帮助及右键菜单。
- [x] 更新 project-workbench 和 CONTEXT：三级规则、未分组、U 单步及冲突限制、入口与维护文件。
- [x] 跑相关 ERT、修改模块编译、diff-check。临时图形示例验证拖动手感；真实会话只局部重载、读视图，不用真实任务演练写入。
- [x] 提交最后整合，报告各提交、验证与实际会话限制；不自行合并／推送。

## 验证方式

从包根目录执行，使用本机已有依赖且不加载个人 init：

```sh
PACKAGE_USER_DIR=/home/meph1st0/.config/emacs/elpa make test
PACKAGE_USER_DIR=/home/meph1st0/.config/emacs/elpa make compile
git diff --check
```

每个单元先在隔离 profile／临时源目录中运行该单元列出的具名 ERT 用例，避免旧 .elc；
最后用上述现有 runner 跑一次完整回归。测试全部使用临时 Org／SQLite。若完整回归出现
既有失败，先核对基线并明确报告，不为使本功能通过而改写不相关行为；无需安装新依赖或
调用打包发布流程。图形手感用临时样例，困难的桌面交互留给用户按步骤验收。

## 自检映射

结构／普通 Heading／日期隔离 → Task 1；真实子树／事务／保存失败 → Task 2；
单步记录／后续变更保护／非撤销操作失效规则 → Task 3；鼠标／键盘同路径 → Task 4；
旧入口／重复实现清理／日视图回归 → Task 5。Review Focus 五类分别由 Tasks 1–4 的具名测试覆盖。

## 已确认的实施默认值

1. U 只撤销最后一次已应用的安排／归类；项目状态、开始日期和 Area 暂停／恢复使旧记录失效，不做多级或跨重启撤销。
2. 源／目标有未保存编辑时先保存再归类；归类后参与文件有后续编辑则拒绝快照撤销。已应用待保存归类保留自身撤销并阻止继续写入，先重试保存或 U。
3. DONE 项目／分组不接收新条目；TODO、DIVE、HOLD 可接收，归类不会自动启动它们。
4. 保留原型的“选择后点击目标名称”归类；箭头始终只展开／折叠，键盘另有等价归类命令。

用户已于 2026-10-28 确认，在当前会话按上述五单元实施；真实用户数据不参与写入测试。
