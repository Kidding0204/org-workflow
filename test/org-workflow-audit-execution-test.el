;;; org-workflow-audit-execution-test.el --- Execution source contracts -*- lexical-binding: t; -*-
(require 'ert)
(load "org-workflow-projects-test" nil t)
(load "org-workflow-habits-test" nil t)

(defmacro workflow-audit-execution-fixture (&rest body)
  `(workflow-project-fixture
    (let ((org-workflow-target-stack nil)
          (org-workflow-habit-selection nil)
          (org-workflow-target-invalidated-selection nil)
          (org-workflow-clock 'org-clock)
          (org-clock-marker (make-marker))
          (org-clock-hd-marker (make-marker))
          (org-workflow-work-periods
           '((morning "00:00" "12:00") (afternoon "12:00" "18:00")
             (evening "18:00" "23:59"))))
      (cl-letf (((symbol-function 'current-time) (lambda () (encode-time 0 0 20 16 9 2026))))
        ,@body))))

(ert-deftest workflow-audit-execution-deletion-does-not-complete-successor ()
  (dolist (existing-id '(nil t))
    (workflow-audit-execution-fixture
     (when existing-id (workflow-project-at "Tokens") (org-entry-put nil "ID" "selected"))
     (org-workflow-target-select-marker (workflow-project-at "Tokens"))
     (org-with-point-at org-workflow-executing-marker
			(delete-region (point) (save-excursion (org-end-of-subtree t t))))
     (org-workflow-target-refresh t)
     (should-error (org-workflow-target-complete) :type 'user-error)
     (workflow-project-at "Parser")
     (should (equal "TODO" (org-get-todo-state))))))

(ert-deftest workflow-audit-execution-replacement-is-not-selected-source ()
  (workflow-audit-execution-fixture
   (org-workflow-target-select-marker (workflow-project-at "Tokens"))
   (org-with-point-at org-workflow-executing-marker
		      (delete-region (point) (save-excursion (org-end-of-subtree t t)))
		      (insert "*** TODO Replacement\nSCHEDULED: <2026-09-16 Wed>\n"))
   (should-error (org-workflow-target-complete) :type 'user-error)
   (workflow-project-at "Replacement")
   (should (equal "TODO" (org-get-todo-state)))))

(ert-deftest workflow-audit-execution-title-edit-and-insertion-preserve-source ()
  (dolist (existing-id '(nil t))
    (workflow-audit-execution-fixture
     (when existing-id (workflow-project-at "Tokens") (org-entry-put nil "ID" "selected"))
     (org-workflow-target-select-marker (workflow-project-at "Tokens"))
     (workflow-project-at "Tokens")
     (org-edit-headline "Renamed")
     (workflow-project-at "Renamed")
     (insert "*** TODO Inserted\n")
     (workflow-project-at "Renamed")
     (org-move-subtree-down)
     (let ((position (point)) (text (buffer-string)))
       (org-workflow-target-refresh t)
       (should (= position (point)))
       (should (equal text (buffer-string)))
       (should (equal "Renamed" (org-workflow-target-entry-title (org-workflow-current-item)))))
     (org-workflow-target-complete)
     (workflow-project-at "Renamed")
     (should (equal "DONE" (org-get-todo-state))))))

(ert-deftest workflow-audit-execution-closed-ancestor-stops-matching-clock ()
  (dolist (state '("HOLD" "DONE"))
    (workflow-audit-execution-fixture
     (org-workflow-target-select-marker (workflow-project-at "Tokens"))
     (org-workflow-target-start)
     (should (org-clocking-p))
     (org-workflow-projects-set-state (workflow-project-at "Lexing") state)
     (org-workflow-target-refresh t)
     (should-not org-workflow-executing-marker)
     (should-not (org-clocking-p))
     (should-not (seq-find (lambda (entry) (equal "Tokens" (org-workflow-target-entry-title entry)))
                           org-workflow-target-stack)))))

(ert-deftest workflow-audit-execution-done-ancestor-excluded-from-queue ()
  (workflow-audit-execution-fixture
   (org-workflow-projects-set-state (workflow-project-at "Lexing") "DONE")
   (should-not (seq-find (lambda (entry) (equal "Tokens" (org-workflow-target-entry-title entry)))
                         (org-workflow-target--collect)))))

(ert-deftest workflow-audit-execution-stage-current-policy-requires-done ()
  (workflow-audit-execution-fixture
   (org-workflow-store-set-meta "completion-floor-since" "2026-09-16")
   (workflow-project-at "Tokens") (org-todo "HOLD")
   (should (= 0 (plist-get (org-workflow--stage-progress "2026-09-16") :stageSatisfied)))))

(ert-deftest workflow-audit-execution-stage-legacy-policy-retains-held ()
  (workflow-audit-execution-fixture
   (org-workflow-store-set-meta "completion-floor-since" "2026-09-17")
   (workflow-project-at "Tokens") (org-todo "HOLD")
   (should (= 1 (plist-get (org-workflow--stage-progress "2026-09-16") :stageSatisfied)))))

(ert-deftest workflow-audit-execution-duplicate-habits-have-distinct-actionable-keys ()
  (workflow-habit-test
   (with-temp-file org-workflow-habit-file
     (dotimes (_ 2)
       (insert "* TODO Drink\nSCHEDULED: <2026-09-16 Wed .+1d>\n:PROPERTIES:\n:STYLE: habit\n:WORKFLOW_HABIT_REMINDER: 08:00\n:END:\n")))
   (let ((org-workflow-habit-selection nil)
         (org-workflow-focus-timer-task-marker nil)
         (org-clock-marker (make-marker))
         (org-workflow-panel--habit-markers nil))
     (cl-letf (((symbol-function 'org-workflow-target--today-string) (lambda () "2026-09-16")))
       (let* ((items (org-workflow-habits-items "2026-09-16"))
              (second (cadr items))
              (key (org-workflow-item-key second))
              (source (marker-buffer (org-workflow-target-entry-marker second)))
              (before (with-current-buffer source (buffer-string))))
         (should-not (equal key (org-workflow-item-key (car items))))
         (org-workflow-panel-toggle-habit key)
         (should (= (marker-position (org-workflow-target-entry-marker second))
                    (marker-position (org-workflow-target-entry-marker (org-workflow-current-item)))))
         (let ((rows (org-workflow-panel--habits "2026-09-16")))
           (should-not (eq t (plist-get (aref rows 0) :selected)))
           (should (eq t (plist-get (aref rows 1) :selected))))
         (should (equal before (with-current-buffer source (buffer-string)))))))))

(ert-deftest workflow-audit-execution-stale-item-cannot-complete-replacement ()
  (workflow-audit-execution-fixture
   (let ((item (org-workflow-item-at-marker (workflow-project-at "Tokens"))))
     (delete-region (point) (save-excursion (org-end-of-subtree t t)))
     (insert "*** TODO Replacement\nSCHEDULED: <2026-09-16 Wed>\n")
     (should-error (org-workflow-item-complete item) :type 'user-error)
     (workflow-project-at "Replacement")
     (should (equal "TODO" (org-get-todo-state))))))

(ert-deftest workflow-audit-execution-deleted-clock-does-not-touch-successor ()
  (workflow-audit-execution-fixture
   (org-workflow-target-select-marker (workflow-project-at "Tokens"))
   (org-workflow-target-start)
   (org-with-point-at org-workflow-executing-marker
		      (delete-region (point) (save-excursion (org-end-of-subtree t t))))
   (org-workflow-target-refresh t)
   (should-not (org-clocking-p))
   (should-error (org-workflow-target-complete) :type 'user-error)
   (workflow-project-at "Parser")
   (should (equal "TODO" (org-get-todo-state)))
   (should-not (string-match-p "CLOCK:"
                               (buffer-substring-no-properties
                                (point) (save-excursion (org-end-of-subtree t t)))))))

(ert-deftest workflow-audit-execution-move-integration-is-reversible ()
  (let ((enabled org-workflow-mode)
        (org-workflow-store-enabled org-workflow-store-enabled))
    (unwind-protect
        (progn
          (org-workflow-mode 1)
          (should (advice-member-p #'org-workflow-target--save-execution-markers
                                   'org-save-markers-in-region))
          (org-workflow-mode -1)
          (should-not (advice-member-p #'org-workflow-target--save-execution-markers
                                       'org-save-markers-in-region)))
      (when enabled (org-workflow-mode 1)))))

(ert-deftest workflow-audit-execution-disable-releases-session-identities ()
  (let ((org-workflow-target-selected-source '(old-source))
        (org-workflow-executing-source '(old-execution))
        (org-workflow-target-selected-marker (make-marker))
        (org-workflow-executing-marker (make-marker))
        (org-workflow-target-selected-date "2026-09-16")
        (org-workflow-executing-clock-start-time '(1 2 3))
        (org-workflow-target-invalidated-selection (make-marker)))
    (org-workflow--cancel-background-work)
    (dolist (value (list org-workflow-target-selected-source org-workflow-executing-source
                         org-workflow-target-selected-marker org-workflow-executing-marker
                         org-workflow-target-selected-date org-workflow-executing-clock-start-time
                         org-workflow-target-invalidated-selection))
      (should-not value))))

(ert-deftest review-habit-key-does-not-retarget-after-source-delete ()
  (workflow-habit-test
   (with-temp-file org-workflow-habit-file
     (dolist (title '("Drink" "Stretch"))
       (insert (format "* TODO %s\nSCHEDULED: <2026-09-16 Wed .+1d>\n:PROPERTIES:\n:STYLE: habit\n:WORKFLOW_HABIT_REMINDER: 08:00\n:END:\n" title))))
   (let ((org-workflow-habit-selection nil)
         (org-workflow-focus-timer-task-marker nil)
         (org-clock-marker (make-marker)))
     (cl-letf (((symbol-function 'org-workflow-target--today-string) (lambda () "2026-09-16")))
       (let* ((item (car (org-workflow-habits-items "2026-09-16")))
              (key (org-workflow-item-key item)))
         (org-workflow-panel-toggle-habit key)
         (org-with-point-at (org-workflow-target-entry-marker item)
			    (delete-region (point) (save-excursion (org-end-of-subtree t t))))

         (should-error (org-workflow-target-complete) :type 'user-error)
         (should-not (org-workflow-current-item))
         (should-not (org-workflow-current-item))))))
  )

(ert-deftest review-habit-switch-keeps-ordinary-selection-identity ()
  (workflow-audit-execution-fixture
   (let ((org-workflow-habit-file (expand-file-name "habits.org" directory)))
     (with-temp-file org-workflow-habit-file
       (insert "* TODO Drink\nSCHEDULED: <2026-09-16 Wed .+1d>\n:PROPERTIES:\n:STYLE: habit\n:END:\n"))
     (org-workflow-target-select-marker (workflow-project-at "Tokens"))
     (let* ((item (car (org-workflow-habits-items "2026-09-16")))
            (key (org-workflow-item-key item)))
       (org-workflow-panel-toggle-habit key)
       (org-workflow-panel-toggle-habit key)
       (workflow-project-at "Tokens")
       (delete-region (point) (save-excursion (org-end-of-subtree t t)))
       (should-error (org-workflow-target-complete) :type 'user-error)
       (workflow-project-at "Parser")
       (should (equal "TODO" (org-get-todo-state)))))))

(ert-deftest review-deleted-selection-keeps-unrelated-clock ()
  (workflow-audit-execution-fixture
   (let ((org-clock-persist nil) (org-clock-auto-clock-resolution nil)
         (org-clock-in-hook nil) (org-clock-in-switch-to-state nil)
         (org-clock-out-hook nil) (org-clock-history nil))
     (unwind-protect
         (progn
           (org-workflow-target-select-marker (workflow-project-at "Tokens"))
           (workflow-project-at "Parser")
           (org-clock-in nil (time-subtract (current-time) 600))
           (workflow-project-at "Tokens")
           (delete-region (point) (save-excursion (org-end-of-subtree t t)))
           (org-workflow-target-refresh t)
           (should (org-clocking-p)))
       (when (org-clocking-p) (org-clock-cancel))))))

(ert-deftest review-deleted-habit-cannot-complete-ordinary-task ()
  (workflow-audit-execution-fixture
   (let ((org-workflow-habit-file (expand-file-name "habits.org" directory)))
     (with-temp-file org-workflow-habit-file
       (insert "* TODO Drink\nSCHEDULED: <2026-09-16 Wed .+1d>\n:PROPERTIES:\n:STYLE: habit\n:END:\n"))
     (org-workflow-target-select-marker (workflow-project-at "Tokens"))
     (let ((item (car (org-workflow-habits-items "2026-09-16"))))
       (org-workflow-panel-toggle-habit (org-workflow-item-key item))
       (org-with-point-at (org-workflow-target-entry-marker item)
			  (delete-region (point) (save-excursion (org-end-of-subtree t t))))
       (should-error (org-workflow-target-complete) :type 'user-error)
       (workflow-project-at "Tokens")
       (should (equal "TODO" (org-get-todo-state)))))))
