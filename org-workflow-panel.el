;;; org-workflow-panel.el --- org-workflow-panel Workflow component -*- lexical-binding: t; -*-
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
;;; org-workflow-panel.el --- Authoritative guidance and daily achievement display -*- lexical-binding: t; -*-
(require 'org-workflow-guidance)

(require 'org-workflow-habits)

(defvar org-workflow-panel--cache nil)

(defvar org-workflow-panel--key nil)

(defvar org-workflow-panel--habit-markers nil)
(defvar org-workflow-panel--reminder-timer nil)

(defun org-workflow-panel-invalidate (&rest _)
  "Invalidate the cached desktop presentation key."
  (setq org-workflow-panel--key nil))

(defun org-workflow-panel--focus-started (phase)
  "Record the start of PHASE when it is an explicit focus phase."
  (when (and (eq phase 'focus) org-workflow-store-enabled)
    (let ((key (concat "started:" (org-workflow-target--today-string))))
      (unless (org-workflow-store-meta key)
        (org-workflow-store-set-meta key (org-workflow-store--now))))
    (org-workflow-panel-invalidate)
    (org-workflow--request-gnome-refresh)))

(defun org-workflow-panel--habits (today)
  "Return habits due or completed on TODAY and retain their source markers."
  (let ((day (time-to-days (org-time-string-to-time (concat today " 12:00")))) rows markers)
    (when (and org-workflow-store-enabled (org-workflow-store-meta "habit-source")
               (not (file-readable-p (org-workflow-habits-file))))
      (error "Habit source unavailable"))
    (org-workflow-habits--map
     (lambda ()
       (unless (org-entry-is-done-p)
         (let* ((habit (org-habit-parse-todo))
                (done (memq day (org-habit-done-dates habit))))
           (when (or done (<= (org-habit-scheduled habit) day))
             (let ((key (or (org-entry-get nil "ID")
                            (secure-hash 'sha256 (format "%s:%s" buffer-file-name
                                                         (org-get-heading t t t t))))))
               (push (cons key (point-marker)) markers)
             (push (list :key key :title (substring-no-properties (org-get-heading t t t t))
                         :done (if done t :false)
                         :reminderTime (org-workflow-habits-reminder-clock)) rows)))))))
    (dolist (entry org-workflow-panel--habit-markers) (set-marker (cdr entry) nil))
    (setq org-workflow-panel--habit-markers (nreverse markers))
    (vconcat (nreverse rows))))

(defun org-workflow-panel--reminder-state (date)
  "Read daily reminder delivery state for DATE, independent of completions."
  (when org-workflow-store-enabled
    (when-let* ((value (org-workflow-store-meta (concat "habit-reminders:" date))))
      (org-workflow-store--decode value))))

(defun org-workflow-panel--save-reminder-state (date state)
  "Persist DATE's reminder STATE and request an immediate desktop refresh."
  (org-workflow-store-set-meta (concat "habit-reminders:" date)
                               (org-workflow-store--encode state))
  (org-workflow-panel-invalidate)
  (org-workflow--request-gnome-refresh))

(defun org-workflow-panel-current-habit ()
  "Return the latest reminded, unfinished habit, or nil.
Covered reminders never resurface after the latest one is skipped or completed."
  (when org-workflow-store-enabled
    (let* ((today (org-workflow-target--today-string))
           (state (org-workflow-panel--reminder-state today))
           (key (plist-get state :current))
           (row (and key (seq-find (lambda (habit) (equal key (plist-get habit :key)))
                                  (org-workflow-panel--habits today)))))
      (when (and row (not (eq t (plist-get row :done)))) row))))

(defun org-workflow-panel--reminder-tick (&optional now)
  "Notify once for due habits at NOW; persist the newest reminder as current."
  (when org-workflow-store-enabled
    (condition-case err
        (let* ((now (or now (current-time)))
               (date (format-time-string "%F" now))
               (decoded (decode-time now))
               (minutes (+ (* 60 (decoded-time-hour decoded)) (decoded-time-minute decoded)))
               (state (org-workflow-panel--reminder-state date))
               (sent (append (plist-get state :sent) nil))
               (skipped (append (plist-get state :skipped) nil))
               (current (plist-get state :current))
               (rows (append (org-workflow-panel--habits date) nil))
               (due (cl-stable-sort
                     (seq-filter (lambda (habit)
                                   (let ((clock (plist-get habit :reminderTime)))
                                     (and clock (not (eq t (plist-get habit :done)))
                                          (<= (org-workflow-periods--minutes clock) minutes)
                                          (not (member (plist-get habit :key) sent))
                                          (not (member (plist-get habit :key) skipped))))) rows)
                     #'string< :key (lambda (habit) (plist-get habit :reminderTime)))))
          (dolist (habit due)
            (setq current (plist-get habit :key))
            (push current sent))
          (unless (seq-some (lambda (habit) (and (equal current (plist-get habit :key))
                                               (not (eq t (plist-get habit :done))))) rows)
            (setq current nil))
          (let ((updated (list :sent (vconcat sent) :skipped (vconcat skipped) :current current)))
            (unless (or (and (null state) (null sent) (null skipped) (null current))
                        (equal state updated))
              ;; Save before delivery so polling/restarts cannot repeat a notification.
              (org-workflow-panel--save-reminder-state date updated)))
          (dolist (habit due)
            (org-workflow--notify "习惯提醒" (plist-get habit :title))))
      (error (message "习惯提醒：%s" (error-message-string err))))))

(defun org-workflow-panel-skip-habit ()
  "Skip the latest reminded habit for today without recording completion."
  (interactive)
  (let* ((habit (org-workflow-panel-current-habit))
         (date (org-workflow-target--today-string))
         (state (org-workflow-panel--reminder-state date)))
    (unless habit (user-error "没有当前习惯提醒"))
    (setq state (plist-put state :skipped
                           (vconcat (cons (plist-get habit :key)
                                          (append (plist-get state :skipped) nil)))))
    (setq state (plist-put state :current nil))
    (org-workflow-panel--save-reminder-state date state)
    (message "今天跳过：%s" (plist-get habit :title))))

(defun org-workflow-panel--clocked-habit ()
  "Return the native habit marker being clocked, if any."
  (when (and (org-clocking-p)
             (org-with-point-at org-clock-marker (org-workflow-habit-p)))
    org-clock-marker))

(defun org-workflow-panel-habit-action (action)
  "Perform ACTION on the current reminder's native habit source."
  (let* ((habit (org-workflow-panel-current-habit))
         (marker (or (and (memq action '(complete visit)) (org-workflow-panel--clocked-habit))
                     (cdr (assoc (plist-get habit :key) org-workflow-panel--habit-markers)))))
    (unless (and (markerp marker) (marker-buffer marker))
      (user-error "没有当前习惯提醒"))
    (pcase action
      ('skip (org-workflow-panel-skip-habit))
      ('visit
       (org-workflow-panel--select-frame)
       (pop-to-buffer (marker-buffer marker)) (goto-char marker)
       (org-fold-show-context) (org-fold-show-entry))
      ((or 'start 'toggle) (org-with-point-at marker (org-workflow-habits-start)))
      ('complete (org-with-point-at marker (org-workflow-habits-complete)))
      (_ (user-error "未知习惯操作：%s" action)))
    (org-workflow-panel-invalidate)
    (org-workflow--request-gnome-refresh)))

(defun org-workflow-panel--invested-p (rows)
  "Whether ROWS contain valid recorded focus or an actual completion."
  (seq-some (lambda (row)
              (or (> (or (plist-get row :focusMinutes) 0) 0)
                  (equal (plist-get row :outcome) "done"))) rows))

(defun org-workflow-panel--day-achievement (date today)
  "Read DATE's achievement, using only sealed facts before TODAY."
  (if (string< date today)
      (let* ((record (and org-workflow-store-enabled (org-workflow-store-day date)))
             (achievement (pcase (plist-get record :commitment)
          ("met" (list :state "complete" :basis "commitment"))
          ("unmet" (list :state "incomplete" :basis "commitment"))
          ("untouch"
           (list :state (if (org-workflow-panel--invested-p
                            (append (plist-get record :minimumTasks)
                                    (plist-get record :optionalTasks)
                                    (plist-get record :habitTasks) nil))
                            "complete" "incomplete") :basis "investment"))
          (_ '(:state "unknown")))))
        (when-let* ((minutes (plist-get record :focusTotalMinutes))
                    ((and (numberp minutes) (>= minutes 0))))
          (setq achievement (plist-put achievement :focusMinutes minutes)))
        achievement)
    (dolist (file (org-agenda-files t))
      (unless (file-readable-p file) (error "Source unavailable")))
    (let* ((org-clock-report-include-clocking-task nil)
           (progress (org-workflow-history-progress date))
           (tasks (org-workflow-history--tasks date))
           (habits (org-workflow-history--habit-records date))
           (committed (> (plist-get progress :minimumTotal) 0)))
      (list :state (if (if committed
                          (eq t (plist-get progress :commitmentComplete))
                        (org-workflow-panel--invested-p
                         (append tasks habits)))
                      "complete" "incomplete")
            :basis (if committed "commitment" "investment")
            :focusMinutes (apply #'+ (mapcar (lambda (row) (or (plist-get row :focusMinutes) 0))
                                             (append tasks habits)))))))

(defun org-workflow-panel--week (today)
  "Return the current week's daily achievement and leave facts relative to TODAY."
  (let ((week (org-workflow-week-start today)))
    (vconcat
     (mapcar
      (lambda (offset)
        (let* ((date (org-workflow-history-add-days week offset))
               (leaves (and org-workflow-store-enabled (org-workflow-store-leaves date)))
               (achievement (if (string< today date) '(:state "future")
                              (condition-case nil
                                  (org-workflow-panel--day-achievement date today)
                                (error '(:state "unknown"))))))
          (when (and (equal (plist-get achievement :state) "incomplete")
                     (> (length leaves) 0))
            (setq achievement (plist-put achievement :state "leave")))
          (append (list :date date) achievement
                  (when (> (length leaves) 0) (list :leaveRecords leaves)))))
      (number-sequence 0 6)))))

(defun org-workflow-panel-status ()
  "Read cached presentation facts.  Errors are unknown, never zero progress."
  (let* ((today (org-workflow-target--today-string))
         (key (list today org-workflow-work-periods (floor (float-time) 60)
                    (sort (delq nil (mapcar (lambda (b) (with-current-buffer b
                                         (and buffer-file-name (derived-mode-p 'org-mode)
                                              (cons buffer-file-name (buffer-chars-modified-tick)))))
                            (buffer-list)))
                          (lambda (a b) (string< (car a) (car b)))))))
    (unless (equal key org-workflow-panel--key)
      (setq org-workflow-panel--cache
            (condition-case err
                (let* ((started (and org-workflow-store-enabled
                                     (org-workflow-store-meta (concat "started:" today))))
                       (hint (or (org-workflow-guidance-opening today) (org-workflow-guidance-current) "")))
                  (unless org-workflow-store-enabled (error "Workflow storage unavailable"))
                  (list :available t :today today :started (if started t :false) :hint hint
                        :week (org-workflow-panel--week today)
                        :habits (org-workflow-panel--habits today)
                        :habitReminder (org-workflow-panel-current-habit)))
              (error (list :available :false :error (error-message-string err)))))
      (setq org-workflow-panel--key key))
    org-workflow-panel--cache))

(defun org-workflow-panel--augment (status)
  "Add desktop panel facts and the current task's resume hint to STATUS."
  (let ((marker (org-workflow-target-current-marker))
        (clocked (org-workflow-panel--clocked-habit)))
    (when clocked
      (setq status (copy-sequence status))
      (setq status (plist-put status :available t))
      (setq status (plist-put status :task (org-with-point-at clocked
                                            (substring-no-properties (org-get-heading t t t t)))))
      (setq status (plist-put status :parent "")))
    (append status (list :panel (org-workflow-panel-status)
                         :habitReminderPaused (if (org-clocking-p) t :false)
                         :resume (or (and marker (org-with-point-at marker (org-entry-get nil "WORKFLOW_RESUME"))) "")))))

(defun org-workflow-panel--select-frame ()
  "Reuse a graphical frame for desktop visits; never create one."
  (let ((frame (if (display-graphic-p) (selected-frame)
                 (seq-find #'display-graphic-p (frame-list)))))
    (unless frame (user-error "请先打开 Emacs 窗口"))
    (select-frame-set-input-focus frame)))

(defun org-workflow-panel-open (page)
  "Visit PAGE in an existing graphical frame."
  (org-workflow-panel--select-frame)
  (pcase page
    ('agenda (org-workflow-open-agenda))
    ('week (org-workflow-week-open))
    (_ (user-error "未知 Workflow 页面"))))

(defun org-workflow-panel-visit-habit (key)
  "Visit the habit identified by KEY without starting a clock."
  (interactive "s习惯引用：")
  (let ((marker (cdr (assoc key org-workflow-panel--habit-markers))))
    (unless (and (markerp marker) (marker-buffer marker)
                 (org-with-point-at marker (org-workflow-habit-p)))
      (user-error "习惯已变化，请刷新"))
    (org-workflow-panel--select-frame)
    (pop-to-buffer (marker-buffer marker)) (goto-char marker)
    (org-fold-show-context) (org-fold-show-entry)))

(defun org-workflow-panel--enable ()
  "Install this component while Workflow is being enabled."
  (org-workflow--with-after-load 'org-workflow-focus-timer
  (org-workflow--advice-add 'org-workflow-focus-timer--enter-phase :after #'org-workflow-panel--focus-started))
  (when (timerp org-workflow-panel--reminder-timer)
    (cancel-timer org-workflow-panel--reminder-timer))
  (setq org-workflow-panel--reminder-timer
        (run-at-time 1 30 #'org-workflow-panel--reminder-tick))
  (org-workflow--add-hook 'org-workflow-habits-saved-hook #'org-workflow-panel--reminder-tick)
  (org-workflow--add-hook 'after-save-hook #'org-workflow-panel-invalidate)
  (org-workflow--add-hook 'org-after-todo-state-change-hook #'org-workflow-panel-invalidate)
  (org-workflow--add-hook 'org-clock-out-hook #'org-workflow-panel-invalidate)
  (org-workflow--advice-add 'org-workflow-status :filter-return #'org-workflow-panel--augment))

(provide 'org-workflow-panel)
;;; org-workflow-panel.el ends here
