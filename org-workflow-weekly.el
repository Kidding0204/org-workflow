;;; org-workflow-weekly.el --- org-workflow-weekly Workflow component -*- lexical-binding: t; -*-
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
;;; org-workflow-weekly.el --- Human journals and navigation -*- lexical-binding: t; -*-
(require 'calendar)

(require 'cl-lib)

(require 'vulpea)

(require 'transient)

(autoload 'org-workflow-evening-open "org-workflow-evening" nil t)

(autoload 'org-workflow-habits-open "org-workflow-habits" nil t)

(require 'org-workflow-history)

(defvar-local org-workflow-week nil)

(defvar org-workflow-agenda-review-week nil)

(defvar-local org-workflow-agenda-review-start nil)

(put 'org-workflow-agenda-review-start 'permanent-local t)

(defun org-workflow-week-start (&optional date)
  "Return the local Monday for DATE, including year boundaries."
  (let* ((date (or date (org-workflow-target--today-string)))
         (parts (mapcar #'string-to-number (split-string date "-")))
         (day (calendar-day-of-week (list (nth 1 parts) (nth 2 parts) (car parts)))))
    (org-workflow-history-add-days date (- (mod (+ day 6) 7)))))

(defun org-workflow-week-file (&optional date)
  "Return the weekly journal path for DATE, defaulting to the current week."
  (expand-file-name (concat "journal/weekly/" (org-workflow-week-start date) ".org")
                    (org-workflow--directory)))

(defun org-workflow-week--agenda-file-p (file)
  "Whether FILE is a weekly journal in the configured notes directory."
  (let ((directory (file-name-as-directory
                    (expand-file-name "journal/weekly" (org-workflow--directory)))))
    (and (string-prefix-p directory (expand-file-name file))
         (string-match-p "/[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\.org\\'"
                         (expand-file-name file)))))

(defun org-workflow-week-sync-agenda (file)
  "Add weekly FILE to Agenda if current or future, removing past weekly files."
  (when (and (org-workflow-week--agenda-file-p file)
             (not (string< (file-name-base file) (org-workflow-week-start))))
    (let* ((files (org-agenda-files t))
           (kept (cl-remove-if
                  (lambda (candidate)
                    (and (org-workflow-week--agenda-file-p candidate)
                         (string< (file-name-base candidate)
                                  (org-workflow-week-start))))
                  files))
           (updated (if (member (expand-file-name file)
                                (mapcar #'expand-file-name kept))
                        kept (cons (abbreviate-file-name file) kept))))
      (unless (equal (mapcar #'expand-file-name updated)
                     (mapcar #'expand-file-name files))
        (org-store-new-agenda-file-list updated)
        (org-install-agenda-files-menu)))))

(defun org-workflow-week--ensure-area (file)
  "Give an existing weekly journal FILE the area filetag."
  (with-current-buffer (find-file-noselect file)
    (org-with-wide-buffer
     (unless (member "area" org-file-tags)
       (goto-char (point-min))
       (if (re-search-forward "^#\\+filetags:[ \t]*\\(.*\\)$" nil t)
           (progn (end-of-line) (insert " :area:"))
         (goto-char (point-min)) (insert "#+filetags: :area:\n"))
       (org-set-regexps-and-options)
       (save-buffer)))))

(defun org-workflow-week-ensure (&optional date)
  "Create the journal for DATE's week, leaving existing text intact."
  (let* ((week (org-workflow-week-start date)) (file (org-workflow-week-file week)))
    (unless (file-exists-p file)
      (make-directory (file-name-directory file) t)
      (vulpea-create (format "%s — %s" week (org-workflow-history-add-days week 6)) file
                     :tags '("journal-week" "area") :properties `(("WORKFLOW_WEEK" . ,week))
                     :body (concat "* 周目标\n\n* 随记\n\n* 收集箱\n:PROPERTIES:\n:JOURNAL_INBOX: "
                                   week "\n:END:\n\n* 周回顾\n")))
    (org-workflow-week--ensure-area file)
    (org-workflow-week-sync-agenda file)
    file))

(defun org-workflow-week-detect ()
  "Detect the visited weekly journal's week property for buffer-local navigation."
  (when (and buffer-file-name (derived-mode-p 'org-mode))
    (setq-local org-workflow-week
                (save-excursion (save-restriction (widen) (goto-char (point-min))
                                                  (when (re-search-forward "^:WORKFLOW_WEEK: +\\([0-9-]+\\)" nil t)
                                                    (match-string-no-properties 1)))))))

(defun org-workflow-week-open (&optional date)
  "Visit the week containing DATE without opening companion windows."
  (interactive)
  (find-file (org-workflow-week-ensure date))
  (org-workflow-week-detect))

(defcustom org-workflow-review-sidebar-min-width 180
  "Minimum frame width in columns for Vulpea beside the review workbench."
  :type 'integer :group 'org)

(defun org-workflow-week-open-review (&optional date)
  "Open DATE's weekly journal with Sprint to its left.
On wide frames, also open the Vulpea sidebar using its usual note check."
  (interactive)
  (org-workflow-week-open date)
  (when (and (>= (frame-width) org-workflow-review-sidebar-min-width)
             org-workflow-sidebar-function)
    (funcall org-workflow-sidebar-function))
  (org-workflow-week-show-sprint))

(defun org-workflow-week-previous ()
  "Visit the previous weekly journal."
  (interactive) (org-workflow-week-open (org-workflow-history-add-days (or org-workflow-week (org-workflow-week-start)) -7)))

(defun org-workflow-week-next ()
  "Visit the next weekly journal."
  (interactive) (org-workflow-week-open (org-workflow-history-add-days (or org-workflow-week (org-workflow-week-start)) 7)))

(defun org-workflow-week-capture-target ()
  "Prepare the current week's inbox heading as an Org capture target."
  (set-buffer (org-capture-target-buffer (org-workflow-week-ensure)))
  (widen) (goto-char (point-min))
  (unless (re-search-forward "^\\* 收集箱$" nil t) (user-error "周日志缺少收集箱标题"))
  (beginning-of-line))

(defun org-workflow-week-show-sprint (&rest _)
  "Reuse the review layout; never run while creating a capture."
  (when (and org-workflow-week (not noninteractive) (not (bound-and-true-p org-capture-mode))
             (not org-workflow-collection--opening-sprint))
    (let* ((org-workflow-collection--opening-sprint t)
           (journal-window (selected-window))
           (org-agenda-buffer-name "*周日志 Sprint*")
           (org-agenda-window-setup 'current-window)
           (org-workflow-agenda-journal-context t)
           (org-workflow-agenda-review-week org-workflow-week)
           (org-workflow-agenda-columns-enabled nil)
           (window (or (get-buffer-window org-agenda-buffer-name)
                       (condition-case nil (split-window journal-window nil 'left)
                         (error (split-window journal-window nil 'above))))))
      (when (> (car (window-edges window)) (car (window-edges journal-window)))
        (window-swap-states window journal-window)
        (cl-rotatef window journal-window))
      (with-selected-window window (org-agenda nil "d"))
      (select-window journal-window))))

(defun org-workflow-open-agenda ()
  "Open the Workflow Sprint Agenda command."
  (interactive) (org-agenda nil "d"))

(defun org-workflow-open-project ()
  "Select and visit an existing Workflow project or area source."
  (interactive)
  (let ((files (org-workflow-inbox--project-files)))
    (unless files (user-error "没有 Workflow 项目／领域"))
    (find-file (completing-read "项目／领域：" files nil t))))

(transient-define-prefix org-workflow-menu ()
                         "Navigate the Workflow workbench."
                         [["工作台"
                           ("a" "Sprint" org-workflow-open-agenda)
                           ("j" "本周日志" org-workflow-week-open)
                           ("p" "项目／领域" org-workflow-open-project)
                           ("c" "当前任务" org-workflow-target-visit)]
                          ["回顾"
                           ("e" "晚间收尾 · 任务与习惯" org-workflow-evening-open)
                           ("h" "习惯文件" org-workflow-habits-open)
                           ("r" "Sprint ＋ 周日志" org-workflow-week-open-review)
                           ("i" "全部未处理收集项" org-workflow-collection-inbox-review)
                           ("[" "前一周" org-workflow-week-previous)
                           ("]" "后一周" org-workflow-week-next)]])

(defun org-workflow-weekly-setup ()
  "Install weekly navigation bindings, detection and capture integration."
  (org-workflow--global-set-key "C-c n j" #'org-workflow-week-open)
  (org-workflow--global-set-key "C-c o m" #'org-workflow-menu)
  (org-workflow--add-hook 'find-file-hook #'org-workflow-week-detect)
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (org-workflow-week-detect)))
  (let ((file (org-workflow-week-file)))
    (when (file-exists-p file)
      (org-workflow-week--ensure-area file)
      (org-workflow-week-sync-agenda file))))

(provide 'org-workflow-weekly)
;;; org-workflow-weekly.el ends here
