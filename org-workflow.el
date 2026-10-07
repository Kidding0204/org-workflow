;;; org-workflow.el --- Integrated task planning and historical review -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Jinwang Dong
;; Author: Jinwang Dong <dongjinwang040204@gmail.com>
;; Assisted-by: Codex:GPT-6
;; Version: 0.1.0
;; Package-Requires: ((emacs "31.1") (vulpea "2.5.0") (vulpea-journal "0.0") (vui "1.3.0") (transient "0.7.0") (org-super-agenda "1.4.0"))
;; Keywords: outlines, convenience
;; URL: https://github.com/Kidding0204/org-workflow
;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Commentary:
;; Coordinate Org task planning, execution, weekly capture and persistent history.
;; Enable `org-workflow-mode' explicitly after configuring sources and directories.
;; Loading this library alone does not activate integrations or open storage.
;;; Code:
(require 'org-workflow-lifecycle)
(require 'org-workflow-core)
(require 'org-workflow-agenda)
(require 'org-workflow-focus-timer)
(require 'org-workflow-weekly)
(require 'org-workflow-leave)
(require 'org-workflow-migrate)
(require 'org-workflow-history-panel)
(require 'org-workflow-history-workbench)
(require 'org-workflow-screenshot)
(require 'org-workflow-cleanup)

(defconst org-workflow--component-enablers
  '(org-workflow-habits--enable
    org-workflow-history-workbench--enable
    org-workflow-leave--enable
    org-workflow-panel--enable
    org-workflow-web-export--enable
    org-workflow-core--enable
    org-workflow-agenda-actions--enable
    org-workflow-agenda-layout--enable
    org-workflow-agenda-view--enable
    org-workflow-agenda-console--enable
    org-workflow-agenda-inbox--enable
    org-workflow-agenda-mouse--enable
    org-workflow-agenda-plan-undo--enable
    org-workflow-agenda-review--enable
    org-workflow-agenda--enable
    org-workflow-focus-timer--enable
    org-workflow-screenshot--enable))

(defcustom org-workflow-clock 'org-clock
  "Clock backend used by Workflow execution commands."
  :type '(choice (const org-clock) (const org-workflow-focus-timer)) :group 'org-workflow)
(defvar org-workflow--settings-before nil)
(defvar org-workflow--settings-installed nil)
(defconst org-workflow--managed-settings
  '(org-todo-keywords org-provide-todo-statistics org-tag-alist
    org-global-properties org-log-into-drawer org-log-done
    org-agenda-custom-commands org-super-agenda-header-map
    org-capture-templates org-refile-targets org-refile-use-outline-path
    org-outline-path-complete-in-steps org-agenda-hide-tags-regexp
    org-agenda-restore-windows-after-quit org-agenda-start-on-weekday
    org-timer-default-timer org-workflow-status-provider-function
    org-workflow-commitment-streak-provider-function))
(defun org-workflow--configure-org ()
  "Install the Workflow TODO model while retaining unrelated capture settings."
  (setq org-todo-keywords '((sequence "TODO(t)" "DIVE(v)" "|" "DONE(d)" "HOLD(h)"))
        org-provide-todo-statistics '(("TODO" "DIVE") ("DONE"))
        org-log-into-drawer nil org-log-done 'time)
  (let ((owned '("@tiny" "@flow" "@deep" "#Prone" "FLAGGED")))
    (setq org-tag-alist
          (append '((:startgroup . nil) ("@tiny" . ?t) ("@flow" . ?f)
                    ("@deep" . ?d) (:endgroup . nil) ("#Prone" . ?P) ("FLAGGED" . ?F))
                  (seq-remove (lambda (tag) (member (car-safe tag) owned)) org-tag-alist)))))
(defun org-workflow--org-buffer-setup ()
  "Install the local save refresh in an enabled Org buffer."
  (when org-workflow-mode
    (org-workflow--add-hook 'after-save-hook #'org-workflow-target--refresh-after-agenda-save nil t)))
(defun org-workflow--snapshot-settings ()
  "Record settings changed by the mode for a conservative disable."
  (mapcar (lambda (variable) (cons variable (and (boundp variable)
                                               (copy-tree (symbol-value variable)))))
          org-workflow--managed-settings))
(defun org-workflow--restore-keyed-setting (variable)
  "Restore only unchanged Workflow entries in keyed setting VARIABLE."
  (let ((before (alist-get variable org-workflow--settings-before))
        (installed (alist-get variable org-workflow--settings-installed))
        (current (symbol-value variable)))
    (dolist (entry installed)
      (let ((key (car-safe entry)))
        (when (and key (not (equal entry (assoc key before)))
                   (equal entry (assoc key current)))
          (setq current (assoc-delete-all key current))
          (when-let* ((previous (assoc key before))) (push previous current)))))
    (set variable current)))
(defun org-workflow--restore-settings ()
  "Restore settings still owned by Workflow, preserving later user changes."
  (dolist (entry org-workflow--settings-before)
    (let ((variable (car entry)))
      (cond
       ((memq variable '(org-capture-templates org-agenda-custom-commands))
        (if (equal (symbol-value variable) (alist-get variable org-workflow--settings-installed))
            (set variable (cdr entry))
          (org-workflow--restore-keyed-setting variable)))
       ((equal (symbol-value variable) (alist-get variable org-workflow--settings-installed))
        (set variable (cdr entry))))))
  (setq org-workflow--settings-before nil org-workflow--settings-installed nil))
(defun org-workflow--cancel-background-work ()
  "Cancel package timers without changing an existing Org clock record."
  (org-workflow-focus-timer--clear-state)
  (dolist (variable '(org-workflow-target-midnight-timer org-workflow-history-timer
                      org-workflow-history--refresh-timer org-workflow-journal-seal-timer
                      org-workflow-leave--startup-timer))
    (when (and (boundp variable) (timerp (symbol-value variable)))
      (cancel-timer (symbol-value variable)) (set variable nil))))
(defun org-workflow--enable ()
  "Activate current task semantics and owned integrations explicitly."
  (unless org-workflow--settings-before
    (setq org-workflow--settings-before (org-workflow--snapshot-settings))
    (let ((org-workflow--activating t))
    (condition-case err
        (progn
          (dolist (function org-workflow--component-enablers) (funcall function))
          ;; Fresh profiles do not implicitly import old journals or mutate notes.
          (unless (org-workflow-store-meta "anchor")
            (org-workflow-store-set-meta "anchor" (org-workflow-target--today-string)))
          (setq org-workflow-store-enabled t)
          (org-workflow-store-recover)
          (org-workflow-history-setup)
          (org-workflow-weekly-setup)
          (org-workflow--add-hook 'org-workflow-journal-finalized-hook #'org-workflow-web-export-after-finalize)
          (when (string< (org-workflow-store-meta "anchor") (org-workflow-target--today-string))
            (org-workflow-web-export-history))
          (dolist (buffer (buffer-list))
            (with-current-buffer buffer
              (when (derived-mode-p 'org-mode)
                (org-set-regexps-and-options) (org-workflow--org-buffer-setup))))
          (setq org-workflow--settings-installed (org-workflow--snapshot-settings)))
      (error
       (setq org-workflow--settings-installed (org-workflow--snapshot-settings))
       (org-workflow--disable)
       (setq org-workflow-mode nil)
       (signal (car err) (cdr err)))))))
(defun org-workflow--disable ()
  "Release package-owned integration without discarding source or history."
  (org-workflow--cancel-background-work)
  (org-workflow--remove-integrations)
  (setq org-workflow-store-enabled nil)
  (when org-workflow--settings-before (org-workflow--restore-settings))
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (derived-mode-p 'org-mode) (org-set-regexps-and-options)))))
;;;###autoload
(define-minor-mode org-workflow-mode
  "Enable the integrated Org Workflow with controlled global integration.
Loading the library alone does not enable the mode or open its storage."
  :global t :group 'org-workflow :lighter " Workflow"
  (if org-workflow-mode (org-workflow--enable) (org-workflow--disable)))
(provide 'org-workflow)
;;; org-workflow.el ends here
