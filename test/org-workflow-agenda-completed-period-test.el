;;; org-workflow-agenda-completed-period-test.el --- Sprint closure -*- lexical-binding: t; -*-
(require 'ert)
(load "org-workflow-store-test" nil t)
(require 'org-workflow-agenda)

(defmacro workflow-completed-period-fixture (&rest body)
  `(org-workflow-store-test
    (erase-buffer)
    (insert "* DIVE Project\n** TODO Stage\n*** DONE [#A] Morning one\nCLOSED: [2026-09-16 Wed 09:30] SCHEDULED: <2026-09-16 Wed>\nCLOCK: [2026-09-16 Wed 09:00]--[2026-09-16 Wed 09:30] => 0:30\n**** TODO Question :QA:\nCLOCK: [2026-09-16 Wed 09:30]--[2026-09-16 Wed 09:50] => 0:20\n*** DONE [#A] Morning two\nCLOSED: [2026-09-16 Wed 11:00] SCHEDULED: <2026-09-15 Tue>\nCLOCK: [2026-09-15 Tue 09:00]--[2026-09-15 Tue 09:20] => 0:20\nCLOCK: [2026-09-16 Wed 10:00]--[2026-09-16 Wed 11:00] => 1:00\n*** TODO [#B] Afternoon pending\nSCHEDULED: <2026-09-16 Wed>\n*** DONE [#B] Afternoon done\nCLOSED: [2026-09-16 Wed 15:00] SCHEDULED: <2026-09-16 Wed>\n*** TODO [#B] Available\n*** DONE [#C] Yesterday\nCLOSED: [2026-09-15 Tue 20:00] SCHEDULED: <2026-09-15 Tue>\n")
    (org-mode)
    (let ((org-workflow-agenda-plan-tomorrow nil)
          (org-workflow-agenda-review-start nil)
          (org-workflow-agenda-review-week nil)
          (org-workflow-agenda-sprint-view t)
          (org-workflow-projects-file file)
          (org-workflow-agenda--pane-role 'combined))
      ,@body)))

(ert-deftest workflow-completed-tasks-move-to-review-and-period-summary ()
  (workflow-completed-period-fixture
   (let ((before (buffer-string)))
     (with-temp-buffer
       (org-agenda-mode)
       (let ((inhibit-read-only t)) (org-workflow-agenda-workbench-view nil))
       (let* ((text (buffer-string))
              (done (string-match "今日已完成" text))
              (morning (string-match "上午" text))
              (afternoon (string-match "下午" text))
              (evening (string-match "晚上" text)))
         (should done)
         (should (string-match-p "已完成 2 项任务，共专注 1 时 30 分" (substring text morning afternoon)))
         (should-not (string-match-p "Morning one\\|Morning two\\|Afternoon done" (substring text 0 done)))
         (should-not (string-match-p "已完成.*项任务" (substring text afternoon evening)))
         (should (string-match-p "Morning one" (substring text done)))
         (should (= 1 (how-many "Morning one" (point-min) (point-max))))
         (should-not (string-match-p "Yesterday" text))))
     (should (equal before (buffer-string))))))

(ert-deftest workflow-tomorrow-has-no-today-completed-or-period-summary ()
  (workflow-completed-period-fixture
   (let ((org-workflow-agenda-plan-tomorrow t))
     (with-temp-buffer
       (org-agenda-mode)
       (let ((inhibit-read-only t)) (org-workflow-agenda-workbench-view nil))
       (should-not (string-match-p "今日已完成\\|已完成.*项任务\\|Morning one" (buffer-string)))))))

(ert-deftest workflow-anytime-project-heading-uses-category-face-and-italic ()
  (workflow-completed-period-fixture
   (with-temp-buffer
     (org-agenda-mode)
     (let ((inhibit-read-only t)) (org-workflow-agenda-inbox nil nil))
     (goto-char (point-min)) (search-forward "Project")
     (let ((face (get-text-property (1- (point)) 'face)))
       (should (eq (face-attribute face :slant nil nil) 'italic))
       (should (eq (face-attribute face :inherit nil nil) 'org-workflow-agenda-meta))))))
