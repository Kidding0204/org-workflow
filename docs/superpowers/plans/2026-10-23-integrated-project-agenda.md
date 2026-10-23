# Integrated project Agenda implementation plan

**Goal:** Implement the user's file/outline model and integrated daily workbench.
**Architecture:** Org files own goals, level-one headings own projects, level-two headings own stages. Read-only projections share native markers; all mutations use existing transactions. Existing IDs and facts remain intact; WORKFLOW_KIND and WORKFLOW_GOAL_ID no longer override structural identity. Plain organizational headings and Inbox are not activated as learning projects.
**Tech stack:** Emacs Lisp, Org, SQLite, ERT.
**Spec:** User's six requirements in this conversation, superseding the previous explicit-registration design. Autonomous implementation already authorized.

- [x] Structural discovery: agenda files without tags, stable project IDs generated only by lifecycle writes, file-level bulk pause/resume, no duplicate legacy obligations. Tests: discovery/no writes, ID bootstrap, pause ownership, stages not selected as daily tasks.
- [x] Today projection: retain completed scheduled leaves in shared ordering; attach 1–3 quiet next rows only to commitments; exclude already scheduled tasks; truncate project/stage breadcrumb independently. Tests: render before/after completion, stable successor placement, bounded labels, no renderer writes.
- [x] Integrated project section: goals, project progress, seven daily obligation states, completion streak, stages with native markers and actions. Simple repeat habits remain aligned one-line rows; no large graph in periods. Inbox loses candidate preview; Today loses completed section.
- [x] Document changed data/entry rules; run package ERT and compile, review, commit focused changes.

Review focus: paused commitments versus done facts; file-only goals versus source heading actions; unsaved buffers/narrowing; duplicate previews and future dates; native row properties surviving finalization. Personal learning plans are not automatically rewritten into invented exercises.


## Execution record

- Implemented file goals, structural project/stage selection, transactional ID bootstrap and file-goal pause ownership. Read projections do not register/migrate personal sources.
- Reused native Agenda sorting for completed + unfinished scheduled leaves; previews have separate display metadata and never enter the execution queue.
- Updated historical two-level execution fixtures to represent concrete tasks beneath stages; updated UI assertions for intentionally removed optional/completed sections and for all Agenda files entering scope.
- Independent review (review_integrated): fixed stage pause retaining invisible responsibilities, empty stage successor admission, and refile retaining obsolete pause ownership. Reproducing tests failed before fixes and pass afterward.
- Added conservative streak gap handling: unknown dates do not imply consecutive completion. Added window-resize truncation and exclusion of completed empty containers from time bands.
- Full verification and commit are recorded in docs/verification.md after the final run. Live daemon/font/personal-course acceptance remains separate from temporary-fixture automation.

Final verification: 698/698 ERT; byte compilation clean; whitespace check clean. No deferred reviewer findings.
