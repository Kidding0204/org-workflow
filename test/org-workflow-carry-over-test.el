;;; org-workflow-carry-over-test.el --- Natural rollover promises -*- lexical-binding: t; -*-
(require 'ert)
(load "org-workflow-store-test" nil t)

(defmacro workflow-carry-test (&rest body)
  (declare (indent 0))
  `(org-workflow-store-test
     (let ((org-id-locations nil) (org-id-files nil)
           (org-id-locations-file (expand-file-name "ids" directory)))
       (cl-letf (((symbol-function 'org-workflow-store--now)
                  (lambda () (concat (org-workflow-target--today-string)
                                     "T10:00:00+08:00"))))
         ,@body))))

(defun workflow-carry-test--defer ()
  "Use the real Sprint d command on the fixture's only task."
  (let ((org-agenda-buffer-name (generate-new-buffer-name "*Carry test*"))
        (org-agenda-window-setup 'current-window)
        (source (current-buffer)))
    (save-window-excursion
      (unwind-protect
          (progn
            (org-agenda nil "d")
            (goto-char (point-min)) (search-forward "Task")
            (org-workflow-agenda-schedule-tomorrow))
        (when-let* ((buffer (get-buffer org-agenda-buffer-name)))
          (kill-buffer buffer))))
    (set-buffer source)))

(ert-deftest workflow-carry-natural-midnight-creates-once-without-rewriting-yesterday ()
  (workflow-carry-test
    (org-workflow-store-set-meta "anchor" "2026-09-16")
    (org-schedule nil "2026-09-16")
    (should-not (org-entry-get nil "WORKFLOW_COMMITMENT_ID"))
    (cl-letf (((symbol-function 'org-workflow-target--today-string)
               (lambda () "2026-09-17")))
      (org-workflow-history-catch-up)
      (let ((id (org-entry-get nil "WORKFLOW_COMMITMENT_ID"))
            (yesterday (org-workflow-store-day "2026-09-16")))
        (should id)
        (should (equal "2026-09-17" (nth 3 (org-workflow-store-commitment id))))
        (should (equal "2026-09-16" (org-workflow-target--timestamp-date
                                    (org-entry-get nil "SCHEDULED"))))
        (should-not (org-workflow-store-due "2026-09-16"))
        (org-workflow-history-catch-up)
        (should (equal id (org-entry-get nil "WORKFLOW_COMMITMENT_ID")))
        (should (= 1 (length (org-workflow-store-due "2026-09-17"))))
        (should (equal yesterday (org-workflow-store-day "2026-09-16")))))))

(ert-deftest workflow-carry-excludes-ineligible-entries-and-keeps-existing-promise ()
  (workflow-carry-test
    (org-schedule nil "2026-09-15")
    (let ((id (org-workflow-store-create "2026-09-16")))
      (save-excursion
        (goto-char (point-max))
        (insert "\n** TODO Today\nSCHEDULED: <2026-09-16 Wed>\n"
                "** TODO Future\nSCHEDULED: <2026-09-18 Fri>\n"
                "** TODO Unscheduled\n"
                "** DONE Finished\nSCHEDULED: <2026-09-15 Tue>\n"
                "** HOLD Held\nSCHEDULED: <2026-09-15 Tue>\n"
                "** TODO Habit\nSCHEDULED: <2026-09-15 Tue +1d>\n:PROPERTIES:\n:STYLE: habit\n:END:\n"
                "** TODO Parent\nSCHEDULED: <2026-09-15 Tue>\n*** TODO Child\n"))
      (org-set-regexps-and-options)
      (org-workflow-history-carry-over)
      (should (equal id (org-entry-get nil "WORKFLOW_COMMITMENT_ID")))
      (should (= 1 (caar (sqlite-select (org-workflow-store--db)
                                      "SELECT count(*) FROM commitments")))))))

(ert-deftest workflow-carry-explicit-withdrawal-is-not-recreated ()
  (workflow-carry-test
    (org-schedule nil "2026-09-15")
    (org-workflow-history-carry-over)
    (should (org-entry-get nil "WORKFLOW_COMMITMENT_ID"))
    (org-workflow-toggle-commitment)
    (should-not (org-entry-get nil "WORKFLOW_COMMITMENT_ID"))
    (org-workflow-history-carry-over)
    (should-not (org-entry-get nil "WORKFLOW_COMMITMENT_ID"))
    (should (= 1 (caar (sqlite-select (org-workflow-store--db)
                                    "SELECT count(*) FROM commitments"))))))

(ert-deftest workflow-carry-rolls-back-source-and-facts-on-failure ()
  (workflow-carry-test
    (org-schedule nil "2026-09-15")
    (let ((before (buffer-string)) (event (symbol-function 'org-workflow-store--event)))
      (cl-letf (((symbol-function 'org-workflow-store--event)
                 (lambda (id kind &optional payload)
                   (if (equal kind "carried") (error "Injected carry failure")
                     (funcall event id kind payload)))))
        (should (equal "Injected carry failure"
                       (cadr (should-error (org-workflow-history-carry-over))))))
      (should (equal before (buffer-string)))
      (should-not (org-workflow-store-due "2026-09-16")))))

(ert-deftest workflow-carry-manual-d-defers-without-draft-until-naturally-overdue ()
  (workflow-carry-test
    (org-schedule nil "2026-09-16")
    (workflow-carry-test--defer)
    (should (equal "2026-09-17" (org-workflow-target--timestamp-date
                                (org-entry-get nil "SCHEDULED"))))
    (should-not (org-entry-get nil "WORKFLOW_COMMITMENT_ID"))
    (should-not (org-workflow-store-due "2026-09-17"))
    (cl-letf (((symbol-function 'org-workflow-target--today-string)
               (lambda () "2026-09-17")))
      (org-workflow-history-carry-over)
      (should-not (org-entry-get nil "WORKFLOW_COMMITMENT_ID")))
    (cl-letf (((symbol-function 'org-workflow-target--today-string)
               (lambda () "2026-09-18")))
      (org-workflow-history-carry-over)
      (should (org-entry-get nil "WORKFLOW_COMMITMENT_ID"))
      (should (= 1 (length (org-workflow-store-due "2026-09-18")))))))

(ert-deftest workflow-carry-manual-d-keeps-existing-responsibility ()
  (workflow-carry-test
    (org-schedule nil "2026-09-16")
    (let ((id (org-workflow-store-create "2026-09-16")))
      (workflow-carry-test--defer)
      (should (equal id (org-entry-get nil "WORKFLOW_COMMITMENT_ID")))
      (should (equal "deferred" (nth 6 (org-workflow-store-commitment id))))
    (should-not (org-workflow-store-due "2026-09-17")))))

(ert-deftest workflow-carry-defers-read-only-sources-and-preserves-unsaved-edits ()
  (workflow-carry-test
    (org-schedule nil "2026-09-15")
    (save-excursion (goto-char (point-max)) (insert "An unsaved note\n"))
    (let ((buffer-read-only t))
      (should (zerop (org-workflow-history-carry-over))))
    (should-not (org-entry-get nil "WORKFLOW_COMMITMENT_ID"))
    (should (= 1 (org-workflow-history-carry-over)))
    (should (string-match-p "An unsaved note" (buffer-string)))
    (should (buffer-modified-p))
    (with-temp-buffer
      (insert-file-contents file)
      (should-not (string-match-p "WORKFLOW_COMMITMENT_ID\\|An unsaved note"
                                  (buffer-string))))))
