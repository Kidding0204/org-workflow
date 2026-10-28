;;; org-workflow-sources.el --- Bounded read-only Org sources -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Jinwang Dong
;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Commentary:
;; Background queries reuse live edits or read short-lived Org buffers.
;; Only interactive targets and records requiring live markers visit files.
;;; Code:
(require 'org-workflow-lifecycle)

(defvar org-workflow-source--reuse-reads nil
  "Non-nil during a read-only Sprint render that may reuse source facts.")

(defvar-local org-workflow-source--read-cache nil
  "Text revision and derived plain values owned by this source buffer.")

(defun org-workflow-source-cached-read (key context reader)
  "Read plain source facts with READER, reusing KEY under CONTEXT in Sprint.
Text edits invalidate this buffer's facts, including unsaved and indirect edits.
Fontification and saving alone do not.  CONTEXT covers caller dependencies
such as the execution date; it replaces the previous value for KEY.
Never cache markers, clock totals or database state here."
  (if (not org-workflow-source--reuse-reads) (funcall reader)
    (let ((revision (list (buffer-chars-modified-tick) buffer-file-name
                          org-file-tags org-todo-keywords-1 org-not-done-keywords
                          org-done-keywords org-todo-regexp org-complex-heading-regexp
                          org-odd-levels-only org-use-property-inheritance)))
      (unless (equal revision (car org-workflow-source--read-cache))
        (setq org-workflow-source--read-cache
              (cons (copy-tree revision) (make-hash-table :test #'equal))))
      (let* ((cache (cdr org-workflow-source--read-cache))
             (record (gethash key cache)))
        (unless (and record (equal context (car record)))
          (setq record (cons (copy-tree context) (funcall reader)))
          (puthash key record cache))
        ;; Callers may normalize a plist or reverse children.  Keep cache-owned
        ;; conses private so such changes cannot corrupt the following refresh.
        (copy-tree (cdr record))))))

(defun org-workflow-source--clear-read-caches ()
  "Release source facts when Workflow is disabled."
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (local-variable-p 'org-workflow-source--read-cache)
        (setq org-workflow-source--read-cache nil)))))

(defvar org-workflow-source--agenda-cache nil
  "File membership snapshot bound only during a read-only Sprint render.
The t key holds canonical Agenda paths; file-name keys memoize membership.")

(defun org-workflow-source--agenda-snapshot ()
  "Return a fresh Agenda membership table for one read-only render."
  (let ((cache (make-hash-table :test #'equal)))
    (puthash t (mapcar #'file-truename (org-agenda-files t)) cache)
    cache))

(defun org-workflow-source-agenda-file-p ()
  "Whether the current buffer belongs to the configured Agenda sources.
During Sprint rendering resolve each source once, including negative results.
Outside that bounded read, consult the current Agenda configuration directly."
  (when buffer-file-name
    (if (not org-workflow-source--agenda-cache)
        (member (file-truename buffer-file-name)
                (mapcar #'file-truename (org-agenda-files t)))
      (let ((known (gethash buffer-file-name org-workflow-source--agenda-cache 'unknown)))
        (if (not (eq known 'unknown)) known
          (puthash buffer-file-name
                   (and (member (file-truename buffer-file-name)
                                (gethash t org-workflow-source--agenda-cache)) t)
                   org-workflow-source--agenda-cache))))))

(defun org-workflow-source-read (file function)
  "Call FUNCTION on FILE's text without visiting an otherwise closed file.
Reuse a visited buffer and its native cache, including unsaved text.
Return plain values or positions; temporary source markers must not escape
FUNCTION."
  (let ((existing (org-find-base-buffer-visiting file)))
    (cond
     (existing
      (with-current-buffer existing
        (save-excursion (save-restriction (widen) (goto-char (point-min))
                                          (funcall function)))))
     ((file-readable-p file)
      (let ((org-element-use-cache nil))
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
          (funcall function)))))))

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
