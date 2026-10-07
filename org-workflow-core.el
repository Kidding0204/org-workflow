;;; org-workflow-core.el --- org-workflow Workflow component -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Jinwang Dong
;; Author: Jinwang Dong <dongjinwang040204@gmail.com>
;; Assisted-by: Codex:GPT-6
;; SPDX-License-Identifier: GPL-3.0-or-later
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;; Commentary:
;; A component of org-workflow.  Activation is coordinated by its global mode.
;;; Code:
(require 'org-workflow-lifecycle)
;;; org-workflow-core.el --- Org current target workflow -*- lexical-binding: t; -*-

;;; Code:

(require 'cl-lib)

(require 'json)

(require 'seq)

(require 'subr-x)

(require 'org)

(require 'org-clock)

(require 'org-capture)

(require 'org-id)

(require 'org-workflow-commands)

(defcustom org-workflow-clock 'org-clock
  "Clock backend used by current-target workflow commands."
  :type '(choice (const :tag "Org Clock" org-clock)
                 (const :tag "Focus Timer" org-workflow-focus-timer))
  :group 'org)

(defvaralias 'org-workflow-curr-lookahead-threshold 'org-workflow-dive-lookahead-threshold)

(defcustom org-workflow-dive-lookahead-threshold 2
  "Open the next sibling when a DIVE group has at most this many open leaves.
Only groups below level one participate; top-level milestones remain manual.
Only direct task children count.  Nil disables automatic lookahead."
  :type '(choice (const :tag "Disabled" nil) (integer :tag "Remaining leaves"))
  :group 'org)

(defvar org-workflow--advancing-curr nil)

(defvar org-workflow--normalizing nil)

(defvar org-workflow-status-provider-function nil
  "Optional function returning journal-owned status fields for a date.")

(defvar org-workflow-commitment-streak-provider-function nil
  "Optional function returning a Journal-owned streak for DATE and DAILY.")

(defvar org-workflow-current-changed-hook nil
  "Hook run after the derived current workflow leaf changes.")

(defvar org-workflow-stack-empty-hook nil
  "Hook run when an actionable workflow stack becomes empty.")

(defconst org-workflow-external-actions
  '((start . org-workflow-target-start)
    (toggle . org-workflow-focus-toggle)
    (select . org-workflow-target-select)
    (step . org-workflow--step-in-frame)
    (prerequisite . org-workflow-target-prerequisite)
    (defer . org-workflow-target-defer)
    (defer-group . org-workflow-target-defer-group)
    (complete . org-workflow-target-complete)
    (rest . org-workflow-target-rest)
    (continue . org-workflow-target-continue)
    (cancel . org-workflow-target-cancel)
    (visit . org-workflow--visit-in-frame)
    (agenda . org-workflow-open-agenda)
    (week . org-workflow-week-open))
  "Allowed desktop ACTION to interactive Org Workflow command mappings.")

(defconst org-workflow-gnome-sync-object-path
  "/io/github/meph1st0/OrgWorkflow")

(defconst org-workflow-gnome-sync-interface
  "io.github.meph1st0.OrgWorkflow")

(defun org-workflow--request-gnome-refresh ()
  "Ask GNOME to reread workflow JSON without carrying state in the signal."
  (when (fboundp 'dbus-send-signal)
    (condition-case nil
        (dbus-send-signal :session nil
                          org-workflow-gnome-sync-object-path
                          org-workflow-gnome-sync-interface
                          "Changed")
      (error nil))))

(defun org-workflow--notify (title body)
  "Notify with TITLE and BODY, falling back to the echo area."
  (condition-case nil
      (if (require 'notifications nil t)
          (notifications-notify :title title
                                :body body
                                :app-name "Emacs Org Workflow")
        (message "%s: %s" title body))
    (error (message "%s: %s" title body))))

(defun org-workflow-dispatch (action)
  "Invoke an allowed desktop ACTION interactively and report its outcome.

Errors become desktop notifications so GNOME shortcuts do not fail silently."
  (condition-case error-data
      (let ((command (alist-get action org-workflow-external-actions)))
        (unless command
          (user-error "Unknown Org Workflow action: %s" action))
        (call-interactively command)
        (list :ok t :action action))
    (error
     (let ((reason (error-message-string error-data)))
       (org-workflow--notify "Org Workflow" reason)
       (list :ok nil :action action :error reason)))))

(defun org-workflow--dispatch-in-frame (frame action)
  "Select live FRAME, then dispatch desktop ACTION interactively."
  (when (frame-live-p frame)
    (select-frame-set-input-focus frame))
  (org-workflow-dispatch action))

(defun org-workflow-dispatch-in-frame (action)
  "Queue desktop ACTION for the selected frame and return immediately.

This releases the current server request before an interactive command enters
the minibuffer, so other clients such as the GNOME status reader stay usable."
  (unless (alist-get action org-workflow-external-actions)
    (user-error "Unknown Org Workflow action: %s" action))
  (run-at-time 0.1 nil #'org-workflow--dispatch-in-frame
               (selected-frame) action)
  (list :queued t :action action))

(cl-defstruct (org-workflow-target-entry
               (:constructor org-workflow-target-entry-create))
  marker group-marker priority scheduled-date scheduled-minute title group-title
  file outline-position)

(defun org-workflow-target--today-string ()
  "Return today's local date in ISO format."
  (format-time-string "%Y-%m-%d"))

(defun org-workflow-target--scheduled-minute (scheduled)
  "Return SCHEDULED's minute of day, or nil when it has no time."
  (when (and scheduled
             (string-match "[[:space:]]\\([0-9][0-9]\\):\\([0-9][0-9]\\)" scheduled))
    (+ (* 60 (string-to-number (match-string 1 scheduled)))
       (string-to-number (match-string 2 scheduled)))))

(defun org-workflow-target--entry-title ()
  "Return the current heading's plain task title."
  (substring-no-properties (org-link-heading-search-string) 1))

(defun org-workflow-target--timestamp-date (timestamp)
  "Return the ISO date embedded in TIMESTAMP, or nil."
  (when (and timestamp
             (string-match "[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}" timestamp))
    (match-string-no-properties 0 timestamp)))

(defun org-workflow--date-on-or-before-p (left right)
  "Return non-nil when ISO date LEFT is no later than RIGHT."
  (and left right (or (equal left right) (string< left right))))

(defun org-workflow--scheduled-on-or-before-p (date &optional marker)
  "Return non-nil when MARKER has a direct schedule no later than DATE."
  (org-with-point-at (or marker (point-marker))
    (org-workflow--date-on-or-before-p
     (org-workflow-target--timestamp-date (org-entry-get nil "SCHEDULED"))
     date)))

(defun org-workflow-target--ancestor-marker-at-level (level)
  "Return a marker for the current heading's ancestor at LEVEL."
  (save-excursion
    (org-back-to-heading t)
    (while (and (> (org-outline-level) level)
                (org-up-heading-safe)))
    (when (= (org-outline-level) level)
      (copy-marker (point)))))

(defun org-workflow-target--unfinished-p ()
  "Return non-nil when the current heading has an unfinished TODO state."
  (member (org-get-todo-state) org-not-done-keywords))

(defun org-workflow-target--task-leaf-p ()
  "Return non-nil when the current TODO has no TODO descendants."
  (and (org-get-todo-state)
       (not (equal (org-entry-get nil "STYLE") "habit"))
       (save-excursion
         (let ((end (save-excursion (org-end-of-subtree t t))))
           (forward-line 1)
           (not (catch 'task
                  (while (re-search-forward org-heading-regexp end t)
                    (when (org-get-todo-state)
                      (throw 'task t)))))))))

(defun org-workflow-target--unfinished-leaf-p ()
  "Return non-nil when the current heading is an unfinished task leaf."
  (and (org-workflow-target--unfinished-p)
       (org-workflow-target--task-leaf-p)))

(defun org-workflow-target--direct-parent-marker ()
  "Return a marker for the current heading's direct parent, or nil."
  (save-excursion
    (org-back-to-heading t)
    (when (org-up-heading-safe)
      (copy-marker (point)))))

(defun org-workflow--dive-child-p ()
  "Return non-nil when the current heading's direct parent is DIVE.
DIVE is not inherited through intermediate headings or by a leaf itself."
  (save-excursion
    (org-back-to-heading t)
    (and (org-up-heading-safe)
         (equal (org-get-todo-state) "DIVE"))))

(defun org-workflow--explicit-priority-at-point ()
  "Return the current heading's own priority character, or nil."
  (org-element-property :priority (org-element-at-point)))

(defun org-workflow--effective-priority-at-point ()
  "Return numeric priority at point, inheriting the nearest explicit ancestor."
  (let ((priority
         (save-excursion
           (org-back-to-heading t)
           (or (org-workflow--explicit-priority-at-point)
               (catch 'priority
                 (while (org-up-heading-safe)
                   (when-let* ((ancestor-priority
                               (org-workflow--explicit-priority-at-point)))
                     (throw 'priority ancestor-priority)))
                 org-default-priority)))))
    (org-get-priority (format "[#%c]" priority))))

(defun org-workflow--held-p (&optional marker)
  "Return non-nil when MARKER is at or below a HOLD task."
  (org-with-point-at (or marker (point-marker))
    (org-back-to-heading t)
    (catch 'held
      (while t
        (when (equal (org-get-todo-state) "HOLD")
          (throw 'held t))
        (unless (org-up-heading-safe)
          (throw 'held nil))))))

(defun org-workflow-agenda-skip-held ()
  "Skip the current Agenda match when it is inside a HOLD subtree."
  (when (org-workflow--held-p)
    (save-excursion
      (org-end-of-subtree t t)
      (point))))

(defun org-workflow-target--eligible-leaf-p (kind _date)
  "Return non-nil when the current leaf belongs to KIND and is not held."
  (and kind
       (not (equal (org-entry-get nil "STYLE") "habit"))
       (>= (org-outline-level) 2)
       (not (org-workflow--held-p))))

(defun org-workflow--file-kind ()
  "Return the workflow kind declared by the current Org file."
  (cond
   ((member "project" org-file-tags) 'project)
   ((member "area" org-file-tags) 'area)))

(defun org-workflow--eligible-heading-p (kind _date)
  "Return non-nil when KIND identifies a heading eligible for schedule transfer."
  (and kind
       (not (equal (org-entry-get nil "STYLE") "habit"))
       (>= (org-outline-level) 1)
       (not (org-workflow--held-p))))

(defun org-workflow--ensure-statistics-cookie ()
  "Add a count statistics cookie to the current TODO heading when absent."
  (unless (string-match-p "\\[[0-9]+/[0-9]+\\]" (org-get-heading))
    (org-edit-headline
     (concat (org-get-heading t t t t) " [0/0]"))))

(defun org-workflow--unfinished-leaf-markers-in-subtree ()
  "Return unfinished leaf markers under the current heading."
  (let (leaves)
    (save-restriction
      (org-narrow-to-subtree)
      (org-map-entries
       (lambda ()
         (when (and (org-workflow-target--unfinished-leaf-p)
                    (not (org-workflow--held-p)))
           (push (copy-marker (point)) leaves)))
       nil 'tree))
    (nreverse leaves)))

(defun org-workflow--add-schedule (timestamp)
  "Set the current heading's schedule from exact TIMESTAMP data."
  (org-add-planning-info 'scheduled timestamp))

(defun org-workflow-normalize-heading (&optional marker)
  "Move MARKER's direct schedule to unfinished leaves when it is a container."
  (org-with-point-at (or marker (point-marker))
    (org-back-to-heading t)
    (let* ((scheduled (org-entry-get nil "SCHEDULED"))
           (date (org-workflow-target--timestamp-date scheduled))
           (kind (org-workflow--file-kind))
           (priority (org-workflow--explicit-priority-at-point)))
      (when (and scheduled date kind
                 (not (org-workflow--held-p))
                 (org-workflow--eligible-heading-p kind date))
        (let ((leaves (org-workflow--unfinished-leaf-markers-in-subtree)))
          (atomic-change-group
            (unless (and (= (length leaves) 1)
                         (org-workflow-target--same-marker-p (car leaves)
                                                       (point-marker)))
              (save-restriction
                (org-narrow-to-subtree)
                (org-map-entries
                 (lambda ()
                   (when (and (org-workflow-target--unfinished-p)
                              (not (org-workflow--held-p))
                              (not (org-workflow-target--unfinished-leaf-p)))
                     (org-workflow--ensure-statistics-cookie)))
                 nil 'tree))
              (dolist (leaf leaves)
                (org-with-point-at leaf
                  (org-workflow--add-schedule scheduled)
                  (when (and priority
                             (not (org-workflow--explicit-priority-at-point)))
                    (let ((org-workflow--normalizing t))
                      (org-priority priority)))))
              (org-remove-timestamp-with-keyword org-scheduled-string)))
          (org-workflow--request-gnome-refresh)
          leaves)))))

(defun org-workflow--normalize-discovered-containers ()
  "Normalize scheduled eligible containers found in agenda files."
  (unless org-workflow--normalizing
    (let ((org-workflow--normalizing t))
      (dolist (file (org-agenda-files t))
        (when (file-readable-p file)
          (with-current-buffer (find-file-noselect file)
            (org-with-wide-buffer
             (when-let* ((kind (org-workflow--file-kind)))
               (let (containers)
                 (org-map-entries
                  (lambda ()
                    (when-let* ((scheduled (org-entry-get nil "SCHEDULED"))
                                (date (org-workflow-target--timestamp-date scheduled)))
                      (when (and (org-workflow-target--unfinished-p)
                                 (not (org-workflow--held-p))
                                 (not (org-workflow-target--unfinished-leaf-p))
                                 (org-workflow--eligible-heading-p kind date))
                        (push (copy-marker (point)) containers))))
                  nil 'file)
                 (dolist (container (nreverse containers))
                   (org-workflow-normalize-heading container)))))))))))

(defun org-workflow--normalize-current-buffer-before-save ()
  "Normalize scheduled containers in the current scoped agenda buffer."
  (when (and (derived-mode-p 'org-mode)
             buffer-file-name
             (member (file-truename buffer-file-name)
                     (mapcar #'file-truename (org-agenda-files t)))
             (not org-workflow--normalizing))
    (let ((org-workflow--normalizing t))
      (org-with-wide-buffer
       (when-let* ((kind (org-workflow--file-kind)))
         (let (containers)
           (org-map-entries
            (lambda ()
              (when-let* ((scheduled (org-entry-get nil "SCHEDULED"))
                          (date (org-workflow-target--timestamp-date scheduled)))
                (when (and (org-workflow-target--unfinished-p)
                           (not (org-workflow--held-p))
                           (not (org-workflow-target--unfinished-leaf-p))
                           (org-workflow--eligible-heading-p kind date))
                  (push (copy-marker (point)) containers))))
            nil 'file)
           (dolist (container (nreverse containers))
             (org-workflow-normalize-heading container))))))))

(defun org-workflow--stage-priorities (&optional time)
  "Return priority characters visible in the stage containing TIME."
  (let ((hour (decoded-time-hour (decode-time (or time (current-time))))))
    (cond
     ((< hour 12) '(?A))
     ((< hour 18) '(?A ?B))
     (t '(?A ?B ?C)))))

(defun org-workflow--timestamp-on-date-p (timestamp date)
  "Return non-nil when TIMESTAMP carries exact ISO DATE."
  (equal date (org-workflow-target--timestamp-date timestamp)))

(defun org-workflow--ready-on-date-p (date &optional marker)
  "Return non-nil when MARKER entered READY on DATE."
  (org-with-point-at (or marker (point-marker))
    (and (equal (org-get-todo-state) "READY")
         (org-workflow--timestamp-on-date-p
          (org-entry-get nil "WORKFLOW_READY_ON") date))))

(defun org-workflow--held-on-date-p (date &optional marker)
  "Return non-nil when MARKER is under a HOLD closed on DATE."
  (org-with-point-at (or marker (point-marker))
    (org-back-to-heading t)
    (catch 'held
      (while t
        (when (and (equal (org-get-todo-state) "HOLD")
                   (org-workflow--timestamp-on-date-p
                    (org-entry-get nil "CLOSED") date))
          (throw 'held t))
        (unless (org-up-heading-safe) (throw 'held nil))))))

(defun org-workflow--outcome-on-date (date &optional marker)
  "Return MARKER's rolling-chain outcome on DATE, or nil."
  (org-with-point-at (or marker (point-marker))
    (let ((scheduled (org-workflow--scheduled-on-or-before-p date))
          (state (org-get-todo-state)))
      (cond
       ((and (not org-workflow-store-enabled) (org-workflow--ready-on-date-p date)) 'ready)
       ((and scheduled (equal state "DONE")
             (org-workflow--timestamp-on-date-p
              (org-entry-get nil "CLOSED") date))
        'done)
       ((and scheduled (not (org-workflow-habit-p))
             (fboundp 'org-workflow-history-attempted-p)
             (org-workflow-history-attempted-p date))
        'attempted)
       ((and scheduled (org-workflow--held-on-date-p date)) 'held)
       ((and scheduled (org-workflow-target--unfinished-leaf-p)
             (not (org-workflow--held-p)))
        'pending)))))

(defun org-workflow--promise-p (&optional marker local)
  "Return non-nil when MARKER has promise; use local tags when LOCAL."
  (org-with-point-at (or marker (point-marker))
    (if org-workflow-store-enabled
        (org-workflow-store-promise-p)
      (member "promise" (org-get-tags nil local)))))

(defun org-workflow--set-local-tag (tag present)
  "Make local TAG PRESENT or absent at point."
  (let ((tags (delete tag (copy-sequence (org-get-tags nil t)))))
    (org-set-tags (if present (cons tag tags) tags))))

(defun org-workflow--promise-progress (date)
  "Return live promise progress compatible with desktop JSON for DATE."
  (if org-workflow-store-enabled
      (org-workflow-history-progress date)
    (let ((satisfied 0) (total 0))
    (dolist (file (org-agenda-files t))
      (when (file-readable-p file)
        (with-current-buffer (find-file-noselect file)
          (org-with-wide-buffer
           (when (org-workflow--file-kind)
             (org-map-entries
              (lambda ()
                (when-let* ((outcome (and (>= (org-outline-level) 2)
                                         (org-workflow-target--task-leaf-p)
                                         (org-workflow--promise-p)
                                         (org-workflow--outcome-on-date date))))
                  (cl-incf total)
                  (when (memq outcome '(done ready held))
                    (cl-incf satisfied))))
              nil 'file))))))
    (list :minimumSatisfied satisfied
          :minimumTotal total
          :phase (if (and (> total 0) (= satisfied total))
                     "optional" "minimum")
          :commitmentComplete
          (if (and (> total 0) (= satisfied total)) t :false)))))

(defun org-workflow--direct-child-markers (parent)
  "Return direct child heading markers of PARENT in outline order."
  (org-with-point-at parent
    (org-back-to-heading t)
    (let ((child-level (1+ (org-outline-level)))
          (end (save-excursion (org-end-of-subtree t t)))
          children)
      (forward-line 1)
      (while (re-search-forward org-heading-regexp end t)
        (when (= (org-outline-level) child-level)
          (push (copy-marker (line-beginning-position)) children)))
      (nreverse children))))

(defun org-workflow--direct-clock-records ()
  "Return direct CLOCK lines on the heading at point.

Each result is (BEGIN END TEXT).  Only the direct entry content is scanned:
CLOCK records belonging to descendants are deliberately excluded."
  (org-back-to-heading t)
  (let ((subtree-end (save-excursion (org-end-of-subtree t t)))
        direct-end records)
    (save-excursion
      (forward-line 1)
      (setq direct-end
            (or (save-excursion
                  (when (re-search-forward org-heading-regexp subtree-end t)
                    (line-beginning-position)))
                subtree-end))
      (while (< (point) direct-end)
        (when (looking-at "[ \\t]*CLOCK:")
          (let* ((beginning (line-beginning-position))
                 (line-end (line-end-position))
                 (ending (min (point-max) (1+ line-end))))
            (push (list beginning ending
                        (buffer-substring-no-properties beginning line-end))
                  records)))
        (forward-line 1)))
    (nreverse records)))

(defun org-workflow--remove-empty-direct-logbooks ()
  "Remove empty direct LOGBOOK drawers from the heading at point."
  (org-back-to-heading t)
  (let ((subtree-end (save-excursion (org-end-of-subtree t t)))
        direct-end)
    (save-excursion
      (forward-line 1)
      (setq direct-end
            (or (save-excursion
                  (when (re-search-forward org-heading-regexp subtree-end t)
                    (line-beginning-position)))
                subtree-end))
      (while (re-search-forward "^[ \\t]*:LOGBOOK:[ \\t]*$" direct-end t)
        (let ((drawer-start (line-beginning-position))
              (content-start (progn (forward-line 1) (point))))
          (when (re-search-forward "^[ \\t]*:END:[ \\t]*$" direct-end t)
            (let ((drawer-end (min (point-max) (1+ (line-end-position)))))
              (when (string-match-p "\\`[ \\t\\n\\r]*\\'"
                                    (buffer-substring-no-properties
                                     content-start (line-beginning-position)))
                (delete-region drawer-start drawer-end)
                (setq direct-end (- direct-end (- drawer-end drawer-start)))))))))))

(defun org-workflow--move-direct-clocks-to (clocks original replacement)
  "Move direct CLOCK records CLOCKS from ORIGINAL to REPLACEMENT's LOGBOOK.
Existing non-CLOCK logbook and state-history text remains on ORIGINAL.
REPLACEMENT is newly created by `org-workflow-target-step'."
  (when clocks
    ;; Delete from the end to keep every recorded source range valid.
    (dolist (clock (sort (copy-sequence clocks)
                         (lambda (left right) (> (car left) (car right)))))
      (delete-region (nth 0 clock) (nth 1 clock)))
    (org-with-point-at original
      (org-workflow--remove-empty-direct-logbooks))
    (org-with-point-at replacement
      (org-back-to-heading t)
      (org-end-of-meta-data t)
      (insert ":LOGBOOK:\n"
              (mapconcat (lambda (clock) (nth 2 clock)) clocks "\n")
              "\n:END:\n"))))

(defun org-workflow--nearest-local-promise-marker (marker)
  "Return the nearest local promise at or above MARKER."
  (org-with-point-at marker
    (org-back-to-heading t)
    (catch 'source
      (while t
        (when (org-workflow--promise-p (point-marker) t)
          (throw 'source (copy-marker (point))))
        (unless (org-up-heading-safe)
          (throw 'source nil))))))

(defun org-workflow--path-below (ancestor descendant)
  "Return child markers from ANCESTOR down to DESCENDANT."
  (let (path)
    (org-with-point-at descendant
      (org-back-to-heading t)
      (while (not (org-workflow-target--same-marker-p
                   (point-marker) ancestor))
        (push (copy-marker (point)) path)
        (unless (org-up-heading-safe)
          (error "Promise source is not an ancestor"))))
    path))

(defun org-workflow--push-promise-off-path (source original)
  "Remove SOURCE promise and preserve promise on siblings outside ORIGINAL's path."
  (let ((parent source))
    (org-with-point-at source
      (org-workflow--set-local-tag "promise" nil))
    (dolist (child (org-workflow--path-below source original))
      (dolist (sibling (org-workflow--direct-child-markers parent))
        (unless (org-workflow-target--same-marker-p sibling child)
          (org-with-point-at sibling
            (org-workflow--set-local-tag "promise" t))))
      (setq parent child))))

(defun org-workflow--transfer-promise-to (original replacement)
  "Transfer commitment scope from ORIGINAL to REPLACEMENT, retaining history."
  (if org-workflow-store-enabled
      (org-workflow-store-transfer original replacement)
    (progn
  (while (org-workflow--promise-p original)
    (let ((source (org-workflow--nearest-local-promise-marker original)))
      (unless source
        (error "Inherited promise has no local source"))
      (org-workflow--push-promise-off-path source original)))
  (org-with-point-at replacement
    (org-workflow--set-local-tag "promise" t)))))

(defun org-workflow--stage-progress (date &optional time)
  "Return attempted-or-done and total leaf counts for DATE's stage at TIME."
  (let ((priorities
         (mapcar (lambda (priority)
                   (org-get-priority (format "[#%c]" priority)))
                 (org-workflow--stage-priorities time)))
        (satisfied 0)
        (total 0))
    (dolist (file (org-agenda-files t))
      (when (file-readable-p file)
        (with-current-buffer (find-file-noselect file)
          (org-with-wide-buffer
           (when-let* ((kind (org-workflow--file-kind)))
             (org-map-entries
              (lambda ()
                (when (and (>= (org-outline-level) 2)
                           (org-workflow-target--task-leaf-p)
                           (memq (org-workflow--effective-priority-at-point)
                                 priorities))
                  (when-let* ((outcome (org-workflow--outcome-on-date date)))
                    (cl-incf total)
                    (when (or (memq outcome '(done attempted))
                              (and (memq outcome '(ready held))
                                   (not (and (fboundp 'org-workflow-history-attempt-enabled-p)
                                             (org-workflow-history-attempt-enabled-p date)))))
                      (cl-incf satisfied)))))
              nil 'file))))))
    (list :stageSatisfied satisfied :stageTotal total)))

(defun org-workflow-target--collect (&optional through-date)
  "Collect eligible unfinished leaves through THROUGH-DATE, defaulting to today."
  (let ((today (org-workflow-target--today-string))
        (agenda-files (org-agenda-files t))
        entries)
    (dolist (file (delete-dups
                  (append agenda-files
                          (when (fboundp 'org-workflow-collection-inbox--scheduled-files)
                            (org-workflow-collection-inbox--scheduled-files)))))
      (when (file-readable-p file)
        (with-current-buffer (find-file-noselect file)
          (org-with-wide-buffer
           (let ((kind (cond
                        ((member "project" org-file-tags) 'project)
                        ((member "area" org-file-tags) 'area))))
             (when kind
               (org-map-entries
                (lambda ()
                  (when (and (>= (org-outline-level) 2)
                             (or (member file agenda-files)
                                 (org-workflow-collection-inbox-entry-p))
                             (org-workflow-target--unfinished-leaf-p)
                             (org-workflow-target--eligible-leaf-p kind today)
                             (org-workflow--scheduled-on-or-before-p (or through-date today)))
                    (let* ((scheduled (org-entry-get nil "SCHEDULED"))
                           (scheduled-date
                            (org-workflow-target--timestamp-date scheduled))
                           (leaf (copy-marker (point)))
                           (group (org-workflow-target--direct-parent-marker)))
                        (push
                         (org-workflow-target-entry-create
                          :marker leaf
                          :group-marker group
                          :priority
                          (org-workflow--effective-priority-at-point)
                          :scheduled-date scheduled-date
                          :scheduled-minute
                          (org-workflow-target--scheduled-minute scheduled)
                          :title (org-workflow-target--entry-title)
                          :group-title
                          (org-with-point-at group
                            (org-get-heading t t t t))
                          :file (buffer-file-name)
                          :outline-position (marker-position leaf))
                         entries))))
                nil 'file)))))))
    entries))

(defun org-workflow-target--group-key (entry)
  "Return ENTRY's stable direct-parent and priority group key."
  (list (org-workflow-target-entry-file entry)
        (marker-position (org-workflow-target-entry-group-marker entry))
        (org-workflow-target-entry-priority entry)))

(defun org-workflow-target--group-minute (entries)
  "Return the earliest timed scheduled minute in ENTRIES, or nil."
  (when-let* ((minutes (delq nil (mapcar #'org-workflow-target-entry-scheduled-minute
                                        entries))))
    (apply #'min minutes)))

(defun org-workflow-target--group-date (entries)
  "Return the oldest scheduled date in ENTRIES."
  (car (sort (delq nil (mapcar #'org-workflow-target-entry-scheduled-date entries))
             #'string<)))

(defun org-workflow-target--group-less-p (left right)
  "Return non-nil when grouped entry alist LEFT sorts before RIGHT."
  (let* ((left-entries (cdr left))
         (right-entries (cdr right))
         (left-entry (car left-entries))
         (right-entry (car right-entries))
         (left-date (org-workflow-target--group-date left-entries))
         (right-date (org-workflow-target--group-date right-entries))
         (left-time (org-workflow-target--group-minute left-entries))
         (right-time (org-workflow-target--group-minute right-entries))
         (left-title (downcase (or (org-workflow-target-entry-group-title left-entry)
                                   (org-workflow-target-entry-title left-entry))))
         (right-title (downcase (or (org-workflow-target-entry-group-title right-entry)
                                    (org-workflow-target-entry-title right-entry)))))
    (cond
     ((/= (org-workflow-target-entry-priority left-entry)
          (org-workflow-target-entry-priority right-entry))
      (> (org-workflow-target-entry-priority left-entry)
         (org-workflow-target-entry-priority right-entry)))
     ((not (equal left-date right-date))
      (string< left-date right-date))
     ((not (equal left-time right-time))
      (or (and left-time (not right-time))
          (and left-time right-time (< left-time right-time))))
     ((not (string= left-title right-title))
      (string-lessp left-title right-title))
     ((not (string= (org-workflow-target-entry-file left-entry)
                    (org-workflow-target-entry-file right-entry)))
      (string-lessp (org-workflow-target-entry-file left-entry)
                    (org-workflow-target-entry-file right-entry)))
     (t (< (cadr (car left)) (cadr (car right)))))))

(defun org-workflow--order-scope (entry)
  "Return the effective planning day and period of ENTRY."
  (let* ((today (org-workflow-target--today-string))
         (date (org-workflow-target-entry-scheduled-date entry)))
    (format "%s/%d" (if (and date (string< today date)) date today)
            (org-workflow-target-entry-priority entry))))

(defun org-workflow--priority-character (value)
  "Return the Org priority character whose computed priority is VALUE."
  (or (seq-find (lambda (priority)
                  (= value (org-get-priority (format "[#%c]" priority))))
                (number-sequence org-priority-highest org-priority-lowest))
      (error "Unknown Workflow priority %s" value)))

(defun org-workflow--saved-order ()
  "Read the saved (PRIORITY . RANK) at point, including legacy properties."
  (let ((rank (org-entry-get nil "WORKFLOW_ORDER"))
        (scope (org-entry-get nil "WORKFLOW_ORDER_SCOPE")))
    (cond
     ((and rank (string-match "\\`\\([A-Z]\\)/\\([0-9]+\\)\\'" rank))
      (let ((priority (match-string 1 rank))
            (number (string-to-number (match-string 2 rank))))
        (cons (org-get-priority (format "[#%s]" priority)) number)))
     ((and rank (string-match-p "\\`[0-9]+\\'" rank)
           scope (string-match "/\\([0-9]+\\)\\'" scope))
      (cons (string-to-number (match-string 1 scope))
            (string-to-number rank))))))

(defun org-workflow--manual-rank (entry)
  "Return ENTRY's saved rank while its priority period still matches."
  (org-with-point-at (org-workflow-target-entry-marker entry)
    (when-let* ((order (org-workflow--saved-order))
                ((= (car order) (org-workflow-target-entry-priority entry))))
      (cdr order))))

(defun org-workflow--apply-manual-order (entries)
  "Reorder ENTRIES within same-day, same-period slots using retained ranks."
  (let ((groups (make-hash-table :test #'equal)))
    (dolist (entry entries)
      (push entry (gethash (org-workflow--order-scope entry) groups)))
    (maphash
     (lambda (scope items)
       (puthash scope
                (cl-stable-sort
                 (nreverse items)
                 (lambda (left right)
                   (let ((a (org-workflow--manual-rank left))
                         (b (org-workflow--manual-rank right)))
                     (and a (or (null b) (< a b))))))
                groups))
     groups)
    (mapcar (lambda (entry)
              (pop (gethash (org-workflow--order-scope entry) groups)))
            entries)))

(defun org-workflow-target--ordered-entries (&optional through-date)
  "Return entries through THROUGH-DATE, grouped then in outline order.
Without THROUGH-DATE, use today as the upper scheduling boundary."
  (org-workflow--apply-manual-order
   (mapcan
   (lambda (group)
     (sort (copy-sequence (cdr group))
           (lambda (left right)
             (< (or (org-workflow-target-entry-outline-position left)
                    (marker-position (org-workflow-target-entry-marker left)))
                (or (org-workflow-target-entry-outline-position right)
                    (marker-position (org-workflow-target-entry-marker right)))))))
   (sort (seq-group-by #'org-workflow-target--group-key
                       (if through-date (org-workflow-target--collect through-date)
                         (org-workflow-target--collect)))
         #'org-workflow-target--group-less-p))))

(defun org-workflow-target--entries-at-priorities (entries priorities)
  "Return ENTRIES whose effective priority belongs to PRIORITIES."
  (let ((values (mapcar (lambda (priority)
                          (org-get-priority (format "[#%c]" priority)))
                        priorities)))
    (seq-filter (lambda (entry)
                  (memq (org-workflow-target-entry-priority entry) values))
                entries)))

(defun org-workflow-target--expose-by-time (entries now)
  "Expose the fixed priority band from ordered ENTRIES at NOW."
  (let ((hour (decoded-time-hour (decode-time now))))
    (cond
     ((< hour 12)
      (or (org-workflow-target--entries-at-priorities entries '(?A))
          (org-workflow-target--entries-at-priorities entries '(?B))
          (org-workflow-target--entries-at-priorities entries '(?C))))
     ((< hour 18)
      (or (org-workflow-target--entries-at-priorities entries '(?A ?B))
          (org-workflow-target--entries-at-priorities entries '(?C))))
     (t entries))))

(defun org-workflow-target--sorted-entries ()
  "Return today's ordered entries exposed by the current priority band."
  (org-workflow-target--expose-by-time (org-workflow-target--ordered-entries)
                                 (current-time)))

(defvar org-workflow-target-stack nil "Cached sorted list of today's Org target entries.")

(defvar org-workflow-target-midnight-timer nil "Timer refreshing the target stack after midnight.")

(defcustom org-workflow-target-modeline-max-width 48 "Maximum target stack modeline width." :type 'integer :group 'org)

(defvar org-workflow-target-selected-marker nil
  "Manually selected target for this Emacs session.")

(defvar org-workflow-target-selected-date nil)

(defvar org-workflow-target-selection-history nil)

(defun org-workflow-target--entry-at-point ()
  "Describe the current heading for the target selector."
  (let ((parent (org-workflow-target--direct-parent-marker))
        (scheduled (org-entry-get nil "SCHEDULED")))
    (org-workflow-target-entry-create
     :marker (copy-marker (point)) :group-marker parent
     :priority (org-workflow--effective-priority-at-point)
     :scheduled-date (org-workflow-target--timestamp-date scheduled)
     :scheduled-minute (org-workflow-target--scheduled-minute scheduled)
     :title (org-workflow-target--entry-title)
     :group-title (when parent
                    (org-with-point-at parent (org-get-heading t t t t)))
     :file (buffer-file-name) :outline-position (point))))

(defun org-workflow-target--selection-entries ()
  "Return (SECTION . ENTRY) pairs, with today's queue before other DIVE children."
  (let* ((org-element-use-cache nil)
         (stack (org-workflow-target--ordered-entries))
         extra)
    (dolist (file (org-agenda-files t))
      (when (file-readable-p file)
        (with-current-buffer (find-file-noselect file)
          (org-with-wide-buffer
           (when-let* ((kind (org-workflow--file-kind)))
             (org-map-entries
              (lambda ()
                (when (and (org-workflow-target--unfinished-leaf-p)
                           (org-workflow-target--eligible-leaf-p kind nil)
                           (org-workflow--dive-child-p)
                           (not (seq-some
                                 (lambda (entry)
                                   (org-workflow-target--same-marker-p
                                    (point-marker) (org-workflow-target-entry-marker entry)))
                                 stack)))
                  (push (org-workflow-target--entry-at-point) extra)))
              nil 'file))))))
    (append (mapcar (lambda (entry) (cons "今日任务栈" entry)) stack)
            (mapcar (lambda (entry) (cons "栈外 DIVE" entry))
                    (cl-stable-sort (nreverse extra) #'>
                                    :key #'org-workflow-target-entry-priority)))))

(defun org-workflow-target--selected-entry ()
  "Return a fresh eligible manual target, clearing an expired selection."
  (or (when (and (markerp org-workflow-target-selected-marker)
                 (marker-buffer org-workflow-target-selected-marker)
                 (equal org-workflow-target-selected-date (org-workflow-target--today-string)))
        (org-with-point-at org-workflow-target-selected-marker
          (when (and (org-at-heading-p)
                     (org-workflow-target--unfinished-leaf-p)
                     (org-workflow-target--eligible-leaf-p (org-workflow--file-kind) nil)
                     (member (buffer-file-name) (org-agenda-files t))
                     (or (org-workflow--dive-child-p)
                         (org-workflow--scheduled-on-or-before-p
                          (org-workflow-target--today-string))))
            (org-workflow-target--entry-at-point))))
      (progn (setq org-workflow-target-selected-marker nil
                   org-workflow-target-selected-date nil)
             nil)))

(defun org-workflow-target-select ()
  "Choose today's current leaf from the queue or direct DIVE children.
Keep this session's choice until it becomes ineligible, changes TODO state,
is deferred, or the day changes.  Do not start timing automatically."
  (interactive)
  (let ((index 0) candidates groups)
    (dolist (pair (org-workflow-target--selection-entries))
      (let* ((entry (cdr pair))
             (marker (org-workflow-target-entry-marker entry)))
        (org-with-point-at marker
          (let* ((letter (cl-loop for c from org-priority-highest to org-priority-lowest
                                  when (= (org-workflow-target-entry-priority entry)
                                          (org-get-priority (format "[#%c]" c)))
                                  return c))
                 (context (string-join (delq nil (list (org-get-category)
                                                       (org-workflow-target-entry-group-title entry))) " · "))
                 (group (format "%s · %s" (car pair) context))
                 (label (string-trim-right
                         (format "%03d  %s  [%s #%c]  %s"
                                 (cl-incf index) (org-workflow-target-entry-title entry)
                                 (org-get-todo-state) (or letter ??)
                                 (string-join (org-get-tags) ":")))))
            (push (cons label marker) candidates)
            (push (cons label group) groups)))))
    (unless candidates (user-error "没有可选择的未完成任务"))
    (setq candidates (nreverse candidates))
    (let* ((table (lambda (string pred action)
                    (if (eq action 'metadata)
                        `(metadata
                          (category . org-workflow-task)
                          (display-sort-function . identity)
                          (cycle-sort-function . identity)
                          (group-function . ,(lambda (candidate transform)
                                               (if transform candidate
                                                 (cdr (assoc candidate groups))))))
                      (complete-with-action action candidates string pred))))
           (choice (completing-read "当前任务：" table nil t nil
                                    'org-workflow-target-selection-history))
           (marker (cdr (assoc choice candidates)))
           (old-marker org-workflow-target-selected-marker)
           (old-date org-workflow-target-selected-date))
      (setq org-workflow-target-selected-marker (copy-marker marker)
            org-workflow-target-selected-date (org-workflow-target--today-string))
      (condition-case err
          (progn
            (unless (org-workflow-target--selected-entry)
              (user-error "任务已不在可选范围，请重新选择"))
            (org-workflow--release-execution)
            (setq org-workflow-executing-marker (copy-marker marker))
            (org-workflow-target-refresh t))
        (error (setq org-workflow-target-selected-marker old-marker
                     org-workflow-target-selected-date old-date)
               (signal (car err) (cdr err))))
      (message "当前任务：%s" (org-with-point-at marker (org-workflow-target--entry-title))))))

(defun org-workflow--select-in-dedicated-frame (frame)
  "Read a target in FRAME, deleting it on success, error or quit."
  (when (frame-live-p frame)
    (unwind-protect
        (with-selected-frame frame
          (select-frame-set-input-focus frame)
          (let ((default-minibuffer-frame frame))
            (condition-case nil
                (org-workflow-dispatch 'select)
              (quit nil))))
      (when (frame-live-p frame)
        (delete-frame frame)))))

(defun org-workflow-select-in-new-frame ()
  "Queue task selection in a temporary minibuffer-only graphical frame."
  ;; The daemon's initial frame has no graphical terminal to inherit.
  (let ((frame (make-frame-on-display
                (or (and (featurep 'pgtk) (getenv "WAYLAND_DISPLAY"))
                    (getenv "DISPLAY")
                    (user-error "No graphical display is available"))
                '((name . "workflow-select")
                             (minibuffer . only)
                             (width . 100) (height . 18)
                             (menu-bar-lines . 0) (tool-bar-lines . 0)))))
    (run-at-time 0.1 nil #'org-workflow--select-in-dedicated-frame frame)
    (list :queued t :action 'select)))

(defun org-workflow-target--same-marker-p (left right)
  "Return non-nil when LEFT and RIGHT point to the same live location."
  (and (markerp left) (marker-buffer left) (markerp right) (marker-buffer right)
       (eq (marker-buffer left) (marker-buffer right))
       (= (marker-position left) (marker-position right))))

(defun org-workflow-clock--unsupported-clock ()
  "Signal an error for an unsupported `org-workflow-clock' value."
  (user-error "Unsupported Org workflow clock backend: %S" org-workflow-clock))

(defun org-workflow-clock--clock-start (marker)
  "Start the selected clock backend on MARKER."
  (pcase org-workflow-clock
    ('org-clock (org-with-point-at marker (org-clock-in)))
    ('org-workflow-focus-timer
     (require 'org-workflow-focus-timer)
     (org-workflow-focus-timer-start marker))
    (_ (org-workflow-clock--unsupported-clock))))

(defun org-workflow-clock--clock-stop ()
  "Stop the selected clock backend normally."
  (pcase org-workflow-clock
    ('org-clock (org-clock-out))
    ('org-workflow-focus-timer
     (require 'org-workflow-focus-timer)
     (org-workflow-focus-timer-stop))
    (_ (org-workflow-clock--unsupported-clock))))

(defun org-workflow-clock--clock-cancel ()
  "Cancel the current interval in the selected clock backend."
  (pcase org-workflow-clock
    ('org-clock (call-interactively #'org-clock-cancel))
    ('org-workflow-focus-timer
     (require 'org-workflow-focus-timer)
     (call-interactively #'org-workflow-focus-timer-cancel))
    (_ (org-workflow-clock--unsupported-clock))))

(defun org-workflow-clock--clock-continue ()
  "Resume a recent task using the selected clock backend."
  (pcase org-workflow-clock
    ('org-clock (call-interactively #'org-clock-in-last))
    ('org-workflow-focus-timer
     (require 'org-workflow-focus-timer)
     (call-interactively #'org-workflow-focus-timer-start-last))
    (_ (org-workflow-clock--unsupported-clock))))

(defun org-workflow-clock--clock-active-p ()
  "Return non-nil when the selected clock backend is active."
  (pcase org-workflow-clock
    ('org-clock (org-clock-is-active))
    ('org-workflow-focus-timer
     (require 'org-workflow-focus-timer)
     (org-workflow-focus-timer-active-p))
    (_ (org-workflow-clock--unsupported-clock))))

(defun org-workflow-clock--clock-matches-p (marker)
  "Return non-nil when the selected backend is active on MARKER."
  (pcase org-workflow-clock
    ('org-clock
     (and (org-clock-is-active)
          (org-workflow-target--same-marker-p org-clock-hd-marker marker)))
    ('org-workflow-focus-timer
     (require 'org-workflow-focus-timer)
     (and (org-workflow-focus-timer-active-p)
          (org-workflow-target--same-marker-p org-workflow-focus-timer-task-marker marker)))
    (_ (org-workflow-clock--unsupported-clock))))

(defun org-workflow-target--valid-entry-p (entry)
  "Return non-nil when ENTRY has a live marker."
  (let ((marker (org-workflow-target-entry-marker entry)))
    (and (markerp marker) (marker-buffer marker))))

(defvar org-workflow-executing-marker nil
  "Explicit execution target, independent of the recommendation queue.")

(defun org-workflow-target-current-marker ()
  "Return the execution target, or the first recommendation when idle."
  (if (and (markerp org-workflow-executing-marker)
           (marker-buffer org-workflow-executing-marker))
      (copy-marker org-workflow-executing-marker)
    (when-let* ((entry (car org-workflow-target-stack))
                ((org-workflow-target--valid-entry-p entry)))
      (copy-marker (org-workflow-target-entry-marker entry)))))

(defun org-workflow-target-next-marker ()
  "Return the first recommendation other than the current target."
  (let ((current (org-workflow-target-current-marker)))
    (when-let* ((entry (seq-find
                      (lambda (item)
                        (and (org-workflow-target--valid-entry-p item)
                             (not (org-workflow-target--same-marker-p
                                   current (org-workflow-target-entry-marker item)))))
                      org-workflow-target-stack)))
      (copy-marker (org-workflow-target-entry-marker entry)))))

(defun org-workflow--release-execution (&rest _)
  "End an explicit execution selection, stopping its clock if necessary."
  (when org-workflow-executing-marker
    (when (and (org-workflow-clock--clock-active-p)
               (org-workflow-clock--clock-matches-p org-workflow-executing-marker))
      (org-workflow-clock--clock-stop))
    (setq org-workflow-executing-marker nil)))

(defun org-workflow-target--progress (marker)
  "Return (DONE . TOTAL) for descendant TODO entries under MARKER."
  (org-with-point-at marker
    (org-back-to-heading t)
    (save-restriction
      (org-narrow-to-subtree)
      (let ((root (point))
            (done 0)
            (total 0))
        (org-map-entries
         (lambda ()
           (when (/= (point) root)
             (when-let* ((state (org-get-todo-state)))
             (cl-incf total)
             (when (member state org-done-keywords)
               (cl-incf done)))))
         nil 'tree)
        (cons done total)))))

(defun org-workflow-target--progress-suffix (progress)
  "Return a plain Org-like statistics suffix for PROGRESS."
  (format " [%d/%d]" (car progress) (cdr progress)))

(defun org-workflow-target--entry-label (entry)
  "Return ENTRY's title followed by its subtree progress."
  (let ((title (org-workflow-target-entry-title entry))
        (progress (org-workflow-target--progress
                   (org-workflow-target-entry-marker entry))))
    (if (zerop (cdr progress))
        title
      (concat title (org-workflow-target--progress-suffix progress)))))

(defun org-workflow-target-refresh (&optional signal-errors)
  "Refresh the target stack, propagating errors when SIGNAL-ERRORS is non-nil."
  ;; A refresh opens and scans several Org files while daemon startup is still
  ;; initializing their element caches.  Bypass the cache for this bounded
  ;; scan: a stale/incomplete cache can otherwise loop in `org-element--parse-to'.
  (let ((org-element-use-cache nil)
        (old-stack org-workflow-target-stack)
        (old-current (org-workflow-target-current-marker))
        (was-nonempty (seq-some #'org-workflow-target--valid-entry-p
                                org-workflow-target-stack)))
    (condition-case error-data
        (progn
          (setq org-workflow-target-stack (seq-filter #'org-workflow-target--valid-entry-p
                                                (org-workflow-target--sorted-entries)))
          (when-let* ((selected (org-workflow-target--selected-entry)))
            (setq org-workflow-target-stack
                  (cons selected
                        (seq-remove (lambda (entry)
                                      (org-workflow-target--same-marker-p
                                       (org-workflow-target-entry-marker entry)
                                       (org-workflow-target-entry-marker selected)))
                                    org-workflow-target-stack))))
          (let ((new-current (org-workflow-target-current-marker)))
            (unless (or (and (null old-current) (null new-current))
                        (org-workflow-target--same-marker-p old-current new-current))
              (run-hooks 'org-workflow-current-changed-hook))
            (when (and was-nonempty (not new-current))
              (run-hooks 'org-workflow-stack-empty-hook)))
          (force-mode-line-update t)
          org-workflow-target-stack)
      (error
       (setq org-workflow-target-stack (seq-filter #'org-workflow-target--valid-entry-p old-stack))
       (if signal-errors (signal (car error-data) (cdr error-data))
         (message "Org target stack refresh failed: %s" (error-message-string error-data)))
       org-workflow-target-stack))))

(defun org-workflow-target--refresh-after-change (&rest _)
  "Refresh the target stack after an Org change."
  (unless org-workflow--normalizing
    (org-workflow-target-refresh nil)))

(defun org-workflow--after-schedule (&rest _)
  "Normalize an Org schedule edit before refreshing the stack."
  (when (derived-mode-p 'org-mode)
    (org-workflow-normalize-heading))
  (org-workflow-target-refresh nil))

(defun org-workflow-target--refresh-after-agenda-save ()
  "Refresh after saving a file listed in `org-agenda-files'."
  (when (and buffer-file-name
             (member (file-truename buffer-file-name)
                     (mapcar #'file-truename (org-agenda-files t))))
    (let ((current (org-workflow-target-current-marker)))
      (org-workflow-target-refresh nil)
      (when (and current (eq (marker-buffer current) (current-buffer)))
        (org-workflow--request-gnome-refresh)))))

(defun org-workflow-target--schedule-midnight-refresh ()
  "Schedule a one-shot target refresh just after the next local midnight."
  (when (timerp org-workflow-target-midnight-timer) (cancel-timer org-workflow-target-midnight-timer))
  (let* ((tomorrow (decode-time (time-add (current-time) (days-to-time 1))))
         (next-midnight (encode-time 1 0 0 (decoded-time-day tomorrow)
                                     (decoded-time-month tomorrow)
                                     (decoded-time-year tomorrow))))
    (setq org-workflow-target-midnight-timer
          (run-at-time next-midnight nil
                       (lambda ()
                         (org-workflow-target-refresh nil)
                         (org-workflow-target--schedule-midnight-refresh))))))

(defun org-workflow-target--require-current ()
  "Refresh and return today's current target, or signal `user-error'."
  (org-workflow-target-refresh t)
  (or (org-workflow-target-current-marker)
      (user-error "No unfinished Org TODO is scheduled for today")))

(defun org-workflow-target--clock-matches-p (marker)
  "Return non-nil when the selected clock backend belongs to MARKER."
  (org-workflow-clock--clock-matches-p marker))

(defun org-workflow-target--reject-other-clock (marker)
  "Reject an active selected clock backend that does not belong to MARKER."
  (when (and (org-workflow-clock--clock-active-p)
             (not (org-workflow-target--clock-matches-p marker)))
    (user-error "Another Org entry is currently being timed")))

(defun org-workflow-target-start ()
  "Start timing today's current target."
  (interactive)
  (let ((marker (org-workflow-target--require-current)))
    (org-workflow-clock--clock-start marker)
    (setq org-workflow-executing-marker (copy-marker marker))))

(defun org-workflow-focus-toggle ()
  "Switch Focus Timer state for a desktop caller.

An inactive desktop call receives the current Workflow target explicitly;
active Focus and break phases need no Workflow target."
  (interactive)
  (require 'org-workflow-focus-timer)
  (let ((marker (unless (org-workflow-focus-timer-active-p) (org-workflow-target--require-current))))
    (org-workflow-focus-timer-toggle marker)
    (when marker (setq org-workflow-executing-marker (copy-marker marker)))))

(defun org-workflow-target-complete ()
  "Clock out and complete today's current target."
  (interactive)
  (let ((marker (org-workflow-target--require-current)))
    (org-workflow-target--reject-other-clock marker)
    (when (org-workflow-target--clock-matches-p marker)
      (org-workflow-clock--clock-stop))
    (org-with-point-at marker (org-todo "DONE"))
    (org-workflow-target-refresh t)))

(defun org-workflow--curr-scope-p ()
  "Return non-nil in a writable project/area file in the Agenda scope."
  (and (derived-mode-p 'org-mode) buffer-file-name
       (not buffer-read-only) (org-workflow--file-kind)
       (member (file-truename buffer-file-name)
               (mapcar #'file-truename (org-agenda-files t)))))

(defun org-workflow--curr-remaining ()
  "Return open direct task-child count, or nil when no direct task leaves exist."
  (let ((root (point)) (level (org-outline-level)) (remaining 0) has-tasks)
    (save-restriction
      (org-narrow-to-subtree)
      (org-map-entries
       (lambda ()
         (when (and (> (point) root) (= (org-outline-level) (1+ level))
                    (org-workflow-target--task-leaf-p))
           (setq has-tasks t)
           (when (and (org-workflow-target--unfinished-p)
                      (not (org-workflow--held-p)))
             (cl-incf remaining))))
       nil 'tree))
    (and has-tasks remaining)))

(defun org-workflow--advance-curr-at (marker)
  "Set MARKER's immediate next sibling to DIVE once its group is nearly done.
Level-one milestones never participate, including in explicit sync passes.
Return the newly opened sibling marker, or nil.  Preserve all existing tags."
  (when (and (integerp org-workflow-curr-lookahead-threshold)
             (>= org-workflow-curr-lookahead-threshold 0))
    (org-with-point-at marker
      (org-with-wide-buffer
       (org-back-to-heading t)
       (when (and (> (org-outline-level) 1)
                  (equal "DIVE" (org-get-todo-state))
                  (not (org-workflow--held-p)))
         (when-let* ((remaining (org-workflow--curr-remaining))
                     ((<= remaining org-workflow-curr-lookahead-threshold))
                     ((org-get-next-sibling))
                     ((not (org-workflow--held-p)))
                     ((not (org-entry-is-done-p)))
                     ((not (equal "DIVE" (org-get-todo-state))))
                     ;; Opening a leaf cannot expose any direct task children.
                     ((let ((count (org-workflow--curr-remaining)))
                        (and count (> count 0)))))
           (let (org-log-done org-todo-log-states)
             (org-todo "DIVE"))
           (copy-marker (point))))))))

(defun org-workflow--advance-curr-after-state-change ()
  "Open siblings of DIVE ancestors of the changed task, without chaining."
  (when (and org-workflow-curr-lookahead-threshold
             (not (equal (org-entry-get nil "STYLE") "habit"))
             (not org-workflow--advancing-curr)
             (not (equal org-state org-last-state))
             (member org-state '("DONE" "READY" "HOLD"))
             (org-workflow--curr-scope-p))
    (let ((org-workflow--advancing-curr t) roots)
      (org-with-wide-buffer
       (save-excursion
         (org-back-to-heading t)
         (when (equal "DIVE" (org-get-todo-state))
           (push (copy-marker (point)) roots))
         (while (org-up-heading-safe)
           (when (equal "DIVE" (org-get-todo-state))
             (push (copy-marker (point)) roots))))
       (dolist (root roots)
         (org-workflow--advance-curr-at root))))))

(defun org-workflow-sync-dive ()
  "Apply one DIVE lookahead pass to existing groups in scoped Agenda files.
Newly opened groups do not participate until another explicit sync or a task
state change inside them.  Modified Org buffers remain available for saving."
  (interactive)
  (let ((org-workflow--advancing-curr t) roots opened)
    (dolist (file (org-agenda-files t))
      (when (file-readable-p file)
        (with-current-buffer (find-file-noselect file)
          (when (org-workflow--curr-scope-p)
            (org-with-wide-buffer
             (org-map-entries
              (lambda ()
                (when (equal "DIVE" (org-get-todo-state))
                  (push (copy-marker (point)) roots)))
              nil 'file))))))
    (dolist (root (nreverse roots))
      (when-let* ((next (org-workflow--advance-curr-at root)))
        (push next opened)))
    (when (called-interactively-p 'interactive)
      (message "DIVE 已开放 %d 个相邻任务组" (length opened)))
    (nreverse opened)))

(defalias 'org-workflow-sync-curr #'org-workflow-sync-dive)

(defun org-workflow--after-todo-state-change ()
  "Release changed task selections, record legacy facts and refresh state."
  ;; Org runs this hook with point after the heading stars, whereas Workflow
  ;; markers identify the beginning of the heading.  Compare those anchors.
  (save-excursion
    (org-back-to-heading t)
    (when (org-workflow-target--same-marker-p (point-marker) org-workflow-executing-marker)
      (org-workflow--release-execution))
    (when (org-workflow-target--same-marker-p (point-marker) org-workflow-target-selected-marker)
      (setq org-workflow-target-selected-marker nil)))
  (when (and (not org-workflow-store-enabled) (equal org-last-state "TODO")
             (equal org-state "READY"))
    (let ((kind (org-workflow--file-kind))
          (today (org-workflow-target--today-string)))
      (when (and (org-workflow-target--task-leaf-p)
                 (org-workflow-target--eligible-leaf-p kind today)
                 (org-workflow--scheduled-on-or-before-p today))
        (org-entry-put nil "WORKFLOW_READY_ON"
                       (format-time-string "[%Y-%m-%d %a %H:%M]"
                                           (current-time)))
        (org-remove-timestamp-with-keyword org-scheduled-string)
        (org-workflow--request-gnome-refresh))))
  (org-workflow--advance-curr-after-state-change)
  (org-workflow-target--refresh-after-change))

(defun org-workflow-target-ready ()
  "Retired READY entry point; use a planning subtask instead."
  (interactive)
  (user-error "READY 已退役；请推进为一个规划子任务并完成它"))

(defun org-workflow-target--read-executed-part ()
  "Read the optional label for the current target's executed effort."
  (read-string "Executed Part: "))

(defun org-workflow-target--step (title marker)
  "Assign TITLE's existing effort to a TODO child below MARKER.

MARKER has already been revealed by interactive callers.  An empty TITLE is
an intentional no-op, so manual refinement can retain the parent facts."
  (let ((title (string-trim title)))
    ;; Reject malformed programmatic input before stopping an active clock.
    (when (string-match-p "[\r\n]" title)
      (user-error "Executed Part must be a single heading line"))
    (unless (string-empty-p title)
      (org-with-point-at marker
        (org-back-to-heading t)
        (let* ((original (copy-marker (point)))
               (scheduled (org-entry-get nil "SCHEDULED"))
               (priority (org-workflow--explicit-priority-at-point))
               (promised (org-workflow--promise-p original))
               (level (org-outline-level))
               (end (copy-marker (save-excursion (org-end-of-subtree t t)
                                                  (point)) t))
               replacement)
          ;; Validate the source before consulting or touching a live clock.
          (unless scheduled
            (user-error "Current workflow leaf has no direct schedule"))
          (let* ((clock-active (org-workflow-clock--clock-active-p))
                 (clock-matches
                  (and clock-active
                       (org-workflow-target--clock-matches-p original))))
            (when (and clock-active (not clock-matches))
              (user-error "Another Org entry is currently being timed"))
            (when clock-matches
              (org-workflow-clock--clock-stop)))
          ;; Clock-out can rewrite an open CLOCK line, so collect only now.
          (let ((clocks (org-with-point-at original
                          (org-workflow--direct-clock-records))))
            (atomic-change-group
              (goto-char end)
              (unless (bolp) (insert "\n"))
              (setq replacement (copy-marker (point)))
              (insert (make-string (1+ level) ?*) " TODO " title "\n")
              (org-with-point-at replacement
                (org-workflow--add-schedule scheduled)
                (when priority
                  (let ((org-workflow--normalizing t))
                    (org-priority priority))))
              (org-workflow--move-direct-clocks-to clocks original replacement)
              (org-with-point-at original
                (org-remove-timestamp-with-keyword org-scheduled-string))
              (when promised
                (org-workflow--transfer-promise-to original replacement))
              (org-with-point-at original
                (org-workflow--ensure-statistics-cookie)
                (org-update-statistics-cookies nil))
              ;; Keep the refinement legible without exposing its whole body.
              (goto-char original)
              (org-back-to-heading t)
              (org-fold-show-children))))
        (org-workflow--request-gnome-refresh)
        (org-workflow-target-refresh t)
        (org-with-point-at marker
          (org-back-to-heading t)
          (org-fold-show-children))))))

(defun org-workflow-target-step (title &optional marker)
  "Assign existing effort on the current target to TODO child TITLE.

Interactive calls reveal the task before prompting.  Programmatic callers may
pass MARKER after arranging their own UI, or omit it for a pure transformation."
  (interactive
   (let ((marker (org-workflow-target--require-current)))
     (org-workflow-target--reveal marker nil)
     (list (org-workflow-target--read-executed-part) marker)))
  (org-workflow-target--step title (or marker (org-workflow-target--require-current))))

(defun org-workflow-target-prerequisite (title)
  "Insert a scheduled same-level prerequisite named TITLE above current leaf."
  (interactive (list (read-string "Prerequisite: ")))
  (when (string-empty-p (string-trim title))
    (user-error "Prerequisite title cannot be empty"))
  (let ((marker (org-workflow-target--require-current)))
    (org-with-point-at marker
      (org-back-to-heading t)
      (let* ((scheduled (org-entry-get nil "SCHEDULED"))
             (priority (org-workflow--explicit-priority-at-point))
             (level (org-outline-level))
             (promised (org-workflow--promise-p))
             (original (copy-marker (point) t))
             (insert-at (point))
             replacement)
        (unless scheduled
          (user-error "Current workflow leaf has no direct schedule"))
        (atomic-change-group
          (goto-char insert-at)
          (insert (make-string level ?*) " TODO " (string-trim title) "\n")
          (goto-char insert-at)
          (setq replacement (copy-marker (point)))
          (org-workflow--add-schedule scheduled)
          (when priority
            (let ((org-workflow--normalizing t))
              (org-priority priority)))
          (when promised
            (org-workflow--transfer-promise-to original replacement))))
      (org-workflow--request-gnome-refresh))
    (org-workflow-target-refresh t)))

(defun org-workflow-target-rest ()
  "Stop timing the current target without completing it."
  (interactive)
  (if (not (org-workflow-clock--clock-active-p))
      (message "No active Org workflow clock")
    (let ((marker (org-workflow-target--require-current)))
      (org-workflow-target--reject-other-clock marker)
      (org-workflow-clock--clock-stop))))

(defun org-workflow-target-defer ()
  "Defer only the current atomic target by setting priority C."
  (interactive)
  (org-with-point-at (org-workflow-target--require-current)
    (let ((org-workflow--normalizing t))
      (org-priority ?C)))
  (org-workflow--release-execution)
  (setq org-workflow-target-selected-marker nil)
  (org-workflow-target-refresh t))

(defun org-workflow-target-defer-group ()
  "Defer today's unfinished leaves sharing the current target's parent."
  (interactive)
  (let ((today (org-workflow-target--today-string))
        (marker (org-workflow-target--require-current)))
    (org-with-point-at marker
      (let ((parent (org-workflow-target--direct-parent-marker)))
        (unless parent
          (user-error "Current workflow target has no parent task group"))
        (org-with-point-at parent
          (let ((parent-level (org-outline-level))
                (org-workflow--normalizing t))
            (atomic-change-group
              (save-restriction
                (org-narrow-to-subtree)
                (org-map-entries
                 (lambda ()
                   (when-let* ((scheduled (org-entry-get nil "SCHEDULED")))
                     (when (and (= (org-outline-level) (1+ parent-level))
                                (org-workflow-target--unfinished-leaf-p)
                                (string= today
                                         (org-workflow-target--timestamp-date scheduled)))
                       (org-priority ?C))))
                 nil 'tree)))))))
  (org-workflow--release-execution)
  (setq org-workflow-target-selected-marker nil)
  (org-workflow-target-refresh t)))

(defun org-workflow-target-continue () "Resume the most recently timed Org entry." (interactive) (org-workflow-clock--clock-continue))

(defun org-workflow-target-cancel () "Cancel the active timing interval." (interactive) (org-workflow-clock--clock-cancel))

(defun org-workflow-target-capture-location ()
  "Move point to today's current target for `org-capture'."
  (let ((marker (org-workflow-target--require-current)))
    (set-buffer (marker-buffer marker)) (goto-char marker) (org-back-to-heading t)))

(defun org-workflow-target--reveal (marker focused-frame-p)
  "Reveal MARKER's current workflow leaf.

When FOCUSED-FRAME-P is non-nil, make the source buffer the only window in
the selected frame, including removal of protected side windows."
  (if focused-frame-p
      (let ((buffer (marker-buffer marker)))
        (set-window-buffer (selected-window) buffer)
        (set-buffer buffer)
        (let ((ignore-window-parameters t))
          (delete-other-windows)))
    (pop-to-buffer (marker-buffer marker)))
  (widen)
  (goto-char marker)
  (org-back-to-heading t)
  (org-fold-show-context 'agenda))

(defun org-workflow-target--visit (focused-frame-p)
  "Reveal the current workflow leaf.

When FOCUSED-FRAME-P is non-nil, use the selected frame as its only window."
  (org-workflow-target--reveal (org-workflow-target--require-current) focused-frame-p))

(defun org-workflow-target-visit ()
  "Reveal and narrow to the current workflow leaf without changing the window layout.

Use `org-toggle-narrow-to-subtree' to return to the complete plan."
  (interactive)
  (org-workflow-target--visit nil)
  (org-toggle-narrow-to-subtree)
  (org-end-of-meta-data t))

(defun org-workflow--visit-current-target-in-new-frame ()
  "Show today's current target when a graphical frame becomes available.

Make the target the frame's only window.  Leave the frame's default buffer
alone when there is no current target."
  (when (and (display-graphic-p)
             (not (member (frame-parameter nil 'name)
                          '("capture" "workflow-select"))))
    (condition-case nil
        (progn
          (org-workflow-target-visit)
          (let ((ignore-window-parameters t))
            (delete-other-windows)))
      (user-error nil))))

(defun org-workflow--visit-in-frame ()
  "Reveal and narrow to the current workflow leaf as the frame's only window.

Place point at the start of the leaf's body."
  (interactive)
  (org-workflow-target--visit t)
  (org-toggle-narrow-to-subtree)
  (org-end-of-meta-data t))

(defun org-workflow--step-in-frame ()
  "Reveal the current target in this frame, then read its Executed Part."
  (interactive)
  (let ((marker (org-workflow-target--require-current)))
    (org-workflow-target--reveal marker t)
    (org-workflow-target--step (org-workflow-target--read-executed-part) marker)))

(defun org-workflow-target-modeline-text ()
  "Return cached current and next target names for modeline display."
  (let* ((entries (seq-take (seq-filter #'org-workflow-target--valid-entry-p org-workflow-target-stack) 2))
         (text (mapconcat #'org-workflow-target--entry-label entries " -> ")))
    (unless (string-empty-p text)
      (truncate-string-to-width text org-workflow-target-modeline-max-width nil nil "…"))))

(defun org-workflow--display-parent-data (marker)
  "Return (TITLE PROGRESS) for MARKER's display parent."
  (org-with-point-at marker
    (org-back-to-heading t)
    (let ((level (org-outline-level)) found)
      (cond
       ((= level 2)
        (when (org-up-heading-safe) (setq found t)))
       ((> level 2)
        (while (and (not found) (org-up-heading-safe))
          (when (org-get-todo-state) (setq found t)))))
      (when found
        (let* ((heading (org-get-heading t t t t))
               (progress (when (string-match "\\[\\([0-9]+/[0-9]+\\)\\]"
                                             heading)
                           (match-string-no-properties 1 heading)))
               (title (string-trim
                       (replace-regexp-in-string
                        "[[:space:]]*\\[[0-9]+/[0-9]+\\]" "" heading))))
          (list title progress))))))

(defun org-workflow--clean-body (marker)
  "Return MARKER's direct body without Org workflow metadata."
  (org-with-point-at marker
    (org-back-to-heading t)
    (save-restriction
      (org-narrow-to-subtree)
      (org-end-of-meta-data t)
      (let* ((beg (point))
             (end (save-excursion
                    (if (outline-next-heading) (line-beginning-position)
                      (point-max))))
             (text (buffer-substring-no-properties beg end)))
        (string-trim
         (replace-regexp-in-string "^[ \t]*CLOCK:.*\n?" "" text))))))

(defun org-workflow-status ()
  "Return a stable plist describing the current Org workflow state."
  (let* ((today (org-workflow-target--today-string))
         (marker (org-workflow-target-current-marker))
         (parent (and marker (org-workflow--display-parent-data marker)))
         (daily (or (and org-workflow-status-provider-function
                         (funcall org-workflow-status-provider-function
                                  today))
                    (org-workflow--promise-progress today)))
         (provided-streak
          (and org-workflow-commitment-streak-provider-function
               (funcall org-workflow-commitment-streak-provider-function
                        today daily)))
         (streak (if (and (integerp provided-streak)
                          (>= provided-streak 0))
                     provided-streak 0))
         (stage (org-workflow--stage-progress today)))
    (append
     (if marker
         (list :available t
               :task (org-with-point-at marker (org-workflow-target--entry-title))
               :parent (or (car parent) "")
               :parentProgress (or (cadr parent) "")
               :body (org-workflow--clean-body marker))
       (list :available :false :task "" :parent ""
             :parentProgress "" :body ""))
     daily
     (list :commitmentStreak streak)
     stage)))

(defun org-workflow-status-json ()
  "Return `org-workflow-status' as JSON for desktop consumers."
  (decode-coding-string (json-serialize (org-workflow-status)) 'utf-8))

(defun org-workflow-core--enable ()
  "Install this component while Workflow is being enabled."
  (add-to-list 'org-capture-templates
             '("c" "Note -> Current target" plain
               (function org-workflow-target-capture-location)
               "- [ ] %?\n  %a" :empty-lines 1))
  (org-workflow--add-hook 'emacs-startup-hook
          #'org-workflow--visit-current-target-in-new-frame)
  (org-workflow--add-hook 'server-after-make-frame-hook
          #'org-workflow--visit-current-target-in-new-frame)
  (org-workflow--add-hook 'org-after-todo-state-change-hook
          #'org-workflow--after-todo-state-change)
  (org-workflow--add-hook 'org-workflow-current-changed-hook
          #'org-workflow--request-gnome-refresh)
  (org-workflow--advice-add 'org-priority :after #'org-workflow-target--refresh-after-change)
  (org-workflow--advice-add 'org-schedule :after #'org-workflow--after-schedule)
  (org-workflow--add-hook 'org-mode-hook #'org-workflow--org-buffer-setup)
  (org-workflow-commands-setup)
  (org-workflow-target-refresh nil)
  (org-workflow-target--schedule-midnight-refresh)
  (org-workflow--global-set-key "C-c o t" #'org-workflow-target-select)
  (org-workflow--global-set-key "C-c o e" #'org-workflow-target-complete)
  (org-workflow--global-set-key "C-c o w" #'org-workflow-target-step)
  (org-workflow--global-set-key "C-c o b" #'org-workflow-target-prerequisite)
  (org-workflow--global-set-key "C-c o v" #'org-workflow-target-visit)
  (org-workflow--global-set-key "C-c o d" #'org-workflow-target-defer)
  (org-workflow--global-set-key "C-c o D" #'org-workflow-target-defer-group))

(provide 'org-workflow-core)
;;; org-workflow-core.el ends here
