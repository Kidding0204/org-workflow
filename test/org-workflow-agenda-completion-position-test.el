;;; org-workflow-agenda-completion-position-test.el --- Completion cursor -*- lexical-binding: t; -*-
(require 'ert)
(load "org-workflow-agenda-workbench-test" nil t)

(ert-deftest workflow-completion-position-selects-next-task ()
  (org-workflow-workbench-test-with-files
      '("#+filetags: :project:\n#+TODO: TODO DIVE | DONE HOLD\n* DIVE Stage\n** TODO First\nSCHEDULED: <2026-08-17 Mon>\n** TODO Second\nSCHEDULED: <2026-08-17 Mon>\n")
    (set-buffer (org-workflow-workbench-test-open))
    (goto-char (point-min)) (search-forward "First")
    (org-agenda-todo 'done)
    (org-workflow-agenda--refresh-native-edit)
    (should (equal "Second" (org-with-point-at (org-get-at-bol 'org-hd-marker) (org-get-heading t t t t))))
    (should (string-match-p "First" (buffer-string)))
    (should (< (point) (text-property-any (point-min) (point-max) 'org-workflow-agenda-completed-header t)))))

(ert-deftest workflow-completion-position-last-task-selects-previous ()
  (org-workflow-workbench-test-with-files
      '("#+filetags: :project:\n#+TODO: TODO DIVE | DONE HOLD\n* DIVE Stage\n** TODO First\nSCHEDULED: <2026-08-17 Mon>\n** TODO Last\nSCHEDULED: <2026-08-17 Mon>\n")
    (set-buffer (org-workflow-workbench-test-open))
    (goto-char (point-min)) (search-forward "Last")
    (org-agenda-todo 'done)
    (org-workflow-agenda--refresh-native-edit)
    (should (equal "First" (org-with-point-at (org-get-at-bol 'org-hd-marker) (org-get-heading t t t t))))))

(ert-deftest workflow-completion-position-only-task-stays-before-completed ()
  (org-workflow-workbench-test-with-files
      '("#+filetags: :project:\n#+TODO: TODO DIVE | DONE HOLD\n* Stage\n** TODO Only\nSCHEDULED: <2026-08-17 Mon>\n")
    (set-buffer (org-workflow-workbench-test-open))
    (goto-char (point-min)) (search-forward "Only")
    (org-agenda-todo 'done)
    (org-workflow-agenda--refresh-native-edit)
    (should (< (point) (text-property-any (point-min) (point-max) 'org-workflow-agenda-completed-header t)))))
