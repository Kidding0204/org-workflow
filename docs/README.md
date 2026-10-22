# Org Workflow 使用指南

这些指南描述 package 0.1.0 的工作流。先完成主仓库 [安装与配置](../README.md)。
源文件、数据库与备份由用户管理，不放在 package 安装目录。

维护本包的会话先读[项目上下文](CONTEXT.md)，再按阅读地图进入源码与测试。

## 日常使用

| 要做的事 | 文档 |
| --- | --- |
| 管理长期目标、项目状态与每日推进 | [项目规划与每日底线](project-workbench.md) |
| 挑选、安排、重排、撤销任务；鼠标操作与双栏工作台 | [Sprint 安排工作台](agenda-planning-workbench.md) |
| 随记、捕获与收集项归类 | [周日志与收集箱](daily-journal-inbox.md) |
| 理解 DIVE 范围与每日有效投入 | [DIVE 与每日尝试](dive-and-daily-attempts.md) |
| 准备项目背景、任务边界、估时与阶段目标 | [规划辅助](workflow-planning.md) |
| 为当前任务收集截图 | [任务截图](screenshot-inbox.md) |
| 记录请假或补录昨天的说明 | [请假条](workflow-leave.md) |
| 查看原生月历、投入和日详情 | [历史面板](workflow-history-panel.md) |

第一入口是 `M-x org-workflow-menu`；可在个人配置中自行绑定 `C-c o m`。
菜单按工作台、规划与收集、执行、回顾、计时与习惯及设置分组。`h` 打开 Emacs 原生长期历史。

全局快捷键由用户配置定义，文中的 `C-c o m` 等键位是配置示例。
`org-workflow-install-default-bindings` 只控制可选共享 Org／Agenda／Embark 绑定。
命令始终可通过 `M-x` 调用。Sprint 中 `?` 查看当前界面按键。

## 维护

- [任务与历史模型](workflow-architecture.md)：事实来源、承诺、属性、结算与恢复。
- [模块边界](gtd-module-layout.md)：公共入口与内部模块职责。
- [配套工具](../extras/README.md)：可选 GNOME、截图、org-protocol 和网页。
- [网页历史快照](../extras/web/README.md)：导出和本地运行；原生面板不依赖 JSON。

备份必须同时包含 Org 文件和 `org-workflow-store-file` 指向的 SQLite 数据库。
数据库保存历史事实与恢复记录，不是可清理的缓存。

[0.1.0 提取验收记录](verification.md)记录本次验证边界。
