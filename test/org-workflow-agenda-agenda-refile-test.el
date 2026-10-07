;;; org-workflow-agenda-agenda-refile-test.el -*- lexical-binding: t; -*-
(require 'ert)
(require 'org-workflow-agenda)

(ert-deftest org-workflow-agenda-refile-targets-include-agenda-files-and-all-headings ()
  (let* ((file (make-temp-file "agenda-refile-" nil ".org"
                              "* Project\n** Stage\n*** Deep task\n"))
         (org-agenda-files (list file))
         (org-refile-targets '((nil . t)))
         (org-refile-target-verify-function nil)
         (org-refile-use-cache t)
         buffer)
    (unwind-protect
        (with-temp-buffer
          (org-mode)
          (insert "* Outside Agenda\n")
          (let ((targets (org-workflow-agenda--refile-to-agenda-files
                          (lambda () (org-refile-get-targets)))))
            (setq buffer (get-file-buffer file))
            (should (= 4 (length targets)))
            (should (seq-some (lambda (target) (string-match-p "Project/Stage/Deep task" (car target))) targets))
            (should (seq-every-p (lambda (target) (equal (expand-file-name (nth 1 target)) file)) targets))
            (should-not (seq-some (lambda (target) (string-match-p "Outside Agenda" (car target))) targets))
            (should (equal '((nil . t)) org-refile-targets))))
      (when buffer (kill-buffer buffer))
      (delete-file file))))

(ert-deftest org-workflow-agenda-refile-preserves-native-arguments-and-source-config ()
  (let ((org-refile-targets '(("other.org" :level . 1)))
        (location '("Destination" "dest.org" nil 12)))
    (should (equal (list '(4) location t)
                   (org-workflow-agenda--refile-to-agenda-files
                    (lambda (&rest args)
                      (should (equal '((org-agenda-files . t)) org-refile-targets))
                      (should-not org-refile-use-cache)
                      args)
                    '(4) location t)))
    (should (equal '(("other.org" :level . 1)) org-refile-targets))
    (should (advice-member-p #'org-workflow-agenda--refile-to-agenda-files 'org-agenda-refile))))

(ert-deftest org-workflow-agenda-refile-excludes-completed-headings-and-keeps-existing-validator ()
  (let* ((file (make-temp-file "agenda-refile-done-" nil ".org"
                              "#+TODO: TODO | DONE\n* Plain\n** TODO Pending\n** DONE Finished\n** TODO Rejected\n"))
         (org-agenda-files (list file))
         (org-refile-target-verify-function
          (lambda () (not (equal "Rejected" (org-get-heading t t t t)))))
         (original-verify org-refile-target-verify-function))
    (unwind-protect
        (let ((targets (org-workflow-agenda--refile-to-agenda-files
                        (lambda () (org-refile-get-targets)))))
          (should (= 3 (length targets)))
          (should (seq-some (lambda (target) (string-match-p "Pending" (car target))) targets))
          (should-not (seq-some (lambda (target) (string-match-p "Finished\\|Rejected" (car target))) targets))
          (should (eq original-verify org-refile-target-verify-function)))
      (when-let* ((buffer (get-file-buffer file))) (kill-buffer buffer))
      (delete-file file))))
