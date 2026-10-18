;;; org-workflow-agenda-completion-position-test.el --- Completion cursor -*- lexical-binding: t; -*-
(require 'ert)
(load "org-workflow-agenda-workbench-test" nil t)

(ert-deftest workflow-completion-position-stays-at-original-line ()
  "Completing the first, last or only task does not follow any task marker."
  (dolist (titles '(("First" "Second") ("Last" "First") ("Only")))
    (org-workflow-workbench-test-with-files
        (list (concat "#+filetags: :project:\n#+TODO: TODO DIVE | DONE HOLD\n* DIVE Stage\n"
                      (mapconcat (lambda (title)
                                   (format "** TODO %s\nSCHEDULED: <2026-08-17 Mon>\n" title))
                                 (reverse titles) "")))
      (set-buffer (org-workflow-workbench-test-open))
      (goto-char (point-min)) (search-forward (car titles))
      (let ((line (line-number-at-pos)) (column (current-column)))
        (org-agenda-todo 'done)
        (org-workflow-agenda--refresh-native-edit)
        (should (= line (line-number-at-pos)))
        (should (= (min column (- (line-end-position) (line-beginning-position)))
                   (current-column)))))))

(ert-deftest workflow-agenda-edit-keeps-position ()
  "Moving tasks between days or periods retains the view's coordinates."
  (dolist (operation '(org-workflow-agenda-schedule-tomorrow
                       org-workflow-agenda-priority-c
                       org-workflow-agenda-move-down
                       workflow-test-native-schedule
                       workflow-test-native-priority
                       workflow-test-native-tags
                       workflow-test-bulk-schedule))
    (org-workflow-workbench-test-with-files
        '("#+filetags: :project:\n#+TODO: TODO DIVE | DONE HOLD\n* DIVE Stage\n** TODO [#A] First\nSCHEDULED: <2026-08-17 Mon>\n** TODO [#A] Second\nSCHEDULED: <2026-08-17 Mon>\n")
      (set-buffer (org-workflow-workbench-test-open))
      (goto-char (point-min)) (search-forward "First")
      (when (eq operation 'workflow-test-bulk-schedule)
        (org-agenda-bulk-mark 1)
        (search-forward "Second")
        (org-agenda-bulk-mark 1)
        (goto-char (point-min)) (search-forward "First"))
      (set-window-start (selected-window) (line-beginning-position) t)
      (let ((line (line-number-at-pos)) (column (current-column))
            (start (line-number-at-pos (window-start))))
        (pcase operation
          ('workflow-test-native-schedule (org-agenda-schedule nil "2026-08-18"))
          ('workflow-test-native-priority (org-agenda-priority ?C))
          ('workflow-test-native-tags (org-agenda-set-tags "@tiny" 'on))
          ('workflow-test-bulk-schedule (org-workflow-agenda-schedule-tomorrow))
          (_ (funcall operation)))
        (org-workflow-agenda--refresh-native-edit)
        (ert-info ((format "operation: %s" operation))
          (should (= line (line-number-at-pos)))
          (should (= (min column (- (line-end-position) (line-beginning-position)))
                     (current-column)))
          (should (= start (line-number-at-pos (window-start)))))))))

(ert-deftest workflow-agenda-redo-keeps-both-pane-coordinates ()
  (org-workflow-workbench-test-with-files (list org-workflow-workbench-test-source)
    (set-buffer (org-workflow-workbench-test-open))
    (let ((panes (org-workflow-workbench-test-panes)) positions)
      (dolist (pane panes)
        (with-selected-window (get-buffer-window pane)
          (goto-char (point-min))
          (search-forward (if (eq pane (car panes)) "Today" "First"))
          (push (list pane (line-number-at-pos) (current-column)) positions)))
      (with-current-buffer (cadr panes)
        (org-with-point-at (org-get-at-bol 'org-hd-marker)
          (org-schedule nil "2026-08-17")))
      (with-current-buffer (car panes) (org-agenda-redo))
      (dolist (saved positions)
        (with-current-buffer (car saved)
          (should (= (nth 1 saved) (line-number-at-pos)))
          (should (= (nth 2 saved) (current-column))))))))
