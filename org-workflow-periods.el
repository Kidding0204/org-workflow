;;; org-workflow-periods.el --- Configurable work windows -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Jinwang Dong
;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Commentary:
;; Share work-window boundaries between task availability and habit reminders.
;;; Code:
(require 'org-workflow-lifecycle)

(defun org-workflow-periods--minutes (clock)
  "Parse CLOCK in HH:MM format as minutes after local midnight."
  (unless (and (stringp clock)
               (string-match "\\`\\([0-9][0-9]\\):\\([0-9][0-9]\\)\\'" clock))
    (user-error "工作时段时间必须为 HH:MM：%S" clock))
  (let ((hour (string-to-number (match-string 1 clock)))
        (minute (string-to-number (match-string 2 clock))))
    (unless (and (< hour 24) (< minute 60))
      (user-error "无效的工作时段时间：%s" clock))
    (+ (* hour 60) minute)))

(defun org-workflow-periods--validate (periods)
  "Check that PERIODS contains ordered, non-overlapping daytime windows."
  (unless (equal (mapcar #'car-safe periods) '(morning afternoon evening))
    (user-error "请依次设置 morning、afternoon、evening 三个工作时段"))
  (let ((previous-end 0))
    (dolist (period periods)
      (unless (= (length period) 3) (user-error "工作时段需要起止时间"))
      (let ((start (org-workflow-periods--minutes (nth 1 period)))
            (end (org-workflow-periods--minutes (nth 2 period))))
        (unless (and (<= previous-end start) (< start end))
          (user-error "工作时段必须按顺序排列，不能重叠或跨午夜"))
        (setq previous-end end))))
  periods)

(defcustom org-workflow-work-periods
  '((morning "08:30" "12:00")
    (afternoon "14:00" "17:30")
    (evening "19:00" "22:00"))
  "Local work windows as (NAME START END), with HH:MM clock strings.
Configure with `use-package' :custom.  Gaps allow meals, rest and habits.
Task availability advances at START; habit early/late reminders use START/END."
  :type '(repeat (list (choice (const morning) (const afternoon) (const evening))
                       (string :tag "Start") (string :tag "End")))
  :set (lambda (symbol value)
         (set-default symbol (org-workflow-periods--validate value)))
  :group 'org-workflow)

(defun org-workflow-periods-clock (period edge)
  "Return PERIOD's configured clock for EDGE, either early or late."
  (org-workflow-periods--validate org-workflow-work-periods)
  (nth (if (eq edge 'early) 1 2) (assq period org-workflow-work-periods)))

(defun org-workflow-periods-priorities (&optional time)
  "Return task priority bands whose windows have started at TIME.
During gaps retain the preceding bands; before the first start return nil."
  (org-workflow-periods--validate org-workflow-work-periods)
  (let* ((decoded (decode-time (or time (current-time))))
         (minutes (+ (* 60 (decoded-time-hour decoded)) (decoded-time-minute decoded))))
    (cl-loop for period in org-workflow-work-periods
             for letter in '(?A ?B ?C)
             when (>= minutes (org-workflow-periods--minutes (nth 1 period)))
             collect letter)))

(provide 'org-workflow-periods)
;;; org-workflow-periods.el ends here
