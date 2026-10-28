;;; org-workflow-audit-integrations-test.el --- Terminal history entry -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later
(require 'ert)
(require 'org-workflow)
(unless (featurep 'org-workflow-history-view-test)
  (load "org-workflow-history-view-test" nil t))

(ert-deftest workflow-audit-integrations-terminal-menu-history ()
  "The real menu command opens a native tracker on a terminal frame."
  (let* ((suffix (transient-get-suffix 'org-workflow-menu "h"))
         (command (plist-get (cdr suffix) :command))
         (payload (workflow-history-view-test--payload
                   (workflow-history-view-test--day "2026-09-16")))
         (windows (current-window-configuration))
         buffer)
    (unwind-protect
        (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) nil))
                  ((symbol-function 'org-workflow-history-read) (lambda (&rest _) payload)))
          (should (eq command 'org-workflow-history-panel))
          (setq buffer (call-interactively command))
          (with-current-buffer buffer
            (should (derived-mode-p 'org-workflow-history-panel-mode))
            (should (eq 'ready (plist-get org-workflow-history-panel--model :state)))
            (should (equal "2026-09-16"
                           (plist-get (plist-get org-workflow-history-panel--model :detail) :date)))))
      (when (buffer-live-p buffer) (kill-buffer buffer))
      (set-window-configuration windows))))

(provide 'org-workflow-audit-integrations-test)
;;; org-workflow-audit-integrations-test.el ends here
