;;; org-workflow-agenda-notes.el --- Source-backed Sprint questions -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Jinwang Dong
;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Commentary:
;; Questions retain their Org source.  Sprint previews are read-only; editing
;; uses a narrowed indirect buffer and an explicit return command.
;;; Code:
(declare-function org-workflow-collection-inbox--review-files "org-workflow-agenda-inbox" ())

(require 'org-workflow-core)
(require 'org-workflow-projects)

(defun org-workflow-agenda-pending-questions ()
  "Return source markers for all unscheduled, open, non-held questions."
  (let (rows)
    (dolist (file (delete-dups (append (org-agenda-files t)
                                     (org-workflow-collection-inbox--review-files))))
      (when (file-readable-p file)
        (org-workflow-source-read
         file
         (lambda ()
           (org-map-entries
            (lambda ()
              (when (and (org-workflow-qa-p)
                         (member (org-get-todo-state) org-not-done-keywords)
                         (not (org-entry-get nil "SCHEDULED"))
                         (not (org-workflow--held-p)))
                (push (list (or (org-entry-get nil "CAPTURED_ON") "9999")
                            file (point)) rows))) nil 'file)))))
    (mapcar (lambda (row)
              (with-current-buffer (find-file-noselect (nth 1 row))
                (copy-marker (nth 2 row))))
            (cl-stable-sort (nreverse rows) #'string< :key #'car))))

(defun org-workflow-agenda-anytime-projects ()
  "Read the first four unarranged ordinary leaves of each runnable DIVE project."
  (let (groups)
    (dolist (project (org-workflow-projects-collect))
      (when (and (equal (plist-get project :kind) "project")
                 (equal (plist-get project :state) "DIVE")
                 (not (plist-get project :blocked))
                 (not (org-workflow-projects--goal-pause (plist-get project :goal-id))))
        (org-with-point-at (org-workflow-projects-marker project)
          (let (entries)
            (org-map-entries
             (lambda ()
               (when (and (< (length entries) 4)
                          (org-workflow-target--unfinished-leaf-p)
                          (not (org-workflow-qa-p))
                          (not (org-workflow-projects-stage-p))
                          (not (org-workflow-projects-kind))
                          (not (org-entry-get nil "SCHEDULED"))
                          (not (org-workflow-target--execution-blocked-p)))
                 (push (org-workflow-item-at-marker (point-marker)) entries))) nil 'tree)
            (when entries (push (cons project (nreverse entries)) groups))))))
    (nreverse groups)))

(defvar org-workflow-agenda-note-row-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "TAB") #'org-workflow-agenda-note-toggle)
    (define-key map (kbd "e") #'org-workflow-agenda-edit-source)
    map)
  "Local actions for a question row.")

(defun org-workflow-agenda-insert-note-preview (marker)
  "Append MARKER's own body, initially folded, below its preceding Sprint row."
  (let* ((body (org-with-point-at marker
                 (save-excursion
                   ;; 先固定直属正文边界；空正文的 metadata 跳转可能到下一标题。
                   (let ((end (save-excursion (if (outline-next-heading) (point) (point-max)))))
                     (org-end-of-meta-data t)
                     (string-trim (buffer-substring-no-properties (min (point) end) end))))))
         (row-start (save-excursion (forward-line -1) (line-beginning-position))))
    (add-text-properties row-start (point)
                         (list 'keymap org-workflow-agenda-note-row-map
                               'org-workflow-note-row t 'help-echo "TAB 展开正文；e 编辑原文，C-c C-c 返回"))
    (unless (string-empty-p body)
      (insert (propertize (concat "      " (replace-regexp-in-string "\n" "\n      " body) "\n")
                          'org-workflow-note-body t 'invisible t
                          'org-marker marker 'org-hd-marker marker)))))

(defun org-workflow-agenda-note-toggle ()
  "Toggle the source body's preview on this question row."
  (interactive)
  (save-excursion
    (forward-line 1)
    (let ((begin (point)))
      (when (get-text-property begin 'org-workflow-note-body)
        (let ((end (or (next-single-property-change begin 'org-workflow-note-body) (point-max)))
              (inhibit-read-only t))
          (put-text-property begin end 'invisible (not (get-text-property begin 'invisible))))))))

(defvar-local org-workflow-agenda-edit-origin nil)
(defvar-local org-workflow-agenda-edit-window nil)
(defvar-local org-workflow-agenda-edit-start nil)
(defvar-local org-workflow-agenda-edit-position nil)

(define-minor-mode org-workflow-agenda-edit-mode
  "Edit a source subtree; finish with `org-workflow-agenda-edit-finish'."
  :lighter " 返回:C-c C-c"
  :keymap (let ((map (make-sparse-keymap)))
            (define-key map (kbd "C-c C-c") #'org-workflow-agenda-edit-finish)
            map))

(defun org-workflow-agenda-edit-source ()
  "Edit this Agenda row's original subtree in the same window."
  (interactive)
  (let ((marker (or (org-get-at-bol 'org-hd-marker) (org-get-at-bol 'org-marker)))
        (origin (point-marker)) (window (selected-window)) (start (window-start))
        (position (cons (line-number-at-pos) (current-column))))
    (unless (and (markerp marker) (marker-buffer marker)) (user-error "请选择来源条目"))
    (let ((indirect (with-current-buffer (marker-buffer marker)
                      (clone-indirect-buffer (generate-new-buffer-name "*Sprint 原文*") nil))))
      (switch-to-buffer indirect)
      (widen) (goto-char marker) (org-narrow-to-subtree)
      (org-fold-show-subtree)
      (setq-local org-workflow-agenda-edit-origin origin
                  org-workflow-agenda-edit-window window
                  org-workflow-agenda-edit-start start
                  org-workflow-agenda-edit-position position)
      (org-workflow-agenda-edit-mode 1))))

(defun org-workflow-agenda-edit-finish ()
  "Save the source and restore the originating Sprint position."
  (interactive)
  (let ((origin org-workflow-agenda-edit-origin)
        (window org-workflow-agenda-edit-window)
        (start org-workflow-agenda-edit-start)
        (position org-workflow-agenda-edit-position)
        (indirect (current-buffer)))
    (unless origin (user-error "这不是 Sprint 来源编辑窗口"))
    (with-current-buffer (or (buffer-base-buffer) (current-buffer)) (save-buffer))
    (when (window-live-p window) (select-window window))
    (when (marker-buffer origin)
      (switch-to-buffer (marker-buffer origin))
      (when (and (derived-mode-p 'org-agenda-mode) org-agenda-redo-command)
        (org-agenda-redo))
      ;; Agenda 重建会把旧 marker 挤到开头，按进入编辑前的行列恢复。
      (goto-char (point-min))
      (forward-line (1- (car position)))
      (move-to-column (min (cdr position) (- (line-end-position) (line-beginning-position))))
      (set-window-start (selected-window) (min (point-max) start) t))
    (kill-buffer indirect)))

(provide 'org-workflow-agenda-notes)
;;; org-workflow-agenda-notes.el ends here
