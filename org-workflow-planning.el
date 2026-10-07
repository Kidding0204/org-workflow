;;; org-workflow-planning.el --- org-workflow-planning Workflow component -*- lexical-binding: t; -*-
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
;;; org-workflow-planning.el --- Project planning context and proposals -*- lexical-binding: t; -*-
(require 'org-workflow-weekly)

(require 'tabulated-list)

(require 'json)

(defun org-workflow-planning--hash ()
  "Return the current buffer's text hash for proposal freshness checks."
  (secure-hash 'sha256 (buffer-substring-no-properties (point-min) (point-max))))

(defun org-workflow-planning--file (file)
  "Validate FILE without widening the set of editable Workflow sources."
  (unless (member (file-truename file) (mapcar #'file-truename (org-agenda-files t)))
    (user-error "不是 Workflow 文件：%s" file))
  (let ((buffer (find-file-noselect file)))
    (with-current-buffer buffer
      (unless (verify-visited-file-modtime buffer)
        (user-error "文件已被外部修改，请同步 buffer 后重新导出"))
      (unless (org-workflow--file-kind) (user-error "不是项目／领域文件")))
    buffer))

(defun org-workflow-planning--background-file (id)
  "Return the independent planning note path for project ID."
  (expand-file-name (concat "planning/" id ".org") (org-workflow--directory)))

(defun org-workflow-planning-background (file &optional position)
  "Create or open FILE's background note for the heading at POSITION.
When POSITION is nil, use the file's top-level identity."
  (interactive (list (completing-read "项目：" (org-agenda-files t) nil t)))
  (let* ((buffer (org-workflow-planning--file file))
         (id (with-current-buffer buffer
               (org-with-wide-buffer (goto-char (or position (point-min))) (org-id-get-create))))
         (title (with-current-buffer buffer
                  (if position (org-with-point-at position (substring-no-properties (org-get-heading t t t t)))
                    (file-name-base file))))
         (target (org-workflow-planning--background-file id)))
    (unless (file-exists-p target)
      (make-directory (file-name-directory target) t)
      (vulpea-create (concat title " · 规划背景") target
                    :tags '("workflow-context")
                    :body (format "项目：[[id:%s][%s]]\n\n* 用户选择：愿景与完成边界\n\n* 来源事实：课程版本、前置知识与资料\n每条注明来源与核对日期。\n\n* 个人经验与规划约定\n\n* AI 推测与待讨论问题\n" id title)))
    (find-file target)))

(defun org-workflow-planning-context (file position)
  "Read FILE's subtree at POSITION and its next sibling as planning context.
No IDs, schedules or database facts are created by this query."
  (with-current-buffer (org-workflow-planning--file file)
    (org-with-wide-buffer
     (goto-char position) (org-back-to-heading t)
     (let* ((start (point))
            (end (save-excursion
                   (unless (org-get-next-sibling) (goto-char start))
                   (org-end-of-subtree t t) (point)))
            (hash (org-workflow-planning--hash))
            (project-id (save-excursion
                          (goto-char start)
                          (let (found)
                            (while (and (not found)
                                        (progn
                                          (when-let* ((id (org-entry-get nil "ID")))
                                            (when (file-exists-p (org-workflow-planning--background-file id))
                                              (setq found id)))
                                          (org-up-heading-safe))))
                            (or found (progn (goto-char (point-min)) (org-entry-get nil "ID"))))))
            tasks)
       (save-restriction
         (narrow-to-region start end)
         (org-map-entries
          (lambda ()
            (push (list :position (point) :id (org-entry-get nil "ID")
                        :title (substring-no-properties (org-get-heading t t t t))
                        :state (org-get-todo-state) :tags (vconcat (org-get-tags))
                        :effort (org-entry-get nil "EFFORT")
                        :boundary (org-entry-get nil "WORKFLOW_BOUNDARY")
                        :depends (or (org-entry-get nil "BLOCKER") (org-entry-get nil "DEPENDS"))
                        :scheduled (org-entry-get nil "SCHEDULED")
                        :resume (org-entry-get nil "WORKFLOW_RESUME")
                        :notes (buffer-substring-no-properties
                                (line-end-position) (save-excursion (outline-next-heading) (point)))) tasks))
          nil nil))
       (let ((background (and project-id (org-workflow-planning--background-file project-id))))
         (list :version 1 :file (expand-file-name file) :hash hash
               :generated (format-time-string "%FT%T%z")
               :background (and background (file-exists-p background) background)
               :weekFile (org-workflow-week-file)
               :recent (vconcat
                        (let ((org-agenda-files (list file)))
                          (mapcar (lambda (offset)
                                    (let ((date (org-workflow-history-add-days (org-workflow-target--today-string) (- offset))))
                                      (list :date date :tasks (vconcat (org-workflow-history--tasks date)))))
                                  (number-sequence 0 6))))
               :tasks (vconcat (nreverse tasks))))))))

(defun org-workflow-planning-context-json (file position)
  "Serialize FILE's planning context at POSITION as UTF-8 JSON text."
  (decode-coding-string (json-serialize (org-workflow-planning-context file position)) 'utf-8))

(defvar-local org-workflow-planning--proposal nil)

(defvar-local org-workflow-planning--selected nil)

(define-derived-mode org-workflow-planning-preview-mode tabulated-list-mode "规划建议"
  "SPC selects a row, a applies selected rows; source edits require a fresh preview."
  (setq tabulated-list-format [("选" 3) ("任务" 26) ("当前 → 建议" 46) ("依据与不确定性" 40)]
        tabulated-list-padding 1)
  (tabulated-list-init-header))

(define-key org-workflow-planning-preview-mode-map (kbd "SPC") #'org-workflow-planning-select)

(define-key org-workflow-planning-preview-mode-map (kbd "a") #'org-workflow-planning-accept)

(defun org-workflow-planning--validate (proposal)
  "Validate PROPOSAL format, source freshness and task metadata."
  (unless (equal (plist-get proposal :version) 1) (user-error "不支持的建议版本"))
  (with-current-buffer (org-workflow-planning--file (plist-get proposal :file))
    (org-with-wide-buffer
     (unless (equal (plist-get proposal :hash) (org-workflow-planning--hash))
       (user-error "项目已经变化，请重新导出与预览"))
     (let ((positions (mapcar (lambda (row) (plist-get row :position)) (plist-get proposal :suggestions))))
       (unless (= (length positions) (length (delete-dups (copy-sequence positions))))
         (user-error "同一任务不可重复建议")))
     (dolist (row (plist-get proposal :suggestions))
       (unless (and (integerp (plist-get row :position))
                    (<= (point-min) (plist-get row :position) (point-max)))
         (user-error "无效的任务位置"))
       (goto-char (plist-get row :position))
       (unless (and (org-at-heading-p)
                    (equal (plist-get row :title) (substring-no-properties (org-get-heading t t t t))))
         (user-error "任务定位已过期"))
       (when-let* ((tag (plist-get row :tag)))
         (unless (member tag '("@deep" "@flow" "@tiny")) (user-error "不支持的标签")))
       (when-let* ((effort (plist-get row :effort)))
         (unless (and (stringp effort) (string-match-p "\\`[0-9]+:[0-5][0-9]\\'" effort))
           (user-error "EFFORT 必须为 H:MM；探索预算不能写入 EFFORT")))
       (dolist (key '(:boundary :reason :uncertainty))
         (when-let* ((value (plist-get row key)))
           (unless (and (stringp value) (not (string-match-p "[\n\r]" value)))
             (user-error "建议字段必须为单行文本"))))))))

(defun org-workflow-planning-preview (file)
  "Read a JSON proposal FILE, validate it and show a selectable preview."
  (interactive "f建议 JSON：")
  (let ((proposal (with-temp-buffer (insert-file-contents file)
                                   (json-parse-buffer :object-type 'plist :array-type 'list
                                                      :null-object nil :false-object nil))))
    (org-workflow-planning--validate proposal)
    (pop-to-buffer "*Workflow 规划建议*")
    (org-workflow-planning-preview-mode)
    (setq org-workflow-planning--proposal proposal org-workflow-planning--selected nil)
    (org-workflow-planning--render)))

(defun org-workflow-planning--render ()
  "Render the current proposal and selection in the preview buffer."
  (setq tabulated-list-entries
        (mapcar (lambda (row)
                  (let ((pos (plist-get row :position))
                        (source (plist-get org-workflow-planning--proposal :file)))
                    (list pos (vector (if (memq pos org-workflow-planning--selected) "✓" "")
                                      (plist-get row :title)
                                      (with-current-buffer (find-file-noselect source)
                                        (org-with-point-at pos
                                          (format "%s / %s / %s → %s / %s / %s"
                                                  (string-join (org-get-tags) ",") (or (org-entry-get nil "EFFORT") "未估时")
                                                  (or (org-entry-get nil "WORKFLOW_BOUNDARY") "无边界")
                                                  (or (plist-get row :tag) "保留") (or (plist-get row :effort) "保留")
                                                  (or (plist-get row :boundary) "保留边界"))))
                                      (format "%s；%s" (or (plist-get row :reason) "") (or (plist-get row :uncertainty) ""))))))
                (plist-get org-workflow-planning--proposal :suggestions)))
  (tabulated-list-print t))

(defun org-workflow-planning-select ()
  "Toggle selection of the proposal row at point."
  (interactive)
  (let ((id (tabulated-list-get-id)))
    (unless id (user-error "请选择建议条目"))
    (if (memq id org-workflow-planning--selected)
        (setq org-workflow-planning--selected (delq id org-workflow-planning--selected))
      (push id org-workflow-planning--selected)))
  (org-workflow-planning--render))

(defun org-workflow-planning-accept (&optional replace)
  "Apply selected rows atomically.  Prefix REPLACE explicitly permits replacing manual values."
  (interactive "P")
  (unless org-workflow-planning--selected (user-error "先用 SPC 选择建议"))
  (org-workflow-planning--validate org-workflow-planning--proposal)
  (unless org-workflow-store-enabled (user-error "请先启用 Workflow 存储"))
  (let* ((proposal org-workflow-planning--proposal)
         (rows (sort (seq-filter (lambda (row) (memq (plist-get row :position) org-workflow-planning--selected))
                                (plist-get proposal :suggestions))
                     (lambda (a b) (> (plist-get a :position) (plist-get b :position))))))
    (when (and replace (not (yes-or-no-p "覆盖所选条目的现有标签、估时及边界?"))) (user-error "已取消"))
    (org-workflow-store--operation
     (lambda ()
       (with-current-buffer (find-file-noselect (plist-get proposal :file))
         (org-with-wide-buffer
          (dolist (row rows)
            (goto-char (plist-get row :position))
            (let* ((tags (org-get-tags)) (local (org-get-tags nil t))
                   (group '("@deep" "@flow" "@tiny")) (tag (plist-get row :tag)))
              (when (and tag (or replace (not (seq-intersection tags group #'equal))))
                (when (and replace (seq-intersection (seq-difference tags local #'equal) group #'equal))
                  (user-error "存在继承标签；请先明确父任务标签"))
                (org-set-tags (cons tag (seq-difference local group #'equal)))))
            (dolist (pair '((:effort . "EFFORT") (:boundary . "WORKFLOW_BOUNDARY")))
              (when-let* ((value (plist-get row (car pair))))
                (when (or replace (not (org-entry-get nil (cdr pair))))
                  (org-entry-put nil (cdr pair) value)))))))))
    (setq org-workflow-planning--proposal nil org-workflow-planning--selected nil)
    (message "已采纳 %d 项建议；保留非空人工设置，源文件尚未保存" (length rows))
    (quit-window)))

(defun org-workflow-planning-set-week-goals (date text)
  "Set only DATE's weekly goals body after the user has chosen TEXT."
  (interactive (list (org-read-date) (read-string "周目标：")))
  (let ((buffer (find-file-noselect (org-workflow-week-ensure date))))
    (with-current-buffer buffer
      (org-with-wide-buffer
       (goto-char (point-min))
       (unless (re-search-forward "^\\* 周目标[ \t]*$" nil t) (user-error "缺少周目标节"))
       (atomic-change-group
         (forward-line 1)
         (let ((start (point)) (end (save-excursion (org-back-to-heading t) (org-end-of-subtree t t) (point))))
           (delete-region start end) (insert "\n" text "\n\n")))))
    (pop-to-buffer buffer)))

(provide 'org-workflow-planning)
;;; org-workflow-planning.el ends here
