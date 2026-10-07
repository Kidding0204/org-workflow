;;; org-workflow-web-export-test.el --- workflow history export tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'json)
(require 'org)
(require 'vulpea-journal)
(require 'org-workflow-core)
(require 'org-workflow-journal)
(require 'org-workflow-web-export nil t)

(defun org-workflow-web-export-test--file-bytes (file)
  "Return FILE's exact bytes as a unibyte string."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally file)
    (buffer-string)))

(defun org-workflow-web-export-test--records (buffer)
  "Return finalized public record plists found in BUFFER."
  (with-current-buffer buffer
    (org-with-wide-buffer
     (let (records)
       (org-map-entries
        (lambda ()
          (when-let* ((date (org-entry-get nil "WORKFLOW_RECORD")))
            (let ((record (copy-marker (point))))
              (unless (org-up-heading-safe)
                (error "Workflow record lacks a summary root"))
              (when-let* ((finalized-at
                          (org-entry-get nil "WORKFLOW_FINALIZED_AT")))
                (push (cons date
                            (list :date date
                                  :summary-marker (copy-marker (point))
                                  :record-marker record
                                  :finalized-at finalized-at))
                      records)))))
        nil 'file)
       records))))

(defun org-workflow-web-export-test--record-times (records)
  "Return Journal time values represented by RECORDS."
  (mapcar (lambda (entry)
            (org-time-string-to-time (concat "[" (car entry) "]")))
          records))

(defun org-workflow-web-export-test--payload (file)
  "Parse JSON FILE into a plist/list payload."
  (with-temp-buffer
    (insert-file-contents file)
    (json-parse-buffer :object-type 'plist
                       :array-type 'list
                       :null-object nil
                       :false-object :json-false)))

(defmacro org-workflow-web-export-test-with-journal (content &rest body)
  "Run BODY with finalized public records backed by temporary CONTENT."
  (declare (indent 1) (debug t))
  `(let* ((directory (make-temp-file "workflow-web-export-" t))
          (journal-file (expand-file-name "journal.org" directory))
          (org-workflow-web-export-file
           (expand-file-name "workflow-history.v1.json" directory))
          buffer records)
     (unwind-protect
         (progn
           (with-temp-file journal-file (insert ,content))
           (setq buffer (find-file-noselect journal-file))
           (with-current-buffer buffer (org-mode))
           (setq records
                 (org-workflow-web-export-test--records buffer))
           (cl-letf (((symbol-function
                       'org-workflow-journal-finalized-record)
                      (lambda (date) (cdr (assoc date records))))
                     ((symbol-function 'vulpea-journal-all-dates)
                      (lambda ()
                        (org-workflow-web-export-test--record-times
                         records))))
             ,@body))
       (when (buffer-live-p buffer)
         (with-current-buffer buffer (set-buffer-modified-p nil))
         (kill-buffer buffer))
       (delete-directory directory t))))

(defconst org-workflow-web-export-test--valid-journal
  (concat
   "* 2026-08-24\n"
   ":PROPERTIES:\n"
   ":COMMITMENT: met\n"
   ":COMMITMENT_FOCUS_MINUTES: 30\n"
   ":OPTIONAL_FOCUS_MINUTES: 15\n"
   ":FOCUS_TOTAL_MINUTES: 45\n"
   ":OPTIONAL_COMPLETED: 1\n"
   ":WORKFLOW_TRACKING_STARTED: [2026-08-24]\n"
   ":WORKFLOW_FINALIZED_AT: [2026-08-24 22:00]\n"
   ":END:\n"
   "** Workflow\n"
   ":PROPERTIES:\n:WORKFLOW_RECORD: 2026-08-24\n:END:\n"
   "*** Minimum Commitment Progress\n"
   ":PROPERTIES:\n:WORKFLOW_SECTION: minimum\n:END:\n"
   "| Task | Outcome | Focus |\n|------+---------+-------|\n"
   "| Promise | done | 30 |\n"
   "*** Optional Work\n"
   ":PROPERTIES:\n:WORKFLOW_SECTION: optional\n:END:\n"
   "| Task | Outcome | Focus |\n|------+---------+-------|\n"
   "| Bonus | ready | 15 |\n"
   "* 2026-08-26\n"
   ":PROPERTIES:\n"
   ":COMMITMENT: untouch\n"
   ":COMMITMENT_FOCUS_MINUTES: 20\n"
   ":OPTIONAL_FOCUS_MINUTES: 0\n"
   ":FOCUS_TOTAL_MINUTES: 20\n"
   ":OPTIONAL_COMPLETED: 0\n"
   ":WORKFLOW_TRACKING_STARTED: [2026-08-24]\n"
   ":WORKFLOW_FINALIZED_AT: [2026-08-26 22:00]\n"
   ":END:\n"
   "** Workflow\n"
   ":PROPERTIES:\n:WORKFLOW_RECORD: 2026-08-26\n:END:\n"
   "*** Minimum Commitment Progress\n"
   ":PROPERTIES:\n:WORKFLOW_SECTION: minimum\n:END:\n"
   "| Task | Outcome | Focus |\n|------+---------+-------|\n"
   "| Parent promise | focused | 20 |\n"
   "*** Optional Work\n"
   ":PROPERTIES:\n:WORKFLOW_SECTION: optional\n:END:\n"
   "| Task | Outcome | Focus |\n|------+---------+-------|\n"))

(ert-deftest org-workflow-web-export-emits-exact-finalized-and-missing-shapes ()
  "A missing exporter branch or accidental Journal write breaks this test."
  (org-workflow-web-export-test-with-journal
      org-workflow-web-export-test--valid-journal
    (let ((journal-bytes
           (org-workflow-web-export-test--file-bytes journal-file))
          (journal-text
           (with-current-buffer buffer
             (buffer-substring-no-properties (point-min) (point-max))))
          (journal-point (with-current-buffer buffer (point)))
          (journal-narrowed (with-current-buffer buffer (buffer-narrowed-p)))
          (journal-modified (with-current-buffer buffer (buffer-modified-p))))
      (should (equal org-workflow-web-export-file
                     (org-workflow-web-export-history
                      (encode-time 0 5 22 26 8 2026))))
      (let* ((payload
              (org-workflow-web-export-test--payload
               org-workflow-web-export-file))
             (days (plist-get payload :days)))
        (should (equal "org-workflow-history" (plist-get payload :schema)))
        (should (= 1 (plist-get payload :schemaVersion)))
        (should (string-match-p
                 "\\`2026-08-26T22:05:00[+-][0-9][0-9]:[0-9][0-9]\\'"
                 (plist-get payload :generatedAt)))
        (should (equal "Asia/Shanghai" (plist-get payload :timezone)))
        (should (equal '(:trackingStarted "2026-08-24"
                         :eligibleThrough "2026-08-26")
                       (plist-get payload :coverage)))
        (should
         (equal
          '((:date "2026-08-24" :recordState "finalized"
             :commitment "met"
             :commitmentFocusMinutes 30 :optionalFocusMinutes 15
             :focusTotalMinutes 45 :optionalCompleted 1
             :finalizedAt "2026-08-24T22:00:00+08:00"
             :minimumTasks
             ((:task "Promise" :outcome "done" :focusMinutes 30))
             :optionalTasks
             ((:task "Bonus" :outcome "ready" :focusMinutes 15)))
            (:date "2026-08-25" :recordState "missing")
            (:date "2026-08-26" :recordState "finalized"
             :commitment "untouch"
             :commitmentFocusMinutes 20 :optionalFocusMinutes 0
             :focusTotalMinutes 20 :optionalCompleted 0
             :finalizedAt "2026-08-26T22:00:00+08:00"
             :minimumTasks
             ((:task "Parent promise" :outcome "focused"
               :focusMinutes 20))
             :optionalTasks ()))
          days)))
      (should (equal journal-bytes
                     (org-workflow-web-export-test--file-bytes journal-file)))
      (with-current-buffer buffer
        (should (equal journal-text
                       (buffer-substring-no-properties
                        (point-min) (point-max))))
        (should (= journal-point (point)))
        (should (eq journal-narrowed (buffer-narrowed-p)))
        (should (eq journal-modified (buffer-modified-p)))))))

