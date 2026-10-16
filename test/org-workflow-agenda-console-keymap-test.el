;;; org-workflow-agenda-console-keymap-test.el --- Local key ownership -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'org-workflow-agenda-console)

(ert-deftest workflow-console-marking-coexists-with-host-space-prefix ()
  "Mark tasks with m without intercepting the host's SPC command."
  (skip-unless (require 'evil nil t))
  (let ((host-map (make-sparse-keymap)))
    (evil-define-key* 'normal host-map (kbd "SPC") #'ignore)
    (evil-make-intercept-map host-map 'normal t)
    (dolist (role '(combined schedule candidates))
      (with-temp-buffer
        (org-agenda-mode)
        (evil-local-mode 1)
        (evil-normal-state)
        (setq-local minor-mode-map-alist
                    (cons (cons t host-map) minor-mode-map-alist))
        (evil-normalize-keymaps)
        (let* ((base (current-local-map))
               (keys '("m" "d" "f" "t" "SPC"))
               (before (mapcar (lambda (key) (key-binding (kbd key))) keys)))
          (setq-local org-workflow-agenda-sprint-view t
                      org-workflow-agenda--pane-role role)
          (org-workflow-agenda-console-bindings-setup)
          (evil-normalize-keymaps)
          (should (eq (key-binding (kbd "m")) #'org-agenda-bulk-toggle))
          (should (eq (key-binding (kbd "d")) #'org-workflow-agenda-schedule-tomorrow))
          (should (eq (key-binding (kbd "SPC")) #'ignore))
          (dolist (key '("f" "t"))
            (should (eq (key-binding (kbd key)) (nth (cl-position key keys :test #'equal) before))))
          (dolist (key '("f" "t" "SPC"))
            (should-not (assoc key org-workflow-agenda-console-bindings)))
          (setq-local org-workflow-agenda-sprint-view nil)
          (org-workflow-agenda-console-bindings-setup)
          (evil-normalize-keymaps)
          (should (eq (current-local-map) base))
          (should (equal before (mapcar (lambda (key) (key-binding (kbd key))) keys))))))))

(provide 'org-workflow-agenda-console-keymap-test)
