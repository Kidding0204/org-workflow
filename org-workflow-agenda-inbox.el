;;; org-workflow-agenda-inbox.el --- note-gtd-inbox Workflow component -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Jinwang Dong
;; Author: Jinwang Dong <dongjinwang040204@gmail.com>
;; Assisted-by: Codex:GPT-6
;; SPDX-License-Identifier: GPL-3.0-or-later
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;; Commentary:
;; A component of org-workflow.  Activation is coordinated by its global mode.
;;; Code:
(declare-function org-workflow-agenda-ensure-writeable "org-workflow-agenda-plan-undo" ())

(require 'org-workflow-lifecycle)

(declare-function org-workflow-agenda--clear-selection "org-workflow-agenda-layout" ())
(defvar org-workflow-collection-review-count)
(require 'org-archive)
(require 'org-workflow-sources)
;;; org-workflow-agenda-inbox.el --- Capture classification and continuous collection review -*- lexical-binding: t; -*-
;;; Commentary:
;; Internal implementation module loaded by org-workflow-agenda.
;;; Code:
(require 'cl-lib)

(require 'org)

(require 'org-capture)

(require 'transient)

;; Inbox classification
(defcustom org-workflow-inbox-file
  (expand-file-name "inbox.org" (org-workflow--directory))
  "Org file containing unprocessed Inbox items."
  :type 'file
  :group 'org)

(defun org-workflow-inbox--same-file-p (file-a file-b)
  "Return non-nil when FILE-A and FILE-B name the same file."
  (and file-a file-b
       (string-equal (file-truename file-a)
                     (file-truename file-b))))

(defun org-workflow-inbox--someday-location ()
  "Return an `org-refile' location for the level-one Someday heading."
  (let ((file (expand-file-name org-workflow-projects-file)))
    (unless (file-readable-p file)
      (user-error "Projects file is not readable: %s" file))
    (with-current-buffer (find-file-noselect file)
      (org-with-wide-buffer
       (let ((position
              (car
               (delq nil
                     (org-map-entries
                      (lambda ()
                        (when (and (= (org-outline-level) 1)
                                   (string= (org-get-heading t t t t) "Someday"))
                          (point)))
                      nil 'file)))))
         (unless position
           (user-error "No level-one Someday heading in %s" file))
         (list "Someday" file nil position))))))

(defun org-workflow-collection-inbox-capture-target ()
  "Locate or create the level-one Inbox in the projects file."
  (let ((file (expand-file-name org-workflow-projects-file)))
    (make-directory (file-name-directory file) t)
    (set-buffer (org-capture-target-buffer file))
    (widen)
    (goto-char (org-workflow-source-section "Inbox" t))))

(defun org-workflow-inbox--archive-buffer (file)
  "Visit FILE for automatic archiving only when its live text is safe to save."
  (let ((buffer (or (get-file-buffer file) (find-file-noselect file))))
    (with-current-buffer buffer
      (when (or buffer-read-only (buffer-modified-p)
                (not (verify-visited-file-modtime buffer)))
        (user-error "Inbox 归档暂缓，请先保存或重新读取 %s" file)))
    buffer))

(defun org-workflow-inbox--archive-one (marker target)
  "Archive MARKER to TARGET, saving this move before starting the next.
Restore exact buffer snapshots if the destination was not persisted.  Native
Org archive operations can rearrange undo lists across buffers, so a combined
change group is not a reliable rollback for this operation."
  (let* ((source (marker-buffer marker))
         (buffers (delete-dups (list source target)))
         (before (mapcar (lambda (buffer)
                           (with-current-buffer buffer
                             (org-with-wide-buffer
                              (list buffer (buffer-string) buffer-undo-list))))
                         buffers))
         (ids (org-with-point-at marker
                (delq nil (org-map-entries
                           (lambda () (org-entry-get nil "ID")) nil 'tree))))
         archive-text persisted)
    (unwind-protect
        (let ((org-archive-subtree-save-file-p nil)
              (org-workflow-store-enabled nil))
          (org-with-point-at marker (org-archive-subtree))
          (with-current-buffer target
            (setq archive-text (org-with-wide-buffer (buffer-string)))
            (save-buffer)
            (setq persisted t))
          (dolist (id ids) (org-id-add-location id (buffer-file-name target)))
          (with-current-buffer source (save-buffer))
          (org-id-locations-save))
      ;; An after-save hook may signal after the destination reached disk.
      ;; In that case keep the source deletion pending, just as on source-save
      ;; failure; saving it later cannot discard the archived task.
      (unless persisted
        (setq persisted
              (and archive-text (file-readable-p (buffer-file-name target))
                   (with-temp-buffer
                     (insert-file-contents (buffer-file-name target))
                     (equal archive-text (buffer-string))))))
      (unless persisted
        (dolist (snapshot before)
          (with-current-buffer (car snapshot)
            (org-with-wide-buffer
             (replace-region-contents (point-min) (point-max) (nth 1 snapshot))
             (setq buffer-undo-list (nth 2 snapshot))
             (set-buffer-modified-p nil))))
        (dolist (id ids) (org-id-add-location id (buffer-file-name source)))))))

(defun org-workflow-inbox--retained-notes-p ()
  "Whether this subtree holds questions or identified non-task notes."
  ;; 问答与想法属于长期笔记，不能随普通 Inbox 完成项自动移入归档流。
  (let (notes)
    (org-map-entries
     (lambda ()
       (when (or (org-workflow-qa-p)
                 (and (not (org-get-todo-state)) (org-entry-get nil "ID")))
         (setq notes t))) nil 'tree)
    notes))

(defun org-workflow-inbox-archive-done (date)
  "Archive direct DONE Inbox items through settled DATE, preserving full trees.
Newer CLOSED entries remain until their day is settled.  Follow native Org
archive locations; save destinations before removing source entries on disk."
  (let ((file (expand-file-name org-workflow-projects-file)) positions)
    (when (file-readable-p file)
      (org-workflow-source-read
       file
       (lambda ()
         (when-let* ((position (org-workflow-source-section "Inbox")))
           (goto-char position)
           (org-map-entries
            (lambda ()
              (when (and (= 2 (org-outline-level))
                         (equal "DONE" (org-get-todo-state))
                         (not (org-workflow-inbox--retained-notes-p)))
                (let ((closed (org-workflow-target--timestamp-date (org-entry-get nil "CLOSED"))))
                  (when (or (null closed) (not (string< date closed)))
                    (push (point) positions))))) nil 'tree)))))
    (when positions
      (condition-case error-data
          (let* ((source (org-workflow-inbox--archive-buffer file))
                 (markers (mapcar (lambda (position)
                                    (with-current-buffer source (copy-marker position)))
                                  positions))
                 moves)
            (unwind-protect
                (progn
                  ;; Validate every destination before changing any source.
                  (dolist (marker markers)
                    (org-with-point-at marker
                      (let* ((location (org-archive--compute-location
                                        (or (org-entry-get nil "ARCHIVE" 'inherit)
                                            org-archive-location)))
                             (target (org-workflow-inbox--archive-buffer (car location))))
                        (push (cons marker target) moves))))
                  (dolist (move (nreverse moves))
                    (org-workflow-inbox--archive-one (car move) (cdr move)))
                  (length positions))
              (dolist (marker markers) (set-marker marker nil))))
        (user-error (message "%s" (error-message-string error-data)) 0)))))

(defun org-workflow-collection-inbox--heading-p ()
  "Return non-nil for the unified Inbox or a legacy collection heading."
  (or (org-entry-get nil "JOURNAL_INBOX")
      (and (= (org-outline-level) 1)
           (string= (org-get-heading t t t t) "Inbox")
           (org-workflow-inbox--same-file-p
            buffer-file-name org-workflow-projects-file))))

(defun org-workflow-collection-inbox-entry-p ()
  "Return non-nil below the projects Inbox or a legacy collection heading."
  (save-excursion
    (org-back-to-heading t)
    (catch 'inbox
      (while (org-up-heading-safe)
        (when (org-workflow-collection-inbox--heading-p) (throw 'inbox t)))
      nil)))

(defun org-workflow-collection-inbox-visit ()
  "Visit the projects Inbox without opening a capture session."
  (interactive)
  (let ((buffer (current-buffer)) marker)
    (unwind-protect
        (progn (org-workflow-collection-inbox-capture-target)
               (setq marker (point-marker)))
      (set-buffer buffer))
    (pop-to-buffer (marker-buffer marker))
    (goto-char marker)
    (org-fold-show-context 'agenda)
    (org-fold-show-subtree)))

(defun org-workflow-inbox--classification-marker ()
  "Resolve and validate the collection item in Org or its review."
  (when (bound-and-true-p org-workflow-agenda--sprint-buffer-p)
    (org-workflow-agenda-ensure-writeable))
  (if (or (derived-mode-p 'org-workflow-collection-review-mode)
          (and (derived-mode-p 'org-agenda-mode)
               (get-text-property (line-beginning-position) 'org-workflow-agenda-inbox-entry)))
      (org-workflow-collection-review--marker)
    (unless (derived-mode-p 'org-mode)
      (user-error "请在收集条目或收集回顾中使用"))
    (save-excursion
      (org-back-to-heading t)
      (unless (and (not (org-entry-get nil "JOURNAL_INBOX"))
                   (or (org-workflow-inbox--same-file-p buffer-file-name org-workflow-inbox-file)
                       (org-workflow-collection-inbox-entry-p)))
        (user-error "请选择 Inbox 或旧日记收集箱内的条目"))
      (point-marker))))

(defun org-workflow-inbox--project-files ()
  "Return Agenda files recognized as projects or areas by Workflow."
  (require 'org-workflow-core)
  (cl-remove-if-not
   (lambda (file)
     (and (file-readable-p file)
          (with-current-buffer (find-file-noselect file)
            (org-workflow--file-kind))))
   (delete-dups (copy-sequence (org-agenda-files t)))))

(defun org-workflow-inbox--refresh-view (buffer)
  "Refresh the originating collection BUFFER after a successful edit."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (cond ((derived-mode-p 'org-workflow-collection-review-mode)
             (org-workflow-collection-review-refresh))
            ((and (derived-mode-p 'org-agenda-mode)
                  (bound-and-true-p org-workflow-agenda--sprint-buffer-p))
             (org-workflow-agenda--clear-selection)
             (org-agenda-redo))))))

(defun org-workflow-inbox--classify-move (kind)
  "Move the original collection item to KIND using native refile."
  (let ((marker (org-workflow-inbox--classification-marker))
        (review (current-buffer)))
    (org-with-point-at marker
      (org-with-wide-buffer
       (pcase kind
         ('someday
          (unless (equal (org-get-todo-state) "TODO")
            (user-error "Someday 只接收 TODO 条目"))
          (org-refile nil nil (org-workflow-inbox--someday-location)))
         (_
          (let* ((files
                  (pcase kind
                    ('project (org-workflow-inbox--project-files))))
                 (org-refile-targets
                  (pcase kind
                    ('project (unless files (user-error "Agenda 中没有标记 project/area 的文件"))
                              `((,files :maxlevel . 5)))
                    (_ org-refile-targets)))
                 (org-refile-use-cache nil))
            (call-interactively #'org-refile))))))
    (org-workflow-inbox--refresh-view review)))

(defun org-workflow-inbox-classify-someday ()
  "Move a collected TODO to Projects/Someday."
  (interactive)
  (org-workflow-inbox--classify-move 'someday))

(defun org-workflow-inbox-classify-project ()
  "Choose a project or area for the collected subtree."
  (interactive)
  (org-workflow-inbox--classify-move 'project))

(defun org-workflow-inbox-classify-refile ()
  "Choose any configured native refile destination."
  (interactive)
  (org-workflow-inbox--classify-move 'other))

(defun org-workflow-inbox-classify-visit ()
  "Visit the collected item's original text."
  (interactive)
  (let ((marker (org-workflow-inbox--classification-marker)))
    (pop-to-buffer (marker-buffer marker))
    (widen)
    (goto-char marker)
    (org-fold-show-context 'agenda)
    (org-fold-show-subtree)))

(defun org-workflow-inbox--classify-title ()
  "Describe the current item and pending count in the review menu."
  (let ((count (and (derived-mode-p 'org-workflow-collection-review-mode)
                    org-workflow-collection-review-count)))
    (org-with-point-at (org-workflow-inbox--classification-marker)
      (concat "归类 · " (when count (format "剩余 %d 项 · " count))
              (truncate-string-to-width (org-get-heading t nil t t) 48 nil nil "…")))))

(defun org-workflow-inbox--classify-todo-p ()
  "Whether the collected item can move to Someday."
  (org-with-point-at (org-workflow-inbox--classification-marker)
    (equal (org-get-todo-state) "TODO")))

(defun org-workflow-inbox--state (state)
  "Set the original collected task to STATE, saving and refreshing its review."
  (let ((marker (org-workflow-inbox--classification-marker))
        (review (current-buffer)))
    (org-with-point-at marker
      (org-with-wide-buffer
       (org-todo state)
       (when buffer-file-name (save-buffer))))
    (org-workflow-inbox--refresh-view review)))

(defun org-workflow-inbox-state-todo ()
  "Mark the collected task TODO."
  (interactive) (org-workflow-inbox--state "TODO"))

(defun org-workflow-inbox-state-done ()
  "Complete the collected task without moving it."
  (interactive) (org-workflow-inbox--state "DONE"))

(defun org-workflow-inbox-state-hold ()
  "Put the collected task on HOLD."
  (interactive) (org-workflow-inbox--state "HOLD"))

(transient-define-prefix org-workflow-inbox-classify ()
  "Choose where the collected item belongs, preserving its contents and state."
  :variable-pitch t
  :column-widths '(24 24)
  [:description org-workflow-inbox--classify-title
   ["明确去向"
    ("p" "行动 → 项目／领域" org-workflow-inbox-classify-project)
    ("s" "暂缓 → Someday" org-workflow-inbox-classify-someday
     :inapt-if-not org-workflow-inbox--classify-todo-p)]
   ["状态"
    ("t" "→ TODO" org-workflow-inbox-state-todo)
    ("d" "→ DONE" org-workflow-inbox-state-done)
    ("h" "→ HOLD" org-workflow-inbox-state-hold)]
   ["其他"
    ("r" "选择其他位置" org-workflow-inbox-classify-refile)
    ("RET" "查看／编辑原文" org-workflow-inbox-classify-visit)
    ("q" "暂不处理" transient-quit-one)]]
  (interactive)
  (org-workflow-inbox--classification-marker)
  (transient-setup 'org-workflow-inbox-classify))

;; refile 后自动保存 agenda 文件
(defun org-workflow-save-org-buffers ()
  "Save `org-agenda-files' buffers without user confirmation."
  (interactive)
  (message "Saving org-agenda-files buffers...")
  (save-some-buffers t (lambda ()
                         (when (member (buffer-file-name) org-agenda-files) t)))
  (message "Saving org-agenda-files buffers... done"))

(defvar org-workflow-refile-defer-save nil
  "Non-nil only inside a Workflow batch which saves after its facts commit.")

(defun org-workflow-refile--save-participants (original &rest args)
  "Call ORIGINAL with ARGS and save buffers involved in a successful refile.
Save destinations first, so a destination write failure cannot persist removal
from the source.  Navigation, cancellation and failed moves save no buffers."
  (let* ((source (current-buffer)) destinations
         (org-after-refile-insert-hook
          (cons (lambda () (cl-pushnew (current-buffer) destinations))
                org-after-refile-insert-hook))
         (result (apply original args)))
    (when (and destinations (not org-workflow-refile-defer-save))
      (dolist (buffer (delete-dups (append destinations (list source))))
        (when (buffer-live-p buffer)
          (with-current-buffer buffer
            (when (and buffer-file-name (buffer-modified-p))
              (save-buffer))))))
    result))

(defvar-local org-workflow-collection-review-all nil)

(defun org-workflow-collection-inbox--review-files ()
  "Return the unified projects Inbox source without querying journal indexes."
  (when (file-readable-p org-workflow-projects-file)
    (list (expand-file-name org-workflow-projects-file))))

(defun org-workflow-collection-inbox--pending (files &optional all unscheduled)
  "Return date/title/marker records still in collection headings in FILES.
Include items captured in the last seven calendar days unless ALL.
Undated unified Inbox items remain visible.  Nested headings belong to their
containing captured item.  UNSCHEDULED selects only optional Sprint items
before visiting any source."
  (let ((today (format-time-string "%Y-%m-%d"))
        (cutoff (format-time-string
                 "%Y-%m-%d" (time-subtract (current-time) (days-to-time 6))))
        entries)
    (dolist (file (delete-dups (copy-sequence files)))
      (when (file-readable-p file)
        (let ((matches
               (org-workflow-source-read
                file
                (lambda ()
                  (let (locations)
                    (org-map-entries
                     (lambda ()
                       (when (org-workflow-collection-inbox--heading-p)
                         (let ((date (org-entry-get nil "JOURNAL_INBOX"))
                               (level (1+ (org-outline-level)))
                               (end (save-excursion (org-end-of-subtree t t))))
                           (save-excursion
                             (forward-line 1)
                             (while (re-search-forward org-heading-regexp end t)
                               (let ((captured (or (org-entry-get nil "CAPTURED_ON") date)))
                                 (when (and (= level (org-outline-level))
                                            (org-get-todo-state)
                                            (or all (not captured)
                                                (and (not (string< captured cutoff))
                                                     (not (string< today captured))))
                                            (not (equal (org-get-todo-state) "DONE"))
                                            (or (not unscheduled)
                                                (not (or (org-entry-get nil "SCHEDULED")
                                                         (org-entry-get nil "DEADLINE")
                                                         (org-entry-is-done-p)
                                                         (org-workflow--held-p)
                                                         (org-workflow-habit-p)))))
                                   (push (list (or captured "")
                                               (substring-no-properties (org-get-heading t nil t t))
                                               (line-beginning-position)) locations))))))))
                     nil 'file)
                    (nreverse locations))))))
          (when matches
            (with-current-buffer (find-file-noselect file)
              (dolist (record matches)
                (push (list (car record) (cadr record) (copy-marker (nth 2 record))) entries)))))))
    (cl-stable-sort (nreverse entries) #'string< :key #'car)))

(defun org-workflow-collection-review--marker ()
  "Return a validated original marker, rejecting stale review rows."
  (let ((marker (get-text-property (line-beginning-position) 'org-marker))
        (title (get-text-property (line-beginning-position) 'org-workflow-collection-review-title)))
    (when (and (derived-mode-p 'org-agenda-mode)
               (> (length org-agenda-bulk-marked-entries) 1))
      (user-error "归类或完成收集项时请只选择一项"))
    (unless (and (markerp marker) (marker-buffer marker))
      (user-error "请先选择一个收集项"))
    (unless (org-with-point-at marker
              (and (org-at-heading-p) (org-workflow-collection-inbox-entry-p)
                   (equal title (substring-no-properties (org-get-heading t nil t t)))))
      (user-error "原条目已变更，请按 g 刷新"))
    marker))

(defun org-workflow-collection-inbox--scheduled-files ()
  "Return non-Agenda journals with unfinished scheduled collection tasks."
  (cl-remove-if-not
   (lambda (file)
     (when (file-readable-p file)
       (org-workflow-source-read file
				 (lambda ()
				   (catch 'scheduled
				     (org-map-entries
				      (lambda ()
					(when (and (member (org-get-todo-state) org-not-done-keywords)
						   (org-entry-get nil "SCHEDULED")
						   (org-workflow-collection-inbox-entry-p))
					  (throw 'scheduled t))) nil 'file)
				     nil)))))
   (cl-remove-if
    (lambda (file)
      (seq-some (lambda (agenda-file) (org-workflow-inbox--same-file-p file agenda-file))
                (org-agenda-files t)))
    (org-workflow-collection-inbox--review-files))))

(defun org-workflow-collection-review-visit ()
  "Visit the original collection item at point."
  (interactive)
  (let ((marker (org-workflow-collection-review--marker)))
    (pop-to-buffer (marker-buffer marker))
    (widen)
    (goto-char marker)
    (org-fold-show-context 'agenda)
    (org-fold-show-subtree)))

(defun org-workflow-collection-review-refile ()
  "Refile the original collection item, then refresh the review."
  (interactive)
  (when (bound-and-true-p org-workflow-agenda--sprint-buffer-p)
    (org-workflow-agenda-ensure-writeable))
  (let ((review (current-buffer))
        (marker (org-workflow-collection-review--marker)))
    (org-with-point-at marker
      (org-with-wide-buffer
       (unless (org-workflow-collection-inbox-entry-p)
         (user-error "此条目已离开收集箱，请按 g 刷新"))
       (call-interactively #'org-refile)))
    (with-current-buffer review (org-workflow-collection-review-refresh))))

(defvar org-workflow-collection-review-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (org-workflow--keymap-set map "RET" #'org-workflow-collection-review-visit)
    (org-workflow--keymap-set map "r" #'org-workflow-collection-review-refile)
    (org-workflow--keymap-set map "a" #'org-workflow-inbox-classify)
    (org-workflow--keymap-set map "C-c o i" #'org-workflow-inbox-classify)
    (org-workflow--keymap-set map "g" #'org-workflow-collection-review-refresh)
    map))

(define-derived-mode org-workflow-collection-review-mode special-mode "收集回顾"
  "Read-only view of original daily collection entries.")

(defvar-local org-workflow-collection-review-count 0
  "Number of pending original collection entries in the rendered review.")

(defun org-workflow-collection-review-refresh ()
  "Refresh the review, keeping the current item or its next surviving row."
  (interactive)
  (let* ((old-marker (get-text-property (line-beginning-position) 'org-marker))
         (old-index (save-excursion
                      (let ((end (line-beginning-position)) (index 0))
                        (goto-char (point-min))
                        (while (< (point) end)
                          (when (get-text-property (point) 'org-marker) (cl-incf index))
                          (forward-line 1))
                        index)))
         (entries (org-workflow-collection-inbox--pending
                   (org-workflow-collection-inbox--review-files) org-workflow-collection-review-all))
         (inhibit-read-only t) previous-date positions matching-position)
    (setq org-workflow-collection-review-count (length entries))
    (erase-buffer)
    (insert (propertize (format "未处理收集项 · %d\n" org-workflow-collection-review-count)
                        'face 'org-workflow-agenda-section))
    (insert (propertize
             (format "%s · a 归类菜单 · RET 原文 · r 移动 · g 刷新 · q 关闭\n\n"
                     (if org-workflow-collection-review-all "全部日期" "最近 7 天")) 'face 'shadow))
    (dolist (entry entries)
      (unless (equal previous-date (car entry))
        (setq previous-date (car entry))
        (insert (propertize (concat (if (string-empty-p previous-date) "未记录捕获日期" previous-date) "\n") 'face 'org-workflow-agenda-group)))
      (push (point) positions)
      (when (equal old-marker (nth 2 entry)) (setq matching-position (point)))
      (insert (propertize (concat "  " (cadr entry) "\n")
                          'org-marker (nth 2 entry) 'org-workflow-collection-review-title (cadr entry)
                          'mouse-face 'highlight)))
    (unless entries (insert "没有待处理的收集项。\n"))
    (goto-char (or matching-position
                   (when entries
                     (nth (min old-index (1- (length entries))) (nreverse positions)))
                   (point-min)))))

(defun org-workflow-collection-inbox-review (&optional _all)
  "Open the unified Sprint and locate its anytime Inbox."
  (interactive "P")
  (org-agenda nil "d")
  (goto-char (point-min))
  (when (search-forward "随时" nil t) (beginning-of-line)))

(defun org-workflow-install-inbox-capture-templates ()
  "Install the single capture menu for tasks, questions and thoughts."
  (require 'org-capture)
  ;; 去向在菜单中明确选择；不根据当前任务暗中转存。
  (dolist (template
           '(("t" "任务 → Inbox" entry (function org-workflow-collection-inbox-capture-target)
              "* TODO %?\n:PROPERTIES:\n:ID: %(org-id-new)\n:CAPTURED_ON: %<%Y-%m-%d %H:%M>\n:END:\n%i\n%a\n" :supertag t :empty-lines 1)
             ("q" "疑问")
             ("qc" "疑问 → 当前任务" entry (function org-workflow-target-capture-location)
              "* TODO %? :QA:\n:PROPERTIES:\n:ID: %(org-id-new)\n:CAPTURED_ON: %<%Y-%m-%d %H:%M>\n:END:\n%i\n%a\n" :supertag t :empty-lines 1)
             ("qi" "疑问 → Inbox" entry (function org-workflow-collection-inbox-capture-target)
              "* TODO %? :QA:\n:PROPERTIES:\n:ID: %(org-id-new)\n:CAPTURED_ON: %<%Y-%m-%d %H:%M>\n:END:\n%i\n%a\n" :supertag t :empty-lines 1)
             ("n" "想法")
             ("nc" "想法 → 当前任务" entry (function org-workflow-target-capture-location)
              "* %?\n:PROPERTIES:\n:ID: %(org-id-new)\n:CAPTURED_ON: %<%Y-%m-%d %H:%M>\n:END:\n%i\n%a\n" :supertag t :empty-lines 1)
             ("ni" "想法 → Inbox" entry (function org-workflow-collection-inbox-capture-target)
              "* %?\n:PROPERTIES:\n:ID: %(org-id-new)\n:CAPTURED_ON: %<%Y-%m-%d %H:%M>\n:END:\n%i\n%a\n" :supertag t :empty-lines 1)
             ("p" "网页摘录 → Inbox" entry (function org-workflow-collection-inbox-capture-target)
              "* TODO %:annotation\n:PROPERTIES:\n:ID: %(org-id-new)\n:CAPTURED_ON: %<%Y-%m-%d %H:%M>\n:END:\n%i\n%?" :supertag t :empty-lines 1)
             ("L" "网页链接 → Inbox" entry (function org-workflow-collection-inbox-capture-target)
              "* TODO %:annotation\n:PROPERTIES:\n:ID: %(org-id-new)\n:CAPTURED_ON: %<%Y-%m-%d %H:%M>\n:END:\n" :supertag t :immediate-finish t :empty-lines 1)))
    (if-let* ((existing (assoc (car template) org-capture-templates)))
        (setcdr existing (copy-tree (cdr template)))
      (setq org-capture-templates (append org-capture-templates (list template)))))
  ;; 旧 c 键继续可用，但模板内容只由 qc 决定。
  (let ((alias (cons "c" (copy-tree (cdr (assoc "qc" org-capture-templates))))))
    (setf (alist-get "c" org-capture-templates nil nil #'equal) (cdr alias))))

;; vulpea 笔记库中“可通过 `vulpea-find' 找到”的笔记文件。
;; vulpea-find 默认只展示有显式标题的笔记（`vulpea-note-titled-p'），
;; 这里用同一过滤条件查询数据库并取文件路径、去重后返回。
(defun org-workflow-vulpea-note-files ()
  "Return the Org files holding notes findable via `vulpea-find'."
  (require 'vulpea)
  (delete-dups
   (delq nil (mapcar #'vulpea-note-path
                     (vulpea-db-query #'vulpea-note-titled-p)))))

;; org-refile 用 `org-paste-subtree' 把子树原样粘贴到目标位置，前面不补空行，
;; 导致 refile 进来的标题紧贴在前一个标题/文件标题下一行（“叠在一起”）。
;; 这里在 org-refile 进行中时，给粘贴位置补一个空行。
(defvar org-workflow-refile-in-progress nil
  "Non-nil while `org-refile' is inserting its tree.")

(defun org-workflow-paste-subtree-ensure-blank-before (&rest _)
  "Insert a blank line before a subtree pasted by `org-refile'."
  (when (and org-workflow-refile-in-progress
             (bolp)
             (not (bobp)))
    (unless (save-excursion
              (forward-line -1)
              (beginning-of-line)
              (looking-at "[ \t]*$"))
      (insert "\n"))))

(defun org-workflow-refile--with-flag (orig-fn &rest args)
  "Call ORIG-FN with ARGS while `org-workflow-refile-in-progress' is bound."
  (let ((org-workflow-refile-in-progress t))
    (apply orig-fn args)))

(defun org-workflow-agenda-inbox--enable ()
  "Install this component while Workflow is being enabled."
  (org-workflow--with-after-load 'org
  (org-workflow--keymap-set org-mode-map "C-c o i" #'org-workflow-inbox-classify))
  (org-workflow--advice-add 'org-refile :around #'org-workflow-refile--save-participants)
  (org-workflow--with-after-load 'evil
  (evil-define-key* 'normal org-workflow-collection-review-mode-map
    (kbd "RET") #'org-workflow-collection-review-visit
    (kbd "r") #'org-workflow-collection-review-refile
    (kbd "a") #'org-workflow-inbox-classify
    (kbd "C-c o i") #'org-workflow-inbox-classify
    (kbd "g") #'org-workflow-collection-review-refresh
    (kbd "q") #'quit-window))
  (org-workflow--keymap-set org-mode-map "C-c o U" #'org-workflow-collection-inbox-review)
  (org-workflow-install-inbox-capture-templates)
  (org-workflow--keymap-set org-mode-map "C-c o I" #'org-workflow-collection-inbox-visit)
  ;; capture 时自动进入 evil insert 模式
(org-workflow--add-hook 'org-capture-mode-hook #'org-workflow--evil-insert)
  ;; agenda 设置
(setq org-agenda-hide-tags-regexp "inbox")
  (setq org-refile-targets
      '(;; ("projects.org" :regexp . "\\(?:\\(?:Note\\|Task\\)s\\)")
	("projects.org" :level . 1)
	(nil . t)                                    ; 当前 buffer：所有标题
	;; 只把 vulpea 笔记文件本身作为 refile 目标（refile 到文件末尾），
	;; 不匹配笔记内部任何标题。`\`\&' 意为“仅当文件以 & 开头才匹配”，
	;; 实际上永远匹配不到标题行；而 org-refile 对每个文件总是额外提供
	;; 一个“文件”级目标，因此笔记文件仍会出现在候选里。
	;; 注意：这里必须写裸符号 org-workflow-vulpea-note-files，不能写 #'org-workflow-vulpea-note-files ——
	;; 在 quoted 列表里 #' 会展开成 (function ...) 列表，导致 org-refile 报错。
	(org-workflow-vulpea-note-files :regexp . "\\`\\&")))
  ; vulpea 笔记：仅文件目标
;; (setq org-refile-targets
;;       '((org-agenda-files . (:maxlevel . 2))))
(setq org-refile-use-outline-path 'file)
  (setq org-outline-path-complete-in-steps nil)
  (org-workflow--advice-add 'org-paste-subtree :before #'org-workflow-paste-subtree-ensure-blank-before)
  (org-workflow--advice-add 'org-refile :around #'org-workflow-refile--with-flag))

(provide 'org-workflow-agenda-inbox)
;;; org-workflow-agenda-inbox.el ends here
