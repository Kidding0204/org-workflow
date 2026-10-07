;;; org-workflow-store.el --- org-workflow-store Workflow component -*- lexical-binding: t; -*-
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
;;; org-workflow-store.el --- Persistent Workflow facts -*- lexical-binding: t; -*-
(require 'sqlite)

(require 'org-id)

(require 'json)

(require 'cl-lib)

(defcustom org-workflow-store-file
  (expand-file-name "var/org-workflow.sqlite" user-emacs-directory)
  "Persistent facts.  Back up this file together with the Org sources."
  :type 'file :group 'org)

(defvar org-workflow-store-enabled nil)

(defvar org-workflow-store--connection nil)

(defvar org-workflow-store--path nil)

(defvar org-workflow-store--in-operation nil)

(defvar org-workflow-store--read-only nil
  "Non-nil requires an already initialized, matching live connection.")

(defun org-workflow-store--live-p (db)
  "Return non-nil when DB accepts a simple query."
  (and db (condition-case nil (progn (sqlite-select db "SELECT 1") t) (error nil))))

(defun org-workflow-store--db ()
  "Open and version the persistent store."
  (when (and org-workflow-store--read-only
             (not (and org-workflow-store--connection
                       (equal org-workflow-store--path org-workflow-store-file)
                       (org-workflow-store--live-p org-workflow-store--connection))))
    (error "Workflow history backend not ready: no matching live connection"))
  (unless (and org-workflow-store--connection
               (equal org-workflow-store--path org-workflow-store-file)
               (org-workflow-store--live-p org-workflow-store--connection))
    (when (and org-workflow-store--connection (org-workflow-store--live-p org-workflow-store--connection))
      (sqlite-close org-workflow-store--connection))
    (make-directory (file-name-directory org-workflow-store-file) t)
    (setq org-workflow-store--connection (sqlite-open org-workflow-store-file)
          org-workflow-store--path org-workflow-store-file)
    (sqlite-execute org-workflow-store--connection "PRAGMA foreign_keys=ON")
    (let ((version (caar (sqlite-select org-workflow-store--connection "PRAGMA user_version"))))
      (unless (memq version '(0 1)) (error "Unsupported Workflow database version %s" version)))
    (dolist (sql '("CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY,value TEXT NOT NULL)"
                   "CREATE TABLE IF NOT EXISTS commitments(id TEXT PRIMARY KEY,task_id TEXT NOT NULL,created_at TEXT,due TEXT NOT NULL,original_title TEXT NOT NULL,title TEXT NOT NULL,status TEXT NOT NULL,adjusted INTEGER NOT NULL DEFAULT 0)"
                   "CREATE TABLE IF NOT EXISTS events(seq INTEGER PRIMARY KEY,id TEXT NOT NULL,at TEXT NOT NULL,kind TEXT NOT NULL,payload TEXT NOT NULL)"
                   "CREATE TABLE IF NOT EXISTS habit_days(date TEXT PRIMARY KEY,payload TEXT NOT NULL)"
                   "CREATE TABLE IF NOT EXISTS days(date TEXT PRIMARY KEY,payload TEXT NOT NULL)"
                   "CREATE TABLE IF NOT EXISTS leave_records(id TEXT PRIMARY KEY,date TEXT NOT NULL,payload TEXT NOT NULL)"
                   "CREATE TABLE IF NOT EXISTS operations(id TEXT PRIMARY KEY,state TEXT NOT NULL,before_text TEXT NOT NULL,after_text TEXT)"
                   "PRAGMA user_version=1"))
      (sqlite-execute org-workflow-store--connection sql)))
  org-workflow-store--connection)

(defun org-workflow-store--encode (value)
  "Serialize VALUE for persistent storage as readable Lisp text."
  (prin1-to-string value))

(defun org-workflow-store--decode (value)
  "Read stored VALUE with evaluation disabled, or return nil for nil."
  (when value (let ((read-eval nil)) (read value))))

(defun org-workflow-store-leaves (date)
  "Read explicit activity explanations for DATE, separate from work totals."
  (let ((db (org-workflow-store--db)))
    ;; Allow hot activation with a connection opened before this table existed.
    (unless org-workflow-store--read-only
      (sqlite-execute db "CREATE TABLE IF NOT EXISTS leave_records(id TEXT PRIMARY KEY,date TEXT NOT NULL,payload TEXT NOT NULL)"))
    (vconcat
     (mapcar (lambda (row) (org-workflow-store--decode (car row)))
             (sqlite-select db "SELECT payload FROM leave_records WHERE date=? ORDER BY rowid"
                            (list date))))))

(defun org-workflow-store-put-leave (record)
  "Insert one immutable explanation RECORD without changing commitments."
  (org-workflow-store-leaves (plist-get record :date))
  (sqlite-execute (org-workflow-store--db) "INSERT INTO leave_records VALUES(?,?,?)"
                  (list (plist-get record :id) (plist-get record :date)
                        (org-workflow-store--encode record))))

(defun org-workflow-store-habit-days ()
  "Read synchronized habit facts without conflating missing data with zero."
  (mapcar (lambda (row) (cons (car row) (org-workflow-store--decode (cadr row))))
          (sqlite-select (org-workflow-store--db) "SELECT date,payload FROM habit_days ORDER BY date")))

(defun org-workflow-store-meta (key)
  "Return the stored metadata value for KEY."
  (caar (sqlite-select (org-workflow-store--db) "SELECT value FROM meta WHERE key=?" (list key))))

(defun org-workflow-store-set-meta (key value)
  "Store metadata VALUE under KEY, replacing any existing value."
  (sqlite-execute (org-workflow-store--db) "INSERT OR REPLACE INTO meta VALUES(?,?)" (list key value)))

(defun org-workflow-store--now ()
  "Return the current local timestamp with numeric timezone offset."
  (format-time-string "%Y-%m-%dT%H:%M:%S%z"))

(defun org-workflow-store--event (id kind &optional payload)
  "Append an event of KIND for commitment ID with optional PAYLOAD."
  (sqlite-execute (org-workflow-store--db)
                  "INSERT INTO events(id,at,kind,payload) VALUES(?,?,?,?)"
                  (list id (org-workflow-store--now) kind (org-workflow-store--encode payload))))

(defun org-workflow-store-commitment (id)
  "Return ID's current record; historical changes remain in events."
  (when id
    (car (sqlite-select (org-workflow-store--db)
                        "SELECT id,task_id,created_at,due,original_title,title,status,adjusted FROM commitments WHERE id=?"
                        (list id)))))

(defun org-workflow-store-due (date)
  "Return commitments due on DATE, excluding cancelled records."
  (sqlite-select (org-workflow-store--db)
                 "SELECT id,task_id,created_at,due,original_title,title,status,adjusted FROM commitments WHERE due=? AND status!='cancelled'"
                 (list date)))

(defun org-workflow-store-promise-p (&optional marker)
  "Return non-nil when MARKER, or point, has an active commitment."
  (org-with-point-at (or marker (point-marker))
                     (when-let* ((row (org-workflow-store-commitment (org-entry-get nil "WORKFLOW_COMMITMENT_ID")))
                                 ((not (member (nth 6 row) '("cancelled" "withdrawn"))))) t)))

(defun org-workflow-store--attach (row)
  "Attach commitment ROW's identifier to the heading at point."
  (org-entry-put nil "WORKFLOW_COMMITMENT_ID" (nth 0 row)))

(defun org-workflow-store--detach ()
  "Remove commitment reference properties from the heading at point."
  (dolist (property '("WORKFLOW_COMMITMENT_ID" "WORKFLOW_COMMITTED_AT" "WORKFLOW_COMMITTED_FOR"))
    (org-entry-delete nil property)))

(defun org-workflow-store-create (date &optional unknown)
  "Create a draft for DATE at point; UNKNOWN preserves uncertain legacy time."
  (let* ((id (org-id-new)) (task (org-id-get-create))
         (created (unless unknown (org-workflow-store--now)))
         (title (org-get-heading t t t t)))
    (sqlite-execute (org-workflow-store--db)
                    "INSERT INTO commitments VALUES(?,?,?,?,?,?,?,0)"
                    (list id task created date title title "pending"))
    (org-workflow-store--attach (org-workflow-store-commitment id))
    (org-workflow-store--event id "created" (list :unknown unknown :date date))
    id))

(defun org-workflow-store--resolve (row status)
  "Set commitment ROW to STATUS and append the corresponding event."
  (sqlite-execute (org-workflow-store--db) "UPDATE commitments SET status=? WHERE id=?"
                  (list status (car row)))
  (org-workflow-store--event (car row) status))

(defun org-workflow-store-schedule (before after)
  "Record a schedule change from BEFORE to AFTER for the heading at point.
Preserve the effective dates of historical promises."
  (let* ((today (org-workflow-target--today-string))
         (row (org-workflow-store-commitment (org-entry-get nil "WORKFLOW_COMMITMENT_ID")))
         (tomorrow (format-time-string "%F" (encode-time 0 0 12
                                                         (1+ (string-to-number (substring today 8)))
                                                         (string-to-number (substring today 5 7))
                                                         (string-to-number (substring today 0 4))))))
    (when (and row (not (equal before after)))
      (cond
       ((string< today (nth 3 row))
        (org-workflow-store--resolve row "cancelled")
        (org-workflow-store--detach) (setq row nil))
       ((or (null after) (string< (nth 3 row) after))
        (org-workflow-store--resolve row (if after "deferred" "withdrawn"))
        (when (or (null after) (equal after tomorrow))
          (org-workflow-store--detach) (setq row nil)))))
    (when (and (equal after tomorrow) (null row))
      (org-workflow-store-create after))))

(defun org-workflow-store-state (state)
  "Synchronize commitment status with heading TODO STATE."
  (when-let* ((row (org-workflow-store-commitment (org-entry-get nil "WORKFLOW_COMMITMENT_ID"))))
    (org-workflow-store--resolve row
                                 (cond ((equal state "DONE") (if (= 1 (nth 7 row)) "adjusted-done" "done"))
                                       ((equal state "HOLD") "held") (t "pending")))))

(defun org-workflow-store-transfer (source target)
  "Transfer responsibility from SOURCE to TARGET without erasing original scope."
  (when-let* ((row (org-with-point-at source
                                     (org-workflow-store-commitment (org-entry-get nil "WORKFLOW_COMMITMENT_ID")))))
    (org-with-point-at target
                       (let ((task (org-id-get-create)) (title (org-get-heading t t t t)))
                         (sqlite-execute (org-workflow-store--db)
                                         "UPDATE commitments SET task_id=?,title=?,adjusted=1 WHERE id=?"
                                         (list task title (car row)))
                         (org-workflow-store--event (car row) "scope-adjusted"
                                                    (list :from (nth 1 row) :to task :title title))
                         (org-workflow-store--attach (org-workflow-store-commitment (car row)))))
    (org-with-point-at source (org-workflow-store--detach))))

(defvar org-workflow-store--extra-source-files nil
  "Additional participants in the current operation, such as historical collections.")

(defun org-workflow-store--sources ()
  "Capture source buffers for crash recovery, never serialize Agenda buffers."
  (mapcar (lambda (file)
            (with-current-buffer (find-file-noselect file)
              (save-restriction (widen)
                                (list (expand-file-name file) (buffer-substring-no-properties (point-min) (point-max))))))
          (seq-filter
           #'file-readable-p
           (delete-dups
            (append (org-agenda-files t) org-workflow-store--extra-source-files
                    (when (and (derived-mode-p 'org-mode) buffer-file-name)
                      (list buffer-file-name))
                    (when (derived-mode-p 'org-agenda-mode)
                      (delq nil
                            (mapcar (lambda (marker)
                                      (when (and (markerp marker) (marker-buffer marker))
                                        (buffer-file-name (marker-buffer marker))))
                                    (or org-agenda-bulk-marked-entries
                                        (list (org-get-at-bol 'org-hd-marker)))))))))))

(defun org-workflow-store--operation (original &rest args)
  "Call ORIGINAL with ARGS inside a coordinated Org and facts transaction.
Retain recoverable source images when committing or rolling back changes."
  (if (or (not org-workflow-store-enabled) org-workflow-store--in-operation)
      (apply original args)
    (let* ((org-workflow-store--in-operation t)
           (org-workflow--normalizing t)
           (db (org-workflow-store--db)) (id (org-id-new))
           (before (org-workflow-store--sources))
           (org-workflow-store--extra-source-files (mapcar #'car before))
           (groups (mapcan (lambda (item) (prepare-change-group (get-file-buffer (car item)))) before))
           committed result)
      (sqlite-execute db "INSERT INTO operations VALUES(?,'prepared',?,NULL)"
                      (list id (org-workflow-store--encode before)))
      (activate-change-group groups)
      (unwind-protect
          (progn
            (sqlite-execute db "BEGIN IMMEDIATE")
            (setq result (apply original args))
            (sqlite-execute db "UPDATE operations SET state='applied',after_text=? WHERE id=?"
                            (list (org-workflow-store--encode
                                   (seq-remove (lambda (item) (equal (cadr item) (cadr (assoc (car item) before))))
                                               (org-workflow-store--sources))) id))
            (sqlite-execute db "COMMIT")
            (setq committed t)
            (accept-change-group groups))
        (unless committed
          (ignore-errors (sqlite-execute db "ROLLBACK"))
          (cancel-change-group groups)
          (sqlite-execute db "UPDATE operations SET state='rolled-back' WHERE id=?" (list id))))
      ;; Saves inside the operation skip the save hook until facts commit.
      (let ((org-workflow-store--in-operation nil)) (org-workflow-store-checkpoint))
      (let ((org-workflow-store--in-operation nil)) (org-workflow-target-refresh t))
      result)))

(defun org-workflow-store-recover ()
  "Validate all pending file versions before restoring the latest source image."
  (dolist (op (sqlite-select (org-workflow-store--db)
                             "SELECT id,before_text FROM operations WHERE state='prepared'"))
    (dolist (entry (org-workflow-store--decode (cadr op)))
      (unless (and (file-readable-p (car entry))
                   (with-temp-buffer (insert-file-contents (car entry))
                                     (equal (buffer-string) (cadr entry))))
        (error "Unfinished Workflow operation %s requires recovery: %s" (car op) (car entry))))
    (sqlite-execute (org-workflow-store--db) "UPDATE operations SET state='rolled-back' WHERE id=?" (list (car op))))
  (let ((versions (make-hash-table :test #'equal))
        (latest (make-hash-table :test #'equal)) restore)
    (dolist (op (sqlite-select (org-workflow-store--db)
                               "SELECT before_text,after_text FROM operations WHERE state='applied' ORDER BY rowid"))
      (let ((before (org-workflow-store--decode (car op))))
        (dolist (entry (org-workflow-store--decode (cadr op)))
          (push (cadr (assoc (car entry) before)) (gethash (car entry) versions))
          (push (cadr entry) (gethash (car entry) versions))
          (puthash (car entry) (cadr entry) latest))))
    (maphash
     (lambda (file text)
       (unless (file-readable-p file) (error "Missing Workflow recovery source %s" file))
       (with-current-buffer (find-file-noselect file)
         (save-restriction (widen)
                           (let ((current (buffer-substring-no-properties (point-min) (point-max))))
                             (unless (equal current text)
                               (unless (member current (gethash file versions))
                                 (error "Workflow recovery conflict in %s" file))
                               (push (cons (current-buffer) text) restore)))))) latest)
    (dolist (item restore)
      (with-current-buffer (car item)
        (save-restriction (widen) (erase-buffer) (insert (cdr item)))
        (message "Recovered Workflow edits in %s; save to persist" (buffer-name))))))

(defun org-workflow-store--after-save ()
  "A successful source save supersedes its earlier recovery images."
  (org-workflow-store-checkpoint buffer-file-name))

(defun org-workflow-store-checkpoint (&optional saved-file)
  "Retire persisted recovery images independently for each source.
Normally disk must match the latest image.  SAVED-FILE also acknowledges
later edits, provided its visiting buffer is unmodified and matches disk.
Pass it only after a successful save, never to bypass startup conflicts."
  (when (and org-workflow-store-enabled (not org-workflow-store--in-operation))
    (let* ((db (org-workflow-store--db))
           (pending (sqlite-select db
                                  "SELECT id,after_text FROM operations WHERE state='applied' ORDER BY rowid DESC"))
           (latest (make-hash-table :test #'equal))
           (persisted (make-hash-table :test #'equal)) committed)
      (dolist (op pending)
        (dolist (entry (org-workflow-store--decode (cadr op)))
          (unless (gethash (car entry) latest)
            (puthash (car entry) (cadr entry) latest))))
      (maphash
       (lambda (file text)
         (when (file-readable-p file)
           (let ((disk (with-temp-buffer (insert-file-contents file) (buffer-string)))
                 (buffer (get-file-buffer file)))
             (when (or (equal disk text)
                       (and saved-file (equal (expand-file-name saved-file) file)
                            buffer
                            (with-current-buffer buffer
                              (and (not (buffer-modified-p))
                                   (save-restriction
                                     (widen)
                                     (equal disk (buffer-substring-no-properties
                                                  (point-min) (point-max))))))))
               (puthash file t persisted))))) latest)
      (sqlite-execute db "BEGIN IMMEDIATE")
      (unwind-protect
          (progn
            (dolist (op pending)
              (let* ((after (org-workflow-store--decode (cadr op)))
                     (remaining (seq-remove (lambda (entry) (gethash (car entry) persisted)) after)))
                (cond
                 ((null remaining)
                  (sqlite-execute db
                                  "UPDATE operations SET state='saved',before_text='nil',after_text=NULL WHERE id=? AND state='applied'"
                                  (list (car op))))
                 ((not (equal after remaining))
                  (sqlite-execute db "UPDATE operations SET after_text=? WHERE id=? AND state='applied'"
                                  (list (org-workflow-store--encode remaining) (car op)))))))
            (sqlite-execute db "COMMIT")
            (setq committed t))
        (unless committed
          (ignore-errors (sqlite-execute db "ROLLBACK")))))))

(defun org-workflow-store-day (date)
  "Return the persisted settlement for DATE, or nil when absent."
  (org-workflow-store--decode
   (caar (sqlite-select (org-workflow-store--db) "SELECT payload FROM days WHERE date=?" (list date)))))

(defun org-workflow-store-days ()
  "Return all persisted settlements ordered by date."
  (mapcar (lambda (row) (org-workflow-store--decode (car row)))
          (sqlite-select (org-workflow-store--db) "SELECT payload FROM days ORDER BY date")))

(defun org-workflow-store-put-day (date record)
  "Store settlement RECORD under DATE, replacing any existing snapshot."
  (sqlite-execute (org-workflow-store--db) "INSERT OR REPLACE INTO days VALUES(?,?)"
                  (list date (org-workflow-store--encode record))))

(provide 'org-workflow-store)
;;; org-workflow-store.el ends here
