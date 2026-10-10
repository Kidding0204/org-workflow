;;; org-workflow-byte-compile-test.el --- Compiled cross-module bindings -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Jinwang Dong
;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Commentary:
;; Compile each consumer before its variable owners are loaded, as a package
;; installer can do.  Source tests alone inherit the fully loaded package.
;;; Code:
(require 'ert)

(defun org-workflow-test--compiled-probe (module forms)
  "Compile MODULE in a fresh process and run its behavioral probe FORMS."
  (let* ((directory (make-temp-file "workflow-compiled-probe-" t))
         (source (expand-file-name (concat module ".el") directory))
         (script (expand-file-name "probe.el" directory)))
    (unwind-protect
        (progn
          (copy-file (expand-file-name (concat module ".el") org-workflow-test-root) source)
          (with-temp-file script
            (prin1
             `(progn
                (require 'cl-lib)
                (require 'bytecomp)
                (add-to-list 'load-path ,org-workflow-test-root)
                (let ((byte-compile-warnings nil))
                  (unless (byte-compile-file ,source) (error "Probe compilation failed")))
                (load ,(concat source "c") nil t t)
                ,@forms)
             (current-buffer)))
          (with-temp-buffer
            (let ((status (call-process (expand-file-name invocation-name invocation-directory)
                                        nil t nil "-Q" "--batch" "-l" script)))
              (ert-info ((buffer-string)) (should (= status 0))))))
      (delete-directory directory t))))

(ert-deftest workflow-compiled-tag-filter-keeps-sprint-context ()
  "Native tag filtering observes the compiled caller's Sprint guards."
  (org-workflow-test--compiled-probe
   "org-workflow-agenda-actions"
   '((setq org-workflow-agenda-sprint-view nil
           org-workflow-agenda--laying-out-columns nil
           org-workflow-agenda--sprint-buffer-p t)
     (let (observed)
       (cl-letf (((symbol-function 'org-workflow-agenda--clear-selection) #'ignore)
                 ((symbol-function 'org-workflow-agenda--workbench-buffers) #'ignore)
                 ((symbol-function 'org-workflow-agenda--set-setting) #'ignore)
                 ((symbol-function 'org-agenda-filter-show-all-tag)
                  (lambda () (setq observed
                                   (list (symbol-value 'org-workflow-agenda-sprint-view)
                                         (symbol-value 'org-workflow-agenda--laying-out-columns))))))
         (org-workflow-agenda--filter-tag nil))
       (unless (equal observed '(t t)) (error "Lost Sprint context: %S" observed))))))

(ert-deftest workflow-compiled-workbench-keeps-planning-settings ()
  "Opening a workbench passes the selected day and scope into Org Agenda."
  (org-workflow-test--compiled-probe
   "org-workflow-agenda-layout"
   '((setq org-workflow-agenda-plan-tomorrow nil
           org-workflow-agenda-planning-all nil)
     (let ((observed
            (catch 'observed
              (cl-letf (((symbol-function 'org-workflow-agenda--clean-menu-windows) #'ignore)
                        ((symbol-function 'org-workflow-agenda--setting) (lambda (_) t))
                        ((symbol-function 'tab-bar-new-tab) #'ignore)
                        ((symbol-function 'tab-bar-rename-tab) #'ignore)
                        ((symbol-function 'delete-other-windows) #'ignore)
                        ((symbol-function 'org-agenda)
                         (lambda (&rest _)
                           (throw 'observed
                                  (list (symbol-value 'org-workflow-agenda-plan-tomorrow)
                                        (symbol-value 'org-workflow-agenda-planning-all))))))
                (org-workflow-agenda-open-workbench)))))
       (unless (equal observed '(t t)) (error "Lost planning settings: %S" observed))))))

(ert-deftest workflow-compiled-candidates-honor-current-only ()
  "Current-only candidates override an outer all-projects planning scope."
  (org-workflow-test--compiled-probe
   "org-workflow-agenda-view"
   '((setq org-workflow-agenda-planning-all t)
     (with-temp-buffer
       (org-mode)
       (insert "* TODO Candidate\n")
       (goto-char (point-min))
       (let ((observed 'unread))
         (cl-letf (((symbol-function 'org-agenda-files) (lambda (&rest _) '("probe.org")))
                   ((symbol-function 'file-readable-p) (lambda (_) t))
                   ((symbol-function 'find-file-noselect) (lambda (&rest _) (current-buffer)))
                   ((symbol-function 'org-map-entries) (lambda (function &rest _) (funcall function)))
                   ((symbol-function 'org-workflow-agenda--plannable-current-leaf-p)
                    (lambda () (setq observed (symbol-value 'org-workflow-agenda-planning-all)) nil)))
           (org-workflow-agenda--candidate-entries t))
         (unless (null observed) (error "Ignored current-only scope: %S" observed)))))))

(provide 'org-workflow-byte-compile-test)
;;; org-workflow-byte-compile-test.el ends here
