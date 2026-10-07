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
;;; org-workflow-agenda-plan-undo.el --- One-step planning correction -*- lexical-binding: t; -*-
(require 'org-workflow-store)

(defvar org-workflow-agenda-last-plan nil "Last successful planning operation in this session.")

(defconst org-workflow-agenda-plan-undo--fields
  '("SCHEDULED" "PRIORITY" "WORKFLOW_COMMITMENT_ID"))

(defun org-workflow-agenda-plan-undo--entry (marker)
  "Return the heading, TODO state and planning properties at MARKER."
  (org-with-point-at marker
    (list (org-get-heading t t t t) (org-get-todo-state)
          (mapcar (lambda (field) (cons field (if (equal field "PRIORITY")
                                         (when-let* ((priority (nth 3 (org-heading-components))))
                                           (char-to-string priority))
                                       (org-entry-get nil field))))
                  org-workflow-agenda-plan-undo--fields))))

(defun org-workflow-agenda-plan-undo--facts ()
  "Return current commitment rows in identifier order."
  (sqlite-select (org-workflow-store--db) "SELECT * FROM commitments ORDER BY id"))

(defun org-workflow-agenda-plan-undo--events (id)
  "Return event sequence numbers belonging to commitment ID."
  (sqlite-select (org-workflow-store--db)
                 "SELECT seq FROM events WHERE id=? ORDER BY seq" (list id)))

(defun org-workflow-agenda-plan-undo--record (original &rest args)
  "Call ORIGINAL with ARGS and remember successful explicit planning changes.
Capture undo state only after the transaction succeeds."
  (if (not org-workflow-store-enabled) (apply original args)
    (let* ((markers (mapcar #'copy-marker
                           (delete-dups (copy-sequence
                                         (or org-agenda-bulk-marked-entries
                                             (list (or (org-get-at-bol 'org-hd-marker)
                                                       (org-agenda-error))))))))
           (before (mapcar #'org-workflow-agenda-plan-undo--entry markers))
           (facts (org-workflow-agenda-plan-undo--facts))
           (date (org-workflow-target--today-string))
           (result (apply original args))
           (after (mapcar #'org-workflow-agenda-plan-undo--entry markers))
           (changed (seq-remove (lambda (row) (equal row (assoc (car row) facts)))
                                (org-workflow-agenda-plan-undo--facts))))
      (unless (and (equal before after) (null changed))
        (setq org-workflow-agenda-last-plan
              (list :date date :database org-workflow-store-file
                    :markers markers :before before :after after
                    :facts (mapcar (lambda (row)
                                     (list (assoc (car row) facts) row
                                           (org-workflow-agenda-plan-undo--events (car row)))) changed))))
      result)))

(defun org-workflow-agenda-undo-plan ()
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
       (dolist (fact (plist-get record :facts))
         (let* ((before (car fact)) (after (nth 1 fact)) (id (car after))
                (status (if before (nth 6 before) "cancelled")))
           ;; Planning never changes scope or ownership: restore status, retain facts.
           (sqlite-execute (org-workflow-store--db)
                           "UPDATE commitments SET status=? WHERE id=?" (list status id))
           (org-workflow-store--event id "plan-corrected"
                                      (list :from (nth 6 after) :to status))
           (org-workflow-store--event id status))))))
    (setq org-workflow-agenda-last-plan nil)
    (org-agenda-redo)
    (when (car markers) (org-workflow-agenda--goto-task (car markers)))
    (message "已撤销上次安排（%d 项）；计时与历史记录保留" (length markers))))

(defun org-workflow-agenda-plan-undo--enable ()
  "Install this component while Workflow is being enabled."
  (dolist (command '(org-workflow-agenda-plan-morning org-workflow-agenda-plan-afternoon
                   org-workflow-agenda-plan-evening org-workflow-agenda-plan-recommended
                   org-workflow-agenda-schedule-today org-workflow-agenda-schedule-tomorrow
                   org-workflow-agenda-unschedule))
  (org-workflow--advice-add command :around #'org-workflow-agenda-plan-undo--record '((depth . -100)))))

(provide 'org-workflow-agenda-plan-undo)
;;; org-workflow-agenda-plan-undo.el ends here
