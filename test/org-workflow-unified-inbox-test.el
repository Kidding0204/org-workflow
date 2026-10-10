;;; org-workflow-unified-inbox-test.el --- Projects Inbox tests -*- lexical-binding: t; -*-
(require 'ert)
(require 'org-workflow-agenda-inbox)
(require 'org-workflow-weekly)

(ert-deftest workflow-unified-inbox-capture-creates-one-heading-and-keeps-date ()
  (let* ((directory (make-temp-file "workflow-inbox-" t))
         (org-workflow-projects-file (expand-file-name "projects.org" directory))
         (org-capture-mode-hook nil)
         (org-capture-after-finalize-hook nil))
    (unwind-protect
        (progn
          (with-temp-file org-workflow-projects-file (insert "* Someday\n"))
          (dotimes (_ 2)
            (org-capture nil "t")
            (insert "Collected")
            (org-capture-finalize))
          (with-current-buffer (find-file-noselect org-workflow-projects-file)
            (should (= 1 (how-many "^\\* Inbox$" (point-min) (point-max))))
            (should (= 2 (how-many "^\\*\\* TODO Collected$" (point-min) (point-max))))
            (should (= 2 (how-many (concat "^:CAPTURED_ON: " (format-time-string "%Y-%m-%d"))
                                  (point-min) (point-max))))))
      (when (bound-and-true-p org-capture-mode) (org-capture-kill))
      (when-let* ((buffer (get-file-buffer org-workflow-projects-file)))
        (with-current-buffer buffer (set-buffer-modified-p nil))
        (kill-buffer buffer))
      (delete-directory directory t))))

(ert-deftest workflow-unified-inbox-pending-keeps-direct-items-and-legacy-backlog ()
  (let* ((directory (make-temp-file "workflow-inbox-" t))
         (org-workflow-projects-file (expand-file-name "projects.org" directory))
         (legacy (expand-file-name "week.org" directory)))
    (unwind-protect
        (progn
          (with-temp-file org-workflow-projects-file
            (insert "* Inbox\n** TODO Undated\n*** TODO Detail\n** TODO Recent\n:PROPERTIES:\n:CAPTURED_ON: 2026-10-10\n:END:\n** TODO Old\n:PROPERTIES:\n:CAPTURED_ON: 2020-01-01\n:END:\n** TODO Scheduled\nSCHEDULED: <2026-10-10>\n** DONE Finished\n** HOLD Held\n* Other\n** TODO Outside\n"))
          (with-temp-file legacy
            (insert "* 收集箱\n:PROPERTIES:\n:JOURNAL_INBOX: 2020-01-01\n:END:\n** TODO Legacy backlog\n"))
          (cl-letf (((symbol-function 'current-time) (lambda () (encode-time 0 0 12 10 10 2026))))
            (should (equal '("TODO Undated" "TODO Recent")
                           (mapcar #'cadr (org-workflow-collection-inbox--pending
                                          (list org-workflow-projects-file legacy) nil t))))
            (should (equal '("TODO Undated" "TODO Old" "TODO Legacy backlog" "TODO Recent")
                           (mapcar #'cadr (org-workflow-collection-inbox--pending
                                          (list org-workflow-projects-file legacy) t t)))))
          (with-current-buffer (find-file-noselect org-workflow-projects-file)
            (goto-char (point-min))
            (should-not (org-workflow-collection-inbox-entry-p))
            (search-forward "TODO Undated")
            (should (org-workflow-collection-inbox-entry-p))
            (should (markerp (org-workflow-inbox--classification-marker)))
            (should-not (buffer-modified-p))))
      (dolist (file (list org-workflow-projects-file legacy))
        (when-let* ((buffer (get-file-buffer file))) (kill-buffer buffer)))
      (delete-directory directory t))))

(ert-deftest workflow-new-week-has-no-collection-section ()
  (let* ((directory (make-temp-file "workflow-week-" t))
         (vulpea-default-notes-directory directory)
         body)
    (unwind-protect
        (cl-letf (((symbol-function 'vulpea-create)
                   (lambda (_title file &rest options)
                     (setq body (plist-get options :body))
                     (with-temp-file file (insert body))))
                  ((symbol-function 'org-workflow-week--ensure-area) #'ignore)
                  ((symbol-function 'org-workflow-week-sync-agenda) #'ignore))
          (org-workflow-week-ensure "2026-10-10")
          (should (string-match-p "随记" body))
          (should (string-match-p "周回顾" body))
          (should-not (string-match-p "收集箱\\|JOURNAL_INBOX" body)))
      (delete-directory directory t))))

(provide 'org-workflow-unified-inbox-test)
