;;; org-workflow-focus-timer-test.el --- Focus Timer tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'package)
(require 'seq)

(require 'org-workflow-focus-timer)

(ert-deftest org-workflow-focus-timer-embark-registers-start-action-for-org-headings ()
  "Embark's Org heading menu offers Focus Timer for agenda candidates."
  (require 'embark-org)
  (should (eq (keymap-lookup embark-org-heading-map "f")
              #'org-workflow-focus-timer-start))
  (should (memq #'embark-org--at-heading
                (alist-get #'org-workflow-focus-timer-start embark-around-action-hooks))))

(ert-deftest org-workflow-focus-timer-embark-org-heading-helper-uses-candidate-marker ()
  "The action context follows the marker carried by a Consult candidate."
  (require 'embark-org)
  (with-temp-buffer
    (org-mode)
    (insert "* Selected task\n")
    (goto-char (point-min))
    (let ((marker (point-marker))
          (target (propertize "* Selected task" 'org-marker (point-marker)))
          seen)
      (cl-letf (((symbol-function 'org-workflow-focus-timer-start)
                 (lambda () (setq seen (point)))))
        (embark-org--at-heading
         :run (lambda (&rest _args) (org-workflow-focus-timer-start))
         :target target))
      (should (= seen (marker-position marker))))))

(ert-deftest org-workflow-focus-timer-next-break-follows-completed-count ()
  "A wrong modulo branch would select the wrong break after Focus."
  (let ((org-workflow-focus-timer-long-break-interval 4))
    (should (eq (org-workflow-focus-timer--next-break-phase 1) 'short-break))
    (should (eq (org-workflow-focus-timer--next-break-phase 4) 'long-break))))

(ert-deftest org-workflow-focus-timer-deadline-only-marks-current-phase-expired ()
  "A hard deadline transition would change phase or increment the cycle."
  (let ((org-workflow-focus-timer-phase 'focus)
        (org-workflow-focus-timer-expired-p nil)
        (org-workflow-focus-timer-target-minutes 25)
        (org-workflow-focus-timer-completed-count 3)
        sound-phase)
    (cl-letf (((symbol-function 'org-workflow-focus-timer--play-phase-sound)
               (lambda () (setq sound-phase org-workflow-focus-timer-phase)))
              ((symbol-function 'org-workflow-focus-timer--refresh-display) #'ignore))
      (org-workflow-focus-timer--deadline)
      (should org-workflow-focus-timer-expired-p)
      (should (eq org-workflow-focus-timer-phase 'focus))
      (should (= org-workflow-focus-timer-completed-count 3))
      (should (eq sound-phase 'focus)))))

(ert-deftest org-workflow-focus-timer-phase-sounds-distinguish-focus-and-break ()
  "Automatic Focus and break reminders must request distinct theme events."
  (let (arguments)
    (cl-letf (((symbol-function 'start-process)
               (lambda (&rest args) (setq arguments args))))
      (let ((org-workflow-focus-timer-phase 'focus)
            (org-workflow-focus-timer-focus-sound-event "complete"))
        (org-workflow-focus-timer--play-phase-sound)
        (should (equal arguments
                       '("org-workflow-focus-timer-sound" nil "canberra-gtk-play" "-i"
                         "complete"))))
      (let ((org-workflow-focus-timer-phase 'short-break)
            (org-workflow-focus-timer-break-sound-event "message"))
        (org-workflow-focus-timer--play-phase-sound)
        (should (equal arguments
                       '("org-workflow-focus-timer-sound" nil "canberra-gtk-play" "-i"
                         "message")))))))

(ert-deftest org-workflow-focus-timer-status-text-uses-whole-minutes ()
  "A seconds-based or elapsed display would violate the compact contract."
  (let ((org-workflow-focus-timer-phase 'focus)
        (org-workflow-focus-timer-phase-start-time (seconds-to-time 1000))
        (org-workflow-focus-timer-target-minutes 25)
        (org-workflow-focus-timer-expired-p nil))
    (cl-letf (((symbol-function 'current-time)
               (lambda () (seconds-to-time (+ 1000 (* 7 60))))))
      (should (equal (org-workflow-focus-timer-status-text) "F 18m")))))

(ert-deftest org-workflow-focus-timer-status-text-shows-overtime-as-data ()
  "A separate overtime phase or countdown would format the status incorrectly."
  (let ((org-workflow-focus-timer-phase 'focus)
        (org-workflow-focus-timer-phase-start-time (seconds-to-time 1000))
        (org-workflow-focus-timer-target-minutes 25)
        (org-workflow-focus-timer-expired-p t))
    (cl-letf (((symbol-function 'current-time)
               (lambda () (seconds-to-time (+ 1000 (* 37 60))))))
      (should (equal (org-workflow-focus-timer-status-text) "F +12m")))))

(ert-deftest org-workflow-focus-timer-gnome-sync-is-a-failure-tolerant-empty-signal ()
  "The GNOME wake-up must never carry timer state or interrupt Focus Timer."
  (let (arguments)
    (cl-letf (((symbol-function 'dbus-send-signal)
               (lambda (&rest values) (setq arguments values))))
      (org-workflow-focus-timer--request-gnome-refresh)
      (should
       (equal arguments
              (list :session
                    nil
                    org-workflow-focus-timer-gnome-sync-object-path
                    org-workflow-focus-timer-gnome-sync-interface
                    "Changed"))))
    (cl-letf (((symbol-function 'dbus-send-signal)
               (lambda (&rest _values) (error "session bus unavailable"))))
      (should-not (org-workflow-focus-timer--request-gnome-refresh)))))

(ert-deftest org-workflow-focus-timer-state-transitions-wake-the-gnome-extension ()
  "Phase changes and deadlines must request an immediate reread."
  (should (member #'org-workflow-focus-timer--request-gnome-refresh
                  org-workflow-focus-timer-phase-changed-hook))
  (should (member #'org-workflow-focus-timer--request-gnome-refresh
                  org-workflow-focus-timer-deadline-hook)))

(ert-deftest org-workflow-focus-timer-enter-phase-schedules-minute-events ()
  "A seconds tick or wrong offset would violate the minute schedule."
  (let ((org-workflow-focus-timer-focus-duration 25)
        (org-workflow-focus-timer-focus-overtime-reminder-interval 10)
        (org-workflow-focus-timer-phase nil)
        (org-workflow-focus-timer-phase-start-time nil)
        (org-workflow-focus-timer-target-minutes nil)
        (org-workflow-focus-timer-expired-p nil)
        (org-workflow-focus-timer--deadline-timer nil)
        (org-workflow-focus-timer--overtime-timer nil)
        (org-workflow-focus-timer--display-timer nil)
        scheduled)
    (cl-letf (((symbol-function 'run-at-time)
               (lambda (time repeat function &rest _arguments)
                 (push (list time repeat function) scheduled)
                 (list function)))
              ((symbol-function 'timerp) (lambda (_value) nil))
              ((symbol-function 'force-mode-line-update) #'ignore))
      (org-workflow-focus-timer--enter-phase 'focus)
      (should (member '(1500 nil org-workflow-focus-timer--deadline) scheduled))
      (should (member '(2100 600 org-workflow-focus-timer--overtime-reminder) scheduled))
      (should (member '(60 60 org-workflow-focus-timer--refresh-display) scheduled)))))

(ert-deftest org-workflow-focus-timer-nil-overtime-interval-schedules-no-repeat ()
  "A nil reminder interval must not accidentally create a repeat timer."
  (let ((org-workflow-focus-timer-focus-overtime-reminder-interval nil)
        (org-workflow-focus-timer-phase nil)
        (org-workflow-focus-timer-phase-start-time nil)
        (org-workflow-focus-timer-target-minutes nil)
        (org-workflow-focus-timer-expired-p nil)
        (org-workflow-focus-timer--deadline-timer nil)
        (org-workflow-focus-timer--overtime-timer nil)
        (org-workflow-focus-timer--display-timer nil)
        scheduled)
    (cl-letf (((symbol-function 'run-at-time)
               (lambda (time repeat function &rest _arguments)
                 (push (list time repeat function) scheduled)
                 (list function)))
              ((symbol-function 'timerp) (lambda (_value) nil))
              ((symbol-function 'force-mode-line-update) #'ignore))
      (org-workflow-focus-timer--enter-phase 'focus)
      (should-not
       (seq-find (lambda (item)
                   (eq (nth 2 item) 'org-workflow-focus-timer--overtime-reminder))
                 scheduled)))))

(defmacro org-workflow-focus-timer-test-with-org-task (&rest body)
  "Run BODY on TASK-MARKER with real Org Clock and inert timer objects."
  (declare (indent 0) (debug t))
  `(let ((org-clock-persist nil)
         (org-clock-out-remove-zero-time-clocks nil)
         (org-workflow-focus-timer-phase nil)
         (org-workflow-focus-timer-phase-start-time nil)
         (org-workflow-focus-timer-target-minutes nil)
         (org-workflow-focus-timer-expired-p nil)
         (org-workflow-focus-timer-completed-count 0)
         (org-workflow-focus-timer-task-marker nil))
     (with-temp-buffer
       (org-mode)
       (insert "* TODO Focus me\n")
       (goto-char (point-min))
       (let ((task-marker (copy-marker (point))))
         (unwind-protect
             (cl-letf (((symbol-function 'force-mode-line-update) #'ignore)
                       ((symbol-function 'org-agenda-maybe-redo) #'ignore)
                       ((symbol-function 'org-workflow-focus-timer--notify) #'ignore))
               ,@body)
           (when (org-clocking-p)
             (let ((org-workflow-focus-timer--clock-operation t))
               (org-clock-cancel)))
           (org-workflow-focus-timer--clear-state))))))

(ert-deftest org-workflow-focus-timer-start-marker-creates-real-org-clock ()
  "Replacing Org Clock with private state would leave no CLOCK line."
  (org-workflow-focus-timer-test-with-org-task
    (org-workflow-focus-timer-start task-marker)
    (should (org-clocking-p))
    (should (eq (marker-buffer org-workflow-focus-timer-task-marker)
                (current-buffer)))
    (should (= (marker-position org-workflow-focus-timer-task-marker)
               (marker-position org-clock-hd-marker)))
    (goto-char (point-min))
    (should (re-search-forward "^[[:space:]]*CLOCK: \\[" nil t))))

(ert-deftest org-workflow-focus-timer-record-last-pomodoro-adds-a-closed-25-minute-clock ()
  "Retrospective Pomodoros remain ordinary Org CLOCK records."
  (org-workflow-focus-timer-test-with-org-task
    (let ((now (encode-time 0 0 12 1 9 2026)))
      (cl-letf (((symbol-function 'current-time) (lambda () now)))
        (should (= 25 (org-workflow-focus-timer-record-last-pomodoro task-marker)))))
    (should-not (org-clocking-p))
    (should-not org-workflow-focus-timer-phase)
    (should (= org-workflow-focus-timer-completed-count 0))
    (goto-char (point-min))
    (should (re-search-forward
             "CLOCK: .*11:35.*--.*12:00.*=>[[:space:]]+0:25"
             nil t))))

(ert-deftest org-workflow-focus-timer-record-last-pomodoro-preserves-an-active-clock ()
  "Backfilling must not truncate an already running Org clock."
  (org-workflow-focus-timer-test-with-org-task
    (let ((org-workflow-focus-timer--clock-operation t))
      (org-with-point-at task-marker
        (org-clock-in)))
    (let ((active-clock-marker (copy-marker org-clock-marker)))
      (should-error (org-workflow-focus-timer-record-last-pomodoro task-marker)
                    :type 'user-error)
      (should (org-clocking-p))
      (should (= (marker-position org-clock-marker)
                 (marker-position active-clock-marker))))))

(ert-deftest org-workflow-focus-timer-finish-focus-clocks-out-and-starts-break ()
  "A hard or fake transition would omit the real clock end or break phase."
  (org-workflow-focus-timer-test-with-org-task
    (let ((now (encode-time 0 0 12 1 9 2026))
          (org-workflow-focus-timer-minimum-recorded-minutes 5))
      (cl-letf (((symbol-function 'current-time) (lambda () now))
                ((symbol-function 'org-current-time)
                 (lambda (&rest _arguments) now)))
        (org-workflow-focus-timer-start task-marker)
        (setq now (time-add now (seconds-to-time 300)))
        (org-workflow-focus-timer-finish-phase)))
    (should-not (org-clocking-p))
    (should (= org-workflow-focus-timer-completed-count 1))
    (should (eq org-workflow-focus-timer-phase 'short-break))
    (goto-char (point-min))
    (should (re-search-forward "CLOCK: .*=>[[:space:]]+0:05" nil t))))

(ert-deftest org-workflow-focus-timer-fourth-finish-starts-long-break ()
  "An off-by-one cycle counter would choose a short fourth break."
  (org-workflow-focus-timer-test-with-org-task
    (setq org-workflow-focus-timer-completed-count 3)
    (org-workflow-focus-timer-start task-marker)
    (org-workflow-focus-timer-finish-phase)
    (should (= org-workflow-focus-timer-completed-count 4))
    (should (eq org-workflow-focus-timer-phase 'long-break))))

(ert-deftest org-workflow-focus-timer-finish-break-resumes-real-clock-on-same-task ()
  "A detached next Focus would resume the phase without its Org clock."
  (org-workflow-focus-timer-test-with-org-task
    (org-workflow-focus-timer-start task-marker)
    (org-workflow-focus-timer-finish-phase)
    (org-workflow-focus-timer-finish-phase)
    (should (eq org-workflow-focus-timer-phase 'focus))
    (should (org-clocking-p))
    (should (= (marker-position org-workflow-focus-timer-task-marker)
               (marker-position org-clock-hd-marker)))))

(ert-deftest org-workflow-focus-timer-toggle-starts-an-inactive-cycle-on-the-given-task ()
  "Ignoring MARKER would make a desktop toggle prompt for an unavailable context."
  (org-workflow-focus-timer-test-with-org-task
    (org-workflow-focus-timer-toggle task-marker)
    (should (eq org-workflow-focus-timer-phase 'focus))
    (should (org-clocking-p))
    (should (= (marker-position org-workflow-focus-timer-task-marker)
               (marker-position task-marker)))))

(ert-deftest org-workflow-focus-timer-toggle-stops-an-unexpired-focus-without-a-break ()
  "Treating an early stop as completion would incorrectly begin a break."
  (org-workflow-focus-timer-test-with-org-task
    (org-workflow-focus-timer-start task-marker)
    (org-workflow-focus-timer-toggle)
    (should-not org-workflow-focus-timer-phase)
    (should-not (org-clocking-p))
    (should (= org-workflow-focus-timer-completed-count 0))))

(ert-deftest org-workflow-focus-timer-toggle-finishes-focus-overflow-into-a-break ()
  "Stopping overflow outright would lose the completed cycle transition."
  (org-workflow-focus-timer-test-with-org-task
    (org-workflow-focus-timer-start task-marker)
    (setq org-workflow-focus-timer-expired-p t)
    (org-workflow-focus-timer-toggle)
    (should (eq org-workflow-focus-timer-phase 'short-break))
    (should-not (org-clocking-p))
    (should (= org-workflow-focus-timer-completed-count 1))))

(ert-deftest org-workflow-focus-timer-toggle-ends-an-active-break-into-focus ()
  "An unexpired break must still be skippable with the unified switch."
  (org-workflow-focus-timer-test-with-org-task
    (org-workflow-focus-timer-start task-marker)
    (org-workflow-focus-timer-finish-phase)
    (org-workflow-focus-timer-toggle)
    (should (eq org-workflow-focus-timer-phase 'focus))
    (should (org-clocking-p))))

(ert-deftest org-workflow-focus-timer-toggle-ends-break-overflow-into-focus ()
  "Break overflow must follow the same next-Focus transition as an active break."
  (org-workflow-focus-timer-test-with-org-task
    (org-workflow-focus-timer-start task-marker)
    (org-workflow-focus-timer-finish-phase)
    (setq org-workflow-focus-timer-expired-p t)
    (org-workflow-focus-timer-toggle)
    (should (eq org-workflow-focus-timer-phase 'focus))
    (should (org-clocking-p))))

(ert-deftest org-workflow-focus-timer-toggle-discards-immediate-focus-created-from-break ()
  "Stopping the Focus entered from break must not leave a second zero clock."
  (org-workflow-focus-timer-test-with-org-task
    (let ((now (encode-time 0 0 12 1 9 2026))
          (org-workflow-focus-timer-minimum-recorded-minutes 5))
      (cl-letf (((symbol-function 'current-time) (lambda () now))
                ((symbol-function 'org-current-time)
                 (lambda (&rest _arguments) now)))
        (org-workflow-focus-timer-start task-marker)
        (setq now (time-add now (seconds-to-time 300)))
        (org-workflow-focus-timer-finish-phase)
        (org-workflow-focus-timer-toggle)
        (org-workflow-focus-timer-toggle)))
    (should-not org-workflow-focus-timer-phase)
    (should-not (org-clocking-p))
    (goto-char (point-min))
    (should (= 1 (how-many "^[[:space:]]*CLOCK:" (point-min) (point-max))))))

(ert-deftest org-workflow-focus-timer-finish-phase-discards-a-focus-under-five-minutes ()
  "The explicit finish path must not bypass the minimum clock duration."
  (org-workflow-focus-timer-test-with-org-task
    (let ((now (encode-time 0 0 12 1 9 2026))
          (org-workflow-focus-timer-minimum-recorded-minutes 5))
      (cl-letf (((symbol-function 'current-time) (lambda () now))
                ((symbol-function 'org-current-time)
                 (lambda (&rest _arguments) now)))
        (org-workflow-focus-timer-start task-marker)
        (setq now (time-add now (seconds-to-time 240)))
        (org-workflow-focus-timer-finish-phase)))
    (should (eq org-workflow-focus-timer-phase 'short-break))
    (should (= org-workflow-focus-timer-completed-count 1))
    (goto-char (point-min))
    (should-not (re-search-forward "^[[:space:]]*CLOCK:" nil t))))

(ert-deftest org-workflow-focus-timer-stop-closes-clock-without-starting-break ()
  "Stopping at the threshold must retain elapsed time but start no break."
  (org-workflow-focus-timer-test-with-org-task
    (let ((now (encode-time 0 0 12 1 9 2026))
          (org-workflow-focus-timer-minimum-recorded-minutes 5))
      (cl-letf (((symbol-function 'current-time) (lambda () now))
                ((symbol-function 'org-current-time)
                 (lambda (&rest _arguments) now)))
        (org-workflow-focus-timer-start task-marker)
        (setq now (time-add now (seconds-to-time 300)))
        (org-workflow-focus-timer-stop)))
    (should-not (org-clocking-p))
    (should-not org-workflow-focus-timer-phase)
    (should (= org-workflow-focus-timer-completed-count 0))
    (goto-char (point-min))
    (should (re-search-forward "CLOCK: .*=>[[:space:]]+0:05" nil t))))

(ert-deftest org-workflow-focus-timer-cancel-removes-current-org-clock ()
  "Cancel must use Org Clock cancel rather than preserving a zero interval."
  (org-workflow-focus-timer-test-with-org-task
    (org-workflow-focus-timer-start task-marker)
    (org-workflow-focus-timer-cancel)
    (should-not (org-clocking-p))
    (should-not org-workflow-focus-timer-phase)
    (goto-char (point-min))
    (should-not (re-search-forward "CLOCK:" nil t))))

(ert-deftest org-workflow-focus-timer-reset-clears-completed-count ()
  "Reset must differ from stop by clearing the completed Focus count."
  (org-workflow-focus-timer-test-with-org-task
    (setq org-workflow-focus-timer-completed-count 3)
    (org-workflow-focus-timer-start task-marker)
    (org-workflow-focus-timer-reset)
    (should-not org-workflow-focus-timer-phase)
    (should (= org-workflow-focus-timer-completed-count 0))))

(ert-deftest org-workflow-focus-timer-start-from-agenda-uses-source-heading ()
  "Agenda interaction must clock the source heading, not the Agenda buffer."
  (let ((source (generate-new-buffer " *org-workflow-focus-timer-agenda-source*"))
        (org-workflow-focus-timer-phase nil)
        source-marker clocked-marker)
    (unwind-protect
        (progn
          (with-current-buffer source
            (org-mode)
            (insert "* TODO Agenda task\n")
            (setq source-marker (copy-marker (point-min))))
          (with-temp-buffer
            (setq major-mode 'org-agenda-mode)
            (cl-letf (((symbol-function 'org-get-at-bol)
                       (lambda (_property) source-marker))
                      ((symbol-function 'org-clock-in)
                       (lambda (&rest _arguments)
                         (setq org-clock-hd-marker (copy-marker (point))
                               clocked-marker (copy-marker (point)))))
                      ((symbol-function 'org-workflow-focus-timer--enter-phase)
                       (lambda (phase)
                         (setq org-workflow-focus-timer-phase phase
                               org-workflow-focus-timer-phase-start-time (current-time)
                               org-workflow-focus-timer-target-minutes 25))))
              (org-workflow-focus-timer-start)
              (should (eq (marker-buffer clocked-marker) source))
              (should (= (marker-position clocked-marker)
                         (marker-position source-marker))))))
      (when (buffer-live-p source)
        (kill-buffer source)))))

(ert-deftest org-workflow-focus-timer-start-outside-org-selects-recent-task ()
  "Outside Org, task resolution must use Org's recent task selector."
  (let ((source (generate-new-buffer " *org-workflow-focus-timer-recent-source*"))
        (org-workflow-focus-timer-phase nil)
        source-marker clocked-marker)
    (unwind-protect
        (progn
          (with-current-buffer source
            (org-mode)
            (insert "* TODO Recent task\n")
            (setq source-marker (copy-marker (point-min))))
          (with-temp-buffer
            (fundamental-mode)
            (cl-letf (((symbol-function 'org-clock-select-task)
                       (lambda (&rest _arguments) source-marker))
                      ((symbol-function 'org-clock-in)
                       (lambda (&rest _arguments)
                         (setq org-clock-hd-marker (copy-marker (point))
                               clocked-marker (copy-marker (point)))))
                      ((symbol-function 'org-workflow-focus-timer--enter-phase)
                       (lambda (phase)
                         (setq org-workflow-focus-timer-phase phase
                               org-workflow-focus-timer-phase-start-time (current-time)
                               org-workflow-focus-timer-target-minutes 25))))
              (org-workflow-focus-timer-start)
              (should (eq (marker-buffer clocked-marker) source))
              (should (= (marker-position clocked-marker)
                         (marker-position source-marker))))))
      (when (buffer-live-p source)
        (kill-buffer source)))))

(ert-deftest org-workflow-focus-timer-universal-prefix-selects-recent-task ()
  "A single universal prefix must select a recent task like Org Clock."
  (let ((source (generate-new-buffer " *org-workflow-focus-timer-prefix-source*"))
        (org-workflow-focus-timer-phase nil)
        selected-marker clocked-marker)
    (unwind-protect
        (progn
          (with-current-buffer source
            (org-mode)
            (insert "* TODO Current\n* TODO Selected\n")
            (goto-char (point-min))
            (re-search-forward "^\\* TODO Selected")
            (setq selected-marker (copy-marker (line-beginning-position)))
            (goto-char (point-min))
            (cl-letf (((symbol-function 'org-clock-select-task)
                       (lambda (&rest _arguments) selected-marker))
                      ((symbol-function 'org-clock-in)
                       (lambda (&rest _arguments)
                         (setq org-clock-hd-marker (copy-marker (point))
                               clocked-marker (copy-marker (point)))))
                      ((symbol-function 'org-workflow-focus-timer--enter-phase)
                       (lambda (phase)
                         (setq org-workflow-focus-timer-phase phase
                               org-workflow-focus-timer-phase-start-time (current-time)
                               org-workflow-focus-timer-target-minutes 25))))
              (org-workflow-focus-timer-start nil '(4))
              (should (= (marker-position clocked-marker)
                         (marker-position selected-marker))))))
      (when (buffer-live-p source)
        (kill-buffer source)))))

(ert-deftest org-workflow-focus-timer-start-declined-replacement-keeps-current-cycle ()
  "Declining the conventional replacement prompt must leave state untouched."
  (let ((org-workflow-focus-timer-phase 'focus)
        (org-workflow-focus-timer-phase-start-time (current-time))
        (org-workflow-focus-timer-target-minutes 25)
        stopped selected)
    (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) nil))
              ((symbol-function 'org-workflow-focus-timer-stop)
               (lambda () (setq stopped t)))
              ((symbol-function 'org-workflow-focus-timer--context-marker)
               (lambda () (setq selected t))))
      (should (stringp (org-workflow-focus-timer-start)))
      (should-not stopped)
      (should-not selected)
      (should (eq org-workflow-focus-timer-phase 'focus)))))

(ert-deftest org-workflow-focus-timer-start-last-uses-org-clock-history ()
  "Continue must delegate selection semantics to `org-clock-in-last'."
  (let ((org-workflow-focus-timer-phase nil)
        received-prefix)
    (with-temp-buffer
      (org-mode)
      (insert "* TODO Last task\n")
      (goto-char (point-min))
      (cl-letf (((symbol-function 'org-clock-in-last)
                 (lambda (&optional prefix)
                   (setq received-prefix prefix
                         org-clock-hd-marker (copy-marker (point)))))
                ((symbol-function 'org-workflow-focus-timer--enter-phase)
                 (lambda (phase)
                   (setq org-workflow-focus-timer-phase phase
                         org-workflow-focus-timer-phase-start-time (current-time)
                         org-workflow-focus-timer-target-minutes 25))))
        (org-workflow-focus-timer-start-last '(4))
        (should (equal received-prefix '(4)))
        (should (eq org-workflow-focus-timer-phase 'focus))
        (should (= (marker-position org-workflow-focus-timer-task-marker) (point-min)))))))

(ert-deftest org-workflow-focus-timer-external-clock-out-clears-focus-state ()
  "Raw Org clock termination must not leave a detached Focus phase."
  (let ((org-workflow-focus-timer-phase 'focus)
        (org-workflow-focus-timer--clock-operation nil)
        cleared)
    (cl-letf (((symbol-function 'org-workflow-focus-timer--clear-state)
               (lambda () (setq cleared t org-workflow-focus-timer-phase nil))))
      (org-workflow-focus-timer--after-external-clock-out)
      (should cleared)
      (should-not org-workflow-focus-timer-phase))))

(ert-deftest org-workflow-focus-timer-owned-clock-out-keeps-transition-state ()
  "The reconciliation hook must ignore timer-owned clock operations."
  (let ((org-workflow-focus-timer-phase 'focus)
        (org-workflow-focus-timer--clock-operation t)
        cleared)
    (cl-letf (((symbol-function 'org-workflow-focus-timer--clear-state)
               (lambda () (setq cleared t org-workflow-focus-timer-phase nil))))
      (org-workflow-focus-timer--after-external-clock-out)
      (should-not cleared)
      (should (eq org-workflow-focus-timer-phase 'focus)))))

(ert-deftest org-workflow-focus-timer-break-stop-does-not-touch-org-clock ()
  "Break phases are timer state only and must never write clock data."
  (let ((org-workflow-focus-timer-phase 'short-break)
        clock-called)
    (cl-letf (((symbol-function 'org-clocking-p) (lambda () t))
              ((symbol-function 'org-clock-out)
               (lambda (&rest _arguments) (setq clock-called t)))
              ((symbol-function 'org-workflow-focus-timer--clear-state)
               (lambda () (setq org-workflow-focus-timer-phase nil))))
      (org-workflow-focus-timer-stop)
      (should-not clock-called))))

(ert-deftest org-workflow-focus-timer-status-json-is-stable-and-minute-based ()
  "External consumers need JSON values rather than printed Lisp state."
  (let ((org-workflow-focus-timer-phase 'focus)
        (org-workflow-focus-timer-phase-start-time (seconds-to-time 1000))
        (org-workflow-focus-timer-target-minutes 25)
        (org-workflow-focus-timer-completed-count 2)
        (org-workflow-focus-timer-expired-p nil))
    (cl-letf (((symbol-function 'current-time)
               (lambda () (seconds-to-time (+ 1000 (* 7 60))))))
      (should
       (equal (json-parse-string (org-workflow-focus-timer-status-json)
                                 :object-type 'plist)
              '(:phase "focus" :elapsed 7 :target 25
                :completed 2 :expired :false))))))

(ert-deftest org-workflow-focus-timer-notify-status-uses-printable-status ()
  "The emacsclient status command must return what it notifies."
  (let (notification)
    (cl-letf (((symbol-function 'org-workflow-focus-timer-status-text)
               (lambda () "F +10m"))
              ((symbol-function 'org-workflow-focus-timer--notify)
               (lambda (title body) (setq notification (list title body)))))
      (should (equal (org-workflow-focus-timer-notify-status) "F +10m"))
      (should (equal notification '("Focus Timer" "F +10m"))))))

(ert-deftest org-workflow-focus-timer-notify-falls-back-to-message ()
  "Desktop notification failure must still surface the same information."
  (let (fallback)
    (cl-letf (((symbol-function 'notifications-notify)
               (lambda (&rest _arguments) (error "No desktop bus")))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (setq fallback (apply #'format format-string arguments)))))
      (provide 'notifications)
      (org-workflow-focus-timer--notify "Focus target" "Continue naturally.")
      (should (equal fallback "Focus target: Continue naturally.")))))

(provide 'org-workflow-focus-timer-test)
;;; org-workflow-focus-timer-test.el ends here
