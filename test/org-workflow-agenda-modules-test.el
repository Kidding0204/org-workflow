;;; org-workflow-agenda-modules-test.el --- Module reload contracts -*- lexical-binding: t; -*-
(require 'ert)
(require 'org-workflow-agenda)

(defun note-gtd-modules-test--advice-counts ()
  (mapcar (lambda (symbol)
            (let ((count 0))
              (advice-mapc (lambda (&rest _) (cl-incf count)) symbol)
              (cons symbol count)))
          '(org-agenda-change-all-lines org-refile org-paste-subtree
            org-agenda-schedule org-schedule org-agenda)))

(ert-deftest note-gtd-modules-reload-preserves-state-and-does-not-duplicate-hooks ()
  "Reloading implementation modules preserves session choices and user capture."
  (let* ((org-capture-templates (copy-tree org-capture-templates))
         (org-workflow-agenda-future-expanded t)
         (org-workflow-agenda-planning-all t)
         (org-workflow-agenda-columns-enabled nil)
         (template '("c" "Custom current capture" plain (function ignore) "Keep me")))
    (setq org-capture-templates
          (cons template (assoc-delete-all "c" org-capture-templates)))
    (let ((before (list (copy-tree org-capture-templates)
                        (copy-tree org-agenda-finalize-hook)
                        (copy-sequence window-size-change-functions)
                        (note-gtd-modules-test--advice-counts))))
      (dotimes (_ 2)
        (dolist (module '(org-workflow-agenda-view org-workflow-agenda-layout
                          org-workflow-agenda-actions org-workflow-agenda-inbox
                          org-workflow-agenda-review))
          (load (symbol-name module) nil t)))
      (should (equal before
                     (list org-capture-templates org-agenda-finalize-hook
                           window-size-change-functions
                           (note-gtd-modules-test--advice-counts))))
      (should (equal template (assoc "c" org-capture-templates)))
      (should org-workflow-agenda-future-expanded)
      (should org-workflow-agenda-planning-all)
      (should-not org-workflow-agenda-columns-enabled))))
