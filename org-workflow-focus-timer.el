;;; org-workflow-focus-timer.el --- focus-timer Workflow component -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Jinwang Dong
;; Author: Jinwang Dong <dongjinwang040204@gmail.com>
;; Assisted-by: Codex:GPT-6
;; SPDX-License-Identifier: GPL-3.0-or-later
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;; Commentary:
;; A component of org-workflow.  Activation is coordinated by its global mode.
;;; Code:
(require 'org-workflow-lifecycle)
;;; org-workflow-focus-timer.el --- Soft-boundary focus cycle for Org -*- lexical-binding: t; -*-

;;; Code:

(require 'cl-lib)

(require 'json)

(require 'org)

(require 'org-agenda)

(require 'org-clock)

(require 'timer)

(defgroup org-workflow-focus-timer nil
  "Soft-boundary focus cycles backed by Org Clock."
  :group 'org-clock)

(defcustom org-workflow-focus-timer-focus-duration 25
  "Target Focus duration in minutes."
  :type '(integer :tag "Minutes")
  :group 'org-workflow-focus-timer)

(defconst org-workflow-focus-timer-pomodoro-minutes 25
  "Length of a retrospectively recorded Pomodoro, in minutes.")

(defcustom org-workflow-focus-timer-short-break-duration 5
  "Target short-break duration in minutes."
  :type '(integer :tag "Minutes")
  :group 'org-workflow-focus-timer)

(defcustom org-workflow-focus-timer-long-break-duration 15
  "Target long-break duration in minutes."
  :type '(integer :tag "Minutes")
  :group 'org-workflow-focus-timer)

(defcustom org-workflow-focus-timer-long-break-interval 4
  "Normally completed Focus phases before a long break."
  :type '(integer :tag "Focus phases")
  :group 'org-workflow-focus-timer)

(defcustom org-workflow-focus-timer-minimum-recorded-minutes 5
  "Minimum Focus length retained as an Org CLOCK entry.

A Focus interval shorter than this many elapsed minutes is canceled instead
of clocked out.  The boundary itself is retained.  Set this to 0 to keep every
Focus interval."
  :type 'natnum
  :group 'org-workflow-focus-timer)

(defcustom org-workflow-focus-timer-focus-overtime-reminder-interval 10
  "Minutes between Focus overtime reminders, or nil."
  :type '(choice (const :tag "Disabled" nil)
                 (integer :tag "Minutes"))
  :group 'org-workflow-focus-timer)

(defcustom org-workflow-focus-timer-break-overtime-reminder-interval 5
  "Minutes between break overtime reminders, or nil."
  :type '(choice (const :tag "Disabled" nil)
                 (integer :tag "Minutes"))
  :group 'org-workflow-focus-timer)

(defcustom org-workflow-focus-timer-focus-sound-event "complete"
  "Freedesktop sound event played when a Focus phase needs attention.

Set this to nil to silence automatic Focus reminders."
  :type '(choice (const :tag "Disabled" nil) string)
  :group 'org-workflow-focus-timer)

(defcustom org-workflow-focus-timer-break-sound-event "message"
  "Freedesktop sound event played when a break phase needs attention.

Set this to nil to silence automatic break reminders."
  :type '(choice (const :tag "Disabled" nil) string)
  :group 'org-workflow-focus-timer)

(defvar org-workflow-focus-timer-phase nil
  "Current phase, or nil when Focus Timer is inactive.")

(defvar org-workflow-focus-timer-phase-start-time nil
  "Absolute start time of the current phase.")

(defvar org-workflow-focus-timer-target-minutes nil
  "Target duration of the current phase in minutes.")

(defvar org-workflow-focus-timer-expired-p nil
  "Non-nil after the current phase reaches its target.")

(defvar org-workflow-focus-timer-completed-count 0
  "Number of normally completed Focus phases.")

(defvar org-workflow-focus-timer-task-marker nil
  "Marker for the Org task attached to the current Focus cycle.")

(defvar org-workflow-focus-timer--deadline-timer nil)

(defvar org-workflow-focus-timer--overtime-timer nil)

(defvar org-workflow-focus-timer--display-timer nil)

(defvar org-workflow-focus-timer--clock-operation nil)

(defconst org-workflow-focus-timer-gnome-sync-object-path
  "/io/github/meph1st0/FocusTimer"
  "Session D-Bus object path used to wake the GNOME Focus Timer extension.")

(defconst org-workflow-focus-timer-gnome-sync-interface
  "io.github.meph1st0.FocusTimer"
  "Session D-Bus interface used to wake the GNOME Focus Timer extension.")

(defvar org-workflow-focus-timer-phase-changed-hook nil
  "Hook run after the Focus Timer phase changes.")

(defvar org-workflow-focus-timer-deadline-hook nil
  "Hook run when a Focus Timer phase reaches its target.")

(defvar org-workflow-focus-timer-stopped-hook nil
  "Hook run after the Focus Timer is stopped.")

(defun org-workflow-focus-timer-active-p ()
  "Return non-nil when a Focus Timer phase is active."
  (memq org-workflow-focus-timer-phase '(focus short-break long-break)))

(defun org-workflow-focus-timer--duration-for-phase (phase)
  "Return target duration in minutes for PHASE."
  (pcase phase
    ('focus org-workflow-focus-timer-focus-duration)
    ('short-break org-workflow-focus-timer-short-break-duration)
    ('long-break org-workflow-focus-timer-long-break-duration)
    (_ (user-error "No active Focus Timer phase"))))

(defun org-workflow-focus-timer--next-break-phase (completed-count)
  "Return the break phase after COMPLETED-COUNT Focus phases."
  (if (zerop (% completed-count org-workflow-focus-timer-long-break-interval))
      'long-break
    'short-break))

(defun org-workflow-focus-timer--elapsed-minutes (&optional now)
  "Return whole elapsed minutes at NOW for the current phase."
  (floor (float-time
          (time-subtract (or now (current-time))
                         org-workflow-focus-timer-phase-start-time))
         60))

(defun org-workflow-focus-timer-status ()
  "Return a stable plist describing the current Focus Timer state."
  (list :phase (or org-workflow-focus-timer-phase 'inactive)
        :elapsed (if org-workflow-focus-timer-phase-start-time
                     (org-workflow-focus-timer--elapsed-minutes)
                   0)
        :target (or org-workflow-focus-timer-target-minutes 0)
        :completed org-workflow-focus-timer-completed-count
        :expired (and org-workflow-focus-timer-expired-p t)))

(defun org-workflow-focus-timer-status-text ()
  "Return compact minute-based text for the current phase."
  (if (not (org-workflow-focus-timer-active-p))
      "inactive"
    (let* ((elapsed (org-workflow-focus-timer--elapsed-minutes))
           (prefix (pcase org-workflow-focus-timer-phase
                     ('focus "F")
                     ('short-break "B")
                     ('long-break "L")))
           (minutes (if org-workflow-focus-timer-expired-p
                        (format "+%dm" (max 0 (- elapsed org-workflow-focus-timer-target-minutes)))
                      (format "%dm" (max 0 (- org-workflow-focus-timer-target-minutes elapsed))))))
      (format "%s %s" prefix minutes))))

;;;###autoload
(defun org-workflow-focus-timer-status-json ()
  "Return the current Focus Timer status as stable JSON."
  (let ((status (org-workflow-focus-timer-status)))
    (json-serialize
     (list :phase (symbol-name (plist-get status :phase))
           :elapsed (plist-get status :elapsed)
           :target (plist-get status :target)
           :completed (plist-get status :completed)
           :expired (if (plist-get status :expired) t :false)))))

(defun org-workflow-focus-timer--positive-minutes-p (value)
  "Return non-nil when VALUE is a positive integer minute count."
  (and (integerp value) (> value 0)))

(defun org-workflow-focus-timer--overtime-interval (phase)
  "Return the configured overtime reminder interval for PHASE."
  (if (eq phase 'focus)
      org-workflow-focus-timer-focus-overtime-reminder-interval
    org-workflow-focus-timer-break-overtime-reminder-interval))

(defun org-workflow-focus-timer--cancel-timers ()
  "Cancel and clear all Focus Timer timer objects."
  (dolist (timer (list org-workflow-focus-timer--deadline-timer
                       org-workflow-focus-timer--overtime-timer
                       org-workflow-focus-timer--display-timer))
    (when (timerp timer)
      (cancel-timer timer)))
  (setq org-workflow-focus-timer--deadline-timer nil
        org-workflow-focus-timer--overtime-timer nil
        org-workflow-focus-timer--display-timer nil))

(defun org-workflow-focus-timer--refresh-display ()
  "Refresh displays which may contain Focus Timer state."
  (force-mode-line-update t)
  (when (fboundp 'org-agenda-maybe-redo)
    (org-agenda-maybe-redo)))

(defun org-workflow-focus-timer--request-gnome-refresh ()
  "Ask the GNOME extension to reread authoritative Emacs timer state.
The signal deliberately has no payload: Emacs remains the sole state source.
Failure to reach the session bus must not affect the timer or Org Clock."
  (when (fboundp 'dbus-send-signal)
    (condition-case nil
        (dbus-send-signal :session
                          nil
                          org-workflow-focus-timer-gnome-sync-object-path
                          org-workflow-focus-timer-gnome-sync-interface
                          "Changed")
      (error nil))))

(defun org-workflow-focus-timer--enter-phase (phase)
  "Enter PHASE and schedule its minute-based events."
  (let ((duration (org-workflow-focus-timer--duration-for-phase phase))
        (overtime-interval (org-workflow-focus-timer--overtime-interval phase)))
    (unless (org-workflow-focus-timer--positive-minutes-p duration)
      (user-error "Focus Timer duration must be a positive integer"))
    (unless (or (null overtime-interval)
                (org-workflow-focus-timer--positive-minutes-p overtime-interval))
      (user-error "Focus Timer reminder interval must be nil or a positive integer"))
    (org-workflow-focus-timer--cancel-timers)
    (setq org-workflow-focus-timer-phase phase
          org-workflow-focus-timer-phase-start-time (current-time)
          org-workflow-focus-timer-target-minutes duration
          org-workflow-focus-timer-expired-p nil
          org-workflow-focus-timer--deadline-timer
          (run-at-time (* duration 60) nil #'org-workflow-focus-timer--deadline)
          org-workflow-focus-timer--overtime-timer
          (when overtime-interval
            (run-at-time (* (+ duration overtime-interval) 60)
                         (* overtime-interval 60)
                         #'org-workflow-focus-timer--overtime-reminder))
          org-workflow-focus-timer--display-timer
          (run-at-time 60 60 #'org-workflow-focus-timer--refresh-display))
    (run-hooks 'org-workflow-focus-timer-phase-changed-hook)
    (org-workflow-focus-timer--refresh-display)
    phase))

(defun org-workflow-focus-timer--clear-state ()
  "Clear active phase state without resetting the completed Focus count."
  (org-workflow-focus-timer--cancel-timers)
  (setq org-workflow-focus-timer-phase nil
        org-workflow-focus-timer-phase-start-time nil
        org-workflow-focus-timer-target-minutes nil
        org-workflow-focus-timer-expired-p nil
        org-workflow-focus-timer-task-marker nil)
  (run-hooks 'org-workflow-focus-timer-phase-changed-hook)
  (org-workflow-focus-timer--refresh-display))

(defun org-workflow-focus-timer--deadline ()
  "Mark the current phase expired without changing phase or clock."
  (when (org-workflow-focus-timer-active-p)
    (setq org-workflow-focus-timer-expired-p t)
    (org-workflow-focus-timer--play-phase-sound)
    (run-hooks 'org-workflow-focus-timer-deadline-hook)
    (org-workflow-focus-timer--refresh-display)))

(defun org-workflow-focus-timer--overtime-reminder ()
  "Play the active phase's reminder sound while it remains overdue."
  (when (and (org-workflow-focus-timer-active-p) org-workflow-focus-timer-expired-p)
    (org-workflow-focus-timer--play-phase-sound)))

(defun org-workflow-focus-timer--context-marker ()
  "Return the Org task marker implied by the current context."
  (cond
   ((derived-mode-p 'org-agenda-mode)
    (or (org-get-at-bol 'org-hd-marker)
        (user-error "No Org task on this Agenda line")))
   ((derived-mode-p 'org-mode)
    (save-excursion
      (org-back-to-heading t)
      (copy-marker (point))))
   (t
    (or (org-clock-select-task "Focus on task: ")
        (user-error "No Org task selected")))))

(defun org-workflow-focus-timer--clock-in-marker (marker &optional select)
  "Clock into Org task MARKER using Org's public API and SELECT."
  (unless (and (markerp marker) (marker-buffer marker))
    (user-error "Focus Timer task is no longer available"))
  (let ((org-workflow-focus-timer--clock-operation t))
    (org-with-point-at marker
      (org-back-to-heading t)
      (org-clock-in select)))
  (setq org-workflow-focus-timer-task-marker (copy-marker org-clock-hd-marker)))

;;;###autoload
(defun org-workflow-focus-timer-record-last-pomodoro (&optional marker)
  "Record a completed 25-minute Pomodoro ending now on an Org task.
Use MARKER when supplied; otherwise resolve the current Org context.  This
adds a closed Org CLOCK entry without starting a Focus Timer phase."
  (interactive)
  (when (or (org-workflow-focus-timer-active-p) (org-clocking-p))
    (user-error "Stop the active timer or Org clock before recording a past Pomodoro"))
  (let* ((task (or marker (org-workflow-focus-timer--context-marker)))
         (end-time (current-time))
         (start-time (time-subtract
                      end-time
                      (seconds-to-time (* 60 org-workflow-focus-timer-pomodoro-minutes))))
         (clock-started nil))
    (unless (and (markerp task) (marker-buffer task))
      (user-error "Focus Timer task is no longer available"))
    (condition-case error-data
        (let ((org-workflow-focus-timer--clock-operation t))
          (org-with-point-at task
            (org-back-to-heading t)
            (org-clock-in nil start-time)
            (setq clock-started t)
            (org-clock-out nil nil end-time))
          (message "Recorded a 25-minute Pomodoro ending now")
          org-workflow-focus-timer-pomodoro-minutes)
      (error
       (when (and clock-started (org-clocking-p))
         (let ((org-workflow-focus-timer--clock-operation t))
           (org-clock-cancel)))
       (signal (car error-data) (cdr error-data))))))

(defun org-workflow-focus-timer--prepare-start ()
  "Return non-nil when a new cycle may start.
Ask once before replacing an active cycle, following Pomodoro convention."
  (or (not (org-workflow-focus-timer-active-p))
      (when (yes-or-no-p "Stop the active Focus Timer and start another? ")
        (org-workflow-focus-timer-stop)
        t)))

(defun org-workflow-focus-timer--short-focus-p (&optional now)
  "Return non-nil when the active Focus is too short to retain at NOW."
  (and (eq org-workflow-focus-timer-phase 'focus)
       org-workflow-focus-timer-phase-start-time
       (> org-workflow-focus-timer-minimum-recorded-minutes 0)
       (< (float-time
           (time-subtract (or now (current-time))
                          org-workflow-focus-timer-phase-start-time))
          (* 60 org-workflow-focus-timer-minimum-recorded-minutes))))

(defun org-workflow-focus-timer--close-focus-clock ()
  "Close the active Focus clock, canceling it when it is too short."
  (when (org-clocking-p)
    (let ((org-workflow-focus-timer--clock-operation t))
      (if (org-workflow-focus-timer--short-focus-p)
          (org-clock-cancel)
        (org-clock-out nil t)))))

;;;###autoload
(defun org-workflow-focus-timer-start (&optional marker select)
  "Clock into an Org task and start a soft-boundary Focus phase.
Use MARKER when supplied; otherwise resolve the current Org context.
SELECT carries useful `org-clock-in' prefix behavior."
  (interactive (list nil current-prefix-arg))
  (if (not (org-workflow-focus-timer--prepare-start))
      (org-workflow-focus-timer-status-text)
    (let* ((select-recent (and (null marker) (equal select '(4))))
           (task (or marker
                     (and select-recent
                          (org-clock-select-task "Focus on task: "))
                     (org-workflow-focus-timer--context-marker)))
           (clock-prefix (unless select-recent select)))
      (condition-case error-data
          (progn
            (org-workflow-focus-timer--clock-in-marker task clock-prefix)
            (org-workflow-focus-timer--enter-phase 'focus)
            (org-workflow-focus-timer-status-text))
        (error
         (when (org-clocking-p)
           (let ((org-workflow-focus-timer--clock-operation t))
             (org-clock-out nil t)))
         (org-workflow-focus-timer--clear-state)
         (signal (car error-data) (cdr error-data)))))))

;;;###autoload
(defun org-workflow-focus-timer-start-last (&optional select)
  "Clock into an Org history task and start a Focus phase.
Pass SELECT to `org-clock-in-last' so its prefix behavior remains available."
  (interactive "P")
  (if (not (org-workflow-focus-timer--prepare-start))
      (org-workflow-focus-timer-status-text)
    (condition-case error-data
        (progn
          (let ((org-workflow-focus-timer--clock-operation t))
            (org-clock-in-last select))
          (unless (and (markerp org-clock-hd-marker)
                       (marker-buffer org-clock-hd-marker))
            (user-error "No recent Org clock task is available"))
          (setq org-workflow-focus-timer-task-marker (copy-marker org-clock-hd-marker))
          (org-workflow-focus-timer--enter-phase 'focus)
          (org-workflow-focus-timer-status-text))
      (error
       (when (org-clocking-p)
         (let ((org-workflow-focus-timer--clock-operation t))
           (org-clock-out nil t)))
       (org-workflow-focus-timer--clear-state)
       (signal (car error-data) (cdr error-data))))))

;;;###autoload
(defun org-workflow-focus-timer-finish-phase ()
  "Finish the current phase and immediately start the conventional next one."
  (interactive)
  (pcase org-workflow-focus-timer-phase
    ('focus
     (org-workflow-focus-timer--close-focus-clock)
     (cl-incf org-workflow-focus-timer-completed-count)
     (org-workflow-focus-timer--enter-phase
      (org-workflow-focus-timer--next-break-phase org-workflow-focus-timer-completed-count)))
    ((or 'short-break 'long-break)
     (org-workflow-focus-timer--clock-in-marker org-workflow-focus-timer-task-marker)
     (org-workflow-focus-timer--enter-phase 'focus))
    (_ (user-error "Focus Timer is not active")))
  (org-workflow-focus-timer-status-text))

;;;###autoload
(defun org-workflow-focus-timer-toggle (&optional marker select)
  "Perform the natural action for the current Focus Timer state.

When inactive, start Focus using MARKER and SELECT exactly as
`org-workflow-focus-timer-start' does.  Stop an unexpired Focus, finish Focus overflow into
a break, and finish either break state into the next Focus."
  (interactive (list nil current-prefix-arg))
  (pcase org-workflow-focus-timer-phase
    ((pred null) (org-workflow-focus-timer-start marker select))
    ('focus
     (if org-workflow-focus-timer-expired-p
         (org-workflow-focus-timer-finish-phase)
       (org-workflow-focus-timer-stop)))
    ((or 'short-break 'long-break)
     (org-workflow-focus-timer-finish-phase))
    (_ (user-error "Unknown Focus Timer phase: %S" org-workflow-focus-timer-phase))))

;;;###autoload
(defun org-workflow-focus-timer-stop ()
  "Stop the current cycle, retaining only a sufficiently long Focus clock."
  (interactive)
  (when (eq org-workflow-focus-timer-phase 'focus)
    (org-workflow-focus-timer--close-focus-clock))
  (org-workflow-focus-timer--clear-state)
  (run-hooks 'org-workflow-focus-timer-stopped-hook)
  (org-workflow-focus-timer-status-text))

;;;###autoload
(defun org-workflow-focus-timer-cancel ()
  "Cancel the current cycle and discard its active Org clock interval."
  (interactive)
  (when (and (eq org-workflow-focus-timer-phase 'focus) (org-clocking-p))
    (let ((org-workflow-focus-timer--clock-operation t))
      (org-clock-cancel)))
  (org-workflow-focus-timer--clear-state)
  (run-hooks 'org-workflow-focus-timer-stopped-hook)
  (org-workflow-focus-timer-status-text))

;;;###autoload
(defun org-workflow-focus-timer-reset ()
  "Stop the current cycle and reset the completed Focus count."
  (interactive)
  (setq org-workflow-focus-timer-completed-count 0)
  (org-workflow-focus-timer-stop))

(defun org-workflow-focus-timer--after-external-clock-out ()
  "Clear a Focus phase ended by a raw Org Clock operation."
  (when (and (eq org-workflow-focus-timer-phase 'focus)
             (not org-workflow-focus-timer--clock-operation))
    (org-workflow-focus-timer--clear-state)
    (run-hooks 'org-workflow-focus-timer-stopped-hook)))

(defun org-workflow-focus-timer--play-phase-sound ()
  "Play the configured sound for the active phase without showing a popup."
  (let ((event (if (eq org-workflow-focus-timer-phase 'focus)
                   org-workflow-focus-timer-focus-sound-event
                 org-workflow-focus-timer-break-sound-event)))
    (when event
      (condition-case nil
          (start-process "org-workflow-focus-timer-sound" nil
                         "canberra-gtk-play" "-i" event)
        (file-missing
         (message "Focus Timer sound player is unavailable"))))))

(defun org-workflow-focus-timer--notify (title body)
  "Notify with TITLE and BODY, falling back to the echo area."
  (condition-case nil
      (if (require 'notifications nil t)
          (notifications-notify :title title
                                :body body
                                :app-name "Emacs Focus Timer")
        (message "%s: %s" title body))
    (error (message "%s: %s" title body))))

;;;###autoload
(defun org-workflow-focus-timer-notify-status ()
  "Notify and return the current minute-based Focus Timer status."
  (interactive)
  (let ((status (org-workflow-focus-timer-status-text)))
    (org-workflow-focus-timer--notify "Focus Timer" status)
    status))

(defun org-workflow-focus-timer--enable ()
  "Install this component while Workflow is being enabled."
  (org-workflow--add-hook 'org-clock-out-hook #'org-workflow-focus-timer--after-external-clock-out)
  (org-workflow--add-hook 'org-clock-cancel-hook #'org-workflow-focus-timer--after-external-clock-out)
  (org-workflow--add-hook 'org-workflow-focus-timer-phase-changed-hook #'org-workflow-focus-timer--request-gnome-refresh)
  (org-workflow--add-hook 'org-workflow-focus-timer-deadline-hook #'org-workflow-focus-timer--request-gnome-refresh)
  (org-workflow--with-after-load 'embark-org
  (org-workflow--keymap-set embark-org-heading-map "f" #'org-workflow-focus-timer-start t)
  (org-workflow--add-list-entry 'embark-around-action-hooks
               '(org-workflow-focus-timer-start embark-org--at-heading))))

(provide 'org-workflow-focus-timer)
;;; org-workflow-focus-timer.el ends here
