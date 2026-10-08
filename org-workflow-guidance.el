;;; org-workflow-guidance.el --- org-workflow-guidance Workflow component -*- lexical-binding: t; -*-
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
;;; org-workflow-guidance.el --- Planning text, never duplicate task state -*- lexical-binding: t; -*-
(require 'org-workflow-weekly)

(require 'org-workflow-planning)
(require 'org-workflow-sources)

(defcustom org-workflow-guidance-file nil
  "Guidance source; nil uses the configured miscellaneous projects file."
  :type '(choice (const :tag "Miscellaneous projects file" nil) file)
  :group 'org-workflow)

(defun org-workflow-guidance--read (file function)
  "Call FUNCTION in existing FILE without creating a document."
  (when (file-exists-p file)
    (unless (file-readable-p file) (error "Cannot read %s" file))
    (org-workflow-source-read file function)))

(defun org-workflow-guidance-opening (date)
  "Return the opening hint explicitly recorded for DATE, or nil."
  (org-workflow-guidance--read
   (org-workflow-week-file date)
   (lambda ()
     (let (text)
       (org-map-entries
        (lambda () (when (equal date (org-entry-get nil "WORKFLOW_START_DATE"))
                     (setq text (org-entry-get nil "WORKFLOW_START_HINT")))) nil 'file)
       text))))

(defun org-workflow-guidance-edit-tomorrow ()
  "Edit tomorrow's one-line opening hint in its weekly journal."
  (interactive)
  (let* ((date (org-workflow-history-add-days (org-workflow-target--today-string) 1))
         (text (read-string (format "%s 开工提示：" date) (org-workflow-guidance-opening date))))
    (when (string-match-p "[\n\r]" text) (user-error "请用一句话填写"))
    (when (or (not (string-empty-p text)) (org-workflow-guidance-opening date))
      (with-current-buffer (find-file-noselect (org-workflow-week-ensure date))
        (org-with-wide-buffer
         (let (location)
           (org-map-entries (lambda () (when (equal date (org-entry-get nil "WORKFLOW_START_DATE"))
                                        (setq location (point)))) nil 'file)
           (unless location
             (goto-char (point-min))
             (unless (re-search-forward "^\\* 随记[ \t]*$" nil t) (user-error "缺少随记节"))
             (org-end-of-subtree t t)
             (unless (bolp) (insert "\n"))
             (setq location (point)) (insert "** 开工提示 · " date "\n")
             (goto-char location) (org-entry-put nil "WORKFLOW_START_DATE" date))
           (goto-char location)
           (if (string-empty-p text) (org-entry-delete nil "WORKFLOW_START_HINT")
             (org-entry-put nil "WORKFLOW_START_HINT" text))
           (save-buffer)))))
    (org-workflow--request-gnome-refresh)))

(defun org-workflow-guidance--file ()
  "Return the guidance note path in the configured notes directory."
  (expand-file-name (or org-workflow-guidance-file org-workflow-projects-file)))

(defun org-workflow-guidance-open ()
  "Visit the guidance note, creating a minimal document if absent."
  (interactive)
  (let ((file (org-workflow-guidance--file)))
    (unless (file-exists-p file)
      (make-directory (file-name-directory file) t)
      (vulpea-create "杂项" file :tags '("project")
                    :body "* 实践指导\n** 指导\n添加自己的指导标题；在选中的标题运行 org-workflow-guidance-select。\n"))
    (find-file file)
    (widen)
    (goto-char (org-workflow-source-section "实践指导" t))
    (org-fold-show-entry)
    (org-narrow-to-subtree)))

(defun org-workflow-guidance-select ()
  "Select the guidance heading at point, without rotation."
  (interactive)
  (unless (equal (file-truename (or buffer-file-name "")) (file-truename (org-workflow-guidance--file)))
    (user-error "请在实践指导笔记中选择标题"))
  (let ((marker (point-marker)))
    (atomic-change-group
      (save-restriction
	(widen)
	(let ((position (org-workflow-source-section "实践指导")))
          (unless position (user-error "缺少实践指导节"))
          (goto-char position) (org-narrow-to-subtree)
          (unless (and (<= (point-min) marker) (< marker (point-max)))
            (user-error "请在实践指导节中选择标题")))
	(org-map-entries (lambda () (org-entry-delete nil "WORKFLOW_GUIDANCE_SELECTED")) nil 'tree)
	(org-with-point-at marker (org-entry-put nil "WORKFLOW_GUIDANCE_SELECTED" "t"))))
    (save-buffer))
  (org-workflow--request-gnome-refresh))

(defun org-workflow-guidance-current ()
  "Return the selected guidance heading text, or nil when none is selected."
  (org-workflow-guidance--read
   (org-workflow-guidance--file)
   (lambda ()
     (let (text)
       (when-let* ((position (org-workflow-source-section "实践指导")))
         (goto-char position)
         (org-narrow-to-subtree)
	 (org-map-entries
          (lambda () (when (org-entry-get nil "WORKFLOW_GUIDANCE_SELECTED")
                       (setq text (substring-no-properties (org-get-heading t t t t))))) nil 'tree))
       text))))

(defun org-workflow-guidance-edit-resume ()
  "Edit the selected task's one-line reminder for resuming work."
  (interactive)
  (let ((marker (if (derived-mode-p 'org-agenda-mode) (org-get-at-bol 'org-hd-marker) (point-marker))))
    (unless marker (user-error "请选择任务"))
    (org-with-point-at marker
      (let ((text (read-string "下次从这里开始：" (org-entry-get nil "WORKFLOW_RESUME"))))
        (when (string-match-p "[\n\r]" text) (user-error "请用一句话填写"))
        (if (string-empty-p text) (org-entry-delete nil "WORKFLOW_RESUME")
          (org-entry-put nil "WORKFLOW_RESUME" text)))))
  (org-workflow--request-gnome-refresh))

(provide 'org-workflow-guidance)
;;; org-workflow-guidance.el ends here
