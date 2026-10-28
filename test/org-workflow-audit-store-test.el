;;; org-workflow-audit-store-test.el --- Transaction boundary regressions -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Jinwang Dong
;; SPDX-License-Identifier: GPL-3.0-or-later
(load "org-workflow-store-test" nil t)

(ert-deftest audit-store-quit-after-commit-must-keep-org-and-sql-together ()
  (org-workflow-store-test
   (let ((execute (symbol-function 'sqlite-execute)))
     (cl-letf (((symbol-function 'sqlite-execute)
                (lambda (db sql &rest args)
                  (prog1 (apply execute db sql args)
                    ;; Model a pending C-g at the durable commit boundary.
                    (when (and (equal sql "COMMIT") (not inhibit-quit))
                      (signal 'quit nil))))))
       (condition-case nil
           (org-workflow-store--operation (lambda () (org-workflow-store-create "2026-09-17")))
         (quit nil)))
     (should (= 1 (length (org-workflow-store-due "2026-09-17"))))
     (should (org-entry-get nil "WORKFLOW_COMMITMENT_ID"))
     (should (equal "applied" (caar (sqlite-select (org-workflow-store--db)
                                                   "SELECT state FROM operations")))))))

(ert-deftest audit-store-save-inside-failing-command-must-preserve-recovery ()
  (org-workflow-store-test
   (let ((before (buffer-string)))
     (should-error
      (org-workflow-store--operation
       (lambda ()
         (org-workflow-store-create "2026-09-17")
         (save-buffer) (error "failure after source save"))))
     (should (equal before (buffer-string)))
     (should (equal before (with-temp-buffer (insert-file-contents file) (buffer-string))))
     (should-not (org-workflow-store-due "2026-09-17")))))

(ert-deftest audit-public-todo-failure-after-saving-must-preserve-disk-state ()
  (org-workflow-store-test
   (org-schedule nil "2026-09-17") (save-buffer)
   (let* ((id (org-entry-get nil "WORKFLOW_COMMITMENT_ID"))
          (before (buffer-string))
          (org-after-todo-state-change-hook
           (append org-after-todo-state-change-hook
                   (list (lambda () (save-buffer) (error "later hook failed"))))))
     (should-error (org-todo "DONE"))
     (should (equal "pending" (nth 6 (org-workflow-store-commitment id))))
     (should (equal before (buffer-string)))
     (should (equal before (with-temp-buffer (insert-file-contents file) (buffer-string)))))))

(ert-deftest audit-public-todo-failure-must-not-lose-live-clock ()
  (org-workflow-store-test
   (let ((org-clock-persist nil) (org-clock-auto-clock-resolution nil)
         (org-clock-out-hook nil) (org-clock-history nil)
         (org-workflow-clock 'org-clock)
         (org-clock-in-hook nil) (org-clock-in-switch-to-state nil))
     (unwind-protect
         (progn
           (org-clock-in nil (time-subtract (current-time) (* 25 60)))
           (let ((org-after-todo-state-change-hook
                  (append org-after-todo-state-change-hook
                          (list (lambda () (error "later hook failed"))))))
             (should-error (org-todo "DONE")))
           (should (equal "TODO" (org-get-todo-state)))
           (should-not (org-clock-is-active))
           (should (save-excursion (goto-char (point-min)) (search-forward "]--[" nil t))))
       (when (org-clock-is-active) (org-clock-cancel))))))

(ert-deftest audit-store-external-write-is-never-overwritten-on-rollback ()
  (org-workflow-store-test
   (let ((before (buffer-string)))
     (should-error
      (org-workflow-store--operation
       (lambda ()
         (org-workflow-store-create "2026-09-17") (save-buffer)
         (with-temp-file file (insert "* External editor's replacement\n"))
         (error "later failure"))))
     (should (equal before (buffer-string)))
     (should (equal "* External editor's replacement\n"
                    (with-temp-buffer (insert-file-contents file) (buffer-string))))
     (should (equal "prepared" (caar (sqlite-select (org-workflow-store--db)
                                                   "SELECT state FROM operations"))))
     (should-error (org-workflow-store-recover)))))

(ert-deftest audit-store-save-hook-error-preserves-preexisting-unsaved-notes ()
  (org-workflow-store-test
   (goto-char (point-max)) (insert "My unsaved note\n")
   (org-back-to-heading t)
   (let ((before (buffer-string))
         (disk (with-temp-buffer (insert-file-contents file) (buffer-string)))
         (after-save-hook (list (lambda () (error "after-save failed")))))
     (should-error
      (org-workflow-store--operation
       (lambda () (org-workflow-store-create "2026-09-17") (save-buffer))))
     (should (equal before (buffer-string)))
     (should (buffer-modified-p))
     (should (equal disk (with-temp-buffer (insert-file-contents file) (buffer-string))))
     (should-not (org-workflow-store-due "2026-09-17")))))

(ert-deftest audit-store-outer-transaction-retains-clock-close-on-inner-failure ()
  (org-workflow-store-test
   (let ((org-clock-persist nil) (org-clock-auto-clock-resolution nil)
         (org-clock-out-hook nil) (org-clock-history nil)
         (org-clock-in-hook nil) (org-clock-in-switch-to-state nil))
     (unwind-protect
         (progn
           (org-clock-in nil (time-subtract (current-time) (* 25 60)))
           (let ((org-after-todo-state-change-hook
                  (append org-after-todo-state-change-hook
                          (list (lambda () (error "inner TODO failed"))))))
             (should-error (org-workflow-store--operation (lambda () (org-todo "DONE")))))
           (should (equal "TODO" (org-get-todo-state)))
           (should-not (org-clock-is-active))
           (should (save-excursion (goto-char (point-min)) (search-forward "]--[" nil t)))
           (should (buffer-modified-p)))
       (when (org-clock-is-active) (org-clock-cancel))))))

(ert-deftest audit-store-rollback-does-not-resurrect-a-cancelled-clock ()
  (org-workflow-store-test
   (let ((org-clock-persist nil) (org-clock-auto-clock-resolution nil)
         (org-clock-in-hook nil) (org-clock-in-switch-to-state nil))
     (unwind-protect
         (progn
           (org-clock-in nil (time-subtract (current-time) 120))
           (should-error (org-workflow-store--operation
                          (lambda () (org-clock-cancel) (error "later failure"))))
           (should-not (org-clock-is-active))
           (should-not (save-excursion (goto-char (point-min)) (search-forward "CLOCK:" nil t))))
       (when (org-clock-is-active) (org-clock-cancel))))))

(ert-deftest audit-store-missing-clock-line-never-removes-unrelated-text ()
  (org-workflow-store-test
   (let ((org-clock-persist nil) (org-clock-auto-clock-resolution nil)
         (org-clock-in-hook nil) (org-clock-in-switch-to-state nil))
     (unwind-protect
         (progn
           (org-clock-in nil (time-subtract (current-time) 120))
           (org-with-point-at org-clock-marker
             (delete-region (line-beginning-position) (min (point-max) (1+ (line-end-position)))))
           (let ((before (buffer-string)))
             (should-error (org-workflow-store--operation
                            (lambda () (org-clock-cancel) (error "later failure"))))
             (should (equal before (buffer-string)))))
       (when (org-clock-is-active) (org-clock-cancel))))))
