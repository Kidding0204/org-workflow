;;; org-workflow-agenda-layout.el --- note-gtd-agenda-layout Workflow component -*- lexical-binding: t; -*-
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
;;; org-workflow-agenda-layout.el --- Independent Sprint panes -*- lexical-binding: t; -*-
;;; Commentary:
;; A workbench owns its panes and settings; ordinary Agendas stay independent.
;;; Code:
(require 'cl-lib)

(require 'org-agenda)

(require 'tab-bar)

(defvar org-workflow-agenda-columns-enabled nil)

(defvar org-workflow-agenda-selected-group nil)

(defvar org-workflow-agenda--laying-out-columns nil)

(defvar org-workflow-agenda--refreshing-workbench nil)

(defvar-local org-workflow-agenda--workbench nil)

(defvar-local org-workflow-agenda--pane-role 'combined)

(defvar-local org-workflow-agenda--column-window nil)

(defvar-local org-workflow-agenda--sprint-buffer-p nil)

(cl-defstruct (org-workflow-agenda-workbench
               (:constructor org-workflow-agenda-workbench-create))
              primary candidates window settings window-configuration tab-frame)

(defconst org-workflow-agenda--shared-settings
  '(org-workflow-agenda-plan-tomorrow org-workflow-agenda-planning-all
				org-workflow-agenda-selected-group org-workflow-agenda-future-expanded
                                org-workflow-agenda-completed-expanded org-workflow-agenda-columns-enabled
                                org-agenda-tag-filter))

(dolist (variable (append org-workflow-agenda--shared-settings
                          '(org-workflow-agenda--workbench org-workflow-agenda--pane-role
                            org-workflow-agenda--column-window org-workflow-agenda--sprint-buffer-p)))
  (put variable 'permanent-local t))

(defun org-workflow-agenda--workbench-buffers (&optional workbench)
  "Return live buffers owned by WORKBENCH, defaulting to this Sprint."
  (when-let* ((state (or workbench org-workflow-agenda--workbench)))
    (seq-filter #'buffer-live-p
                (list (org-workflow-agenda-workbench-primary state)
                      (org-workflow-agenda-workbench-candidates state)))))

(defun org-workflow-agenda--setting (variable)
  "Read VARIABLE from this workbench, or its existing default."
  (if org-workflow-agenda--workbench
      (gethash variable (org-workflow-agenda-workbench-settings org-workflow-agenda--workbench))
    (and (boundp variable) (symbol-value variable))))

(defun org-workflow-agenda--set-setting (variable value)
  "Set shared VARIABLE to VALUE without changing another workbench."
  (if org-workflow-agenda--workbench
      (progn
        (puthash variable value (org-workflow-agenda-workbench-settings org-workflow-agenda--workbench))
        (dolist (buffer (org-workflow-agenda--workbench-buffers))
          (with-current-buffer buffer (set (make-local-variable variable) value))))
    (set (make-local-variable variable) value))
  value)

(defun org-workflow-agenda-target-date ()
  "Return this workbench's planning day, never the Workflow execution day."
  (if (org-workflow-agenda--setting 'org-workflow-agenda-plan-tomorrow)
      (org-workflow-agenda--date-offset 1)
    (org-workflow-target--today-string)))

(defun org-workflow-agenda--ensure-workbench ()
  "Initialize settings for a newly generated Sprint buffer."
  (unless org-workflow-agenda--workbench
    (let ((settings (make-hash-table :test #'eq)))
      (dolist (variable org-workflow-agenda--shared-settings)
        (puthash variable (and (boundp variable) (symbol-value variable)) settings))
      (setq org-workflow-agenda--workbench
            (org-workflow-agenda-workbench-create
             :primary (current-buffer) :settings settings
             :window-configuration org-agenda-pre-window-conf))))
  org-workflow-agenda--workbench)

(defun org-workflow-agenda--clear-selection ()
  "Clear only this workbench's native bulk selections."
  (dolist (buffer (or (org-workflow-agenda--workbench-buffers) (list (current-buffer))))
    (with-current-buffer buffer
      (when org-agenda-bulk-marked-entries (org-agenda-bulk-unmark-all)))))

(defun org-workflow-agenda-set-day (tomorrow)
  "Select today or TOMORROW for both display and planning commands."
  (interactive)
  (org-workflow-agenda--clear-selection)
  (org-workflow-agenda--set-setting 'org-workflow-agenda-plan-tomorrow tomorrow)
  (org-agenda-redo)
  (force-mode-line-update t))

(defun org-workflow-agenda--isolate-prepare (original &rest args)
  "Call ORIGINAL with ARGS after giving Sprint its own native marker pool."
  (when org-workflow-agenda-sprint-view
    (with-current-buffer (get-buffer-create org-agenda-buffer-name)
      (unless (local-variable-p 'org-agenda-markers)
        (setq-local org-agenda-markers nil))
      (mapc #'make-local-variable org-agenda-local-vars)))
  (apply original args))

(defun org-workflow-agenda--isolate-mode (original &rest args)
  "Call ORIGINAL with ARGS, preserving local state while constructing Sprint."
  (if org-workflow-agenda-sprint-view
      (let ((org-agenda-sticky t) (org-agenda-doing-sticky-redo t))
        (prog1 (apply original args)
          (setq-local org-agenda-this-buffer-is-sticky nil)))
    (apply original args)))

(defun org-workflow-agenda--buffer-position (position)
  "Describe POSITION by source task identity and line fallback."
  (save-excursion
    (goto-char position)
    (list (when-let* ((marker (org-get-at-bol 'org-hd-marker)))
            (copy-marker marker))
          (line-number-at-pos))))

(defun org-workflow-agenda--restore-position (anchor)
  "Return the rebuilt position corresponding to ANCHOR."
  (save-excursion
    (goto-char (point-min))
    (unless (and (car anchor) (org-workflow-agenda--goto-task (car anchor)))
      (forward-line (1- (cadr anchor))))
    (point)))

(defun org-workflow-agenda--redo-pane (original buffer args)
  "Call ORIGINAL with ARGS to rebuild BUFFER, retaining task and scroll anchors."
  (with-current-buffer buffer
    (let* ((windows (get-buffer-window-list buffer nil t))
           (point-anchor (org-workflow-agenda--buffer-position (point)))
           (starts (mapcar (lambda (window)
                             (list window (org-workflow-agenda--buffer-position (window-start window))
                                   (org-workflow-agenda--buffer-position (window-point window))))
                           windows))
           (org-agenda-buffer-name (buffer-name buffer))
           (org-agenda-this-buffer-name (buffer-name buffer))
           (org-agenda-window-setup 'current-window))
      (save-window-excursion
        (when windows (select-window (car windows)))
        (set-buffer buffer)
        (apply original args))
      (goto-char (org-workflow-agenda--restore-position point-anchor))
      (dolist (row starts)
        (when (window-live-p (car row))
          (set-window-start (car row) (org-workflow-agenda--restore-position (cadr row)) t)
          (set-window-point (car row) (org-workflow-agenda--restore-position (caddr row)))))
      (dolist (anchor (cons point-anchor (apply #'append (mapcar #'cdr starts))))
        (when (markerp (car anchor)) (set-marker (car anchor) nil))))))

(defun org-workflow-agenda--redo-workbench (original &rest args)
  "Call ORIGINAL with ARGS to refresh both panes for native Agenda redo."
  (if (and org-workflow-agenda--workbench org-workflow-agenda--sprint-buffer-p
           (not org-workflow-agenda--refreshing-workbench))
      (let* ((org-workflow-agenda--refreshing-workbench t)
             (state org-workflow-agenda--workbench)
             (origin (current-buffer)))
        (dolist (buffer (org-workflow-agenda--workbench-buffers state))
          (org-workflow-agenda--redo-pane original buffer args))
        (when (buffer-live-p origin)
          (set-buffer origin)
          (unless noninteractive (org-workflow-agenda--apply-columns))))
    (apply original args)))

(defun org-workflow-agenda--make-candidates (state)
  "Generate STATE's independent candidate Agenda through the native command."
  (or (and (buffer-live-p (org-workflow-agenda-workbench-candidates state))
           (org-workflow-agenda-workbench-candidates state))
      (let* ((primary (org-workflow-agenda-workbench-primary state))
             (buffer (generate-new-buffer
                      (format "%s · 待安排" (buffer-name primary))))
             (org-agenda-buffer-name (buffer-name buffer))
             (org-agenda-window-setup 'current-window)
             (org-agenda-sticky nil)
             (org-workflow-agenda--refreshing-workbench t)
             (org-workflow-agenda--laying-out-columns t))
        (setf (org-workflow-agenda-workbench-candidates state) buffer)
        (with-current-buffer buffer
          (setq org-workflow-agenda--workbench state org-workflow-agenda--pane-role 'candidates)
          (maphash (lambda (variable value) (set (make-local-variable variable) value))
                   (org-workflow-agenda-workbench-settings state)))
        (save-window-excursion (org-agenda nil "d"))
        buffer)))

(defun org-workflow-agenda--apply-columns (&optional frame)
  "Apply the selected pane layout on FRAME, or the selected frame if nil."
  (unless org-workflow-agenda--laying-out-columns
    (let* ((org-workflow-agenda--laying-out-columns t)
           (state (org-workflow-agenda--ensure-workbench))
           (primary (org-workflow-agenda-workbench-primary state))
           (candidate-buffer (org-workflow-agenda-workbench-candidates state))
           (owned (org-workflow-agenda-workbench-window state))
           (companion (and (window-live-p owned)
                           (eq (window-buffer owned) candidate-buffer) owned))
           (windows (get-buffer-window-list primary nil (or frame (selected-frame))))
           (main (car windows))
           (enabled (gethash 'org-workflow-agenda-columns-enabled
                             (org-workflow-agenda-workbench-settings state)))
           changed)
      (when main
        (cond
         ((and companion (not enabled))
          (when (eq (selected-window) companion) (select-window main))
          (delete-window companion)
          (setf (org-workflow-agenda-workbench-window state) nil)
          (with-current-buffer primary
            (setq org-workflow-agenda--pane-role 'combined org-workflow-agenda--column-window nil)
            (org-workflow-agenda--set-setting 'org-workflow-agenda-selected-group nil))
          (setq changed t))
         ((and (not companion) enabled (= (length windows) 1))
          (let* ((candidates (org-workflow-agenda--make-candidates state))
                 (right (split-window main nil 'right)))
            (set-window-buffer right candidates)
            (setf (org-workflow-agenda-workbench-window state) right)
            (with-current-buffer primary
              (setq org-workflow-agenda--pane-role 'schedule org-workflow-agenda--column-window right))
            (setq changed t)))
         ((and (not companion)
               (not (eq (buffer-local-value 'org-workflow-agenda--pane-role primary) 'combined)))
          (with-current-buffer primary (setq org-workflow-agenda--pane-role 'combined))
          (setq changed t)))
        (when changed
          (with-current-buffer primary
            (let ((org-workflow-agenda--refreshing-workbench nil)) (org-agenda-redo))))))))

(defun org-workflow-agenda--columns-finalize ()
  "Initialize a Sprint session and update its owned windows after rendering."
  ;; Native edits finalize a narrowed row outside custom-command bindings.
  (unless (buffer-narrowed-p)
    (setq org-workflow-agenda--sprint-buffer-p org-workflow-agenda-sprint-view)
    (if org-workflow-agenda-sprint-view
        (org-workflow-agenda--ensure-workbench)
      (when org-workflow-agenda--workbench
	(let* ((state org-workflow-agenda--workbench)
               (window (org-workflow-agenda-workbench-window state))
               (candidates (org-workflow-agenda-workbench-candidates state)))
          (when (and (window-live-p window) (eq (window-buffer window) candidates))
            (delete-window window))
          (when (and (buffer-live-p candidates) (not (eq candidates (current-buffer))))
            (kill-buffer candidates))
          (setq org-workflow-agenda--workbench nil org-workflow-agenda--column-window nil
		org-workflow-agenda--pane-role 'combined))))))

(defun org-workflow-agenda--columns-resize (frame)
  "Compatibility entry point; resizing FRAME never changes Sprint layout."
  (ignore frame))

(defun org-workflow-agenda--clean-menu-windows ()
  "Remove only abandoned Transient side windows in the current tab."
  (dolist (window (window-list))
    (when (and (window-parent window)
               (window-parameter window 'window-side)
               (string-match-p "\\` \\*Old buffer +\\*transient\\*\\*\\'"
                               (buffer-name (window-buffer window))))
      (delete-window window))))

(defun org-workflow-agenda-open-workbench (&optional _match)
  "Open an explicit Sprint tab with schedule left and project candidates right."
  (interactive)
  (org-workflow-agenda--clean-menu-windows)
  (let ((org-workflow-agenda-plan-tomorrow (org-workflow-agenda--setting 'org-workflow-agenda-plan-tomorrow))
        (org-workflow-agenda-planning-all (org-workflow-agenda--setting 'org-workflow-agenda-planning-all))
        (org-workflow-agenda-selected-group nil)
        (org-workflow-agenda-columns-enabled nil)
        (org-agenda-buffer-name (generate-new-buffer-name "*Sprint 工作台*"))
        (org-agenda-window-setup 'current-window)
        (tab-bar-new-tab-choice "*scratch*"))
    (tab-bar-new-tab)
    (tab-bar-rename-tab "Sprint 工作台")
    (condition-case err
        (progn
          (delete-other-windows)
          (org-agenda nil "d")
          (let ((state (org-workflow-agenda--ensure-workbench)))
            (setf (org-workflow-agenda-workbench-tab-frame state) (selected-frame))
            (let ((tab (tab-bar--current-tab-find)))
              (setf (alist-get 'org-workflow-agenda-workbench (cdr tab)) state))
            (org-workflow-agenda--set-setting 'org-workflow-agenda-columns-enabled t)
            (org-workflow-agenda--apply-columns)))
      (error
       (when org-workflow-agenda--workbench
         (dolist (buffer (org-workflow-agenda--workbench-buffers))
           (when (buffer-live-p buffer) (kill-buffer buffer))))
       (tab-bar-close-tab)
       (signal (car err) (cdr err))))))

(defun org-workflow-agenda-toggle-columns ()
  "Manually toggle panes; window width never controls this setting."
  (interactive)
  (org-workflow-agenda--set-setting 'org-workflow-agenda-columns-enabled
                              (not (org-workflow-agenda--setting 'org-workflow-agenda-columns-enabled)))
  (org-workflow-agenda--apply-columns)
  (message "%s" (if (org-workflow-agenda--setting 'org-workflow-agenda-columns-enabled)
                    "双页：左侧日安排，右侧待安排" "已合并为单页")))

(defun org-workflow-agenda--close-workbench-tab (tab last-tab)
  "Clean up buffers owned by TAB when it is not the LAST-TAB."
  (when-let* (((not last-tab))
              (state (alist-get 'org-workflow-agenda-workbench tab)))
    (let ((org-workflow-agenda--laying-out-columns t))
      (dolist (buffer (org-workflow-agenda--workbench-buffers state))
        (when (buffer-live-p buffer) (kill-buffer buffer))))))

(defun org-workflow-agenda--quit-workbench (original &optional bury)
  "Exit Sprint with its saved window configuration.
Pass BURY to ORIGINAL when delegating to the native quit command."
  (if (or (not org-workflow-agenda--workbench) org-agenda-columns-active)
      (funcall original bury)
    (let* ((org-workflow-agenda--laying-out-columns t)
           (state org-workflow-agenda--workbench)
           (buffers (org-workflow-agenda--workbench-buffers state))
           (window (org-workflow-agenda-workbench-window state))
           (primary (org-workflow-agenda-workbench-primary state))
           (candidates (org-workflow-agenda-workbench-candidates state))
           (org-agenda-pre-window-conf (org-workflow-agenda-workbench-window-configuration state)))
      (when (and (window-live-p window) (eq (window-buffer window) candidates))
        (when (eq (selected-window) window)
          (when-let* ((main (get-buffer-window primary))) (select-window main)))
        (delete-window window))
      (let* ((frame (org-workflow-agenda-workbench-tab-frame state))
             (tabs (and (frame-live-p frame) (funcall tab-bar-tabs-function frame)))
             (index (seq-position tabs state
                                  (lambda (tab workbench)
                                    (eq (alist-get 'org-workflow-agenda-workbench tab) workbench)))))
        (if index
            (with-selected-frame frame (tab-bar-close-tab (1+ index)))
          (with-current-buffer primary (funcall original bury))))
      (dolist (buffer buffers)
        (when (buffer-live-p buffer)
          (if bury (bury-buffer buffer) (kill-buffer buffer)))))))

(defun org-workflow-agenda-layout--enable ()
  "Install this component while Workflow is being enabled."
  (org-workflow--advice-add 'org-agenda-prepare :around #'org-workflow-agenda--isolate-prepare)
  (org-workflow--advice-add 'org-agenda-mode :around #'org-workflow-agenda--isolate-mode)
  (org-workflow--advice-add 'org-agenda-redo :around #'org-workflow-agenda--redo-workbench)
  (org-workflow--advice-add 'org-agenda--quit :around #'org-workflow-agenda--quit-workbench)
  (org-workflow--add-hook 'org-agenda-finalize-hook #'org-workflow-agenda--columns-finalize 90)
  (remove-hook 'window-size-change-functions #'org-workflow-agenda--columns-resize)
  (org-workflow--add-hook 'tab-bar-tab-pre-close-functions #'org-workflow-agenda--close-workbench-tab))

(provide 'org-workflow-agenda-layout)
;;; org-workflow-agenda-layout.el ends here
