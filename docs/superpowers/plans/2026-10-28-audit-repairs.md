# Workflow 审查修复实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox syntax.

**Goal:** 修复已批准审查中的 11 类根因，保留 Org 源事实、历史和既有交互。
**Architecture:** 在现有身份、事务、项目责任与只读视图入口修复，不重写全包。各文件组独立 RED→GREEN 后整体验证。
**Tech Stack:** Emacs Lisp／Org／SQLite、TypeScript、shell。
**Spec:** `docs/reviews/2026-10-28-org-workflow.md` 与用户“确认修复”。

## Global Constraints

- 只用临时 Org／SQLite 测试；保留父配置脏改动，不改历史结算。
- 只读渲染不创建 ID；保留当前任务重命名／原生重排、时钟事实、正文和单步 U。
- 当前 DONE/HOLD 分支统一阻断；历史进度政策保留按日期边界的旧语义。
- 沿用原生 hook、生命周期和事务入口，无新依赖。工作沿用当前干净功能分支。
- 独立本地提交；不推送，不自动改变 daemon／GNOME 会话。

## Review Focus

- 无 ID 的原生子树移动与删除必须能区分；同名条目不能互相代替。
- 内层状态命令在外层事务失败时，也应保留已经实际结束／取消的 CLOCK。
- 保存错误或外部文件变化不能让回滚覆盖用户外部编辑，恢复事实不能静默丢弃。
- U 恢复承诺的有效语义并保留后续正文／CLOCK，遇到后续关联变更须拒绝。
- 新旧历史字段兼容，严格拒绝非法新值；终端走现有回退。

### Task 1: 执行身份与政策

**Files:** core、items、新增 audit-execution 测试；负责人 repair_execution。
**Interfaces:** 消费 execution-blocked-p；输出独立选择身份校验、只读唯一 habit key。
- [x] 写并运行删除／替换、重命名／原生移动、祖先暂停、当前／旧政策、同名 habit 回归，观察 RED。
- [x] 最小修改现有入口；针对性 ERT GREEN；核对生命周期。
- [x] 审查并提交该文件组。

### Task 2: 归类身份与完整承诺撤销

**Files:** agenda-projects/view/mouse/plan-undo、project-classify、projects、对应测试；负责人 repair_agenda。
**Interfaces:** 消费同一 execution-blocked-p；追加可补偿 superseded 事实，不删除历史事件。
- [x] 公开 C 与鼠标承诺＋U、关联冲突、正文／CLOCK 保留、DONE 分支回归 RED。
- [x] 保存并校验来源身份、完整撤销关联／当日 meta／有效事件语义，GREEN。
- [x] 审查并提交该文件组。

### Task 3: 导出与入口契约

**Files:** extras/web parser/tests、weekly、dispatch／terminal tests、client shell test；负责人 repair_integrations。
**Interfaces:** 消费真实导出字段，不复制业务统计逻辑。
- [x] 新旧 payload／非法字段、终端入口、shell 分支先验证 RED。
- [x] 更新严格 parser、菜单公开路由与陈旧 argv，Node／ERT／shell GREEN。
- [x] 审查并提交该文件组。

### Task 4: 事务、CLOCK 与磁盘回滚

**Files:** store、commands（如确有需要）、新增 audit-store 测试；负责人 root。
**Interfaces:** 内存文本／SQLite 可回滚；实际关闭／取消的 CLOCK 是保留事实；原生保存 hook 记录磁盘副作用。
- [x] 提交后 quit、公开 TODO 失败、外层事务停钟、事务保存后错误／外部修改回归 RED。
- [x] 保护短提交临界区；协调 CLOCK 及安全磁盘恢复，针对性 GREEN。
- [x] 审查并提交该文件组。

### Task 5: 契约回归与交付

**Files:** 陈旧测试、CONTEXT／模块文档、必要 checkdoc、修复日志；负责人 root。
- [x] 按当前已批准行为更新旧断言与层级 fixture，修正缺失文件交互测试设置，不掩盖失败。
- [x] 完整 ERT、编译、checkdoc、安装 smoke、便捷 shell／前端契约验证。
- [x] 新鲜整体代码审查；重要发现先 RED→GREEN，再最终全套验证。
- [x] 更新当前维护入口与修复记录，提交并报告验证边界。
