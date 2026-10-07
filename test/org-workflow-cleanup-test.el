;;; org-workflow-cleanup-test.el --- Property migration regression -*- lexical-binding: t; -*-
(unless (fboundp 'org-workflow-store-test) (load "org-workflow-store-test" nil t))
(require 'org-workflow-cleanup)

(ert-deftest workflow-cleanup-backs-up-sources-and-preserves-facts ()
  (org-workflow-store-test
   (let ((user-emacs-directory directory))
     (org-workflow-store-set-meta "migration-v1" "complete")
     (org-schedule nil "2026-09-17")
     (let* ((id (org-entry-get nil "WORKFLOW_COMMITMENT_ID"))
            (row (org-workflow-store-commitment id)))
       (org-entry-put nil "WORKFLOW_COMMITTED_AT" (nth 2 row))
       (org-entry-put nil "WORKFLOW_COMMITTED_FOR" (nth 3 row))
       (org-entry-put nil "WORKFLOW_ORDER_SCOPE"
                      (format "2026-09-16/%d" (org-get-priority "[#A]")))
       (org-entry-put nil "WORKFLOW_ORDER" "0")
       (org-entry-put nil "WORKFLOW_DEFER_COUNT" "2")
       (org-entry-put nil "WORKFLOW_BATCH" "old")
       (save-buffer)
       (let* ((before (buffer-string))
              (events (sqlite-select (org-workflow-store--db) "SELECT * FROM events"))
              (preview (org-workflow-cleanup-properties)))
         (should (= 1 (plist-get preview :headings)))
         (should (= 5 (plist-get preview :removed)))
         (should (= 1 (plist-get preview :orders)))
         (should (equal before (buffer-string)))
         (let* ((result (org-workflow-cleanup-properties t))
                (backup (plist-get result :backup))
                (copy (sqlite-open (expand-file-name "facts-before.sqlite" backup) 'read-only)))
           (unwind-protect
               (progn
                 (should (equal (list row) (sqlite-select copy "SELECT * FROM commitments")))
                 (should (equal before (with-temp-buffer
                                        (insert-file-contents
                                         (expand-file-name (concat (secure-hash 'sha256 file) ".org") backup))
                                        (buffer-string)))))
             (sqlite-close copy)))
         (should (equal row (org-workflow-store-commitment id)))
         (should (equal events (sqlite-select (org-workflow-store--db) "SELECT * FROM events")))
         (should (equal "A/0" (org-entry-get nil "WORKFLOW_ORDER")))
         (should (equal id (org-entry-get nil "WORKFLOW_COMMITMENT_ID")))
         (dolist (property (cons "WORKFLOW_ORDER_SCOPE" org-workflow-cleanup--retired-properties))
           (should-not (org-entry-get nil property)))
         (should-not (buffer-modified-p))
         (should-not (sqlite-select (org-workflow-store--db)
                                    "SELECT id FROM operations WHERE state IN ('applied','prepared')"))
         (should (= 0 (plist-get (org-workflow-cleanup-properties t) :headings))))))))

(ert-deftest workflow-cleanup-rejects-unverified-commitment-without-editing ()
  (org-workflow-store-test
   (org-workflow-store-set-meta "migration-v1" "complete")
   (org-entry-put nil "WORKFLOW_COMMITTED_FOR" "2026-09-17")
   (let ((before (buffer-string)))
     (should-error (org-workflow-cleanup-properties t) :type 'user-error)
     (should (equal before (buffer-string))))))

(ert-deftest workflow-cleanup-rejects-unsaved-sources-and-invalid-order ()
  (org-workflow-store-test
   (org-workflow-store-set-meta "migration-v1" "complete")
   (org-entry-put nil "WORKFLOW_DEFER_COUNT" "1")
   (let ((before (buffer-string)))
     (should-error (org-workflow-cleanup-properties t) :type 'user-error)
     (should (equal before (buffer-string))))
   (org-entry-put nil "WORKFLOW_ORDER" "broken")
   (should-error (org-workflow-cleanup-properties) :type 'user-error)))

(ert-deftest workflow-scheduling-stores-facts-without-tracking-properties ()
  (org-workflow-store-test
   (org-schedule nil "2026-09-17")
   (let ((id (org-entry-get nil "WORKFLOW_COMMITMENT_ID")))
     (should id)
     (should (nth 2 (org-workflow-store-commitment id)))
     (should (equal "2026-09-17" (nth 3 (org-workflow-store-commitment id))))
     (org-schedule nil "2026-09-18")
     (dolist (property '("WORKFLOW_COMMITTED_AT" "WORKFLOW_COMMITTED_FOR" "WORKFLOW_DEFER_COUNT"))
       (should-not (org-entry-get nil property))))))

(ert-deftest workflow-cleanup-leaves-area-tagged-journals-unchanged ()
  (org-workflow-store-test
   (org-workflow-store-set-meta "migration-v1" "complete")
   (let* ((journal (expand-file-name "week.org" directory))
          (org-agenda-files (list file journal))
          (text "#+filetags: :journal-week:area:\n* Old record\n:PROPERTIES:\n:WORKFLOW_BATCH: preserve\n:END:\n"))
     (unwind-protect
         (progn
           (with-temp-file journal (insert text))
           (should (= 0 (plist-get (org-workflow-cleanup-properties t) :headings)))
           (should (equal text (with-temp-buffer
                                 (insert-file-contents journal) (buffer-string)))))
       (when-let* ((buffer (get-file-buffer journal))) (kill-buffer buffer))))))

(provide 'org-workflow-cleanup-test)
