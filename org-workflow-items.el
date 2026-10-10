;;; org-workflow-items.el --- Shared task and habit items -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Jinwang Dong
;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Commentary:
;; One source model and current-item interface for tasks and repeated habits.
;; Ordinary planning admission and habit occurrence policies remain distinct.
;;; Code:
(require 'org-workflow-lifecycle)
(require 'org-clock)
(require 'org-id)

(declare-function org-workflow-target--direct-parent-marker "org-workflow-core" ())
(declare-function org-workflow-target--entry-title "org-workflow-core" ())
(declare-function org-workflow--effective-priority-at-point "org-workflow-core" ())
(declare-function org-workflow-target--timestamp-date "org-workflow-core" (timestamp))
(declare-function org-workflow-target--scheduled-minute "org-workflow-core" (scheduled))
(declare-function org-workflow-target--today-string "org-workflow-core" ())
(declare-function org-workflow-target--ordinary-marker "org-workflow-core" ())
(declare-function org-workflow-target-refresh "org-workflow-core" (&optional signal-errors))
(declare-function org-workflow-target--reveal "org-workflow-core" (marker focused-frame-p))
(declare-function org-workflow-clock--clock-start "org-workflow-core" (marker))
(declare-function org-workflow-clock--clock-stop "org-workflow-core" ())
(declare-function org-workflow-clock--clock-matches-p "org-workflow-core" (marker))
(declare-function org-workflow-focus-timer-active-p "org-workflow-focus-timer" ())
(declare-function org-workflow-habits-check-completion "org-workflow-habits" ())
(declare-function org-workflow-habits-after-complete "org-workflow-habits" ())
(declare-function org-workflow-habits-current-item "org-workflow-habits" ())
(declare-function org-workflow-habits-skip-item "org-workflow-habits" (item))
(declare-function org-workflow-panel-invalidate "org-workflow-panel" (&rest ignored))
(declare-function org-workflow--request-gnome-refresh "org-workflow-core" ())
(declare-function org-workflow-journal-direct-clock-minutes "org-workflow-journal" (marker start end))
(defvar org-workflow-focus-timer-task-marker)
(defvar org-workflow-executing-marker)
(defvar org-workflow-current-item-cache nil
  "Last resolved item for lightweight consumers such as the mode line.")

(cl-defstruct (org-workflow-target-entry
               (:constructor org-workflow-target-entry-create))
  marker group-marker priority scheduled-date scheduled-minute title group-title
  file outline-position (kind 'task) id occurrence-date habit-position reminder-time done)

(defun org-workflow-item-at-marker (marker &optional date)
  "Read MARKER as a task or habit item, with habit occurrence DATE.
This bounded source read bypasses the Org element cache and never creates IDs."
  (unless (and (markerp marker) (marker-buffer marker))
    (user-error "当前项源文件已不可用"))
  (let ((org-element-use-cache nil))
    (org-with-point-at marker
      (org-back-to-heading t)
      (let* ((habit (equal (org-entry-get nil "STYLE") "habit"))
             (parent (org-workflow-target--direct-parent-marker))
             (scheduled (org-entry-get nil "SCHEDULED")))
        (org-workflow-target-entry-create
         :marker (copy-marker (point)) :group-marker parent
         :kind (if habit 'habit 'task) :id (org-entry-get nil "ID")
         :occurrence-date (and habit (or date (org-workflow-target--today-string)))
         :priority (org-workflow--effective-priority-at-point)
         :scheduled-date (org-workflow-target--timestamp-date scheduled)
         :scheduled-minute (org-workflow-target--scheduled-minute scheduled)
         :title (org-workflow-target--entry-title)
         :group-title (when parent (org-with-point-at parent (org-get-heading t t t t)))
         :file (buffer-file-name) :outline-position (point))))))

(defun org-workflow-item-key (item)
  "Return ITEM's source ID or a stable presentation-only source key."
  (or (org-workflow-target-entry-id item)
      (secure-hash 'sha256 (format "%s:%s" (org-workflow-target-entry-file item)
                                   (org-workflow-target-entry-title item)))))

(defun org-workflow-current-item ()
  "Return the one current item shared by UI, commands and source navigation."
  (let* ((org-element-use-cache nil)
         (ordinary (org-workflow-target--ordinary-marker))
         (active (org-workflow-focus-timer-active-p))
         (timer-marker (and active org-workflow-focus-timer-task-marker))
         (clock-marker (and (org-clocking-p) org-clock-marker)))
    (setq org-workflow-current-item-cache
          (cond
           ((and timer-marker (marker-buffer timer-marker))
            (org-workflow-item-at-marker timer-marker))
           ((and clock-marker
                 (or (org-with-point-at clock-marker (equal (org-entry-get nil "STYLE") "habit"))
                     (and ordinary (equal clock-marker ordinary))))
            (org-workflow-item-at-marker clock-marker))
           ((or active clock-marker) (and ordinary (org-workflow-item-at-marker ordinary)))
           (t (or (org-workflow-habits-current-item)
                  (and ordinary (org-workflow-item-at-marker ordinary))))))))

(defun org-workflow-item-supports-p (item action)
  "Whether ITEM supports ACTION without changing its domain semantics."
  (or (memq action '(visit start toggle complete stop cancel note save))
      (if (eq (org-workflow-target-entry-kind item) 'habit)
          (eq action 'skip)
        (memq action '(step prerequisite defer defer-group commitment)))))

(defun org-workflow-item-require (&optional action)
  "Refresh and require the current item, checking optional ACTION support."
  (org-workflow-target-refresh t)
  (let ((item (or (org-workflow-current-item) (user-error "没有当前任务或习惯"))))
    (when (and action (not (org-workflow-item-supports-p item action)))
      (user-error "当前习惯不支持此任务规划操作"))
    item))

(defun org-workflow-item-changed ()
  "Refresh common current-item consumers after a source or occurrence change."
  (org-workflow-panel-invalidate)
  (org-workflow-target-refresh t)
  (org-workflow--request-gnome-refresh))

(defun org-workflow-item-save (item)
  "Save ITEM's native source using its existing synchronization hooks."
  (org-with-point-at (org-workflow-target-entry-marker item) (save-buffer)))

(defun org-workflow-item-start (item)
  "Start the shared clock backend on ITEM without replacing an active clock."
  (let ((marker (org-workflow-target-entry-marker item)))
    (when (or (org-clocking-p) (org-workflow-focus-timer-active-p))
      (user-error "请先结束当前计时"))
    (org-workflow-clock--clock-start marker)
    (when (eq (org-workflow-target-entry-kind item) 'task)
      (setq org-workflow-executing-marker (copy-marker marker)))
    (org-workflow-item-changed)))

(defun org-workflow-item-complete (item)
  "Complete ITEM, recording only this occurrence for a repeated habit."
  (let ((marker (org-workflow-target-entry-marker item))
        (habit (eq (org-workflow-target-entry-kind item) 'habit))
        (org-element-use-cache nil))
    (when habit
      (org-with-point-at marker (org-workflow-habits-check-completion)))
    (when (and (org-clocking-p) (not (org-workflow-clock--clock-matches-p marker)))
      (user-error "另一项正在计时"))
    (when (org-workflow-clock--clock-matches-p marker) (org-workflow-clock--clock-stop))
    (org-with-point-at marker
      (if habit
          (let ((org-log-repeat 'time) (org-log-into-drawer t))
            (org-todo "DONE")
            (when org-log-note-marker (org-add-log-note))
            (org-workflow-habits-after-complete))
        (org-todo "DONE")))
    ;; Habits already save native repeat logs immediately; ordinary edits retain
    ;; their established unsaved-buffer/recovery policy.
    (when habit (org-workflow-item-save item))
    (org-workflow-item-changed)))

(defun org-workflow-item-skip (item)
  "Skip ITEM's current habit occurrence without marking it completed."
  (unless (org-workflow-item-supports-p item 'skip)
    (user-error "当前项不支持跳过习惯提醒"))
  (org-workflow-habits-skip-item item)
  (org-workflow-item-changed))

(defun org-workflow-item-skip-current ()
  "Skip today's occurrence of the shared current habit item."
  (interactive)
  (org-workflow-item-skip (org-workflow-item-require 'skip)))

(defun org-workflow-item-visit (item &optional focused-frame-p)
  "Reveal ITEM's source subtree, optionally alone in FOCUSED-FRAME-P."
  (let ((org-element-use-cache nil))
    (org-workflow-target--reveal (org-workflow-target-entry-marker item) focused-frame-p)
    (org-narrow-to-subtree)
    (org-end-of-meta-data t)))

(defun org-workflow-item-body (item)
  "Read ITEM's direct body without metadata or nested headings."
  (let ((org-element-use-cache nil))
    (org-with-point-at (org-workflow-target-entry-marker item)
      (org-back-to-heading t)
      (save-restriction
        (org-narrow-to-subtree)
        (org-end-of-meta-data t)
        (let* ((beg (point))
               (end (save-excursion (if (outline-next-heading) (line-beginning-position) (point-max))))
               (text (buffer-substring-no-properties beg end)))
          (string-trim (replace-regexp-in-string "^[ \t]*CLOCK:.*\n?" "" text)))))))

(defun org-workflow-item-day-record (item date)
  "Read ITEM's direct effort and completion facts for DATE through one pipeline."
  (let* ((marker (org-workflow-target-entry-marker item))
         (start (org-time-string-to-time (concat date " 00:00")))
         (parts (decode-time start))
         (end (encode-time 0 0 0 (1+ (nth 3 parts)) (nth 4 parts) (nth 5 parts)))
         (org-element-use-cache nil)
         (minutes (org-workflow-journal-direct-clock-minutes marker start end))
         completions)
    (org-with-point-at marker
      (if (eq (org-workflow-target-entry-kind item) 'habit)
          (save-restriction
            (narrow-to-region (point) (save-excursion (if (outline-next-heading) (point) (point-max))))
            (while (re-search-forward "^[ \t]*- State \"DONE\".*?\\[\\([0-9-]+[^]\n]*\\)\\]" nil t)
              (let ((stamp (match-string-no-properties 1)))
                (when (string-prefix-p date stamp) (push stamp completions)))))
        (when (and (equal (org-get-todo-state) "DONE")
                   (equal date (org-workflow-target--timestamp-date (org-entry-get nil "CLOSED"))))
          (push (org-entry-get nil "CLOSED") completions))))
    (when (or completions (> minutes 0))
      (list :id (org-workflow-target-entry-id item) :task (org-workflow-target-entry-title item)
            :outcome (if completions "done" "focused") :focusMinutes minutes
            :completedAt (vconcat (nreverse completions))))))

(provide 'org-workflow-items)
;;; org-workflow-items.el ends here
