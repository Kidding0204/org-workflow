;;; org-workflow-cleanup.el --- org-workflow-cleanup Workflow component -*- lexical-binding: t; -*-
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
;;; org-workflow-cleanup.el --- Explicit task property cleanup -*- lexical-binding: t; -*-
(require 'org-workflow-migrate)

(defconst org-workflow-cleanup--retired-properties
  '("WORKFLOW_COMMITTED_AT" "WORKFLOW_COMMITTED_FOR" "WORKFLOW_DEFER_COUNT"
    "WORKFLOW_BATCH" "WORKFLOW_BLOCKED_BY" "WORKFLOW_PHASE"
    "WORKFLOW_MINIMUM_SEALED_AT" "WORKFLOW_LEGACY_PROMISE"
    "WORKFLOW_LEGACY_STATE" "WORKFLOW_READY_ON" "WORKFLOW_PROMISE_DATE"))

(defun org-workflow-cleanup--changes ()
  "Validate migrated task properties and return explicit heading edits."
  (let (changes)
    (dolist (file (org-agenda-files t))
      (when (file-readable-p file)
        (with-current-buffer (find-file-noselect file)
          (org-with-wide-buffer
           (when (and (org-workflow--file-kind)
                      (not (seq-intersection org-file-tags '("journal" "journal-week"))))
             (org-map-entries
              (lambda ()
                (let* ((removed (seq-filter (lambda (property)
                                             (org-entry-get nil property))
                                           org-workflow-cleanup--retired-properties))
                       (rank (org-entry-get nil "WORKFLOW_ORDER"))
                       (scope (org-entry-get nil "WORKFLOW_ORDER_SCOPE"))
                       (order (org-workflow--saved-order))
                       (compact (when order
                                  (format "%c/%d" (org-workflow--priority-character
                                                   (car order)) (cdr order)))))
                  (when (seq-some (lambda (property)
                                   (member property removed))
                                 '("WORKFLOW_COMMITTED_AT" "WORKFLOW_COMMITTED_FOR"))
                    (let ((row (org-workflow-store-commitment
                                (org-entry-get nil "WORKFLOW_COMMITMENT_ID"))))
                      (unless (and row (equal (nth 1 row) (org-entry-get nil "ID")))
                        (user-error "承诺关联无法验证：%s / %s" file
                                    (org-get-heading t t t t)))))
                  (when (and rank (null compact))
                    (user-error "排序属性无法转换：%s / %s" file
                                (org-get-heading t t t t)))
                  (when scope (push "WORKFLOW_ORDER_SCOPE" removed))
                  (when (or removed (and compact (not (equal rank compact))))
                    (push (list :marker (copy-marker (point)) :remove removed
                                :order compact :reordered (and compact (not (equal rank compact))))
                          changes)))) nil 'file))))))
    (nreverse changes)))

(defun org-workflow-cleanup-properties (&optional apply)
  "Preview redundant task properties; with APPLY, back up and clean sources.
Only migrated project/area Agenda sources participate.  Old journals and
SQLite commitment/history facts are preserved.  Interactive prefix applies."
  (interactive "P")
  (unless (and org-workflow-store-enabled
               (equal "complete" (org-workflow-store-meta "migration-v1")))
    (user-error "请先完成 Workflow 数据库迁移"))
  (let* ((changes (org-workflow-cleanup--changes))
         (files (delete-dups (mapcar (lambda (change)
                                      (buffer-file-name (marker-buffer
                                                         (plist-get change :marker)))) changes)))
         (result (list :headings (length changes) :files files
                       :removed (apply #'+ (mapcar (lambda (change)
                                                    (length (plist-get change :remove))) changes))
                       :orders (seq-count (lambda (change) (plist-get change :reordered)) changes))))
    (when (and apply changes)
      (when (sqlite-select (org-workflow-store--db)
                           "SELECT id FROM operations WHERE state IN ('applied','prepared')")
        (user-error "请先保存或处理待恢复的 Workflow 操作"))
      (dolist (file files)
        (with-current-buffer (get-file-buffer file)
          (when (or (buffer-modified-p) buffer-read-only)
            (user-error "清理前请保存并确认文件可写：%s" file))))
      (let ((backup (org-workflow-migrate--backup files)))
        (sqlite-execute (org-workflow-store--db) "VACUUM INTO ?"
                        (list (expand-file-name "facts-before.sqlite" backup)))
        (org-workflow-store--operation
         (lambda ()
           (dolist (change changes)
             (org-with-point-at (plist-get change :marker)
               (dolist (property (plist-get change :remove))
                 (org-entry-delete nil property))
               (when-let* ((order (plist-get change :order)))
                 (org-entry-put nil "WORKFLOW_ORDER" order))))))
        (dolist (file files) (with-current-buffer (get-file-buffer file) (save-buffer)))
        (org-workflow-store-checkpoint)
        (when (boundp 'org-workflow-agenda-last-plan) (setq org-workflow-agenda-last-plan nil))
        (setq result (plist-put result :backup backup))))
    (when (called-interactively-p 'interactive) (message "%S" result))
    result))

(provide 'org-workflow-cleanup)
;;; org-workflow-cleanup.el ends here
