;;; org-workflow-project-classify.el --- Inbox subtree classification -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Jinwang Dong
;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Commentary:
;; Native refile owns subtree level adjustment. Workflow owns the batch,
;; durable recovery and the one-step record; rendering never writes identities.
;;; Code:
(require 'org-workflow-projects)
(require 'org-workflow-agenda-inbox)
(require 'org-workflow-agenda-layout)
(require 'org-id)

(defun org-workflow-project-classify--buffer (file)
  "Use FILE's live text without an implicit revert or an external-change prompt."
  (or (get-file-buffer file) (find-file-noselect file)))

(defun org-workflow-project-classify--snapshot (files)
  "Read live source images for FILES, preserving restrictions and point."
  (mapcar (lambda (file)
            (with-current-buffer (org-workflow-project-classify--buffer file)
              (org-with-wide-buffer (list file (buffer-substring-no-properties (point-min) (point-max)))))) files))

(defun org-workflow-project-classify--files (markers)
  "Return canonical file names for live MARKERS, rejecting foreign data."
  (delete-dups
   (mapcar (lambda (marker)
             (unless (and (markerp marker) (marker-buffer marker)
                          (buffer-file-name (marker-buffer marker)))
               (user-error "条目来源已失效，请刷新"))
             (file-truename (buffer-file-name (marker-buffer marker)))) markers)))

(defun org-workflow-project-classify--clean (files &optional allow-modified)
  "Check FILES before changing their source, optionally ALLOW-MODIFIED."
  (dolist (file files)
    (with-current-buffer (org-workflow-project-classify--buffer file)
      (when (or buffer-read-only (not (file-writable-p file)))
        (user-error "归类文件只读：%s" file))
      (unless (verify-visited-file-modtime (current-buffer))
        (user-error "文件在外部发生变化，请先重新读取：%s" file))
      (when (and (not allow-modified) (buffer-modified-p))
        (user-error "请先保存已有编辑：%s" file)))))

(defun org-workflow-project-classify--target (target)
  "Validate TARGET and return its structural project marker."
  (let ((marker (plist-get target :marker)) (kind (plist-get target :kind)))
    (org-workflow-project-classify--files (list marker))
    (unless (memq kind '(project heading)) (user-error "请选择项目或二级分组"))
    (org-with-point-at marker
      (when (and (plist-get target :title)
                 (not (and (equal (plist-get target :title) (org-get-heading t t t t))
                           (or (not (plist-get target :id))
                               (equal (plist-get target :id) (org-entry-get nil "ID"))))))
        (user-error "目标身份已变化，请刷新"))
      (unless (and (org-at-heading-p)
                   (if (eq kind 'project) (equal (org-workflow-projects-kind) "project")
                     (org-workflow-projects-stage-p)))
        (user-error "归类目标已变化，请刷新"))
      (let ((root (org-workflow-projects-root)))
        (when (or (equal (org-get-todo-state) "DONE")
                  (org-with-point-at root (equal (org-get-todo-state) "DONE")))
          (user-error "请先恢复已完成的项目／分组"))
        root))))

(defun org-workflow-project-classify--ungrouped (project &optional create)
  "Locate PROJECT's unique direct 未分组 Heading; CREATE only in a transaction."
  (org-with-point-at project
    (org-with-wide-buffer
     (let (found)
       (org-map-entries (lambda ()
                          (when (and (= (org-outline-level) 2)
                                     (equal (org-get-heading t t t t) "未分组"))
                            (push (point-marker) found))) nil 'tree)
       (when (> (length found) 1) (user-error "项目中有多个直属“未分组”，请先合并"))
       (or (car found)
           (when create
             (goto-char project) (org-end-of-subtree t t)
             (unless (bolp) (insert "\n"))
             (let ((marker (point-marker))) (insert "** 未分组\n") marker)))))))

(defun org-workflow-project-classify--source-p (marker)
  "Validate a direct Inbox capture subtree and exclude a running clock."
  (org-with-point-at marker
    (unless (and (org-at-heading-p) (org-get-todo-state)
                 (not (org-entry-is-done-p))
                 (save-excursion (and (org-up-heading-safe) (org-workflow-collection-inbox--heading-p))))
      (user-error "归类来源已离开 Inbox 或已完成，请刷新"))
    (when (and (bound-and-true-p org-clock-marker) (marker-buffer org-clock-marker)
               (eq (marker-buffer marker) (marker-buffer org-clock-marker))
               (<= (point) (marker-position org-clock-marker))
               (< (marker-position org-clock-marker) (save-excursion (org-end-of-subtree t t))))
      (user-error "请先停止此条目中的计时，再归类"))))

(defun org-workflow-project-classify--identities (files)
  "Read ID/file pairs from live FILES, never creating IDs."
  (let (ids)
    (dolist (file files)
      (with-current-buffer (org-workflow-project-classify--buffer file)
        (org-with-wide-buffer
         (org-map-entries (lambda () (when-let* ((id (org-entry-get nil "ID")))
                                      (push (cons id file) ids))) nil 'file))))
    ids))

(defun org-workflow-project-classify--index (files previous)
  "Refresh ID locations in FILES and retire identities missing from PREVIOUS."
  (let ((current (org-workflow-project-classify--identities files)))
    (dolist (pair previous)
      (unless (assoc (car pair) current)
        (when (hash-table-p org-id-locations) (remhash (car pair) org-id-locations))))
    (dolist (pair current) (org-id-add-location (car pair) (cdr pair)))))

(defun org-workflow-project-classify--restore (images)
  "Restore source IMAGES inside the caller's operation."
  (dolist (image images)
    (with-current-buffer (org-workflow-project-classify--buffer (car image))
      (org-with-wide-buffer
       (unless (equal (buffer-substring-no-properties (point-min) (point-max)) (cadr image))
         (replace-region-contents (point-min) (point-max) (lambda () (cadr image))))))))

(defun org-workflow-project-classify--register (record)
  "Remember an applied RECORD before any fallible post-commit action."
  (org-workflow-agenda--set-setting 'org-workflow-agenda-last-operation record))

(defun org-workflow-project-classify-save (record)
  "Persist applied RECORD without replaying moves; keep failures recoverable."
  (interactive (list (org-workflow-agenda--setting 'org-workflow-agenda-last-operation)))
  (unless (and record (eq (plist-get record :save-state) 'pending))
    (user-error "没有待保存的归类"))
  (condition-case err
      (progn
        (org-workflow-project-classify--clean (plist-get record :files) t)
        (unless (equal (plist-get record :after)
                       (org-workflow-project-classify--snapshot (plist-get record :files)))
          (user-error "参与文件有后续编辑，请先处理恢复记录"))
        (dolist (file (plist-get record :save-order))
          (with-current-buffer (org-workflow-project-classify--buffer file) (when (buffer-modified-p) (save-buffer))))
        (setf (plist-get record :save-state) 'saved
              (plist-get record :error) nil)
        (message "归类已保存"))
    (error (setf (plist-get record :error) (error-message-string err))
           (message "归类已应用，保存未完成：%s；可重试保存或 U 撤销" (error-message-string err))))
  record)

(defun org-workflow-project-classify (markers target)
  "Move Inbox MARKERS into structural TARGET as one recoverable batch."
  (unless org-workflow-store-enabled (user-error "请先启用 Org Workflow 存储"))
  (when (eq (plist-get (org-workflow-agenda--setting 'org-workflow-agenda-last-operation) :save-state) 'pending)
    (user-error "请先保存或撤销上次已应用的归类"))
  (unless (and markers (= (length markers) (length (delete-dups (copy-sequence markers)))))
    (user-error "请选择不重复的 Inbox 条目"))
  (let* ((project (org-workflow-project-classify--target target))
         (destination (plist-get target :marker))
         (files (org-workflow-project-classify--files (append markers (list destination))))
         (sources (org-workflow-project-classify--files markers))
         (destination-file (car (org-workflow-project-classify--files (list destination))))
         (before (org-workflow-project-classify--snapshot files))
         (identities (org-workflow-project-classify--identities files))
         (undo-lists (mapcar (lambda (f) (with-current-buffer (org-workflow-project-classify--buffer f)
                                         (cons f buffer-undo-list))) files))
         (owner (current-buffer))
         (selected-id (when (and (markerp org-workflow-target-selected-marker)
                                 (marker-buffer org-workflow-target-selected-marker))
                        (org-with-point-at org-workflow-target-selected-marker (org-entry-get nil "ID"))))
         inserted record applied)
    (org-workflow-project-classify--clean files)
    (mapc #'org-workflow-project-classify--source-p markers)
    ;; Detect an ambiguous/default closed Heading before changing any source.
    (when (eq (plist-get target :kind) 'project)
      (when-let* ((group (org-workflow-project-classify--ungrouped project)))
        (org-workflow-project-classify--target (list :kind 'heading :marker group))))
    (let ((org-workflow-store--extra-source-files files)
          (org-workflow-refile-defer-save t)
          (org-workflow-store--after-commit-function
           (lambda ()
             (setq applied t
                   record (list :kind 'classify :date (org-workflow-target--today-string)
                                :database org-workflow-store-file :files files :before before
                                :after (org-workflow-project-classify--snapshot files)
                                :identities identities :markers inserted :project project
                                :save-order (delete-dups (cons destination-file sources))
                                :save-state 'pending :error nil))
             (with-current-buffer owner (org-workflow-project-classify--register record)))))
      (condition-case err
          (org-workflow-store--operation
           (lambda ()
             (let* ((group (if (eq (plist-get target :kind) 'heading) destination
                             (org-workflow-project-classify--ungrouped project t)))
                    (org-refile-keep nil) (org-refile-use-cache nil)
                    (org-log-refile nil)
                    (org-after-refile-insert-hook
                     (cons (lambda () (push (point-marker) inserted)) org-after-refile-insert-hook)))
               (dolist (marker markers)
                 (org-with-point-at marker
                   (org-id-get-create)
                   (org-refile nil nil
                               (org-with-point-at group
                                 (list (org-get-heading t t t t) buffer-file-name nil (point))))))
               (setq inserted (nreverse inserted))
               (org-workflow-project-classify--index files identities)
               (when selected-id
                 (when-let* ((new (seq-find (lambda (m) (org-with-point-at m
                                                       (equal selected-id (org-entry-get nil "ID")))) inserted)))
                   (setq org-workflow-target-selected-marker (copy-marker new)))))))
        (error
         (if applied
             (setf (plist-get record :error) (error-message-string err))
           (org-workflow-project-classify--restore before)
           (dolist (row undo-lists)
             (with-current-buffer (org-workflow-project-classify--buffer (car row))
               (setq buffer-undo-list (cdr row)) (set-buffer-modified-p nil)))
           (org-workflow-project-classify--index files identities)
           (signal (car err) (cdr err))))))
    (if (plist-get record :error)
        (message "归类已应用，保存未完成：%s" (plist-get record :error))
      (org-workflow-project-classify-save record))
    record))

(defun org-workflow-project-classify-undo (record)
  "Reverse applied RECORD only while every participating source still matches."
  (unless (and org-workflow-store-enabled
               (equal org-workflow-store-file (plist-get record :database))
               (equal (org-workflow-target--today-string) (plist-get record :date)))
    (user-error "日期或数据库已变化，不能撤销归类"))
  (org-workflow-project-classify--clean (plist-get record :files) t)
  (unless (equal (plist-get record :after)
                 (org-workflow-project-classify--snapshot (plist-get record :files)))
    (user-error "参与文件有后续编辑，未执行撤销；请用 refile 手动归回"))
  (if (plist-get record :undoing)
      (org-workflow-project-classify-save record)
    (let* ((files (plist-get record :files))
           (identities (org-workflow-project-classify--identities files))
           (order (plist-get record :save-order))
           (owner (current-buffer))
           (reverse (list :kind 'classify :undoing t :files files
                          :before (plist-get record :after) :after (plist-get record :before)
                          :date (plist-get record :date) :database (plist-get record :database)
                          :save-order (append (cdr order) (list (car order)))
                          :save-state 'pending :error nil))
           (org-workflow-store--extra-source-files files)
           (org-workflow-store--after-commit-function
            (lambda () (with-current-buffer owner (org-workflow-project-classify--register reverse))))
           committed)
      (condition-case err
          (org-workflow-store--operation
           (lambda ()
             (org-workflow-project-classify--restore (plist-get record :before))
             (org-workflow-project-classify--index files identities)))
        (error
         (if (eq (org-workflow-agenda--setting 'org-workflow-agenda-last-operation) reverse)
             (setf (plist-get reverse :error) (error-message-string err))
           (signal (car err) (cdr err)))))
      (setq committed (eq (org-workflow-agenda--setting 'org-workflow-agenda-last-operation) reverse))
      (when committed (org-workflow-project-classify-save reverse))
      (setq record reverse)))
  (when (eq (plist-get record :save-state) 'saved)
    (org-workflow-agenda--set-setting 'org-workflow-agenda-last-operation nil)
    (message "已撤销归类，原位置和内容已恢复"))
  record)

(provide 'org-workflow-project-classify)
;;; org-workflow-project-classify.el ends here
