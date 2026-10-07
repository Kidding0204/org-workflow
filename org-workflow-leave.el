;;; org-workflow-leave.el --- org-workflow-leave Workflow component -*- lexical-binding: t; -*-
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
;;; org-workflow-leave.el --- Explicit activity explanations -*- lexical-binding: t; -*-
;;; Commentary:
;; Leave is context, not task completion, scheduling, or measured work.
;;; Code:
(require 'org-workflow-core)

(require 'org-workflow-weekly)

(defconst org-workflow-leave--slots
  '(("morning" "上午" ?A) ("afternoon" "下午" ?B) ("evening" "晚上" ?C)))

(defun org-workflow-leave--past-tasks (date)
  "Read unfinished DATE commitments, never infer yesterday from today's queue.
Historical settlements do not preserve task IDs or time slots."
  (let ((day (org-workflow-store-day date)))
    (vconcat
     (if day
         (seq-keep (lambda (task)
                     (unless (or (equal (plist-get task :outcome) "done")
                                 (eq (plist-get task :satisfied) t))
                       (list :id :null :task (plist-get task :task) :slot :null)))
                   (plist-get day :minimumTasks))
       (seq-keep (lambda (row)
                   (unless (org-workflow-history--commitment-satisfied-p row date)
                     (list :id (nth 1 row) :task (nth 5 row) :slot :null)))
                 (org-workflow-history--responsibilities date))))))

(defun org-workflow-leave--read-input (date &optional required)
  "Read slots and a non-empty reason for DATE.  REQUIRED identifies a catch-up."
  (let* ((choice (completing-read (format "%s%s请假时段：" date (if required " 补录 · " " · "))
                                  '("上午" "下午" "晚上" "全天" "上午、下午" "下午、晚上" "上午、晚上")
                                  nil t nil nil "全天"))
         (slots (if (equal choice "全天") (mapcar #'car org-workflow-leave--slots)
                  (mapcar (lambda (label)
                            (car (seq-find (lambda (slot) (equal label (cadr slot)))
                                           org-workflow-leave--slots)))
                          (split-string choice "、" t))))
         reason)
    (while (or (not reason) (string-empty-p (string-trim reason)))
      (setq reason (read-string (format "%s %s：" date (if required "未完成承诺的原因（必填）" "请假理由")))))
    (list slots reason date)))

(defun org-workflow-leave--tasks (slots)
  "Snapshot all unfinished queue entries in SLOTS without changing their IDs."
  (let ((entries (org-workflow-target--ordered-entries)) tasks)
    (unwind-protect
        (dolist (entry entries)
          (let* ((priority (org-workflow-target-entry-priority entry))
                 (slot (seq-find
                        (lambda (item)
                          (= priority (org-get-priority (format "[#%c]" (nth 2 item)))))
                        org-workflow-leave--slots)))
            (when (and (member (car slot) slots)
                       (not (org-workflow-history-attempted-p
                             (org-workflow-target--today-string) (org-workflow-target-entry-marker entry))))
              (push (list :id (or (org-with-point-at (org-workflow-target-entry-marker entry)
                                   (org-entry-get nil "ID")) :null)
                          :task (substring-no-properties (org-workflow-target-entry-title entry))
                          :slot (car slot)) tasks))))
      (dolist (entry entries)
        (set-marker (org-workflow-target-entry-marker entry) nil)
        (set-marker (org-workflow-target-entry-group-marker entry) nil)))
    (vconcat (nreverse tasks))))

(defun org-workflow-leave--write (record file)
  "Append RECORD under FILE's notes heading and write the database fact."
  (with-current-buffer (find-file-noselect file)
    (org-with-wide-buffer
     (goto-char (point-min))
     (unless (re-search-forward "^\\* 随记[ \t]*$" nil t)
       (goto-char (point-max)) (insert "\n* 随记\n"))
     (beginning-of-line) (org-end-of-subtree t t)
     (unless (bolp) (insert "\n"))
     (insert (format "\n** %s 请假条 · %s\n:PROPERTIES:\n:WORKFLOW_LEAVE_ID: %s\n:WORKFLOW_LEAVE_DATE: %s\n:WORKFLOW_LEAVE_SLOTS: %s\n:END:\n%s\n"
                     (plist-get record :date)
                     (mapconcat (lambda (slot) (cadr (assoc slot org-workflow-leave--slots)))
                                (append (plist-get record :slots) nil) "、")
                     (plist-get record :id) (plist-get record :date)
                     (mapconcat #'identity (plist-get record :slots) " ")
                     (org-escape-code-in-string (plist-get record :reason))))
     (when (> (length (plist-get record :tasks)) 0)
       (insert "\n涉及的未完成任务：\n")
       (seq-doseq (task (plist-get record :tasks))
         (insert (format "- %s · %s\n"
                         (or (cadr (assoc (plist-get task :slot) org-workflow-leave--slots)) "时段未记录")
                         (plist-get task :task)))))
     (org-workflow-store-put-leave record))))

(defun org-workflow-record-leave (slots reason &optional date)
  "Record REASON for SLOTS on DATE (default today), leaving tasks unchanged.
With a prefix, interactively choose a past date.  Past task snapshots come
from historical commitments, not mutable source schedules."
  (interactive
   (org-workflow-leave--read-input
    (if current-prefix-arg (org-read-date nil nil nil "补录日期：")
      (org-workflow-target--today-string))))
  (unless org-workflow-store-enabled (user-error "请先启用 Workflow 数据库"))
  (setq date (or date (org-workflow-target--today-string)))
  (org-workflow-history-add-days date 0)
  (when (string< (org-workflow-target--today-string) date) (user-error "不能提前填写未来日期的原因"))
  (unless (and (listp slots) slots
               (seq-every-p (lambda (slot) (assoc slot org-workflow-leave--slots)) slots))
    (user-error "请选择有效的请假时段"))
  (when (stringp reason)
    (setq reason (string-trim reason)))
  (unless (and (stringp reason) (not (string-empty-p reason))
               (not (string-search (string 10) reason))
               (not (string-search (string 13) reason)))
    (user-error "请填写一行非空的请假理由"))
  (let* ((slots (seq-filter (lambda (slot) (member slot slots))
                            (mapcar #'car org-workflow-leave--slots)))
         (record (list :id (org-id-new) :date date :slots (vconcat slots)
                       :reason reason
                       :recordedAt (format-time-string "%Y-%m-%dT%H:%M:%S%:z")
                       :tasks (if (equal date (org-workflow-target--today-string))
                                  (org-workflow-leave--tasks slots)
                                (org-workflow-leave--past-tasks date))))
         (file (org-workflow-week-ensure date))
         (org-workflow-store--extra-source-files (list file)))
    (with-current-buffer (find-file-noselect file)
      (when buffer-read-only (user-error "周随记只读，未记录请假条")))
    (org-workflow-store--operation #'org-workflow-leave--write record file)
    ;; Save only this journal after the database commit.  A failed save leaves
    ;; the existing recovery image intact, rather than losing the record.
    (with-current-buffer (find-file-noselect file) (save-buffer))
    (when (fboundp 'org-workflow-panel-invalidate) (org-workflow-panel-invalidate))
    (org-workflow--request-gnome-refresh)
    (message "已记录 %s 请假条（%d 项未完成任务），未修改安排" date (length (plist-get record :tasks)))
    record))

(defun org-workflow-leave--required-date ()
  "Return yesterday when its commitments were unmet and have no explanation."
  (when org-workflow-store-enabled
    (let* ((date (org-workflow-history-add-days (org-workflow-target--today-string) -1))
           (day (org-workflow-store-day date)))
      (when (and (= 0 (length (org-workflow-store-leaves date)))
                 (if day (equal (plist-get day :commitment) "unmet")
                   (> (length (org-workflow-leave--past-tasks date)) 0)))
        date))))

(defvar org-workflow-leave--prompting nil)

(defvar org-workflow-leave--startup-timer nil)

(defvar org-workflow-leave--checked-day nil)

(defun org-workflow-leave-check-yesterday ()
  "Require yesterday's missing explanation, without offering a skip choice.
Quit never records a reason or marks the requirement as handled."
  (interactive)
  (unless org-workflow-leave--prompting
    (let ((org-workflow-leave--prompting t)
          (checked-date (org-workflow-target--today-string)))
      (when-let* ((date (org-workflow-leave--required-date)))
        (apply #'org-workflow-record-leave (org-workflow-leave--read-input date t)))
      (setq org-workflow-leave--checked-day checked-date))))

(defun org-workflow-leave--startup-check (frame)
  "Prompt only after FRAME is ready, outside daemon startup and nested input."
  (setq org-workflow-leave--startup-timer nil)
  (when (and (frame-live-p frame)
             (or (not (display-graphic-p frame)) (eq t (frame-focus-state frame))))
    (if (active-minibuffer-window)
        (setq org-workflow-leave--startup-timer
              (run-with-idle-timer 1 nil #'org-workflow-leave--startup-check frame))
      (with-selected-frame frame
        (condition-case err (org-workflow-leave-check-yesterday)
          (quit (message "昨天的原因尚未补录，下次打开 Emacs 时仍会要求填写"))
          (error (message "请假补录未完成：%s" (error-message-string err))))))))

(defun org-workflow-leave--startup ()
  "Queue one check for an ordinary interactive startup or client frame."
  (unless (or noninteractive (not after-init-time) (not org-workflow-store-enabled)
              org-workflow-leave--prompting
              (equal org-workflow-leave--checked-day (org-workflow-target--today-string))
              (timerp org-workflow-leave--startup-timer)
              (member (frame-parameter nil 'name) '("capture" "workflow-select"))
              (and (daemonp) (not (frame-parameter nil 'client))))
    (setq org-workflow-leave--startup-timer
          (run-with-idle-timer 0.5 nil #'org-workflow-leave--startup-check (selected-frame)))))

(defun org-workflow-leave--focus-check ()
  "Also check an existing daemon frame when it is reopened on a new day."
  (when-let* ((frame (seq-find (lambda (candidate)
                                (and (eq t (frame-focus-state candidate))
                                     (not (member (frame-parameter candidate 'name)
                                                  '("capture" "workflow-select")))))
                              (cons (selected-frame) (delq (selected-frame) (frame-list))))))
    (with-selected-frame frame (org-workflow-leave--startup))))

(defun org-workflow-leave--enable ()
  "Install this component while Workflow is being enabled."
  (org-workflow--add-hook 'emacs-startup-hook #'org-workflow-leave--startup 90)
  (org-workflow--add-hook 'server-after-make-frame-hook #'org-workflow-leave--startup 90)
  (org-workflow--advise-variable 'after-focus-change-function :after #'org-workflow-leave--focus-check))

(provide 'org-workflow-leave)
;;; org-workflow-leave.el ends here
