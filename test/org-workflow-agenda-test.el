;;; org-workflow-agenda-test.el --- Tests for Inbox classification -*- lexical-binding: t; -*-

(require 'ert)
(require 'org-workflow-agenda)
(require 'org-capture)
(require 'org-protocol)
(require 'vulpea-journal)

(ert-deftest note-gtd-classifies-inbox-todo-as-someday ()
  (let* ((directory (make-temp-file "note-gtd-test-" t))
         (inbox (expand-file-name "inbox.org" directory))
         (projects (expand-file-name "projects.org" directory))
         (org-workflow-inbox-file inbox)
         (org-workflow-projects-file projects)
         (org-agenda-files (list inbox projects)))
    (unwind-protect
        (progn
          (with-temp-file inbox
            (insert "* TODOs\n** TODO Learn transient\nBody text.\n"))
          (with-temp-file projects
            (insert "* Someday\n"))
          (with-current-buffer (find-file-noselect inbox)
            (goto-char (point-min))
            (re-search-forward "Learn transient")
            (org-workflow-inbox-classify-someday)
            (save-buffer)
            (should-not (string-match-p "Learn transient"
                                        (buffer-string))))
          (with-current-buffer (find-file-noselect projects)
            (revert-buffer t t)
            (should (string-match-p
                     "\\* Someday\n\n\\*\\* TODO Learn transient\nBody text\\."
                     (buffer-string)))))
      (dolist (file (list inbox projects))
        (when-let* ((buffer (get-file-buffer file)))
          (kill-buffer buffer)))
      (delete-directory directory t))))

(ert-deftest note-gtd-rejects-non-todo-inbox-heading ()
  (let* ((directory (make-temp-file "note-gtd-test-" t))
         (inbox (expand-file-name "inbox.org" directory))
         (projects (expand-file-name "projects.org" directory))
         (org-workflow-inbox-file inbox)
         (org-workflow-projects-file projects))
    (unwind-protect
        (progn
          (with-temp-file inbox
            (insert "* Notes\n** SEED An idea\n"))
          (with-temp-file projects
            (insert "* Someday\n"))
          (with-current-buffer (find-file-noselect inbox)
            (goto-char (point-max))
            (should-error (org-workflow-inbox-classify-someday)
                          :type 'user-error)))
      (dolist (file (list inbox projects))
        (when-let* ((buffer (get-file-buffer file)))
          (kill-buffer buffer)))
      (delete-directory directory t))))

(ert-deftest note-gtd-org-protocol-unselected-page-saves-immediately ()
  "An unselected Firefox capture becomes a saved Inbox TODO without editing."
  (let* ((directory (make-temp-file "note-gtd-protocol-test-" t))
         (inbox (expand-file-name "inbox.org" directory))
         (org-workflow-inbox-file inbox)
         (org-capture-mode-hook nil)
         (org-capture-after-finalize-hook nil))
    (unwind-protect
        (progn
          (with-temp-file inbox (insert "#+title: Test journal\n* 收集箱\n"))
          (should (assoc "L" org-capture-templates))
          (cl-letf (((symbol-function 'org-workflow-week-capture-target)
                     (lambda (&optional _date)
                       (set-buffer (org-capture-target-buffer inbox))
                       (goto-char (point-min)) (search-forward "* 收集箱") (beginning-of-line))))
           (org-protocol-capture
           '(:template "L"
             :url "https://example.com/path?a=1"
             :title "Example Page"
             :body "")))
          (should-not (bound-and-true-p org-capture-mode))
          (with-temp-buffer
            (insert-file-contents inbox)
            (should
             (string-match-p
              (regexp-quote
               "** TODO [[https://example.com/path?a=1][Example Page]]")
              (buffer-string)))))
      (when-let* ((buffer (get-file-buffer inbox)))
        (set-buffer-modified-p nil)
        (kill-buffer buffer))
      (delete-directory directory t))))

(ert-deftest note-gtd-org-protocol-selected-text-opens-editable-capture ()
  "A selected Firefox capture keeps its link and selection open for editing."
  (let* ((directory (make-temp-file "note-gtd-protocol-test-" t))
         (inbox (expand-file-name "inbox.org" directory))
         (org-workflow-inbox-file inbox)
         (org-capture-mode-hook nil)
         (org-capture-after-finalize-hook nil))
    (unwind-protect
        (progn
          (with-temp-file inbox (insert "#+title: Test journal\n* 收集箱\n"))
          (should (assoc "p" org-capture-templates))
          (cl-letf (((symbol-function 'org-workflow-week-capture-target)
                     (lambda (&optional _date)
                       (set-buffer (org-capture-target-buffer inbox))
                       (goto-char (point-min)) (search-forward "* 收集箱") (beginning-of-line))))
           (org-protocol-capture
           '(:template "p"
             :url "https://example.com/article"
             :title "Article Title"
             :body "Selected passage")))
          (should (bound-and-true-p org-capture-mode))
          (should
           (string-match-p
            (regexp-quote
             "** TODO [[https://example.com/article][Article Title]]")
            (buffer-string)))
          (should (string-match-p (regexp-quote "Selected passage")
                                  (buffer-string))))
      (when (bound-and-true-p org-capture-mode)
        (org-capture-kill))
      (when-let* ((buffer (get-file-buffer inbox)))
        (set-buffer-modified-p nil)
        (kill-buffer buffer))
      (delete-directory directory t))))

(ert-deftest note-gtd-task-states-use-hold-and-remove-cncl ()
  "Task lifecycle uses HOLD rather than the obsolete CNCL state."
  (let ((sequence (car org-todo-keywords)))
    (should (equal '(sequence "TODO(t)" "DIVE(v)" "|"
                             "DONE(d)" "HOLD(h)")
                   sequence))
    (should-not (member "CNCL(c)" sequence))))

(ert-deftest note-gtd-statistics-ignore-hold ()
  "HOLD contributes to neither side of a task statistics cookie."
  (should (equal '(("TODO" "DIVE") ("DONE"))
                 org-provide-todo-statistics))
  (with-temp-buffer
    (org-mode)
    (insert "* TODO Parent [/]
** TODO Open
** DIVE Planned
** DONE Finished
** HOLD Deferred
")
    (goto-char (point-min))
    (org-update-statistics-cookies t)
    (should (equal "Parent [1/3]" (org-get-heading t t t t)))))

(ert-deftest note-gtd-statistics-preserve-explicit-local-knowledge-lifecycle ()
  "Workflow does not complete headings using an unrelated local lifecycle."
  (with-temp-buffer
    (insert "#+TODO: SEED FRUIT | EVERGREEN\n* SEED Knowledge [/]\n** SEED Draft\n** FRUIT Mature\n** EVERGREEN Stable\n")
    (let ((org-provide-todo-statistics '(("SEED" "FRUIT") ("EVERGREEN"))))
      (org-mode)
      (goto-char (point-min)) (search-forward "* SEED Knowledge")
      (beginning-of-line)
      (org-update-statistics-cookies t)
      (should (equal "SEED" (org-get-todo-state)))
      (should (equal "Knowledge [1/3]" (org-get-heading t t t t))))))

(ert-deftest note-gtd-statistics-preserve-hold-parent ()
  "Updating a held subtree must not reactivate or complete its HOLD parent."
  (with-temp-buffer
    (org-mode)
    (insert "* HOLD Parent [/]
** TODO Child
")
    (goto-char (point-min))
    (re-search-forward "TODO Child")
    (beginning-of-line)
    (org-todo "DONE")
    (org-up-heading-safe)
    (should (equal "HOLD" (org-get-todo-state)))
    (should (equal "Parent [1/1]" (org-get-heading t t t t)))))

(ert-deftest note-gtd-statistics-skip-unchanged-parent-state ()
  "Updating checkbox statistics must not re-enter an unchanged TODO state."
  (with-temp-buffer
    (org-mode)
    (insert "* TODO Parent [0/1]\n- [ ] Captured note\n")
    (goto-char (point-min))
    (let ((todo-calls 0))
      (cl-letf (((symbol-function 'org-todo)
                 (lambda (&rest _args) (cl-incf todo-calls))))
        (org-workflow-summary-todo 0 1))
      (should (zerop todo-calls)))))

(provide 'org-workflow-agenda-test)
;;; org-workflow-agenda-test.el ends here
