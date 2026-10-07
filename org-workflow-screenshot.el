;;; org-workflow-screenshot.el --- note-screenshot Workflow component -*- lexical-binding: t; -*-
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
;;; org-workflow-screenshot.el --- Screenshot collection for current task -*- lexical-binding: t; -*-
(require 'org)

(require 'org-capture)

(require 'org-id)

(require 'subr-x)

(defgroup org-workflow-screenshot nil
  "Collect screenshots in the current Org Workflow task."
  :group 'org)

(defcustom org-workflow-screenshot-helper (executable-find "org-screenshot")
  "Path to the optional desktop screenshot helper."
  :type '(choice (const nil) file) :group 'org-workflow)

(defvar org-workflow-screenshot--clipboard nil)

(declare-function org-workflow-target--require-current "org-workflow-core")

(defun org-workflow-screenshot--location ()
  "Append to the captured task body, before its first child or sibling."
  (let ((marker (org-capture-get :screenshot-marker)))
    (unless (and (markerp marker) (marker-buffer marker))
      (user-error "截图任务已不可用"))
    (set-buffer (marker-buffer marker))
    (widen)
    (goto-char marker)
    ;; Org plain capture appends the body before its first child.
    (org-back-to-heading t)))

(defun org-workflow-screenshot--save-image (image clipboard)
  "Save IMAGE using the portal, or CLIPBOARD when non-nil."
  (unless (and org-workflow-screenshot-helper (file-executable-p org-workflow-screenshot-helper))
    (user-error "Configure org-workflow-screenshot-helper before collecting screenshots"))
  (with-temp-buffer
    (let ((status (apply #'call-process (or (executable-find "python3") (user-error "Python 3 is unavailable")) nil (list t t) nil
                         org-workflow-screenshot-helper
                         (append (when clipboard '("--clipboard")) (list image)))))
      (unless (and (integerp status) (zerop status) (file-exists-p image))
        (user-error "截图未收集：%s" (string-trim (buffer-string)))))))

(defun org-workflow-screenshot--capture-body ()
  "Collect a screenshot before resolving the capture target."
  (let* ((marker (copy-marker (org-workflow-target--require-current)))
         (source (buffer-file-name (marker-buffer marker))))
    (unless (and source (not (file-remote-p source)))
      (user-error "当前任务必须位于本地 Org 文件中"))
    (with-current-buffer (marker-buffer marker)
      (when buffer-read-only (user-error "当前任务文件只读")))
    (let* ((directory (file-name-directory source))
           (images (expand-file-name "doc/images/" directory))
           (image (expand-file-name
                   (concat (format-time-string "%Y%m%d-%H%M%S-")
                           (substring (org-id-new) 0 8) ".png") images)))
      (make-directory images t)
      (org-workflow-screenshot--save-image image org-workflow-screenshot--clipboard)
      ;; Retain the task chosen before screenshot selection, even if focus changes.
      (org-capture-put :screenshot-marker marker)
      (concat "[[file:" (file-relative-name image directory) "]]\n"))))

(defun org-workflow-screenshot-capture (&optional clipboard)
  "Save a screenshot and append its link to the current workflow task.
With prefix CLIPBOARD, collect the PNG already on the Wayland clipboard."
  (interactive "P")
  (when (cl-some (lambda (buffer)
                   (buffer-local-value 'org-capture-mode buffer))
                 (buffer-list))
    (user-error "请先完成或取消当前 Capture"))
  (let ((org-workflow-screenshot--clipboard clipboard)
        ;; No source annotation is needed.  Avoid interactive store-link
        ;; handlers when called by the GNOME shortcut in a daemon frame.
        (org-capture-link-is-already-stored t)
        (org-store-link-plist nil))
    (org-capture nil "S"))
  (message "截图已追加到当前任务"))

(defun org-workflow-screenshot--enable ()
  "Install this component while Workflow is being enabled."
  (setq org-capture-templates
      (cons '("S" "截图 → 当前任务" plain
                  (function org-workflow-screenshot--location)
                  (function org-workflow-screenshot--capture-body)
                  :immediate-finish t :empty-lines 1)
            (assoc-delete-all "S" org-capture-templates)))
  (org-workflow--global-set-key "C-c o S" #'org-workflow-screenshot-capture))

(provide 'org-workflow-screenshot)
;;; org-workflow-screenshot.el ends here
