;;; org-workflow-sprint-performance-test.el --- Bounded Sprint reads -*- lexical-binding: t; -*-
(require 'ert)
(load "org-workflow-agenda-workbench-test" nil t)
(require 'org-workflow-agenda-projects)

(ert-deftest workflow-sprint-reuses-project-scan-within-render ()
  (org-workflow-workbench-test-with-files (list org-workflow-workbench-test-source)
    (let ((reads 0)
          (original (symbol-function 'org-workflow-projects--next)))
      (cl-letf (((symbol-function 'org-workflow-projects--next)
                 (lambda (&rest args) (cl-incf reads) (apply original args))))
        (org-workflow-workbench-test-open)
        (should (= 1 reads))
        (should (member "First" (org-workflow-workbench-test-titles)))
        (should (string-match-p "项目" (buffer-string)))))))

(ert-deftest workflow-sprint-resolves-agenda-membership-once-per-source ()
  (org-workflow-workbench-test-with-files (list org-workflow-workbench-test-source)
    ;; The project's many descendants must not resolve every Agenda path again.
    (let ((reads 0)
          (original (symbol-function 'org-agenda-files)))
      (cl-letf (((symbol-function 'org-agenda-files)
                 (lambda (&rest args) (cl-incf reads) (apply original args))))
        (with-temp-buffer (org-workflow-agenda-workbench-view nil))
        (should (< reads 25))))))

(ert-deftest workflow-sprint-refresh-sees-unsaved-project-and-progress-edits ()
  (org-workflow-workbench-test-with-files (list org-workflow-workbench-test-source)
    (let ((agenda (org-workflow-workbench-test-open))
          (source (find-file-noselect (car files))))
      (should (string-match-p "Stage" (buffer-string)))
      (with-current-buffer source
        (goto-char (point-min))
        (search-forward "DIVE Stage") (replace-match "DIVE Renamed")
        (search-forward "TODO First") (replace-match "DONE First"))
      (with-current-buffer agenda
        (org-agenda-redo)
        (should (string-match-p "Renamed" (buffer-string)))
        (should-not (member "First" (org-workflow-workbench-test-titles)))
        (should (string-match-p "\\[1/" (buffer-string)))))))

(ert-deftest workflow-sprint-render-does-not-retain-agenda-membership ()
  (org-workflow-workbench-test-with-files
      (list org-workflow-workbench-test-source "* DIVE Other\n** DIVE Group\n*** TODO New\n")
    (let ((second (cadr files)) (org-agenda-files (list (car files))))
      (with-temp-buffer
        (org-workflow-agenda-workbench-view nil)
        (should-not (string-match-p "New" (buffer-string))))
      (let ((org-agenda-files (list second)))
        (with-temp-buffer
          (org-workflow-agenda-workbench-view nil)
          (should (string-match-p "New" (buffer-string)))
          (should-not (string-match-p "First" (buffer-string))))))))

(ert-deftest workflow-sprint-membership-preserves-symlink-aliases-and-live-fallback ()
  (org-workflow-workbench-test-with-files (list org-workflow-workbench-test-source)
    (let ((alias (concat (car files) "-alias.org")))
      (unwind-protect
          (progn
            (make-symbolic-link (car files) alias)
            (with-current-buffer (find-file-noselect (car files))
              (let* ((org-agenda-files (list alias))
                     (org-workflow-source--agenda-cache (org-workflow-source--agenda-snapshot)))
                (should (org-workflow-source-agenda-file-p)))
              ;; Outside rendering, changes take effect in the same source buffer.
              (let ((org-agenda-files nil))
                (should-not (org-workflow-source-agenda-file-p))
                (setq org-agenda-files (list alias))
                (should (org-workflow-source-agenda-file-p)))))
        (delete-file alias)))))

(ert-deftest workflow-sprint-interrupted-render-releases-read-caches ()
  (org-workflow-workbench-test-with-files (list org-workflow-workbench-test-source)
    (cl-letf (((symbol-function 'org-workflow-agenda-project-summary)
               (lambda () (error "Interrupted summary"))))
      (should-error (with-temp-buffer (org-workflow-agenda-workbench-view nil))))
    (should-not org-workflow-source--agenda-cache)
    (should-not org-workflow-projects--read-cache)
    (with-temp-buffer
      (org-workflow-agenda-workbench-view nil)
      (should (string-match-p "First" (buffer-string))))))

(provide 'org-workflow-sprint-performance-test)
