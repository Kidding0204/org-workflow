# org-workflow：项目会话上下文

核对日期：2026-10-07。面向需要研究、修改或排查本包的会话。
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
当前个人配置绑定 `C-c k`；包自身在默认绑定开启时提供 `C-c o m`。
常用菜单项为 `a` Sprint、`A` 双栏工作台、`n` 捕获、`s` 开始任务、
`h` 原生长期历史、`e` 晚间收尾、`C` 参数设置。
计时项是多键序列 `f t / f f / f s / f r`，不是单个名为 ft 的键事件。

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
[declarations 库](../org-workflow-declarations.el) 只声明跨模块变量，保证字节编译时动态绑定正确；
不要把重复声明直接当成冗余初始化删除。

## 4. 数据和行为约束

### 任务、范围与承诺

- 状态模型为 `TODO / DIVE | DONE / HOLD`；DIVE 是活跃任务组，HOLD 排除对应子树。
- Agenda 中 project/area 文件提供任务。默认未安排候选要求直接父标题为 DIVE；
  习惯、HOLD 子树等排除。执行队列另按安排日期和时段筛选，不以 DIVE 标签继承准入。
- 原生 priority A/B/C 表达上午／下午／晚上的安排意图。
- 当前执行目标独立于排序建议；刷新、重排和展示不能悄悄切换执行目标。
- 每日“承担并尝试”与实际完成不同，不应因满足当天责任自动将任务改为 DONE。
- 承诺创建／调整规则由 core、commands、store、history 共同实现。
  不用当前 SCHEDULED 或某个标签重新推算过去承诺集合。
- `ID` 和 `WORKFLOW_COMMITMENT_ID` 负责关联；`WORKFLOW_ORDER` 如 `A/0` 保存时段与序号。
  延期计数、原定日期提示和重复承诺时间镜像已退役，不能在渲染中重新写入。
- `Effort`、`WORKFLOW_BOUNDARY`、`WORKFLOW_RESUME` 等仍有用途；不可按前缀批量删属性。

具体准入、跨日、推进和兑现条件见 [任务与历史模型](workflow-architecture.md)，
涉及这类行为必须同时看相关 core/store/history 测试。

### 持久事实与恢复

Org 文件保存结构、安排、状态和真实 CLOCK；SQLite 保存持久事实与恢复映像。
[store](../org-workflow-store.el) 的七张表为 `meta`、`commitments`、`events`、`days`、
`operations`、`habit_days`、`leave_records`。数据库不是可随意重建的缓存。

任务写操作走已有共用事务边界。Org buffer 文本与 SQLite 的同步不是一个普通文件保存：
`operations` 保存 before/after，启动恢复会校验版本；独立手动修改产生冲突时不能覆盖。
checkpoint 按文件退役已保存的恢复映像，不能一次丢弃其他未保存文件的恢复能力。
不要为“修复启动”直接清空 operations、删除数据库、伪造 checkpoint 或覆盖用户 Org 文件。
迁移／清理操作先满足已有校验并做备份，参见 [恢复边界](workflow-architecture.md#保存恢复与备份)。

### 计时、结算与展示

Focus Timer 通过标准 Org Clock 记录；自身停止时默认不足五分钟的片段取消，
普通手动 Org Clock 不因这条规则被接管。计时状态机在 [focus-timer](../org-workflow-focus-timer.el)。

每日统计按本地午夜分界，跨日 CLOCK 分摊；历史后端负责结算／补结算。
已结算快照按既有规则读取，missing 不等于零，旧规则边界也不能随意重写。
[history-read](../org-workflow-history.el) 和视图／图表层只读；界面不能重算承诺或写源文件。
长期追踪现在在 Emacs 原生历史工作台中完成。
外部网页启动器和后台 JSON 导出已移除；[显式静态导出](../org-workflow-web-export.el)
及旧历史解析仍供手动使用和迁移，不是当前后台追踪入口。

## 5. Evil、字体与桌面集成

- Evil 和 Org Modern 可选；包不负责调用 `evil-mode 1` 或安装 Evil。
- `org-workflow-install-default-bindings` 默认 nil，当前宿主设为 t。
  它控制默认全局／共享绑定，不是 Evil 总开关；包内私有界面键表仍存在。
- 普通 Agenda 的 Normal 辅助绑定由生命周期工具管理；Sprint 复制局部 map，
  只在专用界面安装普通键及 Normal 键；历史面板适配 Normal/Motion，收集回顾适配 Normal。
- 共享键停用时只恢复仍由包占用的值，保留用户后来改动。Evil 延迟加载也受模式状态保护。
- 个人 intercept map 可以覆盖 Sprint 按键。实际优先级须查运行 buffer 的
  `key-binding`、`current-active-maps`，不能仅凭绑定定义断言某个键已生效。
- 颜色从宿主主题与包 face 继承；维护 UI 时检查实际中文字体、像素宽度与 Evil 状态。
- [GNOME／桌面／截图配套](../extras/README.md) 独立安装，不随 Lisp tar 自动部署。
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
bootstrap 安装 Evil 等开发测试工具，不等于把它们写入运行时依赖。

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
需要 GSD 时选择适合当前范围的流程，不把一次局部维护扩成未授权的新里程碑。
