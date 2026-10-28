;;; -*- lexical-binding: t; -*-
(require 'ert)
(require 'org-workflow-agenda)
(require 'org-workflow-agenda-projects)
(load "org-workflow-store-test" nil t)
(require 'org-workflow-project-classify nil t)

(defmacro workflow-classify-fixture (&rest body)
  `(org-workflow-store-test
    (let* ((org-workflow-projects-file file)
           (target-file (expand-file-name "area.org" directory))
           (org-id-locations nil) (org-id-track-globally nil)
           (org-workflow-agenda--workbench (org-workflow-agenda-workbench-create :settings (make-hash-table :test #'eq))))
      (with-temp-file file (insert "* Inbox\n** TODO First :QA:topic:\nSCHEDULED: <2026-09-18 Fri>\n:PROPERTIES:\n:ID: item-one\n:CAPTURED_ON: [2026-09-16 Wed 10:00]\n:END:\nBody [[id:reference]]\n:LOGBOOK:\nCLOCK: [2026-09-15 Tue 10:00]--[2026-09-15 Tue 10:20] => 0:20\n:END:\n*** Notes\nDetail\n** TODO Second\n:PROPERTIES:\n:ID: item-two\n:END:\n"))
      (with-current-buffer (get-file-buffer file) (revert-buffer t t))
      (with-temp-file target-file (insert "* HOLD Project\n:PROPERTIES:\n:ID: project\n:END:\n** Group\n*** TODO Existing\n"))
      (let ((org-agenda-files (list file target-file)))
        (unwind-protect
            (let ((source (with-current-buffer (find-file-noselect file)
                            (goto-char (point-min)) (re-search-forward "^\\*\\* TODO First")
                            (line-beginning-position)))
                  (target (with-current-buffer (find-file-noselect target-file)
                            (goto-char (point-min)) (point-marker))))
              (let ((one (with-current-buffer (find-file-noselect file) (copy-marker source)))
                    (two (with-current-buffer (find-file-noselect file)
                           (goto-char (point-min)) (re-search-forward "^\\*\\* TODO Second")
                           (copy-marker (line-beginning-position)))))
                ,@body))
          (when-let* ((b (get-file-buffer target-file)))
            (with-current-buffer b (set-buffer-modified-p nil)) (kill-buffer b)))))))

(ert-deftest workflow-classify-project-creates-or-reuses-only-direct-ungrouped ()
  (workflow-classify-fixture
   (org-workflow-project-classify (list one) (list :kind 'project :marker target))
   (org-workflow-project-classify (list two) (list :kind 'project :marker target))
   (with-current-buffer (marker-buffer target)
     (should (= 1 (how-many "^\\*\\* 未分组" (point-min) (point-max))))
     (should (string-match-p "\\*\\*\\* TODO First[ \t]+:QA:topic:" (buffer-string)))
     (should (string-match-p "\\*\\*\\*\\* Notes" (buffer-string)))
     (should (string-match-p "CLOCK:.*2026-09-15" (buffer-string)))
     (should (string-match-p "^\\* HOLD Project" (buffer-string))))))

(ert-deftest workflow-classify-batch-preserves-subtrees-and-source-order ()
  (workflow-classify-fixture
   (let ((record (org-workflow-project-classify (list one two) (list :kind 'project :marker target))))
     (should (eq (plist-get record :save-state) 'saved))
     (with-current-buffer (marker-buffer one) (should-not (string-match-p "TODO" (buffer-string))))
     (with-current-buffer (marker-buffer target)
       (should (< (string-match "First" (buffer-string)) (string-match "Second" (buffer-string))))
       (should (string-match-p "CAPTURED_ON:.*2026-09-16" (buffer-string)))
       (should (string-match-p "SCHEDULED: <2026-09-18 Fri>" (buffer-string)))))))

(ert-deftest workflow-classify-preflight-rejects-entire-invalid-batch ()
  (workflow-classify-fixture
   (with-current-buffer (marker-buffer target) (goto-char (point-max)) (insert "dirty\n"))
   (let ((text (with-current-buffer (marker-buffer one) (buffer-string))))
     (should-error (org-workflow-project-classify (list one two) (list :kind 'project :marker target)) :type 'user-error)
     (should (equal text (with-current-buffer (marker-buffer one) (buffer-string)))))))

(ert-deftest workflow-classify-failure-rolls-back-batch ()
  (workflow-classify-fixture
   (let ((before (with-current-buffer (marker-buffer one) (buffer-string)))
         (target-before (with-current-buffer (marker-buffer target) (buffer-string)))
         (original (symbol-function 'org-refile)) (calls 0))
     (cl-letf (((symbol-function 'org-refile)
                (lambda (&rest args) (if (= (cl-incf calls) 2) (error "second move failed") (apply original args)))))
       (should-error (org-workflow-project-classify (list one two) (list :kind 'project :marker target))))
     (should (equal before (with-current-buffer (marker-buffer one) (buffer-string))))
     (should (equal target-before (with-current-buffer (marker-buffer target) (buffer-string)))))))

(ert-deftest workflow-classify-save-failure-keeps-recovery ()
  (workflow-classify-fixture
   (let ((record (cl-letf (((symbol-function 'save-buffer) (lambda (&rest _) (error "disk full"))))
                   (org-workflow-project-classify (list one two) (list :kind 'project :marker target)))))
     (should (eq (plist-get record :save-state) 'pending))
     (should (eq record (org-workflow-agenda--setting 'org-workflow-agenda-last-operation)))
     (should (sqlite-select (org-workflow-store--db) "SELECT id FROM operations WHERE state='applied'"))
     (should-error (org-workflow-project-classify (list one) (list :kind 'project :marker target))))))

(ert-deftest workflow-classify-existing-heading-keeps-state-and-identity-location ()
  (workflow-classify-fixture
   (let ((group (org-with-point-at target (search-forward "** Group") (line-beginning-position))))
     (org-workflow-project-classify (list one) (list :kind 'heading :marker (with-current-buffer (marker-buffer target) (copy-marker group)))))
   (with-current-buffer (marker-buffer target)
     (should-not (string-match-p "未分组" (buffer-string)))
     (should (string-match-p "HOLD Project" (buffer-string))))
   (when (hash-table-p org-id-locations)
     (should (equal target-file (gethash "item-one" org-id-locations))))))

(ert-deftest workflow-classify-rejects-done-target-clock-and-duplicate-group ()
  (workflow-classify-fixture
   (org-with-point-at target (let (org-log-done) (org-todo "DONE")) (save-buffer))
   (should-error (org-workflow-project-classify (list one) (list :kind 'project :marker target)) :type 'user-error)))

(ert-deftest workflow-classify-checkpoint-failure-still-registers-pending ()
  (workflow-classify-fixture
   (let ((record (cl-letf (((symbol-function 'org-workflow-store-checkpoint)
                            (lambda () (error "checkpoint failed"))))
                   (org-workflow-project-classify (list one) (list :kind 'project :marker target)))))
     (should (eq (plist-get record :save-state) 'pending))
     (should (eq record (org-workflow-agenda--setting 'org-workflow-agenda-last-operation)))
     (should (string-match-p "checkpoint" (plist-get record :error))))))

(ert-deftest workflow-classify-undo-restores-order-and-created-heading ()
  (workflow-classify-fixture
   (let* ((before (org-workflow-project-classify--snapshot (list file target-file)))
          (record (org-workflow-project-classify (list one two) (list :kind 'project :marker target))))
     (org-workflow-project-classify-undo record)
     (should (equal before (org-workflow-project-classify--snapshot (list file target-file)))))))

(ert-deftest workflow-classify-undo-rejects-post-edit-or-date-change ()
  (workflow-classify-fixture
   (let ((record (org-workflow-project-classify (list one) (list :kind 'project :marker target))))
     (with-current-buffer (marker-buffer target) (goto-char (point-max)) (insert "later note\n"))
     (should-error (org-workflow-project-classify-undo record) :type 'user-error)
     (should (with-current-buffer (marker-buffer target) (string-match-p "later note" (buffer-string)))))))

(ert-deftest workflow-sprint-undo-dispatches-only-most-recent-success ()
  (workflow-classify-fixture
   (org-workflow-project-classify (list one two) (list :kind 'project :marker target))
   (org-workflow-agenda-undo-last-operation)
   (should-not (org-workflow-agenda--setting 'org-workflow-agenda-last-operation))
   (should (with-current-buffer (marker-buffer one) (string-match-p "TODO First" (buffer-string))))))

(ert-deftest workflow-project-mutations-invalidate-older-undo ()
  (workflow-classify-fixture
   (org-workflow-project-classify (list one) (list :kind 'project :marker target))
   (org-workflow-agenda-project-state target "TODO")
   (should-not (org-workflow-agenda--setting 'org-workflow-agenda-last-operation))
   (should-error (org-workflow-agenda-undo-last-operation) :type 'user-error)))

(ert-deftest workflow-classify-undo-pending-save-and-reverse-save-failure ()
  (workflow-classify-fixture
   (let* ((before (org-workflow-project-classify--snapshot (list file target-file)))
          (record (cl-letf (((symbol-function 'save-buffer) (lambda (&rest _) (error "disk full"))))
                    (org-workflow-project-classify (list one two) (list :kind 'project :marker target)))))
     (cl-letf (((symbol-function 'save-buffer) (lambda (&rest _) (error "still full"))))
       (org-workflow-project-classify-undo record))
     (should (equal before (org-workflow-project-classify--snapshot (list file target-file))))
     (let ((pending (org-workflow-agenda--setting 'org-workflow-agenda-last-operation)))
       (should (plist-get pending :undoing))
       (org-workflow-project-classify-undo pending))
     (should-not (org-workflow-agenda--setting 'org-workflow-agenda-last-operation)))))

(ert-deftest workflow-classify-preflight-active-clock-and-duplicate-heading ()
  (workflow-classify-fixture
   (let ((org-clock-marker (copy-marker one)))
     (should-error (org-workflow-project-classify (list one) (list :kind 'project :marker target)) :type 'user-error))
   (org-with-point-at target (goto-char (point-max)) (insert "** 未分组\n** 未分组\n") (save-buffer))
   (should-error (org-workflow-project-classify (list one) (list :kind 'project :marker target)) :type 'user-error)))

(ert-deftest workflow-classify-undo-preserves-unmoved-marker ()
  (workflow-classify-fixture
   (let* ((existing (org-with-point-at target (search-forward "*** TODO Existing")
                                     (copy-marker (line-beginning-position))))
          (record (org-workflow-project-classify (list one) (list :kind 'project :marker target))))
     (org-workflow-project-classify-undo record)
     (should (equal "Existing" (org-with-point-at existing (org-get-heading t t t t)))))))
