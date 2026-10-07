;;; org-workflow-history.el --- org-workflow-history Workflow component -*- lexical-binding: t; -*-
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
;;; org-workflow-history.el --- Daily facts without journal documents -*- lexical-binding: t; -*-
(require 'org-workflow-store)

(require 'org-workflow-habits)

(require 'org-workflow-journal)

; read-only legacy migration and CLOCK reader
(require 'org-workflow-web-export)

; legacy schema-v1 validator

(defun org-workflow-history-add-days (date days)
  "Return the calendar date DAYS days after DATE."
  (org-workflow-journal--date-add-days date days))

(defun org-workflow-history-attempt-enabled-p (date)
  "Whether DATE uses recorded investment rather than only final completion."
  (when-let* ((since (and org-workflow-store-enabled
                         (org-workflow-store-meta "attempt-progress-since"))))
    (not (string< date since))))

(defun org-workflow-history-attempted-p (date &optional marker)
  "Whether MARKER has a positive, closed direct CLOCK record on DATE.
Running clocks and descendants' records cannot satisfy a daily attempt."
  (and (org-workflow-history-attempt-enabled-p date)
       (let ((org-clock-report-include-clocking-task nil))
         (> (org-workflow-journal-direct-clock-minutes
             (or marker (point-marker)) (concat "[" date " 00:00]")
             (concat "[" (org-workflow-history-add-days date 1) " 00:00]")) 0))))

(defun org-workflow-history--commitment-satisfied-p (row date &optional tasks)
  "Read ROW's fulfillment on DATE without changing task lifecycle.
Use supplied TASKS when non-nil, otherwise read that day's direct clocks."
  (or (member (org-workflow-history--row-state row date) '("done" "adjusted-done"))
      (and (org-workflow-history-attempt-enabled-p date)
           (seq-some (lambda (task)
                       (and (equal (plist-get task :id) (nth 1 row))
                            (> (plist-get task :focusMinutes) 0)))
                     (or tasks (org-workflow-history--tasks date))))))

(defun org-workflow-history-progress (date)
  "Compute responsibility on DATE, including unresolved earlier commitments."
  (let* ((rows (org-workflow-history--responsibilities date))
         (tasks (org-workflow-history--tasks date))
         (done (seq-count (lambda (row) (org-workflow-history--commitment-satisfied-p row date tasks)) rows))
         (total (length rows)))
    (list :minimumSatisfied done :minimumTotal total
          :phase (if (and (> total 0) (= done total)) "optional" "minimum")
          :commitmentComplete (if (and (> total 0) (= done total)) t :false))))

(defun org-workflow-history--row-state (row date)
  "Read ROW's outcome at DATE's exclusive end from its event history."
  (let ((end (org-workflow-history-add-days date 1)) (state "pending"))
    (dolist (event (sqlite-select (org-workflow-store--db)
                                  "SELECT at,kind FROM events WHERE id=? ORDER BY seq" (list (car row))))
      (when (and (string< (substring (car event) 0 10) end)
                 (member (cadr event) '("pending" "done" "adjusted-done" "held" "deferred" "withdrawn" "cancelled")))
        (setq state (cadr event))))
    state))

(defun org-workflow-history--responsibilities (date)
  "Return commitments due on DATE or carried forward without fulfillment.
Keep original due dates intact.  Leave records do not discharge commitments."
  (let ((previous (org-workflow-history-add-days date -1))
        (tasks-by-date (make-hash-table :test #'equal)))
    (seq-filter
     (lambda (row)
       (or (and (equal (nth 3 row) date)
                (not (equal (org-workflow-history--row-state row date) "cancelled")))
           (and
            (string< (nth 3 row) date)
            (not (member (org-workflow-history--row-state row previous)
                         '("done" "adjusted-done" "withdrawn" "cancelled")))
            (let ((day (nth 3 row)) fulfilled)
              ;; Read each day's direct clocks once for the whole commitment set.
              (while (and (string< day date) (not fulfilled))
                (when (org-workflow-history-attempt-enabled-p day)
                  (let ((tasks (gethash day tasks-by-date 'missing)))
                    (when (eq tasks 'missing)
                      (setq tasks (org-workflow-history--tasks day))
                      (puthash day tasks tasks-by-date))
                    (setq fulfilled
                          (seq-some (lambda (task)
                                      (and (equal (plist-get task :id) (nth 1 row))
                                           (> (plist-get task :focusMinutes) 0)))
                                    tasks))))
                (setq day (org-workflow-history-add-days day 1)))
              (not fulfilled)))))
     (sqlite-select
      (org-workflow-store--db)
      "SELECT id,task_id,created_at,due,original_title,title,status,adjusted FROM commitments WHERE due<=? ORDER BY due,rowid"
      (list date)))))

(defun org-workflow-history--tasks (date)
  "Read direct clocks and completed tasks on DATE, including refined containers."
  (let ((org-clock-report-include-clocking-task nil)
        (start (concat "[" date " 00:00]"))
        (end (concat "[" (org-workflow-history-add-days date 1) " 00:00]")) rows)
    (dolist (file (org-agenda-files t))
      (when (file-readable-p file)
        (with-current-buffer (find-file-noselect file)
          (org-with-wide-buffer
           (when (org-workflow--file-kind)
             (org-map-entries
              (lambda ()
                (let ((minutes (org-workflow-journal-direct-clock-minutes (point-marker) start end))
                      (done (and (equal (org-get-todo-state) "DONE")
                                 (equal date (org-workflow-target--timestamp-date (org-entry-get nil "CLOSED"))))))
                  (when (and (not (org-workflow-habit-p)) (or done (> minutes 0)))
                    (push (list :id (org-entry-get nil "ID") :task (org-get-heading t t t t)
                                :outcome (if done "done" "focused") :focusMinutes minutes) rows))))
              nil 'file))))))
    rows))

(defun org-workflow-history--habit-records (date)
  "Read habit facts for DATE, rejecting a missing established source."
  (when (and (org-workflow-store-meta "habit-source")
             (not (file-readable-p (org-workflow-habits-file))))
    (error "Habit source is missing or unreadable: %s" (org-workflow-habits-file)))
  (org-workflow-habits-records date))

(defun org-workflow-history--compute (date)
  "Compute DATE's settlement from commitments, direct clocks and habit facts."
  (let* ((commitments (org-workflow-history--responsibilities date))
         (tasks (org-workflow-history--tasks date)) (committed-minutes 0) (optional-minutes 0)
         (habits (org-workflow-history--habit-records date))
         (habit-minutes (apply #'+ (mapcar (lambda (row) (plist-get row :focusMinutes)) habits)))
         (fulfilled 0) minimum optional)
    (dolist (row commitments)
      (let* ((task (seq-find (lambda (item) (equal (plist-get item :id) (nth 1 row))) tasks))
             (minutes (or (plist-get task :focusMinutes) 0))
             (state (org-workflow-history--row-state row date))
             (satisfied (org-workflow-history--commitment-satisfied-p row date tasks)))
        (cl-incf committed-minutes minutes)
        (when satisfied (cl-incf fulfilled))
        (push (list :task (nth 5 row) :outcome
                    (cond ((member state '("done" "adjusted-done")) "done")
                          ((equal state "held") "held") (t "pending"))
                    :focusMinutes minutes :satisfied (if satisfied t :false)) minimum)))
    (dolist (task tasks)
      (unless (seq-some (lambda (row) (equal (nth 1 row) (plist-get task :id))) commitments)
        (cl-incf optional-minutes (plist-get task :focusMinutes))
        (push (list :task (plist-get task :task) :outcome (plist-get task :outcome)
                    :focusMinutes (plist-get task :focusMinutes)) optional)))
    (org-workflow-history--with-leaves
     (list :date date :recordState "finalized"
          :commitment (cond ((null commitments) "untouch") ((= fulfilled (length commitments)) "met") (t "unmet"))
          :commitmentFocusMinutes committed-minutes :optionalFocusMinutes optional-minutes
          :habitFocusMinutes habit-minutes
          :habitCompleted (seq-count (lambda (row) (equal (plist-get row :outcome) "done")) habits)
          :habitTasks (vconcat (mapcar (lambda (row) (list :task (plist-get row :task)
                                                         :outcome (plist-get row :outcome)
                                                         :focusMinutes (plist-get row :focusMinutes))) habits))
          :focusTotalMinutes (+ committed-minutes optional-minutes habit-minutes)
          :optionalCompleted (seq-count (lambda (row) (equal (plist-get row :outcome) "done")) optional)
          :finalizedAt (format-time-string "%Y-%m-%dT%H:%M:%S%:z")
          :minimumTasks (vconcat (nreverse minimum)) :optionalTasks (vconcat (nreverse optional))))))

(defun org-workflow-history--with-leaves (record)
  "Attach leave explanations to RECORD without synthesizing work or settlement."
  (let ((leaves (org-workflow-store-leaves (plist-get record :date))))
    (if (> (length leaves) 0)
        (plist-put (copy-sequence record) :leaveRecords leaves)
      record)))

(defun org-workflow-history--export-leaves (original &rest args)
  "Call ORIGINAL with ARGS and attach leave explanations to exported days."
  (let ((days (apply original args)))
    (if org-workflow-store-enabled
        (vconcat (mapcar #'org-workflow-history--with-leaves days))
      days)))

(defun org-workflow-history-finalize (date &optional recompute)
  "Seal past calendar DATE, or return its existing settlement.
RECOMPUTE changes statistics without changing commitments."
  (unless (string< date (org-workflow-target--today-string))
    (user-error "只能结算已经结束的日期"))
  (when (and recompute (org-workflow-store-day date)
             (null (org-workflow-history--responsibilities date))
             (> (length (plist-get (org-workflow-store-day date) :minimumTasks)) 0))
    (user-error "旧结算缺少可验证的承诺关联，保留原快照，不能安全重算"))
  (or (and (not recompute) (org-workflow-store-day date))
      (let ((record (org-workflow-history--compute date)) (db (org-workflow-store--db)))
        (sqlite-execute db "BEGIN IMMEDIATE")
        (condition-case err
            (progn (org-workflow-store-put-day date record) (sqlite-execute db "COMMIT"))
          (error (sqlite-execute db "ROLLBACK") (signal (car err) (cdr err))))
        (run-hook-with-args 'org-workflow-journal-finalized-hook date)
        record)))

(defun org-workflow-history-recompute (date)
  "Explicitly recalculate DATE's historical clocks without recreating promises."
  (interactive (list (org-read-date nil nil nil "重算日期")))
  (org-workflow-history-finalize date t))

(defun org-workflow-history-catch-up (&rest _)
  "Seal all past days from the tracking anchor through yesterday."
  (let ((date (or (org-workflow-store-meta "anchor") (org-workflow-target--today-string)))
        (today (org-workflow-target--today-string)))
    (while (string< date today)
      (org-workflow-history-finalize date)
      (setq date (org-workflow-history-add-days date 1)))))

(defun org-workflow-history-streak (date daily)
  "Return the fulfilled-day streak ending at DATE, using current DAILY progress."
  (let ((count 0) (anchor (org-workflow-store-meta "anchor")))
    (when (eq (plist-get daily :commitmentComplete) t) (setq count 1))
    (setq date (org-workflow-history-add-days date -1))
    (while (and anchor (not (string< date anchor))
                (equal (plist-get (org-workflow-store-day date) :commitment) "met"))
      (cl-incf count) (setq date (org-workflow-history-add-days date -1)))
    count))

(defun org-workflow-history--export-candidates (original &rest args)
  "Return stored day candidates, or call legacy ORIGINAL with ARGS."
  (if org-workflow-store-enabled
      (mapcar (lambda (day) (cons (plist-get day :date) day)) (org-workflow-store-days))
    (apply original args)))

(defun org-workflow-history--export-day (original date record)
  "Return stored RECORD, or call legacy ORIGINAL with DATE and RECORD."
  (if org-workflow-store-enabled record (funcall original date record)))

(defun org-workflow-history--export-anchor (original records)
  "Return the stored anchor, or call legacy ORIGINAL with RECORDS."
  (if org-workflow-store-enabled (org-workflow-store-meta "anchor") (funcall original records)))

(defun org-workflow-history--export-cutoff (original now)
  "Return yesterday at NOW, or call legacy ORIGINAL with NOW."
  (if org-workflow-store-enabled
      (org-workflow-history-add-days (format-time-string "%F" now) -1)
    (funcall original now)))

(defun org-workflow-history--record (original date)
  "Read stored facts for DATE, or delegate to legacy ORIGINAL."
  (if org-workflow-store-enabled (org-workflow-store-day date) (funcall original date)))

(defvar org-workflow-history-timer nil)

(defvar org-workflow-history--refresh-timer nil)

(defun org-workflow-history--refresh-after-clock ()
  "Refresh desktop facts and Sprint after a closed CLOCK has been retained."
  (when org-workflow-store-enabled
    (when (fboundp 'org-workflow-panel-invalidate) (org-workflow-panel-invalidate))
    (org-workflow--request-gnome-refresh)
    (when (timerp org-workflow-history--refresh-timer)
      (cancel-timer org-workflow-history--refresh-timer))
    ;; Wait until native clock-out and its caller have finished changing buffers.
    (setq org-workflow-history--refresh-timer
          (run-at-time
           0.1 nil
           (lambda ()
             (setq org-workflow-history--refresh-timer nil)
             (save-window-excursion
               (dolist (buffer (buffer-list))
                 (with-current-buffer buffer
                   (when (and (derived-mode-p 'org-agenda-mode)
                              (bound-and-true-p org-workflow-agenda--sprint-buffer-p))
                     (condition-case err (org-agenda-redo)
                       (error (message "专注记录已保留；Sprint 刷新失败：%s"
                                       (error-message-string err)))))))))))))

(defun org-workflow-history--schedule-midnight ()
  "Schedule the next midnight catch-up, replacing any existing timer."
  (when (timerp org-workflow-history-timer) (cancel-timer org-workflow-history-timer))
  (let* ((tomorrow (org-workflow-history-add-days (org-workflow-target--today-string) 1))
         (time (org-time-string-to-time (concat tomorrow " 00:00"))))
    (setq org-workflow-history-timer
          (run-at-time time nil
                       (lambda ()
                         (unwind-protect (org-workflow-history-catch-up)
                           (org-workflow-history--schedule-midnight)))))))

(defun org-workflow-history-sync-habits ()
  "Rebuild habit facts after source saves.  Org remains authoritative.
Sources are saved first: a database failure is reported and the next sync can
replay them.  Past finalized totals require explicit recomputation."
  (interactive)
  (when org-workflow-store-enabled
    ;; Also supports hot activation with an already-open pre-habit connection.
    (sqlite-execute (org-workflow-store--db)
                    "CREATE TABLE IF NOT EXISTS habit_days(date TEXT PRIMARY KEY,payload TEXT NOT NULL)")
    (let* ((previous (org-workflow-store-habit-days))
           (dates (delete-dups (append (mapcar #'car previous)
                                      (org-workflow-habits-dates))))
           (records (mapcar (lambda (date) (cons date (org-workflow-history--habit-records date))) dates))
           (db (org-workflow-store--db)))
      (sqlite-execute db "BEGIN IMMEDIATE")
      (condition-case err
          (progn
            (dolist (record records)
              (sqlite-execute db "INSERT OR REPLACE INTO habit_days VALUES(?,?)"
                              (list (car record) (org-workflow-store--encode (cdr record)))))
            (when (file-exists-p (org-workflow-habits-file))
              (org-workflow-store-set-meta "habit-source" (org-workflow-habits-file)))
            (sqlite-execute db "COMMIT"))
        (error (sqlite-execute db "ROLLBACK") (signal (car err) (cdr err)))))))

(defun org-workflow-history-setup ()
  "Install history adapters, synchronize habits and schedule daily settlement.
A dated boundary keeps older settlements on their original progress rules."
  ;; A dated boundary keeps old settlements and old missing days on their rules.
  (unless (org-workflow-store-meta "attempt-progress-since")
    (org-workflow-store-set-meta "attempt-progress-since" (org-workflow-target--today-string)))
  (org-workflow--add-hook 'org-clock-out-hook #'org-workflow-history--refresh-after-clock)
  (remove-hook 'org-workflow-journal-finalized-hook #'org-workflow-web-export-after-finalize)
  (org-workflow--add-hook 'org-workflow-habits-saved-hook #'org-workflow-history-sync-habits)
  (org-workflow-history-sync-habits)
  (when (timerp org-workflow-journal-seal-timer) (cancel-timer org-workflow-journal-seal-timer))
  (setq org-workflow-status-provider-function #'org-workflow-history-progress
        org-workflow-commitment-streak-provider-function #'org-workflow-history-streak)
  (org-workflow--advice-add 'org-workflow-web-export--candidate-records :around #'org-workflow-history--export-candidates)
  (org-workflow--advice-add 'org-workflow-web-export--finalized-day :around #'org-workflow-history--export-day)
  (org-workflow--advice-add 'org-workflow-web-export--tracking-started :around #'org-workflow-history--export-anchor)
  (org-workflow--advice-add 'org-workflow-web-export--eligible-through :around #'org-workflow-history--export-cutoff)
  (org-workflow--advice-add 'org-workflow-web-export--days :around #'org-workflow-history--export-leaves)
  (org-workflow--advice-add 'org-workflow-journal-finalized-record :around #'org-workflow-history--record)
  (org-workflow-history--schedule-midnight)
  (org-workflow-history-catch-up))

(defun org-workflow-history--check-stored-days (db)
  "Validate persisted day rows in DB before missing days can be synthesized.
Decode failures report only a calendar-date location and a fixed reason."
  (dolist (row (sqlite-select db "SELECT date,payload FROM days ORDER BY date"))
    (let* ((date (car row))
           (valid-date (and (stringp date)
                            (string-match-p "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\'" date)
                            (condition-case nil
                                (equal date (org-workflow-web-export--date-add-days date 0))
                              (error nil))))
           (path (if valid-date (format "days[%s]" (substring-no-properties date)) "days[invalid date]"))
           (record (condition-case nil (org-workflow-store--decode (cadr row))
                     (error (error "Workflow history invalid: %s.payload cannot be decoded" path)))))
      (unless (and valid-date record (proper-list-p record) (cl-evenp (length record))
                   (cl-loop for (key _value) on record by #'cddr always (keywordp key))
                   (= (/ (length record) 2)
                      (length (delete-dups (cl-loop for (key _value) on record by #'cddr collect key)))))
        (error "Workflow history invalid: %s.payload must be a day record" path))
      (unless (equal date (plist-get record :date))
        (error "Workflow history invalid: %s.date must match stored date" path))
      (unless (equal "finalized" (plist-get record :recordState))
        (error "Workflow history invalid: %s.recordState must be finalized" path)))))

(defun org-workflow-history-read (&optional now)
  "Read the selected initialized history backend into a schema-v1 payload.
NOW defaults to the current time.  Never initialize or repair storage,
install advice, settle days, or write an export while browsing."
  (let ((org-workflow-store--read-only t))
    (when org-workflow-store-enabled
      (let* ((db (org-workflow-store--db))
             (days (sqlite-select db "SELECT 1 FROM days LIMIT 1"))
             (leaves (sqlite-select db "SELECT 1 FROM leave_records LIMIT 1")))
        ;; No anchor means empty to the builder.  Never hide persisted facts.
        (when (and (not (org-workflow-store-meta "anchor")) (or days leaves))
          (error "Workflow history inconsistent: persisted history has no anchor"))
        (org-workflow-history--check-stored-days db))
      (dolist (pair '((org-workflow-web-export--candidate-records . org-workflow-history--export-candidates)
                      (org-workflow-web-export--finalized-day . org-workflow-history--export-day)
                      (org-workflow-web-export--tracking-started . org-workflow-history--export-anchor)
                      (org-workflow-web-export--eligible-through . org-workflow-history--export-cutoff)
                      (org-workflow-web-export--days . org-workflow-history--export-leaves)
                      (org-workflow-journal-finalized-record . org-workflow-history--record)))
        (unless (advice-member-p (cdr pair) (car pair))
          (error "Workflow history backend not ready: missing history advice"))))
    ;; Legacy Org parsing must not schedule the global element-cache timer.
    ;; Disabling caching changes no record interpretation or builder output.
    (let ((org-element-use-cache nil))
      (org-workflow-web-export--payload (or now (current-time))))))

(provide 'org-workflow-history)
;;; org-workflow-history.el ends here
