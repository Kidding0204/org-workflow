;;; org-workflow-sources-test.el --- Bounded source lifecycle -*- lexical-binding: t; -*-
(require 'ert)
(require 'org-workflow)
(require 'org-workflow-guidance)
(require 'org-workflow-sources)

(defmacro workflow-source-test (&rest body)
  `(let* ((directory (make-temp-file "workflow-sources-" t))
          (org-workflow-directory directory)
          (org-workflow-projects-file (expand-file-name "projects.org" directory))
          (org-workflow-habit-file nil) (org-workflow-guidance-file nil)
          (org-workflow-store-enabled nil) (org-agenda-files nil))
     (unwind-protect (progn ,@body)
       (dolist (buffer (buffer-list))
         (when (and (buffer-file-name buffer) (string-prefix-p directory (buffer-file-name buffer)))
           (with-current-buffer buffer (set-buffer-modified-p nil)) (kill-buffer buffer)))
       (delete-directory directory t))))

(ert-deftest workflow-source-read-no-visit-no-ui-hooks ()
  (workflow-source-test
   (with-temp-file org-workflow-projects-file (insert "* TODO Item\n"))
   (let ((org-mode-hook (list (lambda () (ert-fail "Background UI hook"))))
         (kill-buffer-query-functions (list (lambda () (ert-fail "Background close query")))))
     (should (equal "Item" (org-workflow-source-read org-workflow-projects-file
                            (lambda () (should-not org-element-use-cache)
                              (should-not (buffer-modified-p))
                              (org-get-heading t t t t))))))
   (should-not (get-file-buffer org-workflow-projects-file))))

(ert-deftest workflow-source-read-preserves-unsaved-text-and-view ()
  (workflow-source-test
   (with-temp-file org-workflow-projects-file (insert "* TODO Disk\n* Other\n"))
   (with-current-buffer (find-file-noselect org-workflow-projects-file)
     (goto-char (point-min)) (search-forward "Disk") (replace-match "Live")
     (org-narrow-to-subtree)
     (let ((position (point)) (limit (point-max)))
       (should (equal "Live" (org-workflow-source-read org-workflow-projects-file
                               (lambda () (org-get-heading t t t t)))))
       (should (= position (point))) (should (= limit (point-max)))
       (should (buffer-modified-p))))))

(ert-deftest workflow-source-scheduled-scout-keeps-files-closed ()
  (workflow-source-test
   (with-temp-file org-workflow-projects-file
     (insert "* Inbox\n:PROPERTIES:\n:JOURNAL_INBOX: 2026-09-28\n:END:\n** TODO Work\nSCHEDULED: <2026-10-08>\n"))
   (cl-letf (((symbol-function 'org-workflow-collection-inbox--review-files)
              (lambda () (list org-workflow-projects-file))))
     (should (equal (list org-workflow-projects-file) (org-workflow-collection-inbox--scheduled-files))))
   (should-not (get-file-buffer org-workflow-projects-file))))

(ert-deftest workflow-source-pending-only-hydrates-live-matches ()
  (workflow-source-test
   (let ((empty (expand-file-name "empty.org" directory)))
     (with-temp-file empty (insert "* Inbox\n:PROPERTIES:\n:JOURNAL_INBOX: 2026-09-21\n:END:\n** DONE Done\n** TODO Scheduled\nSCHEDULED: <2026-10-08>\n"))
     (with-temp-file org-workflow-projects-file (insert "* Inbox\n:PROPERTIES:\n:JOURNAL_INBOX: 2026-09-28\n:END:\n** TODO Work\n"))
     (let ((rows (org-workflow-collection-inbox--pending (list empty org-workflow-projects-file) t t)))
       (should (= 1 (length rows))) (should (equal "TODO Work" (cadar rows)))
       (should (buffer-live-p (marker-buffer (nth 2 (car rows)))))
       (should (equal org-workflow-projects-file (buffer-file-name (marker-buffer (nth 2 (car rows)))))))
     (should-not (get-file-buffer empty)))))

(ert-deftest workflow-source-sealed-note-excluded-before-reading ()
  (workflow-source-test
   (let ((closed (make-vulpea-note :path "/absent/closed.org" :tags '("journal-week" "workflow-closed")))
         (active (make-vulpea-note :path "/absent/active.org" :tags '("journal-week"))))
     (cl-letf (((symbol-function 'vulpea-db-query-by-tags-every)
                (lambda (tags) (and (equal tags '("journal-week")) (list closed active)))))
       (should (equal '("/absent/active.org") (org-workflow-collection-inbox--review-files)))))))

(ert-deftest workflow-source-seal-rejects-pending-and-current-weeks ()
  (workflow-source-test
   (let ((file (org-workflow-week-file "2026-09-21")))
     (make-directory (file-name-directory file) t)
     (with-temp-file file (insert "* Inbox\n:PROPERTIES:\n:JOURNAL_INBOX: 2026-09-21\n:END:\n** TODO Pending\n"))
     (should-error (org-workflow-week-close file) :type 'user-error)
     (should-not (get-file-buffer file))
     (should-error (org-workflow-week-close (org-workflow-week-file)) :type 'user-error))))

(ert-deftest workflow-source-seal-retains-completion-and-updates-index ()
  (workflow-source-test
   (let ((file (org-workflow-week-file "2026-09-21")) indexed)
     (make-directory (file-name-directory file) t)
     (with-temp-file file (insert "#+filetags: :area:journal-week:\n* Inbox\n:PROPERTIES:\n:JOURNAL_INBOX: 2026-09-21\n:END:\n** DONE Done\nCLOSED: [2026-09-22 Tue 10:00]\n"))
     (cl-letf (((symbol-function 'vulpea-db-update-file) (lambda (path) (setq indexed path)))
               ((symbol-function 'org-workflow-target-refresh) #'ignore))
       (org-workflow-week-close file))
     (should (equal file indexed))
     (with-current-buffer (get-file-buffer file)
       (should (member "workflow-closed" org-file-tags))
       (should (string-match-p "CLOSED: \\[2026-09-22 Tue 10:00\\]" (buffer-string)))
       (should-not (buffer-modified-p))))))

(ert-deftest workflow-source-guidance-text-read-keeps-file-closed ()
  (workflow-source-test
   (with-temp-file org-workflow-projects-file
     (insert "* Someday\n** TODO Task\n* 实践指导 :workflow_guidance:\n** Keep trying\n:PROPERTIES:\n:WORKFLOW_GUIDANCE_SELECTED: t\n:END:\n"))
   (should (equal "Keep trying" (org-workflow-guidance-current)))
   (should-not (get-file-buffer org-workflow-projects-file))))

(ert-deftest workflow-source-misc-commands-address-their-own-subtrees ()
  (workflow-source-test
   (save-window-excursion
     (org-workflow-habits-create "Exercise")
     (should (= 2 (org-outline-level)))
     (should (equal "habit" (org-entry-get nil "STYLE")))
     (should (buffer-narrowed-p))
     (org-workflow-guidance-open)
     (should (equal "实践指导" (org-get-heading t t t t)))
     (should (buffer-narrowed-p))
     (widen) (goto-char (point-min))
     (should (re-search-forward "^\\* Someday$" nil t))
     (should (re-search-forward "^\\*\\* TODO Exercise$" nil t)))))

(provide 'org-workflow-sources-test)
