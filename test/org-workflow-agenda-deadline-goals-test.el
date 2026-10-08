;;; org-workflow-agenda-deadline-goals-test.el --- Deadline milestones -*- lexical-binding: t; -*-

(require 'ert)
(require 'org-workflow-agenda)
(load "org-workflow-agenda-workbench-test" nil t)

(ert-deftest org-workflow-deadline-goals-scope-order-and-no-execution-admission ()
  (org-workflow-workbench-test-with-files
      '("#+filetags: :project:\n#+TODO: TODO DIVE | DONE HOLD\n* TODO Project milestone\nDEADLINE: <2026-09-01 Tue>\n** TODO Future goal\nDEADLINE: <2026-08-21 Fri>\n** TODO Overdue goal\nDEADLINE: <2026-08-16 Sun>\n** DONE Finished\nDEADLINE: <2026-08-10 Mon>\n** HOLD Paused\n*** TODO Held child\nDEADLINE: <2026-08-11 Tue>\n** TODO Habit\nDEADLINE: <2026-08-12 Wed>\n:PROPERTIES:\n:STYLE: habit\n:END:\n** DIVE Active\n*** TODO Execute today\nSCHEDULED: <2026-08-17 Mon>\n"
        "#+filetags: :area:\n* Backlog\n** TODO Due today\nDEADLINE: <2026-08-17 Mon>\n"
        "#+filetags: :project:workflow-closed:\n* TODO Closed source\nDEADLINE: <2026-08-01 Sat>\n"
        "* TODO Unscoped source\nDEADLINE: <2026-08-01 Sat>\n")
    (let ((records (org-workflow-agenda--deadline-goals)))
      (should (equal '("2026-08-16" "2026-08-17" "2026-08-21" "2026-09-01")
                     (mapcar #'car records)))
      ;; The read-only scan does not visit filtered or matching files.
      (should-not (seq-some #'get-file-buffer files)))
    (should (equal '("Execute today")
                   (mapcar #'org-workflow-target-entry-title
                           (org-workflow-target--ordered-entries))))))

(ert-deftest org-workflow-deadline-goals-read-live-unsaved-deadline ()
  (org-workflow-workbench-test-with-files
      '("#+filetags: :project:\n* TODO Goal\nDEADLINE: <2026-08-21 Fri>\n")
    (with-current-buffer (find-file-noselect (car files))
      (goto-char (point-min))
      (search-forward "2026-08-21")
      (replace-match "2026-08-17"))
    (should (equal "2026-08-17" (caar (org-workflow-agenda--deadline-goals))))
    (with-temp-buffer
      (insert-file-contents (car files))
      (should (string-match-p "2026-08-21" (buffer-string))))))

(ert-deftest org-workflow-deadline-goals-header-native-markers-and-completion ()
  (org-workflow-workbench-test-with-files
      '("#+filetags: :project:\n#+TODO: TODO DIVE | DONE HOLD\n* Stage\n** TODO Due today [1/3]\nDEADLINE: <2026-08-17 Mon>\n** TODO Overdue\nDEADLINE: <2026-08-16 Sun>\n** DIVE Current\n*** TODO Work\nSCHEDULED: <2026-08-17 Mon>\n")
    (set-buffer (org-workflow-workbench-test-open))
    (let ((text (buffer-string)))
      (should (< (string-match "阶段目标 · 截止日期" text)
                 (string-match "今日安排" text)))
      (should (string-match-p "Due today \\[1/3\\]" text))
      (should (string-match-p "2026-08-16 · 已逾期" text))
      (should (string-match-p "2026-08-17 · 今天截止" text)))
    (goto-char (point-min))
    (search-forward "Due today")
    (let ((marker (org-get-at-bol 'org-hd-marker)))
      (should (eq marker (org-get-at-bol 'org-marker)))
      (should (marker-buffer marker))
      (should (equal "Due today [1/3]"
                     (org-with-point-at marker (org-get-heading t t t t)))))
    (let ((org-log-done nil)) (org-agenda-todo 'done))
    (should (equal '("2026-08-16")
                   (mapcar #'car (org-workflow-agenda--deadline-goals))))))

(ert-deftest org-workflow-deadline-goals-empty-header-is-omitted ()
  (org-workflow-workbench-test-with-files
      '("#+filetags: :project:\n* TODO No deadline\n")
    (with-temp-buffer
      (org-workflow-agenda-deadline-goals nil)
      (should (equal "" (buffer-string))))))

(provide 'org-workflow-agenda-deadline-goals-test)
;;; org-workflow-agenda-deadline-goals-test.el ends here
