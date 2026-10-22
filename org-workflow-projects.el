;;; org-workflow-projects.el --- Explicit learning projects -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Jinwang Dong
;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Commentary:
;; Project boundaries are explicit; ordinary DIVE chapter groups remain groups.
;; Reads return source locations.  Mutations share the Org/facts transaction.
;;; Code:
(require 'org-workflow-core)
(require 'org-workflow-store)
(require 'org-workflow-sources)

(defvar org-workflow-projects--syncing nil)
(defvar org-workflow-projects--batch nil)
(declare-function org-workflow-history--row-state "org-workflow-history" (row date))

(defun org-workflow-projects-kind ()
  "Return the explicit kind of the heading at point, without inheritance."
  (org-entry-get nil "WORKFLOW_KIND"))

(defun org-workflow-projects-root ()
  "Return the nearest explicit project marker, preserving point and restriction."
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
     (unless (and (org-at-heading-p)
                  (if (plist-get item :id)
                      (equal (plist-get item :id) (org-entry-get nil "ID"))
                    (equal (plist-get item :title) (org-get-heading t t t t))))
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
  "Read explicit cross-file goal link, or the enclosing goal's ID."
  (or (org-entry-get nil "WORKFLOW_GOAL_ID")
      (save-excursion
        (catch 'goal
          (while (org-up-heading-safe)
            (when (equal (org-workflow-projects-kind) "goal")
              (throw 'goal (org-entry-get nil "ID"))))))))

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
  "Read explicit goals and projects without modifying or saving their sources."
  (let (items)
    (dolist (file (org-agenda-files t))
      (org-workflow-source-read
       file
       (lambda ()
         (when (org-workflow--file-kind)
           (org-map-entries
            (lambda ()
              (when (member (org-workflow-projects-kind) '("goal" "project"))
                (let* ((kind (org-workflow-projects-kind))
                       (next (and (equal kind "project") (org-workflow-projects--next))))
                  (push (append (org-workflow-projects--location)
                                (list :kind kind :state (org-get-todo-state)
                                      :goal-id (org-workflow-projects--goal-id)
                                      :blocked (org-workflow-projects--blocked-p)
                                      :paused (org-entry-get nil "WORKFLOW_PAUSED")
                                      :pause-owner (org-entry-get nil "WORKFLOW_PAUSE_OWNER")
                                      :deferred-start (org-entry-get nil "WORKFLOW_START_DEFERRED")
                                      :start (org-workflow-target--timestamp-date (org-entry-get nil "SCHEDULED"))
                                      :phase (plist-get next :phase) :next next)) items))))
            nil 'file)))))
    (nreverse items)))

(defun org-workflow-projects-read-goal (&optional optional)
  "Choose an existing goal ID; OPTIONAL allows leaving a project unassigned."
  (let ((choices
         (mapcar (lambda (x) (cons (format "%s — %s" (plist-get x :title)
                                          (file-name-nondirectory (plist-get x :file)))
                                  (plist-get x :id)))
                 (seq-filter (lambda (x) (and (equal (plist-get x :kind) "goal")
                                              (plist-get x :id)))
                             (org-workflow-projects-collect)))))
    (when optional (push '("暂不归属" . nil) choices))
    (unless choices (user-error "请先登记一个长期目标"))
    (cdr (assoc (completing-read "长期目标：" choices nil t) choices))))

(defun org-workflow-projects-set-goal (marker goal-id)
  "Assign project MARKER to GOAL-ID across Org files without moving its text."
  (let ((goal (seq-find (lambda (x) (and (equal (plist-get x :kind) "goal")
                                        (equal (plist-get x :id) goal-id)))
                        (org-workflow-projects-collect))))
    (unless goal (user-error "长期目标不存在，请刷新视图"))
    (org-with-point-at marker
      (unless (equal (org-workflow-projects-kind) "project") (user-error "请选择项目"))
      (org-workflow-store--operation
       (lambda ()
         (org-entry-put nil "WORKFLOW_GOAL_ID" goal-id)
         (org-entry-delete nil "WORKFLOW_PAUSE_OWNER")
         (when (and (plist-get goal :paused) (equal (org-get-todo-state) "DIVE"))
           (let (org-log-done org-todo-log-states) (org-todo "HOLD")))
         (org-workflow-projects-sync))))))

;;;###autoload
(defun org-workflow-projects-register (kind &optional goal-id)
  "Register this heading as KIND (goal or project), optionally linked to GOAL-ID."
  (interactive
   (list (cdr (assoc (completing-read "登记为：" '("长期目标" "项目") nil t)
                     '(("长期目标" . "goal") ("项目" . "project"))))))
  (unless (and (member kind '("goal" "project"))
               (derived-mode-p 'org-mode) buffer-file-name
               (org-workflow--file-kind)
               (member (file-truename buffer-file-name)
                       (mapcar #'file-truename (org-agenda-files t))))
    (user-error "请在 Agenda 的 project/area 文件标题上登记"))
  (org-back-to-heading t)
  (when (and (called-interactively-p 'interactive) (equal kind "project")
             (not goal-id) (not (org-workflow-projects--goal-id)))
    (setq goal-id (org-workflow-projects-read-goal t)))
  (org-workflow-store--operation
   (lambda ()
     (org-id-get-create)
     (org-entry-put nil "WORKFLOW_KIND" kind)
     (when goal-id (org-entry-put nil "WORKFLOW_GOAL_ID" goal-id))
     (when (and (equal kind "project") (not (member (org-get-todo-state) '("TODO" "DIVE" "HOLD" "DONE"))))
       (org-todo "TODO"))
     (org-workflow-projects-sync)))
  (message "已登记 %s；源文件保留为待保存状态" kind))

(defun org-workflow-projects-row-p (row)
  "Whether commitment ROW is a daily project responsibility."
  (and row (caar (sqlite-select (org-workflow-store--db)
                               "SELECT 1 FROM events WHERE id=? AND kind='project-daily' LIMIT 1"
                               (list (car row))))))

(defun org-workflow-projects-superseded-p (row date)
  "Whether ROW stopped carrying forward into project duties by DATE."
  (seq-some
   (lambda (event)
     (let ((since (plist-get (org-workflow-store--decode (car event)) :date)))
       (and since (not (string< date since)))))
   (sqlite-select (org-workflow-store--db)
                  "SELECT payload FROM events WHERE id=? AND kind='project-superseded'"
                  (list (car row)))))

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

(defun org-workflow-projects--ensure-day (project date)
  "Create or resume PROJECT's single frozen responsibility on DATE."
  (let ((row (org-workflow-projects--row project date)))
    (if row
        ;; Explicit task withdrawal is not automatically reversed.
        (when (and (equal (nth 6 row) "withdrawn")
                   (equal (caar (sqlite-select (org-workflow-store--db)
                                              "SELECT kind FROM events WHERE id=? ORDER BY seq DESC LIMIT 1"
                                              (list (car row)))) "project-paused"))
          (org-workflow-store--resolve row "pending"))
      ;; Resolve the project by ID again: an earlier project may have inserted
      ;; properties and moved un-ID'd leaf positions in this same buffer.
      (org-with-point-at (org-workflow-projects-marker project)
        (when-let* ((next (org-workflow-projects--next)))
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
              (org-workflow-store-set-meta (org-workflow-projects--day-key (plist-get project :id) date) id)
              (unless (org-entry-get nil "SCHEDULED")
                (org-add-planning-info 'scheduled (org-read-date nil t date))))))))))

(defun org-workflow-projects-sync (&rest _)
  "Synchronize due starts and today's project responsibilities.
Never generate obligations for days when Workflow was not running."
  (interactive)
  (when (and org-workflow-store-enabled (not org-workflow-projects--syncing))
    (let* ((org-workflow-projects--syncing t)
           (today (org-workflow-target--today-string))
           (items (org-workflow-projects-collect))
           (projects (seq-filter (lambda (x) (and (equal (plist-get x :kind) "project")
                                                  (plist-get x :id))) items))
           (paused (mapcar (lambda (x) (plist-get x :id))
                           (seq-filter (lambda (x) (and (equal (plist-get x :kind) "goal")
                                                        (plist-get x :paused))) items))))
      (when projects
        (org-workflow-store--operation
         (lambda ()
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
  "Set explicit project MARKER to STATE and reconcile today's responsibility."
  (unless (member state '("TODO" "DIVE" "HOLD" "DONE")) (user-error "无效项目状态"))
  (org-with-point-at marker
    (unless (equal (org-workflow-projects-kind) "project") (user-error "请选择已登记的项目"))
    (org-workflow-store--operation
     (lambda ()
       (unless org-workflow-projects--batch (org-entry-delete nil "WORKFLOW_PAUSE_OWNER"))
       (let (org-log-done org-todo-log-states) (org-todo state))
       (org-workflow-projects-sync)))))

(defun org-workflow-projects-set-start (marker date)
  "Set project MARKER's start DATE without scheduling its entire subtree."
  (org-with-point-at marker
    (unless (equal (org-workflow-projects-kind) "project") (user-error "请选择已登记的项目"))
    (unless (equal (org-get-todo-state) "TODO") (user-error "只有 TODO 项目需要计划开始日期"))
    (org-workflow-store--operation
     (lambda () (org-schedule (when (null date) '(4)) date)
       (org-workflow-projects-sync)))))

(defun org-workflow-projects-goal-state (marker pause)
  "PAUSE goal MARKER, or resume only projects still owned by its pause batch."
  (org-with-point-at marker
    (unless (equal (org-workflow-projects-kind) "goal") (user-error "请选择已登记的长期目标"))
    (org-workflow-store--operation
     (lambda ()
       (let* ((org-workflow-projects--batch t)
              (org-workflow-projects--syncing t)
              (id (org-entry-get nil "ID"))
              (token (org-entry-get nil "WORKFLOW_PAUSED"))
              (projects (seq-filter (lambda (x) (and (equal (plist-get x :kind) "project")
                                                    (equal (plist-get x :goal-id) id)))
                                    (org-workflow-projects-collect))))
         (if pause
             (progn
               (unless token (setq token (org-id-new)) (org-entry-put nil "WORKFLOW_PAUSED" token))
               (dolist (project projects)
                 (when (equal (plist-get project :state) "DIVE")
                   (org-with-point-at (org-workflow-projects-marker project)
                     (org-entry-put nil "WORKFLOW_PAUSE_OWNER" token)
                     (org-workflow-projects-set-state (point-marker) "HOLD")))))
           (when token
             (org-entry-delete nil "WORKFLOW_PAUSED")
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
             (or (org-workflow-projects-root)
                 (save-excursion
                   (org-back-to-heading t)
                   (re-search-forward ":WORKFLOW_KIND: +project"
                                      (save-excursion (org-end-of-subtree t t)) t))))
    (when (and (equal (org-workflow-projects-kind) "project")
               (not org-workflow-projects--batch))
      (org-entry-delete nil "WORKFLOW_PAUSE_OWNER")
      ;; Explicitly returning to TODO overrides an already elapsed start date.
      (when (equal (org-get-todo-state) "TODO")
        (when-let* ((date (org-workflow-target--timestamp-date (org-entry-get nil "SCHEDULED")))
                    ((not (string< (org-workflow-target--today-string) date))))
          (org-entry-put nil "WORKFLOW_START_DEFERRED" date))))
    (org-workflow-projects-sync)))

(defun org-workflow-projects--enable ()
  "Install lifecycle-owned project hooks."
  (org-workflow--add-hook 'org-after-todo-state-change-hook #'org-workflow-projects--state-change 80)
  (org-workflow--advice-add 'org-workflow-history-catch-up :after #'org-workflow-projects--catch-up))

(provide 'org-workflow-projects)
;;; org-workflow-projects.el ends here
