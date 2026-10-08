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

(defun org-workflow-evening--week (done today &optional non-daily)
  "Render Monday to Sunday from DONE absolute dates relative to TODAY.
NON-DAILY disables the daily streak indicator.
Today's pending occurrence does not break the ongoing streak."
  (let* ((monday (- today (mod (1- today) 7)))
         (cursor (if (memq today done) today (1- today)))
         (total 0))
    (while (memq cursor done)
      (cl-incf total) (cl-decf cursor))
    (concat
     (mapconcat
      (lambda (offset)
        (let* ((day (+ monday offset))
               (completed (memq day done))
               (future (> day today)))
          (propertize
           (concat (nth offset '("一" "二" "三" "四" "五" "六" "日"))
                   (cond (completed "●") (future "–") ((= day today) "○") (t "·")))
           'face (cond (completed 'success) ((= day today) 'default) (t 'shadow))
           'help-echo (cond (completed "已完成") (future "未来")
                            ((= day today) "今天待完成") (t "未记录完成")))))
      (number-sequence 0 6) "  ")
     (unless non-daily
       (propertize (format "  连续 %d 天" total) 'face 'shadow)))))

(defun org-workflow-evening--habit-rows (date)
  "Collect DATE's native habit rows with position and week tracking."
  (let ((today (time-to-days (org-time-string-to-time (concat date " 12:00")))) rows)
    (org-workflow-habits--map
     (lambda ()
       (unless (org-entry-is-done-p)
         (let* ((habit (let ((org-habit-preceding-days most-positive-fixnum)
                            (org-habit-following-days 0))
                        (org-habit-parse-todo)))
                (done (org-habit-done-dates habit)))
           (when (or (<= (org-habit-scheduled habit) today) (memq today done))
             (let* ((marker (org-agenda-new-marker (point)))
                    (tags (org-workflow-display-tags))
                    (position (org-workflow-habits-position))
                    (line (concat "      " (substring-no-properties (org-get-heading t t t t))
                                  (org-workflow-agenda--visible-tags tags) "\n        "
                                  (org-workflow-evening--week
                                   done today
                                   (not (and (= (org-habit-scheduled-repeat habit) 1)
                                             (null (nth 3 habit))))) "\n")))
               (org-add-props line nil
                              'org-marker marker 'org-hd-marker marker
                              'org-category (org-get-category) 'todo-state (org-get-todo-state)
                              'tags tags 'priority (org-get-priority (thing-at-point 'line))
                              'type "todo" 'org-heading t 'mouse-face 'highlight
                              'org-workflow-agenda-create-context 'habit)
               (push (cons position line) rows)))))))
    (nreverse rows)))

(defun org-workflow-evening--insert-habits (rows period edge)
  "Insert habit ROWS matching priority PERIOD and window EDGE."
  (let* ((name (cdr (assq period '((?A . morning) (?B . afternoon) (?C . evening)))))
         (position (seq-find (lambda (item) (and (eq (nth 1 item) name)
                                                (eq (nth 2 item) edge)))
                             org-workflow-habits-positions))
         (selected (seq-filter (lambda (row) (equal (car row) position)) rows)))
    (when selected
      ;; Titles use the same six-space inset as ordinary task titles.
      ;; A blank line separates the habit block from the adjacent task block.
      (when (eq edge 'late) (insert "\n"))
      (dolist (row selected) (insert (cdr row)))
      (when (eq edge 'early) (insert "\n")))))

(defun org-workflow-evening-today (_match)
  "Render the queue with placed habits and an unassigned habit section."
  (let* ((tomorrow (org-workflow-agenda--setting 'org-workflow-agenda-plan-tomorrow))
         (rows (unless tomorrow
                 (org-workflow-evening--habit-rows (org-workflow-agenda-target-date)))))
    (org-workflow-agenda-task-stack nil rows)
    (unless tomorrow
      (let ((start (point))
            (unassigned (seq-filter (lambda (row) (null (car row))) rows)))
        (when (or unassigned (null rows))
          (insert (propertize "  习惯\n" 'face 'org-workflow-agenda-habit
                              'org-agenda-structural-header t))
          (if unassigned (mapc (lambda (row) (insert (cdr row))) unassigned)
            (insert (propertize "      今天没有待做习惯\n" 'face 'shadow)))
          (insert "\n")
          (add-text-properties start (point) '(org-agenda-type todo
                                              org-workflow-agenda-create-context habit)))))))

(defun org-workflow-evening-open ()
  "Open the default task and habit console."
  (interactive)
  (org-agenda nil "d"))

(provide 'org-workflow-evening)
;;; org-workflow-evening.el ends here
