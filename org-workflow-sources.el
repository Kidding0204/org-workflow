;;; org-workflow-sources.el --- Bounded read-only Org sources -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Jinwang Dong
;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Commentary:
;; Background queries reuse live edits or read short-lived Org buffers.
;; Only interactive targets and records requiring live markers visit files.
;;; Code:
(require 'org-workflow-lifecycle)

(defun org-workflow-source-read (file function)
  "Call FUNCTION on FILE's text without visiting an otherwise closed file.
Reuse a visited buffer, including its unsaved text.  Return plain values or
positions; temporary source markers must not escape FUNCTION."
  (let ((existing (org-find-base-buffer-visiting file))
        (org-element-use-cache nil))
    (cond
     (existing
      (with-current-buffer existing
        (save-excursion (save-restriction (widen) (goto-char (point-min))
                                        (funcall function)))))
     ((file-readable-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (setq buffer-file-name (expand-file-name file))
        (let ((org-inhibit-startup t)) (delay-mode-hooks (org-mode)))
        (setq buffer-read-only t)
        (set-buffer-modified-p nil)
        ;; This private read buffer must neither ask to save nor run user
        ;; file-close integrations when `with-temp-buffer' releases it.
        (setq-local kill-buffer-query-functions nil)
        (setq-local kill-buffer-hook nil)
        (goto-char (point-min))
        (funcall function))))))

(defun org-workflow-source-section (title &optional create)
  "Locate the level-one TITLE in the current Org source.
When CREATE is non-nil, append a missing section; return its position."
  (goto-char (point-min))
  (or (catch 'found
        (while (re-search-forward org-heading-regexp nil t)
          (when (and (= 1 (org-outline-level))
                     (equal title (org-get-heading t t t t)))
            (throw 'found (line-beginning-position))))
        nil)
      (when create
        (goto-char (point-max))
        (unless (bolp) (insert "\n"))
        (let ((position (point))) (insert "\n* " title "\n") (1+ position)))))

(provide 'org-workflow-sources)
;;; org-workflow-sources.el ends here