(ert-deftest org-workflow-web-export-decodes-multibyte-org-table-title ()
  "Returning raw table/link syntax or broken UTF-8 breaks this test."
  (let ((content
         (replace-regexp-in-string
          "| Promise | done | 30 |"
          "| [[id:task-id][中文 \\vert \\] 标题]] | done | 30 |"
          org-workflow-web-export-test--valid-journal t t)))
    (org-workflow-web-export-test-with-journal content
      (org-workflow-web-export-history
       (encode-time 0 5 22 26 8 2026))
      (let* ((payload
              (org-workflow-web-export-test--payload
               org-workflow-web-export-file))
             (task (car (plist-get (car (plist-get payload :days))
                                   :minimumTasks))))
        (should (equal "中文 | ] 标题" (plist-get task :task)))
        (should-not (plist-member task :id))
        (should-not (plist-member task :link))
        (should (multibyte-string-p
                 (decode-coding-string
                  (org-workflow-web-export-test--file-bytes
                   org-workflow-web-export-file)
                  'utf-8)))))))

(ert-deftest org-workflow-web-export-decodes-inline-markup-as-plain-title ()
  "Dropping markup values or their trailing spaces breaks display titles."
  (let ((content
         (replace-regexp-in-string
          "| Promise | done | 30 |"
          (concat
           "| [[id:code-only][=org-mode=]] | done | 10 |\n"
           "| [[id:mixed-code][Use =org-mode= now]] | done | 10 |\n"
           "| [[id:bold-title][*Bold* words]] | done | 10 |")
          org-workflow-web-export-test--valid-journal t t)))
    (org-workflow-web-export-test-with-journal content
      (org-workflow-web-export-history
       (encode-time 0 5 22 26 8 2026))
      (let* ((payload
              (org-workflow-web-export-test--payload
               org-workflow-web-export-file))
             (tasks (plist-get (car (plist-get payload :days))
                               :minimumTasks)))
        (should (equal '("org-mode" "Use org-mode now" "Bold words")
                       (mapcar (lambda (task) (plist-get task :task))
                               tasks)))))))

(ert-deftest org-workflow-web-export-uses-yesterday-before-seal-cutoff ()
  "Treating an unsealed current day as missing breaks this test."
  (org-workflow-web-export-test-with-journal
      org-workflow-web-export-test--valid-journal
    (org-workflow-web-export-history
     (encode-time 0 59 21 26 8 2026))
    (let* ((payload
            (org-workflow-web-export-test--payload
             org-workflow-web-export-file))
           (coverage (plist-get payload :coverage))
           (days (plist-get payload :days)))
      (should (equal "2026-08-25" (plist-get coverage :eligibleThrough)))
      (should (equal '("2026-08-24" "2026-08-25")
                     (mapcar (lambda (day) (plist-get day :date)) days))))))

(ert-deftest org-workflow-web-export-rejects-backward-coverage-and-preserves-output ()
  "Writing a snapshot before its tracking anchor makes stale history misleading."
  (org-workflow-web-export-test-with-journal
      org-workflow-web-export-test--valid-journal
    (with-temp-file org-workflow-web-export-file (insert "sentinel\n"))
    (let ((before
           (org-workflow-web-export-test--file-bytes
            org-workflow-web-export-file)))
      (let ((error-data
             (should-error
              (org-workflow-web-export-history
               (encode-time 0 59 21 24 8 2026))
              :type 'error)))
        (should (string-match-p
                 "tracking started 2026-08-24 is after eligible through 2026-08-23"
                 (error-message-string error-data))))
      (should (equal before
                     (org-workflow-web-export-test--file-bytes
                      org-workflow-web-export-file))))))

(ert-deftest org-workflow-web-export-invalid-properties-preserve-output ()
  "Lenient numeric or commitment validation breaks this test."
  (dolist (replacement '("-1" "1.5" "2x"))
    (let ((content
           (replace-regexp-in-string
            ":FOCUS_TOTAL_MINUTES: 45"
            (concat ":FOCUS_TOTAL_MINUTES: " replacement)
            org-workflow-web-export-test--valid-journal t t)))
      (org-workflow-web-export-test-with-journal content
        (with-temp-file org-workflow-web-export-file (insert "sentinel\n"))
        (let ((before
               (org-workflow-web-export-test--file-bytes
                org-workflow-web-export-file)))
          (should-error
           (org-workflow-web-export-history
            (encode-time 0 5 22 26 8 2026)))
          (should (equal before
                         (org-workflow-web-export-test--file-bytes
                          org-workflow-web-export-file)))))))
  (dolist (replacement '("unknown" "MET"))
    (let ((content
           (replace-regexp-in-string
            ":COMMITMENT: met"
            (concat ":COMMITMENT: " replacement)
            org-workflow-web-export-test--valid-journal t t)))
      (org-workflow-web-export-test-with-journal content
        (with-temp-file org-workflow-web-export-file (insert "sentinel\n"))
        (let ((before
               (org-workflow-web-export-test--file-bytes
                org-workflow-web-export-file)))
          (should-error
           (org-workflow-web-export-history
            (encode-time 0 5 22 26 8 2026)))
          (should (equal before
                         (org-workflow-web-export-test--file-bytes
                          org-workflow-web-export-file))))))))

(ert-deftest org-workflow-web-export-inconsistent-focus-total-preserves-output ()
  "Writing a snapshot with inconsistent Focus totals breaks this test."
  (let ((content
         (replace-regexp-in-string
          ":FOCUS_TOTAL_MINUTES: 45"
          ":FOCUS_TOTAL_MINUTES: 46"
          org-workflow-web-export-test--valid-journal t t)))
    (org-workflow-web-export-test-with-journal content
      (with-temp-file org-workflow-web-export-file (insert "sentinel\n"))
      (let ((before
             (org-workflow-web-export-test--file-bytes
              org-workflow-web-export-file)))
        (should-error
         (org-workflow-web-export-history
          (encode-time 0 5 22 26 8 2026)))
        (should (equal before
                       (org-workflow-web-export-test--file-bytes
                        org-workflow-web-export-file)))))))

(ert-deftest org-workflow-web-export-invalid-table-preserves-output ()
  "Accepting malformed generated tables or outcomes breaks this test."
  (dolist (content
           (list
            (replace-regexp-in-string
             "| Promise | done | 30 |" "not a table"
             org-workflow-web-export-test--valid-journal t t)
            (replace-regexp-in-string
             "| Promise | done | 30 |" "| Promise | strange | 30 |"
             org-workflow-web-export-test--valid-journal t t)))
    (org-workflow-web-export-test-with-journal content
      (with-temp-file org-workflow-web-export-file (insert "sentinel\n"))
      (let ((before
             (org-workflow-web-export-test--file-bytes
              org-workflow-web-export-file)))
        (should-error
         (org-workflow-web-export-history
          (encode-time 0 5 22 26 8 2026)))
        (should (equal before
                       (org-workflow-web-export-test--file-bytes
                        org-workflow-web-export-file)))))))

(ert-deftest org-workflow-web-export-write-error-preserves-output ()
  "Replacing the snapshot before a successful write breaks this test."
  (org-workflow-web-export-test-with-journal
      org-workflow-web-export-test--valid-journal
    (with-temp-file org-workflow-web-export-file (insert "sentinel\n"))
    (let ((before
           (org-workflow-web-export-test--file-bytes
            org-workflow-web-export-file)))
      (cl-letf (((symbol-function 'write-region)
                 (lambda (&rest _arguments) (error "write failed"))))
        (should-error
         (org-workflow-web-export-history
          (encode-time 0 5 22 26 8 2026))))
      (should (equal before
                     (org-workflow-web-export-test--file-bytes
                      org-workflow-web-export-file))))))

(ert-deftest org-workflow-web-export-wrapper-ignores-hook-date ()
  "Passing the ISO hook date as NOW breaks this test."
  (let (arguments)
    (cl-letf (((symbol-function 'org-workflow-web-export-history)
               (lambda (&optional now) (push now arguments))))
      (org-workflow-web-export-after-finalize "2026-08-24"))
    (should (equal '(nil) arguments))))

(ert-deftest org-workflow-web-export-error-cannot-undo-journal-finalize ()
  "Coupling exporter failure to Journal persistence breaks this test."
  (let* ((directory (make-temp-file "workflow-web-hook-" t))
         (journal-file (expand-file-name "journal.org" directory))
         (org-workflow-web-export-file
          (expand-file-name "missing/output.json" directory))
         (buffer nil)
         (note nil)
         (org-workflow-journal--tracking-anchor nil)
         (org-workflow-journal-finalized-hook
          '(org-workflow-web-export-after-finalize)))
    (unwind-protect
        (progn
          (with-temp-file journal-file (insert "#+title: Journal\n"))
          (setq buffer (find-file-noselect journal-file))
          (with-current-buffer buffer (org-mode))
          (setq note
                (make-vulpea-note
                 :id "journal-note" :path journal-file :level 0
                 :pos (point-min) :title "Journal" :tags '("journal")))
          (cl-letf (((symbol-function 'vulpea-journal-note)
                     (lambda (_date) note))
                    ((symbol-function 'vulpea-journal-find-note)
                     (lambda (_date) note))
                    ((symbol-function 'vulpea-journal-all-dates)
                     (lambda () nil))
                    ((symbol-function 'org-workflow-journal-rows)
                     (lambda (_date) nil))
                    ((symbol-function 'org-workflow-web-export-history)
                     (lambda (&optional _now) (error "export failed"))))
            (should (eq 'untouch
                        (org-workflow-journal-finalize "2026-08-24"))))
          (with-current-buffer buffer
            (goto-char (point-min))
            (should (equal "[2026-08-24 22:00]"
                           (org-entry-get nil "WORKFLOW_FINALIZED_AT"))))
          (should (string-match-p
                   (regexp-quote
                    ":WORKFLOW_FINALIZED_AT: [2026-08-24 22:00]")
                   (org-workflow-web-export-test--file-bytes journal-file))))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer (set-buffer-modified-p nil))
        (kill-buffer buffer))
      (delete-directory directory t))))

(ert-deftest org-workflow-web-export-without-anchor-emits-empty-history ()
  "Inventing coverage before a durable tracking anchor breaks this test."
  (let* ((directory (make-temp-file "workflow-web-empty-" t))
         (org-workflow-web-export-file
          (expand-file-name "workflow-history.v1.json" directory)))
    (unwind-protect
        (cl-letf (((symbol-function 'vulpea-journal-all-dates)
                   (lambda () nil))
                  ((symbol-function 'org-workflow-journal-finalized-record)
                   (lambda (_date) (error "reader must not be called"))))
          (org-workflow-web-export-history
           (encode-time 0 5 22 26 8 2026))
          (let ((bytes
                 (org-workflow-web-export-test--file-bytes
                  org-workflow-web-export-file))
                (payload
                 (org-workflow-web-export-test--payload
                  org-workflow-web-export-file)))
            (should (string-match-p
                     (regexp-quote "\"coverage\":null") bytes))
            (should-not (plist-get payload :coverage))
            (should (equal nil (plist-get payload :days)))))
      (delete-directory directory t))))

(ert-deftest org-workflow-web-export-setup-registers-wrapper-and-catches-error ()
  "Registering the command directly or leaking startup errors breaks this test."
  (let ((org-workflow-journal-finalized-hook nil)
        messages)
    (cl-letf (((symbol-function 'org-workflow-web-export-history)
               (lambda (&optional _now) (error "export failed")))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push (apply #'format format-string arguments) messages))))
      (should-not (org-workflow-web-export-setup)))
    (should (memq #'org-workflow-web-export-after-finalize
                  org-workflow-journal-finalized-hook))
    (should (equal '("Org Workflow web export failed: export failed")
                   messages))))

(ert-deftest org-workflow-web-open-exports-before-configured-launcher ()
  "The portable opener exports before delegating to its optional launcher."
  (let* ((calls nil)
         (org-workflow-web-open-function (lambda () (push 'launch calls))))
    (cl-letf (((symbol-function 'org-workflow-web-export-history)
               (lambda (&optional _) (push 'export calls))))
      (org-workflow-web-open))
    (should (equal '(export launch) (nreverse calls)))))

(ert-deftest org-workflow-web-open-requires-an-explicit-launcher ()
  (let ((org-workflow-web-open-function nil))
    (should-error (org-workflow-web-open) :type 'user-error)))

(ert-deftest org-workflow-web-open-has-a-free-workflow-key ()
  "The dashboard opener should use uppercase H without replacing lowercase h."
  (should (eq #'org-workflow-web-open
              (key-binding (kbd "C-c o H")))))

(provide 'org-workflow-web-export-test)
;;; org-workflow-web-export-test.el ends here
