;;; org-workflow-task-types-test.el --- Typed notes and task boundaries -*- lexical-binding: t; -*-
(require 'ert)
(require 'org-workflow)
(load "org-workflow-agenda-target-test" nil t)

(ert-deftest org-workflow-task-types-use-a-separate-org-type-set ()
  "Typed notes are recognized by Org without becoming execution tasks."
  (with-temp-buffer
    (org-mode)
    (insert "* QA Question\n* LAB Experiment\n* HW Exercise\n")
    (goto-char (point-min))
    (dolist (state '("QA" "LAB" "HW"))
      (should (equal state (org-get-todo-state)))
      (should (eq 'type (cadr (assoc state org-todo-kwd-alist))))
      (should-not (org-entry-is-done-p))
      (should-not (org-workflow-target--unfinished-p))
      (should-not (org-workflow-target--task-leaf-p))
      (outline-next-heading))))

(ert-deftest org-workflow-task-types-keep-the-parent-in-the-queue ()
  "Editing and saving typed descendants leaves the scheduled parent actionable."
  (org-workflow-target-test-with-files
   '("#+filetags: :project:\n#+TODO: TODO DIVE | DONE HOLD\n#+TYP_TODO: QA LAB HW |\n* DIVE Course\n** TODO [#A] Lecture\nSCHEDULED: <2026-08-17 Mon>\n")
   (with-current-buffer (find-file-noselect (car org-agenda-files))
     (goto-char (point-min))
     (re-search-forward "^\\*\\* TODO")
     (beginning-of-line)
     ;; Warm the native cache before manual editing, as in an open task buffer.
     (org-element-at-point)
     (goto-char (point-max))
     (insert "*** QA Question\n*** LAB Experiment\nSCHEDULED: <2026-08-17 Mon>\n**** HW Exercise\n")
     (save-buffer)
     (org-workflow-target--refresh-after-agenda-save)
     (should (equal '("Lecture")
                    (mapcar #'org-workflow-target-entry-title
                            (org-workflow-target--collect)))))))

(ert-deftest org-workflow-task-types-preserve-the-parent-schedule-on-normalization ()
  "Rescheduling a task must not transfer its schedule to typed notes."
  (org-workflow-target-test-with-files
   '("#+filetags: :project:\n#+TODO: TODO DIVE | DONE HOLD\n#+TYP_TODO: QA LAB HW |\n* Course\n** TODO Lecture\nSCHEDULED: <2026-08-17 Mon>\n*** QA Question\n*** LAB Experiment\n*** HW Exercise\n")
   (with-current-buffer (find-file-noselect (car org-agenda-files))
     (goto-char (point-min))
     (re-search-forward "^\\*\\* TODO")
     (beginning-of-line)
     (org-workflow-normalize-heading)
     (should (equal "<2026-08-17 Mon>" (org-entry-get nil "SCHEDULED")))
     (outline-next-heading)
     (should-not (org-entry-get nil "SCHEDULED"))
     (should-not (org-workflow--unfinished-leaf-markers-in-subtree)))))

(ert-deftest org-workflow-task-types-do-not-normalize-a-typed-note ()
  "A typed note's own date is not a Workflow schedule to redistribute."
  (org-workflow-target-test-with-files
   '("#+filetags: :project:\n#+TODO: TODO DIVE | DONE HOLD\n#+TYP_TODO: QA LAB HW |\n* Course\n** QA Question\nSCHEDULED: <2026-08-17 Mon>\n")
   (with-current-buffer (find-file-noselect (car org-agenda-files))
     (goto-char (point-min))
     (re-search-forward "^\\*\\* QA")
     (beginning-of-line)
     (let ((before (buffer-string)))
       (org-workflow-normalize-heading)
       (should (equal before (buffer-string)))))))

(ert-deftest org-workflow-task-types-do-not-hide-real-task-descendants ()
  "A TODO below a typed heading still makes its ancestor a task container."
  (with-temp-buffer
    (insert "#+TODO: TODO DIVE | DONE HOLD\n#+TYP_TODO: QA LAB HW |\n* TODO Lecture\n** QA Question\n*** TODO Investigate\n")
    (org-mode)
    (goto-char (point-min))
    (re-search-forward "^\\* TODO")
    (beginning-of-line)
    (should-not (org-workflow-target--task-leaf-p))
    (outline-next-heading)
    (should-not (org-workflow-target--task-leaf-p))
    (outline-next-heading)
    (should (org-workflow-target--unfinished-leaf-p))))

(ert-deftest org-workflow-task-types-do-not-auto-complete-a-statistics-parent ()
  "A cookie containing only typed notes cannot mark the executing task DONE."
  (with-temp-buffer
    (org-mode)
    (insert "* TODO Lecture [/]\n** QA Question\n** LAB Experiment\n** HW Exercise\n")
    (goto-char (point-min))
    (org-update-statistics-cookies t)
    (should (equal "TODO" (org-get-todo-state)))
    (should (org-workflow-target--unfinished-leaf-p))))

(ert-deftest org-workflow-task-types-statistics-still-track-real-tasks ()
  "Typed notes do not enter the cookie or block completion of real tasks."
  (with-temp-buffer
    (org-mode)
    (insert "* TODO Lecture [/]\n** QA Question\n** TODO Investigate\n** DONE Finished\n** HW Exercise\n")
    (goto-char (point-min))
    (org-update-statistics-cookies t)
    (should (equal "Lecture [1/2]" (org-get-heading t t t t)))
    (should (equal "TODO" (org-get-todo-state)))
    (re-search-forward "^\\*\\* TODO")
    (beginning-of-line)
    (org-todo "DONE")
    (goto-char (point-min))
    (should (equal "Lecture [2/2]" (org-get-heading t t t t)))
    (should (equal "DONE" (org-get-todo-state)))))

(provide 'org-workflow-task-types-test)
;;; org-workflow-task-types-test.el ends here
