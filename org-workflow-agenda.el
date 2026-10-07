;;; org-workflow-agenda.el --- note-gtd Workflow component -*- lexical-binding: t; -*-
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
;;; org-workflow-agenda.el --- Org-mode configuration for gtd -*- lexical-binding: t; -*-
;;; Code:
(require 'cl-lib)

(require 'seq)

(defun org-workflow-todo--include-dive (sequence)
  "Keep DIVE available as unfinished work in local TODO SEQUENCE definitions."
  (when (and (eq (car sequence) 'sequence)
             (member "TODO" (org-remove-keyword-keys (cdr sequence)))
             (not (member "DIVE" (org-remove-keyword-keys (cdr sequence)))))
    (let* ((keywords (cdr sequence))
           (separator (or (cl-position "|" keywords :test #'equal)
                          (1- (length keywords)))))
      (cons 'sequence
            (append (seq-take keywords separator) '("DIVE(v)")
                    (nthcdr separator keywords))))))

(defun org-workflow-agenda-evil-bindings ()
  "Install optional Evil Agenda bindings with reversible ownership."
  (dolist (binding '(("e" . org-agenda-set-effort)
                     ("j" . org-agenda-next-item)
                     ("k" . org-agenda-previous-item)
                     ("a" . org-workflow-agenda-view-menu)))
    (org-workflow--evil-keymap-set
     'normal org-agenda-mode-map (car binding) (cdr binding))))

(defun org-workflow-summary-todo (n-done n-not-done)
  "Set a statistics parent to DONE when N-NOT-DONE is zero.
N-DONE is the completed child count supplied by Org and is ignored."
  (ignore n-done)
  (when-let* ((state (org-get-todo-state)))
    (when (member state '("TODO" "DIVE" "READY" "DONE"))
      (let ((target-state (if (zerop n-not-done) "DONE"
                            (if (equal state "DIVE") "DIVE" "TODO"))))
        (unless (equal state target-state)
          (let (org-log-done org-todo-log-states)
            (org-todo target-state)))))))

;; Sprint implementation; menu and custom command remain below.
(require 'org-workflow-agenda-view)

(require 'org-workflow-agenda-layout)

(require 'org-workflow-agenda-actions)

(autoload 'org-workflow-evening-today "org-workflow-evening")

(require 'org-super-agenda)

(require 'transient)

(transient-define-prefix org-workflow-agenda-view-menu ()
  "Filter and configure the Workflow view."
  :transient-suffix 'transient--do-stay
  :variable-pitch t
  [["筛选"
    ("t" "@tiny" org-workflow-agenda-filter-tiny)
    ("f" "@flow" org-workflow-agenda-filter-flow)
    ("d" "@deep" org-workflow-agenda-filter-deep)
    ("p" "promise" org-workflow-agenda-filter-promise)
    ("0" "清除筛选" org-workflow-agenda-filter-clear)]
   ["视图"
    ("c" "双页工作台" org-workflow-agenda-open-workbench :transient nil)
    ("w" org-workflow-agenda-planning-scope-label org-workflow-agenda-toggle-planning-scope)
    ("C" "今日已完成" org-workflow-agenda-toggle-completed)]
   ["返回"
    ("q" "关闭菜单" transient-quit-one)]])

(require 'org-workflow-agenda-inbox)

(require 'org-workflow-agenda-review)

(require 'org-workflow-agenda-console)

(require 'org-workflow-agenda-mouse)

(defun org-workflow-agenda--enable ()
  "Install this component while Workflow is being enabled."
  (org-workflow--add-hook 'org-todo-setup-filter-hook #'org-workflow-todo--include-dive)
  (org-workflow--configure-org)
  (org-workflow--add-hook 'org-agenda-mode-hook #'org-workflow-agenda-evil-bindings)
  (org-workflow--add-hook 'org-after-todo-statistics-hook #'org-workflow-summary-todo)
  (setq org-super-agenda-header-map nil)
  (setq org-agenda-custom-commands
        (append '(("d" "Sprint"
           ((org-workflow-agenda-workbench-view ""))
           ((org-agenda-block-separator nil)
            (org-workflow-agenda-sprint-view t)
            (org-agenda-compact-blocks t)
            (org-agenda-todo-keyword-format "")
            (org-super-agenda-header-prefix "  ")
            (org-super-agenda-header-separator "")))
          ("s" "Sprint 工作台（双栏）" org-workflow-agenda-open-workbench ""))
                (seq-remove (lambda (command) (member (car-safe command) '("d" "s")))
                            org-agenda-custom-commands)))
  (org-workflow--keymap-set org-agenda-mode-map "a" #'org-workflow-agenda-view-menu)
  (org-workflow--with-after-load 'evil-collection
    (org-workflow-agenda-evil-bindings))
  (org-workflow--keymap-set org-agenda-mode-map "<mouse-1>" #'org-agenda-goto-mouse)
  (org-workflow--keymap-set org-agenda-mode-map "<mouse-2>"
            #'org-workflow-agenda-schedule-today-mouse)
  (org-workflow--with-after-load 'evil
    (org-workflow-agenda-evil-bindings))
  ;; Org-agenda related configuration
(setopt org-agenda-restore-windows-after-quit t)
  (setopt org-agenda-start-on-weekday 0)
  ;; when dispalyed on week view dashboard

(setopt org-timer-default-timer "25"))

(provide 'org-workflow-agenda)
;;; org-workflow-agenda.el ends here
