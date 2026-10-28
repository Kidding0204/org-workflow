;;; -*- lexical-binding: t; -*-
(require 'ert)
(load "org-workflow-agenda-workbench-test" nil t)

(ert-deftest workflow-unified-default-folds-follow-dive-and-buttons-are-plain ()
  (org-workflow-workbench-test-with-files
      '("* DIVE Project\n** DONE Finished\n*** DONE Old\n** DIVE Current\n*** TODO Active\n** TODO Future\n*** TODO Later\n** Plain\n*** TODO Unsorted\n* TODO Waiting\n** DIVE Hidden\n*** TODO Hidden task\n")
    (org-workflow-workbench-test-open)
    (pcase-let ((`(,_left ,right) (org-workflow-workbench-test-panes)))
      (with-current-buffer right
        (should (string-match-p "Active" (buffer-string)))
        (should-not (string-match-p "Old\\|Later\\|Unsorted\\|Hidden task" (buffer-string)))
        (goto-char (point-min)) (search-forward "DIVE Project") (beginning-of-line)
        (let ((button (next-button (point))))
          (should button)
          (should (eq nil (face-attribute (button-get button 'face) :underline nil t))))
        (search-forward "TODO Future")
        (org-workflow-agenda-project-toggle)
        (should (string-match-p "Later" (buffer-string)))
        (org-agenda-redo)
        (should (string-match-p "Later" (buffer-string)))))))

(ert-deftest workflow-unified-old-project-entry-keeps-day-and-shows-schedule ()
  (org-workflow-workbench-test-with-files (list org-workflow-workbench-test-source)
    (org-workflow-workbench-test-open)
    (org-workflow-agenda-set-day t)
    (org-workflow-project-view)
    (should (eq 'tomorrow (org-workflow-agenda-selected-view)))
    (should (org-workflow-agenda--setting 'org-workflow-agenda-columns-enabled))
    (should (string-match-p "安排" (buffer-string)))
    (should (string-match-p "随时" (buffer-string)))
    (with-temp-buffer
      (org-workflow-agenda--insert-day-tabs)
      (should-not (string-match-p "项目" (buffer-string))))))

(ert-deftest workflow-unified-day-tree-accepts-classify-and-period-targets ()
  (org-workflow-workbench-test-with-files (list org-workflow-workbench-test-source)
    (org-workflow-workbench-test-open)
    (pcase-let* ((`(,left ,right) (org-workflow-workbench-test-panes))
                (state org-workflow-agenda--workbench))
      (with-current-buffer right
        (goto-char (point-min)) (search-forward "DIVE Stage")
        (should (eq 'classify (car (nth 1 (org-workflow-agenda-mouse--target
                                           (list (get-buffer-window right) (point) '(20 . 40) 0) state))))))
      (with-current-buffer left
        (goto-char (point-min)) (search-forward "上午")
        (should (eq 'task (car (nth 1 (org-workflow-agenda-mouse--target
                                        (list (get-buffer-window left) (point) '(20 . 40) 0) state)))))))))

(ert-deftest workflow-unified-inbox-keeps-scheduled-captures-without-duplicate-rows ()
  (org-workflow-workbench-test-with-files
      '("* Inbox\n** TODO Today capture\nSCHEDULED: <2026-08-17 Mon>\n** TODO Future capture\nSCHEDULED: <2026-08-20 Thu>\n** TODO Unplanned capture\n* DIVE Project\n** DIVE Group\n*** TODO Step\n")
    (let ((org-workflow-projects-file (car files)))
      (cl-letf (((symbol-function 'org-workflow-collection-inbox--review-files) (lambda () files)))
        (org-workflow-workbench-test-open)
        (should (equal 1 (cl-count "Today capture" (org-workflow-workbench-test-titles) :test #'equal)))
        (should (member "Future capture" (org-workflow-workbench-test-titles)))
        (goto-char (point-min)) (search-forward "Today capture")
        (should (org-get-at-bol 'org-workflow-agenda-inbox-row))
        (goto-char (point-min)) (search-forward "Future capture")
        (should (org-get-at-bol 'org-workflow-agenda-inbox-row))))))

(ert-deftest workflow-unified-inbox-always-excludes-held-and-completed-states ()
  (org-workflow-workbench-test-with-files
      '("#+TODO: TODO DIVE HOLD | DONE CANCELLED\n* Inbox\n** TODO Open\n** DIVE Active\n** HOLD Paused\n** DONE Finished\n** CANCELLED Cancelled\n** TODO Planned\nSCHEDULED: <2026-08-20 Thu>\n")
    (let ((org-workflow-projects-file (car files)))
      (should (equal '("TODO Open" "DIVE Active" "TODO Planned")
                     (mapcar #'cadr (org-workflow-collection-inbox--pending files t))))
      (should (equal '("TODO Open" "DIVE Active")
                     (mapcar #'cadr (org-workflow-collection-inbox--pending files t t))))
      (cl-letf (((symbol-function 'org-workflow-collection-inbox--review-files) (lambda () files)))
        (org-workflow-workbench-test-open)
        (should-not (string-match-p "Paused\\|Finished\\|Cancelled" (buffer-string)))
        (should (string-match-p "Planned" (buffer-string)))))))
