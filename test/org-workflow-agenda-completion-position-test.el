;;; org-workflow-agenda-completion-position-test.el --- Completion cursor -*- lexical-binding: t; -*-
(require 'ert)
(load "org-workflow-agenda-workbench-test" nil t)

(ert-deftest workflow-completion-position-selects-remaining-task ()
  "Completion selects a remaining task, or keeps coordinates if none remain."
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
        (if (cadr titles)
            (let ((marker (org-get-at-bol 'org-hd-marker)))
              (should (markerp marker))
              (should (equal (cadr titles)
                             (org-with-point-at marker (org-get-heading t t t t)))))
          (should (= line (line-number-at-pos))))
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

(ert-deftest workflow-agenda-task-cursor-skips-rebuilt-group-headings ()
  "A task cursor selects the following task across headings and blank lines."
  (with-temp-buffer
    (org-mode)
    (insert "* TODO Fixture\n")
    (let ((marker (copy-marker (point-min))))
      (with-temp-buffer
	(insert (propertize "First task\n" 'org-hd-marker marker))
	(goto-char (point-min))
	(let ((anchor (org-workflow-agenda--buffer-position (point) t)))
          (erase-buffer)
          (insert "Project heading\n\n")
          (insert (propertize "Hidden task\n" 'org-hd-marker marker 'invisible t))
          (insert (propertize "Stage goal\n" 'org-hd-marker marker
                              'org-workflow-agenda-stage-goal t))
          (let ((expected (point)))
            (insert (propertize "Next task\n" 'org-hd-marker marker))
            (should (= expected (org-workflow-agenda--restore-position anchor)))))))))

(ert-deftest workflow-agenda-task-cursor-falls-back-without-moving-scroll-anchor ()
  "At the end, select the previous task; viewport anchors remain geometric."
  (with-temp-buffer
    (org-mode)
    (insert "* TODO Fixture\n")
    (let ((marker (copy-marker (point-min))))
      (with-temp-buffer
	(insert "Heading\n")
	(insert (propertize "Task\n" 'org-hd-marker marker))
	(goto-char (point-min)) (forward-line)
	(let ((cursor (org-workflow-agenda--buffer-position (point) t))
              (scroll (org-workflow-agenda--buffer-position (point))))
          (erase-buffer)
          (insert (propertize "Previous\n" 'org-hd-marker marker))
          (insert "Empty group\n")
          (should (= (point-min) (org-workflow-agenda--restore-position cursor)))
          (should (= 2 (line-number-at-pos
			(org-workflow-agenda--restore-position scroll))))
          (erase-buffer)
          (insert "No tasks\n")
          (should (integerp (org-workflow-agenda--restore-position cursor))))))))

(ert-deftest workflow-agenda-scheduling-continues-with-next-task-across-groups ()
  "Removing a group must leave a real task selected for the next command."
  (org-workflow-workbench-test-with-files
      '("#+filetags: :project:\n#+TODO: TODO DIVE | DONE HOLD\n* DIVE First group\n** TODO First\n* DIVE Second group\n** TODO Second\n** TODO Third\n")
    (set-buffer (org-workflow-workbench-test-open))
    (goto-char (point-min)) (search-forward "First\n") (backward-char)
    (org-workflow-agenda-schedule-tomorrow)
    (let ((marker (org-get-at-bol 'org-hd-marker)))
      (should (markerp marker))
      (should (equal "Second" (org-with-point-at marker
						 (org-get-heading t t t t)))))
    (org-workflow-agenda-schedule-tomorrow)
    (let ((marker (org-get-at-bol 'org-hd-marker)))
      (should (markerp marker))
      (should (equal "Third" (org-with-point-at marker
					        (org-get-heading t t t t)))))))
