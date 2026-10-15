;;; org-workflow-habits-test.el --- Habit facts and isolation -*- lexical-binding: t; -*-
(require 'ert)
(require 'org-workflow-history)
(require 'org-workflow-evening)

(defmacro workflow-habit-test (&rest body)
  `(let* ((directory (make-temp-file "habit-test-" t))
          (org-workflow-habit-file (expand-file-name "habits.org" directory))
          (org-workflow-store-file (expand-file-name "facts.sqlite" directory))
          (org-workflow-store--connection nil) (org-workflow-store--path nil)
          (org-workflow-store-enabled t)
          (org-workflow-habits-saved-hook nil)
          (org-workflow-executing-marker nil)
          (org-workflow-target-stack nil) (org-workflow-target-selected-marker nil)
          (org-agenda-files nil))
     (unwind-protect (progn ,@body)
       (dolist (buffer (buffer-list))
         (when (and (buffer-file-name buffer)
                    (string-prefix-p directory (buffer-file-name buffer)))
           (with-current-buffer buffer (set-buffer-modified-p nil)) (kill-buffer buffer)))
       (when (org-workflow-store--live-p org-workflow-store--connection)
         (sqlite-close org-workflow-store--connection))
       (delete-directory directory t))))

(ert-deftest workflow-habit-scan-reuses-warm-native-cache ()
  "Repeated history scans must not rebuild already parsed source buffers."
  (workflow-habit-test
   (with-temp-file org-workflow-habit-file
     (insert "* TODO Habit\n:PROPERTIES:\n:STYLE: habit\n:END:\n* Ordinary task\n"))
   (let ((org-element-use-cache t) titles)
     (with-current-buffer (find-file-noselect org-workflow-habit-file)
       (org-element-at-point (point-max)))
     (cl-letf (((symbol-function 'org-element-cache-reset)
                (lambda (&rest _) (ert-fail "Warm habit source cache was reset"))))
       (dotimes (_ 2)
         (org-workflow-habits--map
          (lambda () (push (org-get-heading t t t t) titles)))))
     (should (equal titles '("Habit" "Habit"))))))

(ert-deftest workflow-habit-sync-scans-sources-twice-regardless-of-history ()
  "Date discovery and fact collection each scan once, even for long history."
  (workflow-habit-test
   (with-temp-file org-workflow-habit-file
     (insert "* TODO Habit\n:PROPERTIES:\n:STYLE: habit\n:ID: bulk\n:END:\n:LOGBOOK:\n- State \"DONE\" from \"TODO\" [2026-09-19 Sat 00:20]\nCLOCK: [2026-09-18 Fri 23:50]--[2026-09-19 Sat 00:20] => 0:30\n:END:\n"))
   (let ((scan (symbol-function 'org-workflow-habits--map)) (calls 0))
     (cl-letf (((symbol-function 'org-workflow-habits--map)
                (lambda (function) (cl-incf calls) (funcall scan function))))
       (org-workflow-history-sync-habits))
     (should (= calls 2)))
   (let ((days (org-workflow-store-habit-days)))
     (should (= 10 (plist-get (cadr (assoc "2026-09-18" days)) :focusMinutes)))
     (should (= 20 (plist-get (cadr (assoc "2026-09-19" days)) :focusMinutes))))))

(ert-deftest workflow-habit-bulk-records-preserve-order-and-empty-days ()
  (workflow-habit-test
   (with-temp-file org-workflow-habit-file
     (dolist (id '("first" "second"))
       (insert (format "* TODO %s\n:PROPERTIES:\n:STYLE: habit\n:ID: %s\n:END:\n- State \"DONE\" from \"TODO\" [2026-09-19 Sat 00:20]\n" id id))))
   (let ((records (org-workflow-habits-records-for-dates '("2026-09-19" "2026-09-20"))))
     (should (equal (mapcar (lambda (row) (plist-get row :id)) (cdar records))
                    '("first" "second")))
     (should (equal (cadr records) '("2026-09-20"))))))

(ert-deftest workflow-habit-sync-clears-deleted-facts-and-rejects-duplicate-ids ()
  (workflow-habit-test
   (let ((text "* TODO Habit\n:PROPERTIES:\n:STYLE: habit\n:ID: same\n:END:\n- State \"DONE\" from \"TODO\" [2026-09-19 Sat 00:20]\n"))
     (with-temp-file org-workflow-habit-file (insert text))
     (org-workflow-history-sync-habits)
     (let ((before (org-workflow-store-habit-days)))
       (with-current-buffer (find-file-noselect org-workflow-habit-file)
         (goto-char (point-max)) (insert text))
       (should-error (org-workflow-history-sync-habits))
       (should (equal before (org-workflow-store-habit-days))))
     (with-current-buffer (find-file-noselect org-workflow-habit-file) (erase-buffer))
     (org-workflow-history-sync-habits)
     (should (equal (assoc "2026-09-19" (org-workflow-store-habit-days))
                    '("2026-09-19"))))))

(ert-deftest workflow-habit-capture-save-and-kill-use-bulk-sync ()
  (require 'org-capture)
  (workflow-habit-test
   (with-temp-file org-workflow-habit-file
     (insert "* TODO Habit\n:PROPERTIES:\n:STYLE: habit\n:ID: capture-test\n:END:\n- State \"DONE\" from \"TODO\" [2026-09-19 Sat 00:20]\n"))
   (let ((org-capture-templates
          `(("x" "Test" entry (file ,org-workflow-habit-file) "* TODO %?")))
         (org-capture-mode-hook nil)
         (org-capture-prepare-finalize-hook nil)
         (org-capture-after-finalize-hook nil)
         (org-workflow-habits-saved-hook '(org-workflow-history-sync-habits))
         (scan (symbol-function 'org-workflow-habits--map)) (calls 0))
     (save-window-excursion
       (org-capture nil "x")
       (unwind-protect
           (cl-letf (((symbol-function 'org-workflow-habits--map)
                      (lambda (function) (cl-incf calls) (funcall scan function))))
             (insert "Temporary capture")
             (with-current-buffer (buffer-base-buffer) (save-buffer))
             (should (= calls 2))
             (setq calls 0)
             (org-capture-kill)
             (should (= calls 2)))
         (when (bound-and-true-p org-capture-mode) (org-capture-kill))))
     (with-temp-buffer
       (insert-file-contents org-workflow-habit-file)
       (should-not (search-forward "Temporary capture" nil t)))
     (should (= 1 (length (cdr (assoc "2026-09-19" (org-workflow-store-habit-days)))))))))

(ert-deftest workflow-habit-cross-midnight-completion-and-sqlite-replay ()
  (workflow-habit-test
   (with-temp-file org-workflow-habit-file
     (insert "#+TODO: TODO | DONE\n* TODO Exercise\nSCHEDULED: <2026-09-20 Sun .+1d>\n:PROPERTIES:\n:STYLE: habit\n:ID: habit-test\n:END:\n:LOGBOOK:\n- State \"DONE\" from \"TODO\" [2026-09-19 Sat 00:20]\nCLOCK: [2026-09-18 Fri 23:50]--[2026-09-19 Sat 00:20] => 0:30\n:END:\n"))
   (should (= 10 (plist-get (car (org-workflow-habits-records "2026-09-18")) :focusMinutes)))
   (let ((record (car (org-workflow-habits-records "2026-09-19"))))
     (should (= 20 (plist-get record :focusMinutes)))
     (should (equal "done" (plist-get record :outcome)))
     (should (= 1 (length (plist-get record :completedAt)))))
   (org-workflow-history-sync-habits)
   (let ((before (org-workflow-store-habit-days)))
     (org-workflow-history-sync-habits)
     (should (equal before (org-workflow-store-habit-days))))
   (let ((record (org-workflow-history--compute "2026-09-19")))
     (should (= 20 (plist-get record :habitFocusMinutes)))
     (should (= 20 (plist-get record :focusTotalMinutes)))
     (should (= 0 (plist-get record :optionalFocusMinutes)))
     (should (= 1 (plist-get record :habitCompleted))))))

(ert-deftest workflow-habit-in-project-is-not-a-workflow-task ()
  (workflow-habit-test
   (with-temp-file org-workflow-habit-file
     (insert "#+filetags: :project:\n* Stage :CURR:\n** TODO Exercise\nSCHEDULED: <2026-09-01 Tue .+1d>\n:PROPERTIES:\n:ID: isolated\n:STYLE: habit\n:END:\n"))
   (let ((org-agenda-files (list org-workflow-habit-file)))
     (should-not (org-workflow-target--collect))
     (with-current-buffer (find-file-noselect org-workflow-habit-file)
       (goto-char (point-max)) (org-back-to-heading t)
       (should-not (org-workflow-commands--scoped-p))))))

(ert-deftest workflow-habit-native-completion-repeats-and-records ()
  (workflow-habit-test
   (org-workflow-habits-create "认真尝试一道题")
   (org-workflow-habits-complete)
   (should (equal "TODO" (org-get-todo-state)))
   (should (= 1 (length (org-workflow-habits-records (format-time-string "%F")))))
   (should-not org-workflow-executing-marker)))

(ert-deftest workflow-habit-evening-view-keeps-native-markers ()
  (workflow-habit-test
   (org-workflow-habits-create "SICP")
   (cl-letf (((symbol-function 'org-workflow-collection-inbox--review-files) (lambda () nil)))
     (org-workflow-evening-open)
     (goto-char (point-min))
     (search-forward "SICP")
     (should (markerp (org-get-at-bol 'org-hd-marker)))
     (should (eq (lookup-key (current-local-map) (kbd "a")) #'org-workflow-agenda-view-menu)))))

(ert-deftest workflow-habit-clock-is-saved-without-changing-execution ()
  (workflow-habit-test
   (org-workflow-habits-create "Clock test")
   (let* ((org-workflow-clock 'org-clock)
          (org-workflow-executing-marker (copy-marker (point)))
          (original org-workflow-executing-marker)
          (org-clock-history nil)
          (org-clock-persist nil)
          (org-clock-out-remove-zero-time-clocks nil)
          (org-workflow-habits-saved-hook '(org-workflow-history-sync-habits)))
     (unwind-protect
         (progn
           (org-workflow-habits-start)
           (should (org-clocking-p))
           (should-error (org-workflow-habits-start) :type 'user-error)
           (org-clock-out)
           (should-not (buffer-modified-p))
           (should (eq original org-workflow-executing-marker))
           (should (org-workflow-store-habit-days)))
       (when (org-clocking-p) (org-clock-cancel))))))

(ert-deftest workflow-habit-sync-failure-preserves-snapshot-and-can-replay ()
  (workflow-habit-test
   (org-workflow-habits-create "Retry")
   (org-workflow-history-sync-habits)
   (let ((before (org-workflow-store-habit-days))
         (execute (symbol-function 'sqlite-execute)))
     (org-workflow-habits-complete)
     (cl-letf (((symbol-function 'sqlite-execute)
                (lambda (db sql &optional values)
                  (if (string-prefix-p "INSERT OR REPLACE INTO habit_days" sql)
                      (error "Injected database failure")
                    (funcall execute db sql values)))))
       (should-error (org-workflow-history-sync-habits)))
     (should (equal before (org-workflow-store-habit-days)))
     (org-workflow-history-sync-habits)
     (should (= 1 (length (cdr (assoc (format-time-string "%F")
                                      (org-workflow-store-habit-days)))))))))

(ert-deftest workflow-habit-completion-cannot-advance-curr ()
  (workflow-habit-test
   (with-temp-file org-workflow-habit-file
     (insert "#+filetags: :project:\n#+TODO: TODO | DONE\n* Milestone\n** Step :CURR:\n*** TODO Habit\nSCHEDULED: <2026-09-19 Sat .+1d>\n:PROPERTIES:\n:ID: isolated\n:STYLE: habit\n:END:\n*** TODO Task\n** Next step\n*** TODO Next task\n"))
   (let ((org-agenda-files (list org-workflow-habit-file)))
     (with-current-buffer (find-file-noselect org-workflow-habit-file)
       (goto-char (point-min)) (search-forward "*** TODO Habit") (org-back-to-heading t)
       (org-workflow-habits-complete)
       (goto-char (point-min)) (search-forward "** Next step")
       (should-not (member "CURR" (org-get-tags nil t)))))))

(ert-deftest workflow-habit-missing-source-is-not-zero ()
  (workflow-habit-test
   (org-workflow-habits-create "Keep facts")
   (org-workflow-history-sync-habits)
   (rename-file org-workflow-habit-file (concat org-workflow-habit-file ".backup"))
   (should-error (org-workflow-history-sync-habits))
   (should-error (org-workflow-history--compute (format-time-string "%F")))))

(ert-deftest workflow-habit-week-streak-boundaries ()
  (let* ((sat (time-to-days (org-time-string-to-time "2026-09-19 12:00")))
         (done (list (- sat 2) (1- sat)))
         (pending (substring-no-properties (org-workflow-evening--week done sat))))
    (should (string-prefix-p "日 ☒" pending))
    (should (string-match-p "五 ☑  六 ☐" pending))
    (should (string-match-p "连续 2 天" pending))
    (should (string-match-p "连续 3 天"
                            (org-workflow-evening--week (cons sat done) sat)))
    (should (string-match-p "连续 0 天"
                            (org-workflow-evening--week done (+ sat 2))))))

(ert-deftest workflow-habit-optional-hides-completed-and-future-and-is-readonly ()
  (workflow-habit-test
   (with-temp-file org-workflow-habit-file
     (insert "#+TODO: TODO | DONE\n* TODO Completed\nSCHEDULED: <2026-09-20 Sun .+1d>\n:PROPERTIES:\n:STYLE: habit\n:END:\n:LOGBOOK:\n- State \"DONE\" from \"TODO\" [2026-09-19 Sat 20:00]\n:END:\n* TODO Future\nSCHEDULED: <2026-09-21 Mon .+1d>\n:PROPERTIES:\n:STYLE: habit\n:END:\n"))
   (let* ((source (find-file-noselect org-workflow-habit-file))
          (before (with-current-buffer source (buffer-string))))
     (cl-letf (((symbol-function 'org-workflow-target--today-string) (lambda () "2026-09-19"))
               ((symbol-function 'org-workflow-target--ordered-entries) (lambda (&rest _) nil))
               ((symbol-function 'org-workflow-collection-inbox--review-files) (lambda () nil)))
       (with-temp-buffer
         (org-workflow-agenda-inbox nil)
         (should-not (string-match-p "Completed" (buffer-string)))
         (should-not (string-match-p "Future" (buffer-string)))
         (should (org-workflow-target-entry-done
                  (car (org-workflow-habits-items "2026-09-19"))))))
     (should (equal before (with-current-buffer source (buffer-string))))
     (should-not (buffer-modified-p source)))))

(ert-deftest workflow-habit-streak-crosses-weeks-and-stops-at-gap ()
  (let* ((today (time-to-days (org-time-string-to-time "2026-09-19 12:00")))
         (done (number-sequence (- today 60) (1- today))))
    (should (string-match-p "  连续 60 天"
                            (org-workflow-evening--week done today)))
    (should (string-match-p "  连续 61 天"
                            (org-workflow-evening--week (cons today done) today)))
    (should (string-match-p "  连续 2 天"
                            (org-workflow-evening--week
                             (remq (- today 3) done) today)))))

(ert-deftest workflow-console-isolates-bindings-and-restores-base-map ()
  (with-temp-buffer
    (org-agenda-mode)
    (let ((base (current-local-map))
          (before (lookup-key org-agenda-mode-map (kbd "u"))))
      (let ((org-workflow-agenda-sprint-view t))
        (org-workflow-agenda-console-bindings-setup)
        (should (eq (lookup-key (current-local-map) (kbd "u"))
                    #'org-workflow-agenda-plan-morning))
        (org-workflow-agenda-console-bindings-setup)
        (should (= 1 (cl-count org-workflow-agenda-console--mode-line mode-line-misc-info
                               :test #'equal))))
      (let ((org-workflow-agenda-sprint-view nil)) (org-workflow-agenda-console-bindings-setup))
      (should (eq base (current-local-map)))
      (should (eq before (lookup-key org-agenda-mode-map (kbd "u")))))))

(ert-deftest workflow-habit-nondaily-grid-has-no-daily-streak ()
  (let* ((today (time-to-days (org-time-string-to-time "2026-09-20 12:00")))
         (grid (org-workflow-evening--week (list today) today t)))
    (should (string-match-p "日 ☑" grid))
    (should-not (string-match-p "连续" grid))))

(ert-deftest workflow-habit-default-path-follows-miscellaneous-configuration ()
  (let ((org-workflow-habit-file nil)
        (org-workflow-projects-file "/tmp/early-projects.org"))
    (should (equal "/tmp/early-projects.org" (org-workflow-habits-file)))
    (setq org-workflow-projects-file "/tmp/configured/projects.org")
    (let ((default-directory "/tmp/another-project/"))
      (should (equal "/tmp/configured/projects.org" (org-workflow-habits-file))))
    (setq org-workflow-habit-file "/tmp/explicit-habits.org")
    (should (equal "/tmp/explicit-habits.org" (org-workflow-habits-file)))))

(ert-deftest workflow-habit-established-missing-source-still-errors ()
  (workflow-habit-test
   (org-workflow-store-set-meta "habit-source" org-workflow-habit-file)
   (should-error (org-workflow-history--habit-records "2026-09-21"))
   (should-not (file-exists-p org-workflow-habit-file))))

(ert-deftest workflow-habit-save-clears-last-embedded-habit ()
  (workflow-habit-test
   (let* ((embedded (expand-file-name "embedded.org" directory))
          (org-agenda-files (list embedded))
          (org-workflow-habits-saved-hook '(org-workflow-history-sync-habits)))
     (with-temp-file org-workflow-habit-file (insert "* Dedicated source\n"))
     (with-temp-file embedded
       (insert "* TODO Embedded\n:PROPERTIES:\n:STYLE: habit\n:ID: embedded\n:END:\n- State \"DONE\" from \"TODO\" [2026-10-14 Wed 09:00]\n"))
     (org-workflow-history-sync-habits)
     (should (cdr (assoc "2026-10-14" (org-workflow-store-habit-days))))
     (with-current-buffer (find-file-noselect embedded)
       (erase-buffer) (insert "* Ordinary task\n")
       (let ((org-workflow-habits-saved-hook
              (list (lambda () (error "Temporary sync failure")))))
         (should-error (save-buffer)))
       (should (cdr (assoc "2026-10-14" (org-workflow-store-habit-days))))
       (insert "Retry\n") (save-buffer)
       (let ((org-workflow-habits-saved-hook
              (list (lambda () (ert-fail "Ordinary save repeated habit sync")))))
         (insert "Ordinary edit\n") (save-buffer)))
     (should-not (org-workflow-habits-records "2026-10-14"))
     (should-not (cdr (assoc "2026-10-14" (org-workflow-store-habit-days)))))))

(ert-deftest workflow-habit-sync-quit-rolls-back ()
  (workflow-habit-test
   (with-temp-file org-workflow-habit-file (insert "* Source\n"))
   (let ((execute (symbol-function 'sqlite-execute)) (quit-seen nil))
     (cl-letf (((symbol-function 'sqlite-execute)
                (lambda (db sql &optional values)
                  (if (string-prefix-p "INSERT OR REPLACE INTO habit_days" sql)
                      (signal 'quit nil)
                    (funcall execute db sql values)))))
       (condition-case nil (org-workflow-history-sync-habits)
         (quit (setq quit-seen t))))
     (should quit-seen)
     (sqlite-execute (org-workflow-store--db) "BEGIN IMMEDIATE")
     (sqlite-execute (org-workflow-store--db) "ROLLBACK"))))


(ert-deftest workflow-habit-finalize-quit-rolls-back ()
  (workflow-habit-test
   (cl-letf (((symbol-function 'org-workflow-history--compute)
              (lambda (_) (signal 'quit nil))))
     (should (eq 'cancelled
                 (condition-case nil (org-workflow-history-finalize "2026-01-01")
                   (quit 'cancelled)))))
   (sqlite-execute (org-workflow-store--db) "BEGIN IMMEDIATE")
   (sqlite-execute (org-workflow-store--db) "ROLLBACK")))
