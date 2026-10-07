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
             (let ((key (secure-hash 'sha256 (format "%s:%s:%s" buffer-file-name (point) (org-get-heading t t t t)))))
               (push (cons key (point-marker)) markers)
             (push (list :key key :title (substring-no-properties (org-get-heading t t t t))
                         :done (if done t :false)) rows)))))))
    (dolist (entry org-workflow-panel--habit-markers) (set-marker (cdr entry) nil))
    (setq org-workflow-panel--habit-markers (nreverse markers))
    (vconcat (nreverse rows))))

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
         (key (list today (floor (float-time) 60)
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
                        :habits (org-workflow-panel--habits today)))
              (error (list :available :false :error (error-message-string err)))))
      (setq org-workflow-panel--key key))
    org-workflow-panel--cache))

(defun org-workflow-panel--augment (status)
  "Add desktop panel facts and the current task's resume hint to STATUS."
  (let ((marker (org-workflow-target-current-marker)))
    (append status (list :panel (org-workflow-panel-status)
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
    (org-show-context) (org-show-entry)))

(defun org-workflow-panel--enable ()
  "Install this component while Workflow is being enabled."
  (org-workflow--with-after-load 'org-workflow-focus-timer
  (org-workflow--advice-add 'org-workflow-focus-timer--enter-phase :after #'org-workflow-panel--focus-started))
  (org-workflow--add-hook 'after-save-hook #'org-workflow-panel-invalidate)
  (org-workflow--add-hook 'org-after-todo-state-change-hook #'org-workflow-panel-invalidate)
  (org-workflow--add-hook 'org-clock-out-hook #'org-workflow-panel-invalidate)
  (org-workflow--advice-add 'org-workflow-status :filter-return #'org-workflow-panel--augment))

(provide 'org-workflow-panel)
;;; org-workflow-panel.el ends here
