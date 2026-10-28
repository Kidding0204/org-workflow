;;; org-workflow-projects.el --- Structural learning projects -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Jinwang Dong
;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Commentary:
;; Agenda file names own goals; level-one TODO headings own projects.
;; Reads return source locations.  Mutations share the Org/facts transaction.
;;; Code:
(require 'org-workflow-core)
(require 'org-workflow-store)
(require 'org-workflow-sources)

(defvar org-workflow-projects--syncing nil)
(defvar org-workflow-projects--batch nil)
(defvar org-workflow-projects--read-cache nil
  "Project collection shared only by sections of one read-only Sprint render.")
(declare-function org-workflow-history--row-state "org-workflow-history" (row date))

(defun org-workflow-projects--agenda-file-p ()
  "Whether this buffer belongs to the configured Agenda sources."
  (org-workflow-source-agenda-file-p))

(defun org-workflow-projects-kind ()
  "Return project for a level-one TODO heading in an Agenda source.
Plain organizational headings, typed notes and simple habits are not projects."
  (when (and (not (org-before-first-heading-p))
             (= (org-outline-level) 1)
             (org-workflow-projects--agenda-file-p)
             (org-workflow-target--blocking-task-p)
             (not (org-entry-get nil "JOURNAL_INBOX"))
             (not (and (fboundp 'org-workflow-collection-inbox--heading-p)
                       (org-workflow-collection-inbox--heading-p)))
             (not (equal (org-entry-get nil "STYLE") "habit")))
    "project"))

(defun org-workflow-projects-stage-p ()
  "Whether point is a structural stage rather than an executable step."
  (and (= (org-outline-level) 2)
       (org-workflow-projects--agenda-file-p)
       (not (org-workflow-qa-p))
       (not (equal (org-entry-get nil "STYLE") "habit"))
       (save-excursion
         (org-up-heading-safe)
         (equal (org-workflow-projects-kind) "project"))))

(defun org-workflow-projects--file-goal-id ()
  "Return the identity of this Agenda file's long-term goal."
  (concat "file:" (file-truename buffer-file-name)))

(defun org-workflow-projects--goal-pause (id)
  "Read the pause batch for file goal ID without opening an unused store."
  (when org-workflow-store-enabled
    (org-workflow-store-meta (concat "goal-paused:" id))))

(defun org-workflow-projects-root ()
  "Return the nearest structural project marker, preserving point and restriction."
  (org-with-wide-buffer
   (unless (org-before-first-heading-p)
     (org-back-to-heading t)
     (catch 'root
       (while t
         (when (equal (org-workflow-projects-kind) "project")
           (throw 'root (point-marker)))
         (unless (org-up-heading-safe) (throw 'root nil)))))))

(defun org-workflow-projects--location ()
  "Read stable identity and source position at point."
  (list :file buffer-file-name :pos (point) :id (org-entry-get nil "ID")
        :title (org-get-heading t t t t)))

(defun org-workflow-projects-marker (item)
  "Resolve ITEM in its live source, verifying identity before returning a marker."
  (unless (plist-get item :file) (user-error "此行是分组标题，请选择具体项目"))
  (with-current-buffer (find-file-noselect (plist-get item :file))
    (org-with-wide-buffer
     (goto-char (min (point-max) (plist-get item :pos)))
     (when (plist-get item :file-goal) (goto-char (point-min)))
     (unless (or (plist-get item :file-goal)
                 (and (org-at-heading-p)
                  (if (plist-get item :id)
                      (equal (plist-get item :id) (org-entry-get nil "ID"))
                    (equal (plist-get item :title) (org-get-heading t t t t)))))
       (goto-char (point-min))
       (let ((id (plist-get item :id)) found)
         (when id
           (org-map-entries (lambda ()
                              (when (equal id (org-entry-get nil "ID"))
                                (setq found (point)))) nil 'file))
         (unless found (user-error "项目来源已变化，请刷新视图"))
         (goto-char found)))
     (point-marker))))

(defun org-workflow-projects--goal-id ()
  "Return this project's containing file goal."
  (org-workflow-projects--file-goal-id))

(defun org-workflow-projects--blocked-p ()
  "Whether an ancestor prevents this project's execution."
  (save-excursion
    (catch 'blocked
      (while (org-up-heading-safe)
        (when (or (member (org-get-todo-state) '("HOLD" "DONE"))
                  (and (equal (org-workflow-projects-kind) "project")
                       (not (equal (org-get-todo-state) "DIVE"))))
          (throw 'blocked t))))))

(defun org-workflow-projects--next ()
  "Read the next executable leaf in this project, preferring active branches."
  (let ((root (point)) (end (save-excursion (org-end-of-subtree t t))) candidates)
    (save-excursion
      (forward-line 1)
      (while (re-search-forward org-heading-regexp end t)
        (goto-char (line-beginning-position))
        (cond
         ((or (member (org-workflow-projects-kind) '("project" "goal"))
              (member (org-get-todo-state) '("HOLD" "DONE"))
              (equal (org-entry-get nil "STYLE") "habit"))
          (org-end-of-subtree t t))
         (t
          (let ((date (org-workflow-target--timestamp-date (org-entry-get nil "SCHEDULED"))))
            (when (and (org-workflow-target--unfinished-leaf-p)
                       (not (org-workflow-projects-stage-p))
                       (or (not date) (not (string< (org-workflow-target--today-string) date))))
              (let ((item (org-workflow-projects--location)) phase active)
                (save-excursion
                  (while (and (org-up-heading-safe) (> (point) root))
                    (unless phase (setq phase (org-get-heading t t t t)))
                    (when (equal (org-get-todo-state) "DIVE") (setq active t))))
                (push (append item (list :phase phase :active active)) candidates))))
          (forward-line 1)))))
    (setq candidates (nreverse candidates))
    (or (seq-find (lambda (x) (plist-get x :active)) candidates) (car candidates))))

(defun org-workflow-projects-collect ()
  "Read file goals and structural projects without changing sources."
  (if (not org-workflow-projects--read-cache) (org-workflow-projects--collect)
    (let ((items (gethash 'projects org-workflow-projects--read-cache 'unknown)))
      (if (not (eq items 'unknown)) items
        (puthash 'projects (org-workflow-projects--collect) org-workflow-projects--read-cache)))))

(defun org-workflow-projects--collect ()
  "Scan current sources for file goals and structural projects."
  (let (items)
    (dolist (file (org-agenda-files t))
      (let ((rows (org-workflow-source-read
                   file (lambda ()
                          (org-workflow-source-cached-read
                           'projects (org-workflow-projects--read-context t)
                           #'org-workflow-projects--file-items)))))
        ;; Goal pause is a database fact, not part of the source text revision.
        (when rows
          (setf (plist-get (car rows) :paused)
                (org-workflow-projects--goal-pause (plist-get (car rows) :id))))
        (setq items (nconc items rows))))
    items))

(defun org-workflow-projects--read-context (&optional dated)
  "Return project reader dependencies, including today when DATED."
  (list org-workflow-task-type-keywords
        (and (org-workflow-source-agenda-file-p) t)
        (org-workflow-projects--file-goal-id)
        (and dated (org-workflow-target--today-string))))

(defun org-workflow-projects--file-items ()
  "Read this source's structural project facts, excluding database pause."
  (let (items)
    (when (org-workflow--file-kind)
      (push (list :kind "goal" :file-goal t :file buffer-file-name
                  :pos (point-min) :id (org-workflow-projects--file-goal-id)
                  :title (file-name-base buffer-file-name)) items)
      (org-map-entries
       (lambda ()
         (when-let* ((kind (org-workflow-projects-kind)))
           (let ((next (org-workflow-projects--next)))
             (push (append (org-workflow-projects--location)
                           (list :kind kind :state (org-get-todo-state)
                                 :goal-id (org-workflow-projects--goal-id)
                                 :blocked (org-workflow-projects--blocked-p)
                                 :paused (org-entry-get nil "WORKFLOW_PAUSED")
                                 :pause-owner (org-entry-get nil "WORKFLOW_PAUSE_OWNER")
                                 :deferred-start (org-entry-get nil "WORKFLOW_START_DEFERRED")
                                 :start (org-workflow-target--timestamp-date (org-entry-get nil "SCHEDULED"))
                                 :phase (plist-get next :phase) :next next)) items))))
       nil 'file))
    (nreverse items)))

(defun org-workflow-projects-set-goal (_marker _goal-id)
  "Explain the structural replacement for cross-file goal associations."
  (user-error "长期目标由文件决定；请用 Org refile 将项目移动到目标文件"))

;;;###autoload
(defun org-workflow-projects-register (&rest _)
  "Explain automatic project discovery for existing callers."
  (interactive)
  (message "无需登记：Agenda 文件名是目标，一级 TODO 是项目，二级是阶段，三级是任务"))

(defun org-workflow-projects-row-p (row)
  "Whether commitment ROW is a daily project responsibility."
  (and row (caar (sqlite-select (org-workflow-store--db)
                               "SELECT 1 FROM events WHERE id=? AND kind='project-daily' LIMIT 1"
                               (list (car row))))))

(defun org-workflow-projects-superseded-p (row date)
  "Whether ROW stopped carrying forward into project duties by DATE."
  (let ((events (sqlite-select
                 (org-workflow-store--db)
                 "SELECT seq,kind,payload FROM events WHERE id=? AND kind IN ('project-superseded','plan-corrected') ORDER BY seq"
                 (list (car row))))
        superseded)
    (dolist (event events)
      (let ((payload (org-workflow-store--decode (nth 2 event))))
        (if (equal (nth 1 event) "plan-corrected")
            ;; 更正只补偿这次安排新增的事件；旧替换和已结算快照仍保留。
            (setq superseded (seq-remove (lambda (entry) (memq (car entry) (plist-get payload :events))) superseded))
          (when-let* ((since (plist-get payload :date)))
            (when (not (string< date since)) (push event superseded))))))
    (and superseded t)))

(defun org-workflow-projects--day-key (id date)
  "Return the daily responsibility key for project ID on DATE."
  (concat "project-day:" date ":" id))

(defun org-workflow-projects--row (project date)
  "Return PROJECT's frozen daily record for DATE, if any."
  (org-workflow-store-commitment
   (org-workflow-store-meta (org-workflow-projects--day-key (plist-get project :id) date))))

(defun org-workflow-projects--withdraw (project date)
  "Withdraw PROJECT's unfinished responsibility on DATE without losing clocks."
  (when-let* ((row (org-workflow-projects--row project date)))
    (unless (member (nth 6 row) '("done" "adjusted-done" "withdrawn" "cancelled"))
      (org-workflow-store--resolve row "withdrawn")
      (org-workflow-store--event (car row) "project-paused"))))

(defun org-workflow-projects--row-blocked-p (project row)
  "Whether ROW's frozen leaf is inside a closed execution branch of PROJECT."
  (org-with-point-at (org-workflow-projects-marker project)
    (let ((task (nth 1 row)) blocked)
      (org-map-entries
       (lambda ()
         (when (equal task (org-entry-get nil "ID"))
           (setq blocked (org-workflow-target--execution-blocked-p)))) nil 'tree)
      blocked)))

(defun org-workflow-projects--scheduled-first (date)
  "Return the first unfinished leaf explicitly scheduled on DATE in this project."
  (let (candidate)
    (org-map-entries
     (lambda ()
       (when (and (not candidate)
                  (org-workflow-target--unfinished-leaf-p)
                  (not (org-workflow-projects-kind))
                  (not (org-workflow-projects-stage-p))
                  (not (org-workflow-target--execution-blocked-p))
                  (equal date (org-workflow-target--timestamp-date (org-entry-get nil "SCHEDULED"))))
         (setq candidate (org-workflow-projects--location)))) nil 'tree)
    candidate))

(defun org-workflow-projects--ensure-day (project date)
  "Create or resume PROJECT's single frozen responsibility on DATE."
  (let ((row (org-workflow-projects--row project date)))
    (if row
        (if (org-workflow-projects--row-blocked-p project row)
            (org-workflow-projects--withdraw project date)
          ;; Explicit task withdrawal is not automatically reversed.
          (when (and (equal (nth 6 row) "withdrawn")
                   (equal (caar (sqlite-select (org-workflow-store--db)
                                              "SELECT kind FROM events WHERE id=? ORDER BY seq DESC LIMIT 1"
                                              (list (car row)))) "project-paused"))
          (org-workflow-store--resolve row "pending")))
      ;; Resolve the project by ID again: an earlier project may have inserted
      ;; properties and moved un-ID'd leaf positions in this same buffer.
      (org-with-point-at (org-workflow-projects-marker project)
        (when-let* ((next (org-workflow-projects--scheduled-first date)))
          (org-with-point-at (org-workflow-projects-marker next)
            (let* ((task (org-entry-get nil "ID"))
                   (existing (and task (car (sqlite-select
                                            (org-workflow-store--db)
                                            "SELECT id,task_id,created_at,due,original_title,title,status,adjusted FROM commitments WHERE task_id=? AND due=? AND status!='cancelled' ORDER BY rowid DESC LIMIT 1"
                                            (list task date)))))
                   (id (if existing (car existing) (org-workflow-store-create date))))
              ;; Retire old carry-forward prospectively, retaining historical
              ;; dates/statuses and settled snapshots without retroactive success.
              (when task
                (dolist (old (sqlite-select
                             (org-workflow-store--db)
                             "SELECT id,task_id,created_at,due,original_title,title,status,adjusted FROM commitments WHERE task_id=? AND due<?"
                             (list task date)))
                  (unless (or (org-workflow-projects-row-p old)
                              (org-workflow-projects-superseded-p old date))
                    (org-workflow-store--event (car old) "project-superseded"
                                              (list :date date :project (plist-get project :id))))))
              ;; Adopt existing responsibilities rather than doubling the task.
              (when existing (org-workflow-store--attach existing))
              (unless (org-workflow-projects-row-p (org-workflow-store-commitment id))
                (org-workflow-store--event id "project-daily" (list :project (plist-get project :id))))
              ;; 日期/项目索引是当天决定；完成、改期和撤回后都保留它。
              (org-workflow-store-set-meta (org-workflow-projects--day-key (plist-get project :id) date) id))))))))

(defun org-workflow-projects--identify (projects)
  "Give PROJECTS stable IDs inside the caller's source/facts transaction."
  (let ((markers (mapcar #'org-workflow-projects-marker projects)))
    (cl-mapc (lambda (project marker)
               (org-with-point-at marker
                 (setf (plist-get project :id) (org-id-get-create))))
             projects markers)))

(defun org-workflow-projects-sync (&rest _)
  "Synchronize due starts and today's project responsibilities.
Never generate obligations for days when Workflow was not running."
  (interactive)
  (when (and org-workflow-store-enabled (not org-workflow-projects--syncing))
    (let* ((org-workflow-projects--syncing t)
           (today (org-workflow-target--today-string))
           (items (org-workflow-projects-collect))
           (projects (seq-filter (lambda (x) (equal (plist-get x :kind) "project")) items))
           (paused (mapcar (lambda (x) (plist-get x :id))
                           (seq-filter (lambda (x) (and (equal (plist-get x :kind) "goal")
                                                        (plist-get x :paused))) items))))
      (when projects
        (org-workflow-store--operation
         (lambda ()
           (org-workflow-projects--identify projects)
           (dolist (project projects)
             (let ((state (plist-get project :state)) (start (plist-get project :start)))
               (when (and (not (plist-get project :blocked))
                          (equal state "TODO") start (not (string< today start))
                          (not (equal start (plist-get project :deferred-start)))
                          (not (member (plist-get project :goal-id) paused)))
                 (org-with-point-at (org-workflow-projects-marker project)
                   (let (org-log-done org-todo-log-states) (org-todo "DIVE")))
                 (setq state "DIVE"))
               (if (and (not (plist-get project :blocked))
                        (equal state "DIVE") (not (member (plist-get project :goal-id) paused)))
                   (org-workflow-projects--ensure-day project today)
                 (org-workflow-projects--withdraw project today))))))))))

(defun org-workflow-projects--catch-up (&rest _)
  "Run project synchronization only for profiles using the new daily contract."
  (when (org-workflow-store-meta "completion-floor-since")
    (org-workflow-projects-sync)))

(defun org-workflow-projects-set-state (marker state)
  "Set project or stage MARKER to STATE and reconcile today's responsibility."
  (unless (member state '("TODO" "DIVE" "HOLD" "DONE")) (user-error "无效项目状态"))
  (org-with-point-at marker
    (unless (or (equal (org-workflow-projects-kind) "project")
                (org-workflow-projects-stage-p)) (user-error "请选择项目或阶段"))
    (org-workflow-store--operation
     (lambda ()
       (unless org-workflow-projects--batch (org-entry-delete nil "WORKFLOW_PAUSE_OWNER"))
       (let (org-log-done org-todo-log-states) (org-todo state))
       (org-workflow-projects-sync)))))

(defun org-workflow-projects-set-start (marker date)
  "Set project MARKER's start DATE without scheduling its entire subtree."
  (org-with-point-at marker
    (unless (equal (org-workflow-projects-kind) "project") (user-error "请选择一级 TODO 项目"))
    (unless (equal (org-get-todo-state) "TODO") (user-error "只有 TODO 项目需要计划开始日期"))
    (org-workflow-store--operation
     (lambda () (org-schedule (when (null date) '(4)) date)
       (org-workflow-projects-sync)))))

(defun org-workflow-projects-goal-state (marker pause)
  "PAUSE MARKER's file goal, or restore only projects owned by its pause batch."
  (org-with-point-at marker
    (unless (org-workflow-projects--agenda-file-p) (user-error "请选择 Agenda 目标文件"))
    (org-workflow-store--operation
     (lambda ()
       (let* ((org-workflow-projects--batch t)
              (org-workflow-projects--syncing t)
              (id (org-workflow-projects--file-goal-id))
              (token (org-workflow-projects--goal-pause id))
              (projects (seq-filter (lambda (x) (and (equal (plist-get x :kind) "project")
                                                    (equal (plist-get x :goal-id) id)))
                                    (org-workflow-projects-collect))))
         (org-workflow-projects--identify projects)
         (if pause
             (progn
               (unless token
                 (setq token (org-id-new))
                 (org-workflow-store-set-meta (concat "goal-paused:" id) token))
               (dolist (project projects)
                 (when (equal (plist-get project :state) "DIVE")
                   (org-with-point-at (org-workflow-projects-marker project)
                     (org-entry-put nil "WORKFLOW_PAUSE_OWNER" token)
                     (org-workflow-projects-set-state (point-marker) "HOLD")))))
           (when token
             (sqlite-execute (org-workflow-store--db) "DELETE FROM meta WHERE key=?"
                             (list (concat "goal-paused:" id)))
             (dolist (project projects)
               (when (and (equal (plist-get project :state) "TODO")
                          (plist-get project :start)
                          (not (string< (org-workflow-target--today-string) (plist-get project :start))))
                 (org-with-point-at (org-workflow-projects-marker project)
                   (org-entry-put nil "WORKFLOW_START_DEFERRED" (plist-get project :start))))
               (when (equal token (plist-get project :pause-owner))
                 (org-with-point-at (org-workflow-projects-marker project)
                   (org-entry-delete nil "WORKFLOW_PAUSE_OWNER")
                   (when (equal (org-get-todo-state) "HOLD")
                     (org-workflow-projects-set-state (point-marker) "DIVE"))))))))
       (org-workflow-projects-sync)))))

(defun org-workflow-projects--state-change ()
  "Reconcile relevant ancestor, project and leaf edits in the outer transaction."
  (when (and org-workflow-store-enabled (not org-workflow-projects--syncing)
             (org-workflow-projects-root))
    (when (and (equal (org-workflow-projects-kind) "project")
               (not org-workflow-projects--batch))
      (org-entry-delete nil "WORKFLOW_PAUSE_OWNER")
      ;; Explicitly returning to TODO overrides an already elapsed start date.
      (when (equal (org-get-todo-state) "TODO")
        (when-let* ((date (org-workflow-target--timestamp-date (org-entry-get nil "SCHEDULED")))
                    ((not (string< (org-workflow-target--today-string) date))))
          (org-entry-put nil "WORKFLOW_START_DEFERRED" date))))
    (org-workflow-projects-sync)))

(defun org-workflow-projects--after-refile ()
  "Invalidate pause ownership when a project is structurally reassigned."
  (when (and org-workflow-store-enabled (derived-mode-p 'org-mode))
    (org-workflow-store--operation
     (lambda ()
       (org-map-entries (lambda () (org-entry-delete nil "WORKFLOW_PAUSE_OWNER")) nil 'tree)))))

(defun org-workflow-projects--enable ()
  "Install lifecycle-owned project hooks."
  (org-workflow--add-hook 'org-after-refile-insert-hook #'org-workflow-projects--after-refile)
  (org-workflow--add-hook 'org-after-todo-state-change-hook #'org-workflow-projects--state-change 80)
  (org-workflow--advice-add 'org-workflow-history-catch-up :after #'org-workflow-projects--catch-up))

(provide 'org-workflow-projects)
;;; org-workflow-projects.el ends here
