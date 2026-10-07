;;; org-workflow-lifecycle.el --- Controlled integration helpers -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Jinwang Dong
;; Author: Jinwang Dong <dongjinwang040204@gmail.com>
;; Assisted-by: Codex:GPT-6
;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Commentary:
;; Track integrations installed by the explicit global Workflow mode.
;;; Code:
(require 'org)
(require 'org-workflow-declarations)
(require 'cl-lib)
(require 'seq)
(declare-function evil-get-auxiliary-keymap "evil-core" (map state &optional create ignore-parent))
(defgroup org-workflow nil "Integrated Org task workflow." :group 'org)
(defcustom org-workflow-directory nil
  "Directory for weekly journals and planning notes; nil uses `org-directory'."
  :type '(choice (const nil) directory) :group 'org-workflow)
(defcustom org-workflow-install-default-bindings nil
  "Whether to install Workflow global prefixes and shared Org bindings."
  :type 'boolean :group 'org-workflow)
(defcustom org-workflow-sidebar-function nil
  "Optional function opening a notes sidebar beside the weekly review."
  :type '(choice (const nil) function) :group 'org-workflow)
(defvar org-workflow-mode nil)
(defvar org-workflow--activating nil)
(defvar org-workflow--hooks nil)
(defvar org-workflow--advices nil)
(defvar org-workflow--keys nil)
(defvar org-workflow--variable-advices nil)
(defvar org-workflow--deferred nil)
(defvar org-workflow--list-entries nil
  "Added integration entries as (VARIABLE ENTRY ORIGINAL-VALUE) records.")
(defun org-workflow--directory ()
  "Return the configured notes directory without using private note APIs."
  (file-name-as-directory (expand-file-name (or org-workflow-directory org-directory))))
(defun org-workflow--add-hook (hook function &optional depth local)
  "Add FUNCTION to HOOK at DEPTH, recording LOCAL ownership when enabled."
  (when (or org-workflow-mode org-workflow--activating)
    (cl-pushnew (list hook function local (and local (current-buffer))) org-workflow--hooks :test #'equal))
  (add-hook hook function depth local))
(defun org-workflow--advice-add (symbol where function &optional props)
  "Advise SYMBOL at WHERE with FUNCTION and PROPS, recording ownership."
  (when (and (or org-workflow-mode org-workflow--activating)
             (not (advice-member-p function symbol)))
    (push (cons symbol function) org-workflow--advices))
  (advice-add symbol where function props))
(defun org-workflow--advise-variable (variable where function)
  "Advise VARIABLE's function at WHERE with FUNCTION until mode disable."
  (cl-pushnew (cons variable function) org-workflow--variable-advices :test #'equal)
  (add-function where (symbol-value variable) function))
(defun org-workflow--keymap-set (map key definition &optional shared)
  "Bind KEY in MAP to DEFINITION, preserving shared-map bindings.
SHARED marks optional integrations whose maps belong to another package."
  (let ((shared (or shared (memq map (list (current-global-map) org-mode-map org-agenda-mode-map)))))
    (when (or (not shared) org-workflow-install-default-bindings)
      (when (and shared (or org-workflow-mode org-workflow--activating)
                 (not (seq-some (lambda (item) (and (eq (nth 0 item) map)
                                                   (equal (nth 1 item) key))) org-workflow--keys)))
        (push (list map key (keymap-lookup map key) definition) org-workflow--keys))
      (keymap-set map key definition))))
(defun org-workflow--evil-keymap-set (state map key definition)
  "Optionally bind KEY to DEFINITION in STATE's auxiliary map for MAP.
Restore the previous state binding when Workflow is disabled."
  (when (and org-workflow-install-default-bindings
             (fboundp 'evil-get-auxiliary-keymap))
    (org-workflow--keymap-set
     (evil-get-auxiliary-keymap map state t t) key definition t)))
(defun org-workflow--add-list-entry (variable entry)
  "Add ENTRY to list VARIABLE, recording only newly added entries.
Removal preserves entries supplied or subsequently replaced by the user."
  (unless (member entry (symbol-value variable))
    (set variable (cons entry (symbol-value variable)))
    (when (or org-workflow-mode org-workflow--activating)
      (push (list variable entry (copy-tree entry)) org-workflow--list-entries))))
(defun org-workflow--global-set-key (key definition)
  "Optionally bind global KEY to DEFINITION while the mode is enabled."
  (org-workflow--keymap-set (current-global-map) key definition))
(defun org-workflow--defer (feature forms)
  "Run integration FORMS once FEATURE is available and Workflow is enabled."
  (if (featurep feature)
      (eval (cons 'progn forms) t)
    (unless (member (cons feature forms) org-workflow--deferred)
      (push (cons feature forms) org-workflow--deferred)
      (eval-after-load feature
        (lambda () (when org-workflow-mode (eval (cons 'progn forms) t)))))))
(defmacro org-workflow--with-after-load (feature &rest forms)
  "Defer FORMS for FEATURE, guarded by the explicit Workflow mode."
  (declare (indent 1))
  `(org-workflow--defer ,feature ',forms))
(defun org-workflow--evil-insert ()
  "Enter insert state during capture when optional Evil is available."
  (when (fboundp 'evil-insert-state) (evil-insert-state)))
(defun org-workflow--remove-integrations ()
  "Remove the hooks, advice, shared keys and list entries owned by Workflow."
  (dolist (item org-workflow--hooks)
    (pcase-let ((`(,hook ,function ,local ,buffer) item))
      (if local
          (when (buffer-live-p buffer)
            (with-current-buffer buffer (remove-hook hook function t)))
        (remove-hook hook function))))
  (dolist (item org-workflow--advices) (advice-remove (car item) (cdr item)))
  (dolist (item org-workflow--variable-advices)
    (remove-function (symbol-value (car item)) (cdr item)))
  (dolist (item org-workflow--keys)
    (pcase-let ((`(,map ,key ,before ,ours) item))
      (when (equal (keymap-lookup map key) ours)
        (keymap-set map key (if (numberp before) nil before)))))
  (dolist (item org-workflow--list-entries)
    (when (equal (nth 1 item) (nth 2 item))
      (set (car item) (delq (nth 1 item) (symbol-value (car item))))))
  (setq org-workflow--list-entries nil
        org-workflow--hooks nil org-workflow--advices nil
        org-workflow--keys nil org-workflow--variable-advices nil))
(provide 'org-workflow-lifecycle)
;;; org-workflow-lifecycle.el ends here
