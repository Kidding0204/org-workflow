;;; org-workflow-migrate.el --- org-workflow-migrate Workflow component -*- lexical-binding: t; -*-
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
;;; org-workflow-migrate.el --- One-way verified migration with backups -*- lexical-binding: t; -*-
(require 'org-workflow-history)

(defun org-workflow-migrate--inactive-current-root-p ()
  "Return non-nil when a legacy root is at or under completed or held work."
  (save-excursion
    (org-back-to-heading t)
    (catch 'inactive
      (while t
        (when (or (org-entry-is-done-p) (equal "HOLD" (org-get-todo-state)))
          (throw 'inactive t))
        (unless (org-up-heading-safe) (throw 'inactive nil))))))

(defun org-workflow-migrate-current-scope (&optional apply)
  "Preview explicit CURR roots in scoped Agenda files; with APPLY, migrate them.
Open roots become DIVE, completed or held roots retain their state.  Only local
CURR tags are removed; inherited tags never create additional roots.  Applying
requires clean writable source buffers, creates backups, and rolls back every
affected file if an edit or save fails.  No commitment or historical facts change."
  (interactive "P")
  (let (plans report)
    (dolist (file (seq-filter #'file-readable-p (org-agenda-files t)))
      (with-current-buffer (or (get-file-buffer file) (find-file-noselect file))
        (org-with-wide-buffer
         (when (org-workflow--file-kind)
           (let (roots)
             (org-map-entries
              (lambda ()
                (when (member "CURR" (org-get-tags nil t))
                  (push (list :marker (copy-marker (point))
                              :title (org-get-heading t t t t)
                              :state (org-get-todo-state)
                              :inactive (org-workflow-migrate--inactive-current-root-p)) roots)))
              nil 'file)
             (when roots
               (push (list :file file :buffer (current-buffer)
                           :roots (nreverse roots)) plans)))))))
    (setq plans (nreverse plans)
          report (mapcar (lambda (plan)
                           (list :file (plist-get plan :file)
                                 :roots (mapcar
                                         (lambda (root)
                                           (list :title (plist-get root :title)
                                                 :from (plist-get root :state)
                                                 :to (if (plist-get root :inactive)
                                                         (plist-get root :state) "DIVE")))
                                         (plist-get plan :roots)))) plans))
    (unwind-protect
        (when (and apply plans)
          (dolist (plan plans)
            (with-current-buffer (plist-get plan :buffer)
              (when (buffer-modified-p) (user-error "迁移前请保存 %s" buffer-file-name))
              (unless (verify-visited-file-modtime (current-buffer))
                (user-error "文件已被外部修改，请先重新加载：%s" buffer-file-name))
              (when (or buffer-read-only (not (file-writable-p buffer-file-name)))
                (user-error "迁移文件不可写：%s" buffer-file-name))
              (org-set-regexps-and-options)
              (unless (member "DIVE" org-not-done-keywords)
                (user-error "文件未识别 DIVE 未完成状态：%s" buffer-file-name))))
          (let* ((parent (expand-file-name "var/workflow-backups/" user-emacs-directory))
                 (backup (progn (make-directory parent t)
                                (make-temp-file (expand-file-name "curr-to-dive-" parent) t)))
                 groups backups)
            (dolist (plan plans)
              (let* ((file (plist-get plan :file))
                     (copy (expand-file-name (concat (secure-hash 'sha256 (expand-file-name file)) ".org") backup)))
                (copy-file file copy)
                (push (cons file copy) backups)))
            (with-temp-file (expand-file-name "manifest.el" backup)
              (prin1 backups (current-buffer)))
            (condition-case err
                (progn
                  (dolist (plan plans)
                    (with-current-buffer (plist-get plan :buffer)
                      (let ((group (prepare-change-group)))
                        (activate-change-group group)
                        (push (cons (current-buffer) group) groups))
                      (org-with-wide-buffer
                       (let (org-after-todo-state-change-hook
                             (org-workflow-store-enabled nil)
                             org-after-todo-statistics-hook org-todo-log-states
                             org-log-done org-enforce-todo-dependencies
                             org-trigger-hook org-todo-state-tags-triggers
                             (org-inhibit-logging t))
                         (dolist (root (plist-get plan :roots))
                           (org-with-point-at (plist-get root :marker)
                             (unless (plist-get root :inactive)
                               (org-todo "DIVE")
                               (unless (equal "DIVE" (org-get-todo-state))
                                 (error "迁移状态失败：%s" (plist-get root :title))))
                             (org-set-tags (remove "CURR" (org-get-tags nil t)))))))))
                  (dolist (plan plans)
                    (with-current-buffer (plist-get plan :buffer)
                      (let (before-save-hook after-save-hook)
                        (save-buffer))))
                  (dolist (pair groups)
                    (with-current-buffer (car pair) (accept-change-group (cdr pair))))
                  (when (called-interactively-p 'interactive)
                    (message "已迁移 %d 个文件；备份：%s" (length plans) backup)))
              ((error quit)
               (let ((inhibit-quit t))
                 (dolist (pair groups)
                   (with-current-buffer (car pair) (cancel-change-group (cdr pair))))
                 (dolist (pair backups) (copy-file (cdr pair) (car pair) t))
                 (dolist (plan plans)
                   (with-current-buffer (plist-get plan :buffer)
                     (set-visited-file-modtime)
                     (set-buffer-modified-p nil))))
               (signal (car err) (cdr err))))))
      (dolist (plan plans)
        (dolist (root (plist-get plan :roots))
          (set-marker (plist-get root :marker) nil))))
    (when (and (called-interactively-p 'interactive) (not apply))
      (message "CURR → DIVE 预览：%d 个文件；使用前缀参数应用" (length report)))
    report))

(defun org-workflow-migrate--legacy-days ()
  "Validate legacy exports before changing anything.  Do not fabricate missing days."
  (let ((org-workflow-store-enabled nil) days)
    (dolist (entry (org-workflow-web-export--candidate-records))
      (push (org-workflow-web-export--finalized-day (car entry) (cdr entry)) days))
    days))

(defun org-workflow-migrate--backup (files)
  "Copy FILES into a timestamped backup directory and write their manifest."
  (let ((directory (expand-file-name (format-time-string "var/workflow-backups/%Y%m%d-%H%M%S/") user-emacs-directory)))
    (make-directory directory t)
    (dolist (file files)
      (copy-file file (expand-file-name (concat (secure-hash 'sha256 (expand-file-name file)) ".org") directory)))
    (with-temp-file (expand-file-name "manifest.el" directory) (prin1 files (current-buffer)))
    directory))

(defun org-workflow-migrate ()
  "Validate/import old facts and migrate source commitments once, with backups."
  (interactive)
  (unless (org-workflow-store-meta "migration-v1")
    (let* ((files (seq-filter #'file-readable-p (org-agenda-files t)))
           (days (org-workflow-migrate--legacy-days))
           (journal-files (org-workflow-collection-inbox--review-files))
           (anchor (let ((org-workflow-store-enabled nil))
                     (org-workflow-web-export--tracking-started
                      (org-workflow-web-export--candidate-records))))
           backup)
      (dolist (file files)
        (when-let* ((buffer (get-file-buffer file)))
          (when (buffer-modified-p buffer) (user-error "迁移前请保存 %s" file))))
      (setq backup (org-workflow-migrate--backup (delete-dups (append files journal-files))))
      (sqlite-execute (org-workflow-store--db) "VACUUM INTO ?"
                      (list (expand-file-name "facts-before.sqlite" backup)))
      (let ((org-workflow-store-enabled t))
        (org-workflow-store--operation
         (lambda ()
           (dolist (day days)
             (let ((old (org-workflow-store-day (plist-get day :date))))
               (when (and old (not (equal old day)))
                 (error "Conflicting history for %s" (plist-get day :date)))
               (org-workflow-store-put-day (plist-get day :date) day)))
           (dolist (file files)
             (with-current-buffer (find-file-noselect file)
               (org-with-wide-buffer
                (when (org-workflow--file-kind)
                  ;; Resolve inherited tags before removing any local legacy tags.
                  (let (targets)
                    (org-map-entries
                     (lambda ()
                       (when (and (>= (org-outline-level) 2) (org-workflow-target--task-leaf-p)
                                  (org-entry-get nil "SCHEDULED")
                                  (member "promise" (org-get-tags))
                                  (member (org-get-todo-state) '("TODO" "READY")))
                         (push (point-marker) targets))) nil 'file)
                    (dolist (marker targets)
                      (org-with-point-at marker
                                         (unless (org-entry-get nil "WORKFLOW_COMMITMENT_ID")
                                           (org-workflow-store-create
                                            (or (org-entry-get nil "WORKFLOW_PROMISE_DATE")
                                                (org-workflow-target--timestamp-date (org-entry-get nil "SCHEDULED"))) t)))))
                  (org-map-entries
                   (lambda ()
                     (when (equal (org-get-todo-state) "READY")
                       (org-entry-put nil "WORKFLOW_LEGACY_STATE" "READY")
                       (let ((org-log-done nil)) (org-todo "TODO")))
                     (when (member "promise" (org-get-tags nil t))
                       (org-entry-put nil "WORKFLOW_LEGACY_PROMISE" "t")
                       (org-toggle-tag "promise" 'off))
                     (when (org-entry-get nil "WORKFLOW_COMMITMENT_ID")
                       (org-entry-delete nil "WORKFLOW_PROMISE_DATE"))) nil 'file)
                  (goto-char (point-min))
                  (while (re-search-forward "^#\\+\\(?:TODO\\|SEQ_TODO\\):.*" nil t)
                    (replace-match (replace-regexp-in-string "\\bREADY\\(?:([^)]*)\\)? *" "" (match-string 0)) t t))
                  (goto-char (point-min))
                  (while (re-search-forward "^#\\+filetags:.*" nil t)
                    (replace-match (replace-regexp-in-string ":promise:" ":" (match-string 0)) t t))))))
           (org-workflow-store-set-meta "anchor" (or anchor (org-workflow-target--today-string)))
           (org-workflow-store-set-meta "backup" backup)
           (org-workflow-store-set-meta "migration-v1" "complete")))
        (dolist (file files) (with-current-buffer (find-file-noselect file) (when (buffer-modified-p) (save-buffer))))
        (org-workflow-store-checkpoint))
      (unless (= (length days) (length (org-workflow-store-days)))
        (error "Imported day count mismatch"))
      (dolist (day days)
        (unless (equal day (org-workflow-store-day (plist-get day :date)))
          (error "Imported record differs for %s" (plist-get day :date))))))
)

(defun org-workflow-system-setup ()
  "Recover persisted work and enable the new model only after migration."
  (org-workflow-migrate)
  (setq org-workflow-external-actions (assq-delete-all 'ready org-workflow-external-actions))
  (setq org-workflow-store-enabled t
        org-todo-keywords '((sequence "TODO(t)" "DIVE(v)" "|" "DONE(d)" "HOLD(h)"))
        org-provide-todo-statistics '(("TODO" "DIVE") ("DONE"))
        org-tag-alist (seq-remove (lambda (item) (member (car item) '("promise" "CURR"))) org-tag-alist))
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (derived-mode-p 'org-mode) (org-set-regexps-and-options))))
  (org-workflow-store-recover)
  (org-workflow-store-checkpoint)
  (org-workflow-history-setup)
  (org-workflow-commands-setup)
  (org-workflow-weekly-setup))

(provide 'org-workflow-migrate)
;;; org-workflow-migrate.el ends here
