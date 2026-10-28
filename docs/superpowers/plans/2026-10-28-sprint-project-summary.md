# Sprint Project Summary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 单栏在随时与完成回顾之间展示可管理状态的项目／阶段摘要。

**Architecture:** 在 agenda-projects 共享项目进度读取器中增加阶段计数；同模块渲染摘要行并附原生 Agenda marker。agenda-view 只在 combined pane 插入摘要。使用现有状态事务与 org-modern 渲染，不引入依赖、advice 或生命周期入口。

**Tech Stack:** Emacs Lisp, Org Agenda, optional org-modern, ERT.

**Spec:** docs/superpowers/specs/2026-10-28-sprint-project-summary-design.md

## Global Constraints

- 状态、项目／阶段、进度三列；按 Area 与源顺序组织，任务不显示。
- 单栏显示、双栏不重复；今日和明日均有摘要。
- Org／SQLite 不因渲染而写入；状态修改使用现有公开接口。
- TAB 另窗展示并保留 Agenda 焦点；Enter 当前窗打开；双栏 TAB 不变。

## Review Focus

- 大小不同阶段、嵌套任务、QA 后代不得重复或误计。
- 无状态阶段、无任务项目、已有源 cookie 的标题不伪造状态、不显示重复进度。
- 窄窗与长中文标题不破坏列顺序，保留完整标题提示。
- 原生 marker、Evil 与 org-modern 渲染不能吞掉状态／访问操作。
- 渲染不能创建 ID／修改源文本；状态变更刷新需保持项目行位置。

### Task 1: Read-only summary with native navigation and state editing

**Files:**
- Modify: org-workflow-agenda-projects.el, org-workflow-agenda-view.el, org-workflow-agenda-mouse.el
- Create: test/org-workflow-agenda-project-summary-test.el
- Modify: docs/CONTEXT.md, docs/project-workbench.md

**Interfaces:**
- Consumes: org-workflow-projects-collect, org-workflow-projects-progress, org-workflow-agenda-project-state and source markers.
- Produces: stage :done/:total in progress; org-workflow-agenda-project-summary rendering, summary row identity and source navigation.

- [x] Write ERTs for weighted project/stage statistics, single vs double pane placement, minimal rows, status editing, org-modern and native TAB/Enter navigation; run RED.
  Expected: new summary tests fail before implementation, with existing tests unaffected.
- [x] Extend the existing progress reader, render compact summary rows, add combined-pane insertion and native interactions; run GREEN.
  Expected: focused new and prior project/Workbench tests pass using temporary Org/SQLite only.
- [x] Run necessary related ERT, package compilation and diff checks; document and commit.
  Expected: no new related failures, clean compilation, focused Git commit.
