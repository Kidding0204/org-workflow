;;; org-workflow-journal-test.el --- tests for workflow journal -*- lexical-binding: t; -*-

(require 'ert)
(require 'org)
(require 'vulpea-journal)
(require 'org-workflow-core)
(require 'org-workflow-journal)

(defmacro org-workflow-journal-test-with-note (level content &rest body)
  `(let* ((org-workflow-journal--tracking-anchor nil)
          (file (make-temp-file "workflow-journal-" nil ".org" ,content))
          (buffer (find-file-noselect file))
          (position
           (with-current-buffer buffer
             (org-mode)
             (goto-char (point-min))
             (if (zerop ,level) (point-min)
               (re-search-forward "^\\* Day")
               (line-beginning-position))))
          (note (make-vulpea-note
                 :id "journal-note" :path file :level ,level :pos position
                 :title "Journal" :tags '("journal"))))
     (unwind-protect
         (cl-letf (((symbol-function 'vulpea-journal-note)
                    (lambda (_date) note))
                   ((symbol-function 'vulpea-journal-find-note)
                    (lambda (_date) note))
                   ((symbol-function 'vulpea-journal-all-dates)
                    (lambda () nil)))
           ,@body)
       (when (buffer-live-p buffer)
         (with-current-buffer buffer (set-buffer-modified-p nil))
         (kill-buffer buffer))
       (delete-file file))))

(defun org-workflow-journal-test--section-count (record kind)
  "Return the number of generated KIND sections below RECORD."
  (org-with-point-at record
    (save-restriction
      (org-narrow-to-subtree)
      (let ((count 0))
        (org-map-entries
         (lambda ()
           (when (equal kind (org-entry-get nil "WORKFLOW_SECTION"))
             (cl-incf count)))
         nil 'tree)
        count))))

(defun org-workflow-journal-test--literal-file-string (file)
  "Return FILE's exact bytes as a unibyte string."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally file)
    (buffer-string)))

(defmacro org-workflow-journal-test-with-file-note (path &rest body)
  "Run BODY with a level-zero journal note visiting existing PATH."
  `(let* ((org-workflow-journal--tracking-anchor nil)
          (file ,path)
          (buffer (find-file-noselect file))
          (note (make-vulpea-note
                 :id "journal-note" :path file :level 0 :pos (point-min)
                 :title "Journal" :tags '("journal"))))
     (unwind-protect
         (cl-letf (((symbol-function 'vulpea-journal-note)
                    (lambda (_date) note))
                   ((symbol-function 'vulpea-journal-find-note)
                    (lambda (_date) note)))
           ,@body)
       (when (buffer-live-p buffer)
         (with-current-buffer buffer (set-buffer-modified-p nil))
         (kill-buffer buffer)))))

(ert-deftest org-workflow-journal-record-is-idempotent-in-daily-note ()
  (org-workflow-journal-test-with-note
   0 "#+title: Journal\n"
   (let ((first (org-workflow-journal-record "2026-08-24" t))
         (second (org-workflow-journal-record "2026-08-24" t)))
     (should (org-workflow-target--same-marker-p first second))
     (with-current-buffer (marker-buffer first)
       (goto-char (point-min))
       (should (= 1 (how-many ":WORKFLOW_RECORD: 2026-08-24")))))))

(ert-deftest org-workflow-journal-record-is-not-an-id-bearing-note ()
  (org-workflow-journal-test-with-note
   0 "#+title: Journal\n"
   (org-with-point-at (org-workflow-journal-record "2026-08-24" t)
     (should-not (org-entry-get nil "ID"))
     (should-not (org-entry-get nil "WORKFLOW_PHASE"))
     (should (equal "2026-08-24"
                    (org-entry-get nil org-workflow-journal-record-property))))))

(ert-deftest org-workflow-journal-remove-record-ids-preserves-note-ids ()
  (org-workflow-journal-test-with-note
   0
   (concat
    "#+title: Journal\n"
    "* Workflow\n"
    ":PROPERTIES:\n"
    ":ID: obsolete-workflow-id\n"
    ":WORKFLOW_RECORD: 2026-08-24\n"
    ":WORKFLOW_PHASE: minimum\n"
    ":END:\n"
    "* Real note\n"
    ":PROPERTIES:\n"
    ":ID: keep-real-note-id\n"
    ":END:\n")
   (cl-letf (((symbol-function 'vulpea-journal-all-dates)
              (lambda () (list (org-workflow-journal--date-time "2026-08-24"))))
             ((symbol-function 'vulpea-db-update-file) (lambda (_path) 1))
             ((symbol-function 'org-id-update-id-locations)
              (lambda (&rest _args) nil)))
     (should (= 1 (org-workflow-journal-remove-record-ids))))
   (with-current-buffer buffer
     (goto-char (point-min))
     (re-search-forward "^\\* Workflow")
     (should-not (org-entry-get nil "ID"))
     (re-search-forward "^\\* Real note")
     (should (equal "keep-real-note-id" (org-entry-get nil "ID"))))))

(ert-deftest org-workflow-journal-record-nests-under-monthly-day ()
  (org-workflow-journal-test-with-note
   1 "#+title: 2026-08\n* Day\n:PROPERTIES:\n:ID: day\n:END:\n"
   (cl-letf (((symbol-function 'org-workflow-journal-rows)
              (lambda (_date) nil)))
     (should (eq 'untouch
                 (org-workflow-journal-finalize "2026-08-24"))))
   (let ((record (org-workflow-journal-record "2026-08-24" nil)))
     (should (= 2 (org-with-point-at record (org-outline-level))))
     (should-not (org-with-point-at record
                   (org-entry-get nil "WORKFLOW_PHASE")))
     (with-current-buffer buffer
       (goto-char (point-min))
       (should-not (org-entry-get nil "COMMITMENT"))
       (re-search-forward "^\\* Day")
       (should (equal "day" (org-entry-get nil "ID")))
       (should (equal "untouch" (org-entry-get nil "COMMITMENT")))
       (should (equal "2026-08-24"
                      (org-workflow-target--timestamp-date
                       (org-entry-get nil "WORKFLOW_FINALIZED_AT"))))))))

(ert-deftest org-workflow-journal-finalizes-root-note-with-detail-tables ()
  (org-workflow-journal-test-with-note
   0
   (concat
    "#+title: Journal\n"
    "* Workflow\n"
    ":PROPERTIES:\n"
    ":WORKFLOW_RECORD: 2026-08-24\n"
    ":END:\n"
    "** Daily Summary\n"
    ":PROPERTIES:\n"
    ":WORKFLOW_SECTION: summary\n"
    ":END:\n"
    "obsolete prose\n")
   (cl-letf (((symbol-function 'org-workflow-journal-rows)
              (lambda (_date)
                '((:title "Promise" :link "Promise" :task-leaf t
                          :promise t :outcome done :minutes 30)
                  (:title "Optional" :link "Optional" :task-leaf t
                          :promise nil :outcome done :minutes 20)))))
     (should (eq 'met (org-workflow-journal-finalize "2026-08-24"))))
   (with-current-buffer buffer
     (goto-char (point-min))
     (should (equal "met" (org-entry-get nil "COMMITMENT")))
     (should (equal "30"
                    (org-entry-get nil "COMMITMENT_FOCUS_MINUTES")))
     (should (equal "20" (org-entry-get nil "OPTIONAL_FOCUS_MINUTES")))
     (should (equal "50" (org-entry-get nil "FOCUS_TOTAL_MINUTES")))
     (should (equal "1" (org-entry-get nil "OPTIONAL_COMPLETED")))
     (should (equal "2026-08-24"
                    (org-workflow-target--timestamp-date
                     (org-entry-get nil "WORKFLOW_FINALIZED_AT")))))
   (let ((record (org-workflow-journal-record "2026-08-24" nil)))
     (org-with-point-at record
       (should-not (org-entry-get nil "ID"))
       (should-not (org-entry-get nil "COMMITMENT"))
       (should-not (org-entry-get nil "WORKFLOW_PHASE")))
     (should (= 1 (org-workflow-journal-test--section-count
                   record "minimum")))
     (should (= 1 (org-workflow-journal-test--section-count
                   record "optional")))
     (should (= 0 (org-workflow-journal-test--section-count
                   record "summary")))
     (org-with-point-at record
       (save-restriction
         (org-narrow-to-subtree)
         (goto-char (point-min))
         (should (= 1 (how-many "^\\*+ Minimum Commitment Progress$")))
         (should (= 1 (how-many "^\\*+ Optional Work$")))
         (should (= 0 (how-many "^\\*+ Daily Summary$"))))))))

(ert-deftest org-workflow-journal-finalizes-unmet-commitment ()
  (org-workflow-journal-test-with-note
   0 "#+title: Journal\n"
   (cl-letf (((symbol-function 'org-workflow-journal-rows)
              (lambda (_date)
                '((:title "Pending" :link "Pending" :task-leaf t
                          :promise t :outcome pending :minutes 15)
                  (:title "Held optional" :link "Held optional"
                          :task-leaf t :promise nil :outcome held
                          :minutes 5)))))
     (should (eq 'unmet (org-workflow-journal-finalize "2026-08-24"))))
   (with-current-buffer buffer
     (goto-char (point-min))
     (should (equal "unmet" (org-entry-get nil "COMMITMENT")))
     (should (equal "15"
                    (org-entry-get nil "COMMITMENT_FOCUS_MINUTES")))
     (should (equal "5" (org-entry-get nil "OPTIONAL_FOCUS_MINUTES")))
     (should (equal "0" (org-entry-get nil "OPTIONAL_COMPLETED"))))))

(ert-deftest org-workflow-journal-finalizes-empty-commitment-as-untouch ()
  (org-workflow-journal-test-with-note
   0 "#+title: Journal\n"
   (cl-letf (((symbol-function 'org-workflow-journal-rows)
              (lambda (_date)
                '((:title "Optional" :link "Optional" :task-leaf t
                          :promise nil :outcome ready :minutes 10)))))
     (should (eq 'untouch
                 (org-workflow-journal-finalize "2026-08-24"))))
   (with-current-buffer buffer
     (goto-char (point-min))
     (should (equal "untouch" (org-entry-get nil "COMMITMENT")))
     (should (equal "0"
                    (org-entry-get nil "COMMITMENT_FOCUS_MINUTES")))
     (should (equal "10" (org-entry-get nil "OPTIONAL_FOCUS_MINUTES")))
     (should (equal "1" (org-entry-get nil "OPTIONAL_COMPLETED"))))))

(ert-deftest org-workflow-journal-finalization-is-idempotent ()
  (org-workflow-journal-test-with-note
   0 "#+title: Journal\n"
   (let ((queries 0))
     (cl-letf (((symbol-function 'org-workflow-journal-rows)
                (lambda (_date)
                  (cl-incf queries)
                  '((:title "Promise" :link "Promise" :task-leaf t
                            :promise t :outcome done :minutes 30)))))
       (should (eq 'met (org-workflow-journal-finalize "2026-08-24")))
       (should (eq 'met (org-workflow-journal-finalize "2026-08-24"))))
     (should (= 1 queries)))
   (let ((record (org-workflow-journal-record "2026-08-24" nil)))
     (should (= 1 (org-workflow-journal-test--section-count
                   record "minimum")))
     (should (= 1 (org-workflow-journal-test--section-count
                   record "optional"))))))

(ert-deftest org-workflow-journal-finalized-record-does-not-create-missing-record ()
  "Reading an absent Journal date leaves the Journal untouched."
  (let ((created nil))
    (cl-letf (((symbol-function 'vulpea-journal-find-note)
               (lambda (_date) nil))
              ((symbol-function 'vulpea-journal-note)
               (lambda (_date) (setq created t))))
      (should-not (org-workflow-journal-finalized-record "2026-08-24"))
      (should-not created))))

(ert-deftest org-workflow-journal-finalized-record-returns-finalized-boundary ()
  "A finalized record exposes its date, markers, and seal timestamp."
  (org-workflow-journal-test-with-note
   0 "#+title: Journal\n"
   (cl-letf (((symbol-function 'org-workflow-journal-rows)
              (lambda (_date) nil)))
     (org-workflow-journal-finalize "2026-08-24"))
   (let ((result (org-workflow-journal-finalized-record "2026-08-24")))
     (should (equal "2026-08-24" (plist-get result :date)))
     (should (markerp (plist-get result :summary-marker)))
     (should (markerp (plist-get result :record-marker)))
     (should (equal "[2026-08-24 22:00]" (plist-get result :finalized-at)))
     (should (equal '(:date :summary-marker :record-marker :finalized-at)
                    (cl-loop for (key _value) on result by #'cddr collect key))))))

(ert-deftest org-workflow-journal-finalized-hook-runs-once-after-new-save ()
  "A seal event is emitted only for the newly saved finalization."
  (org-workflow-journal-test-with-note
   0 "#+title: Journal\n"
   (let* ((dates nil)
          (org-workflow-journal-finalized-hook
          (list (lambda (date) (push date dates)))))
     (cl-letf (((symbol-function 'org-workflow-journal-rows)
                (lambda (_date) nil)))
       (should (eq 'untouch
                   (org-workflow-journal-finalize "2026-08-24")))
       (should (equal '("2026-08-24") dates))
       (should (eq 'untouch
                   (org-workflow-journal-finalize "2026-08-24")))
       (should (equal '("2026-08-24") dates))))))

(ert-deftest org-workflow-journal-finalized-hook-errors-preserve-finalization ()
  "A failing event listener cannot undo a successfully saved seal."
  (org-workflow-journal-test-with-note
   0 "#+title: Journal\n"
   (let* ((hook-runs 0)
          (org-workflow-journal-finalized-hook
          (list (lambda (_date)
                  (cl-incf hook-runs)
                  (error "listener failed")))))
     (cl-letf (((symbol-function 'org-workflow-journal-rows)
                (lambda (_date) nil)))
       (should (eq 'untouch
                   (org-workflow-journal-finalize "2026-08-24"))))
     (should (= 1 hook-runs))
     (with-current-buffer buffer
       (goto-char (point-min))
       (should (equal "[2026-08-24 22:00]"
                      (org-entry-get nil "WORKFLOW_FINALIZED_AT")))))))

(ert-deftest org-workflow-journal-finalization-refreshes-once-after-new-success ()
  "Only a newly persisted finalization invalidates the desktop status."
  (org-workflow-journal-test-with-note
   0 "#+title: Journal\n"
   (let ((refreshes 0))
     (cl-letf (((symbol-function 'org-workflow-journal-rows)
                (lambda (_date) nil))
               ((symbol-function 'org-workflow--request-gnome-refresh)
                (lambda () (cl-incf refreshes))))
       (should (eq 'untouch
                   (org-workflow-journal-finalize "2026-08-24")))
       (should (= 1 refreshes))
       (should (eq 'untouch
                   (org-workflow-journal-finalize "2026-08-24")))
       (should (= 1 refreshes))))))

(ert-deftest org-workflow-journal-finalization-failure-does-not-refresh ()
  "A failed save leaves status live and emits no finalized invalidation."
  (org-workflow-journal-test-with-note
   0 "#+title: Journal\n"
   (let ((refreshes 0))
     (cl-letf (((symbol-function 'org-workflow-journal-rows)
                (lambda (_date) nil))
               ((symbol-function 'save-buffer)
                (lambda (&rest _args) (error "disk full")))
               ((symbol-function 'org-workflow--request-gnome-refresh)
                (lambda () (cl-incf refreshes))))
       (should-error (org-workflow-journal-finalize "2026-08-24")
                     :type 'error))
     (should (= 0 refreshes)))))

(ert-deftest org-workflow-journal-finalization-rolls-back-on-save-error ()
  (org-workflow-journal-test-with-note
   0 "#+title: Journal\n"
   (let ((before (with-current-buffer buffer
                   (buffer-substring-no-properties (point-min) (point-max)))))
     (cl-letf (((symbol-function 'org-workflow-journal-rows)
                (lambda (_date)
                  '((:title "Promise" :link "Promise" :task-leaf t
                            :promise t :outcome done :minutes 30))))
               ((symbol-function 'save-buffer)
                (lambda (&rest _args) (error "disk full"))))
       (should-error (org-workflow-journal-finalize "2026-08-24")
                     :type 'error))
     (with-current-buffer buffer
       (should (equal before
                      (buffer-substring-no-properties
                       (point-min) (point-max))))
       (goto-char (point-min))
       (should-not (org-entry-get nil "WORKFLOW_FINALIZED_AT"))
       (should-not (org-entry-get nil "WORKFLOW_TRACKING_STARTED")))
     (should-not (org-workflow-journal-record "2026-08-24" nil))
     (with-temp-buffer
       (insert-file-contents file)
       (should (equal before (buffer-string)))))))

(ert-deftest org-workflow-journal-finalization-restores-disk-after-hook-error ()
  (org-workflow-journal-test-with-note
   0 "#+title: Journal\n"
   (with-current-buffer buffer
     (goto-char (point-max))
     (insert "# unsaved before seal\n"))
   (let ((before-buffer
          (with-current-buffer buffer
            (buffer-substring-no-properties (point-min) (point-max))))
         (before-disk (org-workflow-journal-test--literal-file-string file))
         (modes (file-modes file)))
     (let ((after-save-hook
            (list (lambda () (error "after-save failed")))))
       (cl-letf (((symbol-function 'org-workflow-journal-rows)
                  (lambda (_date)
                    '((:title "Promise" :link "Promise" :task-leaf t
                              :promise t :outcome done :minutes 30)))))
         (let ((error-data
                (should-error
                 (org-workflow-journal-finalize "2026-08-24")
                 :type 'error)))
           (should (equal "after-save failed"
                          (error-message-string error-data))))))
     (with-current-buffer buffer
       (should (equal before-buffer
                      (buffer-substring-no-properties
                       (point-min) (point-max))))
       (should (buffer-modified-p))
       (goto-char (point-min))
       (should-not (org-entry-get nil "WORKFLOW_FINALIZED_AT")))
     (should (equal before-disk
                    (org-workflow-journal-test--literal-file-string file)))
     (should-not (equal before-buffer before-disk))
     (should (= modes (file-modes file)))
     (should-not (org-workflow-journal-status "2026-08-24"))
     (with-current-buffer buffer
       (set-buffer-modified-p nil))
     (kill-buffer buffer)
     (setq buffer (find-file-noselect file))
     (cl-letf (((symbol-function 'org-workflow-journal-rows)
                (lambda (_date)
                  '((:title "Promise" :link "Promise" :task-leaf t
                            :promise t :outcome done :minutes 30)))))
       (should (eq 'met
                   (org-workflow-journal-finalize "2026-08-24"))))
     (should (org-workflow-journal-status "2026-08-24")))))

(ert-deftest org-workflow-journal-rollback-preserves-symlink-identity ()
  (let* ((target (make-temp-file
                  "workflow-journal-target-" nil ".org"
                  "#+title: Journal\n"))
         (link (concat target "-link.org")))
    (unwind-protect
        (progn
          (make-symbolic-link target link)
          (org-workflow-journal-test-with-file-note
           link
           (let ((before
                  (org-workflow-journal-test--literal-file-string target))
                 (link-target (file-symlink-p link))
                 (modes (file-modes target)))
             (let ((after-save-hook
                    (list (lambda () (error "after-save failed")))))
               (cl-letf (((symbol-function 'org-workflow-journal-rows)
                          (lambda (_date)
                            '((:title "Promise" :link "Promise"
                                      :task-leaf t :promise t
                                      :outcome done :minutes 30)))))
                 (should-error
                  (org-workflow-journal-finalize "2026-08-24")
                  :type 'error)))
             (should (equal link-target (file-symlink-p link)))
             (should (equal (file-truename target) (file-truename link)))
             (should (equal before
                            (org-workflow-journal-test--literal-file-string
                             target)))
             (should (equal before
                            (org-workflow-journal-test--literal-file-string
                             link)))
             (should (= modes (file-modes target)))
             (with-current-buffer buffer
               (should-not (buffer-modified-p))
               (should-not (save-excursion
                             (goto-char (point-min))
                             (re-search-forward
                              "WORKFLOW_FINALIZED_AT" nil t)))))))
      (when (file-exists-p link) (delete-file link))
      (when (file-exists-p target) (delete-file target)))))

(ert-deftest org-workflow-journal-rollback-preserves-hard-link-identity ()
  (let* ((target (make-temp-file
                  "workflow-journal-target-" nil ".org"
                  "#+title: Journal\n"))
         (link (concat target "-hard.org")))
    (unwind-protect
        (progn
          (add-name-to-file target link)
          (org-workflow-journal-test-with-file-note
           link
           (let* ((before
                   (org-workflow-journal-test--literal-file-string target))
                  (attributes (file-attributes link))
                  (inode (file-attribute-inode-number attributes))
                  (links (file-attribute-link-number attributes))
                  (modes (file-modes link)))
             (let ((after-save-hook
                    (list (lambda () (error "after-save failed")))))
               (cl-letf (((symbol-function 'org-workflow-journal-rows)
                          (lambda (_date)
                            '((:title "Promise" :link "Promise"
                                      :task-leaf t :promise t
                                      :outcome done :minutes 30)))))
                 (should-error
                  (org-workflow-journal-finalize "2026-08-24")
                  :type 'error)))
             (let ((target-attributes (file-attributes target))
                   (link-attributes (file-attributes link)))
               (should (= inode
                          (file-attribute-inode-number target-attributes)))
               (should (= inode
                          (file-attribute-inode-number link-attributes)))
               (should (= links
                          (file-attribute-link-number target-attributes)))
               (should (= links
                          (file-attribute-link-number link-attributes))))
             (should (equal before
                            (org-workflow-journal-test--literal-file-string
                             target)))
             (should (equal before
                            (org-workflow-journal-test--literal-file-string
                             link)))
             (should (= modes (file-modes link)))
             (with-current-buffer buffer
               (should-not (buffer-modified-p))
               (should-not (save-excursion
                             (goto-char (point-min))
                             (re-search-forward
                              "WORKFLOW_FINALIZED_AT" nil t)))))))
      (when (file-exists-p link) (delete-file link))
      (when (file-exists-p target) (delete-file target)))))

(ert-deftest org-workflow-journal-finalization-preserves-retired-properties ()
  (org-workflow-journal-test-with-note
   1
   (concat
    "#+title: 2026-08\n"
    "* Day\n"
    ":PROPERTIES:\n"
    ":ID: daily-note-id\n"
    ":END:\n"
    "** Workflow\n"
    ":PROPERTIES:\n"
    ":ID: legacy-workflow-id\n"
    ":WORKFLOW_RECORD: 2026-08-24\n"
    ":WORKFLOW_PHASE: optional\n"
    ":WORKFLOW_BATCH: [2026-08-24]/minimum\n"
    ":WORKFLOW_BLOCKED_BY: legacy-id\n"
    ":WORKFLOW_MINIMUM_SEALED_AT: [2026-08-24 Mon 12:00]\n"
    ":COMMITMENT: unmet\n"
    ":END:\n")
   (cl-letf (((symbol-function 'org-workflow-journal-rows)
              (lambda (_date)
                '((:title "Promise" :link "Promise" :task-leaf t
                          :promise t :outcome done :minutes 30)))))
     (should (eq 'met (org-workflow-journal-finalize "2026-08-24"))))
   (with-current-buffer buffer
     (goto-char (point-min))
     (re-search-forward "^\\* Day")
     (should (equal "daily-note-id" (org-entry-get nil "ID")))
     (should (equal "met" (org-entry-get nil "COMMITMENT"))))
   (org-with-point-at (org-workflow-journal-record "2026-08-24" nil)
     (should-not (org-entry-get nil "ID"))
     (should-not (org-entry-get nil "COMMITMENT"))
     (should (equal "optional" (org-entry-get nil "WORKFLOW_PHASE")))
     (should (equal "[2026-08-24]/minimum"
                    (org-entry-get nil "WORKFLOW_BATCH")))
     (should (equal "legacy-id"
                    (org-entry-get nil "WORKFLOW_BLOCKED_BY")))
     (should (equal "[2026-08-24 Mon 12:00]"
                    (org-entry-get nil "WORKFLOW_MINIMUM_SEALED_AT")))
     (should (equal "2026-08-24"
                    (org-entry-get nil "WORKFLOW_RECORD"))))))

(ert-deftest org-workflow-journal-finalization-collapses-duplicate-sections ()
  (org-workflow-journal-test-with-note
   0
   (concat
    "#+title: Journal\n"
    "* Workflow\n"
    ":PROPERTIES:\n"
    ":WORKFLOW_RECORD: 2026-08-24\n"
    ":END:\n"
    "** Minimum Commitment Progress\n"
    ":PROPERTIES:\n:WORKFLOW_SECTION: minimum\n:END:\nold one\n"
    "** Minimum Commitment Progress\n"
    ":PROPERTIES:\n:WORKFLOW_SECTION: minimum\n:END:\nold two\n"
    "** Optional Work\n"
    ":PROPERTIES:\n:WORKFLOW_SECTION: optional\n:END:\nold one\n"
    "** Optional Work\n"
    ":PROPERTIES:\n:WORKFLOW_SECTION: optional\n:END:\nold two\n")
   (cl-letf (((symbol-function 'org-workflow-journal-rows)
              (lambda (_date)
                '((:title "Promise" :link "Promise" :task-leaf t
                          :promise t :outcome done :minutes 30)
                  (:title "Optional" :link "Optional" :task-leaf t
                          :promise nil :outcome done :minutes 20)))))
     (org-workflow-journal-finalize "2026-08-24"))
   (let ((record (org-workflow-journal-record "2026-08-24" nil)))
     (should (= 1 (org-workflow-journal-test--section-count
                   record "minimum")))
     (should (= 1 (org-workflow-journal-test--section-count
                   record "optional")))
     (org-with-point-at record
       (save-restriction
         (org-narrow-to-subtree)
         (goto-char (point-min))
         (should (= 1 (how-many "^\\*+ Minimum Commitment Progress$")))
         (should (= 1 (how-many "^\\*+ Optional Work$")))
         (should-not (re-search-forward "old \\(one\\|two\\)" nil t)))))))

(ert-deftest org-workflow-journal-status-exposes-only-finalized-records ()
  (org-workflow-journal-test-with-note
   0 "#+title: Journal\n"
   (should-not (org-workflow-journal-status "2026-08-24"))
   (cl-letf (((symbol-function 'org-workflow-journal-rows)
              (lambda (_date)
                '((:title "Promise" :link "Promise" :task-leaf t
                          :promise t :outcome done :minutes 30)))))
     (org-workflow-journal-finalize "2026-08-24"))
   (cl-letf (((symbol-function 'org-workflow--promise-progress)
              (lambda (_date)
                '(:minimumSatisfied 1 :minimumTotal 2
                  :phase "minimum" :commitmentComplete :false))))
     (let ((status (org-workflow-journal-status "2026-08-24")))
       (should (= 1 (plist-get status :minimumSatisfied)))
       (should (= 2 (plist-get status :minimumTotal)))
       (should (equal "finalized" (plist-get status :phase)))
       (should (eq t (plist-get status :commitmentComplete))))
     (with-current-buffer buffer
       (goto-char (point-min))
       (org-entry-put nil "COMMITMENT" "unmet"))
     (should (eq :false
                 (plist-get (org-workflow-journal-status "2026-08-24")
                            :commitmentComplete))))))

(ert-deftest org-workflow-journal-commitment-streak-uses-finalized-history-and-live-today ()
  "Only sealed `met' days extend the streak; today's value stays provisional."
  (let ((outcomes '(("2026-08-24" . unmet)
                    ("2026-08-25" . met)
                    ("2026-08-26" . met)))
        (before-seal (encode-time 0 59 21 27 8 2026))
        (at-seal (encode-time 0 0 22 27 8 2026)))
    (cl-letf (((symbol-function 'org-workflow-journal-ensure-anchor)
               (lambda (&optional _date) "2026-08-24"))
              ((symbol-function 'org-workflow-journal--finalized-commitment)
               (lambda (date) (alist-get date outcomes nil nil #'equal))))
      (should (= 2 (org-workflow-journal-commitment-streak
                    "2026-08-27"
                    '(:commitmentComplete :false) before-seal)))
      (should (= 3 (org-workflow-journal-commitment-streak
                    "2026-08-27"
                    '(:commitmentComplete t) before-seal)))
      (should (= 0 (org-workflow-journal-commitment-streak
                    "2026-08-27"
                    '(:commitmentComplete t) at-seal)))
      (setf (alist-get "2026-08-27" outcomes nil nil #'equal) 'met)
      (should (= 3 (org-workflow-journal-commitment-streak
                    "2026-08-27"
                    '(:commitmentComplete :false) at-seal)))
      (setf (alist-get "2026-08-27" outcomes nil nil #'equal) 'unmet)
      (should (= 0 (org-workflow-journal-commitment-streak
                    "2026-08-27"
                    '(:commitmentComplete t) at-seal)))
      (setf (alist-get "2026-08-27" outcomes nil nil #'equal) 'untouch)
      (should (= 0 (org-workflow-journal-commitment-streak
                    "2026-08-27"
                    '(:commitmentComplete t) at-seal)))
      (setf (alist-get "2026-08-27" outcomes nil nil #'equal) nil)
      (setf (alist-get "2026-08-26" outcomes nil nil #'equal) nil)
      (should (= 0 (org-workflow-journal-commitment-streak
                    "2026-08-27"
                    '(:commitmentComplete :false) before-seal))))))

(ert-deftest org-workflow-journal-anchor-is-written-at-root-by-successful-seal ()
  (org-workflow-journal-test-with-note
   0 "#+title: Journal\n"
   (should (equal "2026-08-24"
                  (org-workflow-journal-ensure-anchor "2026-08-24")))
   (with-current-buffer buffer
     (goto-char (point-min))
     (should-not (org-entry-get nil "WORKFLOW_TRACKING_STARTED")))
   (should-not (org-workflow-journal-record "2026-08-24" nil))
   (cl-letf (((symbol-function 'org-workflow-journal-rows)
              (lambda (_date) nil)))
     (should (eq 'untouch
                 (org-workflow-journal-finalize "2026-08-24"))))
   (with-current-buffer buffer
     (goto-char (point-min))
     (should (equal "[2026-08-24]"
                    (org-entry-get nil "WORKFLOW_TRACKING_STARTED"))))
   (org-with-point-at (org-workflow-journal-record "2026-08-24" nil)
     (should-not (org-entry-get nil "WORKFLOW_TRACKING_STARTED")))))

(ert-deftest org-workflow-journal-anchor-migrates-legacy-child-read ()
  "A legacy child anchor is read without moving it before a successful seal."
  (org-workflow-journal-test-with-note
   0
   "#+title: Journal\n* Workflow\n:PROPERTIES:\n:WORKFLOW_RECORD: 2026-08-24\n:WORKFLOW_TRACKING_STARTED: [2026-08-20]\n:END:\n"
   (cl-letf (((symbol-function 'vulpea-journal-all-dates)
              (lambda ()
                (list (org-workflow-journal--date-time "2026-08-24")))))
     (should (equal "2026-08-20"
                    (org-workflow-journal-ensure-anchor "2026-08-25"))))
   (with-current-buffer buffer
     (goto-char (point-min))
     (should-not (org-entry-get nil "WORKFLOW_TRACKING_STARTED")))))

(ert-deftest org-workflow-journal-next-seal-time-is-first-strictly-later-2200 ()
  "The daily seal targets the first local 22:00 strictly after now."
  (dolist (case `((,(encode-time 0 59 21 27 8 2026) . (27 8 2026 22 0))
                  (,(encode-time 0 0 22 27 8 2026) . (28 8 2026 22 0))
                  (,(encode-time 0 1 22 27 8 2026) . (28 8 2026 22 0))))
    (let ((decoded (decode-time
                    (org-workflow-journal--next-seal-time (car case)))))
      (should (equal (cdr case)
                     (list (decoded-time-day decoded)
                           (decoded-time-month decoded)
                           (decoded-time-year decoded)
                           (decoded-time-hour decoded)
                           (decoded-time-minute decoded)))))))

(ert-deftest org-workflow-journal-catch-up-stops-at-local-2200-cutoff ()
  "Catch-up includes today only once its local 22:00 seal is eligible."
  (let (finalized)
    (cl-letf (((symbol-function 'org-workflow-journal-ensure-anchor)
               (lambda (&optional _) "2026-08-24"))
              ((symbol-function 'org-workflow-journal-finalize)
               (lambda (date) (push date finalized) 'untouch)))
      (should (equal '("2026-08-24" "2026-08-25" "2026-08-26")
                     (org-workflow-journal-catch-up
                      (encode-time 0 0 21 27 8 2026))))
      (should (equal '("2026-08-24" "2026-08-25" "2026-08-26"
                       "2026-08-27")
                     (org-workflow-journal-catch-up
                      (encode-time 0 1 22 27 8 2026)))))))

(ert-deftest org-workflow-journal-delayed-seal-catches-up-across-midnight ()
  "A delayed timer seals its captured date instead of the execution date."
  (let ((org-workflow-journal-seal-timer nil)
        (now (encode-time 0 5 0 28 8 2026))
        callbacks
        finalized)
    (cl-letf (((symbol-function 'current-time) (lambda () now))
              ((symbol-function 'org-workflow-journal--next-seal-time)
               (lambda (&optional _now)
                 (encode-time 0 0 22 27 8 2026)))
              ((symbol-function 'run-at-time)
               (lambda (_time _repeat callback &rest args)
                 (push (cons callback args) callbacks)
                 (intern (format "seal-timer-%d" (length callbacks)))))
              ((symbol-function 'org-workflow-journal-ensure-anchor)
               (lambda (&optional _) "2026-08-27"))
              ((symbol-function 'org-workflow-journal-finalize)
               (lambda (date) (push date finalized) 'untouch)))
      (org-workflow-journal--schedule-seal)
      (let ((scheduled (car callbacks)))
        (apply (car scheduled) (cdr scheduled))))
    (should (equal '("2026-08-27") finalized))))

(ert-deftest org-workflow-journal-setup-schedules-before-crossing-2200 ()
  "Setup retains today's timer when synchronous catch-up crosses 22:00."
  (let ((org-workflow-journal-seal-timer nil)
        (org-workflow-status-provider-function nil)
        (now (encode-time 0 59 21 27 8 2026))
        scheduled-time
        callback
        callback-args
        finalized)
    (cl-letf (((symbol-function 'current-time) (lambda () now))
              ((symbol-function 'run-at-time)
               (lambda (time _repeat function &rest args)
                 (setq scheduled-time time
                       callback function
                       callback-args args)
                 'seal-timer))
              ((symbol-function 'org-workflow-journal-catch-up)
               (lambda (&optional _now)
                 (setq now (encode-time 0 1 22 27 8 2026))))
              ((symbol-function 'org-workflow-journal-finalize)
               (lambda (date) (push date finalized) 'untouch)))
      (org-workflow-journal-setup)
      (let ((decoded (decode-time scheduled-time)))
        (should (equal '(27 8 2026 22 0)
                       (list (decoded-time-day decoded)
                             (decoded-time-month decoded)
                             (decoded-time-year decoded)
                             (decoded-time-hour decoded)
                             (decoded-time-minute decoded)))))
      (apply callback callback-args))
    (should (equal '("2026-08-27") finalized))))

(ert-deftest org-workflow-journal-seal-error-notifies-and-reschedules ()
  "A failed seal remains retryable while the next timer is installed."
  (let ((org-workflow-journal-seal-timer nil)
        callbacks notifications)
    (cl-letf (((symbol-function 'run-at-time)
               (lambda (_time _repeat callback &rest _args)
                 (push callback callbacks)
                 (intern (format "seal-timer-%d" (length callbacks)))))
              ((symbol-function 'org-workflow-journal-finalize)
               (lambda (_date) (error "save failed")))
              ((symbol-function 'org-workflow--notify)
               (lambda (title body) (push (list title body) notifications))))
      (org-workflow-journal--schedule-seal)
      (funcall (car callbacks)))
    (should (= 2 (length callbacks)))
    (should (equal '(("Org Workflow journal" "save failed"))
                   notifications))))

(ert-deftest org-workflow-journal-direct-clock-excludes-child-subtree ()
  (with-temp-buffer
    (org-mode)
    (insert "* Parent\n:LOGBOOK:\nCLOCK: [2026-08-24 Mon 09:00]--[2026-08-24 Mon 09:10] =>  0:10\n:END:\n** Child\n:LOGBOOK:\nCLOCK: [2026-08-24 Mon 09:10]--[2026-08-24 Mon 09:30] =>  0:20\n:END:\n")
    (goto-char (point-min))
    (let ((parent (point-marker)) child)
      (outline-next-heading)
      (setq child (point-marker))
      (should (= 10 (org-workflow-journal-direct-clock-minutes
                     parent "[2026-08-24 00:00]" "[2026-08-25 00:00]")))
      (should (= 20 (org-workflow-journal-direct-clock-minutes
                     child "[2026-08-24 00:00]" "[2026-08-25 00:00]"))))))

(ert-deftest org-workflow-journal-direct-clock-clips-at-seal-boundary ()
  (with-temp-buffer
    (org-mode)
    (insert "* Task\n:LOGBOOK:\nCLOCK: [2026-08-24 Mon 21:30]--[2026-08-24 Mon 22:30] =>  1:00\n:END:\n")
    (should (= 30 (org-workflow-journal-direct-clock-minutes
                   (point-marker) "[2026-08-24 00:00]" "[2026-08-24 22:00]")))))

(ert-deftest org-workflow-journal-rows-retain-nonleaf-direct-focus ()
  "Direct focus survives decomposition and keeps final inherited promise."
  (let* ((task-file
          (make-temp-file
           "workflow-nonleaf-focus-" nil ".org"
           (concat
            "#+filetags: :area:\n#+TODO: TODO | DONE\n"
            "* Promised area :promise:\n"
            "** TODO Promised container\n"
            ":LOGBOOK:\n"
            "CLOCK: [2026-08-24 Mon 09:00]--[2026-08-24 Mon 09:15] =>  0:15\n"
            ":END:\n"
            "*** TODO Focused child\n"
            ":LOGBOOK:\n"
            "CLOCK: [2026-08-24 Mon 09:15]--[2026-08-24 Mon 09:20] =>  0:05\n"
            ":END:\n"
            "* Optional area\n"
            "** TODO Optional focus only\n"
            ":LOGBOOK:\n"
            "CLOCK: [2026-08-24 Mon 10:00]--[2026-08-24 Mon 10:10] =>  0:10\n"
            ":END:\n")))
         (before (org-workflow-journal-test--literal-file-string task-file)))
    (unwind-protect
        (let ((org-agenda-files (list task-file)))
          (with-current-buffer (find-file-noselect task-file)
            (let ((was-modified (buffer-modified-p))
                  (rows (org-workflow-journal-rows "2026-08-24")))
              (should (equal '("Promised container" "Focused child"
                               "Optional focus only")
                             (mapcar (lambda (row) (plist-get row :title))
                                     rows)))
              (should (equal '(nil t t)
                             (mapcar (lambda (row)
                                       (plist-get row :task-leaf))
                                     rows)))
              (should (equal '(t t nil)
                             (mapcar (lambda (row) (plist-get row :promise))
                                     rows)))
              (should (equal '(focused focused focused)
                             (mapcar (lambda (row) (plist-get row :outcome))
                                     rows)))
              (should (equal '(15 5 10)
                             (mapcar (lambda (row) (plist-get row :minutes))
                                     rows)))
              (should (eq was-modified (buffer-modified-p)))))
          (let ((data (org-workflow-journal--final-data "2026-08-24")))
            (should (eq 'untouch (plist-get data :outcome)))
            (should-not (plist-get data :promise-rows))
            (should (= 20 (plist-get data :commitment-minutes)))
            (should (= 10 (plist-get data :optional-minutes)))
            (should (= 0 (plist-get data :optional-completed))))
          (should (equal before
                         (org-workflow-journal-test--literal-file-string
                          task-file))))
      (when-let* ((buffer (get-file-buffer task-file)))
        (with-current-buffer buffer (set-buffer-modified-p nil))
        (kill-buffer buffer))
      (delete-file task-file))))

(ert-deftest org-workflow-journal-rows-queries-final-facts-without-mutation ()
  "Final facts, not selection batches, determine the journal rows."
  (let ((task-file
         (make-temp-file
          "workflow-final-facts-" nil ".org"
          "#+filetags: :area:\n#+TODO: TODO READY | DONE HOLD\n* Area\n** DONE Promise done :promise:\nSCHEDULED: <2026-08-23 Sun> CLOSED: [2026-08-24 Mon 10:00]\n:PROPERTIES:\n:WORKFLOW_BATCH: [2026-08-24]/optional\n:WORKFLOW_BLOCKED_BY: missing-id\n:WORKFLOW_PHASE: optional\n:WORKFLOW_MINIMUM_SEALED_AT: [2026-08-24 Mon 09:00]\n:END:\n:LOGBOOK:\nCLOCK: [2026-08-24 Mon 09:30]--[2026-08-24 Mon 10:00] =>  0:30\n:END:\n** READY Promise ready :promise:\n:PROPERTIES:\n:WORKFLOW_READY_ON: [2026-08-24 Mon 11:00]\n:END:\n** DONE Optional done\nSCHEDULED: <2026-08-24 Mon> CLOSED: [2026-08-24 Mon 12:00]\n** HOLD Optional held\nSCHEDULED: <2026-08-24 Mon> CLOSED: [2026-08-24 Mon 13:00]\n")))
    (unwind-protect
        (let ((org-agenda-files (list task-file)))
          (let ((rows (org-workflow-journal-rows "2026-08-24")))
            (should (equal '("Promise done" "Promise ready" "Optional done"
                             "Optional held")
                           (mapcar (lambda (row) (plist-get row :title)) rows)))
            (should (equal '(t t nil nil)
                           (mapcar (lambda (row) (plist-get row :promise)) rows)))
            (should (equal '(done ready done held)
                           (mapcar (lambda (row) (plist-get row :outcome)) rows)))
            (should (equal '(30 0 0 0)
                           (mapcar (lambda (row) (plist-get row :minutes)) rows)))
            (should (equal '(t t t t)
                           (mapcar (lambda (row) (plist-get row :task-leaf)) rows)))
            (should (equal '(nil nil nil nil)
                           (mapcar (lambda (row) (plist-get row :id)) rows))))
          (with-current-buffer (find-file-noselect task-file)
            (goto-char (point-min))
            (should-not (re-search-forward "^:ID:" nil t))
            (goto-char (point-min))
            (dolist (property '("WORKFLOW_BATCH" "WORKFLOW_BLOCKED_BY"
                                "WORKFLOW_PHASE"
                                "WORKFLOW_MINIMUM_SEALED_AT"))
              (should (re-search-forward
                       (format "^:%s:" property) nil t)))))
      (when-let* ((buffer (get-file-buffer task-file)))
        (with-current-buffer buffer (set-buffer-modified-p nil))
        (kill-buffer buffer))
      (delete-file task-file))))

(ert-deftest org-workflow-journal-rows-escape-table-and-link-titles ()
  "Table rows preserve headings containing Org table or link delimiters."
  (let ((task-file
         (make-temp-file
          "workflow-escaped-titles-" nil ".org"
          "#+filetags: :area:\n#+TODO: TODO | DONE\n* Area\n** DONE Plain | title\nSCHEDULED: <2026-08-24 Mon> CLOSED: [2026-08-24 Mon 10:00]\n** DONE Linked ] | title\nSCHEDULED: <2026-08-24 Mon> CLOSED: [2026-08-24 Mon 11:00]\n:PROPERTIES:\n:ID: linked-id\n:END:\n")))
    (unwind-protect
        (let ((org-agenda-files (list task-file)))
          (let ((rows (org-workflow-journal-rows "2026-08-24")))
            (should (equal "Plain \\vert title" (plist-get (car rows) :link)))
            (should (equal "[[id:linked-id][Linked \\] \\vert title]]"
                           (plist-get (cadr rows) :link)))
            (with-temp-buffer
              (org-mode)
              (insert (org-workflow-journal--rows-table rows))
              (goto-char (point-min))
              (let ((table (org-table-to-lisp)))
                (should (equal '("Plain \\vert title" "done" "0")
                               (nth 2 table)))
                (should (equal '("[[id:linked-id][Linked \\] \\vert title]]"
                                 "done" "0")
                               (nth 3 table)))))))
      (when-let* ((buffer (get-file-buffer task-file)))
        (with-current-buffer buffer (set-buffer-modified-p nil))
        (kill-buffer buffer))
      (delete-file task-file))))

(ert-deftest org-workflow-journal-setup-installs-only-status-and-one-2200-timer ()
  "Journal setup exposes finalized status and schedules one daily seal."
  (let ((org-workflow-journal-seal-timer nil)
        (org-after-todo-state-change-hook nil)
        (org-workflow-status-provider-function nil)
        (org-workflow-commitment-streak-provider-function nil)
        (catch-ups 0)
        scheduled)
    (cl-letf (((symbol-function 'org-workflow-journal-catch-up)
               (lambda (&optional _now) (cl-incf catch-ups)))
              ((symbol-function 'run-at-time)
               (lambda (time repeat function &rest args)
                 (push (list time repeat function args) scheduled)
                 'seal-timer)))
      (org-workflow-journal-setup))
    (should (eq #'org-workflow-journal-status
                org-workflow-status-provider-function))
    (should (eq #'org-workflow-journal-commitment-streak
                org-workflow-commitment-streak-provider-function))
    (should (eq 'seal-timer org-workflow-journal-seal-timer))
    (should (= 1 catch-ups))
    (should (= 1 (length scheduled)))
    (should-not (cadar scheduled))
    (should-not org-after-todo-state-change-hook)))

(ert-deftest org-workflow-journal-setup-retires-live-legacy-midnight-timer ()
  "Reloading the new setup cancels the daemon's obsolete midnight timer."
  (let* ((legacy-symbol 'org-workflow-journal-midnight-timer)
         (legacy-timer (run-at-time 3600 nil #'ignore)))
    (unwind-protect
        (progn
          (set legacy-symbol legacy-timer)
          (cl-letf (((symbol-function 'org-workflow-journal-catch-up)
                     (lambda (&optional _now) nil))
                    ((symbol-function 'org-workflow-journal--schedule-seal)
                     #'ignore))
            (org-workflow-journal-setup))
          (should-not (memq legacy-timer timer-list))
          (should-not (boundp legacy-symbol)))
      (when (memq legacy-timer timer-list)
        (cancel-timer legacy-timer))
      (when (boundp legacy-symbol)
        (makunbound legacy-symbol)))))

(provide 'org-workflow-journal-test)
;;; org-workflow-journal-test.el ends here
