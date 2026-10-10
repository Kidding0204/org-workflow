;;; org-workflow-evening.el --- org-workflow-evening Workflow component -*- lexical-binding: t; -*-
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
;;; org-workflow-evening.el --- Explicit task and habit workbench -*- lexical-binding: t; -*-
(require 'org-workflow-habits)

(require 'org-workflow-agenda)

(require 'transient)

(defun org-workflow-evening-stop-clock ()
  "Stop only the clock belonging to the habit at point, then save its source."
  (interactive)
  (let ((marker (org-workflow-habits--marker)))
    (unless (org-workflow-clock--clock-matches-p marker) (user-error "当前习惯没有正在运行的计时"))
    (org-workflow-clock--clock-stop)
    (org-with-point-at marker (save-buffer))
    (org-agenda-redo)))

(declare-function nerd-icons-mdicon "nerd-icons" (icon-name &rest args))

(defun org-workflow-evening--day-icon (state face)
  "Return a consistently sized status glyph for STATE using FACE."
  (let ((icon (assq state '((done "nf-md-checkbox_marked_outline" "☑")
                           (missed "nf-md-close_box_outline" "☒")
                           (today "nf-md-checkbox_blank_outline" "☐")
                           (future "nf-md-minus_box_outline" "⊟")))))
    (if (and (display-graphic-p) (require 'nerd-icons nil t))
        (nerd-icons-mdicon (nth 1 icon) :height 1.0 :v-adjust 0.0 :face face)
      (propertize (nth 2 icon) 'face face))))

(defun org-workflow-evening--week (done today &optional non-daily weekdays weekly)
  "Render Sunday to Saturday from DONE absolute dates relative to TODAY.
NON-DAILY disables the daily streak indicator.
WEEKDAYS restrict expected days; WEEKLY makes uncompleted days neutral.
Today's pending occurrence does not break the ongoing streak."
  (let* ((sunday (org-workflow-habits-week-start today))
         (cursor (if (memq today done) today (1- today)))
         (total 0))
    (while (memq cursor done)
      (cl-incf total) (cl-decf cursor))
    (concat
     (mapconcat
      (lambda (offset)
        (let* ((day (+ sunday offset))
               (completed (memq day done))
               (future (> day today))
               (neutral (or weekly (and weekdays (not (memq offset weekdays)))))
               (state (cond (completed 'done) (neutral 'future) (future 'future)
                            ((= day today) 'today) (t 'missed)))
               (face (cond (completed 'success) ((= day today) 'default) (t 'shadow))))
          (propertize
           (concat (propertize (concat (nth offset '("日" "一" "二" "三" "四" "五" "六")) " ")
                               'face face)
                   (org-workflow-evening--day-icon state face))
           'help-echo (cond (completed "已完成") (neutral (if weekly "自主安排执行日" "无需执行")) (future "未来")
                            ((= day today) "今天待完成") (t "未记录完成")))))
      (number-sequence 0 6) "  ")
     (unless non-daily
       (propertize (format "  连续 %d 天" total) 'face 'shadow)))))

(defface org-workflow-evening-habit-title
  '((t (:inherit shadow :weight normal)))
  "Quiet habit titles in the Sprint work windows."
  :group 'org-workflow-habits)

(defun org-workflow-evening--habit-rows (date)
  "Render shared habit items for DATE with native week tracking."
  (let ((today (time-to-days (org-time-string-to-time (concat date " 12:00"))))
        (org-element-use-cache nil) rows)
    (dolist (item (org-workflow-habits-items date))
      (org-with-point-at (org-workflow-target-entry-marker item)
        (let* ((habit (org-workflow-habits--parse))
               (done (org-habit-done-dates habit))
               (marker (org-agenda-new-marker (point)))
               (tags (org-workflow-display-tags))
               (line (concat "    " (propertize "↻" 'face 'shadow)
                             (propertize " " 'display '(space :align-to 6))
                             (propertize (org-workflow-target-entry-title item)
                                         'face 'org-workflow-evening-habit-title)
                             (org-workflow-agenda--visible-tags tags)
                             (propertize (concat "  " (org-workflow-habits-rule-label habit today)) 'face 'shadow)
                             "\n      "
                             (org-workflow-evening--week done today
                              (not (and (= (org-habit-scheduled-repeat habit) 1)
                                        (null (nth 3 habit))
                                        (null (org-workflow-habits-week-target))
                                        (null (org-workflow-habits-weekdays))))
                              (org-workflow-habits-weekdays)
                              (org-workflow-habits-week-target)) "\n")))
          (org-add-props line nil
                         'org-marker marker 'org-hd-marker marker
                         'org-category (org-get-category) 'todo-state (org-get-todo-state)
                         'tags tags 'priority (org-workflow-target-entry-priority item)
                         'type "todo" 'org-heading t 'mouse-face 'highlight
                         'org-workflow-agenda-create-context 'habit
                         'org-workflow-agenda-habit-done (org-workflow-target-entry-done item))
          (push (cons (org-workflow-target-entry-habit-position item) line) rows))))
    (nreverse rows)))

(defun org-workflow-evening--insert-habits (rows period edge)
  "Insert habit ROWS matching priority PERIOD and window EDGE."
  (let* ((name (cdr (assq period '((?A . morning) (?B . afternoon) (?C . evening)))))
         (position (seq-find (lambda (item) (and (eq (nth 1 item) name)
                                                (eq (nth 2 item) edge)))
                             org-workflow-habits-positions))
         (selected (seq-filter (lambda (row) (equal (car row) position)) rows)))
    ;; Habit and task glyphs share the four-space inset; titles follow them.
    (dolist (row selected) (insert (cdr row)))))

(defun org-workflow-evening-today (_match)
  "Render the timed queue; free habits appear in the all-day optional section."
  (let* ((tomorrow (org-workflow-agenda--setting 'org-workflow-agenda-plan-tomorrow))
         (rows (unless tomorrow
                 (org-workflow-evening--habit-rows (org-workflow-agenda-target-date)))))
    (org-workflow-agenda-task-stack nil rows)))

(defun org-workflow-evening-open ()
  "Open the default task and habit console."
  (interactive)
  (org-agenda nil "d"))

(provide 'org-workflow-evening)
;;; org-workflow-evening.el ends here
