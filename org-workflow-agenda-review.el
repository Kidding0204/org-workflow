;;; org-workflow-agenda-review.el --- note-gtd-review Workflow component -*- lexical-binding: t; -*-
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
;;; org-workflow-agenda-review.el --- Daily review beside Sprint -*- lexical-binding: t; -*-
(require 'org-clock)

(defvar org-workflow-agenda-journal-context nil)

(defvar org-workflow-agenda-review-week nil)

(defvar-local org-workflow-agenda-review-start nil)

(put 'org-workflow-agenda-review-start 'permanent-local t)

(defvar-local org-workflow-agenda-completed-expanded t)

(put 'org-workflow-agenda-completed-expanded 'permanent-local t)

(defun org-workflow-agenda--clock-summary ()
  "Return (TOTAL TODAY HAS-RECORD) for the current subtree using Org Clock."
  (let* ((today (org-workflow-target--today-string))
         (start (org-time-string-to-time (concat today " 00:00")))
         (parts (decode-time start))
         (end (encode-time 0 0 0 (1+ (nth 3 parts)) (nth 4 parts) (nth 5 parts))))
    (save-excursion
      (save-restriction
        (org-narrow-to-subtree)
        (let ((total (org-clock-sum nil nil nil 'org-workflow-agenda-clock-total))
              (daily (org-clock-sum start end nil 'org-workflow-agenda-clock-today))
              (record (progn
                        (goto-char (point-min))
                        (re-search-forward (concat "^[ \t]*" (regexp-quote org-clock-string)
                                                   "[ \t]+\\(?:\\[\\|=>\\)") nil t))))
          (list total daily (and record t)))))))

(defun org-workflow-agenda--clock-summary-text (summary)
  "Format clock SUMMARY without presenting missing records as recorded zero."
  (if (nth 2 summary)
      (format "今日 %s · 累计 %s"
              (org-duration-from-minutes (nth 1 summary))
              (org-duration-from-minutes (car summary)))
    "无计时记录"))

(defun org-workflow-agenda--file-has-closed-in-range-p (file start end)
  "Cheaply check FILE for CLOSED timestamps in [START, END).
Use live text when available, including unsaved edits.  Otherwise read text
without visiting the file or running Org, Vulpea and UI startup hooks.
This is only a candidate filter; Org still validates matching entries."
  (let ((buffer (find-buffer-visiting file)))
    (with-current-buffer (or buffer (generate-new-buffer " *agenda-date-scan*"))
      (unwind-protect
          (save-excursion
            (save-restriction
              (widen)
              (unless buffer (insert-file-contents file))
              (goto-char (point-min))
              (catch 'found
                (while (re-search-forward
                        "CLOSED:[ \t]*\\[\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" nil t)
                  (let ((date (match-string-no-properties 1)))
                    (when (and (not (string< date start)) (string< date end))
                      (throw 'found t))))
                nil)))
        (unless buffer (kill-buffer (current-buffer)))))))

(defun org-workflow-agenda--completed-entries ()
  "Collect today's DONE headings from Agenda and existing journal files."
  (require 'org-workflow-core)
  (let* ((files (delete-dups (append (org-agenda-files t)
                                    (org-workflow-collection-inbox--review-files))))
         ;; Capture Agenda-local context before entering source buffers.
         (start (or org-workflow-agenda-review-start (org-workflow-target--today-string)))
         (end (let ((date (decode-time (org-time-string-to-time (concat start " 00:00")))))
                (format-time-string
                 "%F" (encode-time 0 0 0
                                   (+ (nth 3 date) (if org-workflow-agenda-review-start 7 1))
                                   (nth 4 date) (nth 5 date)))))
         entries)
    (dolist (file files)
      (when (and (file-readable-p file)
                 (org-workflow-agenda--file-has-closed-in-range-p file start end))
        (with-current-buffer (find-file-noselect file)
          (org-with-wide-buffer
           (org-map-entries
            (lambda ()
              (when (and (equal (org-get-todo-state) "DONE")
                         (let ((closed (org-workflow-target--timestamp-date (org-entry-get nil "CLOSED"))))
                           (and closed (not (string< closed start))
                                (string< closed end))))
                (let ((marker (point-marker))
                      (title (org-get-heading t t t t))
                      (tags (org-workflow-display-tags))
                      (category (org-get-category)) summary)
                  (setq summary (org-workflow-agenda--clock-summary))
                  (push (list marker title tags category summary) entries))))
            nil 'file)))))
    (nreverse entries)))

(defun org-workflow-agenda-toggle-completed (&optional _button)
  "Expand or collapse today's completed tasks in this Agenda buffer."
  (interactive)
  (org-workflow-agenda--set-setting 'org-workflow-agenda-completed-expanded
                              (not (org-workflow-agenda--setting 'org-workflow-agenda-completed-expanded)))
  (org-agenda-redo))

(defun org-workflow-agenda-completed (_match)
  "Render today's completed tasks, retaining native Agenda markers."
  (unless (local-variable-p 'org-workflow-agenda-completed-expanded)
    (setq-local org-workflow-agenda-completed-expanded t
                org-workflow-agenda-review-start org-workflow-agenda-review-week))
  (goto-char (point-max))
  (let ((inhibit-read-only t) (start (point))
        (entries (org-workflow-agenda--completed-entries)))
    (insert "\n")
    (insert-text-button
     (concat (format "%s %s" (if org-workflow-agenda-completed-expanded "▾" "▸")
                     (if org-workflow-agenda-review-start "本周已完成" "今日已完成"))
             (unless org-workflow-agenda-sprint-view (format " · %d" (length entries))))
     'face 'org-workflow-agenda-section 'follow-link t
     'keymap org-workflow-agenda-future-header-map
     'action #'org-workflow-agenda-toggle-completed
     'org-agenda-structural-header t)
    (insert "\n")
    (when org-workflow-agenda-review-start
      (setq entries (cl-stable-sort entries #'string< :key (lambda (item) (nth 3 item)))))
    (when org-workflow-agenda-completed-expanded
      (let (previous-category)
      (dolist (entry entries)
        (pcase-let ((`(,marker ,title ,tags ,category ,summary) entry))
          (when (and org-workflow-agenda-review-start (not (equal category previous-category)))
            (insert (propertize (concat "  " category "\n") 'face 'org-super-agenda-header))
            (setq previous-category category))
          (let ((line (concat "    " title
                              (propertize (if org-workflow-agenda-review-start "" (concat "  " (org-workflow-agenda--clock-summary-text summary)))
                                          'face 'org-workflow-agenda-meta)
                              (org-workflow-agenda--visible-tags tags))))
            (org-add-props line nil
              'org-marker marker 'org-hd-marker marker 'org-category category
              'todo-state "DONE" 'tags tags 'priority 0 'type "todo"
              'org-heading t 'mouse-face 'highlight)
            (insert line "\n"))))))
    (add-text-properties start (point) '(org-agenda-type todo))))

(defun org-workflow-agenda--reset-completed-context (&rest _)
  "Start newly opened Agendas with the entry point's review default."
  (when-let* ((buffer (get-buffer org-agenda-buffer-name)))
    (with-current-buffer buffer
      (setq-local org-workflow-agenda-completed-expanded t
                  org-workflow-agenda-review-start org-workflow-agenda-review-week))))

(defvar org-workflow-collection--opening-sprint nil)

(defun org-workflow-collection-show-sprint (&rest _)
  "Show a dedicated Sprint beside today's visited journal, keeping journal focus."
  (unless (or (bound-and-true-p org-workflow-store-enabled) noninteractive (not (featurep 'vulpea-journal)) org-workflow-collection--opening-sprint
              (bound-and-true-p org-capture-mode))
    (when-let* ((file buffer-file-name)
                (note (vulpea-journal-find-note (current-time))))
      (when (and (org-workflow-inbox--same-file-p file (vulpea-note-path note))
                 (equal (format-time-string "%F" (or (vulpea-journal-active-date) (current-time)))
                        (org-workflow-target--today-string)))
        (let* ((org-workflow-collection--opening-sprint t)
               (journal-window (selected-window))
               (org-agenda-buffer-name "*日记 Sprint*")
               (org-agenda-window-setup 'current-window)
               (org-workflow-agenda-journal-context t)
               (org-workflow-agenda-columns-enabled nil)
               (existing-window (get-buffer-window org-agenda-buffer-name))
               (original-configuration (current-window-configuration))
               (window (or existing-window
                           (condition-case nil
                               (split-window journal-window nil 'left)
                             (error (split-window journal-window nil 'above))))))
          ;; Reuse a previously opened right-hand Sprint without disturbing
          ;; the sidebar or unrelated windows.  Keep focus with the journal.
          (when (> (car (window-edges window)) (car (window-edges journal-window)))
            (window-swap-states window journal-window)
            (cl-rotatef window journal-window))
          (with-selected-window window
            (org-agenda nil "d")
            (unless existing-window
              (setf (org-workflow-agenda-workbench-window-configuration
                     org-workflow-agenda--workbench)
                    original-configuration)))
          (select-window journal-window))))))

(defun org-workflow-agenda-review--enable ()
  "Install this component while Workflow is being enabled."
  (org-workflow--advice-add 'org-agenda :before #'org-workflow-agenda--reset-completed-context)
  (org-workflow--with-after-load 'vulpea
  (org-workflow--advice-add 'vulpea-visit :after #'org-workflow-collection-show-sprint))
  (org-workflow--advice-add 'find-file :after #'org-workflow-collection-show-sprint)
  (org-workflow--with-after-load 'vulpea-journal
  (org-workflow--advice-add 'vulpea-journal :after #'org-workflow-collection-show-sprint))
  (org-workflow--advice-add 'org-workflow-collection-inbox-visit :after #'org-workflow-collection-show-sprint))

(provide 'org-workflow-agenda-review)
;;; org-workflow-agenda-review.el ends here
