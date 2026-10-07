;;; zzz-org-workflow-optional-integrations-test.el --- Shared integrations -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Jinwang Dong
;; Author: Jinwang Dong <dongjinwang040204@gmail.com>
;; Assisted-by: Codex:GPT-6
;; SPDX-License-Identifier: GPL-3.0-or-later
(require 'ert)
(require 'org-workflow)
(require 'evil nil t)
(require 'embark-org nil t)

(defmacro org-workflow-test--isolated-integrations (&rest body)
  "Run BODY with isolated integration ownership and shared Agenda maps."
  (declare (indent 0))
  `(let ((org-workflow-mode t)
         (org-workflow--hooks nil) (org-workflow--advices nil)
         (org-workflow--keys nil) (org-workflow--variable-advices nil)
         (org-workflow--list-entries nil)
         (org-agenda-mode-map (make-sparse-keymap)))
     (unwind-protect (progn ,@body) (org-workflow--remove-integrations))))

(ert-deftest zzz-org-workflow-evil-bindings-respect-opt-in-and-restore ()
  "Real Evil state bindings are optional and restore previous definitions."
  (skip-unless (featurep 'evil))
  (org-workflow-test--isolated-integrations
    (let ((org-workflow-install-default-bindings nil))
      (evil-define-key* 'normal org-agenda-mode-map "j" #'ignore)
      (org-workflow-agenda-evil-bindings)
      (let ((map (evil-get-auxiliary-keymap org-agenda-mode-map 'normal)))
        (should (eq (keymap-lookup map "j") #'ignore))
        (should-not (keymap-lookup map "a"))))
    (let ((org-workflow-install-default-bindings t))
      (org-workflow-agenda-evil-bindings)
      (org-workflow-agenda-evil-bindings)
      (let ((map (evil-get-auxiliary-keymap org-agenda-mode-map 'normal)))
        (should (eq (keymap-lookup map "j") #'org-agenda-next-item))
        (should (= 4 (length org-workflow--keys)))
        ;; Changes made after activation must survive disabling.
        (keymap-set map "a" #'forward-char)
        (org-workflow--remove-integrations)
        (should (eq (keymap-lookup map "j") #'ignore))
        (should (eq (keymap-lookup map "a") #'forward-char))))))

(ert-deftest zzz-org-workflow-embark-bindings-and-action-hooks-restore ()
  "Embark integration restores its key and retains unrelated action hooks."
  (skip-unless (featurep 'embark-org))
  (org-workflow-test--isolated-integrations
    (let ((embark-org-heading-map (make-sparse-keymap))
          (embark-around-action-hooks '((other-action ignore)))
          (org-workflow-install-default-bindings t))
      (keymap-set embark-org-heading-map "f" #'ignore)
      (org-workflow-focus-timer--enable)
      (org-workflow-focus-timer--enable)
      (should (eq (keymap-lookup embark-org-heading-map "f") #'org-workflow-focus-timer-start))
      (should (= 1 (length org-workflow--list-entries)))
      (org-workflow--remove-integrations)
      (should (eq (keymap-lookup embark-org-heading-map "f") #'ignore))
      (should (equal embark-around-action-hooks '((other-action ignore)))))))

(ert-deftest zzz-org-workflow-embark-preserves-preexisting-and-user-edited-hooks ()
  "Disabling retains supplied action hooks and later replacement entries."
  (skip-unless (featurep 'embark-org))
  (org-workflow-test--isolated-integrations
    (let ((embark-org-heading-map (make-sparse-keymap))
          (embark-around-action-hooks '((org-workflow-focus-timer-start embark-org--at-heading)))
          (org-workflow-install-default-bindings nil))
      (keymap-set embark-org-heading-map "f" #'ignore)
      (org-workflow-focus-timer--enable)
      (should-not org-workflow--list-entries)
      (should (eq (keymap-lookup embark-org-heading-map "f") #'ignore))
      (org-workflow--remove-integrations)
      (should (assoc 'org-workflow-focus-timer-start embark-around-action-hooks))
      (setq embark-around-action-hooks nil
            org-workflow-install-default-bindings t)
      (org-workflow-focus-timer--enable)
      (setcdr (assoc 'org-workflow-focus-timer-start embark-around-action-hooks) '(ignore))
      (keymap-set embark-org-heading-map "f" #'forward-char)
      (org-workflow--remove-integrations)
      (should (equal embark-around-action-hooks '((org-workflow-focus-timer-start ignore))))
      (should (eq (keymap-lookup embark-org-heading-map "f") #'forward-char)))))

(ert-deftest zzz-org-workflow-agenda-retains-unrelated-custom-commands ()
  "Enabling and disabling preserve user Agenda commands and later edits."
  (org-workflow-mode -1)
  (let ((org-agenda-custom-commands '(("x" "User Agenda" agenda "")
                                     ("d" "Original daily" agenda ""))))
    (unwind-protect
        (progn
          (org-workflow-mode 1)
          (should (equal (assoc "x" org-agenda-custom-commands)
                         '("x" "User Agenda" agenda "")))
          (should (equal (cadr (assoc "d" org-agenda-custom-commands)) "Sprint"))
          (push '("y" "Later user Agenda" todo "") org-agenda-custom-commands)
          (org-workflow-mode -1)
          (should (assoc "x" org-agenda-custom-commands))
          (should (assoc "y" org-agenda-custom-commands))
          (should (equal (assoc "d" org-agenda-custom-commands)
                         '("d" "Original daily" agenda "")))
          (should-not (assoc "s" org-agenda-custom-commands)))
      (org-workflow-mode -1)))
  (org-workflow-mode 1))
