;;; org-workflow-agenda-plan-undo.el --- note-gtd-plan-undo Workflow component -*- lexical-binding: t; -*-
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

(declare-function org-workflow-collection-inbox--review-files "org-workflow-agenda-inbox" ())
(declare-function org-workflow-projects-root "org-workflow-projects" ())
;;; org-workflow-agenda-plan-undo.el --- One-step planning correction -*- lexical-binding: t; -*-
(require 'org-workflow-store)
(require 'org-workflow-agenda-layout)
(autoload 'org-workflow-project-classify-undo "org-workflow-project-classify")

(defvar org-workflow-agenda-last-plan nil "Last successful planning operation in this session.")

(defconst org-workflow-agenda-plan-undo--fields
  ;; 挂接的三个属性作为整体恢复；不把后来正文／CLOCK 纳入撤销镜像。
  '("SCHEDULED" "PRIORITY" "WORKFLOW_COMMITMENT_ID"
    "WORKFLOW_COMMITTED_AT" "WORKFLOW_COMMITTED_FOR"))

(defun org-workflow-agenda-plan-undo--entry (marker)
  "Return MARKER's heading, TODO state, planning fields and existing ID."
  (org-with-point-at marker
    (list (org-get-heading t t t t) (org-get-todo-state)
          (mapcar (lambda (field) (cons field (if (equal field "PRIORITY")
                                         (when-let* ((priority (nth 3 (org-heading-components))))
                                           (char-to-string priority))
                                       (org-entry-get nil field))))
                  org-workflow-agenda-plan-undo--fields)
          (org-entry-get nil "ID"))))

(defun org-workflow-agenda-plan-undo--markers (selected)
  "Read SELECTED and attached tasks that a project replacement may detach."
  (let ((markers (mapcar #'copy-marker selected)))
    (dolist (project (delete-dups
                      (delq nil (mapcar (lambda (marker)
                                          (org-with-point-at marker (org-workflow-projects-root))) selected))))
      (org-with-point-at project
        (org-map-entries
         (lambda ()
           (when (seq-some (lambda (field) (org-entry-get nil field))
                           '("WORKFLOW_COMMITMENT_ID" "WORKFLOW_COMMITTED_AT" "WORKFLOW_COMMITTED_FOR"))
             (push (point-marker) markers))) nil 'tree)))
    (delete-dups markers)))

(defun org-workflow-agenda-plan-undo--project-days ()
  "Read the project-day decisions that explicit planning can replace."
  (sqlite-select (org-workflow-store--db)
                 "SELECT key,value FROM meta WHERE key LIKE 'project-day:%' ORDER BY key"))

(defun org-workflow-agenda-plan-undo--facts ()
  "Return current commitment rows in identifier order."
  (sqlite-select (org-workflow-store--db) "SELECT * FROM commitments ORDER BY id"))

(defun org-workflow-agenda-plan-undo--events (id)
  "Return event sequence numbers belonging to commitment ID."
  (sqlite-select (org-workflow-store--db)
                 "SELECT seq FROM events WHERE id=? ORDER BY seq" (list id)))

(defun org-workflow-agenda-plan-undo--event-index ()
  "Read commitment event sequences in one query for planning comparisons."
  (let ((index (make-hash-table :test #'equal)))
    (dolist (row (sqlite-select (org-workflow-store--db) "SELECT id,seq FROM events ORDER BY id,seq"))
      (push (cdr row) (gethash (car row) index)))
    (maphash (lambda (id events) (puthash id (nreverse events) index)) index)
    index))

(defun org-workflow-agenda-plan-undo--record (original &rest args)
  "Call ORIGINAL with ARGS and remember successful explicit planning changes.
Capture undo state only after the transaction succeeds."
  (if (not org-workflow-store-enabled) (apply original args)
    (let* ((selected (delete-dups (copy-sequence
                                  (or org-agenda-bulk-marked-entries
                                      (list (or (org-get-at-bol 'org-hd-marker)
                                                (org-agenda-error)))))))
           (markers (org-workflow-agenda-plan-undo--markers selected))
           (before (mapcar #'org-workflow-agenda-plan-undo--entry markers))
           (facts (org-workflow-agenda-plan-undo--facts))
           (events (org-workflow-agenda-plan-undo--event-index))
           (project-days (org-workflow-agenda-plan-undo--project-days))
           (date (org-workflow-target--today-string))
           (result (apply original args))
           (after (mapcar #'org-workflow-agenda-plan-undo--entry markers))
           (events-after (org-workflow-agenda-plan-undo--event-index))
           (days-after (org-workflow-agenda-plan-undo--project-days))
           changed days affected)
      ;; An old completed duty can gain supersession events without changing
      ;; its status row. Events are part of the decision and its conflict check.
      (dolist (row (org-workflow-agenda-plan-undo--facts))
        (let ((prior (assoc (car row) facts))
              (prior-events (gethash (car row) events))
              (current-events (gethash (car row) events-after)))
          (unless (and (equal row prior) (equal current-events prior-events))
            (push (list prior row current-events prior-events) changed))))
      (dolist (key (delete-dups (mapcar #'car (append project-days days-after))))
        (let ((old (cadr (assoc key project-days))) (new (cadr (assoc key days-after))))
          (unless (equal old new) (push (list key old new) days))))
      (cl-mapc (lambda (marker old new)
                 (when (or (member marker selected) (not (equal old new)))
                   (push (list marker old new) affected))) markers before after)
      (unless (and (equal before after) (null changed) (null days))
        (setq org-workflow-agenda-last-plan
              (list :date date :database org-workflow-store-file
                    :markers (mapcar #'car affected)
                    :before (mapcar #'cadr affected) :after (mapcar #'caddr affected)
                    :facts changed :project-days days))
        (org-workflow-agenda--set-setting 'org-workflow-agenda-last-operation
                                         (list :kind 'plan :record org-workflow-agenda-last-plan)))
      result)))

(defun org-workflow-agenda--undo-plan ()
  "Correct the last plan without erasing commitment events or clock history."
  (interactive)
  (let* ((record org-workflow-agenda-last-plan)
         (markers (plist-get record :markers)))
    (unless record (user-error "本次会话没有可撤销的安排"))
    (unless (and org-workflow-store-enabled
                 (equal org-workflow-store-file (plist-get record :database))
                 (equal (org-workflow-target--today-string) (plist-get record :date)))
      (user-error "日期或数据库已变化；不能撤销此前的安排"))
    (cl-mapc (lambda (marker after)
               (unless (and (marker-buffer marker)
                            (member (buffer-file-name (marker-buffer marker))
                                    (append (org-agenda-files t)
                                            (org-workflow-collection-inbox--review-files)))
                            (equal after (org-workflow-agenda-plan-undo--entry marker)))
                 (user-error "任务或安排已变化，未执行撤销")))
             markers (plist-get record :after))
    (dolist (fact (plist-get record :facts))
      (let ((id (car (nth 1 fact))))
        (unless (and (equal (nth 1 fact) (org-workflow-store-commitment id))
                     (equal (nth 2 fact) (org-workflow-agenda-plan-undo--events id)))
          (user-error "承诺已有后续变更，未执行撤销"))))
    (dolist (day (plist-get record :project-days))
      (unless (equal (nth 2 day) (org-workflow-store-meta (car day)))
        (user-error "项目当天承诺已变化，未执行撤销")))
    (let ((org-workflow-store--extra-source-files
           (mapcar (lambda (marker) (buffer-file-name (marker-buffer marker))) markers)))
      (org-workflow-store--operation
     (lambda ()
       (cl-mapc
        (lambda (marker before)
          (org-with-point-at marker
            ;; Restore planning fields only; never restore a clock or task body.
            (let ((org-workflow-store-enabled nil))
              (dolist (pair (nth 2 before))
                (cond
                 ((equal (car pair) "SCHEDULED")
                  (if (cdr pair) (org-schedule nil (cdr pair)) (org-schedule '(4))))
                 ((equal (car pair) "PRIORITY")
                  (when (or (cdr pair) (nth 3 (org-heading-components)))
                    (org-priority (if (cdr pair) (string-to-char (cdr pair)) 'remove))))
                 ((cdr pair) (org-entry-put nil (car pair) (cdr pair)))
                 (t (org-entry-delete nil (car pair))))))))
        markers (plist-get record :before))
       (dolist (day (plist-get record :project-days))
         (if (nth 1 day)
             (org-workflow-store-set-meta (car day) (nth 1 day))
           (sqlite-execute (org-workflow-store--db) "DELETE FROM meta WHERE key=?" (list (car day)))))
       (dolist (fact (plist-get record :facts))
         (let* ((before (car fact)) (after (nth 1 fact)) (id (car after))
                (status (if before (nth 6 before) "cancelled")))
           ;; Restore status and compensate only this operation's added events.
           (sqlite-execute (org-workflow-store--db)
                           "UPDATE commitments SET status=? WHERE id=?" (list status id))
           (org-workflow-store--event id "plan-corrected"
                                      (list :from (nth 6 after) :to status
                                            :events (mapcar #'car (seq-difference (nth 2 fact) (nth 3 fact) #'equal))))
           (org-workflow-store--event id status))))))
    (setq org-workflow-agenda-last-plan nil)
    (org-agenda-redo)
    (message "已撤销上次安排（%d 项）；计时与历史记录保留" (length markers))))

(defun org-workflow-agenda-ensure-writeable ()
  "Reject a new Sprint write while a prior classification awaits persistence."
  (when (eq (plist-get (org-workflow-agenda--setting 'org-workflow-agenda-last-operation)
                       :save-state) 'pending)
    (user-error "请先重试保存归类，或 U 撤销")))

(defun org-workflow-agenda-invalidate-last-operation (reason)
  "End this Sprint's undo opportunity after another successful write, with REASON."
  (org-workflow-agenda--set-setting 'org-workflow-agenda-last-operation nil)
  (org-workflow-agenda--set-setting 'org-workflow-agenda-undo-reason reason)
  (setq org-workflow-agenda-last-plan nil))

(defun org-workflow-agenda-undo-last-operation ()
  "Correct this Sprint's latest arrangement or classification only."
  (interactive)
  (let ((record (org-workflow-agenda--setting 'org-workflow-agenda-last-operation)))
    (pcase (plist-get record :kind)
      ('classify (org-workflow-project-classify-undo record))
      ('plan (let ((org-workflow-agenda-last-plan (plist-get record :record)))
               (org-workflow-agenda--undo-plan))
             (org-workflow-agenda--set-setting 'org-workflow-agenda-last-operation nil)
             (setq org-workflow-agenda-last-plan nil))
      (_ (user-error "%s" (or (org-workflow-agenda--setting 'org-workflow-agenda-undo-reason)
                                "本工作台没有可撤销的安排／归类")))))
  (when (and (derived-mode-p 'org-agenda-mode) org-agenda-redo-command) (org-agenda-redo)))

(defun org-workflow-agenda-undo-plan ()
  "Compatibility entry for unified Sprint correction."
  (interactive)
  (if (org-workflow-agenda--setting 'org-workflow-agenda-last-operation)
      (org-workflow-agenda-undo-last-operation)
    (if org-workflow-agenda-last-plan (org-workflow-agenda--undo-plan)
      (org-workflow-agenda-undo-last-operation))))

(defun org-workflow-agenda-plan-undo--enable ()
  "Install this component while Workflow is being enabled."
  (dolist (command '(org-workflow-agenda-plan-morning org-workflow-agenda-plan-afternoon
                   org-workflow-agenda-plan-evening org-workflow-agenda-plan-recommended
                   org-workflow-agenda-schedule-today org-workflow-agenda-schedule-tomorrow
                   org-workflow-agenda-unschedule))
  (org-workflow--advice-add command :around #'org-workflow-agenda-plan-undo--record '((depth . -100)))))

(provide 'org-workflow-agenda-plan-undo)
;;; org-workflow-agenda-plan-undo.el ends here
