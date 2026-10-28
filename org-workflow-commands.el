;;; org-workflow-commands.el --- org-workflow-commands Workflow component -*- lexical-binding: t; -*-
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

(defvar org-state)
(declare-function org-workflow-projects-sync "org-workflow-projects" (&rest _))
;;; org-workflow-commands.el --- Shared command boundaries -*- lexical-binding: t; -*-
(require 'org-workflow-store)

(defun org-workflow-commands--scoped-p ()
  "Return non-nil for a non-habit Workflow heading in an Agenda source."
  (and org-workflow-store-enabled (derived-mode-p 'org-mode)
       buffer-file-name (org-workflow--file-kind)
       (not (equal (org-entry-get nil "STYLE") "habit"))
       (member (file-truename buffer-file-name)
               (mapcar #'file-truename (org-agenda-files t)))))

(defun org-workflow-commands--schedule (original &rest args)
  "Call ORIGINAL with ARGS and synchronize the heading's commitment schedule."
  (if (not (org-workflow-commands--scoped-p)) (apply original args)
    (let ((marker (point-marker))
          (current (and (org-workflow-qa-p) (org-workflow-target-current-marker)))
          (before (org-workflow-target--timestamp-date (org-entry-get nil "SCHEDULED"))))
      (prog1 (apply original args)
        (org-with-point-at marker
                           (let ((after (org-workflow-target--timestamp-date (org-entry-get nil "SCHEDULED"))))
                             (if (equal (org-workflow-projects-kind) "project")
                                 (progn
                                   (org-entry-delete nil "WORKFLOW_START_DEFERRED")
                                   (org-workflow-projects-sync))
                               (org-workflow-store-schedule before after))
                             (when current
                               (setq org-workflow-target-selected-marker current
                                     org-workflow-target-selected-date (org-workflow-target--today-string)))
                             (org-workflow-projects-sync)
                             (when (and (not (equal before (org-workflow-target--timestamp-date (org-entry-get nil "SCHEDULED"))))
                                        (org-workflow-target--same-marker-p marker org-workflow-executing-marker))
                               (org-workflow--release-execution))))))))

(defun org-workflow-commands--state ()
  "Synchronize the current heading's TODO state with its commitment record."
  (when (org-workflow-commands--scoped-p)
    (org-workflow-store-state org-state)))

(defun org-workflow-commands--scoped-operation (original &rest args)
  "Call ORIGINAL with ARGS inside a transaction for Workflow headings."
  (if (org-workflow-commands--scoped-p)
      (apply #'org-workflow-store--operation original args)
    (apply original args)))

(defun org-workflow-toggle-commitment ()
  "Explicitly withdraw, replace today's project duty, or create a future draft."
  (interactive)
  (unless org-workflow-store-enabled (user-error "Workflow storage has not been migrated"))
  (let ((marker (if (derived-mode-p 'org-agenda-mode)
                    (org-get-at-bol 'org-hd-marker) (point-marker))))
    (org-with-point-at marker
      (unless (and (org-workflow-commands--scoped-p)
                   (org-workflow-target--unfinished-leaf-p)
                   (not (org-workflow-projects-kind))
                   (not (org-workflow-projects-stage-p)))
        (user-error "请选择可执行的未完成任务"))
      (org-workflow-store--operation
       (lambda ()
         (let* ((today (org-workflow-target--today-string))
                (date (org-workflow-target--timestamp-date (org-entry-get nil "SCHEDULED")))
                (row (org-workflow-store-commitment (org-entry-get nil "WORKFLOW_COMMITMENT_ID")))
                (root (org-workflow-projects-root)))
           (cond
            ((and row (not (member (nth 6 row) '("withdrawn" "cancelled"))))
             (org-workflow-store--resolve row (if (string< today (nth 3 row)) "cancelled" "withdrawn"))
             (org-workflow-store--event (car row) "manual-withdrawal")
             (org-workflow-store--detach))
            ((and root (equal today date))
             (when (or (org-workflow-target--execution-blocked-p)
                       (org-with-point-at root
                         (or (not (equal (org-get-todo-state) "DIVE"))
                             (org-workflow-projects--goal-pause (org-workflow-projects--goal-id))
                             (org-workflow-projects--blocked-p))))
               (user-error "请先启用项目与所属阶段，再选择当天承诺"))
             (let* ((project-id (org-with-point-at root (org-id-get-create)))
                    (key (org-workflow-projects--day-key project-id today))
                    (old (org-workflow-store-commitment (org-workflow-store-meta key))))
               (when old
                 (unless (member (nth 6 old) '("done" "adjusted-done" "cancelled" "withdrawn"))
                   (org-workflow-store--resolve old "withdrawn"))
                 (org-workflow-store--event (car old) "manual-replacement")
                 ;; 完成记录留存，但手动替换后当天只计新责任。
                 (org-workflow-store--event (car old) "project-superseded"
                                            (list :date today :project project-id))
                 (org-with-point-at root
                   (org-map-entries
                    (lambda ()
                      (when (equal (car old) (org-entry-get nil "WORKFLOW_COMMITMENT_ID"))
                        (org-workflow-store--detach))) nil 'tree)))
               (let ((id (org-workflow-store-create today)))
                 (org-workflow-store--event id "project-daily" (list :project project-id))
                 (org-workflow-store--event id "manual-selection")
                 (org-workflow-store-set-meta key id))))
            ((and date (string< today date))
             (when (org-workflow-target--execution-blocked-p)
               (user-error "不能为暂停或完成的分支创建承诺"))
             (org-workflow-store-create date))
            (t (user-error "请先安排日期；当天更换承诺需属于项目")))))))
    (when (derived-mode-p 'org-agenda-mode) (org-workflow-agenda--redo-at-task marker))))

(defun org-workflow-display-tags (&optional marker)
  "Return semantic display tags for MARKER, or the heading at point.
Derive commitment from stored facts rather than source tags."
  (org-with-point-at (or marker (point-marker))
                     (let ((tags (copy-sequence (org-get-tags))))
                       (if (not org-workflow-store-enabled) tags
                         (setq tags (delete "promise" tags))
                         (if (org-workflow-store-promise-p) (cons "promise" tags) tags)))))

(defun org-workflow-commands--step (original title marker)
  "Call ORIGINAL with TITLE and MARKER after closing matching live time.
Close time before the rollback boundary so a failure cannot lose it."
  (when (string-match-p "[\r\n]" title) (user-error "Executed Part must be a single heading line"))
  (when (and org-workflow-store-enabled (org-workflow-clock--clock-active-p)
             (org-workflow-clock--clock-matches-p marker)
             (not (string-empty-p (string-trim title))))
    (org-workflow--release-execution)
    (when (org-workflow-clock--clock-active-p) (org-workflow-clock--clock-stop)))
  (prog1 (org-workflow-store--operation original title marker)
    (when org-workflow-store-enabled (setq org-workflow-executing-marker nil))))

(defun org-workflow-commands--refresh (original &rest args)
  "Call ORIGINAL with ARGS unless an outer transaction will perform the refresh."
  (unless org-workflow-store--in-operation (apply original args)))

(defun org-workflow-commands-setup ()
  "Install shared boundaries once.  Source and Agenda commands use the same facts."
  (org-workflow--advice-add 'org-workflow-target-refresh :around #'org-workflow-commands--refresh)
  (org-workflow--advice-add 'org-schedule :around #'org-workflow-commands--schedule '((depth . 10)))
  (org-workflow--advice-add 'org-schedule :around #'org-workflow-commands--scoped-operation '((depth . -90)))
  (org-workflow--advice-add 'org-todo :around #'org-workflow-commands--scoped-operation '((depth . -90)))
  (org-workflow--advice-add 'org-workflow--add-schedule :around #'org-workflow-commands--schedule)
  (org-workflow--add-hook 'org-after-todo-state-change-hook #'org-workflow-commands--state -90)
  (org-workflow--advice-add 'org-workflow-target--step :around #'org-workflow-commands--step)
  (remove-hook 'after-save-hook #'org-workflow-store-checkpoint)
  (org-workflow--add-hook 'after-save-hook #'org-workflow-store--after-save)
  (dolist (command '(org-workflow-agenda--apply-planning
                     org-workflow-target-prerequisite org-workflow-target-defer-group))
    (org-workflow--advice-add command :around #'org-workflow-store--operation)))

(provide 'org-workflow-commands)
;;; org-workflow-commands.el ends here
