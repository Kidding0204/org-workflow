;;; org-workflow-audit-agenda-test.el --- Public planning boundaries -*- lexical-binding: t; -*-
(require 'ert)
(load "org-workflow-project-classify-test" nil t)
(load "org-workflow-projects-test" nil t)
(load "org-workflow-agenda-plan-undo-test" nil t)

(defmacro workflow-audit-sprint (&rest body)
  "Run BODY through a real Sprint, retaining only fixture buffers afterwards."
  `(let ((prior (buffer-list))
         (org-workflow-agenda--workbench nil)
         (org-agenda-buffer-name (generate-new-buffer-name "*Audit Sprint*"))
         (org-agenda-window-setup 'current-window))
     (unwind-protect
         (save-window-excursion (org-agenda nil "d") ,@body)
       (dolist (buffer (seq-difference (buffer-list) prior))
         (when (buffer-live-p buffer)
           (with-current-buffer buffer (set-buffer-modified-p nil))
           (kill-buffer buffer))))))

(defun workflow-audit-classify-key ()
  "Use the public C command, replacing only its completion prompt."
  (cl-letf (((symbol-function 'completing-read)
             (lambda (_prompt choices &rest _)
               (caar (seq-filter (lambda (c) (string-match-p "Project" (car c))) choices)))))
    (call-interactively (key-binding (kbd "C")))))

(ert-deftest workflow-audit-public-C-rejects-replaced-identity ()
  (workflow-classify-fixture
   (workflow-audit-sprint
    (org-workflow-agenda-select-view 'projects)
    (goto-char (point-min)) (search-forward "First") (beginning-of-line)
    (org-with-point-at one
      ;; Same title: only the rendered ID can distinguish this replacement.
      (org-entry-put nil "ID" "different-task") (save-buffer))
    (should-error (workflow-audit-classify-key) :type 'user-error)
    (should (string-match-p "TODO First" (org-with-point-at one (buffer-string))))
    (should-not (string-match-p "TODO First" (org-with-point-at target (buffer-string)))))))

(ert-deftest workflow-audit-public-C-no-ID-rejects-stale-title ()
  (workflow-classify-fixture
   (org-with-point-at one (org-entry-delete nil "ID") (save-buffer))
   (workflow-audit-sprint
    (org-workflow-agenda-select-view 'projects)
    (goto-char (point-min)) (search-forward "First") (beginning-of-line)
    (should-not (org-with-point-at one (org-entry-get nil "ID")))
    (org-with-point-at one (org-edit-headline "Replacement") (save-buffer))
    (should-error (workflow-audit-classify-key) :type 'user-error)
    (should-not (string-match-p "TODO Replacement" (org-with-point-at target (buffer-string)))))))

(ert-deftest workflow-audit-public-C-keeps-later-body-and-clock ()
  (workflow-classify-fixture
   (org-with-point-at one (org-entry-delete nil "ID") (save-buffer))
   (workflow-audit-sprint
    (org-workflow-agenda-select-view 'projects)
    (goto-char (point-min)) (search-forward "First") (beginning-of-line)
    (org-with-point-at one
      (org-end-of-subtree t t) (insert "Later body\n") (save-buffer))
    (workflow-audit-classify-key)
    (org-with-point-at target
      (should (string-match-p "Later body" (buffer-string)))
      (should (string-match-p "CLOCK:.*2026-09-15" (buffer-string)))))))

(ert-deftest workflow-audit-public-C-rejects-whole-stale-batch ()
  (workflow-classify-fixture
   (workflow-audit-sprint
    (org-workflow-agenda-select-view 'projects)
    (goto-char (point-min)) (search-forward "First") (beginning-of-line)
    (org-agenda-bulk-mark 1)
    (goto-char (point-min)) (search-forward "Second") (beginning-of-line)
    (org-agenda-bulk-mark 1)
    ;; Deleting First moves its old row marker onto the surviving Second.
    (org-with-point-at one
      (delete-region (point) (save-excursion (org-end-of-subtree t t))) (save-buffer))
    (should-error (workflow-audit-classify-key) :type 'user-error)
    (should (string-match-p "TODO Second" (org-with-point-at two (buffer-string))))
    (should-not (string-match-p "TODO Second" (org-with-point-at target (buffer-string)))))))

(ert-deftest workflow-audit-public-mouse-replacement-U-restores-domain ()
  (workflow-project-fixture
   (workflow-project-at "Parser")
   (org-add-planning-info 'scheduled (org-time-string-to-time "2026-09-16"))
   (org-workflow-projects-sync)
   (let* ((tokens (workflow-project-at "Tokens"))
          (old-id (org-entry-get nil "WORKFLOW_COMMITMENT_ID"))
          (key "project-day:2026-09-16:compiler"))
     (org-entry-put nil "WORKFLOW_COMMITTED_AT" "legacy-time")
     (org-entry-put nil "WORKFLOW_COMMITTED_FOR" "2026-09-16")
     (org-workflow-store-put-day "2026-09-15" '(:date "2026-09-15" :commitment "unmet"))
     (workflow-audit-sprint
      (goto-char (point-min)) (search-forward "Parser") (beginning-of-line)
      (org-workflow-agenda-mouse--select (org-get-at-bol 'org-hd-marker) nil)
      (org-workflow-agenda-mouse-toggle-commitment)
      (let* ((new-id (org-workflow-store-meta key))
             (events-before (sqlite-select (org-workflow-store--db) "SELECT * FROM events ORDER BY seq")))
        (should-not (equal old-id new-id))
        (org-with-point-at tokens
          (org-end-of-subtree t t) (backward-char)
          (insert "\nLater task body\nCLOCK: [2026-09-16 Wed 10:00]--[2026-09-16 Wed 10:20] => 0:20\n"))
        (call-interactively (key-binding (kbd "U")))
        (should (equal old-id (org-workflow-store-meta key)))
        (org-with-point-at tokens
          (should (equal old-id (org-entry-get nil "WORKFLOW_COMMITMENT_ID")))
          (should (equal "legacy-time" (org-entry-get nil "WORKFLOW_COMMITTED_AT")))
          (should (equal "2026-09-16" (org-entry-get nil "WORKFLOW_COMMITTED_FOR")))
          (should (string-match-p "Later task body" (buffer-string)))
          (should (string-match-p "CLOCK:.*0:20" (buffer-string))))
        (should (equal "cancelled" (nth 6 (org-workflow-store-commitment new-id))))
        (should (equal (list old-id) (mapcar #'car (org-workflow-history--responsibilities "2026-09-16"))))
        (should-not (org-workflow-projects-superseded-p (org-workflow-store-commitment old-id) "2026-09-16"))
        (should (equal '(:date "2026-09-15" :commitment "unmet") (org-workflow-store-day "2026-09-15")))
        (should (seq-every-p (lambda (event)
                              (member event (sqlite-select (org-workflow-store--db) "SELECT * FROM events ORDER BY seq")))
                            events-before))
        (should-error (org-workflow-agenda-undo-last-operation) :type 'user-error))))))

(ert-deftest workflow-audit-undo-rejects-later-indirect-attachment-change ()
  (workflow-project-fixture
   (workflow-project-at "Parser")
   (org-add-planning-info 'scheduled (org-time-string-to-time "2026-09-16"))
   (org-workflow-projects-sync)
   (let* ((tokens (workflow-project-at "Tokens"))
          (parser (workflow-project-at "Parser"))
          (org-agenda-bulk-marked-entries (list parser)))
     (cl-letf (((symbol-function 'org-agenda-redo) #'ignore))
       (org-workflow-agenda-plan-undo--record #'org-workflow-toggle-commitment)
       (org-with-point-at tokens (org-entry-put nil "WORKFLOW_COMMITTED_FOR" "later-change"))
       (should-error (org-workflow-agenda-undo-plan) :type 'user-error)))))

(ert-deftest workflow-audit-undo-rejects-later-project-day-change ()
  (workflow-project-fixture
   (workflow-project-at "Parser")
   (org-add-planning-info 'scheduled (org-time-string-to-time "2026-09-16"))
   (org-workflow-projects-sync)
   (let ((org-agenda-bulk-marked-entries (list (workflow-project-at "Parser"))))
     (cl-letf (((symbol-function 'org-agenda-redo) #'ignore))
       (org-workflow-agenda-plan-undo--record #'org-workflow-toggle-commitment)
       (org-workflow-store-set-meta "project-day:2026-09-16:compiler" "later-change")
       (should-error (org-workflow-agenda-undo-plan) :type 'user-error)))))

(ert-deftest workflow-audit-undo-completed-replacement-restores-responsibility ()
  (workflow-project-fixture
   (workflow-project-at "Parser")
   (org-add-planning-info 'scheduled (org-time-string-to-time "2026-09-16"))
   (org-workflow-projects-sync)
   (workflow-project-at "Tokens") (org-todo "DONE")
   (let ((old-id (org-entry-get nil "WORKFLOW_COMMITMENT_ID"))
         (org-agenda-bulk-marked-entries (list (workflow-project-at "Parser"))))
     (cl-letf (((symbol-function 'org-agenda-redo) #'ignore))
       (org-workflow-agenda-plan-undo--record #'org-workflow-toggle-commitment)
       (org-workflow-agenda-undo-plan)
       (should (equal "done" (nth 6 (org-workflow-store-commitment old-id))))
       (should (equal (list old-id) (mapcar #'car (org-workflow-history--responsibilities "2026-09-16"))))
       (should (= 1 (plist-get (org-workflow-history-progress "2026-09-16") :minimumSatisfied)))))))

(ert-deftest workflow-audit-public-mouse-batch-U-restores-one-duty ()
  (workflow-project-fixture
   (workflow-project-at "Parser")
   (org-add-planning-info 'scheduled (org-time-string-to-time "2026-09-16"))
   (org-workflow-projects-sync)
   (let* ((tokens (workflow-project-at "Tokens"))
          (old-id (org-entry-get nil "WORKFLOW_COMMITMENT_ID"))
          (parser (workflow-project-at "Parser")))
     (workflow-audit-sprint
      (goto-char (point-min)) (search-forward "Tokens") (beginning-of-line)
      (org-workflow-agenda-mouse--select (org-get-at-bol 'org-hd-marker) nil)
      (goto-char (point-min)) (search-forward "Parser") (beginning-of-line)
      (org-workflow-agenda-mouse--select (org-get-at-bol 'org-hd-marker) 'control)
      (should (= 2 (length org-agenda-bulk-marked-entries)))
      (org-workflow-agenda-mouse-toggle-commitment)
      (call-interactively (key-binding (kbd "U")))
      (should (equal old-id (org-with-point-at tokens (org-entry-get nil "WORKFLOW_COMMITMENT_ID"))))
      (should-not (org-with-point-at parser (org-entry-get nil "WORKFLOW_COMMITMENT_ID")))
      (should (equal (list old-id) (mapcar #'car (org-workflow-history--responsibilities "2026-09-16"))))))))

(ert-deftest workflow-audit-undo-preserves-unrelated-later-planning-edit ()
  (workflow-project-fixture
   (workflow-project-at "Parser")
   (org-add-planning-info 'scheduled (org-time-string-to-time "2026-09-16"))
   (org-workflow-projects-sync)
   (let* ((unrelated (workflow-project-at "Matrices"))
          (other-id (org-workflow-store-create "2026-09-17"))
          (org-agenda-bulk-marked-entries (list (workflow-project-at "Parser"))))
     (cl-letf (((symbol-function 'org-agenda-redo) #'ignore))
       (org-workflow-agenda-plan-undo--record #'org-workflow-toggle-commitment)
       (org-with-point-at unrelated (org-priority ?C))
       (org-workflow-store-set-meta "project-day:2026-09-16:unrelated" other-id)
       (org-workflow-agenda-undo-plan)
       (org-with-point-at unrelated
         (should (equal "C" (org-entry-get nil "PRIORITY")))
         (should (equal other-id (org-entry-get nil "WORKFLOW_COMMITMENT_ID"))))
       (should (equal other-id (org-workflow-store-meta "project-day:2026-09-16:unrelated")))))))

(ert-deftest workflow-audit-undo-rejects-later-event-on-replaced-duty ()
  (workflow-project-fixture
   (workflow-project-at "Parser")
   (org-add-planning-info 'scheduled (org-time-string-to-time "2026-09-16"))
   (org-workflow-projects-sync)
   (let ((old-id (org-with-point-at (workflow-project-at "Tokens") (org-entry-get nil "WORKFLOW_COMMITMENT_ID")))
         (org-agenda-bulk-marked-entries (list (workflow-project-at "Parser"))))
     (cl-letf (((symbol-function 'org-agenda-redo) #'ignore))
       (org-workflow-agenda-plan-undo--record #'org-workflow-toggle-commitment)
       (org-workflow-store--event old-id "later-external-fact")
       (should-error (org-workflow-agenda-undo-plan) :type 'user-error)))))

(ert-deftest workflow-audit-U-does-not-consume-another-workbench-record ()
  (workflow-undo-test
   (let ((org-workflow-agenda--workbench
          (org-workflow-agenda-workbench-create :settings (make-hash-table :test #'eq))))
     (org-workflow-agenda-plan-undo--record (lambda () (org-schedule nil "2026-09-17")))
     (let ((org-workflow-agenda--workbench
            (org-workflow-agenda-workbench-create :settings (make-hash-table :test #'eq))))
       (should-error (org-workflow-agenda-undo-last-operation) :type 'user-error))
     (org-workflow-agenda-undo-last-operation)
     (should-not (org-entry-get nil "SCHEDULED")))))

(ert-deftest workflow-audit-undo-preserves-earlier-supersession ()
  (workflow-undo-test
   (let ((id (org-workflow-store-create "2026-09-16")))
     (org-workflow-store--event id "project-superseded" '(:date "2026-09-16" :project "earlier-project"))
     (org-workflow-agenda-plan-undo--record (lambda () (org-schedule nil "2026-09-17")))
     (org-workflow-agenda-undo-plan)
     (should (org-workflow-projects-superseded-p (org-workflow-store-commitment id) "2026-09-16"))
     (should-not (org-workflow-projects-superseded-p (org-workflow-store-commitment id) "2026-09-15")))))

(ert-deftest workflow-audit-existing-duty-under-DONE-stage-is-withdrawn ()
  (workflow-project-fixture
   (org-workflow-projects-sync)
   (let ((id (org-with-point-at (workflow-project-at "Tokens") (org-entry-get nil "WORKFLOW_COMMITMENT_ID"))))
     (org-workflow-projects-set-state (workflow-project-at "Lexing") "DONE")
     (should (equal "withdrawn" (nth 6 (org-workflow-store-commitment id))))
     (should-not (org-workflow-history--responsibilities "2026-09-16"))
     (org-workflow-projects-set-state (workflow-project-at "Lexing") "DIVE")
     (should (equal "pending" (nth 6 (org-workflow-store-commitment id)))))))

(ert-deftest workflow-audit-completed-duty-under-DONE-stage-stays-historical ()
  (workflow-project-fixture
   (org-workflow-projects-sync)
   (workflow-project-at "Tokens") (org-todo "DONE")
   (let ((id (org-entry-get nil "WORKFLOW_COMMITMENT_ID")))
     (org-workflow-projects-set-state (workflow-project-at "Lexing") "DONE")
     (should (equal "done" (nth 6 (org-workflow-store-commitment id))))
     (should (= 1 (plist-get (org-workflow-history-progress "2026-09-16") :minimumSatisfied))))))

(provide 'org-workflow-audit-agenda-test)
