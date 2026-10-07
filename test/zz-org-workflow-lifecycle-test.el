;;; zz-org-workflow-lifecycle-test.el --- Activation contracts -*- lexical-binding: t; -*-
(require 'ert)
(require 'org-workflow)

(ert-deftest zz-org-workflow-enable-is-idempotent-and-reversible ()
  "Repeated enable owns one integration set and restores existing settings."
  (org-workflow-mode -1)
  (let ((templates (copy-tree org-capture-templates))
        (commands (copy-tree org-agenda-custom-commands))
        (schedule-advices nil))
    (advice-mapc (lambda (fn props) (push (list fn props) schedule-advices)) 'org-schedule)
    (org-workflow-mode 1)
    (let ((hooks (length org-workflow--hooks)) (advices (length org-workflow--advices)))
      (org-workflow-mode 1)
      (should (= hooks (length org-workflow--hooks)))
      (should (= advices (length org-workflow--advices))))
    (org-workflow-mode -1)
    (should (equal templates org-capture-templates))
    (should (equal commands org-agenda-custom-commands))
    (should-not org-workflow--hooks)
    (should-not org-workflow--advices)
    (should-not (timerp org-workflow-target-midnight-timer))
    (should-not (timerp org-workflow-history-timer))
    (let (after)
      (advice-mapc (lambda (fn props) (push (list fn props) after)) 'org-schedule)
      (should (equal schedule-advices after)))
    (org-workflow-mode 1)))

(ert-deftest zz-org-workflow-disable-preserves-later-custom-capture ()
  "Later user capture entries survive disabling the package."
  (let ((org-capture-templates (copy-tree org-capture-templates)))
    (org-workflow-mode -1)
    (org-workflow-mode 1)
    (push '("z" "User capture" entry (file "user.org") "* %?") org-capture-templates)
    (org-workflow-mode -1)
    (should (assoc "z" org-capture-templates))
    (org-workflow-mode 1)))

(ert-deftest zz-org-workflow-load-is-inert-in-a-fresh-profile ()
  "A fresh require neither activates integrations nor opens storage."
  (let* ((profile (make-temp-file "workflow-load-contract-" t))
         (script (expand-file-name "probe.el" profile)))
    (unwind-protect
        (progn
          (with-temp-file script
            (prin1 `(progn
                      (setq user-emacs-directory ,(concat profile "/")
                            package-user-dir ,package-user-dir
                            max-lisp-eval-depth 5000)
                      (require 'package) (package-initialize)
                      (require 'org) (require 'org-capture) (require 'org-agenda)
                      (require 'vulpea-journal) (require 'vui) (require 'org-super-agenda)
                      (add-to-list 'load-path ,org-workflow-test-root)
                      (let ((before (copy-tree (list org-capture-templates org-agenda-custom-commands
                                                    org-mode-hook org-after-todo-state-change-hook))))
                        (require 'org-workflow)
                        (unless (and (not org-workflow-mode)
                                     (not org-workflow-store--connection)
                                     (equal before (list org-capture-templates org-agenda-custom-commands
                                                         org-mode-hook org-after-todo-state-change-hook))
                                     (not (file-exists-p (expand-file-name "var" user-emacs-directory))))
                          (error "Require activated Workflow")))) (current-buffer)))
          (with-temp-buffer
            (let ((status (call-process (expand-file-name invocation-name invocation-directory)
                                        nil t nil "-Q" "--batch" "-l" script)))
              (ert-info ((buffer-string)) (should (= 0 status))))))
      (delete-directory profile t))))

(ert-deftest zz-org-workflow-enable-preserves-migration-state-and-anchor ()
  "Activation preserves the historical anchor and leaves legacy import available."
  (org-workflow-mode -1)
  (let* ((profile (make-temp-file "workflow-init-state-" t))
         (org-workflow-store-file (expand-file-name "facts.sqlite" profile))
         (org-workflow-store--connection nil)
         (org-workflow-store--path nil)
         (org-workflow-web-export-file (expand-file-name "history.json" profile)))
    (unwind-protect
        (progn
          (org-workflow-store-set-meta "anchor" "2026-10-01")
          (cl-letf (((symbol-function 'org-workflow-web-export-history) #'ignore)
                    ((symbol-function 'org-workflow-history-setup) #'ignore)
                    ((symbol-function 'org-workflow-weekly-setup) #'ignore))
            (org-workflow-mode 1)
            (should (equal "2026-10-01" (org-workflow-store-meta "anchor")))
            (should-not (org-workflow-store-meta "migration-v1"))
            (org-workflow-mode -1)))
      (when (org-workflow-store--live-p org-workflow-store--connection)
        (sqlite-close org-workflow-store--connection))
      (delete-directory profile t)))
  (org-workflow-mode 1))
