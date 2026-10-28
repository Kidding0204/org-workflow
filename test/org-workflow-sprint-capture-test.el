;;; org-workflow-sprint-capture-test.el --- Daily capture contracts -*- lexical-binding: t; -*-
(require 'ert)
(load "org-workflow-store-test" nil t)
(require 'org-workflow-agenda)

(ert-deftest workflow-qa-never-replaces-parent-leaf ()
  (with-temp-buffer
    (insert "* TODO Work [0/0]\n** TODO Question :QA:\n")
    (org-mode)
    (goto-char (point-min))
    (should (org-workflow-target--task-leaf-p))
    (forward-line 1)
    (should-not (org-workflow-target--task-p))
    (org-add-planning-info 'scheduled (org-time-string-to-time "2026-09-16"))
    (should (org-workflow-target--task-p))
    (goto-char (point-min))
    (should (org-workflow-target--task-leaf-p))))

(ert-deftest workflow-qa-statistics-ignore-open-and-closed-questions ()
  (with-temp-buffer
    (insert "* TODO Work [0/0]\n** TODO Question :QA:\n")
    (org-mode)
    (goto-char (point-min)) (forward-line 1)
    (let ((org-log-done nil)) (org-todo "DONE"))
    (goto-char (point-min))
    (should (equal "TODO" (org-get-todo-state)))
    (should (looking-at-p "\\* TODO Work \\[0/0\\]"))))

(ert-deftest workflow-qa-identity-is-not-inherited ()
  (with-temp-buffer
    (insert "* TODO Container :QA:\n** TODO Real task\n")
    (org-mode) (goto-char (point-min)) (forward-line 1)
    (should-not (org-workflow-qa-p))
    (should (org-workflow-target--task-p))))
