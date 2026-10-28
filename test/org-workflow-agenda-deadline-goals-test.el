;;; org-workflow-agenda-deadline-goals-test.el --- Deadline milestones -*- lexical-binding: t; -*-

(require 'ert)
(require 'org-workflow-agenda)
(load "org-workflow-agenda-workbench-test" nil t)

(ert-deftest org-workflow-deadline-goals-scope-order-and-no-execution-admission ()
  (org-workflow-workbench-test-with-files
      '("#+filetags: :project:\n#+TODO: TODO DIVE | DONE HOLD\n* Fixture\n** DIVE Project milestone\nDEADLINE: <2026-09-01 Tue>\n*** DIVE Future goal\nDEADLINE: <2026-08-21 Fri>\n*** DIVE Overdue goal\nDEADLINE: <2026-08-16 Sun>\n*** TODO Ordinary deadline\nDEADLINE: <2026-08-05 Wed>\n*** DIVE No deadline\n*** DONE Finished\nDEADLINE: <2026-08-10 Mon>\n*** HOLD Paused\n**** DIVE Held child\nDEADLINE: <2026-08-11 Tue>\n*** DIVE Habit\nDEADLINE: <2026-08-12 Wed>\n:PROPERTIES:\n:STYLE: habit\n:END:\n*** DIVE Active\n**** TODO Execute today\nSCHEDULED: <2026-08-17 Mon>\n"
        "#+filetags: :area:\n* Backlog\n** DIVE Due today\nDEADLINE: <2026-08-17 Mon>\n"
        "#+filetags: :project:workflow-closed:\n* DIVE Closed source\nDEADLINE: <2026-08-01 Sat>\n"
        "* DIVE Unscoped source\nDEADLINE: <2026-08-01 Sat>\n")
    (let ((records (org-workflow-agenda--deadline-goals)))
      (should (equal '("2026-08-01" "2026-08-16" "2026-08-17" "2026-08-21" "2026-09-01")
                     (mapcar #'car records)))
      ;; The read-only scan does not visit filtered or matching files.
      (should-not (seq-some #'get-file-buffer files)))
    (should (equal '("Execute today")
                   (mapcar #'org-workflow-target-entry-title
                           (org-workflow-target--ordered-entries))))))

(ert-deftest org-workflow-deadline-goals-read-live-unsaved-deadline ()
  (org-workflow-workbench-test-with-files
      '("#+filetags: :project:\n* DIVE Goal\nDEADLINE: <2026-08-21 Fri>\n")
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
      '("#+filetags: :project:\n#+TODO: TODO DIVE | DONE HOLD\n* Stage\n** DIVE Due today [1/3]\nDEADLINE: <2026-08-17 Mon>\n** DIVE Overdue\nDEADLINE: <2026-08-16 Sun>\n** DIVE Current\n*** TODO Work\nSCHEDULED: <2026-08-17 Mon>\n")
    (set-buffer (org-workflow-workbench-test-open))
    (let ((text (buffer-string)))
      (should (string-prefix-p "目标\n" text))
      (should (< (string-match "Due today" text)
                 (string-match "安排" text)))
      (should-not (string-match-p "阶段目标 · 截止日期" text))
      (should (string-match-p "Due today \\[1/3\\]" text))
      (should (string-match-p "逾期 1 天" text))
      (should (string-match-p "今天截止" text)))
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

(ert-deftest org-workflow-stage-goals-replace-week-goals-in-both-views ()
  (org-workflow-workbench-test-with-files
      '("#+filetags: :project:\n#+TODO: TODO DIVE | DONE HOLD\n* DIVE CMU Deep Learning Intro [1/28]\nDEADLINE: <2026-10-10 Sat>\n** TODO Neural Nets\nDEADLINE: <2026-10-09 Fri>\n")
    (set-buffer (org-workflow-workbench-test-open))
    (should (string-match-p "CMU Deep Learning Intro \\[1/28\\]" (buffer-string)))
    (should-not (string-match-p "Neural Nets"
                                (buffer-substring (point-min)
                                                  (save-excursion (goto-char (point-min)) (search-forward "安排")))))
    (should-not (string-match-p "周目标" (buffer-string)))
    (should (eq (lookup-key (current-local-map) (kbd "W")) #'org-workflow-agenda-open-goals))
    (org-workflow-agenda-console-toggle-day)
    (should (string-match-p "CMU Deep Learning Intro \\[1/28\\]" (buffer-string)))
    (should-not (string-match-p "周目标" (buffer-string)))))

(ert-deftest org-workflow-stage-goals-visit-source-without-writing ()
  (org-workflow-workbench-test-with-files
      '("#+filetags: :project:\n#+TODO: TODO DIVE | DONE HOLD\n* DIVE CMU Deep Learning Intro [1/28]\nDEADLINE: <2026-10-10 Sat>\n")
    (org-workflow-agenda-open-goals)
    (should (equal (buffer-file-name) (car files)))
    (should (equal "DIVE" (org-get-todo-state)))
    (should (equal "CMU Deep Learning Intro [1/28]" (org-get-heading t t t t)))
    (should-not (buffer-modified-p))))

(ert-deftest org-workflow-stage-goals-render-parent-with-source-narrowed-to-child ()
  (org-workflow-workbench-test-with-files
      '("#+filetags: :project:\n#+TODO: TODO DIVE | DONE HOLD\n* DIVE CMU Deep Learning Intro [1/28]\nDEADLINE: <2026-10-10 Sat>\n** TODO Neural Nets :@flow:\nSCHEDULED: <2026-10-05 Mon>\n")
    (let ((source (find-file-noselect (car files))) start end)
      (with-current-buffer source
        (goto-char (point-min)) (search-forward "** TODO Neural Nets")
        (org-back-to-heading t) (org-narrow-to-subtree)
        (setq start (point-min) end (point-max)))
      (with-temp-buffer
        (org-workflow-agenda-deadline-goals nil)
        (should (string-match-p "CMU Deep Learning Intro \\[1/28\\]" (buffer-string)))
        (should-not (string-match-p "Neural Nets" (buffer-string)))
        (goto-char (point-min)) (search-forward "CMU Deep Learning Intro")
        (let ((marker (org-get-at-bol 'org-hd-marker)))
          (should (equal "DIVE" (org-with-point-at marker (org-get-todo-state))))
          (should (equal "CMU Deep Learning Intro [1/28]"
                         (org-with-point-at marker (org-get-heading t t t t))))))
      (with-current-buffer source
        (should (buffer-narrowed-p))
        (should (= start (point-min)))
        (should (= end (point-max)))
        (should-not (buffer-modified-p))))))

(ert-deftest org-workflow-stage-goals-countdown-threshold-and-native-date ()
  (org-workflow-workbench-test-with-files
      '("#+filetags: :project:\n#+TODO: TODO DIVE | DONE HOLD\n* DIVE Overdue\nDEADLINE: <2026-08-16 Sun>\n* DIVE Due\nDEADLINE: <2026-08-17 Mon>\n* DIVE Three days\nDEADLINE: <2026-08-20 Thu>\n* DIVE Four days :@flow:\nDEADLINE: <2026-08-21 Fri>\n")
    (set-buffer (org-workflow-workbench-test-open))
    (dolist (case '(("Overdue" "逾期 1 天" error "2026-08-16")
                    ("Due" "今天截止" error "2026-08-17")
                    ("Three days" "剩 3 天" error "2026-08-20")
                    ("Four days" "剩 4 天" default "2026-08-21")))
      (goto-char (point-min)) (search-forward (car case))
      (should (eq (nth 2 case) (get-text-property (1- (point)) 'face)))
      (search-forward (nth 1 case))
      (should (eq (if (eq (nth 2 case) 'error) 'error 'org-workflow-agenda-meta)
                  (get-text-property (1- (point)) 'face)))
      (should (equal (concat "截止日期：" (nth 3 case))
                     (get-text-property (1- (point)) 'help-echo))))
    (should-not (string-match-p "@flow" (buffer-string)))
    (org-workflow-agenda-console-toggle-day)
    (should (string-match-p "Three days  剩 3 天" (buffer-string)))))

(ert-deftest org-workflow-stage-goals-reuse-progress-and-inline-day-buttons ()
  (require 'org-modern)
  (org-workflow-workbench-test-with-files
      '("#+filetags: :project:\n#+TODO: TODO DIVE | DONE HOLD\n* DIVE Goal [1/4]\nDEADLINE: <2026-08-20 Thu>\n")
    (set-buffer (org-workflow-workbench-test-open))
    (goto-char (point-min)) (search-forward "[1/4]")
    (let ((bar (get-text-property (- (point) 5) 'display)))
      (should (stringp bar))
      (should (string-match-p "1/4" bar))
      (should (eq 'org-modern-progress-complete (get-text-property 0 'face bar))))
    (search-forward "安排")
    (let ((line (line-number-at-pos)))
      (search-forward "今日")
      (should (= line (line-number-at-pos)))
      (should (button-at (1- (point))))
      (search-forward "明日")
      (should (= line (line-number-at-pos)))
      (button-activate (button-at (1- (point)))))
    (should (org-workflow-agenda--setting 'org-workflow-agenda-plan-tomorrow))
    (should-not (string-match-p "今日安排\\|明日安排\\|阶段目标 · 截止日期" (buffer-string)))))
