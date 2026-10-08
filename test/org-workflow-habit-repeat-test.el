;;; org-workflow-habit-repeat-test.el --- Repeat rules -*- lexical-binding: t; -*-
(load "org-workflow-habits-test.el" nil t)

(defmacro workflow-repeat-at (date &rest body)
  `(let ((time (org-time-string-to-time (concat ,date " 12:00")))
         (formatter (symbol-function 'format-time-string)))
     (cl-letf (((symbol-function 'current-time) (lambda () time))
               ((symbol-function 'org-today) (lambda () (time-to-days time)))
               ((symbol-function 'format-time-string)
                (lambda (format &optional when zone)
                  (funcall formatter format (or when time) zone)))) ,@body)))

(ert-deftest workflow-repeat-interval-native-completion ()
  (workflow-habit-test
   (workflow-repeat-at "2026-10-08"
    (org-workflow-habits-create "Read one chapter")
    (org-workflow-habits-set-repeat 'interval 2 "2026-10-08")
    (should (equal ".+2d" (org-get-repeat (org-entry-get nil "SCHEDULED"))))
    (org-workflow-habits-complete)
    (should (string-match-p "2026-10-10" (org-entry-get nil "SCHEDULED")))
    (should (equal "TODO" (org-get-todo-state)))
    (should (= 1 (length (org-workflow-habits-records "2026-10-08")))))))

(ert-deftest workflow-repeat-fixed-weekday-late-completion-keeps-sunday ()
  (workflow-habit-test
   (workflow-repeat-at "2026-10-12"
    (org-workflow-habits-create "Weekly review")
    (org-workflow-habits-set-repeat 'weekdays '(0) "2026-10-11")
    (should-not (org-workflow-habits-items "2026-10-12"))
    (org-workflow-habits-complete)
    (should (string-match-p "2026-10-18" (org-entry-get nil "SCHEDULED")))
    (should (equal "++1d" (org-get-repeat (org-entry-get nil "SCHEDULED"))))
    (should (org-workflow-habits-items "2026-10-18")))))

(ert-deftest workflow-repeat-multiple-weekdays-advance ()
  (workflow-habit-test
   (workflow-repeat-at "2026-10-08"
    (org-workflow-habits-create "Practice")
    (org-workflow-habits-set-repeat 'weekdays '(0 3 5) "2026-10-08")
    (should (string-match-p "2026-10-09" (org-entry-get nil "SCHEDULED")))
    (should-not (org-workflow-habits-items "2026-10-10")))
   (workflow-repeat-at "2026-10-09"
    (org-workflow-habits-complete)
    (should (string-match-p "2026-10-11" (org-entry-get nil "SCHEDULED"))))))

(ert-deftest workflow-repeat-weekly-quota-reset-and-duplicate-guard ()
  (workflow-habit-test
   (workflow-repeat-at "2026-10-04"
    (org-workflow-habits-create "Atomic Habits: one chapter per session")
    (org-workflow-habits-set-repeat 'weekly 3 "2026-10-04")
    (org-workflow-habits-complete)
    (should-error (org-workflow-habits-complete) :type 'user-error))
   (workflow-repeat-at "2026-10-06" (org-workflow-habits-complete))
   (workflow-repeat-at "2026-10-08"
    (should (org-workflow-habits-items "2026-10-08"))
    (org-workflow-habits-complete)
    (should (equal "每周 3 次 · 本周 3/3" (org-workflow-habits-rule-label)))
    (should (org-workflow-habits-items "2026-10-08"))
    (should-not (org-workflow-habits-items "2026-10-10"))
    (should (org-workflow-habits-items "2026-10-11"))
    (should (= 0 (org-workflow-habits-week-count
                  (org-workflow-habits--parse)
                  (time-to-days (org-time-string-to-time "2026-10-11 12:00"))))))))

(ert-deftest workflow-repeat-weekly-future-start-and-no-debt ()
  (workflow-habit-test
   (workflow-repeat-at "2026-10-08"
    (org-workflow-habits-create "Read")
    (org-workflow-habits-set-repeat 'weekly 3 "2026-10-11")
    (should-not (org-workflow-habits-items "2026-10-08"))
    (should (org-workflow-habits-items "2026-10-18"))
    (should (= 0 (org-workflow-habits-week-count
                  (org-workflow-habits--parse)
                  (time-to-days (org-time-string-to-time "2026-10-18 12:00"))))))))

(ert-deftest workflow-repeat-invalid-input-does-not-change-source ()
  (workflow-habit-test
   (org-workflow-habits-create "Keep")
   (let ((before (buffer-string)))
     (dolist (rule '((weekly 8) (weekly 0) (interval 0) (weekdays nil) (weekdays (7))))
       (should-error (apply #'org-workflow-habits-set-repeat rule) :type 'user-error)
       (should (equal before (buffer-string)))))))

(ert-deftest workflow-repeat-changing-mode-clears-only-repeat-properties ()
  (workflow-habit-test
   (org-workflow-habits-create "Keep facts")
   (org-entry-put nil "WORKFLOW_HABIT_POSITION" "morning-early")
   (org-workflow-habits-set-repeat 'weekly 3)
   (org-workflow-habits-complete)
   (let ((facts (org-workflow-habits-records (format-time-string "%F"))))
     (org-workflow-habits-set-repeat 'weekdays '(0))
     (should-not (org-workflow-habits-week-target))
     (org-workflow-habits-set-repeat 'interval 2)
     (should-not (org-workflow-habits-weekdays))
     (should (org-workflow-habits-position))
     (should (equal facts (org-workflow-habits-records (format-time-string "%F")))))))

(ert-deftest workflow-repeat-grid-neutral-days-and-sunday-start ()
  (let* ((day (time-to-days (org-time-string-to-time "2026-10-08 12:00")))
         (grid (org-workflow-evening--week nil day t '(0))))
    (should (string-prefix-p "日 ☒" grid))
    (should (string-match-p "四 ⊟" grid))
    (should (equal "无需执行" (get-text-property (string-match "四" grid) 'help-echo grid)))
    (should-not (string-match-p "连续" grid))
    (should-not (string-match-p "☒" (org-workflow-evening--week nil day t nil 3)))))

(ert-deftest workflow-repeat-native-todo-advances-fixed-weekdays ()
  (workflow-habit-test
   (workflow-repeat-at "2026-10-09"
    (org-workflow-habits-create "Native Friday completion")
    (org-workflow-habits-set-repeat 'weekdays '(0 5) "2026-10-09")
    (let ((org-log-repeat 'time) (org-log-into-drawer t))
      (org-todo "DONE")
      (when org-log-note-marker (org-add-log-note)))
    (should (string-match-p "2026-10-11" (org-entry-get nil "SCHEDULED"))))))

(ert-deftest workflow-repeat-weekly-desktop-stops-at-quota-and-resets ()
  (workflow-habit-test
   (let ((org-workflow-panel--habit-markers nil))
     (workflow-repeat-at "2026-10-08"
      (org-workflow-habits-create "Read")
      (org-workflow-habits-set-repeat 'weekly 1 "2026-10-08")
      (org-workflow-habits-complete)
      (should (eq t (plist-get (aref (org-workflow-panel--habits "2026-10-08") 0) :done)))
      (should (= 0 (length (org-workflow-panel--habits "2026-10-10"))))
      (should (eq :false (plist-get (aref (org-workflow-panel--habits "2026-10-11") 0) :done)))))))
