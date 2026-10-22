# Project Workflow Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement task-by-task.

**Goal:** Add a project planning surface and the approved daily learning contract.
**Architecture:** Explicit Org goal/project markers, native special-mode planning
buffer, existing transaction/event store; dated daily completion/time-floor adapter.
**Tech Stack:** Emacs Lisp, Org, SQLite, ERT, existing GNOME extension.
**Spec:** docs/superpowers/specs/2026-10-23-project-workflow.md

## Global Constraints
- Preserve Today layout, personal data, existing history and unrelated edits.
- No new dependencies; no publishing or live data migration.
- Source reads preserve point/narrowing/unsaved edits; writes use store operation.

## Review Focus
- Nested DIVE groups and QA/LAB/HW are not independent projects/steps.
- Pause/resume twice, manual state overrides, completed commitments.
- Midnight/offline catch-up must not double count or rewrite yesterday.
- Future start dates stay on project and do not spread to all descendants.
- Empty/withdrawn commitments must not vacuously meet daily floor.

### Task 1: Project model and planning buffer
Files: new org-workflow-projects.el, org-workflow-project-view.el,
test/org-workflow-projects-test.el; integrate org-workflow.el, weekly and agenda.
Interfaces: projects-collect returns source-backed goal/project plists;
projects-register, projects-set-state, projects-set-start; project-view opens buffer.
- [x] Write/run failing source discovery, next-step, read-only render tests.
- [x] Implement explicit boundary collection and plain view with navigation/actions.
- [x] Run focused ERT and commit.

### Task 2: Daily responsibilities and lifecycle
Files: projects module, commands/core/history integration and project tests.
Interfaces: projects-sync generates one record per project/date; goal-state handles
batch provenance; projects-row-p identifies daily records through event metadata.
- [x] Test generation idempotency, completion freeze, rollover, pause/resume and goal provenance.
- [x] Implement in existing transactions, exclude project schedules from normalization,
  disable legacy group lookahead across explicit project boundaries.
- [x] Run focused lifecycle/storage ERT and commit.

### Task 3: Daily floor and delivery
Files: history, panel/history UI, GNOME status display, docs.
Interfaces: history progress retains counts and adds total investment/floor reason;
old dates and snapshots retain old interpretation.
- [x] Test completion-only boundary, global-time alternative, empty set, historical isolation.
- [x] Implement dated semantics and minimum-time configuration with recorded daily values.
- [x] Run suite, compile, review diff, document runtime acceptance, commit.

## Execution record

Implemented in the clean independent package checkout; parent Emacs repository
was dirty and untouched. User authorized independent execution without further
approval. Baseline: 661/661 ERT. Final: 684/684 ERT (23 new project tests),
byte compilation, all GNOME JavaScript test files and git diff --check passed.
A separate read-only reviewer reproduced and rechecked lifecycle fixes with
isolated fixtures. The source suite includes rollback, adoption, nested scopes,
paused ancestors, narrowed buffers, daily floors and historical policy boundaries.

Rulings: explicit WORKFLOW_KIND markers avoid turning old DIVE chapters into
projects; cross-file goal IDs preserve material locations. Missed start dates
while a goal is paused require explicit rescheduling. Global minimum defaults to
60 configurable minutes, recorded per date. No live note migration or daemon/
Shell restart; layout/font and desktop acceptance remain interactive.

All three tasks shipped together in one focused feature commit because the
project lifecycle, historical contract and view form a single usable change.
