;;; org-workflow-dive-test.el --- Direct active scope tests -*- lexical-binding: t; -*-
(require 'ert)
(require 'org-workflow-agenda)
(require 'org-workflow-core)
(require 'org-workflow-migrate)

(defmacro org-workflow-dive-test--with-files (contents &rest body)
  (declare (indent 1))
  `(let* ((directory (make-temp-file "workflow-dive-" t))
          (user-emacs-directory (file-name-as-directory directory))
          (org-agenda-files nil)
          (org-workflow-store-enabled nil)
          (org-workflow-agenda-planning-all nil)
          (org-workflow-target-selected-marker nil)
          (org-workflow-target-selected-date nil)
          (org-after-todo-state-change-hook nil)
          (org-after-todo-statistics-hook nil)
          (org-mode-hook nil)
          (org-workflow-curr-lookahead-threshold 2))
     (unwind-protect
         (progn
           (cl-loop for content in ,contents for index from 1
                    for file = (expand-file-name (format "%d.org" index) directory)
                    do (with-temp-file file (insert content))
                    do (push file org-agenda-files))
           (setq org-agenda-files (nreverse org-agenda-files))
           ,@body)
       (dolist (file org-agenda-files)
         (when-let* ((buffer (get-file-buffer file)))
           (with-current-buffer buffer (set-buffer-modified-p nil))
           (kill-buffer buffer)))
       (delete-directory directory t))))

(defun org-workflow-dive-test--goto (title)
  "Move to the heading containing TITLE."
  (goto-char (point-min))
  (search-forward title)
  (org-back-to-heading t))

(ert-deftest org-workflow-dive-migration-does-not-journal-intermediate-tag-state ()
  (org-workflow-dive-test--with-files '("#+filetags: :project:\n* TODO Stage :CURR:\n** TODO Task\n")
    (let ((org-workflow-store-enabled t)
          (org-workflow-store-file (expand-file-name "facts.sqlite" directory))
          (org-workflow-store--connection nil)
          (org-workflow-store--path nil))
      (unwind-protect
          (progn
            (org-workflow-migrate-current-scope t)
            (should (= 0 (caar (sqlite-select (org-workflow-store--db)
                                             "SELECT count(*) FROM operations"))))
            (org-workflow-store-recover)
            (with-current-buffer (find-file-noselect (car org-agenda-files))
              (goto-char (point-min)) (search-forward "DIVE Stage")
              (org-back-to-heading t)
              (should-not (member "CURR" (org-get-tags nil t)))
              (should-not (buffer-modified-p))))
        (when org-workflow-store--connection (sqlite-close org-workflow-store--connection))))))

(ert-deftest org-workflow-dive-recognized-in-local-keywords-and-statistics ()
  (with-temp-buffer
    (insert "#+TODO: TODO READY | DONE HOLD\n* DIVE Stage\n** TODO Child\n")
    (org-mode)
    (org-workflow-dive-test--goto "Stage")
    (should (equal "DIVE" (org-get-todo-state)))
    (should (org-workflow-target--unfinished-p))
    (should-not (org-entry-is-done-p))
    (org-workflow-summary-todo 0 1)
    (should (equal "DIVE" (org-get-todo-state)))
    (let (org-after-todo-state-change-hook)
      (org-workflow-summary-todo 1 0))
    (should (equal "DONE" (org-get-todo-state)))))

(ert-deftest org-workflow-dive-candidates-are-only-direct-todo-leaves ()
  (org-workflow-dive-test--with-files
      '("#+filetags: :project:\n* DIVE Stage\n** TODO Candidate\n** TODO Container\n*** TODO Nested\n** DIVE Nested active\n*** TODO Explicit child\n** DONE Finished\n** TODO Scheduled\nSCHEDULED: <2026-10-06 Tue>\n** TODO Habit\n:PROPERTIES:\n:STYLE: habit\n:END:\n* DIVE Standalone\n* Old :CURR:\n** TODO Inherited legacy\n* HOLD Paused\n** DIVE Held active\n*** TODO Held child\n")
    (with-current-buffer (find-file-noselect (car org-agenda-files))
      (let (titles)
        (org-map-entries
         (lambda ()
           (when (org-workflow-agenda--plannable-current-leaf-p)
             (push (org-get-heading t t t t) titles))) nil 'file)
        (should (equal '("Candidate" "Explicit child") (nreverse titles))))
      (org-workflow-dive-test--goto "Standalone")
      (should-not (org-workflow--dive-child-p))
      (should-not (org-workflow-agenda--plannable-current-leaf-p)))))

(ert-deftest org-workflow-dive-all-scope-keeps-backlog-and-exclusions ()
  (org-workflow-dive-test--with-files
      '("#+filetags: :area:\n* Parent\n** TODO Backlog\n** TODO Container\n*** TODO Nested\n** TODO Scheduled\nSCHEDULED: <2026-10-07 Wed>\n** HOLD Paused\n*** TODO Held\n")
    (with-current-buffer (find-file-noselect (car org-agenda-files))
      (let ((org-workflow-agenda-planning-all t) titles)
        (org-map-entries
         (lambda ()
           (when (org-workflow-agenda--plannable-current-leaf-p)
             (push (org-get-heading t t t t) titles))) nil 'file)
        (should (equal '("Backlog" "Nested") (nreverse titles)))))))

(ert-deftest org-workflow-dive-manual-selection-keeps-scheduled-outside-active-scope ()
  (org-workflow-dive-test--with-files
      '("#+filetags: :area:\n* DIVE Active\n** TODO Candidate\n** Container\n*** TODO Nested\n* Backlog\n** TODO Scheduled\nSCHEDULED: <2026-10-06 Tue>\n** TODO Unscheduled\n")
    (cl-letf (((symbol-function 'org-workflow-target--today-string) (lambda () "2026-10-06"))
              ((symbol-function 'org-workflow-target--ordered-entries) (lambda () nil)))
      (should (equal '("Candidate")
                     (mapcar (lambda (pair) (org-workflow-target-entry-title (cdr pair)))
                             (org-workflow-target--selection-entries))))
      (with-current-buffer (find-file-noselect (car org-agenda-files))
        (org-workflow-dive-test--goto "Scheduled")
        (setq org-workflow-target-selected-marker (copy-marker (point))
              org-workflow-target-selected-date "2026-10-06")
        (should (org-workflow-target--selected-entry))
        (org-workflow-dive-test--goto "Unscheduled")
        (setq org-workflow-target-selected-marker (copy-marker (point)))
        (should-not (org-workflow-target--selected-entry))))))

(ert-deftest org-workflow-dive-lookahead-opens-only-one-group-and-keeps-tags ()
  (org-workflow-dive-test--with-files
      '("#+filetags: :project:\n* Milestone\n** DIVE One\n*** TODO First\n*** TODO Second\n** TODO Two :@deep:\n*** TODO Next\n** TODO Three\n*** TODO Later\n")
    (should (= 1 (length (org-workflow-sync-dive))))
    (with-current-buffer (find-file-noselect (car org-agenda-files))
      (org-workflow-dive-test--goto "Two")
      (should (equal "DIVE" (org-get-todo-state)))
      (should (member "@deep" (org-get-tags nil t)))
      (should-not (member "CURR" (org-get-tags nil t)))
      (org-workflow-dive-test--goto "Three")
      (should (equal "TODO" (org-get-todo-state))))))

(ert-deftest org-workflow-dive-lookahead-does-not-open-top-level-held-or-leaf-siblings ()
  (dolist (source '("#+filetags: :project:\n* DIVE One\n** TODO First\n* TODO Two\n** TODO Next\n"
                    "#+filetags: :project:\n* Milestone\n** DIVE One\n*** TODO First\n** HOLD Two\n*** TODO Next\n"
                    "#+filetags: :project:\n* Milestone\n** DIVE One\n*** TODO First\n** TODO Two\n"))
    (org-workflow-dive-test--with-files (list source)
      (should-not (org-workflow-sync-dive)))))

(ert-deftest org-workflow-dive-lookahead-does-not-traverse-nested-inactive-work ()
  (org-workflow-dive-test--with-files
      '("#+filetags: :project:\n* Milestone\n** DIVE One\n*** TODO Container\n**** TODO Deep work\n** TODO Two\n*** TODO Next\n")
    (with-current-buffer (find-file-noselect (car org-agenda-files))
      (org-workflow-dive-test--goto "One")
      (should-not (org-workflow--curr-remaining)))
    (should-not (org-workflow-sync-dive))))

(ert-deftest org-workflow-dive-migration-preview-is-source-preserving ()
  (org-workflow-dive-test--with-files
      '("#+filetags: :project:\n* Stage :CURR:@deep:\n** TODO Task\n* DONE Finished :CURR:\n* HOLD Paused :CURR:\n"
        "* Not a project :CURR:\n** TODO Foreign\n")
    (let ((report (org-workflow-migrate-current-scope)))
      (should (= 1 (length report)))
      (should (equal '("DIVE" "DONE" "HOLD")
                     (mapcar (lambda (root) (plist-get root :to))
                             (plist-get (car report) :roots)))))
    (dolist (file org-agenda-files)
      (should-not (with-current-buffer (find-file-noselect file) (buffer-modified-p))))))

(ert-deftest org-workflow-dive-migration-preserves-schedules-tags-properties-and-done-states ()
  (org-workflow-dive-test--with-files
      '("#+filetags: :area:\n#+TODO: TODO | DONE HOLD\n* TODO Stage :CURR:@deep:\n:PROPERTIES:\n:ID: keep-id\n:END:\n** TODO Task\nSCHEDULED: <2026-10-06 Tue>\n* DONE Finished :CURR:\n* HOLD Paused :CURR:\n")
    (org-workflow-migrate-current-scope t)
    (with-current-buffer (find-file-noselect (car org-agenda-files))
      (should-not (buffer-modified-p))
      (org-workflow-dive-test--goto "Stage")
      (should (equal "DIVE" (org-get-todo-state)))
      (should (equal "keep-id" (org-entry-get nil "ID")))
      (should (equal '("@deep") (org-get-tags nil t)))
      (org-workflow-dive-test--goto "Task")
      (should (equal "<2026-10-06 Tue>" (org-entry-get nil "SCHEDULED")))
      (org-workflow-dive-test--goto "Finished")
      (should (equal "DONE" (org-get-todo-state)))
      (org-workflow-dive-test--goto "Paused")
      (should (equal "HOLD" (org-get-todo-state)))
      (should-not (string-match-p ":CURR:" (buffer-string))))
    (should (file-directory-p (expand-file-name "var/workflow-backups/" user-emacs-directory)))
    (should-not (org-workflow-migrate-current-scope t))))

(ert-deftest org-workflow-dive-migration-rejects-unsaved-and-readonly-sources ()
  (dolist (kind '(dirty readonly))
    (org-workflow-dive-test--with-files
        '("#+filetags: :project:\n* Stage :CURR:\n** TODO Task\n")
      (with-current-buffer (find-file-noselect (car org-agenda-files))
        (if (eq kind 'dirty) (insert "Unsaved\n") (setq buffer-read-only t))
        (should-error (org-workflow-migrate-current-scope t) :type 'user-error)
        (should (string-match-p ":CURR:" (buffer-string)))))))

(ert-deftest org-workflow-dive-migration-does-not-reopen-completed-or-held-ancestors ()
  (org-workflow-dive-test--with-files
      '("#+filetags: :project:\n* DONE Finished\n** Plain :CURR:\n*** TODO Child\n* HOLD Paused\n** TODO Other :CURR:\n*** TODO Work\n")
    (org-workflow-migrate-current-scope t)
    (with-current-buffer (find-file-noselect (car org-agenda-files))
      (org-workflow-dive-test--goto "Plain")
      (should-not (org-get-todo-state))
      (org-workflow-dive-test--goto "Other")
      (should (equal "TODO" (org-get-todo-state)))
      (should-not (string-match-p ":CURR:" (buffer-string))))))

(ert-deftest org-workflow-dive-migration-rejects-external-source-changes ()
  (org-workflow-dive-test--with-files
      '("#+filetags: :project:\n* Stage :CURR:\n** TODO Child\n")
    (find-file-noselect (car org-agenda-files))
    (let ((content "#+filetags: :project:\n* Externally changed :CURR:\n"))
      (with-temp-file (car org-agenda-files) (insert content))
      (set-file-times (car org-agenda-files) (time-add (current-time) 3))
      (should-error (org-workflow-migrate-current-scope t) :type 'user-error)
      (should (equal content (with-temp-buffer
                              (insert-file-contents (car org-agenda-files)) (buffer-string)))))))

(ert-deftest org-workflow-dive-migration-rolls-back-all-files-on-save-failure ()
  (org-workflow-dive-test--with-files
      '("#+filetags: :project:\n* One :CURR:\n** TODO Child\n"
        "#+filetags: :area:\n* Two :CURR:\n** TODO Other\n")
    (let ((before (mapcar (lambda (file)
                           (with-current-buffer (find-file-noselect file) (buffer-string)))
                         org-agenda-files))
          (original-save (symbol-function 'save-buffer)) (saves 0))
      (cl-letf (((symbol-function 'save-buffer)
                 (lambda (&rest args)
                   (if (= (cl-incf saves) 2) (error "Test save failure")
                     (apply original-save args)))))
        (should-error (org-workflow-migrate-current-scope t)))
      (cl-loop for file in org-agenda-files for content in before
               do (with-current-buffer (find-file-noselect file)
                    (should (equal content (buffer-string)))
                    (should-not (buffer-modified-p)))
               do (should (equal content (with-temp-buffer
                                          (insert-file-contents file) (buffer-string))))))))

(ert-deftest org-workflow-dive-migration-rolls-back-on-keyboard-quit ()
  (org-workflow-dive-test--with-files
      '("#+filetags: :project:\n* One :CURR:\n** TODO Child\n")
    (let ((before (with-current-buffer (find-file-noselect (car org-agenda-files))
                    (buffer-string))) quit-seen)
      (cl-letf (((symbol-function 'save-buffer)
                 (lambda (&rest _) (signal 'quit nil))))
        (condition-case nil (org-workflow-migrate-current-scope t)
          (quit (setq quit-seen t))))
      (should quit-seen)
      (with-current-buffer (get-file-buffer (car org-agenda-files))
        (should (equal before (buffer-string)))
        (should-not (buffer-modified-p)))
      (should (equal before (with-temp-buffer
                             (insert-file-contents (car org-agenda-files)) (buffer-string)))))))

(provide 'org-workflow-dive-test)
