;;; org-workflow-habits.el --- org-workflow-habits Workflow component -*- lexical-binding: t; -*-
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
;;; org-workflow-habits.el --- Independent native Org habits -*- lexical-binding: t; -*-
(require 'org-habit)
(require 'org-workflow-periods)
(require 'org-workflow-items)
(require 'org-workflow-store)

(require 'org-clock)

(require 'org-id)

(require 'cl-lib)

(require 'seq)

(require 'subr-x)

(defgroup org-workflow-habits nil "Independent habits and daily facts." :group 'org)

(defcustom org-workflow-habit-file nil
  "Dedicated habit source, or nil to resolve the configured notes directory.
The default is resolved when used, after note configuration has loaded.
It is not added to Workflow's Agenda scope."
  :type '(choice (const :tag "In the configured notes directory" nil) file)
  :group 'org-workflow-habits)

(defun org-workflow-habits-file ()
  "Resolve the source without capturing load order or the visited directory."
  (expand-file-name
   (or org-workflow-habit-file
       (expand-file-name "habits.org"
                         (or org-workflow-directory
                             (bound-and-true-p vulpea-default-notes-directory)
                             (car (bound-and-true-p vulpea-db-sync-directories))
                             org-directory)))))

(defvar org-workflow-habits-saved-hook nil
  "Run after a habit source has been saved; database adapters may synchronize.")

(defun org-workflow-habit-p ()
  "Whether the current heading is a native habit, without inheriting STYLE."
  (equal (org-entry-get nil "STYLE") "habit"))

(defun org-workflow-habits-files ()
  "Existing habit sources, including habits moved into Agenda files."
  (delete-dups (cons (org-workflow-habits-file) (org-agenda-files t))))

(defun org-workflow-habits--map (function)
  "Call FUNCTION on each native habit with bounded, cache-free source reads."
  (let ((org-element-use-cache nil))
    (dolist (file (org-workflow-habits-files))
      (when (file-exists-p file)
        (unless (file-readable-p file) (error "Unreadable habit source: %s" file))
        (with-current-buffer (find-file-noselect file)
          (org-with-wide-buffer
           (org-map-entries
            (lambda () (when (org-workflow-habit-p) (funcall function))) nil 'file)))))))

(defun org-workflow-habits--direct-end ()
  "Return the position of the next heading, excluding nested habit content."
  (save-excursion (outline-next-heading) (point)))

(defun org-workflow-habits-records (date)
  "Read DATE's habit facts through the shared item day-record pipeline."
  (let (records)
    (org-workflow-habits--map
     (lambda ()
       (when-let* ((record (org-workflow-item-day-record
                           (org-workflow-item-at-marker (point-marker) date) date)))
         (let ((id (plist-get record :id)))
           (unless id (user-error "习惯缺少 ID：%s；请创建 ID 并保存" (plist-get record :task)))
           (when (seq-find (lambda (row) (equal id (plist-get row :id))) records)
             (error "Duplicate habit ID: %s" id))
           (push record records)))))
    (nreverse records)))

(defun org-workflow-habits-items (date)
  "Return native habit items due or completed on DATE."
  (let ((day (time-to-days (org-time-string-to-time (concat date " 12:00")))) items)
    (when (and org-workflow-store-enabled (org-workflow-store-meta "habit-source")
               (not (file-readable-p (org-workflow-habits-file))))
      (error "Habit source unavailable"))
    (org-workflow-habits--map
     (lambda ()
       (unless (org-entry-is-done-p)
         (let* ((habit (org-habit-parse-todo))
                (done (memq day (org-habit-done-dates habit))))
           (when (or done (<= (org-habit-scheduled habit) day))
             (let ((item (org-workflow-item-at-marker (point-marker) date)))
               (setf (org-workflow-target-entry-done item) (and done t)
                     (org-workflow-target-entry-habit-position item) (org-workflow-habits-position)
                     (org-workflow-target-entry-reminder-time item) (org-workflow-habits-reminder-clock))
               (push item items)))))))
    (nreverse items)))

(defun org-workflow-habits-current-item ()
  "Return the latest reminded occurrence, independent of UI presentation."
  (when org-workflow-store-enabled
    (let* ((date (org-workflow-target--today-string))
           (state (org-workflow-store--decode
                   (org-workflow-store-meta (concat "habit-reminders:" date))))
           (key (plist-get state :current)))
      (when key
        (seq-find (lambda (item) (and (equal key (org-workflow-item-key item))
                                     (not (org-workflow-target-entry-done item))))
                  (org-workflow-habits-items date))))))

(defun org-workflow-habits-skip-item (item)
  "Suppress ITEM's habit occurrence today without altering completion facts."
  (unless (eq (org-workflow-target-entry-kind item) 'habit)
    (user-error "普通任务不使用习惯跳过规则"))
  (let* ((date (org-workflow-target--today-string))
         (key (org-workflow-item-key item))
         (meta-key (concat "habit-reminders:" date))
         (state (org-workflow-store--decode (org-workflow-store-meta meta-key))))
    (unless (equal date (org-workflow-target-entry-occurrence-date item))
      (user-error "习惯本次执行日期已经变化"))
    (setq state (plist-put state :skipped
                           (vconcat (delete-dups (cons key (append (plist-get state :skipped) nil))))))
    (when (equal key (plist-get state :current)) (setq state (plist-put state :current nil)))
    (org-workflow-store-set-meta meta-key (org-workflow-store--encode state))))

(defun org-workflow-habits-dates ()
  "Enumerate dates covered by native habit logs and clocks, including clock spans."
  (let ((dates (list (format-time-string "%F"))))
    (org-workflow-habits--map
     (lambda ()
       (save-excursion
         (save-restriction
           (narrow-to-region (point) (org-workflow-habits--direct-end))
           (while (re-search-forward "\\[\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" nil t)
             (push (match-string-no-properties 1) dates))))))
    ;; Include intervening dates so a multi-day CLOCK is split correctly.
    (let* ((first (car (sort dates #'string<)))
           (time (org-time-string-to-time (concat first " 00:00")))
           (today (format-time-string "%F")) result)
      (while (not (string< today (format-time-string "%F" time)))
        (push (format-time-string "%F" time) result)
        (let ((parts (decode-time time)))
          (setq time (encode-time 0 0 0 (1+ (nth 3 parts)) (nth 4 parts) (nth 5 parts)))))
      (nreverse result))))

(defun org-workflow-habits-open ()
  "Visit the independent habit source, creating a minimal document if absent."
  (interactive)
  (unless (file-exists-p (org-workflow-habits-file))
    (make-directory (file-name-directory (org-workflow-habits-file)) t)
    (with-temp-file (org-workflow-habits-file)
      (insert "#+title: 习惯\n#+TODO: TODO | DONE\n#+STARTUP: logrepeat\n#+PROPERTY: LOGGING logrepeat\n\n")))
  (find-file (org-workflow-habits-file)))

(defconst org-workflow-habits-positions
  '(("上午·初" morning early "morning-early")
    ("上午·末" morning late "morning-late")
    ("下午·初" afternoon early "afternoon-early")
    ("下午·末" afternoon late "afternoon-late")
    ("晚上·初" evening early "evening-early")
    ("晚上·末" evening late "evening-late"))
  "Habit position labels, window names, edges and Org property values.")

(defun org-workflow-habits-position ()
  "Return the current habit's configured position, or nil when unassigned."
  (let ((value (org-entry-get nil "WORKFLOW_HABIT_POSITION")))
    (when value
      (or (seq-find (lambda (item) (equal value (nth 3 item)))
                    org-workflow-habits-positions)
          (user-error "未知习惯位置：%s" value)))))

(defun org-workflow-habits-reminder-clock ()
  "Return the current habit's override clock or work-window boundary."
  (let ((override (org-entry-get nil "WORKFLOW_HABIT_REMINDER"))
        (position (org-workflow-habits-position)))
    (when override (org-workflow-periods--minutes override))
    (or override (and position (org-workflow-periods-clock
                                (nth 1 position) (nth 2 position))))))

(defun org-workflow-habits-configure ()
  "Set the selected habit's position and optional reminder clock."
  (interactive)
  (let* ((marker (org-workflow-habits--marker))
         (position (org-with-point-at marker (org-workflow-habits-position)))
         (label (completing-read "习惯位置：" (cons "未设置" (mapcar #'car org-workflow-habits-positions))
                                 nil t nil nil (or (car position) "未设置")))
         (value (nth 3 (assoc label org-workflow-habits-positions)))
         (clock (string-trim (read-string "提醒钟点（HH:MM，留空跟随时段）："
                                         (org-with-point-at marker
                                           (org-entry-get nil "WORKFLOW_HABIT_REMINDER"))))))
    ;; Validate all input before touching the source.
    (unless (string-empty-p clock) (org-workflow-periods--minutes clock))
    (org-with-point-at marker
      (if value (org-entry-put nil "WORKFLOW_HABIT_POSITION" value)
        (org-entry-delete nil "WORKFLOW_HABIT_POSITION"))
      (if (string-empty-p clock) (org-entry-delete nil "WORKFLOW_HABIT_REMINDER")
        (org-entry-put nil "WORKFLOW_HABIT_REMINDER" clock))
      (save-buffer))
    (when (derived-mode-p 'org-agenda-mode) (org-agenda-redo))))

(defun org-workflow-habits-create (title)
  "Create a native daily habit with TITLE and a stable ID."
  (interactive (list (read-string "习惯（完成标准）：")))
  (when (string-match-p "[\n\r]" title) (user-error "习惯标题必须为一行"))
  (when (string-empty-p (string-trim title)) (user-error "请输入习惯标题"))
  (org-workflow-habits-open)
  (goto-char (point-max))
  (insert "\n* TODO " title "\nSCHEDULED: <" (format-time-string "%Y-%m-%d %a")
          " .+1d>\n:PROPERTIES:\n:STYLE: habit\n:LOGGING: logrepeat\n:END:\n")
  (org-back-to-heading t)
  (org-id-get-create)
  (save-buffer)
  (when (called-interactively-p 'interactive) (org-workflow-habits-configure)))

(defun org-workflow-habits--marker ()
  "Return the selected habit's marker or signal a user error."
  (let ((marker (if (derived-mode-p 'org-agenda-mode)
                    (org-get-at-bol 'org-hd-marker) (point-marker))))
    (unless (and marker (org-with-point-at marker (org-workflow-habit-p)))
      (user-error "请将光标放在习惯上"))
    marker))

(defun org-workflow-habits-complete ()
  "Complete the selected habit using the shared item operation."
  (interactive)
  (org-workflow-item-complete (org-workflow-item-at-marker (org-workflow-habits--marker)))
  (when (derived-mode-p 'org-agenda-mode) (org-agenda-redo)))

(defun org-workflow-habits-start ()
  "Start the selected habit through the shared item clock operation."
  (interactive)
  (org-workflow-item-start (org-workflow-item-at-marker (org-workflow-habits--marker))))

(defun org-workflow-habits--after-save ()
  "Notify adapters after saving a dedicated or embedded habit source."
  (when (and (derived-mode-p 'org-mode)
             (or (equal buffer-file-name (org-workflow-habits-file))
                 (save-excursion (save-restriction (widen) (goto-char (point-min))
                                                 (re-search-forward "^:STYLE:[ \t]+habit[ \t]*$" nil t)))))
    (run-hooks 'org-workflow-habits-saved-hook)))

(defun org-workflow-habits--after-clock-out ()
  "Save completed habit CLOCKs so the statistics adapter can replay them."
  (when (and buffer-file-name (derived-mode-p 'org-mode))
    (save-excursion
      (org-back-to-heading t)
      (when (org-workflow-habit-p) (save-buffer)))))

(defun org-workflow-habits--enable ()
  "Install this component while Workflow is being enabled."
  (org-workflow--add-hook 'org-clock-out-hook #'org-workflow-habits--after-clock-out)
  (org-workflow--add-hook 'after-save-hook #'org-workflow-habits--after-save))

(provide 'org-workflow-habits)
;;; org-workflow-habits.el ends here
