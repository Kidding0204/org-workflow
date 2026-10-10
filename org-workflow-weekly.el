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
                     :body "* 随记\n\n* 周回顾\n"))
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

(defun org-workflow-week-close (&optional file)
  "Seal past weekly FILE after its collection entries are resolved.
Closed weeks remain readable for explicit review but leave background scans."
  (interactive)
  (setq file (or file buffer-file-name))
  (unless (and file (org-workflow-week--agenda-file-p file) (file-readable-p file)
               (string< (file-name-base file) (org-workflow-week-start)))
    (user-error "只能封存已结束的周日志"))
  (require 'org-workflow-agenda-inbox)
  (when (org-workflow-source-read
         file (lambda ()
                (catch 'pending
                  (org-map-entries
                   (lambda ()
                     (when (and (org-workflow-collection-inbox-entry-p)
                                (not (org-entry-is-done-p)))
                       (throw 'pending t))) nil 'file)
                  nil)))
    (user-error "旧周仍有未完成或未归类的收集项"))
  (with-current-buffer (find-file-noselect file)
    (org-with-wide-buffer
     (goto-char (point-min))
     (unless (member "workflow-closed" org-file-tags)
       (if (re-search-forward "^#\\+filetags:[ \t]*.*$" nil t)
           (progn (end-of-line) (insert " :workflow-closed:"))
         (goto-char (point-min)) (insert "#+filetags: :workflow-closed:\n"))
       (org-set-regexps-and-options)
       (save-buffer))))
  (require 'vulpea-db)
  (vulpea-db-update-file file)
  (org-workflow-target-refresh t)
  (message "已封存：%s" (file-name-base file)))

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

(defun org-workflow-customize ()
  "Open customization options for the complete Workflow package."
  (interactive)
  (customize-group 'org-workflow))

;; Loaddefs cannot evaluate Transient macros before Transient is loaded.
;;;###autoload (autoload 'org-workflow-menu "org-workflow-weekly" nil t)
(transient-define-prefix org-workflow-menu ()
  "Dispatch planning, execution, capture and native review commands.
Commands are grouped by purpose, like Projectile's dispatch menu.
Use the timer key sequences to control Focus Timer independently."
  :variable-pitch t
  :column-widths '(16 20)
  [["工作台"
    ("a" "Sprint" org-workflow-open-agenda)
    ("A" "双栏工作台" org-workflow-agenda-open-workbench)
    ("j" "本周日志" org-workflow-week-open)
    ("p" "项目／领域" org-workflow-open-project)
    ("c" "当前任务" org-workflow-target-visit)]
   ["规划与收集"
    ("t" "选择任务" org-workflow-target-select)
    ("w" "阶段目标" org-workflow-agenda-open-goals)
    ("n" "捕获任务／笔记" org-capture)
    ("o" "明日开工提示" org-workflow-guidance-edit-tomorrow)
    ("u" "续接提示" org-workflow-guidance-edit-resume)
    ("S" "任务截图" org-workflow-screenshot-capture)]
   ["执行"
    ("s" "开始任务" org-workflow-target-start)
    ("d" "完成任务" org-workflow-target-complete)
    ("b" "休息" org-workflow-target-rest)
    ("v" "推进任务" org-workflow-target-step)
    ("P" "添加前置任务" org-workflow-target-prerequisite)
    ("x" "取消执行" org-workflow-target-cancel)]]
  [["回顾"
    ("h" "长期历史" org-workflow-history-workbench)
    ("e" "晚间收尾" org-workflow-evening-open)
    ("r" "日志旁 Sprint" org-workflow-week-open-review)
    ("i" "收集箱回顾" org-workflow-collection-inbox-review)
    ("J" "封存旧周日志" org-workflow-week-close)]
   ["计时与习惯"
    ("f t" "开始／结束专注" org-workflow-focus-timer-toggle)
    ("f f" "阶段结束" org-workflow-focus-timer-finish-phase)
    ("f s" "停止计时" org-workflow-focus-timer-stop)
    ("f r" "重置计时" org-workflow-focus-timer-reset)
    ("H" "打开习惯" org-workflow-habits-open)
    ("N" "新建习惯" org-workflow-habits-create)]
   ["导航与设置"
    ("[" "前一周" org-workflow-week-previous)
    ("]" "后一周" org-workflow-week-next)
    ("g" "开工提示" org-workflow-guidance-open)
    ("C" "参数设置" org-workflow-customize)
    ("q" "退出" transient-quit-one)]]
  (interactive)
  (require 'org-workflow)
  (transient-setup 'org-workflow-menu))

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
