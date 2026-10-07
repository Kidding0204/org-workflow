;;; org-workflow-attempt-test.el --- Daily attempt feedback contracts -*- lexical-binding: t; -*-
(require 'ert)
(load (expand-file-name "org-workflow-store-test.el"
                        (file-name-directory (or load-file-name buffer-file-name))) nil t)
(require 'org-workflow-leave)
(require 'org-workflow-focus-timer)

(defmacro org-workflow-attempt-test (&rest body)
  `(org-workflow-store-test
    (let ((org-id-locations nil)
          (org-id-files nil)
          (org-id-locations-file (expand-file-name "ids" directory)))
      (cl-letf (((symbol-function 'org-workflow-store--now)
                 (lambda () "2026-09-16T10:00:00+08:00")))
        (org-workflow-store-set-meta "attempt-progress-since" "2026-09-16")
        ,@body))))

(defun org-workflow-attempt-test--clock (date minutes)
  "Add a closed, direct CLOCK at point for DATE and MINUTES."
  (save-excursion
    (org-back-to-heading t)
    (org-end-of-meta-data t)
    (insert (format ":LOGBOOK:\nCLOCK: [%s 10:00]--[%s 10:%02d] =>  0:%02d\n:END:\n"
                    date date minutes minutes))))

(ert-deftest workflow-attempt-unfulfilled-promise-carries-across-leave-days ()
  (org-workflow-attempt-test
   (org-workflow-store-create "2026-09-16")
   (org-workflow-store-put-leave
    '(:id "leave" :date "2026-09-16" :slots ["evening"]
      :reason "Away" :recordedAt "2026-09-16T23:00:00+08:00" :tasks []))
   (should (= 1 (plist-get (org-workflow-history-progress "2026-09-17") :minimumTotal)))
   (let ((record (org-workflow-history--compute "2026-09-17")))
     (should (equal "unmet" (plist-get record :commitment)))
     (org-workflow-store-put-day "2026-09-17" record))
   (cl-letf (((symbol-function 'org-workflow-target--today-string) (lambda () "2026-09-18")))
     (should (equal "2026-09-17" (org-workflow-leave--required-date))))
   (should (= 1 (length (org-workflow-leave--past-tasks "2026-09-18"))))))

(ert-deftest workflow-attempt-carried-promise-ends-after-first-valid-attempt ()
  (org-workflow-attempt-test
   (org-workflow-store-create "2026-09-16")
   (org-workflow-attempt-test--clock "2026-09-17" 5)
   (should (equal "unmet" (plist-get (org-workflow-history--compute "2026-09-16") :commitment)))
   (should (equal "met" (plist-get (org-workflow-history--compute "2026-09-17") :commitment)))
   (should-not (org-workflow-history--responsibilities "2026-09-18"))
   (should (equal "TODO" (org-get-todo-state)))))

(ert-deftest workflow-attempt-carried-promise-ends-after-goal-completion ()
  (org-workflow-attempt-test
   (let ((id (org-workflow-store-create "2026-09-16")))
     (cl-letf (((symbol-function 'org-workflow-store--now)
                (lambda () "2026-09-17T10:00:00+08:00")))
       (org-workflow-store--resolve (org-workflow-store-commitment id) "done"))
     (should (= 1 (length (org-workflow-history--responsibilities "2026-09-17"))))
     (should-not (org-workflow-history--responsibilities "2026-09-18")))))

(ert-deftest workflow-attempt-other-completions-do-not-discharge-carried-promise ()
  (org-workflow-attempt-test
   (org-workflow-store-create "2026-09-16")
   (cl-letf (((symbol-function 'org-workflow-history--tasks)
              (lambda (date)
                (when (equal date "2026-09-17")
                  '((:id "other" :task "Other" :outcome "done" :focusMinutes 0))))))
     (let ((record (org-workflow-history--compute "2026-09-17")))
       (should (equal "unmet" (plist-get record :commitment)))
       (should (= 1 (plist-get record :optionalCompleted)))))))

(ert-deftest workflow-attempt-cancelled-promise-does-not-carry ()
  (org-workflow-attempt-test
   (let ((id (org-workflow-store-create "2026-09-16")))
     (org-workflow-store--resolve (org-workflow-store-commitment id) "cancelled")
     (should-not (org-workflow-history--responsibilities "2026-09-16"))
     (should-not (org-workflow-history--responsibilities "2026-09-17")))))

(ert-deftest workflow-attempt-retained-five-minute-focus-keeps-task-unfinished ()
  (org-workflow-attempt-test
   (let* ((start (encode-time 0 0 10 16 9 2026))
          (end (encode-time 0 5 10 16 9 2026))
          (org-workflow-focus-timer-phase 'focus)
          (org-workflow-focus-timer-phase-start-time start)
          (org-workflow-focus-timer-minimum-recorded-minutes 5)
          (org-clock-in-hook nil) (org-clock-out-hook nil) (org-clock-cancel-hook nil)
          (org-clock-in-switch-to-state nil) (org-clock-out-switch-to-state nil))
     (unwind-protect
         (progn
           (org-clock-in nil start)
           (cl-letf (((symbol-function 'current-time) (lambda () end)))
             (org-workflow-focus-timer--close-focus-clock))
           (should (org-workflow-history-attempted-p "2026-09-16"))
           (should (equal "TODO" (org-get-todo-state)))
           (should-not (org-workflow-history-attempted-p "2026-09-17")))
       (when (org-clocking-p) (org-clock-cancel))))))

(ert-deftest workflow-attempt-cancelled-short-focus-does-not-count ()
  (org-workflow-attempt-test
   (let* ((start (encode-time 0 0 10 16 9 2026))
          (end (encode-time 0 2 10 16 9 2026))
          (org-workflow-focus-timer-phase 'focus)
          (org-workflow-focus-timer-phase-start-time start)
          (org-workflow-focus-timer-minimum-recorded-minutes 5)
          (org-clock-in-hook nil) (org-clock-out-hook nil) (org-clock-cancel-hook nil)
          (org-clock-in-switch-to-state nil))
     (unwind-protect
         (progn
           (org-clock-in nil start)
           (cl-letf (((symbol-function 'current-time) (lambda () end)))
             (org-workflow-focus-timer--close-focus-clock))
           (should-not (org-workflow--direct-clock-records))
           (should-not (org-workflow-history-attempted-p "2026-09-16")))
       (when (org-clocking-p) (org-clock-cancel))))))

(ert-deftest workflow-attempt-ignores-open-clock-and-descendants ()
  (org-workflow-attempt-test
   (let ((parent (point-marker)))
     (org-end-of-meta-data t)
     (insert ":LOGBOOK:\nCLOCK: [2026-09-16 10:00]\n:END:\n*** TODO Child\n:LOGBOOK:\nCLOCK: [2026-09-16 10:00]--[2026-09-16 10:25] =>  0:25\n:END:\n")
     (goto-char parent)
     (let ((org-clock-report-include-clocking-task t))
       (should-not (org-workflow-history-attempted-p "2026-09-16" parent)))
     (outline-next-heading)
     (should (org-workflow-history-attempted-p "2026-09-16")))))

(ert-deftest workflow-attempt-fulfills-promise-without-finishing-task ()
  (org-workflow-attempt-test
   (org-workflow-store-create "2026-09-16")
   (org-workflow-attempt-test--clock "2026-09-16" 5)
   (let* ((progress (org-workflow-history-progress "2026-09-16"))
          (record (org-workflow-history--compute "2026-09-16"))
          (task (aref (plist-get record :minimumTasks) 0)))
     (should (= 1 (plist-get progress :minimumSatisfied)))
     (should (eq t (plist-get progress :commitmentComplete)))
     (should (equal "met" (plist-get record :commitment)))
     (should (equal "pending" (plist-get task :outcome)))
     (should (eq t (plist-get task :satisfied)))
     (should (equal "TODO" (org-get-todo-state))))))

(ert-deftest workflow-attempt-respects-activation-and-sealed-history ()
  (org-workflow-attempt-test
   (org-workflow-store-create "2026-09-15")
   (org-workflow-attempt-test--clock "2026-09-15" 5)
   (should-not (org-workflow-history-attempt-enabled-p "2026-09-15"))
   (should (= 0 (plist-get (org-workflow-history-progress "2026-09-15") :minimumSatisfied)))
   (let ((sealed (org-workflow-history-finalize "2026-09-15")))
     (should (equal "unmet" (plist-get sealed :commitment)))
     (org-workflow-store-set-meta "attempt-progress-since" "2026-09-14")
     (should (= 1 (plist-get (org-workflow-history-progress "2026-09-15") :minimumSatisfied)))
     (should (equal sealed (org-workflow-history-finalize "2026-09-15"))))))

(ert-deftest workflow-attempt-yesterdays-focus-cannot-fulfill-tomorrows-promise ()
  (org-workflow-attempt-test
   (org-workflow-store-create "2026-09-17")
   (org-workflow-attempt-test--clock "2026-09-16" 5)
   (should (= 0 (plist-get (org-workflow-history-progress "2026-09-17") :minimumSatisfied)))
   (should (equal "unmet" (plist-get (org-workflow-history--compute "2026-09-17") :commitment)))
   (org-workflow-attempt-test--clock "2026-09-17" 5)
   (should (= 1 (plist-get (org-workflow-history-progress "2026-09-17") :minimumSatisfied)))
   (should (equal "met" (plist-get (org-workflow-history--compute "2026-09-17") :commitment)))))

(ert-deftest workflow-attempt-added-ordinary-task-advances-stage-progress ()
  (org-workflow-attempt-test
   (org-add-planning-info 'scheduled "2026-09-16")
   (org-priority ?A)
   (org-workflow-attempt-test--clock "2026-09-16" 5)
   (let ((stage (org-workflow--stage-progress "2026-09-16" (encode-time 0 0 10 16 9 2026))))
     (should (= 1 (plist-get stage :stageTotal)))
     (should (= 1 (plist-get stage :stageSatisfied)))
     (should (equal 'attempted (org-workflow--outcome-on-date "2026-09-16")))
     (should-not (org-workflow-store-promise-p))
     (should (equal "TODO" (org-get-todo-state))))))

(ert-deftest workflow-attempt-agenda-diamond-fills-only-on-target-day ()
  (org-workflow-attempt-test
   (org-workflow-store-create "2026-09-16")
   (let ((entry (org-workflow-target-entry-create :marker (point-marker)
                                           :title "Task" :priority (org-get-priority "[#A]"))))
     (cl-letf (((symbol-function 'org-workflow-agenda-target-date) (lambda () "2026-09-16")))
       (should (string-prefix-p "    ◇ Task" (org-workflow-agenda--stack-line entry nil)))
       (org-workflow-attempt-test--clock "2026-09-16" 5)
       (let ((line (org-workflow-agenda--stack-line entry nil)))
         (should (string-prefix-p "    ◆ Task" line))
         (should-not (get-text-property 6 'face line))
         (should (markerp (get-text-property 6 'org-hd-marker line)))))
     (cl-letf (((symbol-function 'org-workflow-agenda-target-date) (lambda () "2026-09-17")))
       (should (string-prefix-p "    ◇ Task" (org-workflow-agenda--stack-line entry nil)))))))

(ert-deftest workflow-attempt-held-without-focus-does-not-advance-new-stage ()
  (org-workflow-attempt-test
   (org-add-planning-info 'scheduled "2026-09-16")
   (org-priority ?A)
   (let ((org-log-done nil)) (org-todo "HOLD"))
   (org-add-planning-info 'closed "2026-09-16 10:00")
   (should (= 0 (plist-get (org-workflow--stage-progress
                           "2026-09-16" (encode-time 0 0 10 16 9 2026)) :stageSatisfied)))
   (org-workflow-attempt-test--clock "2026-09-16" 5)
   (should (= 1 (plist-get (org-workflow--stage-progress
                           "2026-09-16" (encode-time 0 0 10 16 9 2026)) :stageSatisfied)))))

(ert-deftest workflow-attempt-refreshes-both-panes-without-stealing-editor ()
  (let ((org-workflow-store-enabled t)
        (org-workflow-history--refresh-timer nil)
        (panes (list (generate-new-buffer " *attempt-pane-a*")
                     (generate-new-buffer " *attempt-pane-b*")))
        (ordinary (generate-new-buffer " *ordinary-agenda*"))
        callback refreshed)
    (unwind-protect
        (save-window-excursion
          (dolist (buffer (cons ordinary panes))
            (with-current-buffer buffer
              (setq major-mode 'org-agenda-mode)
              (setq-local org-workflow-agenda--sprint-buffer-p (memq buffer panes))))
          (let ((editor (window-buffer)))
            (cl-letf (((symbol-function 'run-at-time)
                       (lambda (_delay _repeat fn) (setq callback fn) 'pending))
                      ((symbol-function 'org-workflow-panel-invalidate) #'ignore)
                      ((symbol-function 'org-workflow--request-gnome-refresh) #'ignore)
                      ((symbol-function 'org-agenda-redo)
                       (lambda () (push (current-buffer) refreshed)
                         (switch-to-buffer (current-buffer)))))
              (org-workflow-history--refresh-after-clock)
              (should callback)
              (funcall callback)
              (should (equal (sort (mapcar #'buffer-name refreshed) #'string<)
                             (sort (mapcar #'buffer-name panes) #'string<)))
              (should (eq editor (window-buffer)))
              (should-not org-workflow-history--refresh-timer))))
      (mapc #'kill-buffer (cons ordinary panes)))))

(ert-deftest workflow-attempt-goal-completion-qualifies-without-a-clock ()
  (org-workflow-attempt-test
   (org-workflow-store-create "2026-09-16")
   (let ((org-log-done nil)) (org-todo "DONE"))
   (org-add-planning-info 'closed "2026-09-16 10:02")
   (should-not (org-workflow-history-attempted-p "2026-09-16"))
   (let ((record (org-workflow-history--compute "2026-09-16")))
     (should (equal "met" (plist-get record :commitment)))
     (should (equal "done" (plist-get (aref (plist-get record :minimumTasks) 0) :outcome)))
     (should (= 0 (plist-get record :focusTotalMinutes))))))

(ert-deftest workflow-attempt-sealed-fulfillment-does-not-demand-leave ()
  (org-workflow-attempt-test
   (org-workflow-store-put-day "2026-09-15"
                               '(:date "2026-09-15" :commitment "met"
                                 :minimumTasks [(:task "Tried yesterday" :outcome "pending" :satisfied t)]))
   (should-not (org-workflow-leave--required-date))
   (should (equal [] (org-workflow-leave--past-tasks "2026-09-15")))
   (org-workflow-store-put-day "2026-09-15"
                               '(:date "2026-09-15" :commitment "unmet"
                                 :minimumTasks [(:task "Tried yesterday" :outcome "pending" :satisfied t)
                                                (:task "Untouched" :outcome "pending" :satisfied :false)]))
   (should (equal "2026-09-15" (org-workflow-leave--required-date)))
   (should (equal "Untouched"
                  (plist-get (aref (org-workflow-leave--past-tasks "2026-09-15") 0) :task)))))

(provide 'org-workflow-attempt-test)
;;; org-workflow-attempt-test.el ends here
