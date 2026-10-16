# org-workflow：项目会话上下文

核对日期：2026-10-11。面向需要研究、修改或排查本包的会话。
本文是当前代码的阅读地图与维护边界；行为事实以对应源码为准。
修改入口、数据规则、依赖或验证方法时同步本页，避免继续使用历史方案。

## 1. 先建立项目边界

`org-workflow` 是独立、多文件 Emacs Lisp 包：把 Org 任务选择、Sprint 安排、
执行计时、周日志、收集箱、习惯、请假与长期历史连接起来。
当前实现已满足用户的日常工作流，维护时优先保留行为，针对明确需求做局部调整。

- 当前宿主把仓库放在 `~/.config/emacs/user-lisp/org-workflow/`，独立 Git 仓库在本目录。
- 父 Emacs 配置仓库负责个人路径、主题、Evil、系统服务与桌面快捷键。
  宿主入口是 `modules/org-workflow-config.el` 的 `use-package org-workflow`，不是包源码。
- 父仓库 `.planning/` 的原项目是“内置 Workflow 历史面板”；其 ROADMAP 不代表独立包的新需求。
  本页也不是某个 GSD phase 的决策文件。新的规划按当前用户授权范围建立。
- 公开仓库为 [Kidding0204/org-workflow](https://github.com/Kidding0204/org-workflow)。
  本地修改可能尚未推送；先读当前 Git 状态，不把历史 CI 或远端缓存当成当前提交的验证。
- `extras/` 是可选配套源码；用户数据、`.ci/`、`dist/`、`.elc` 和个人配置不属于分发源码。

建议首先执行：

```sh
git status --short
git log -5 --oneline
rg --files -g 'org-workflow*.el' -g '*-test.el'
```

若从父配置工作区进入，请对独立包使用正确的 `git -C user-lisp/org-workflow ...`。
不要把包提交、个人配置提交及用户未提交工作混在一起。

## 2. 最短阅读顺序

| 要了解的内容 | 优先阅读 |
| --- | --- |
| 安装、依赖与公开使用入口 | [README](../README.md)、[主库](../org-workflow.el) |
| 习惯重复、周次数与截止阶段目标 | [习惯系统长期上下文](habit-system.md) |
| 当前任务与历史规则 | [任务与历史模型](workflow-architecture.md) |
| 模块职责和修改位置 | [模块边界](gtd-module-layout.md) |
| 开关模式、集成撤销和键位归属 | [生命周期](../org-workflow-lifecycle.el) |
| 承诺、事件与 Org 文件恢复 | [存储](../org-workflow-store.el) |
| 执行、筛选和排序 | [核心](../org-workflow-core.el) |
| 结算与只读历史入口 | [历史后端](../org-workflow-history.el)、[视图模型](../org-workflow-history-view.el) |
| 现有测试及验收范围 | [Makefile](../Makefile)、[验收记录](verification.md) |

先读与问题对应的源文件和测试，再决定是否扩展阅读，不必每次扫描全部 33 个库。
历史设计、旧个人模块名和旧日志语义只能作为迁移材料，不能直接作为当前实现方案。

## 3. 使用入口与初始化

第一入口是 `M-x org-workflow-menu`，定义在 [周日志／菜单库](../org-workflow-weekly.el)。
当前个人配置绑定 `C-c k` 和 `C-c o m`；所有全局键位由宿主配置拥有，包不定义。
常用菜单项为 `a` Sprint、`A` 双栏工作台、`n` 捕获、`s` 开始任务、
`h` 原生长期历史、`e` 晚间收尾、`C` 参数设置。
计时项是多键序列 `f t / f f / f s / f r`，不是单个名为 ft 的键事件。

Sprint 原生 org-agenda-todo 完成后，延迟刷新优先定位到操作前下一项可见未完成任务，
无下一项时选上一项；没有剩余任务则留在原列表附近，不跟随完成项跳入今日已完成。
普通刷新、改期及优先级修改仍按原任务 marker 定位；动作库负责完成定位，布局库不改队列。

“可选”中的习惯、收集项和待安排分组统一使用 `org-workflow-agenda-meta`。
已完成任务与队列任务一样移除源 Org 标题的字体属性，保留原生 Agenda marker 和 DONE 状态。

Sprint 工作台用 `m` 标记／取消任务、`M` 清除选择，`d` 延至明天。
不再占用 SPC，也不单独绑定 f/t/d 添加 @flow/@tiny/@deep；这些标签操作函数保留。
f/t 回到原 Agenda／宿主键图的行为，p 仍为承诺／撤回。`?` 帮助与同一绑定表同步。

Sprint 右侧项目循环用 `org-workflow-agenda-previous-project` / `org-workflow-agenda-next-project`
（`H` / `L`），独立于 tab-line 切换命令；tab-line 只呈现可点击的项目标签。
右栏局部重映射 Evil 的 buffer 前后切换命令，以兼容宿主 H/L intercept 绑定。

图形历史工作台的 `q`（总览和日详情均可）及关闭按钮关闭整个所属 tab，恢复调用者窗口；
单缓冲区历史跟踪仍只退出自身窗口。Evil 派生模式键位安装后须刷新活动键表。

菜单沿用 Agenda 菜单的像素对齐：`:variable-pitch t`、`:column-widths '(16 20)`。
中西文字体混排时不要退回按字符长度计算列位置；新增描述要核对上下分组和窄窗口。

生命周期集中在 [org-workflow.el](../org-workflow.el)：

1. `require` 加载包定义，不主动启用 Workflow 集成、计时或打开 Workflow 数据库。
2. 显式 `(org-workflow-mode 1)` 安装组件、建立必要的存储元数据、恢复操作，
   再启用历史后端和周日志集成，更新已有 Org buffer。
3. 首次启用不会自动导入旧日日志，也不会假称已完成迁移；旧数据使用显式
   `org-workflow-migrate`，范围／属性清理有各自预览与备份要求。
4. 停用会取消本包计时器、清除 Focus Timer 阶段、移除拥有的 hook/advice，
   并保守恢复共享键和设置；已运行的标准 Org clock 仍需由用户正常结束。

默认 `org-workflow-clock` 为 `org-clock`；当前宿主选择 `org-workflow-focus-timer`。
路径默认值与所有最低版本看源码的 `defcustom` 和 `Package-Requires`，不要复制个人绝对路径。
无初始值的 defvar 声明只影响所在文件，且会被字节编译消除。已删除无实际跨模块
作用的 declarations 库；使用跨模块变量作 let 绑定的模块须保留自己的 defvar，
或在编译时加载其定义库。不要把这些本地声明误删为冗余，也不要用 nil 初始化
覆盖所属模块的默认值。

## 4. 数据和行为约束

### 任务、范围与承诺

- 状态模型为 `TODO / DIVE | DONE / HOLD`；DIVE 是活跃任务组，HOLD 排除对应子树。
- Agenda 中 project/area 文件提供任务。默认未安排候选要求直接父标题为 DIVE；
  习惯、HOLD 子树等排除。执行队列另按安排日期和时段筛选，不以 DIVE 标签继承准入。
- 原生 priority A/B/C 表达上午／下午／晚上的安排意图。
- 工作窗口统一由 `org-workflow-work-periods` 配置（periods 库）；任务范围和顶栏阶段进度
  在窗口开始时推进，休息间隔保留上一阶段，不自动提前打开下一阶段。
- 习惯用 `WORKFLOW_HABIT_POSITION` 指定六种初／末位置，`WORKFLOW_HABIT_REMINDER` 可覆盖
  窗口边界钟点；Agenda 放在本时段任务前／后并保留原生完成记录。
- panel 库每 30 秒检查到点习惯；当日通知、跳过和最新提醒写入 meta 的
  `habit-reminders:YYYY-MM-DD`，不修改完成事实。通知只一次，最新覆盖旧提醒，
  完成／跳过不会重新露出旧提醒。GNOME v22 非专注且无 Org clock 时显示最新提醒，
  桌面及 Emacs 的 start/toggle/visit/complete 共用 items 库的当前项，普通任务选择保留。
- `org-workflow-target-entry` 是共用条目，`kind` 区分 task／habit；items 库只读适配原文，
  不创建 ID。唯一当前项解析优先正在执行的计时周期（包含休息），再读取空闲提醒和普通队列。
  状态、capture、新 frame 和操作共用这个解析结果；无人安装的旧任务 mode-line 展示已删除。
- 桌面阶段进度 `org-workflow--stage-progress` 通过 `org-workflow-source-read` 读取 Agenda
  文件，复用现场 Org element cache 和未保存内容，保留 point／narrowing；未访问的文件
  用临时只读 buffer，不触发文件访问或 Org UI hooks。避免已访问文件在桌面轮询时重复建立临时解析缓存。
- 阶段目标以 DIVE + DEADLINE 为唯一来源，替代旧周日志文本周目标；今天／明天 Sprint
  顶部展示截止日期及原生进度，`W`／主菜单 `w` 访问源阶段。仅 TODO + DEADLINE 不列入。
  新周日志不生成周目标节，已有日志原文保留；参见 [习惯与阶段目标](habit-system.md)。
- 共用操作保留习惯的原生重复完成及仅当天跳过规则；推进、前置任务、延期和承诺属于普通
  任务的能力。普通队列准入不因当前项统一而扩大。任务／习惯共用直接 CLOCK 的每日读取，
  没有新增表、迁移历史快照或改写已结算事实。正文和每日事实读取仍局部绕过缓存；条目元数据与界面定位保留原生缓存。
- 当前执行目标独立于排序建议；刷新、重排和展示不能悄悄切换执行目标。
- 每日“承担并尝试”与实际完成不同，不应因满足当天责任自动将任务改为 DONE。
- 承诺创建／调整规则由 core、commands、store、history 共同实现。
  不用当前 SCHEDULED 或某个标签重新推算过去承诺集合。
- `ID` 和 `WORKFLOW_COMMITMENT_ID` 负责关联；`WORKFLOW_ORDER` 如 `A/0` 保存时段与序号。
  延期计数、原定日期提示和重复承诺时间镜像已退役，不能在渲染中重新写入。
- `Effort`、`WORKFLOW_BOUNDARY`、`WORKFLOW_RESUME` 等仍有用途；不可按前缀批量删属性。

具体准入、跨日、推进和兑现条件见 [任务与历史模型](workflow-architecture.md)，
涉及这类行为必须同时看相关 core/store/history 测试。

### 源文件与缓冲区生命周期

- Org element cache 的绕过只属于有界的只读扫描。不要在完成、归档、保存、文件访问
  或刷新通知外层绑定 `org-element-use-cache` 为 nil：Org 的修改钩子也受此变量控制，
  会导致正文已变而原生查询仍返回旧 TODO、属性或日程。任务队列收集和 habits 的
  `org-map-entries` 保留原生缓存，避免 Org 9.8 的临时缓存反复解析。items 的条目元数据读取同样复用缓存；访问条目时的窗口切换、展开及宿主回调保留原生变更追踪。
- 保存习惯来源时，日期发现与多日期事实收集各遍历一次来源；逐日复用条目元数据与
  共用 day-record 读取，保留缺失来源／ID 校验、已删除日期清空及 SQLite 事务回滚。
- 不全局关闭或每次强制重置 Org 缓存。缓存回归须先预热原生解析，再执行真实操作，
  验证后续原生查询；只断言 Workflow 自己的无缓存读取不足以证明一致性。
- 模式仅拥有自己新增的 hook，停用保留预先注册的同一函数；buffer-local hook 在
  原所属 buffer 清理。停用同时释放 panel 的习惯 marker 和展示缓存，重启重新读取。
  旧 `org-workflow-current-item-cache` 无消费者，已删除；当前项始终走共用解析入口。

- `org-workflow-projects-file` 集中杂项；统一任务捕获位于一级 Inbox，习惯位于“习惯”子树，
  指导位于“实践指导”子树。t/p/L 捕获和 Sprint I 新增安排任务均不再写入周日志。
  t/p/L 标题捕获显式使用 `:empty-lines 0`，不沿用附近空行自动补分隔；正文列表模板不变。
  收集项日常查询只读 projects，不依赖 Vulpea 周日志索引。新周日志仅随记／周回顾。
  本次已授权迁移 52 个旧收集任务，备份与记录见 verification；程序不自动搬移其他文件。
- Sprint “可选”区按自由习惯、未安排收集项、每个直接 DIVE 父组最前两项呈现，单栏和
  双栏主面板均显示。候选按原文顺序、独立于右栏项目选择与全部范围开关，不变更执行队列。
  原生访问／完成不要求启动专注，不创建承诺；计时仍可选。
- Inbox 自动清理接在 history-catch-up 的全部旧日结算之后（当前午夜日结／启动补结算）。
  仅原生 DONE 的直属任务，CLOSED 超出截止日则留待下次；缺少 CLOSED 的旧 DONE 可归档。
  沿用 Org ARCHIVE／org-archive-location，先保存档案再保存源，维护 ID 定位；有未保存编辑
  或外部改动时暂缓，不保存用户其他编辑。不会全局关闭 Org 缓存或改写历史快照。
- history--tasks 的普通任务 CLOCK／完成事实读取也走 source-read；桌面状态刷新复用
  已打开来源的原生缓存，须保留现场未保存文本与收窄范围。
- sources 库后台读取优先复用现场 buffer 的原生缓存与未保存编辑；选择器、阶段进度、
  历史、收集箱及截止目标扫描不再为每次查询重建临时缓存。未访问文件使用禁止启动
  钩子、缓存和保存询问的临时只读 Org buffer。收集项先取得位置，只有实际显示的匹配才访问文件并生成存活 marker。
  修改、事务、计时、捕获和现存用户 buffer 的生命周期不变。
- `org-workflow-week-close`／菜单 J 封存已结束且收集项已清空的周；保存并索引
  `workflow-closed` 文件标签，在日常查询打开文件之前过滤。已结算历史不改写；明确回顾
  仍可直接打开源日志。不会仅按“旧周／未修改”批量关闭现有 buffer。

### 持久事实与恢复

Org 文件保存结构、安排、状态和真实 CLOCK；SQLite 保存持久事实与恢复映像。
[store](../org-workflow-store.el) 的七张表为 `meta`、`commitments`、`events`、`days`、
`operations`、`habit_days`、`leave_records`。数据库不是可随意重建的缓存。

任务写操作走已有共用事务边界。Org buffer 文本与 SQLite 的同步不是一个普通文件保存：
`operations` 保存 before/after，启动恢复会校验版本；独立手动修改产生冲突时不能覆盖。
checkpoint 按文件退役已保存的恢复映像，不能一次丢弃其他未保存文件的恢复能力。
崩溃留下的 prepared 记录须与已有 applied 的合法版本链共同校验；全部文件验证通过
才退役记录，独立文本改动仍是冲突。数据库版本／初始化失败不能留下可复用连接。
已 rolled-back 的映像不再用于恢复，退役及成功启动恢复时清空全文；不自动压缩数据库。
不要为“修复启动”直接清空 operations、删除数据库、伪造 checkpoint 或覆盖用户 Org 文件。
迁移／清理操作先满足已有校验并做备份，参见 [恢复边界](workflow-architecture.md#保存恢复与备份)。

### 计时、结算与展示

Focus Timer 通过标准 Org Clock 记录；自身停止时默认不足五分钟的片段取消，
普通手动 Org Clock 不因这条规则被接管。计时状态机在 [focus-timer](../org-workflow-focus-timer.el)。
休息期已有手动 CLOCK 时拒绝恢复专注，保留该 CLOCK 和休息状态。Sprint 直接新增
安排任务也走 org-schedule 和共用事务：明天建立承诺，今天保持可选，失败回滚完整新增。
桌面标题和习惯操作依据 status 的共用当前项；待处理提醒不能覆盖显式习惯选择或普通队列。

左侧右键菜单（GNOME v25）摘要仅显示当前正文前三行，每行单独省略长文本；
“打开任务”读取完整原文。任务页直接展示今日完整有序任务栈并标记当前项，列表可滚动。
`org-workflow-panel--augment` 添加只读 `tasks` 数组；key 由文件、位置和标题派生，
区分同名任务，不创建持久 ID。`org-workflow-panel-select-task` 重新查询当前栈验证 key，
再调用与 Emacs 选择器共用的 `org-workflow-target-select-marker`；停止旧执行，不自动启动。
已完成／已移出列表的旧 key 拒绝选择。动作行依次为打开任务／完成／取消／补记（后两者完整名称为取消计时／补记番茄钟）。
操作作为与任务／习惯并列的第三标签页，默认任务页，习惯当前项禁用任务专用操作。
补记通过可伸缩空位靠右排列。操作可用性逐项更新，避免 GNOME 分组敏感状态信号
在首个可交互项目返回 true 后提前停止，导致后续项目无法恢复。
原有宽范围选择器、习惯页和计时语义保留；
右侧菜单、顶栏展示与左右键语义未改。

顶栏右键菜单只保留独立计时入口“取消计时”和“补记上一番茄钟”；左键／Super+s
负责智能切换。桌面补记显式传入共用当前项 marker，不使用 Emacs 当前 buffer 的条目。
任务菜单加入现有 step 操作，它将父任务已有投入分配给命名 TODO 子步骤。
`org-workflow-target-ready` 及 `target-continue` 已删除；恢复最近条目的专用
clock-continue／focus-timer-start-last 调用链也已移除。start/rest/finish/stop
等底层入口保留显式控制用途。宿主 GNOME 移除已禁用的 Finish／Stop／Continue／Rest
快捷键和已退役 Ready；不再使用的 Status 快捷键也已删除，Cancel 标签明确为 Cancel Timer。
Status 专用的 `org-workflow-focus-timer-notify-status` 和无人复用的 `--notify`
已删除；`status-text` 仍供计时命令返回状态，`status-json` 仍供顶栏读取。
旧任务 mode-line 格式函数、专用宽度选项及标签辅助函数已删除；Sprint 局部
“安排：今天／明天”提示仍有用途并保留。未被 UI 使用的 inbox-state-ready 也已删除，
迁移及旧历史读取中的 READY 处理保留，不因入口清理改写历史数据。

每日统计按本地午夜分界，跨日 CLOCK 分摊；历史后端负责结算／补结算。
已结算快照按既有规则读取，missing 不等于零，旧规则边界也不能随意重写。
同一任务对应多个承诺时，各条责任分别判断兑现，直接 CLOCK 投入只累计一次。
日结在同一事务内向 events 写入按承诺 ID 关联的 attempt-fulfilled 及实际兑现日期，
后续结转不依赖来源仍在 Agenda。显式重算替换该日统计和兑现事件，失败一起回滚。
旧快照保持原样，来源仍有真实 CLOCK 时可回填兑现；已经失去来源且没有 ID 关联的
旧记录不能安全还原，不按标题猜测，也不把整个 met 日当作每条承诺的关联。
[history-read](../org-workflow-history.el) 和视图／图表层只读；界面不能重算承诺或写源文件。
长期追踪现在在 Emacs 原生历史工作台中完成。
外部网页启动器和后台 JSON 导出已移除；[显式静态导出](../org-workflow-web-export.el)
及旧历史解析仍供手动使用和迁移，不是当前后台追踪入口。

## 5. Evil、字体与桌面集成

- Evil 和 Org Modern 可选；包不负责调用 `evil-mode 1` 或安装 Evil。
- 图形习惯周追踪可选使用 nerd-icons 的同系列方框图标；无该库或终端环境用 Unicode 方框，
  不增加包硬依赖。图标字体由 nerd-icons 的用户配置决定。
- `org-workflow-install-default-bindings` 默认 nil，当前宿主设为 t。
  它仅控制可选共享 Org／Agenda／Embark 绑定，不是 Evil 总开关。包不安装任何全局键，
  原有十个全局绑定已移至宿主 `modules/org-workflow-config.el`；包内私有界面键表保留。
- 普通 Agenda 的 Normal 辅助绑定由生命周期工具管理；Sprint 复制局部 map，
  只在专用界面安装普通键及 Normal 键；历史面板适配 Normal/Motion，收集回顾适配 Normal。
- 共享键停用时只恢复仍由包占用的值，保留用户后来改动。Evil 延迟加载也受模式状态保护。
- 个人 intercept map 可以覆盖 Sprint 按键。实际优先级须查运行 buffer 的
  `key-binding`、`current-active-maps`，不能仅凭绑定定义断言某个键已生效。
- 生命周期改变 Org TODO 规则时，应重建已开启的 Org Modern 字体规则；不能只刷新 Org 正则。
- 颜色从宿主主题与包 face 继承；维护 UI 时检查实际中文字体、像素宽度与 Evil 状态。
- [GNOME／桌面／截图配套](../extras/README.md) 独立安装，不随 Lisp tar 自动部署。
  GNOME 固定调用 `~/.local/bin/org-workflow-client`；须将 extras/bin 的该脚本和
  `emacs-systemd-client` 一起安装。仅在宿主 `bin/` 有脚本不能满足这个入口。
  仅 Win+E 新建 frame 时传入 `org-workflow-initial-target`，server hook 消费一次标记
  后显示当前任务。共用访问入口递归展开当前任务正文及所有子标题，并收窄到该子树。
  普通建窗及启动不跳转任务；页面客户端在下一轮事件打开指定页面。
  右顶栏 Agenda 动作使用专用入口，打开后明确显示 Agenda 再 delete-other-windows，
  覆盖复用窗口跳过 only-window 或恢复原选中窗口的路径；普通及双栏入口不变。
  宿主 core-optimize 在桌面调度期间使用已启用 GCMH 的高阈值，返回或出错后恢复原值；
  包不依赖 GCMH。core-theme 只在初始化加载主题，新 frame 沿用主题及 CJK fontset hook。
  当前计时接口使用 `org-workflow-focus-timer-*`，没有旧名称兼容别名。
  稳定的 D-Bus 路径、接口名和扩展 UUID 是协议，不能随命名整理顺手改掉。
- GNOME Wayland 更新 JS 后需要新 Shell 会话；不要自动注销用户。
  源码已复制、运行版本已载入和实际动作已验证是三个不同结论。

## 6. 验证与编译

依赖：Emacs 31.1、SQLite、Org、Vulpea、Vulpea Journal、vui、Transient、Org Super Agenda。
声明版本以 [包头](../org-workflow.el) 为准，Evil/Org Modern 不变成运行时硬依赖。

在包仓库根目录：

```sh
make bootstrap       # GNU/MELPA 依赖与开发工具进入 .ci/elpa
make check           # compile + test + lint + checkdoc + 安装 smoke
make test            # 单独运行回归
make compile         # 在 dist/compile 中编译副本
make package         # dist/org-workflow-<Version>.tar
```

[test runner](../test/run-tests.el) 使用临时 notes/store/profile。
[build 脚本](../scripts/build-package.el) 的 test 分支先复制源码，避开宿主 User Lisp
字节码与隔离依赖中 Org 版本不同的干扰；测试时间 locale 为 C，导出时间 fixture 指定上海时区。
compile 分支先暂存全部源码，优先从暂存目录加载较新源码，避免宿主旧字节码干扰编译。
bootstrap 安装 Evil 等开发测试工具，不等于把它们写入运行时依赖。

日常交互与选择器测试使用现行 TODO／DIVE／DONE／HOLD 夹具；已退役的 READY 操作
不再作为日常功能测试。旧 READY 日志、历史结果和迁移读取的兼容性验证仍保留。
涉及 Agenda／DIVE 的测试依赖 runner 的 Workflow 初始化；裸加载单个测试文件
出现状态识别或 Agenda 入口缺失时，应先核对测试环境。

User Lisp 会递归处理仓库。宿主 early-init 必须排除 `.ci`、`dist`、`test`、`scripts`、
`extras`、`docs`、`recipes`、`.github`，并在编译前激活依赖。
源码更新后运行 `M-x prepare-user-lisp`；前缀参数可强制重新编译。
已加载的旧定义不会因文件编译自动全面替换；运行时核对 `symbol-file`／`locate-library`。

验证按改动范围选择。涉及数据用现有 ERT；涉及界面、实际服务或桌面桥接则补实际路径验证。
图形检查用临时 frame／fixture，避免启动真实计时、写测试任务或无必要地重启整个用户会话。
对当前宿主做服务重启前检查活跃 clock、未保存 buffers 和待恢复操作，使用已有保存／checkpoint 入口。

[验收记录](verification.md)保存具体日期和范围。最近功能变更的完整检查为 503 ERT；
后续菜单像素对齐只做路由回归与实际 PNG 检查，用户已确认显示效果。
这些是历史记录，不是本次会话自动获得的当前提交保证；不要固定依赖某个测试数量。
GitHub CI、源码本地成功、真实 GUI 和物理鼠标验证也不能互相代替。

## 7. 维护和交付习惯

先看当前用户请求、Git 工作区和本目录 [AGENTS](../AGENTS.md)。
解释／调查请求不修改产品；实现获授权后完成范围内工作，不逐步重复确认。
保护已有未提交改动；每个完成验证的独立改动创建范围明确的本地提交。
推送、发布和破坏性操作需要当前会话范围内的授权，不能由“已能使用 GitHub”推断。

包构建只包含根目录 Lisp、生成的 metadata/autoloads 和许可证；文档与 extras 是仓库资料。
当前 MELPA recipe 仍是候选；本地 tar 成功不等于远端 package-build 验证或 MELPA 接受。
遇到问题先找对应模块及测试，用已有原生路径解决；不为假想未来需求加入抽象层。

本轮减法审查和未处理候选见 [2026-10-11 精简审查](maintenance-audit-2026-10-11.md)。
第二轮已清理审查记录中的无调用者代码和旧 future 状态；共享标题按钮键表改名为
`org-workflow-agenda-header-button-map`，当前日期切换／完成回顾继续使用。
旧界面断言已更新，测试 fixture 不再依赖实际钟点；最终全套 568 项 ERT 全部通过，
编译成功。保留标准计时、习惯、排序及数据迁移的有效验证。

顶栏左菜单顺序为：打开当前任务、完成当前任务、取消计时、补记番茄钟、任务操作。
没有单独计时分区，任务子菜单只提供步骤／前置任务和延期。今日习惯直接列在
状态与习惯分区，左键临时将该习惯置为共用当前项，再点当前习惯恢复原普通队列。
选择保存在会话／当日的 `org-workflow-habit-selection`，不改原普通队列准入或 Org 状态；
选中行显示箭头，完成行显示勾并禁用。完成仍走一级“完成当前任务”。切换正常结束
原周期，不自动开始计时；完成或失效的习惯自动回到普通队列，跨日恢复默认提醒规则。
右菜单移除重复 Sprint 入口，新增 history action，经 frame-aware desktop bridge 调用
`org-workflow-history-panel`；右顶栏左键仍打开 Sprint，周日志菜单保留。

周状态指示使用绿／灰／琥珀橙和 0–600 分钟连续强度；样式为紧凑半透明圆角底座、
柔和填充和暖色今日短下划线。未知／未来不伪造投入量；仅改变桌面显示样式。

周指示底座上／下 padding 为 8／3px，补偿下方 3px 间距与 2px 今日标记，
使状态胶囊本体上下居中；不可直接恢复为等距 padding。

顶栏周状态范围为本周日到周六，复用 habits 的周日起点；星期标签同序。
此显示范围不改变 weekly 库用于现有周日志文件的周一起点和命名。

### 桌面响应延迟

`org-workflow-history--tasks` 在构建完整条目前，先检查直属正文是否有标准 CLOCK
行或当日 DONE/CLOSED；没有事实的标题不读取父组／优先级／安排元数据。
仍用共用 item-day-record 计算分钟与完成，不改变跨午夜、父子 CLOCK 或现场编辑语义。
宿主 `modules/core-optimize.el` 的现有 GCMH 包装同时覆盖 desktop dispatch、
frame dispatch 和 status-json；请求结束／报错后恢复阈值，不全局抬高 GC 阈值。
2026-10-12 的现场只读测量：状态查询中位数约 1885ms → 416ms；冷面板约 808ms。
相关 61 项测试通过，现场最近八天任务记录一致；没有新增持久或跨请求缓存。

状态 JSON 请求在调用内共享当天任务事实和承诺进度，空结果也作为有效读取结果；
请求结束即释放缓存，下一次请求仍读取现场编辑。这个缓存不覆盖写操作或历史重算。
跨日期任务读取还在同一请求内共享每个文件的事实标题位置及 CLOSED 日期，
保留原有 Org 扫描过滤和逐日 CLOCK 计算；不缓存临时 buffer 的 marker。
下一请求重新扫描，仍读取未保存编辑；非请求读取不复用位置。
events 的承诺 ID 索引在打开数据库时以 `IF NOT EXISTS` 建立，既有数据库也适用。
补结算为本轮建立兑现日期和最终状态索引，按到期日推进候选承诺，避免对已经兑现／
终结的记录逐日重复查询；旧快照仍允许用可验证的源 CLOCK 回填更早的兑现事件。
不新增持久回填游标，不改变显式重算及逐日事务边界。

GNOME 动作执行期间的 Changed 通知和轮询合并到现有待刷新队列；所有在途动作
成功或失败后读取最终状态。读取期间及动作完成以后到达的新通知仍可触发后续读取，
不能无条件丢弃，以免遗漏真实变化。此行为需要安装更新的 JS 并进入新 Shell 会话。

桌面 select 用 emacsclient 的 --create-frame／--frame-parameters 创建 workflow-select
迷你缓冲区窗口，再调用选择入口排队执行；显示环境由原生客户端传递。入口复用该
窗口，不依赖 daemon 的 DISPLAY／WAYLAND_DISPLAY，避免无图形 frame 时误报。

### 2026-10-15 审计修复边界

- 日结和习惯同步在 `quit` 等非局部退出时也回滚 SQLite 事务。
- 习惯来源扫描记住曾含习惯的 buffer；删除最后一个嵌入习惯后保存仍同步。
  同步失败保留重试标记，成功清空后普通保存不再触发该同步。
- Inbox 归档逐项保存目标，再保存源删除；开始前校验所有目标。
  后续项失败不回滚已完成项。目标未落盘时恢复当前项两端原文；目标已落盘
  而源保存失败时保留源的待保存删除，避免把已归档任务重新放回内存源文件。
  保存后钩子抛错也要检查目标是否已经落盘；不以函数正常返回作为唯一依据。
