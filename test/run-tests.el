;;; run-tests.el --- Isolated Workflow regression runner -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Jinwang Dong
;; Author: Jinwang Dong <dongjinwang040204@gmail.com>
;; Assisted-by: Codex:GPT-6
;; SPDX-License-Identifier: GPL-3.0-or-later
(require 'ert)
(require 'cl-lib)
(setq max-lisp-eval-depth 5000
      system-time-locale "C")
(defconst org-workflow-test-root
  (file-name-directory (directory-file-name (file-name-directory load-file-name))))
(add-to-list 'load-path org-workflow-test-root)
(add-to-list 'load-path (expand-file-name "test" org-workflow-test-root))
(defconst org-workflow-test-profile (make-temp-file "org-workflow-tests-" t))
(setq user-emacs-directory org-workflow-test-profile
      org-directory (expand-file-name "notes" org-workflow-test-profile)
      org-workflow-directory org-directory
      org-workflow-store-file (expand-file-name "facts.sqlite" org-workflow-test-profile)
      org-workflow-habit-file (expand-file-name "habits.org" org-directory)
      org-workflow-web-export-file (expand-file-name "history.json" org-workflow-test-profile)
      org-agenda-files nil
      org-workflow-install-default-bindings t)
(make-directory org-directory t)
(require 'evil nil t)
(require 'org-workflow)
(org-workflow-mode 1)
;; Historical compatibility tests deliberately use the old backend unless their
;; store fixture dynamically enables a fresh SQLite connection.
(setq org-workflow-store-enabled nil)
(defvar org-workflow-test-loaded nil)
(defun org-workflow-test-load-once (original file &rest arguments)
  "Load test FILE with ARGUMENTS only once while fixtures include each other."
  (let ((resolved (locate-file file load-path '("" ".el"))))
    (if (and resolved (string-suffix-p "-test.el" resolved)
             (or (member resolved org-workflow-test-loaded)
                 (featurep (intern (file-name-base resolved)))))
        t
      (when (and resolved (string-suffix-p "-test.el" resolved))
        (push resolved org-workflow-test-loaded))
      (apply original file arguments))))
(advice-add 'load :around #'org-workflow-test-load-once)
(unwind-protect
    (dolist (file (directory-files (expand-file-name "test" org-workflow-test-root) t "-test\\.el$"))
      (load file nil t))
  (advice-remove 'load #'org-workflow-test-load-once))
(ert-run-tests-batch-and-exit t)
