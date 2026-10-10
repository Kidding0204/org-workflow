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
(require 'org-workflow-sources)
(require 'org-workflow-store)

(require 'org-clock)

(require 'org-id)

(require 'cl-lib)

(require 'seq)

(require 'subr-x)

(defgroup org-workflow-habits nil "Independent habits and daily facts." :group 'org)

(defcustom org-workflow-habit-file nil
  "Habit source; nil uses the configured miscellaneous projects file.
An explicit file keeps the dedicated habit document behavior."
  :type '(choice (const :tag "Miscellaneous projects file" nil) file)
  :group 'org-workflow-habits)

(defun org-workflow-habits-file ()
  "Resolve the source without capturing load order or the visited directory."
  (expand-file-name
   (or org-workflow-habit-file
       org-workflow-projects-file)))

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
  (dolist (file (org-workflow-habits-files))
    (when (file-exists-p file)
      (unless (file-readable-p file) (error "Unreadable habit source: %s" file))
      (with-current-buffer (find-file-noselect file)
        (let ((org-element-use-cache nil))
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

(defun org-workflow-habits--parse ()
  "Read all native completion dates, independent of graph display settings."
  (let ((org-habit-preceding-days most-positive-fixnum)
        (org-habit-following-days 0))
    (org-habit-parse-todo)))

(defun org-workflow-habits-week-start (day)
  "Return the Sunday starting the week containing absolute DAY."
  (- day (mod day 7)))

(defun org-workflow-habits-week-target ()
  "Read the optional weekly completion target at point."
  (when-let* ((value (org-entry-get nil "WORKFLOW_HABIT_WEEK_TARGET")))
    (unless (string-match-p "\\`[1-7]\\'" value)
      (user-error "每周习惯次数必须为 1 至 7"))
    (string-to-number value)))

(defun org-workflow-habits-week-count (habit day)
  "Count distinct completion days of HABIT in DAY's Sunday-based week."
  (let ((start (org-workflow-habits-week-start day)))
    (length (seq-filter (lambda (date) (and (<= start date) (<= date day)))
                        (delete-dups (copy-sequence (org-habit-done-dates habit)))))))

(defun org-workflow-habits-weekdays ()
  "Read optional fixed weekdays at point as Sunday-based numbers."
  (when-let* ((value (org-entry-get nil "WORKFLOW_HABIT_WEEKDAYS")))
    (unless (string-match-p "\\`[0-6]\\(?:,[0-6]\\)*\\'" value)
      (user-error "习惯星期应为 0 至 6，以逗号分隔；0 表示周日"))
    (delete-dups (mapcar #'string-to-number (split-string value ",")))))

(defun org-workflow-habits--next-weekday (day weekdays)
  "Return the first date on or after DAY matching WEEKDAYS."
  (while (not (memq (mod day 7) weekdays)) (setq day (1+ day)))
  day)

(defun org-workflow-habits--day-time (day)
  "Convert absolute calendar DAY to local noon."
  (let ((date (calendar-gregorian-from-absolute day)))
    (encode-time 0 0 12 (nth 1 date) (nth 0 date) (nth 2 date))))

(defun org-workflow-habits-check-completion ()
  "Reject duplicate or excess completions for a weekly habit at point."
  (when-let* ((target (org-workflow-habits-week-target)))
    (let* ((habit (org-workflow-habits--parse))
           (day (time-to-days (current-time))))
      (when (memq day (org-habit-done-dates habit))
        (user-error "本习惯今天已完成；每周次数每天最多计一次"))
      (when (>= (org-workflow-habits-week-count habit day) target)
        (user-error "本周习惯次数已达标")))))

(defun org-workflow-habits-after-complete ()
  "Advance a fixed-weekday habit to the next selected day after completion."
  (when-let* ((habitp (org-workflow-habit-p))
              (weekdays (org-workflow-habits-weekdays)))
    (let* ((day (org-workflow-habits--next-weekday
                 (1+ (time-to-days (current-time))) weekdays))
           (time (org-workflow-habits--day-time day)))
      (unless (= day (time-to-days (org-get-scheduled-time (point))))
        (org-schedule nil (format-time-string "%Y-%m-%d" time))))))

(defun org-workflow-habits-rule-label (&optional habit day)
  "Describe the current repeat rule using optional parsed HABIT and DAY."
  (let* ((habit (or habit (org-workflow-habits--parse)))
         (day (or day (time-to-days (current-time))))
         (target (org-workflow-habits-week-target))
         (weekdays (org-workflow-habits-weekdays)))
    (cond (target (format "每周 %d 次 · 本周 %d/%d" target
                          (org-workflow-habits-week-count habit day) target))
          (weekdays (concat "每周 " (mapconcat
                                     (lambda (n) (nth n '("日" "一" "二" "三" "四" "五" "六")))
                                     weekdays "、")))
          (t (let ((repeat (org-get-repeat (org-entry-get nil "SCHEDULED"))))
               (if (string-match "\\`\\([.+]*+\\)\\([0-9]+\\)\\([dwmy]\\)" repeat)
                   (format "%s %s %s"
                           (if (equal (match-string 1 repeat) ".+") "完成后隔" "每")
                           (match-string 2 repeat)
                           (cdr (assoc (match-string 3 repeat)
                                       '(("d" . "天") ("w" . "周") ("m" . "个月") ("y" . "年")))))
                 "原生重复"))))))

(defun org-workflow-habits-set-repeat (mode value &optional first-date)
  "Set habit repeat MODE and VALUE, starting at optional FIRST-DATE.
MODE is interval (days after completion), weekdays (0 Sunday through 6),
or weekly (1 to 7 completion days per Sunday-based week)."
  (unless (org-workflow-habit-p) (user-error "请将光标放在习惯上"))
  (pcase mode
    ('interval (unless (and (integerp value) (> value 0))
                 (user-error "间隔天数必须为正整数")))
    ('weekly (unless (and (integerp value) (<= 1 value 7))
               (user-error "每周习惯次数必须为 1 至 7")))
    ('weekdays (unless (and (consp value)
                           (seq-every-p (lambda (n) (and (integerp n) (<= 0 n 6))) value))
                 (user-error "请选择至少一个有效星期")))
    (_ (user-error "未知习惯重复模式")))
  (let* ((day (time-to-days (if first-date (org-time-string-to-time first-date) (current-time))))
         (day (if (eq mode 'weekdays) (org-workflow-habits--next-weekday day value) day))
         (repeat (if (eq mode 'weekdays) "++1d"
                   (format ".+%dd" (if (eq mode 'interval) value 1)))))
    (org-entry-delete nil "WORKFLOW_HABIT_WEEK_TARGET")
    (org-entry-delete nil "WORKFLOW_HABIT_WEEKDAYS")
    (pcase mode
      ('weekly (org-entry-put nil "WORKFLOW_HABIT_WEEK_TARGET" (number-to-string value)))
      ('weekdays (org-entry-put nil "WORKFLOW_HABIT_WEEKDAYS"
                                 (mapconcat #'number-to-string (sort (delete-dups (copy-sequence value)) #'<) ","))))
    (org-schedule nil (concat "<" (format-time-string "%Y-%m-%d" (org-workflow-habits--day-time day)) " " repeat ">"))
    (save-buffer)))

(defun org-workflow-habits-configure-repeat ()
  "Choose a simple repeat rule for the selected habit."
  (interactive)
  (let* ((marker (org-workflow-habits--marker))
         (label (completing-read "重复方式：" '("完成后间隔" "固定星期" "每周次数") nil t))
         (mode (cdr (assoc label '(("完成后间隔" . interval) ("固定星期" . weekdays) ("每周次数" . weekly)))))
         (value (if (eq mode 'weekdays)
                    (mapcar (lambda (label) (cl-position label '("周日" "周一" "周二" "周三" "周四" "周五" "周六") :test #'equal))
                            (completing-read-multiple "星期（逗号分隔）：" '("周日" "周一" "周二" "周三" "周四" "周五" "周六") nil t))
                  (read-number (if (eq mode 'weekly) "每周几次（1–7，每天最多一次）：" "完成后隔几天：") 1)))
         (first-date (org-read-date nil nil nil "首次日期：")))
    (org-with-point-at marker (org-workflow-habits-set-repeat mode value first-date))
    (when (derived-mode-p 'org-agenda-mode) (org-agenda-redo))))

(defun org-workflow-habits-items (date)
  "Return native habit items due or completed on DATE."
  (let ((day (time-to-days (org-time-string-to-time (concat date " 12:00")))) items)
    (when (and org-workflow-store-enabled (org-workflow-store-meta "habit-source")
               (not (file-readable-p (org-workflow-habits-file))))
      (error "Habit source unavailable"))
    (org-workflow-habits--map
     (lambda ()
       (unless (org-entry-is-done-p)
         (let* ((habit (org-workflow-habits--parse))
                (done (memq day (org-habit-done-dates habit)))
                (target (org-workflow-habits-week-target))
                (weekdays (org-workflow-habits-weekdays)))
           (when (or done
                     (and (<= (org-habit-scheduled habit) day)
                          (or (null weekdays) (memq (mod day 7) weekdays))
                          (or (null target) (< (org-workflow-habits-week-count habit day) target))))
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
      (insert (if org-workflow-habit-file
                  "#+title: 习惯\n#+TODO: TODO | DONE\n#+STARTUP: logrepeat\n#+PROPERTY: LOGGING logrepeat\n\n"
                "#+title: 杂项\n#+filetags: :project:\n\n* Someday\n\n* 习惯\n"))))
  (find-file (org-workflow-habits-file))
  (widen)
  (unless org-workflow-habit-file
    (goto-char (org-workflow-source-section "习惯" t))
    (org-fold-show-entry)
    (org-narrow-to-subtree)))

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
  (insert (if org-workflow-habit-file "\n* TODO " "\n** TODO ") title "\nSCHEDULED: <" (format-time-string "%Y-%m-%d %a")
          " .+1d>\n:PROPERTIES:\n:STYLE: habit\n:LOGGING: logrepeat\n:END:\n")
  (org-back-to-heading t)
  (org-id-get-create)
  (save-buffer)
  (when (called-interactively-p 'interactive)
    (org-workflow-habits-configure-repeat)
    (org-workflow-habits-configure)))

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
  (org-workflow--add-hook 'org-todo-repeat-hook #'org-workflow-habits-after-complete)
  (org-workflow--add-hook 'org-clock-out-hook #'org-workflow-habits--after-clock-out)
  (org-workflow--add-hook 'after-save-hook #'org-workflow-habits--after-save))

(provide 'org-workflow-habits)
;;; org-workflow-habits.el ends here
