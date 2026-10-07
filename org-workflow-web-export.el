;;; org-workflow-web-export.el --- org-workflow-web-export Workflow component -*- lexical-binding: t; -*-
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
;;; org-workflow-web-export.el --- Export sealed Workflow history -*- lexical-binding: t; -*-

;;; Code:

(require 'calendar)

(require 'cl-lib)

(require 'json)

(require 'org)

(require 'org-element)

(require 'org-table)

(require 'subr-x)

(require 'vulpea-journal)

(require 'org-workflow-journal)

(defconst org-workflow-web-export-schema "org-workflow-history")

(defconst org-workflow-web-export-schema-version 1)

(defgroup org-workflow-web-export nil
  "Static export of finalized Org Workflow history."
  :group 'org)

(defcustom org-workflow-web-export-file
  (expand-file-name "web/public/data/workflow-history.v1.json"
                    user-emacs-directory)
  "Generated historical dashboard JSON file."
  :type 'file
  :group 'org-workflow-web-export)

(defconst org-workflow-web-export--timezone "Asia/Shanghai")

(defconst org-workflow-web-export--commitments
  '("met" "unmet" "untouch"))

(defconst org-workflow-web-export--task-outcomes
  '("pending" "done" "ready" "held" "focused"))

(defun org-workflow-web-export--date-add-days (date days)
  "Return ISO DATE shifted by calendar DAYS."
  (unless (string-match
           "\\`\\([0-9]\\{4\\}\\)-\\([0-9]\\{2\\}\\)-\\([0-9]\\{2\\}\\)\\'"
           date)
    (error "Invalid Workflow date: %S" date))
  (let* ((year (string-to-number (match-string 1 date)))
         (month (string-to-number (match-string 2 date)))
         (day (string-to-number (match-string 3 date)))
         (gregorian (list month day year)))
    (unless (calendar-date-is-valid-p gregorian)
      (error "Invalid Workflow date: %S" date))
    (pcase-let ((`(,next-month ,next-day ,next-year)
                 (calendar-gregorian-from-absolute
                  (+ days (calendar-absolute-from-gregorian gregorian)))))
      (format "%04d-%02d-%02d" next-year next-month next-day))))

(defun org-workflow-web-export--eligible-through (now)
  "Return the latest date eligible for sealing at NOW."
  (let* ((decoded (decode-time now org-workflow-web-export--timezone))
         (today (format-time-string
                 "%Y-%m-%d" now org-workflow-web-export--timezone))
         (seal (encode-time
                0 0 22
                (decoded-time-day decoded)
                (decoded-time-month decoded)
                (decoded-time-year decoded)
                org-workflow-web-export--timezone)))
    (if (time-less-p now seal)
        (org-workflow-web-export--date-add-days today -1)
      today)))

(defun org-workflow-web-export--timestamp-date (value property)
  "Return the strict ISO date from Org timestamp VALUE for PROPERTY."
  (unless (and (stringp value)
               (string-match
                "\\`\\[\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)\\]\\'"
                value))
    (error "Invalid %s: %S" property value))
  (let ((date (match-string 1 value)))
    (org-workflow-web-export--date-add-days date 0)
    date))

(defun org-workflow-web-export--timestamp-iso (value property)
  "Return strict local ISO timestamp from Org VALUE for PROPERTY."
  (unless (and (stringp value)
               (string-match
                (concat
                 "\\`\\["
                 "\\([0-9]\\{4\\}\\)-\\([0-9]\\{2\\}\\)-\\([0-9]\\{2\\}\\) "
                 "\\([0-9]\\{2\\}\\):\\([0-9]\\{2\\}\\)"
                 "\\]\\'")
                value))
    (error "Invalid %s: %S" property value))
  (let* ((year (string-to-number (match-string 1 value)))
         (month (string-to-number (match-string 2 value)))
         (day (string-to-number (match-string 3 value)))
         (hour (string-to-number (match-string 4 value)))
         (minute (string-to-number (match-string 5 value))))
    (unless (and (calendar-date-is-valid-p (list month day year))
                 (< hour 24)
                 (< minute 60))
      (error "Invalid %s: %S" property value))
    (format-time-string
     "%Y-%m-%dT%H:%M:%S%:z"
     (encode-time 0 minute hour day month year
                  org-workflow-web-export--timezone)
     org-workflow-web-export--timezone)))

(defun org-workflow-web-export--property (marker name)
  "Read required root property NAME at MARKER without changing state."
  (let ((value
         (org-with-point-at marker
           (save-restriction
             (widen)
             (org-entry-get nil name)))))
    (unless value
      (error "Finalized Workflow property unavailable: %s" name))
    value))

(defun org-workflow-web-export--non-negative-integer (value field)
  "Parse exact non-negative decimal VALUE for FIELD."
  (unless (and (stringp value) (string-match-p "\\`[0-9]+\\'" value))
    (error "Invalid %s: %S" field value))
  (string-to-number value))

(defun org-workflow-web-export--plain-org-nodes (nodes)
  "Render parsed Org secondary NODES as plain display text."
  (mapconcat
   (lambda (node)
     (cond
      ((stringp node)
       (replace-regexp-in-string "\\\\]" "]"
                                 (substring-no-properties node) t t))
      ((not (consp node)) "")
      ((eq (org-element-type node) 'entity)
       (concat (or (org-element-property :utf-8 node)
                   (org-element-property :ascii node)
                   "")
               (make-string (or (org-element-property :post-blank node) 0)
                            ?\s)))
      ((eq (org-element-type node) 'link)
       (let ((description (org-element-contents node)))
         (unless description
           (error "Generated task link has no display description"))
         (org-workflow-web-export--plain-org-nodes description)))
      (t
       (concat
        (let ((contents (org-element-contents node))
              (value (org-element-property :value node)))
          (cond
           (contents
            (org-workflow-web-export--plain-org-nodes contents))
           ((stringp value) value)
           (t "")))
        (make-string (or (org-element-property :post-blank node) 0)
                     ?\s)))))
   nodes ""))

(defun org-workflow-web-export--plain-task (cell)
  "Return CELL's plain Org display title without link identity."
  (let* ((tree (org-element-parse-secondary-string cell '(link entity)))
         (text (string-trim
                (org-workflow-web-export--plain-org-nodes tree))))
    (when (string-empty-p text)
      (error "Generated task title is empty"))
    text))

(defun org-workflow-web-export--section-marker (record kind)
  "Return RECORD's sole direct generated section of KIND."
  (org-with-point-at record
    (save-restriction
      (org-narrow-to-subtree)
      (let ((record-level (org-outline-level)) markers)
        (org-map-entries
         (lambda ()
           (when (and (= (org-outline-level) (1+ record-level))
                      (equal kind (org-entry-get nil "WORKFLOW_SECTION")))
             (push (copy-marker (point)) markers)))
         nil 'tree)
        (unless (= 1 (length markers))
          (error "Expected one generated %s table, found %d"
                 kind (length markers)))
        (car markers)))))

(defun org-workflow-web-export--table-lisp (section kind)
  "Return the sole well-formed Org table under SECTION for KIND."
  (org-with-point-at section
    (save-restriction
      (org-back-to-heading t)
      (let ((body-start (progn (org-end-of-meta-data t) (point)))
            (body-end (save-excursion
                        (if (outline-next-heading) (point) (point-max)))))
        (narrow-to-region body-start body-end)
        (goto-char (point-min))
        (unless (re-search-forward "^[ \t]*|" nil t)
          (error "Malformed generated %s table" kind))
        (goto-char (line-beginning-position))
        (unless (org-at-table-p)
          (error "Malformed generated %s table" kind))
        (let* ((table-begin (org-table-begin))
               (table-end (org-table-end))
               (before (string-trim
                        (buffer-substring-no-properties
                         (point-min) table-begin)))
               (after (string-trim
                       (buffer-substring-no-properties
                        table-end (point-max))))
               (table (org-table-to-lisp)))
          (unless (and (string-empty-p before) (string-empty-p after))
            (error "Malformed generated %s table body" kind))
          table)))))

(defun org-workflow-web-export--tasks (record kind)
  "Return validated task vectors from RECORD's generated KIND table."
  (let* ((table
          (org-workflow-web-export--table-lisp
           (org-workflow-web-export--section-marker record kind) kind))
         (header (car table))
         (separator (cadr table))
         (rows (cddr table)))
    (unless (and (equal header '("Task" "Outcome" "Focus"))
                 (eq separator 'hline)
                 (cl-every (lambda (row)
                             (and (listp row) (= 3 (length row))))
                           rows))
      (error "Malformed generated %s table cells" kind))
    (vconcat
     (mapcar
      (lambda (row)
        (pcase-let ((`(,task ,outcome ,focus) row))
          (unless (member outcome org-workflow-web-export--task-outcomes)
            (error "Invalid task outcome: %S" outcome))
          (list :task (org-workflow-web-export--plain-task task)
                :outcome outcome
                :focusMinutes
                (org-workflow-web-export--non-negative-integer
                 focus "task Focus"))))
      rows))))

(defun org-workflow-web-export--finalized-day (date record)
  "Convert finalized RECORD for DATE into one schema-v1 day object."
  (let* ((summary (plist-get record :summary-marker))
         (record-marker (plist-get record :record-marker))
         (record-date (plist-get record :date))
         (boundary-finalized (plist-get record :finalized-at))
         (commitment
          (org-workflow-web-export--property summary "COMMITMENT"))
         (finalized
          (org-workflow-web-export--property
           summary "WORKFLOW_FINALIZED_AT"))
         (commitment-focus
          (org-workflow-web-export--non-negative-integer
           (org-workflow-web-export--property
            summary "COMMITMENT_FOCUS_MINUTES")
           "COMMITMENT_FOCUS_MINUTES"))
         (optional-focus
          (org-workflow-web-export--non-negative-integer
           (org-workflow-web-export--property
            summary "OPTIONAL_FOCUS_MINUTES")
           "OPTIONAL_FOCUS_MINUTES"))
         (focus-total
          (org-workflow-web-export--non-negative-integer
           (org-workflow-web-export--property summary "FOCUS_TOTAL_MINUTES")
           "FOCUS_TOTAL_MINUTES")))
    (unless (and (markerp summary) (marker-buffer summary)
                 (markerp record-marker) (marker-buffer record-marker))
      (error "Finalized Workflow markers unavailable for %s" date))
    (unless (equal date record-date)
      (error "Finalized Workflow date mismatch: %S" record-date))
    (unless (equal finalized boundary-finalized)
      (error "Finalized Workflow timestamp boundary mismatch for %s" date))
    (unless (member commitment org-workflow-web-export--commitments)
      (error "Invalid commitment: %S" commitment))
    (unless (= focus-total (+ commitment-focus optional-focus))
      (error "Inconsistent Focus total for %s" date))
    (list
     :date date
     :recordState "finalized"
     :commitment commitment
     :commitmentFocusMinutes
     commitment-focus
     :optionalFocusMinutes
     optional-focus
     :focusTotalMinutes
     focus-total
     :optionalCompleted
     (org-workflow-web-export--non-negative-integer
      (org-workflow-web-export--property summary "OPTIONAL_COMPLETED")
      "OPTIONAL_COMPLETED")
     :finalizedAt
     (org-workflow-web-export--timestamp-iso
      finalized "WORKFLOW_FINALIZED_AT")
     :minimumTasks (org-workflow-web-export--tasks record-marker "minimum")
     :optionalTasks (org-workflow-web-export--tasks record-marker "optional"))))

(defun org-workflow-web-export--candidate-records ()
  "Return finalized public records for existing Journal dates."
  (let (records seen)
    (dolist (time (vulpea-journal-all-dates))
      (let ((date (format-time-string
                   "%Y-%m-%d" time org-workflow-web-export--timezone)))
        (unless (member date seen)
          (push date seen)
          (when-let* ((record
                      (org-workflow-journal-finalized-record date)))
            (push (cons date record) records)))))
    records))

(defun org-workflow-web-export--tracking-started (records)
  "Return the earliest validated tracking anchor in RECORDS."
  (let (anchors)
    (dolist (entry records)
      (let* ((record (cdr entry))
             (summary (plist-get record :summary-marker))
             (anchor
              (org-workflow-web-export--timestamp-date
               (org-workflow-web-export--property
                summary "WORKFLOW_TRACKING_STARTED")
               "WORKFLOW_TRACKING_STARTED")))
        (push anchor anchors)))
    (car (sort anchors #'string-lessp))))

(defun org-workflow-web-export--days (tracking-started eligible-through
                                                        records)
  "Return daily objects from TRACKING-STARTED through ELIGIBLE-THROUGH.

RECORDS caches records found while deriving the anchor."
  (let ((date tracking-started) days)
    (while (not (string-lessp eligible-through date))
      (let ((record
             (or (cdr (assoc date records))
                 (org-workflow-journal-finalized-record date))))
        (push (if record
                  (org-workflow-web-export--finalized-day date record)
                (list :date date :recordState "missing"))
              days))
      (setq date (org-workflow-web-export--date-add-days date 1)))
    (vconcat (nreverse days))))

(defun org-workflow-web-export--payload (now)
  "Build and validate the full schema-v1 payload at NOW."
  (let* ((eligible-through
          (org-workflow-web-export--eligible-through now))
         (records (org-workflow-web-export--candidate-records))
         (tracking-started
          (org-workflow-web-export--tracking-started records)))
    (when (and tracking-started
               (string-lessp eligible-through tracking-started))
      (error
       "Cannot export Workflow history: tracking started %s is after eligible through %s"
       tracking-started eligible-through))
    (list
     :schema org-workflow-web-export-schema
     :schemaVersion org-workflow-web-export-schema-version
     :generatedAt
     (format-time-string "%Y-%m-%dT%H:%M:%S%:z" now
                         org-workflow-web-export--timezone)
     :timezone org-workflow-web-export--timezone
     :coverage
     (if tracking-started
         (list :trackingStarted tracking-started
               :eligibleThrough eligible-through)
       :null)
     :days
     (if tracking-started
         (org-workflow-web-export--days
          tracking-started eligible-through records)
       []))))

(defun org-workflow-web-export--write-atomically (payload)
  "Serialize PAYLOAD and atomically replace the configured snapshot."
  (let* ((target (expand-file-name org-workflow-web-export-file))
         (directory (file-name-directory target))
         (json (json-serialize payload))
         temp)
    (make-directory directory t)
    (setq temp
          (make-nearby-temp-file
           (expand-file-name ".org-workflow-web-export-" directory)))
    (unwind-protect
        (let ((coding-system-for-write 'utf-8-unix)
              (write-region-annotate-functions nil)
              (write-region-post-annotation-function nil))
          (with-temp-buffer
            (set-buffer-multibyte t)
            (insert json "\n")
            (write-region (point-min) (point-max) temp nil 'silent))
          (rename-file temp target t)
          (setq temp nil)
          target)
      (when (and temp (file-exists-p temp))
        (ignore-errors (delete-file temp))))))

;;;###autoload
(defun org-workflow-web-export-history (&optional now)
  "Export finalized Workflow history at NOW and return its pathname.

NOW is a time value intended for deterministic tests."
  (interactive)
  (org-workflow-web-export--write-atomically
   (org-workflow-web-export--payload (or now (current-time)))))

(defun org-workflow-web-export-after-finalize (_date)
  "Refresh the history snapshot after a finalized Journal DATE event."
  (org-workflow-web-export-history))

(defun org-workflow-web-export-setup ()
  "Install the post-finalization exporter and perform an initial export."
  (org-workflow--add-hook 'org-workflow-journal-finalized-hook
            #'org-workflow-web-export-after-finalize)
  (condition-case error-data
      (org-workflow-web-export-history)
    (error
     (message "Org Workflow web export failed: %s"
              (error-message-string error-data))))
  nil)

(defcustom org-workflow-web-open-function nil
  "Optional function that opens the separately installed web dashboard."
  :type '(choice (const nil) function) :group 'org-workflow)

;;;###autoload
(defun org-workflow-web-open ()
  "Export current history and invoke the configured web launcher."
  (interactive)
  (unless org-workflow-web-open-function
    (user-error "Configure org-workflow-web-open-function or use native history"))
  (org-workflow-web-export-history)
  (funcall org-workflow-web-open-function))

(defun org-workflow-web-export--enable ()
  "Install this component while Workflow is being enabled."
  (org-workflow--global-set-key "C-c o H" #'org-workflow-web-open))

(provide 'org-workflow-web-export)
;;; org-workflow-web-export.el ends here
