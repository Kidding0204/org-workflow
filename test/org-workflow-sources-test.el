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

(ert-deftest workflow-source-inbox-does-not-query-journal-indexes ()
  (workflow-source-test
   (with-temp-file org-workflow-projects-file (insert "* Inbox\n"))
   (cl-letf (((symbol-function 'vulpea-db-query-by-tags-every)
              (lambda (&rest _) (ert-fail "Inbox queried journal indexes"))))
     (should (equal (list org-workflow-projects-file)
                    (org-workflow-collection-inbox--review-files)))
     (should-not (get-file-buffer org-workflow-projects-file)))))

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

(ert-deftest workflow-source-stage-progress-bypasses-broken-live-cache ()
  (workflow-source-test
   (with-temp-file org-workflow-projects-file
     (insert "#+filetags: :project:\n* Stage\n** TODO [#A] Task\nSCHEDULED: <2026-10-06 Tue>\n"))
   (let ((org-agenda-files (list org-workflow-projects-file))
         (org-element-use-cache t)
         (cache-map (symbol-function 'org-element-cache-map)))
     (with-current-buffer (find-file-noselect org-workflow-projects-file)
       (goto-char (point-min)) (search-forward "TODO") (replace-match "DONE")
       (forward-line 1) (insert "CLOSED: [2026-10-06 Tue 10:00] ")
       (org-back-to-heading t) (org-narrow-to-subtree)
       (let ((position (point)) (start (point-min)) (end (point-max))
             (text (buffer-string)))
         (cl-letf (((symbol-function 'org-element-cache-map)
                    (lambda (&rest args)
                      (when org-element-use-cache (error "Broken live Org cache"))
                      (apply cache-map args))))
           (should (equal '(:stageSatisfied 1 :stageTotal 1)
                          (org-workflow--stage-progress
                           "2026-10-06" (encode-time 0 0 10 6 10 2026)))))
         (should (= position (point)))
         (should (= start (point-min)))
         (should (= end (point-max)))
         (should (equal text (buffer-string)))
         (should (buffer-modified-p)))))))

(ert-deftest workflow-source-stage-progress-does-not-visit-closed-files ()
  (workflow-source-test
   (with-temp-file org-workflow-projects-file
     (insert "#+filetags: :project:\n* Stage\n** TODO [#A] Pending\nSCHEDULED: <2026-10-06 Tue>\n"))
   (let ((org-agenda-files (list org-workflow-projects-file))
         (org-mode-hook (list (lambda () (ert-fail "Background UI hook")))))
     (should (equal '(:stageSatisfied 0 :stageTotal 1)
                    (org-workflow--stage-progress
                     "2026-10-06" (encode-time 0 0 10 6 10 2026))))
     (should-not (get-file-buffer org-workflow-projects-file)))))

(ert-deftest workflow-source-history-tasks-bypasses-broken-live-cache ()
  (workflow-source-test
   (with-temp-file org-workflow-projects-file
     (insert "#+filetags: :project:\n#+TODO: TODO DIVE | DONE HOLD\n* DIVE Stage\n** TODO Disk task\n:PROPERTIES:\n:ID: history-source-task\n:END:\n:LOGBOOK:\nCLOCK: [2026-10-06 Tue 09:00]--[2026-10-06 Tue 09:25] => 0:25\n:END:\n** TODO Habit\nSCHEDULED: <2026-10-07 Wed .+1d>\n:PROPERTIES:\n:STYLE: habit\n:ID: history-source-habit\n:END:\n:LOGBOOK:\nCLOCK: [2026-10-06 Tue 10:00]--[2026-10-06 Tue 10:10] => 0:10\n:END:\n"))
   (let ((org-agenda-files (list org-workflow-projects-file))
         (org-element-use-cache t)
         (cache-map (symbol-function 'org-element-cache-map))
         (calls 0))
     (with-current-buffer (find-file-noselect org-workflow-projects-file)
       (goto-char (point-min)) (search-forward "Disk task") (replace-match "Live task")
       (org-back-to-heading t) (org-element-at-point) (org-narrow-to-subtree)
       (let ((position (point)) (start (point-min)) (end (point-max)) (text (buffer-string)))
         (cl-letf (((symbol-function 'org-element-cache-map)
                    (lambda (&rest args)
                      (if org-element-use-cache
                          (progn (cl-incf calls)
                                 (error "Invalid search bound (wrong side of point)"))
                        (apply cache-map args)))))
           (let ((rows (org-workflow-history--tasks "2026-10-06")))
             (should (= 0 calls))
             (should (= 1 (length rows)))
             (should (equal "Live task" (plist-get (car rows) :task)))
             (should (= 25 (plist-get (car rows) :focusMinutes)))))
         (should (= position (point)))
         (should (= start (point-min)))
         (should (= end (point-max)))
         (should (equal text (buffer-string)))
         (should (buffer-modified-p)))))))

(ert-deftest workflow-source-history-tasks-does-not-visit-closed-files ()
  (workflow-source-test
   (with-temp-file org-workflow-projects-file
     (insert "#+filetags: :project:\n#+TODO: TODO | DONE\n* DONE Finished\nCLOSED: [2026-10-06 Tue 12:00]\n:PROPERTIES:\n:ID: closed-history-task\n:END:\n"))
   (let ((org-agenda-files (list org-workflow-projects-file))
         (org-mode-hook (list (lambda () (ert-fail "Background UI hook")))))
     (should (equal "Finished" (plist-get (car (org-workflow-history--tasks "2026-10-06")) :task)))
     (should-not (get-file-buffer org-workflow-projects-file)))))

(ert-deftest workflow-source-history-skips-headings-without-direct-facts ()
  (workflow-source-test
   (with-temp-file org-workflow-projects-file
     (insert "#+filetags: :project:\n#+TODO: TODO | DONE\n* Notes\nNo work here.\n* DIVE Parent\n** TODO Clocked\n:LOGBOOK:\nCLOCK: [2026-10-06 Tue 23:50]--[2026-10-07 Wed 00:10] => 0:20\n:END:\n** DONE Finished\nCLOSED: [2026-10-07 Wed 12:00]\n** DONE Other day\nCLOSED: [2026-10-06 Tue 12:00]\n"))
   (let ((org-agenda-files (list org-workflow-projects-file))
         (reader (symbol-function 'org-workflow-item-at-marker)) built)
     (cl-letf (((symbol-function 'org-workflow-item-at-marker)
                (lambda (marker &optional date)
                  (let ((item (funcall reader marker date)))
                    (push (org-workflow-target-entry-title item) built)
                    item))))
       (let ((rows (org-workflow-history--tasks "2026-10-07")))
         (should (equal '("Finished" "Clocked") built))
         (should (= 2 (length rows)))
         (should (= 10 (plist-get (seq-find (lambda (row) (equal "Clocked" (plist-get row :task))) rows)
                                 :focusMinutes)))
         (should (equal "done" (plist-get (seq-find (lambda (row) (equal "Finished" (plist-get row :task))) rows)
                                          :outcome))))))))
