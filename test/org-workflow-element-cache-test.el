;;; org-workflow-element-cache-test.el --- Native cache consistency -*- lexical-binding: t; -*-
(require 'ert)
(require 'org-workflow)
(load "org-workflow-items-test" nil t)

(ert-deftest workflow-complete-updates-warm-native-cache ()
  (with-temp-buffer
    (let ((org-mode-hook nil)
          (org-element-use-cache t)
          (org-todo-keywords '((sequence "TODO" "|" "DONE")))
          (org-after-todo-state-change-hook nil)
          (org-log-done nil))
      (org-mode)
      (insert "* TODO Task\n")
      (goto-char (point-min))
      (should (equal "TODO" (org-element-property :todo-keyword (org-element-at-point))))
      (cl-letf (((symbol-function 'org-workflow-item-changed) #'ignore)
                ((symbol-function 'org-workflow-clock--clock-matches-p) (lambda (_) nil))
                ((symbol-function 'org-clocking-p) (lambda () nil)))
        (org-workflow-item-complete
         (org-workflow-target-entry-create :marker (point-marker))))
      (goto-char (point-min))
      (should (equal "DONE" (org-element-property :todo-keyword (org-element-at-point)))))))

(ert-deftest workflow-repeat-completion-updates-warm-native-schedule ()
  (workflow-items-test
   (let ((org-element-use-cache t))
     (org-with-point-at habit-marker
       (let ((before (org-entry-get nil "SCHEDULED")))
         (org-element-at-point)
         (cl-letf (((symbol-function 'org-workflow--request-gnome-refresh) #'ignore))
           (org-workflow-item-complete habit-item))
         (let ((after (org-entry-get nil "SCHEDULED")))
           (should-not (equal before after))
           (should (equal after (let ((org-element-use-cache nil))
                                 (org-entry-get nil "SCHEDULED"))))))))))

(ert-deftest workflow-refresh-hook-keeps-native-change-tracking ()
  (with-temp-buffer
    (let ((org-mode-hook nil)
          (org-element-use-cache t)
          (org-workflow-target-stack nil)
          (org-workflow-stack-empty-hook nil))
      (org-mode)
      (insert "* Task\n:PROPERTIES:\n:VALUE: before\n:END:\n")
      (goto-char (point-min))
      (should (equal "before" (org-entry-get nil "VALUE")))
      (let* ((marker (point-marker))
             (item (org-workflow-target-entry-create :marker marker))
             (org-workflow-current-changed-hook
              (list (lambda () (org-with-point-at marker (org-entry-put nil "VALUE" "after"))))))
        (cl-letf (((symbol-function 'org-workflow-target-current-marker)
                   (lambda () (and org-workflow-target-stack marker)))
                  ((symbol-function 'org-workflow-target--sorted-entries) (lambda () (list item)))
                  ((symbol-function 'org-workflow-target--valid-entry-p) (lambda (_) t))
                  ((symbol-function 'org-workflow-target--selected-entry) (lambda () nil)))
          (org-workflow-target-refresh t))
        (should (equal "after" (org-entry-get nil "VALUE")))))))

(ert-deftest workflow-habit-file-hooks-keep-native-change-tracking ()
  (let ((file (make-temp-file "workflow-cache-" nil ".org" "* TODO Other\n")))
    (unwind-protect
        (with-temp-buffer
          (let ((org-mode-hook nil)
                (org-element-use-cache t))
            (org-mode)
            (insert "* Task\n:PROPERTIES:\n:VALUE: before\n:END:\n")
            (goto-char (point-min))
            (should (equal "before" (org-entry-get nil "VALUE")))
            (let* ((marker (point-marker))
                   (find-file-hook
                    (list (lambda () (org-with-point-at marker
                                       (org-entry-put nil "VALUE" "after"))))))
              (cl-letf (((symbol-function 'org-workflow-habits-files) (lambda () (list file))))
                (org-workflow-habits--map #'ignore))
              (should (equal "after" (org-entry-get nil "VALUE"))))))
      (when-let* ((buffer (get-file-buffer file))) (kill-buffer buffer))
      (delete-file file))))

;;; org-workflow-element-cache-test.el ends here
