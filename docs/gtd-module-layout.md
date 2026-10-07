# Workflow 模块边界

[文档入口](README.md) · [任务与历史模型](workflow-architecture.md)

`org-workflow.el` 是 package 入口。用户配置路径、Agenda 文件和可选集成后，启用
`org-workflow-mode`；不再通过依次 require 个人配置模块注册功能。

| 文件 | 职责 |
| --- | --- |
| `org-workflow.el` / `org-workflow-lifecycle.el` | 全局模式、初始化顺序、hook/advice/key 的启用与撤销、可配置路径 |
| `org-workflow-core.el` | 任务筛选、执行队列、选择、排序、DIVE 相邻组开放与推进 |
| `org-workflow-agenda.el` | Sprint 配置和任务／捕获入口 |
| `org-workflow-agenda-view.el` / `org-workflow-agenda-layout.el` | 分组渲染、双栏工作台、窗口与同步刷新 |
| `org-workflow-agenda-actions.el` / `org-workflow-agenda-plan-undo.el` | 日期、时段、排序、批量事务与安排撤销 |
| `org-workflow-agenda-console.el` / `org-workflow-agenda-mouse.el` | Sprint 键盘、帮助与鼠标交互 |
| `org-workflow-agenda-inbox.el` / `org-workflow-agenda-review.el` | 周收集箱归类、积压与回顾 |
| `org-workflow-commands.el` / `org-workflow-store.el` | 共用变更边界、SQLite 事实及 Org 恢复事务 |
| `org-workflow-history.el` / `org-workflow-journal.el` | 兑现、结算、重算、历史兼容与 CLOCK 辅助 |
| `org-workflow-migrate.el` / `org-workflow-cleanup.el` | 有备份的旧模型迁移与显式属性清理 |
| `org-workflow-weekly.el` | 周日志、周文件 Agenda 同步与导航 |
| `org-workflow-planning.el` / `org-workflow-guidance.el` | 规划接口、背景、周目标、开工与续接提示 |
| `org-workflow-habits.el` / `org-workflow-evening.el` | 原生习惯及晚间 Agenda |
| `org-workflow-leave.el` / `org-workflow-panel.el` | 请假与桌面只读投影 |
| `org-workflow-focus-timer.el` | 基于标准 Org Clock 的专注生命周期 |
| `org-workflow-screenshot.el` | 当前任务截图收集及可选桌面辅助工具 |
| `org-workflow-history-view.el` / `org-workflow-history-chart.el` | 后端视图、日期选择与 SVG 映射 |
| `org-workflow-history-panel.el` / `org-workflow-history-workbench.el` | 原生历史界面、月历及日详情 |
| `org-workflow-web-export.el` / `extras/web/` | 已结算 JSON 导出与只读网页 |

Evil、Org Modern 和个人主题由用户配置，可选集成不会成为核心硬依赖。

## 修改与验证

任务行保留原生 Agenda marker 与类型；操作仍经标准 Org 命令和共用事务边界。
界面消费已定义的历史事实，不在渲染中重算承诺或修改源文件。

运行 `make check` 验证编译、ERT、metadata、文档、构建和隔离安装。
`test/` 中保留提取后测试；桌面桥接和 GNOME 纯逻辑测试位于 `extras/`。
图形交互、实际桌面服务和截图 Portal 需要另行验证。
