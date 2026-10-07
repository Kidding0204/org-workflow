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
  "Call FUNCTION on each habit in existing sources, without creating files."
  (dolist (file (org-workflow-habits-files))
    (when (file-exists-p file)
      (unless (file-readable-p file) (error "Unreadable habit source: %s" file))
      (with-current-buffer (find-file-noselect file)
        (org-with-wide-buffer
         (org-map-entries
          (lambda () (when (org-workflow-habit-p) (funcall function))) nil 'file))))))

(defun org-workflow-habits--direct-end ()
  "Return the position of the next heading, excluding nested habit content."
  (save-excursion (outline-next-heading) (point)))

(defun org-workflow-habits-records (date)
  "Read direct CLOCK and DONE logs for DATE, including repeated TODO entries.
No source properties are changed.  Missing IDs are errors, not silent omissions."
  (let* ((start (org-time-string-to-time (concat date " 00:00")))
         (parts (decode-time start))
         (end (encode-time 0 0 0 (1+ (nth 3 parts)) (nth 4 parts) (nth 5 parts)))
         records)
    (org-workflow-habits--map
     (lambda ()
       (let ((id (org-entry-get nil "ID"))
             (title (org-get-heading t t t t))
             completions minutes)
         (save-excursion
           (save-restriction
             (narrow-to-region (point) (org-workflow-habits--direct-end))
             (org-clock-sum start end)
             (setq minutes org-clock-file-total-minutes)
             (goto-char (point-min))
             (while (re-search-forward
                     "^[ \t]*- State \"DONE\".*?\\[\\([0-9-]+[^]\n]*\\)\\]" nil t)
               (let ((stamp (match-string-no-properties 1)))
                 (when (string-prefix-p date stamp) (push stamp completions))))))
         (when (or completions (> minutes 0))
           (unless id (user-error "习惯缺少 ID：%s；请在源条目运行 org-id-get-create 并保存" title))
           (when (seq-find (lambda (row) (equal id (plist-get row :id))) records)
             (error "Duplicate habit ID: %s" id))
           (push (list :id id :task title :outcome (if completions "done" "focused")
                       :focusMinutes minutes :completedAt (vconcat (nreverse completions))) records)))))
    (nreverse records)))

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
  (save-buffer))

(defun org-workflow-habits--marker ()
  "Return the selected habit's marker or signal a user error."
  (let ((marker (if (derived-mode-p 'org-agenda-mode)
                    (org-get-at-bol 'org-hd-marker) (point-marker))))
    (unless (and marker (org-with-point-at marker (org-workflow-habit-p)))
      (user-error "请将光标放在习惯上"))
    marker))

(defun org-workflow-habits-complete ()
  "Record one completion through Org's native repeat mechanism."
  (interactive)
  (let ((marker (org-workflow-habits--marker))
        (agenda (derived-mode-p 'org-agenda-mode)))
    (when (and (fboundp 'org-workflow-clock--clock-matches-p)
               (org-workflow-clock--clock-matches-p marker))
      (org-workflow-clock--clock-stop))
    (org-with-point-at marker
      (let ((org-log-repeat 'time) (org-log-into-drawer t))
        (org-todo "DONE")
        ;; Flush the native deferred state log before saving and synchronizing.
        (when org-log-note-marker (org-add-log-note)))
      (save-buffer))
    (when agenda (org-agenda-redo))))

(defun org-workflow-habits-start ()
  "Time this habit without changing the Workflow selection or stopping other work."
  (interactive)
  (let ((marker (org-workflow-habits--marker)))
    (when (or (org-clocking-p)
              (and (fboundp 'org-workflow-focus-timer-active-p) (org-workflow-focus-timer-active-p)))
      (user-error "请先结束当前计时"))
    (if (fboundp 'org-workflow-clock--clock-start)
        (org-workflow-clock--clock-start marker)
      (org-with-point-at marker (org-clock-in)))))

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
