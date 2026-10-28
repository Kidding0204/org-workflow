;;; org-workflow-project-view.el --- Compatibility entry to Sprint projects -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Jinwang Dong
;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Commentary:
;; Project management belongs to Sprint. Keep public commands for existing
;; bindings, but no second renderer, mode or independent project window.
;;; Code:
(require 'org-workflow-agenda)
(require 'org-workflow-agenda-projects)

;;;###autoload
(defun org-workflow-project-view ()
  "Open the existing daily Sprint columns for classification and arranging."
  (interactive)
  (unless (and (derived-mode-p 'org-agenda-mode) org-workflow-agenda--sprint-buffer-p)
    (let ((existing
           (seq-find (lambda (buffer)
                       (with-current-buffer buffer
                         (and org-workflow-agenda--sprint-buffer-p org-workflow-agenda--workbench
                              (eq buffer (org-workflow-agenda-workbench-primary org-workflow-agenda--workbench)))))
                     (buffer-list))))
      (if (not existing) (org-workflow-agenda-open-workbench)
        (let* ((state (buffer-local-value 'org-workflow-agenda--workbench existing))
               (frame (org-workflow-agenda-workbench-tab-frame state))
               (tabs (when (eq frame (selected-frame)) (tab-bar-tabs)))
               (index (seq-position tabs state
                                    (lambda (tab owner)
                                      (eq (alist-get 'org-workflow-agenda-workbench tab) owner)))))
          (when index (tab-bar-select-tab (1+ index)))
          (pop-to-buffer existing)))))
  (org-workflow-agenda-select-view 'projects))

(defun org-workflow-project-view-refresh ()
  "Refresh unified Sprint projects, opening the page when called elsewhere."
  (interactive)
  (if (and (derived-mode-p 'org-agenda-mode) org-workflow-agenda--sprint-buffer-p)
      (org-agenda-redo)
    (org-workflow-project-view)))

(defalias 'org-workflow-project-view-toggle #'org-workflow-agenda-project-toggle)
(defalias 'org-workflow-project-view-visit #'org-agenda-switch-to)
(defalias 'org-workflow-project-view-state #'org-workflow-agenda-project-todo)
(defalias 'org-workflow-project-view-schedule #'org-workflow-agenda-project-start)

(defun org-workflow-project-view-sync ()
  "Explicitly reconcile project obligations and refresh Sprint."
  (interactive)
  (org-workflow-agenda-ensure-writeable)
  (org-workflow-projects-sync)
  (org-workflow-agenda-invalidate-last-operation "最近操作为显式项目同步")
  (org-workflow-project-view-refresh))

(defun org-workflow-project-view-register ()
  "Visit an existing Area file for native outline editing, without registration."
  (interactive)
  (find-file (completing-read "Area 文件：" (org-agenda-files t) nil t)))

(defun org-workflow-project-view-toggle-done ()
  "Toggle completed project context in the shared tree."
  (interactive)
  (let ((folds (org-workflow-agenda--setting 'org-workflow-agenda-project-folds)))
    (dolist (item (org-workflow-projects-collect))
      (when (and (equal (plist-get item :kind) "project") (equal (plist-get item :state) "DONE"))
        (setf (alist-get (org-workflow-agenda-project-key item) folds nil nil #'equal)
              (not (org-workflow-agenda-project-expanded-p item nil)))))
    (org-workflow-agenda--set-setting 'org-workflow-agenda-project-folds folds))
  (org-agenda-redo))

(provide 'org-workflow-project-view)
;;; org-workflow-project-view.el ends here
