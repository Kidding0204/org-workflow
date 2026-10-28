;;; org-workflow-dispatch-test.el --- Native dispatch boundaries -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Jinwang Dong
;; Author: Jinwang Dong <dongjinwang040204@gmail.com>
;; Assisted-by: Codex:GPT-6
;; SPDX-License-Identifier: GPL-3.0-or-later
(require 'ert)
(require 'org-workflow)

(ert-deftest org-workflow-dispatch-connects-native-review-and-capture ()
  "The first entry connects native history, capture and package settings."
  (dolist (entry '(("h" . org-workflow-history-panel)
                   ("SPC" . org-workflow-agenda-open-workbench)
                   ("n" . org-capture)
                   ("C" . org-workflow-customize)
                   ("f t" . org-workflow-focus-timer-toggle)
                   ("f f" . org-workflow-focus-timer-finish-phase)))
    (let* ((suffix (transient-get-suffix 'org-workflow-menu (car entry)))
           (command (plist-get (cdr suffix) :command)))
      (should (eq command (cdr entry)))
      (should (commandp command))
      (when (string-prefix-p "f " (car entry))
        (should (= 2 (length (kbd (plist-get (cdr suffix) :key)))))))))

(ert-deftest org-workflow-mode-does-not-export-or-install-web-launcher ()
  "Activating an established store neither writes a snapshot nor exposes a launcher."
  (let ((org-workflow-store-enabled org-workflow-store-enabled))
    (org-workflow-mode -1)
    (let* ((directory (make-temp-file "workflow-native-entry-" t))
           (org-workflow-store-file (expand-file-name "facts.sqlite" directory))
           (org-workflow-store--connection nil)
           (org-workflow-store--path nil)
           (org-workflow-web-export-file (expand-file-name "history.json" directory))
           exported)
      (unwind-protect
          (progn
            (org-workflow-store-set-meta "anchor" "2026-10-01")
            (cl-letf (((symbol-function 'org-workflow-web-export-history)
                       (lambda (&rest _) (setq exported t)))
                      ((symbol-function 'org-workflow-history-setup) #'ignore)
                      ((symbol-function 'org-workflow-weekly-setup) #'ignore))
              (org-workflow-mode 1)
              (should-not exported)
              (should-not (file-exists-p org-workflow-web-export-file))
              (should-not (fboundp 'org-workflow-web-open))
              (should-not (boundp 'org-workflow-web-open-function))
              (should-not (memq 'org-workflow-web-export-after-finalize
				org-workflow-journal-finalized-hook))
              (org-workflow-mode -1)))
	(when (org-workflow-store--live-p org-workflow-store--connection)
          (sqlite-close org-workflow-store--connection))
	(delete-directory directory t)))
    (org-workflow-mode 1)))

(ert-deftest org-workflow-dispatch-opens-the-requested-native-history-panel ()
  (let (opened)
    (cl-letf (((symbol-function 'org-workflow-history-panel)
               (lambda (&optional _) (interactive) (setq opened t))))
      (should (equal '(:ok t :action history) (org-workflow-dispatch 'history)))
      (should opened))))

(ert-deftest org-workflow-select-reuses-client-frame-without-daemon-display ()
  "A native client selector must work when daemon display variables are absent."
  (let ((process-environment (copy-sequence process-environment)) queued)
    (setenv "DISPLAY" nil)
    (setenv "WAYLAND_DISPLAY" nil)
    (cl-letf (((symbol-function 'display-graphic-p) (lambda (&optional _) t))
              ((symbol-function 'selected-frame) (lambda () 'selector-frame))
              ((symbol-function 'frame-parameter)
               (lambda (_frame parameter)
                 (pcase parameter ('name "workflow-select") ('minibuffer 'only))))
              ((symbol-function 'make-frame-on-display)
               (lambda (&rest _) (ert-fail "Selector must not create a second frame")))
              ((symbol-function 'run-at-time)
               (lambda (&rest arguments) (setq queued arguments))))
      (should (equal '(:queued t :action select) (org-workflow-select-in-new-frame)))
      (should (equal '(0.1 nil org-workflow--select-in-dedicated-frame selector-frame) queued)))))

(provide 'org-workflow-dispatch-test)
;;; org-workflow-dispatch-test.el ends here
