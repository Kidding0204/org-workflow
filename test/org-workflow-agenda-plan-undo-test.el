;;; org-workflow-agenda-plan-undo-test.el --- Planning correction contracts -*- lexical-binding: t; -*-
(require 'org-workflow-agenda)
(load (expand-file-name "org-workflow-store-test.el" (file-name-directory load-file-name)) nil t)
(require 'org-workflow-agenda-plan-undo)

(defmacro workflow-undo-test (&rest body)
  `(org-workflow-store-test
    (let ((org-workflow-agenda-last-plan nil)
          (org-agenda-bulk-marked-entries (list (point-marker))))
      (cl-letf (((symbol-function 'org-agenda-redo) #'ignore)
                ((symbol-function 'org-workflow-agenda--goto-task) #'ignore))
        ,@body))))

(ert-deftest workflow-undo-restores-draft-and-keeps-clock-and-notes ()
  (workflow-undo-test
   (let ((marker (point-marker)))
     (org-workflow-agenda-plan-undo--record
      (lambda () (org-schedule nil "2026-09-17") (org-priority ?A)))
     (let ((id (org-entry-get nil "WORKFLOW_COMMITMENT_ID")))
       (should id)
       (save-excursion (org-end-of-subtree t t)
                       (insert "\nA later note\nCLOCK: [2026-09-16 Wed 10:00]--[2026-09-16 Wed 10:20] => 0:20\n"))
       (goto-char marker)
       (org-workflow-agenda-undo-plan)
       (should-not (org-entry-get nil "SCHEDULED"))
       (should-not (nth 3 (org-heading-components)))
       (should-not (org-entry-get nil "WORKFLOW_COMMITMENT_ID"))
       (should (equal "cancelled" (nth 6 (org-workflow-store-commitment id))))
       (should (string-match-p "A later note" (buffer-string)))
       (should (string-match-p "0:20" (buffer-string)))))))

(ert-deftest workflow-undo-corrects-effective-promise-without-erasing-history ()
  (workflow-undo-test
   (let ((id (org-workflow-store-create "2026-09-16")))
     (org-workflow-agenda-plan-undo--record (lambda () (org-schedule nil "2026-09-17")))
     (should (equal "deferred" (nth 6 (org-workflow-store-commitment id))))
     (org-workflow-agenda-undo-plan)
     (should (equal id (org-entry-get nil "WORKFLOW_COMMITMENT_ID")))
     (should (equal "pending" (nth 6 (org-workflow-store-commitment id))))
     (let ((events (sqlite-select (org-workflow-store--db)
                                 "SELECT kind FROM events WHERE id=? ORDER BY seq" (list id))))
       (should (member '("deferred") events))
       (should (member '("plan-corrected") events))))))

(ert-deftest workflow-undo-rejects-conflicts-and-midnight ()
  (workflow-undo-test
   (org-workflow-agenda-plan-undo--record (lambda () (org-schedule nil "2026-09-17")))
   (cl-letf (((symbol-function 'org-workflow-target--today-string) (lambda () "2026-09-17")))
     (should-error (org-workflow-agenda-undo-plan) :type 'user-error))
   (org-priority ?C)
   (should-error (org-workflow-agenda-undo-plan) :type 'user-error)
   (should (equal "C" (org-entry-get nil "PRIORITY")))))

(ert-deftest workflow-undo-database-failure-rolls-back-and-is-retryable ()
  (workflow-undo-test
   (org-workflow-agenda-plan-undo--record (lambda () (org-schedule nil "2026-09-17")))
   (let ((text (buffer-string)))
     (cl-letf (((symbol-function 'org-workflow-store--event)
                (lambda (&rest _) (error "Injected failure"))))
       (should-error (org-workflow-agenda-undo-plan)))
     (should (equal text (buffer-string)))
     (should org-workflow-agenda-last-plan)
     (org-workflow-agenda-undo-plan)
     (should-not (org-entry-get nil "SCHEDULED")))))

(ert-deftest workflow-undo-batch-restores-both-tasks ()
  (workflow-undo-test
   (let ((first (point-marker)) second)
     (save-excursion
       (goto-char (point-max)) (insert "\n** TODO Second\n")
       (org-back-to-heading t) (setq second (point-marker)))
     (let ((org-agenda-bulk-marked-entries (list first second)))
       (org-workflow-agenda-plan-undo--record
        (lambda ()
          (org-workflow-store--operation
           (lambda ()
             (dolist (marker org-agenda-bulk-marked-entries)
               (org-with-point-at marker
                 (org-schedule nil "2026-09-17") (org-priority ?C)))))))
       (org-workflow-agenda-undo-plan)
       (dolist (marker (list first second))
         (org-with-point-at marker
           (should-not (org-entry-get nil "SCHEDULED"))
           (should-not (nth 3 (org-heading-components)))))))))
