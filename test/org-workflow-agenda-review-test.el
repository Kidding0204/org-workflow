;;; org-workflow-agenda-review-test.el --- Review workbench regressions -*- lexical-binding: t; -*-
(require 'ert)
(require 'org-workflow-agenda)
(require 'org-workflow-core)

(ert-deftest note-gtd-review-completed-clock-tags-and-folding ()
  "Completion review starts expanded and can be explicitly folded."
  (let* ((file (make-temp-file "done-review-" nil ".org"
                 "#+filetags: :area:\n* DONE Finished :promise:@tiny:\nCLOSED: [2026-09-09 Wed 10:00]\n:LOGBOOK:\nCLOCK: [2026-09-09 Wed 09:00]--[2026-09-09 Wed 09:25] =>  0:25\n:END:\n"))
         (org-agenda-files (list file)))
    (unwind-protect
        (cl-letf (((symbol-function 'org-workflow-collection-inbox--review-files) (lambda () nil))
                  ((symbol-function 'org-workflow-target--today-string) (lambda () "2026-09-09")))
          (let ((entries (org-workflow-agenda--completed-entries)))
            (should (= 1 (length entries)))
            (should (equal '(25 25 t) (nth 4 (car entries)))))
          (with-temp-buffer
            (org-agenda-mode)
            (org-workflow-agenda-completed "")
            (should org-workflow-agenda-completed-expanded)
            (goto-char (point-min)) (search-forward "Finished")
            (should (markerp (org-get-at-bol 'org-hd-marker)))
            (should (string-match-p "今日 0:25 · 累计 0:25" (buffer-string)))))
      (when-let* ((buffer (get-file-buffer file))) (kill-buffer buffer))
      (delete-file file))))

(ert-deftest note-gtd-review-tags-toggle-and-respect-exclusive-groups ()
  (with-temp-buffer
    (org-mode)
    (insert "* TODO Item :promise:custom:\n")
    (goto-char (point-min))
    (let ((marker (point-marker)))
      (cl-letf (((symbol-function 'org-workflow-agenda--apply-planning) (lambda (fn) (funcall fn)))
                ((symbol-function 'org-get-at-bol) (lambda (_) marker)))
        (org-workflow-agenda-add-tiny-tag)
        (should (member "@tiny" (org-get-tags nil t)))
        (org-workflow-agenda-add-flow-tag)
        (should-not (member "@tiny" (org-get-tags nil t)))
        (should (member "@flow" (org-get-tags nil t)))
        (org-workflow-agenda-add-deep-tag)
        (should-not (member "@flow" (org-get-tags nil t)))
        (org-workflow-agenda-add-deep-tag)
        (org-workflow-agenda-add-promise-tag)
        (should (equal '("custom") (org-get-tags nil t)))
        (org-workflow-agenda-add-promise-tag)
        (should (member "promise" (org-get-tags nil t)))))))

(ert-deftest note-gtd-review-note-capture-targets-current-task ()
  (let ((template (assoc "n" org-capture-templates)))
    (should (eq (nth 2 template) 'plain))
    (should (equal (nth 3 template) '(function org-workflow-target-capture-location)))
    (should (equal (nth 4 template) "- [ ] %?\n  %a"))))

(ert-deftest note-gtd-review-completion-keeps-source-and-leaves-pending-list ()
  (let ((file (make-temp-file "tiny-review-" nil ".org"
                "* Collection\n:PROPERTIES:\n:JOURNAL_INBOX: 2026-09-09\n:END:\n** TODO Tiny :@tiny:\nNotes stay here\n")))
    (unwind-protect
        (with-current-buffer (find-file-noselect file)
          (goto-char (point-min)) (search-forward "Tiny")
          (let ((org-after-todo-state-change-hook nil))
            (org-workflow-inbox-state-done))
          (should (equal "DONE" (org-get-todo-state)))
          (should (string-match-p "Notes stay here" (buffer-string)))
          (should-not (org-workflow-collection-inbox--pending (list file) t))
          (should-not (buffer-modified-p)))
      (when-let* ((buffer (get-file-buffer file))) (kill-buffer buffer))
      (delete-file file))))

(ert-deftest note-gtd-review-new-agenda-resets-only-its-own-folding ()
  (let ((org-agenda-buffer-name " *review-test-agenda*"))
    (unwind-protect
        (progn
          (get-buffer-create org-agenda-buffer-name)
          (dolist (context '(t nil))
            (let ((org-workflow-agenda-journal-context context))
              (org-workflow-agenda--reset-completed-context))
            (with-current-buffer org-agenda-buffer-name
              (should org-workflow-agenda-completed-expanded))))
      (kill-buffer org-agenda-buffer-name))))

(ert-deftest note-gtd-review-continuous-processing-keeps-next-item ()
  (let ((file (make-temp-file "review-next-" nil ".org"
                "* Collection\n:PROPERTIES:\n:JOURNAL_INBOX: 2026-09-09\n:END:\n** TODO First\n** TODO Second\n** TODO Third\n")))
    (unwind-protect
        (cl-letf (((symbol-function 'org-workflow-collection-inbox--review-files) (lambda () (list file))))
          (with-temp-buffer
            (org-workflow-collection-review-mode)
            (setq org-workflow-collection-review-all t)
            (org-workflow-collection-review-refresh)
            (should (string-match-p "First" (thing-at-point 'line t)))
            (should (string-match-p "剩余 3 项" (org-workflow-inbox--classify-title)))
            (search-forward "Second")
            (let ((org-after-todo-state-change-hook nil)) (org-workflow-inbox-state-done))
            (should (string-match-p "Third" (thing-at-point 'line t)))
            (should (= 2 org-workflow-collection-review-count))
            (org-workflow-collection-review-refresh)
            (should (string-match-p "Third" (thing-at-point 'line t)))
            (let ((org-after-todo-state-change-hook nil)) (org-workflow-inbox-state-done))
            (should (string-match-p "First" (thing-at-point 'line t)))
            (let ((org-after-todo-state-change-hook nil)) (org-workflow-inbox-state-done))
            (should (= 0 org-workflow-collection-review-count))
            (should (string-match-p "没有待处理" (buffer-string)))))
      (when-let* ((buffer (get-file-buffer file))) (kill-buffer buffer))
      (delete-file file))))

(ert-deftest note-gtd-review-clock-summary-distinguishes-history-and-missing ()
  (require 'org-workflow-core)
  (cl-letf (((symbol-function 'org-workflow-target--today-string) (lambda () "2026-09-09")))
    (dolist (spec '(("" (0 0 nil) "无计时记录")
                    ("CLOCK: [2026-09-08 Tue 10:00]--[2026-09-08 Tue 10:25] =>  0:25\n"
                     (25 0 t) "今日 0:00 · 累计 0:25")
                    ("CLOCK: [2026-09-08 Tue 23:45]--[2026-09-09 Wed 00:15] =>  0:30\n"
                     (30 15 t) "今日 0:15 · 累计 0:30")
                    ("CLOCK: [2026-09-09 Wed 10:00]--[2026-09-09 Wed 10:00] =>  0:00\n"
                     (0 0 t) "今日 0:00 · 累计 0:00")))
      (with-temp-buffer
        (org-mode)
        (insert "* DONE Task\n" (car spec))
        (goto-char (point-min))
        (let ((summary (org-workflow-agenda--clock-summary)))
          (should (equal (cadr spec) summary))
          (should (equal (nth 2 spec) (org-workflow-agenda--clock-summary-text summary))))))))

(ert-deftest note-gtd-review-scheduling-outside-workflow-adds-no-tracking ()
  (require 'org-workflow-core)
  (with-temp-buffer
    (org-mode)
    (insert "* TODO Task\nSCHEDULED: <2026-09-09 Wed>\n")
    (goto-char (point-min))
    (org-schedule nil "2026-09-10")
    (should-not (org-entry-get nil "WORKFLOW_DEFER_COUNT"))
    (should-not (org-entry-get nil "WORKFLOW_COMMITTED_FOR"))))

(ert-deftest note-gtd-review-skips-unrelated-unopened-journals ()
  "An old journal must not activate file hooks just to count today's completions."
  (let ((file (make-temp-file "old-review-" nil ".org"
                              "* DONE Old\nCLOSED: [2026-09-01 Tue]\n"))
        (org-agenda-files nil))
    (unwind-protect
        (cl-letf (((symbol-function 'org-workflow-collection-inbox--review-files)
                   (lambda () (list file)))
                  ((symbol-function 'org-workflow-target--today-string)
                   (lambda () "2026-09-17"))
                  ((symbol-function 'find-file-noselect)
                   (lambda (&rest _) (ert-fail "Unrelated file was visited"))))
          (should-not (org-workflow-agenda--completed-entries))
          (should-not (find-buffer-visiting file)))
      (delete-file file))))

(ert-deftest note-gtd-review-range-uses-live-text-and-agenda-week ()
  "Week filtering survives source-buffer switches and sees unsaved completion."
  (let* ((file (make-temp-file "week-review-" nil ".org" "* TODO Work\n"))
         (org-agenda-files (list file)))
    (unwind-protect
        (cl-letf (((symbol-function 'org-workflow-collection-inbox--review-files) (lambda () nil))
                  ((symbol-function 'org-workflow-target--today-string) (lambda () "2026-09-17")))
          (with-current-buffer (find-file-noselect file)
            (erase-buffer)
            (insert "* DONE Monday\nCLOSED: [2026-09-14 Mon]\n* DONE Sunday\nCLOSED: [2026-09-20 Sun]\n* DONE Next week\nCLOSED: [2026-09-21 Mon]\n"))
          (with-temp-buffer
            (setq-local org-workflow-agenda-review-start "2026-09-14")
            (should (equal '("Monday" "Sunday")
                           (mapcar #'cadr (org-workflow-agenda--completed-entries))))))
      (when-let* ((buffer (get-file-buffer file)))
        (with-current-buffer buffer (set-buffer-modified-p nil))
        (kill-buffer buffer))
      (delete-file file))))
