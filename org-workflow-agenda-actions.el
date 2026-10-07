;;; org-workflow-agenda-actions.el --- note-gtd-agenda-actions Workflow component -*- lexical-binding: t; -*-
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
;;; org-workflow-agenda-actions.el --- Native task actions and refresh boundaries -*- lexical-binding: t; -*-
;;; Commentary:
;; Internal implementation module loaded by org-workflow-agenda.
;;; Code:
(require 'cl-lib)

(require 'org-agenda)

(defun org-workflow-agenda--refile-to-agenda-files (original &rest args)
  "Call ORIGINAL with ARGS using unfinished Agenda headings as refile targets."
  (let* ((verify org-refile-target-verify-function)
         (org-refile-target-verify-function
          (lambda () (and (not (org-entry-is-done-p))
                          (or (null verify) (funcall verify)))))
         (org-refile-targets '((org-agenda-files . t)))
        (org-refile-use-outline-path 'file)
        (org-refile-use-cache nil))
    (apply original args)))

(defun org-workflow-agenda--goto-task (marker)
  "Find MARKER's native Agenda row, returning non-nil when found."
  (let ((position (point-min)) found)
    (while (and (< position (point-max)) (not found))
      (if (equal marker (get-text-property position 'org-hd-marker))
          (setq found position)
        (setq position (next-single-property-change
                        position 'org-hd-marker nil (point-max)))))
    (when found
      (goto-char found)
      ;; Programmatic menu/bulk actions do not run Agenda's cursor update hook.
      (when-let* ((type (get-text-property found 'org-agenda-type)))
        (setq-local org-agenda-type type))
      found)))

(defun org-workflow-agenda--apply-planning (operation)
  "Apply native Agenda OPERATION to marked tasks or the task at point.
Validate every row first, and roll back source buffers if an operation fails."
  (let* ((markers (mapcar #'copy-marker
                         (delete-dups
                          (copy-sequence
                           (or org-agenda-bulk-marked-entries
                               (list (or (org-get-at-bol 'org-hd-marker)
                                         (org-agenda-error))))))))
         (buffers (delete-dups (mapcar #'marker-buffer markers)))
         changes accepted)
    (save-excursion
      (dolist (marker markers)
        (unless (and (marker-buffer marker)
                     (org-workflow-agenda--goto-task marker)
                     (not (invisible-p (point))))
          (user-error "选择中含有失效或隐藏任务，请清除选择后重选"))
        (org-with-point-at marker
          (when (or buffer-read-only (get-text-property (point) 'read-only))
            (user-error "所选任务含只读内容")))))
    (setq changes (mapcan #'prepare-change-group buffers))
    (unwind-protect
        (progn
          (activate-change-group changes)
          (dolist (marker markers)
            (unless (org-workflow-agenda--goto-task marker)
              (user-error "所选任务已离开当前视图"))
            (funcall operation))
          (accept-change-group changes)
          (setq accepted t)
          (when org-agenda-bulk-marked-entries (org-agenda-bulk-unmark-all))
          (org-workflow-agenda--redo-at-task (car markers))
          (when (> (length markers) 1)
            (message "已更新 %d 项安排%s" (length markers)
                     (if (seq-some
                          (lambda (marker)
                            (org-with-point-at marker
                              (when-let* ((date (org-workflow-target--timestamp-date
                                               (org-entry-get nil "SCHEDULED"))))
                                (string< (org-workflow-agenda--date-offset 7) date))))
                          markers)
                         "（部分任务超出未来 7 天视图）" ""))))
      (unless accepted
        (cancel-change-group changes)
        (org-agenda-bulk-unmark-all)
        (org-workflow-target-refresh nil)
        (org-agenda-redo)))))

(defvar-local org-workflow-agenda--native-edit-marker nil)

(defun org-workflow-agenda--refresh-failed-plan (original &rest args)
  "Call ORIGINAL with ARGS and refresh Sprint after a transaction rollback."
  (condition-case failure
      (apply original args)
    ((error quit)
     (when (and (derived-mode-p 'org-agenda-mode)
                (bound-and-true-p org-workflow-agenda--sprint-buffer-p))
       (org-workflow-agenda--clear-selection)
       (condition-case refresh-failure (org-agenda-redo)
         (error (message "安排已回滚；界面刷新失败：%s"
                         (error-message-string refresh-failure)))))
     (signal (car failure) (cdr failure)))))

(defun org-workflow-agenda--refresh-native-edit ()
  "Rebuild Sprint once after a native editing command has fully finished."
  (remove-hook 'post-command-hook #'org-workflow-agenda--refresh-native-edit t)
  (let ((marker org-workflow-agenda--native-edit-marker))
    (setq org-workflow-agenda--native-edit-marker nil)
    (when marker
      (unwind-protect
          (when (and (derived-mode-p 'org-agenda-mode)
                     org-workflow-agenda--sprint-buffer-p)
            (org-agenda-redo)
            (when (marker-buffer marker)
              (org-workflow-agenda--goto-task marker)))
        (set-marker marker nil)))))

(defun org-workflow-agenda--queue-native-refresh (marker)
  "Refresh Sprint after the current command, anchored at MARKER."
  (setq org-workflow-agenda--sprint-buffer-p t)
  (when (markerp org-workflow-agenda--native-edit-marker)
    (set-marker org-workflow-agenda--native-edit-marker nil))
  (setq org-workflow-agenda--native-edit-marker (copy-marker marker))
  (org-workflow--add-hook 'post-command-hook #'org-workflow-agenda--refresh-native-edit nil t))

(defun org-workflow-agenda--track-native-edit (original &rest args)
  "Call ORIGINAL with ARGS and defer Sprint refresh until line updates finish.
Standard Agendas retain Org's incremental rendering."
  (let ((sprint org-workflow-agenda--sprint-buffer-p))
    (prog1 (apply original args)
      (when sprint
        ;; Native line finalization runs outside the custom command bindings.
        (org-workflow-agenda--queue-native-refresh (nth 1 args))))))

(defun org-workflow-agenda--track-native-schedule (original &rest args)
  "Call ORIGINAL with ARGS and refresh Sprint after native scheduling finishes."
  (let* ((sprint (bound-and-true-p org-workflow-agenda--sprint-buffer-p))
         (marker (and sprint (org-get-at-bol 'org-hd-marker))))
    (prog1 (apply original args)
      (when marker (org-workflow-agenda--queue-native-refresh marker)))))

(defun org-workflow-agenda--schedule-and-redo (date)
  "Schedule selected Agenda tasks for DATE, then rebuild the view."
  (org-workflow-agenda--apply-planning (lambda () (org-agenda-schedule nil date))))

(defun org-workflow-agenda-schedule-today ()
  "Schedule the Agenda item at point for today."
  (interactive)
  (org-workflow-agenda--schedule-and-redo (org-workflow-target--today-string)))

(defun org-workflow-agenda-schedule-tomorrow ()
  "Schedule the Agenda item at point for tomorrow."
  (interactive)
  (org-workflow-agenda--schedule-and-redo (org-workflow-agenda--date-offset 1)))

(defun org-workflow-agenda-schedule ()
  "Prompt for a date for the Agenda item, then rebuild the view."
  (interactive)
  (org-workflow-agenda--schedule-and-redo (org-read-date nil nil nil "安排日期")))

(defun org-workflow-agenda-unschedule ()
  "Remove selected tasks' schedules, then rebuild the view."
  (interactive)
  (org-workflow-agenda--apply-planning (lambda () (org-agenda-schedule '(4))))
  (message "已取消所选安排；DIVE 的直接子任务回到待安排区"))

(defun org-workflow-agenda--priority-and-redo (priority)
  "Set selected tasks to PRIORITY through Org's native Agenda command."
  (org-workflow-agenda--apply-planning (lambda () (org-agenda-priority priority))))

(defun org-workflow-agenda-priority-a ()
  "Assign the morning period without changing the scheduled date."
  (interactive)
  (org-workflow-agenda--priority-and-redo ?A))

(defun org-workflow-agenda-priority-b ()
  "Assign the afternoon period without changing the scheduled date."
  (interactive)
  (org-workflow-agenda--priority-and-redo ?B))

(defun org-workflow-agenda-priority-c ()
  "Assign the evening period without changing the scheduled date."
  (interactive)
  (org-workflow-agenda--priority-and-redo ?C))

(defun org-workflow-agenda-priority-clear ()
  "Remove explicit priority, restoring inherited or default priority."
  (interactive)
  (org-workflow-agenda--priority-and-redo 'remove))

(defvar-local org-workflow-agenda-plan-tomorrow nil)

(put 'org-workflow-agenda-plan-tomorrow 'permanent-local t)

(defun org-workflow-agenda-plan-period-label ()
  "Show the selected planning day for direct Agenda operations."
  (if (org-workflow-agenda--setting 'org-workflow-agenda-plan-tomorrow)
      "推进 · 明天" "推进 · 今天"))

(defun org-workflow-agenda--planning-count ()
  "Count distinct selected tasks before a planning operation consumes selection."
  (if org-agenda-bulk-marked-entries
      (length (delete-dups (copy-sequence org-agenda-bulk-marked-entries))) 1))

(defun org-workflow-agenda--plan-period (priority)
  "Schedule selected tasks in PRIORITY using the Agenda's day switch."
  (let ((date (org-workflow-agenda-target-date))
        (count (org-workflow-agenda--planning-count)))
    (org-workflow-agenda--apply-planning
     (lambda () (org-agenda-priority priority) (org-agenda-schedule nil date)))
    (message "已安排 %d 项 → %s %s" count date
             (cdr (assq priority '((?A . "上午") (?B . "下午") (?C . "晚上")))))))

(defun org-workflow-agenda-plan-at (date priority)
  "Arrange the selected tasks at explicit DATE and PRIORITY without switching day."
  (unless (and (stringp date)
               (string-match-p "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\'" date)
               (equal date (org-read-date nil nil date))
               (memq priority '(?A ?B ?C)))
    (user-error "无效的安排日期或时段"))
  (org-workflow-agenda--apply-planning
   (lambda ()
     (unless (org-with-point-at (org-get-at-bol 'org-hd-marker)
               (and (equal date (org-workflow-target--timestamp-date (org-entry-get nil "SCHEDULED")))
                    (eq priority (org-workflow-agenda--priority-letter
                                  (org-workflow--effective-priority-at-point)))))
       (org-agenda-priority priority)
       (org-agenda-schedule nil date)))))

(defcustom org-workflow-agenda-period-tag-groups
  '((?A "@deep") (?B "@tiny") (?C "@flow"))
  "Tag recommendations for morning (A), afternoon (B) and evening (C).
Effective tags include inherited tags.  Multiple matches within one period
are allowed; matches across periods require an explicit manual choice."
  :type '(repeat (cons (choice (const :tag "上午" 65)
                              (const :tag "下午" 66)
                              (const :tag "晚上" 67))
                       (repeat (string :tag "Tag"))))
  :group 'org-agenda)

(defun org-workflow-agenda--recommended-period ()
  "Resolve the current source heading's tags to exactly one period."
  (let* ((tags (org-get-tags))
         (periods (delete-dups
                   (cl-loop for (period . candidates) in org-workflow-agenda-period-tag-groups
                            when (seq-intersection tags candidates #'equal)
                            collect period))))
    (unless (= (length periods) 1)
      (user-error "%s：%s，请手动选择时段或调整标签映射"
                  (if periods "标签匹配多个时段" "没有匹配的推荐时段")
                  (org-get-heading t t t t)))
    (unless (memq (car periods) '(?A ?B ?C))
      (user-error "推荐时段必须是 A、B 或 C"))
    (car periods)))

(defun org-workflow-agenda-plan-recommended ()
  "Plan each selected task by its tags, respecting the Agenda's day switch."
  (interactive)
  (let ((date (org-workflow-agenda-target-date)))
    (org-workflow-agenda--apply-planning
     (lambda ()
       (let ((period (org-with-point-at (org-get-at-bol 'org-hd-marker)
                       (org-workflow-agenda--recommended-period))))
         (org-agenda-priority period)
         (org-agenda-schedule nil date))))))

(defun org-workflow-agenda-plan-morning ()
  "Plan morning using the Agenda's selected day."
  (interactive) (org-workflow-agenda--plan-period ?A))

(defun org-workflow-agenda-plan-afternoon ()
  "Plan afternoon using the Agenda's selected day."
  (interactive) (org-workflow-agenda--plan-period ?B))

(defun org-workflow-agenda-plan-evening ()
  "Plan evening using the Agenda's selected day."
  (interactive) (org-workflow-agenda--plan-period ?C))

(defun org-workflow-agenda--move-in-period (direction)
  "Move the current planned task by DIRECTION within its day and period."
  (when org-agenda-bulk-marked-entries
    (user-error "排序只操作当前任务，请先清除批量选择"))
  (when org-agenda-tag-filter
    (user-error "请先清除标签筛选，以免跨过隐藏任务"))
  (let* ((marker (copy-marker (or (org-get-at-bol 'org-hd-marker) (org-agenda-error))))
         (entries (org-workflow-target--ordered-entries (org-workflow-agenda--date-offset 7)))
         (entry (seq-find (lambda (item) (equal marker (org-workflow-target-entry-marker item))) entries)))
    (unless entry (user-error "请选择今日安排或未来 7 天中的任务"))
    (let* ((scope (org-workflow--order-scope entry))
           (peers (seq-filter (lambda (item) (equal scope (org-workflow--order-scope item))) entries))
           (index (cl-position entry peers))
           (other (+ index direction)))
      (unless (< -1 other (length peers))
        (user-error "已经位于该时段的%s" (if (< direction 0) "顶部" "底部")))
      (cl-rotatef (nth index peers) (nth other peers))
      (let* ((buffers (delete-dups (mapcar (lambda (item) (marker-buffer (org-workflow-target-entry-marker item))) peers)))
             changes accepted)
        (dolist (item peers)
          (org-with-point-at (org-workflow-target-entry-marker item)
            (when (or buffer-read-only (get-text-property (point) 'read-only))
              (user-error "该时段含只读任务，无法保存完整排序"))))
        (setq changes (mapcan #'prepare-change-group buffers))
        (unwind-protect
            (progn
              (activate-change-group changes)
              (cl-loop for item in peers for rank from 0 do
                       (org-with-point-at (org-workflow-target-entry-marker item)
                         (org-entry-put nil "WORKFLOW_ORDER"
                                        (format "%c/%d" (org-workflow--priority-character
                                                         (org-workflow-target-entry-priority item)) rank))
                         (org-entry-delete nil "WORKFLOW_ORDER_SCOPE")))
              (accept-change-group changes)
              (setq accepted t))
          (unless accepted (cancel-change-group changes)))
        (org-workflow-target-refresh t)
        (org-workflow-agenda--redo-at-task marker)))))

(defun org-workflow-agenda-move-up ()
  "Move the task up within its day and period in Agenda and Workflow."
  (interactive) (org-workflow-agenda--move-in-period -1))

(defun org-workflow-agenda-move-down ()
  "Move the task down within its day and period in Agenda and Workflow."
  (interactive) (org-workflow-agenda--move-in-period 1))

(defun org-workflow-agenda--schedule-today-period (priority)
  "Assign today and PRIORITY to the Agenda leaf in one source undo group."
  (org-workflow-agenda--apply-planning
   (lambda ()
     (org-agenda-priority priority)
     (org-agenda-schedule nil (org-workflow-target--today-string)))))

(defun org-workflow-agenda-today-morning ()
  "Arrange the task for this morning."
  (interactive)
  (org-workflow-agenda--schedule-today-period ?A))

(defun org-workflow-agenda-today-afternoon ()
  "Arrange the task for this afternoon."
  (interactive)
  (org-workflow-agenda--schedule-today-period ?B))

(defun org-workflow-agenda-today-evening ()
  "Arrange the task for this evening."
  (interactive)
  (org-workflow-agenda--schedule-today-period ?C))

(defun org-workflow-agenda-schedule-today-mouse (event)
  "Schedule the Agenda item clicked by mouse EVENT for today."
  (interactive "e")
  (mouse-set-point event)
  (when org-agenda-bulk-marked-entries (org-agenda-bulk-unmark-all))
  (org-workflow-agenda-schedule-today))

(defun org-workflow-agenda--exclusive-tag-groups ()
  "Read exclusive groups from the current Org tag table."
  (let (groups group collecting)
    (dolist (entry (or org-current-tag-alist org-tag-alist))
      (pcase (car entry)
        (:startgroup (setq group nil collecting t))
        (:endgroup
         (when collecting (push (nreverse group) groups))
         (setq group nil collecting nil))
        ((pred stringp) (when collecting (push (car entry) group)))))
    (nreverse groups)))

(defun org-workflow-agenda--add-tag (tag)
  "Toggle direct TAG on each selected task, respecting Org exclusive groups.
Inherited tags remain owned by their parent headings or file."
  (org-workflow-agenda--apply-planning
   (lambda ()
     (org-with-point-at (org-get-at-bol 'org-hd-marker)
       (org-set-tags
        (org--add-or-remove-tag tag (copy-sequence (org-get-tags nil t))
                                (org-workflow-agenda--exclusive-tag-groups)))))))

(defun org-workflow-agenda-add-promise-tag ()
  "Toggle promise on selected tasks."
  (interactive) (org-workflow-agenda--add-tag "promise"))

(defun org-workflow-agenda-add-flow-tag ()
  "Toggle @flow on selected tasks, replacing exclusive alternatives."
  (interactive) (org-workflow-agenda--add-tag "@flow"))

(defun org-workflow-agenda-add-tiny-tag ()
  "Toggle @tiny on selected tasks, replacing exclusive alternatives."
  (interactive) (org-workflow-agenda--add-tag "@tiny"))

(defun org-workflow-agenda-add-deep-tag ()
  "Toggle @deep on selected tasks, replacing exclusive alternatives."
  (interactive) (org-workflow-agenda--add-tag "@deep"))

(defun org-workflow-agenda--filter-tag (tag)
  "Show only effective TAG in this Agenda, clearing stale bulk selection."
  (org-workflow-agenda--clear-selection)
  (let ((buffers (or (org-workflow-agenda--workbench-buffers) (list (current-buffer))))
        (org-workflow-agenda-sprint-view org-workflow-agenda--sprint-buffer-p)
        (org-workflow-agenda--laying-out-columns t))
    (dolist (buffer buffers)
      (with-current-buffer buffer (org-agenda-filter-show-all-tag)))
    (org-workflow-agenda--set-setting 'org-agenda-tag-filter (and tag (list (concat "+" tag))))
    (when tag
      (dolist (buffer buffers)
        (with-current-buffer buffer (org-agenda-filter-apply org-agenda-tag-filter 'tag)))))
  (message "%s；时段统计为完整安排总量"
           (if tag (concat "仅显示 " tag) "已清除标签筛选")))

(defun org-workflow-agenda-filter-tiny ()
  "Show tiny tasks."
  (interactive) (org-workflow-agenda--filter-tag "@tiny"))

(defun org-workflow-agenda-filter-flow ()
  "Show flow tasks."
  (interactive) (org-workflow-agenda--filter-tag "@flow"))

(defun org-workflow-agenda-filter-deep ()
  "Show deep tasks."
  (interactive) (org-workflow-agenda--filter-tag "@deep"))

(defun org-workflow-agenda-filter-promise ()
  "Show effective promise tasks, including inherited tags."
  (interactive) (org-workflow-agenda--filter-tag "promise"))

(defun org-workflow-agenda-filter-clear ()
  "Remove the tag filter."
  (interactive) (org-workflow-agenda--filter-tag nil))

(defun org-workflow-agenda-selection-label ()
  "Describe the scope of the planning menu before applying an action."
  (if org-agenda-bulk-marked-entries
      (format "操作已选 %d 项" (length org-agenda-bulk-marked-entries))
    "操作当前任务"))

(defun org-workflow-agenda-actions--enable ()
  "Install this component while Workflow is being enabled."
  (org-workflow--advice-add 'org-agenda-refile :around #'org-workflow-agenda--refile-to-agenda-files)
  (org-workflow--advice-add 'org-workflow-agenda--apply-planning :around
            #'org-workflow-agenda--refresh-failed-plan '((depth . -100)))
  (org-workflow--advice-add 'org-agenda-change-all-lines :around #'org-workflow-agenda--track-native-edit)
  (org-workflow--advice-add 'org-agenda-schedule :around #'org-workflow-agenda--track-native-schedule))

(provide 'org-workflow-agenda-actions)
;;; org-workflow-agenda-actions.el ends here
