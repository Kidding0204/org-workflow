;;; org-workflow-journal.el --- org-workflow-journal Workflow component -*- lexical-binding: t; -*-
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
;;; org-workflow-journal.el --- Vulpea Journal adapter for Org Workflow -*- lexical-binding: t; -*-

;;; Code:

(require 'cl-lib)

(require 'calendar)

(require 'seq)

(require 'subr-x)

(require 'org)

(require 'org-clock)

(require 'org-id)

(require 'vulpea-journal)

(require 'org-workflow-core)

(declare-function vulpea-db-update-file "vulpea-db-extract")

(defconst org-workflow-journal-record-property "WORKFLOW_RECORD")

(defvar org-workflow-journal--tracking-anchor nil)

(defvar org-workflow-journal-seal-timer nil)

(defvar org-workflow-journal-finalized-hook nil
  "Functions called with an ISO date after a new Journal finalization.")

(defun org-workflow-journal--retire-obsolete-midnight-timer ()
  "Cancel and forget the pre-seal-lifecycle timer after a live reload."
  (let ((legacy 'org-workflow-journal-midnight-timer))
    (when (boundp legacy)
      (when (timerp (symbol-value legacy))
        (cancel-timer (symbol-value legacy)))
      (makunbound legacy))))

(defun org-workflow-journal--date-time (date)
  "Return local midnight time for ISO DATE."
  (org-time-string-to-time (concat "[" date "]")))

(defun org-workflow-journal--date-add-days (date days)
  "Return ISO DATE shifted by calendar DAYS."
  (pcase-let* ((`(,year ,month ,day)
                 (mapcar #'string-to-number (split-string date "-")))
                (absolute (+ days
                             (calendar-absolute-from-gregorian
                              (list month day year))))
                (`(,next-month ,next-day ,next-year)
                 (calendar-gregorian-from-absolute absolute)))
    (format "%04d-%02d-%02d" next-year next-month next-day)))

(defun org-workflow-journal--next-seal-time (&optional now)
  "Return the first local 22:00 strictly after NOW."
  (let* ((now (or now (current-time)))
         (decoded (decode-time now))
         (today (encode-time 0 0 22
                             (decoded-time-day decoded)
                             (decoded-time-month decoded)
                             (decoded-time-year decoded))))
    (if (time-less-p now today) today
      (let ((tomorrow
             (org-workflow-journal--date-add-days
              (format-time-string "%Y-%m-%d" now) 1)))
        (pcase-let ((`(,year ,month ,day)
                     (mapcar #'string-to-number
                             (split-string tomorrow "-"))))
          (encode-time 0 0 22 day month year))))))

(defun org-workflow-journal--schedule-seal ()
  "Schedule the next idempotent 22:00 journal seal."
  (when (timerp org-workflow-journal-seal-timer)
    (cancel-timer org-workflow-journal-seal-timer))
  (let* ((seal-time (org-workflow-journal--next-seal-time))
         (seal-date (format-time-string "%Y-%m-%d" seal-time)))
    (setq org-workflow-journal-seal-timer
          (run-at-time
           seal-time nil
           (lambda ()
             (let ((now (current-time)))
               (condition-case error-data
                   (if (equal seal-date
                              (format-time-string "%Y-%m-%d" now))
                       (org-workflow-journal-finalize seal-date)
                     (org-workflow-journal-catch-up now))
                 (error
                  (org-workflow--notify
                   "Org Workflow journal"
                   (error-message-string error-data)))))
             (org-workflow-journal--schedule-seal))))))

(defun org-workflow-journal--note-marker (note)
  "Return a live marker at Vulpea NOTE's root."
  (with-current-buffer (find-file-noselect (vulpea-note-path note))
    (org-mode)
    (copy-marker (if (zerop (vulpea-note-level note))
                     (point-min)
                   (vulpea-note-pos note)))))

(defun org-workflow-journal--summary-marker (note)
  "Return NOTE's own root marker for summary properties."
  (org-workflow-journal--note-marker note))

(defun org-workflow-journal--find-record (note date)
  "Return NOTE's Workflow record marker for DATE, or nil."
  (org-with-point-at (org-workflow-journal--note-marker note)
    (save-restriction
      (if (zerop (vulpea-note-level note))
          (widen)
        (org-narrow-to-subtree))
      (catch 'record
        (org-map-entries
         (lambda ()
           (when (equal date
                        (org-entry-get nil
                                       org-workflow-journal-record-property))
             (throw 'record (copy-marker (point)))))
         nil (if (zerop (vulpea-note-level note)) 'file 'tree))
        nil))))

(defun org-workflow-journal--create-record (note date)
  "Create and return NOTE's direct Workflow child for DATE."
  (org-with-point-at (org-workflow-journal--note-marker note)
    (let* ((level (1+ (vulpea-note-level note)))
           (insert-at
            (if (zerop (vulpea-note-level note))
                (point-max)
              (save-excursion (org-end-of-subtree t t) (point))))
           marker)
      (goto-char insert-at)
      (unless (bolp) (insert "\n"))
      (insert (make-string level ?*) " Workflow\n")
      (forward-line -1)
      (setq marker (copy-marker (point)))
      (org-entry-put nil org-workflow-journal-record-property date)
      marker)))

(defun org-workflow-journal-record (date &optional create)
  "Return Workflow record marker for ISO DATE, creating when CREATE."
  (let* ((time (org-workflow-journal--date-time date))
         (note (if create
                   (vulpea-journal-note time)
                 (vulpea-journal-find-note time))))
    (when note
      (or (org-workflow-journal--find-record note date)
          (when create
            (org-workflow-journal--create-record note date))))))

(defun org-workflow-journal-finalized-record (date)
  "Return DATE's finalized Journal record boundary, or nil.

The returned plist contains `:date', `:summary-marker', `:record-marker',
and `:finalized-at'.  This reader never creates Journal notes or records."
  (when-let* ((time (org-workflow-journal--date-time date))
              (note (vulpea-journal-find-note time))
              (record (org-workflow-journal-record date nil))
              (summary (org-workflow-journal--summary-marker note))
              (finalized-at
               (org-with-point-at summary
                 (org-entry-get nil "WORKFLOW_FINALIZED_AT"))))
    (list :date date
          :summary-marker summary
          :record-marker record
          :finalized-at finalized-at)))

(defun org-workflow-journal--run-finalized-hook (date)
  "Run finalization listeners for DATE without compromising the saved seal."
  (dolist (function org-workflow-journal-finalized-hook)
    (condition-case error-data
        (funcall function date)
      (error
       (ignore-errors
         (org-workflow--notify
          "Org Workflow journal"
          (format "Finalization hook failed: %s"
                  (error-message-string error-data))))))))

(defun org-workflow-journal-remove-record-ids ()
  "Remove obsolete Org IDs from all Workflow journal records.

Only headings identified by `org-workflow-journal-record-property' are
changed.  Save affected journal files and refresh both Vulpea and Org ID
indexes.  Return the number of removed IDs."
  (interactive)
  (let ((removed 0)
        buffers)
    (dolist (time (vulpea-journal-all-dates))
      (let ((date (format-time-string "%Y-%m-%d" time)))
        (when-let* ((record (org-workflow-journal-record date nil)))
          (org-with-point-at record
            (when (org-entry-get nil "ID")
              (org-entry-delete nil "ID")
              (cl-incf removed)
              (cl-pushnew (current-buffer) buffers))))))
    (let (files)
      (dolist (buffer buffers)
        (when (buffer-live-p buffer)
          (with-current-buffer buffer
            (save-buffer)
            (when buffer-file-name
              (push buffer-file-name files)))))
      (dolist (file files)
        (when (fboundp 'vulpea-db-update-file)
          (vulpea-db-update-file file)))
      (when (and files org-id-track-globally)
        (org-id-update-id-locations files t)))
    (when (called-interactively-p 'interactive)
      (message "Removed %d Workflow journal ID%s"
               removed (if (= removed 1) "" "s")))
    removed))

(defun org-workflow-journal-ensure-anchor (&optional today)
  "Return the tracking anchor without mutating journal notes.

Read note-root anchors first and legacy Workflow child anchors as a
compatibility fallback.  When none exists, use TODAY."
  (or org-workflow-journal--tracking-anchor
      (let* ((stored
              (catch 'anchor
                (dolist (time (reverse (vulpea-journal-all-dates)))
                  (let* ((date (format-time-string "%Y-%m-%d" time))
                         (note (vulpea-journal-find-note time))
                         (summary (and note
                                       (org-workflow-journal--summary-marker
                                        note)))
                         (record (and note
                                      (org-workflow-journal--find-record
                                       note date)))
                         (anchor
                          (or (and summary
                                   (org-with-point-at summary
                                     (org-workflow-target--timestamp-date
                                      (org-entry-get
                                       nil "WORKFLOW_TRACKING_STARTED"))))
                              (and record
                                   (org-with-point-at record
                                     (org-workflow-target--timestamp-date
                                      (org-entry-get
                                       nil "WORKFLOW_TRACKING_STARTED")))))))
                    (when anchor
                      (throw 'anchor anchor))))))
             (today (or today (format-time-string "%Y-%m-%d")))
             (anchor (or stored today)))
        (setq org-workflow-journal--tracking-anchor anchor))))

(defun org-workflow-journal-direct-clock-minutes (marker start end)
  "Return direct CLOCK minutes on MARKER between START and END."
  (org-with-point-at marker
    (org-back-to-heading t)
    (save-restriction
      (let ((beg (point))
            (limit (save-excursion
                     (if (outline-next-heading) (point) (point-max)))))
        (narrow-to-region beg limit)
        (org-clock-sum start end)
        org-clock-file-total-minutes))))

(defun org-workflow-journal--seal-boundaries (date)
  "Return inactive timestamps bounding DATE's seal window."
  (list (format "[%s 00:00]" date)
        (format "[%s 22:00]" date)))

(defun org-workflow-journal--escape-table-cell (text)
  "Return TEXT escaped for an Org table cell."
  (replace-regexp-in-string "|" "\\vert" text t t))

(defun org-workflow-journal--escape-link-description (text)
  "Return TEXT escaped for an Org link description."
  (replace-regexp-in-string "]" "\\]" text t t))

(defun org-workflow-journal-rows (date)
  "Return final task and Focus facts for DATE's seal window."
  (let* ((bounds (org-workflow-journal--seal-boundaries date))
         (start (car bounds))
         (end (cadr bounds))
         rows)
    (dolist (file (org-agenda-files t))
      (when (file-readable-p file)
        (with-current-buffer (find-file-noselect file)
          (org-with-wide-buffer
           (when (org-workflow--file-kind)
             (org-map-entries
              (lambda ()
                (when (and (>= (org-outline-level) 2)
                           (org-get-todo-state))
                  (let* ((task-leaf (org-workflow-target--task-leaf-p))
                         (outcome
                          (and task-leaf
                               (org-workflow--outcome-on-date date)))
                         (minutes
                          (org-workflow-journal-direct-clock-minutes
                           (point-marker) start end)))
                    (when (or outcome (> minutes 0))
                      (let* ((id (org-entry-get nil "ID"))
                             (title (org-get-heading t t t t))
                             (table-title
                              (org-workflow-journal--escape-table-cell title))
                             (link-title
                              (org-workflow-journal--escape-link-description
                               table-title)))
                        (push
                         (list :id id
                               :title title
                               :link (if id
                                         (format "[[id:%s][%s]]" id link-title)
                                       table-title)
                               :task-leaf task-leaf
                               :promise (and (org-workflow--promise-p) t)
                               :outcome (or outcome 'focused)
                               :minutes minutes)
                         rows))))))
              nil 'file))))))
    (nreverse rows)))

(defun org-workflow-journal--rows-minutes (rows)
  "Return the sum of direct Focus minutes in ROWS."
  (seq-reduce (lambda (total row)
                (+ total (plist-get row :minutes)))
              rows 0))

(defun org-workflow-journal--final-data (date)
  "Return DATE's immutable journal summary from one final row query."
  (let* ((rows (org-workflow-journal-rows date))
         (promise
          (seq-filter
           (lambda (row)
             (and (plist-get row :task-leaf)
                  (plist-get row :promise)
                  (memq (plist-get row :outcome)
                        '(pending done ready held))))
           rows))
         (optional
          (seq-filter
           (lambda (row)
             (and (not (plist-get row :promise))
                  (or (> (plist-get row :minutes) 0)
                      (memq (plist-get row :outcome)
                            '(done ready held)))))
           rows))
         (outcome
          (cond
           ((null promise) 'untouch)
           ((seq-every-p
             (lambda (row)
               (memq (plist-get row :outcome) '(done ready held)))
             promise)
            'met)
           (t 'unmet)))
         (commitment-minutes
          (org-workflow-journal--rows-minutes
           (seq-filter (lambda (row) (plist-get row :promise)) rows)))
         (optional-minutes
          (org-workflow-journal--rows-minutes
           (seq-remove (lambda (row) (plist-get row :promise)) rows)))
         (optional-completed
          (seq-count
           (lambda (row)
             (memq (plist-get row :outcome) '(done ready)))
           optional)))
    (list :outcome outcome
          :promise-rows promise
          :optional-rows optional
          :commitment-minutes commitment-minutes
          :optional-minutes optional-minutes
          :optional-completed optional-completed)))

(defun org-workflow-journal--section (record kind title)
  "Return or create KIND section titled TITLE below RECORD."
  (org-with-point-at record
    (let ((record-level (org-outline-level)) regions)
      (save-restriction
        (org-narrow-to-subtree)
        (org-map-entries
         (lambda ()
           (when (and (= (org-outline-level) (1+ record-level))
                      (equal kind (org-entry-get nil "WORKFLOW_SECTION")))
             (push (cons (point)
                         (save-excursion
                           (org-end-of-subtree t t)
                           (point)))
                   regions)))
         nil 'tree))
      (setq regions (nreverse regions))
      (if regions
          (let ((section (copy-marker (caar regions))))
            (org-workflow-journal--delete-regions (cdr regions))
            (org-with-point-at section
              (org-edit-headline title))
            section)
        (let ((insert-at (save-excursion (org-end-of-subtree t t) (point))))
          (goto-char insert-at)
          (unless (bolp) (insert "\n"))
          (insert (make-string (1+ record-level) ?*) " " title "\n")
          (forward-line -1)
          (org-entry-put nil "WORKFLOW_SECTION" kind)
          (copy-marker (point)))))))

(defun org-workflow-journal--replace-section-body (section text)
  "Replace SECTION's direct body with TEXT."
  (org-with-point-at section
    (org-back-to-heading t)
    (let ((end (save-excursion (org-end-of-subtree t t) (point))))
      (org-end-of-meta-data t)
      (delete-region (point) end)
      (insert text)
      (unless (bolp) (insert "\n")))))

(defun org-workflow-journal--rows-table (rows)
  "Render workflow outcome ROWS as an Org table."
  (concat
   "| Task | Outcome | Focus |\n|------+---------+-------|\n"
   (mapconcat
    (lambda (row)
      (format "| %s | %s | %d |"
              (plist-get row :link)
              (symbol-name (plist-get row :outcome))
              (plist-get row :minutes)))
    rows "\n")
   "\n"))

(defun org-workflow-journal--delete-regions (regions)
  "Delete stable REGIONS from the end of the buffer backward."
  (dolist (region (sort (copy-sequence regions)
                        (lambda (left right)
                          (> (car left) (car right)))))
    (delete-region (car region) (cdr region))))

(defun org-workflow-journal--delete-section (record kind)
  "Delete generated KIND sections below RECORD when present."
  (org-with-point-at record
    (save-restriction
      (org-narrow-to-subtree)
      (let ((record-level (org-outline-level)) regions)
        (org-map-entries
         (lambda ()
           (when (and (= (org-outline-level) (1+ record-level))
                      (equal kind (org-entry-get nil "WORKFLOW_SECTION")))
             (push (cons (point)
                         (save-excursion
                           (org-end-of-subtree t t)
                           (point)))
                   regions)))
         nil 'tree)
        (org-workflow-journal--delete-regions regions)))))

(defun org-workflow-journal--write-finalized-record
    (summary record date data anchor)
  "Write DATE's finalized DATA and tracking ANCHOR to SUMMARY and RECORD."
  (org-with-point-at record
    (dolist (property '("COMMITMENT" "ID"
                        "WORKFLOW_TRACKING_STARTED"))
      (org-entry-delete nil property)))
  (org-workflow-journal--replace-section-body
   (org-workflow-journal--section
    record "minimum" "Minimum Commitment Progress")
   (org-workflow-journal--rows-table
    (plist-get data :promise-rows)))
  (org-workflow-journal--replace-section-body
   (org-workflow-journal--section record "optional" "Optional Work")
   (org-workflow-journal--rows-table
    (plist-get data :optional-rows)))
  (org-workflow-journal--delete-section record "summary")
  (org-with-point-at summary
    (org-entry-put nil "COMMITMENT"
                   (symbol-name (plist-get data :outcome)))
    (org-entry-put nil "COMMITMENT_FOCUS_MINUTES"
                   (number-to-string
                    (plist-get data :commitment-minutes)))
    (org-entry-put nil "OPTIONAL_FOCUS_MINUTES"
                   (number-to-string
                    (plist-get data :optional-minutes)))
    (org-entry-put nil "FOCUS_TOTAL_MINUTES"
                   (number-to-string
                    (+ (plist-get data :commitment-minutes)
                       (plist-get data :optional-minutes))))
    (org-entry-put nil "OPTIONAL_COMPLETED"
                   (number-to-string
                    (plist-get data :optional-completed)))
    (org-entry-put nil "WORKFLOW_TRACKING_STARTED"
                   (format "[%s]" anchor))
    (org-entry-put nil "WORKFLOW_FINALIZED_AT"
                   (format "[%s 22:00]" date))))

(defun org-workflow-journal--restore-file-bytes (backup journal-file)
  "Restore BACKUP bytes through the existing JOURNAL-FILE path."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally backup)
    (let ((coding-system-for-write 'no-conversion)
          (write-region-annotate-functions nil)
          (write-region-post-annotation-function nil))
      (write-region (point-min) (point-max)
                    journal-file nil 'silent))))

(defun org-workflow-journal-finalize (date)
  "Finalize DATE's journal once and return its commitment outcome."
  (let* ((time (org-workflow-journal--date-time date))
         (note (vulpea-journal-note time))
         (summary (org-workflow-journal--summary-marker note))
         (finalized
          (org-with-point-at summary
            (org-entry-get nil "WORKFLOW_FINALIZED_AT"))))
    (if finalized
        (intern (org-with-point-at summary
                  (org-entry-get nil "COMMITMENT")))
      (let ((data (org-workflow-journal--final-data date))
            (anchor (org-workflow-journal-ensure-anchor date)))
        (with-current-buffer (marker-buffer summary)
          (save-restriction
            (widen)
            (let* ((before (buffer-substring-no-properties
                            (point-min) (point-max)))
                   (was-modified (buffer-modified-p))
                   (journal-file buffer-file-name)
                   (backup
                    (make-nearby-temp-file
                     (expand-file-name
                      ".org-workflow-journal-"
                      (file-name-directory journal-file))))
                   disk-rollback-failed)
              (unwind-protect
                  (progn
                    (copy-file journal-file backup t t t t)
                    (condition-case error-data
                        (progn
                          (atomic-change-group
                            (let ((record
                                   (or (org-workflow-journal--find-record
                                        note date)
                                       (org-workflow-journal--create-record
                                        note date))))
                              (org-workflow-journal--write-finalized-record
                               summary record date data anchor)))
                          (save-buffer))
                      (error
                       (condition-case rollback-error
                           (let ((inhibit-read-only t))
                             (erase-buffer)
                             (insert before)
                             (set-buffer-modified-p was-modified))
                         (error
                          (message "Org Workflow buffer rollback failed: %s"
                                   (error-message-string rollback-error))))
                       (condition-case rollback-error
                           (org-workflow-journal--restore-file-bytes
                            backup journal-file)
                         (error
                          (setq disk-rollback-failed t)
                          (message "Org Workflow disk rollback failed; backup remains at %s: %s"
                                   backup
                                   (error-message-string rollback-error))))
                       (unless disk-rollback-failed
                         (condition-case rollback-error
                             (set-visited-file-modtime)
                           (error
                            (message "Org Workflow file timestamp refresh failed: %s"
                                     (error-message-string
                                      rollback-error)))))
                       (signal (car error-data) (cdr error-data)))))
                (when (and (not disk-rollback-failed)
                           (file-exists-p backup))
                  (ignore-errors (delete-file backup)))))))
        (org-workflow-journal--run-finalized-hook date)
        (org-workflow--request-gnome-refresh)
        (plist-get data :outcome)))))

(defun org-workflow-journal-catch-up (&optional now)
  "Finalize tracked dates through the local seal cutoff at NOW.

Today is eligible only at or after local 22:00.  Return the dates passed to
`org-workflow-journal-finalize' in chronological order."
  (let* ((now (or now (current-time)))
         (today (format-time-string "%Y-%m-%d" now))
         (decoded (decode-time now))
         (today-seal (encode-time 0 0 22
                                  (decoded-time-day decoded)
                                  (decoded-time-month decoded)
                                  (decoded-time-year decoded)))
         (cutoff (if (time-less-p now today-seal)
                     (org-workflow-journal--date-add-days today -1)
                   today))
         (date (org-workflow-journal-ensure-anchor today))
         finalized)
    (while (not (string> date cutoff))
      (org-workflow-journal-finalize date)
      (push date finalized)
      (setq date (org-workflow-journal--date-add-days date 1)))
    (nreverse finalized)))

(defun org-workflow-journal-status (date)
  "Return finalized compatibility status for ISO DATE, or nil."
  (when-let* ((note (vulpea-journal-find-note
                     (org-workflow-journal--date-time date)))
              (summary (org-workflow-journal--summary-marker note))
              (finalized
               (org-with-point-at summary
                 (org-entry-get nil "WORKFLOW_FINALIZED_AT"))))
    (let ((status (org-workflow--promise-progress date)))
      (plist-put status :phase "finalized")
      (plist-put status :commitmentComplete
                 (if (equal (org-entry-get summary "COMMITMENT") "met")
                     t :false))
      status)))

(defun org-workflow-journal--finalized-commitment (date)
  "Return DATE's sealed commitment outcome, or nil when it is unavailable."
  (when-let* ((boundary (org-workflow-journal-finalized-record date))
              (summary (plist-get boundary :summary-marker)))
    (org-with-point-at summary
      (pcase (org-entry-get nil "COMMITMENT")
        ("met" 'met)
        ("unmet" 'unmet)
        ("untouch" 'untouch)))))

(defun org-workflow-journal--commitment-streak-ending-at (date anchor)
  "Return the consecutive sealed `met' streak ending on DATE since ANCHOR."
  (let ((count 0))
    (while (and (not (string< date anchor))
                (eq (org-workflow-journal--finalized-commitment date) 'met))
      (cl-incf count)
      (setq date (org-workflow-journal--date-add-days date -1)))
    count))

(defun org-workflow-journal--open-before-seal-p (date &optional now)
  "Return non-nil when DATE is today's pre-seal Journal day at NOW.
NOW defaults to the current time."
  (let* ((now (or now (current-time)))
         (decoded (decode-time now))
         (seal-time (encode-time 0 0 22
                                 (decoded-time-day decoded)
                                 (decoded-time-month decoded)
                                 (decoded-time-year decoded))))
    (and (equal date (format-time-string "%Y-%m-%d" now))
         (time-less-p now seal-time))))

(defun org-workflow-journal-commitment-streak (date daily &optional now)
  "Return DATE's Journal-owned commitment streak using live DAILY progress.

Sealed `met' records alone extend the historical streak.  Only before DATE's
local 22:00 seal does a complete live minimum commitment provisionally add one
day; after that cutoff a missing record interrupts the streak.  NOW is for
deterministic callers and tests."
  (let* ((anchor (org-workflow-journal-ensure-anchor date))
         (today-outcome (org-workflow-journal--finalized-commitment date)))
    (cond
     (today-outcome
      (org-workflow-journal--commitment-streak-ending-at date anchor))
     ((not (org-workflow-journal--open-before-seal-p date now)) 0)
     (t
      (let ((base (org-workflow-journal--commitment-streak-ending-at
                   (org-workflow-journal--date-add-days date -1) anchor)))
        (if (eq (plist-get daily :commitmentComplete) t)
            (1+ base)
          base))))))

(defun org-workflow-journal-setup ()
  "Expose finalized status, catch up, and schedule the next daily seal."
  (org-workflow-journal--retire-obsolete-midnight-timer)
  (setq org-workflow-status-provider-function
        #'org-workflow-journal-status)
  (setq org-workflow-commitment-streak-provider-function
        #'org-workflow-journal-commitment-streak)
  (org-workflow-journal--schedule-seal)
  (condition-case error-data
      (org-workflow-journal-catch-up)
    (error
     (org-workflow--notify
      "Org Workflow journal"
      (error-message-string error-data)))))

(provide 'org-workflow-journal)
;;; org-workflow-journal.el ends here
