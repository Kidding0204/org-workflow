;;; org-workflow-agenda-projects.el --- Projects within the daily Agenda -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Jinwang Dong
;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Commentary:
;; Read-only project summaries and task previews.  Native source markers keep
;; ordinary Agenda editing available for projects, stages and next steps.
;;; Code:
(declare-function org-workflow-collection-inbox--pending "org-workflow-agenda-inbox" (files &optional all unscheduled))
(declare-function org-workflow-collection-inbox--review-files "org-workflow-agenda-inbox" ())
(declare-function org-workflow-agenda-note-toggle "org-workflow-agenda-notes" ())

(require 'org-workflow-projects)
(require 'org-workflow-history)
(declare-function org-workflow-agenda--select-candidate-project "org-workflow-agenda-view" (id))
(declare-function org-workflow-agenda--stack-line "org-workflow-agenda-view" (entry index))
(declare-function org-workflow-agenda--section-header "org-workflow-agenda-view" (title))
(declare-function org-workflow-agenda-target-date "org-workflow-agenda-layout" ())

(declare-function org-workflow-evening--day-icon "org-workflow-evening" (state face))

(defface org-workflow-agenda-fold-button
  '((t :inherit default :underline nil))
  "Fold arrows are controls, not underlined links." :group 'org-workflow)

(defface org-workflow-agenda-project-title
  '((t :inherit default))
  "Project heading, shared by every state." :group 'org-workflow)
(defface org-workflow-agenda-project-goal
  '((t :inherit default :weight semi-bold))
  "Long-term goal heading." :group 'org-workflow)
(defface org-workflow-agenda-project-stage
  '((t :inherit default))
  "Project stage heading." :group 'org-workflow)

(defun org-workflow-agenda--completed-arranged (date)
  "Read leaves completed on DATE that belonged to its arranged queue."
  (let (entries)
    (dolist (file (delete-dups (append (org-agenda-files t)
                                     (org-workflow-collection-inbox--review-files))))
      (with-current-buffer (find-file-noselect file)
        (org-with-wide-buffer
         (org-map-entries
          (lambda ()
            (when (and (equal (org-get-todo-state) "DONE")
                       (org-workflow-target--task-leaf-p)
                       (not (org-workflow-projects-kind))
                       (not (org-workflow-projects-stage-p))
                       (equal date (org-workflow-target--timestamp-date (org-entry-get nil "CLOSED")))
                       (org-workflow--scheduled-on-or-before-p date))
              (push (org-workflow-item-at-marker (point-marker) date) entries))) nil 'file))))
    (org-workflow-target--order-entries entries)))

(defun org-workflow-projects-progress (project)
  "Read PROJECT and stage leaf counts without counting QA or habits."
  (let ((done 0) (total 0) stages stage)
    (org-workflow-source-read
     (plist-get project :file)
     (lambda ()
       (goto-char (plist-get project :pos))
       (let ((level (org-outline-level)))
         (org-map-entries
          (lambda ()
            (let ((depth (org-outline-level)))
              (cond
               ((or (org-workflow-qa-p) (equal (org-entry-get nil "STYLE") "habit"))
                (when (= depth (1+ level)) (setq stage nil))
                (when (and stage (> depth (1+ level)) (org-workflow-qa-p) (org-get-todo-state))
                  (push (append (org-workflow-projects--location)
                                (list :state (org-get-todo-state) :depth (- depth level) :qa t))
                        (plist-get stage :children)))
                (setq org-map-continue-from (save-excursion (org-end-of-subtree t t))))
               (t
                (when (= depth (1+ level))
                  (setq stage nil)
                  (when (org-workflow-projects-stage-p)
                    (setq stage (append (org-workflow-projects--location)
                                        (list :state (org-get-todo-state) :children nil :done 0 :total 0)))
                    (push stage stages)))
                (when (and stage (> depth (1+ level)) (org-get-todo-state))
                  (push (append (org-workflow-projects--location)
                                (list :state (org-get-todo-state) :depth (- depth level)))
                        (plist-get stage :children)))
                (when (and (> depth (1+ level)) (org-workflow-target--task-leaf-p))
                  (cl-incf total)
                  (when stage (cl-incf (plist-get stage :total)))
                  ;; HOLD is an Org done keyword in the default sequence,
                  ;; but represents paused work, not Workflow completion.
                  (when (equal (org-get-todo-state) "DONE")
                    (cl-incf done)
                    (when stage (cl-incf (plist-get stage :done))))))))) nil 'tree))))
    (dolist (item stages)
      (setf (plist-get item :children) (nreverse (plist-get item :children))))
    (list :done done :total total :stages (nreverse stages))))

(defun org-workflow-projects-tracking (project date)
  "Read PROJECT's dated commitment outcomes through DATE, without writes."
  (when (and org-workflow-store-enabled (plist-get project :id))
    (let (days)
      (dolist (record (sqlite-select (org-workflow-store--db)
                                    "SELECT key,value FROM meta WHERE key LIKE 'project-day:%' ORDER BY key DESC"))
        (let* ((key (car record))
               (day (substring key 12 22)))
          (when (and (equal (substring key 23) (plist-get project :id))
                     (not (string< date day)))
            (when-let* ((row (org-workflow-store-commitment (cadr record))))
              (push (cons day (org-workflow-history--row-state row day)) days)))))
      (nreverse days))))

(defun org-workflow-projects-streak (days date)
  "Count completed obligation DAYS backwards from DATE.
Today's pending duty is allowed; recorded withdrawals are rest days.  Unknown
calendar gaps never count as verified continuity."
  (let ((count 0)
        (expected (if (assoc date days) date (org-workflow-history-add-days date -1))))
    (catch 'stop
      (dolist (day days)
        (unless (equal (car day) expected) (throw 'stop nil))
        (cond ((member (cdr day) '("done" "adjusted-done")) (cl-incf count))
              ((member (cdr day) '("withdrawn" "cancelled")) nil)
              ((equal (car day) date) nil)
              (t (throw 'stop nil)))
        (setq expected (org-workflow-history-add-days (car day) -1))))
    count))

(defun org-workflow-agenda-projects--week (days date)
  "Render project DAYS in the same visual form as habit tracking."
  (let* ((time (org-time-string-to-time (concat date " 12:00")))
         (start (org-workflow-history-add-days date (- (nth 6 (decode-time time))))))
    (concat
     (mapconcat
      (lambda (offset)
        (let* ((day (org-workflow-history-add-days start offset))
               (state (cdr (assoc day days)))
               (done (member state '("done" "adjusted-done")))
               (glyph (cond (done 'done)
                            ((or (null state) (member state '("withdrawn" "cancelled"))) 'future)
                            ((string< day date) 'missed) (t 'today)))
               (face (cond (done 'success) ((equal day date) 'default) (t 'shadow))))
          (propertize
           (concat (propertize (concat (nth offset '("日" "一" "二" "三" "四" "五" "六")) " ") 'face face)
                   (org-workflow-evening--day-icon glyph face))
           'help-echo (concat day " " (or state "无承诺")))))
      (number-sequence 0 6) "  ")
     (propertize (format "  %d" (org-workflow-projects-streak days date)) 'face 'shadow))))

(defvar org-modern-progress)
(declare-function org-modern--progress "ext:org-modern" ())

(defun org-workflow-agenda-projects--cookies (start end)
  "Render cookies between START and END with the configured org-modern renderer."
  (when (and (fboundp 'org-modern--progress)
             (boundp 'org-modern-progress) (integerp org-modern-progress)
             (> org-modern-progress 0))
    (save-excursion
      (save-match-data
        (goto-char start)
        (while (re-search-forward
                " \\(\\[\\(?:\\([0-9]+\\)%\\|\\([0-9]+\\)/\\([0-9]+\\)\\)]\\)" end t)
          ;; Very large counters must still fit in org-modern's bar.
          (let ((org-modern-progress (max org-modern-progress
                                          (- (match-end 1) (match-beginning 1) 2))))
            (org-modern--progress)))))))

(defun org-workflow-agenda-projects--line (item indent &optional suffix role)
  "Insert source-backed ITEM at INDENT with optional SUFFIX and visual ROLE."
  (let* ((marker (org-workflow-projects-marker item))
         (state (plist-get item :state))
         (regexps (org-with-point-at marker
                    (list org-todo-regexp org-not-done-regexp)))
         (face (pcase role
                 ('project 'org-workflow-agenda-project-title)
                 ('stage 'org-workflow-agenda-project-stage)
                 (_ 'org-workflow-agenda-meta)))
         (title (replace-regexp-in-string
                 "[ \t]*\\[0/0\\]"
                 "" (plist-get item :title)))
         (start (point))
         (width (max 10 (- (window-body-width) indent (string-width (or suffix "")) 8))))
    (insert (propertize
             (concat (make-string indent ?\s) (if state (concat state " ") "")
                     (truncate-string-to-width title width nil nil "…")
                     suffix "\n")
             'org-marker marker 'org-hd-marker marker 'todo-state state 'type "todo" 'org-heading t 'org-agenda-type 'todo
             'org-todo-regexp (car regexps) 'org-not-done-regexp (cadr regexps)
             'org-workflow-agenda-project-row t 'org-workflow-agenda-project-role role
             'tags (org-with-point-at marker (org-get-tags)) 'workflow-project item
             'face face 'help-echo (plist-get item :title)))
    (org-workflow-agenda-projects--cookies start (point))))

(defun org-workflow-agenda-project-todo ()
  "Dispatch state editing by structural row, keeping ordinary Agenda TODO native."
  (interactive)
  (cond ((org-get-at-bol 'workflow-goal) (org-workflow-agenda-project-goal-toggle))
        ((org-get-at-bol 'org-workflow-agenda-project-role) (org-workflow-agenda-project-state))
        (t (org-workflow-agenda-ensure-writeable) (call-interactively #'org-agenda-todo))))

(defun org-workflow-agenda-project-state (&optional marker state)
  "Set project or Heading MARKER to STATE through the shared project API."
  (interactive)
  (org-workflow-agenda-ensure-writeable)
  (let* ((source (or marker (org-get-at-bol 'org-hd-marker) (user-error "请选择项目／分组")))
         (summary (when (org-get-at-bol 'org-workflow-agenda-project-summary) (copy-marker source)))
         (column (current-column)))
    (unwind-protect
        (progn
          (org-workflow-projects-set-state
           source (or state (completing-read "状态：" '("TODO" "DIVE" "HOLD" "DONE") nil t)))
          (org-workflow-agenda-invalidate-last-operation "最近操作为项目状态调整，请通过状态入口调整")
          (when (derived-mode-p 'org-agenda-mode)
            (org-agenda-redo)
            ;; Pausing removes earlier arranged/anytime rows. Keep the edited
            ;; summary's source identity rather than its former line number.
            (when summary
              (let ((position
                     (save-excursion
                       (goto-char (point-min))
                       (catch 'found
                         (while (< (point) (point-max))
                           (when (and (org-get-at-bol 'org-workflow-agenda-project-summary)
                                      (equal summary (org-get-at-bol 'org-hd-marker)))
                             (throw 'found (point)))
                           (forward-line 1))
                         nil))))
                (if position
                    (progn (goto-char position) (move-to-column column))
                  (goto-char (or (text-property-any (point-min) (point-max)
                                                    'org-workflow-agenda-project-summary-header t)
                                 (point-min))))))))
      (when summary (set-marker summary nil)))))

(defun org-workflow-agenda-project-start (&optional remove)
  "Set the source project's start date, or REMOVE it with a prefix."
  (interactive "P")
  (org-workflow-agenda-ensure-writeable)
  (unless (eq (org-get-at-bol 'org-workflow-agenda-project-role) 'project)
    (user-error "请选择一级项目行"))
  (org-workflow-projects-set-start
   (or (org-get-at-bol 'org-hd-marker) (user-error "请选择项目"))
   (unless remove (org-read-date)))
  (org-workflow-agenda-invalidate-last-operation "最近操作为项目开始日期调整")
  (org-agenda-redo))

(defun org-workflow-agenda-project-goal-toggle ()
  "Pause or resume the file goal at point, then refresh the Agenda."
  (interactive)
  (org-workflow-agenda-ensure-writeable)
  (let ((goal (get-text-property (line-beginning-position) 'workflow-goal)))
    (unless goal (user-error "请选择长期目标行"))
    (org-workflow-projects-goal-state (org-workflow-projects-marker goal)
                                     (not (plist-get goal :paused)))
    (org-workflow-agenda-invalidate-last-operation "最近操作为 Area 暂停／恢复")
    (org-agenda-redo)))

(defvar org-workflow-agenda-project-goal-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "t") #'org-workflow-agenda-project-goal-toggle)
    map)
  "Goal-row pause action; project/stage rows use native Agenda TODO commands.")

(defun org-workflow-agenda-projects (_match)
  "Render the shared tree for Inbox classification and daily task arranging."
  (let ((start (point)))
    (insert (org-workflow-agenda--section-header "项目"))
    (org-workflow-agenda-projects-render)
    (add-text-properties start (point) '(org-agenda-type todo))))

(defun org-workflow-agenda-project-summary-show ()
  "Show this project or stage subtree using Org's other-window navigation."
  (interactive)
  (org-agenda-show-1 3))

(defun org-workflow-agenda-project-summary-expanded-p (project)
  "Read PROJECT's summary-only fold choice, defaulting to collapsed."
  (cdr (assoc (cons 'summary (org-workflow-agenda-project-key project))
              (org-workflow-agenda--setting 'org-workflow-agenda-project-folds))))

(defun org-workflow-agenda-project-summary-toggle ()
  "Show or hide eligible stages under this summary project."
  (interactive)
  (unless (and (org-get-at-bol 'org-workflow-agenda-project-summary)
               (eq (org-get-at-bol 'org-workflow-agenda-project-role) 'project))
    (user-error "请选择项目摘要行"))
  (let* ((project (org-get-at-bol 'workflow-project))
         ;; Namespace the choice so the daily planning tree remains independent.
         (key (cons 'summary (org-workflow-agenda-project-key project)))
         (folds (org-workflow-agenda--setting 'org-workflow-agenda-project-folds)))
    (setf (alist-get key folds nil nil #'equal)
          (not (org-workflow-agenda-project-summary-expanded-p project)))
    (org-workflow-agenda--set-setting 'org-workflow-agenda-project-folds folds)
    (org-agenda-redo)))

(defvar org-workflow-agenda-project-summary-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "t") #'org-workflow-agenda-project-state)
    (define-key map (kbd "<backtab>") #'org-workflow-agenda-project-summary-toggle)
    (define-key map (kbd "TAB") #'org-workflow-agenda-project-summary-show)
    (define-key map (kbd "RET") #'org-agenda-switch-to)
    map)
  "Summary rows edit state or visit Org, rather than folding the task tree.")

(defun org-workflow-agenda-project-summary--line (item role progress)
  "Insert ITEM's state, name and PROGRESS as a source-backed summary ROLE."
  (let* ((marker (org-workflow-projects-marker item))
         (state (plist-get item :state))
         (title (string-trim (replace-regexp-in-string
                             "\\[[0-9]*\\(?:/[0-9]*\\|%\\)\\]" "" (plist-get item :title))))
         (expanded (and (eq role 'project) (org-workflow-agenda-project-summary-expanded-p item)))
         (name (concat (if (eq role 'stage) "  " (if expanded "▾ " "▸ ")) title))
         (total (plist-get progress :total))
         (cookie (if (zerop total) "—" (format "[%d/%d]" (plist-get progress :done) total)))
         (width (max 10 (- (window-body-width) 10
                           (max (string-width cookie)
                                (if (and (boundp 'org-modern-progress) (integerp org-modern-progress))
                                    org-modern-progress 0)))))
         (regexps (org-with-point-at marker (list org-todo-regexp org-not-done-regexp)))
         (start (point)))
    (insert (format (concat "  %-4s %-" (number-to-string width) "s %s\n") (or state "")
                    (truncate-string-to-width name width nil nil "…") cookie))
    (add-text-properties
     start (point)
     (list 'org-marker marker 'org-hd-marker marker 'org-heading t 'todo-state state
           'type "todo" 'org-agenda-type 'todo
           'org-todo-regexp (car regexps) 'org-not-done-regexp (cadr regexps)
           'org-workflow-agenda-project-summary t 'org-workflow-agenda-project-row t
           'org-workflow-agenda-project-role role
           'workflow-project item 'keymap org-workflow-agenda-project-summary-map
           'help-echo (plist-get item :title)
           'face (if (eq role 'project) 'org-workflow-agenda-project-goal 'org-workflow-agenda-project-stage)))
    (when state
      (make-text-button (+ start 2) (+ start 2 (length state))
                        'keymap org-workflow-agenda-project-summary-map
                        'face 'default 'mouse-face 'highlight 'follow-link t
                        'action (lambda (_) (org-workflow-agenda-project-state))))
    (when (eq role 'project)
      (make-text-button (+ start 7) (+ start 7 (length (truncate-string-to-width name width nil nil "…")))
                        'keymap org-workflow-agenda-project-summary-map
                        'face '(:inherit org-workflow-agenda-project-goal :underline nil)
                        'mouse-face 'highlight 'follow-link t
                        'action (lambda (_) (org-workflow-agenda-project-summary-toggle))))
    (org-workflow-agenda-projects--cookies start (point))))

(defun org-workflow-agenda-project-summary ()
  "Render TODO/DIVE projects and manually expanded eligible stages."
  (let* ((items (org-workflow-projects-collect))
         (projects (seq-filter (lambda (p) (and (equal (plist-get p :kind) "project")
                                                (member (plist-get p :state) '("DIVE" "TODO")))) items)))
    (when projects
      (insert "\n" (propertize (org-workflow-agenda--section-header "项目")
                               'org-workflow-agenda-project-summary-header t))
      (dolist (area (seq-filter (lambda (p) (equal (plist-get p :kind) "goal")) items))
        (let ((children (seq-filter (lambda (p) (equal (plist-get p :goal-id) (plist-get area :id))) projects)))
          (when children
            (insert (propertize (concat "  " (plist-get area :title) "\n")
                                'face 'org-workflow-agenda-meta 'org-agenda-structural-header t))
            (dolist (project children)
              (let ((progress (org-workflow-projects-progress project)))
                (org-workflow-agenda-project-summary--line project 'project progress)
                (when (org-workflow-agenda-project-summary-expanded-p project)
                  (dolist (stage (plist-get progress :stages))
                    (when (member (plist-get stage :state) '("DIVE" "TODO"))
                      (org-workflow-agenda-project-summary--line stage 'stage stage))))))))))))

(autoload 'org-workflow-project-classify "org-workflow-project-classify")
(autoload 'org-workflow-project-classify-save "org-workflow-project-classify")

(defun org-workflow-agenda-classify-markers ()
  "Return selected Inbox markers in visible order, independent of the active pane."
  (let* ((buffers (org-workflow-agenda--workbench-buffers))
         (selected (apply #'append (mapcar (lambda (b)
                                            (buffer-local-value 'org-agenda-bulk-marked-entries b)) buffers)))
         (fallback (org-get-at-bol 'org-hd-marker)) markers)
    (dolist (buffer buffers)
      (with-current-buffer buffer
        (save-excursion
          (goto-char (point-min))
          (while (< (point) (point-max))
            (when (org-get-at-bol 'org-workflow-agenda-inbox-row)
              (let ((marker (org-get-at-bol 'org-hd-marker)))
                (when (if selected (member marker selected) (equal marker fallback))
                  (push (copy-marker marker) markers))))
            (forward-line 1)))))
    (nreverse markers)))

(defun org-workflow-agenda-classify-entries (markers target)
  "Classify MARKERS into TARGET, keeping both Sprint panes coherent."
  (org-workflow-agenda-ensure-writeable)
  (unless markers (user-error "请先选择 Inbox 条目"))
  ;; Bulk marks are a stack, but a batch belongs in the source's visible order.
  (let* ((left (org-workflow-agenda-workbench-primary org-workflow-agenda--workbench))
         (order (with-current-buffer left
                  (let (rows) (save-excursion
                                (goto-char (point-min))
                                (while (< (point) (point-max))
                                  (when (org-get-at-bol 'org-workflow-agenda-inbox-row)
                                    (push (org-get-at-bol 'org-hd-marker) rows))
                                  (forward-line 1))) (nreverse rows))))
         (sorted (seq-filter (lambda (m) (member m markers)) order)))
    (unless (= (length markers) (length sorted)) (user-error "来源已不在本页 Inbox，请刷新"))
    (let ((record (org-workflow-project-classify (mapcar #'copy-marker sorted) target)))
      (org-workflow-agenda--clear-selection)
      (let ((folds (org-workflow-agenda--setting 'org-workflow-agenda-project-folds))
            (root (plist-get record :project)))
        (dolist (marker (list root (when-let* ((m (car (plist-get record :markers))))
                                       (org-with-point-at m (org-up-heading-safe) (point-marker)))))
          (when marker
            (let ((item (org-with-point-at marker (org-workflow-projects--location))))
              (setf (alist-get (org-workflow-agenda-project-key item) folds nil nil #'equal) t))))
        (org-workflow-agenda--set-setting 'org-workflow-agenda-project-folds folds))
      (org-agenda-redo)
      (when (eq (plist-get record :save-state) 'saved)
        (message "已归类 %d 项" (length markers)))
      record)))

(defun org-workflow-agenda-classify-selected ()
  "Move selected Inbox captures to this row, or choose a structural destination."
  (interactive)
  (let ((markers (org-workflow-agenda-classify-markers))
        (target (org-get-at-bol 'org-workflow-agenda-classify-target)))
    (unless target
      (let (choices)
        (dolist (buffer (org-workflow-agenda--workbench-buffers))
          (with-current-buffer buffer
            (save-excursion
              (goto-char (point-min))
              (while (< (point) (point-max))
                (when-let* ((item (org-get-at-bol 'org-workflow-agenda-classify-target)))
                  (let ((label (org-with-point-at (plist-get item :marker)
                                 (concat (file-name-base buffer-file-name) " / "
                                         (mapconcat #'identity (org-get-outline-path t) " / ")))))
                    (push (cons (format "%s  (%d)" label (marker-position (plist-get item :marker))) item) choices)))
                (forward-line 1)))))
        (setq target (cdr (assoc (completing-read "归类到：" (nreverse choices) nil t) choices)))))
    (org-workflow-agenda-classify-entries markers target)))

(defun org-workflow-agenda-project-tab ()
  "Visit summary sources, fold tree rows, or retain the QA source preview."
  (interactive)
  (cond ((org-get-at-bol 'org-workflow-agenda-project-summary)
         (org-workflow-agenda-project-summary-show))
        ((or (org-get-at-bol 'workflow-goal) (org-get-at-bol 'org-workflow-agenda-project-role))
         (org-workflow-agenda-project-toggle))
        (t (call-interactively #'org-workflow-agenda-note-toggle))))

(defun org-workflow-agenda-project-key (item)
  "Read ITEM's fold identity without creating an Org ID."
  (list (plist-get item :file) (or (plist-get item :id) (plist-get item :pos))))

(defun org-workflow-agenda-project-expanded-p (item default)
  "Read ITEM's explicit fold choice, falling back to DEFAULT."
  (let ((choice (assoc (org-workflow-agenda-project-key item)
                       (org-workflow-agenda--setting 'org-workflow-agenda-project-folds))))
    (if choice (cdr choice) default)))

(defun org-workflow-agenda-project-toggle ()
  "Toggle the source-backed project, Heading or Area at point."
  (interactive)
  (let* ((item (or (org-get-at-bol 'workflow-project) (org-get-at-bol 'workflow-goal)))
         (key (org-workflow-agenda-project-key item))
         (folds (org-workflow-agenda--setting 'org-workflow-agenda-project-folds)))
    (unless item (user-error "请选择项目、分组或 Area"))
    (setf (alist-get key folds nil nil #'equal)
          (not (org-get-at-bol 'org-workflow-agenda-expanded)))
    (org-workflow-agenda--set-setting 'org-workflow-agenda-project-folds folds)
    (org-agenda-redo)
    ;; Areas have no task marker. Restore their structural identity rather than
    ;; leaving point on the section title after their children disappear.
    (goto-char (point-min))
    (catch 'found
      (while (< (point) (point-max))
        (when-let* ((row (or (org-get-at-bol 'workflow-project)
                            (org-get-at-bol 'workflow-goal))))
          (when (equal key (org-workflow-agenda-project-key row)) (throw 'found t)))
        (forward-line 1)))))

(defvar org-workflow-agenda-project-row-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "t") #'org-workflow-agenda-project-state)
    (define-key map (kbd "TAB") #'org-workflow-agenda-project-toggle)
    map)
  "Structural row actions only; ordinary task keys remain native Agenda keys.")

(defun org-workflow-agenda-projects--tree-line (item indent role expanded)
  "Render ITEM once, with separate fold and classification destinations."
  (let ((start (point)))
    (org-workflow-agenda-projects--line item indent
                                      (when (plist-get item :qa) " :QA:") role)
    (add-text-properties
     start (point)
     (list 'keymap (when role org-workflow-agenda-project-row-map)
           'org-workflow-agenda-expanded expanded
           'mouse-face 'highlight
           'org-workflow-agenda-classify-target
           (when (memq role '(project stage))
             (list :kind (if (eq role 'project) 'project 'heading)
                   :marker (get-text-property start 'org-hd-marker)
                   :id (plist-get item :id) :title (plist-get item :title)))))
    (when (memq role '(project stage))
      (save-excursion
        (goto-char (+ start indent))
        (let ((inhibit-read-only t))
          (insert-text-button (if expanded "▾ " "▸ ")
                              'face 'org-workflow-agenda-fold-button
                              'follow-link t 'org-workflow-agenda-fold-button t
                              'action (lambda (_) (org-workflow-agenda-project-toggle))))))))

(defun org-workflow-agenda-projects-render ()
  "Render the shared tree for daily classification and arranging."
  (let ((start (point)))
    (let* ((items (org-workflow-projects-collect))
           (projects (seq-filter (lambda (p) (equal (plist-get p :kind) "project")) items))
           (goals (seq-filter (lambda (p) (equal (plist-get p :kind) "goal")) items))
           (selected (org-workflow-agenda--setting 'org-workflow-agenda-selected-group)))
      (when (and selected (not (seq-some (lambda (g) (equal selected (plist-get g :id))) goals)))
        (setq selected nil)
        (org-workflow-agenda--set-setting 'org-workflow-agenda-selected-group nil))
      (setq-local org-workflow-agenda--candidate-tab-data
                  (mapcar (lambda (goal)
                            (let ((id (plist-get goal :id)))
                              `((name . ,(or (plist-get goal :title) "全部"))
                                (org-workflow-agenda-group-id . ,id)
                                (select . ,(lambda () (org-workflow-agenda--select-candidate-project id))))))
                          (cons nil goals)))
      (dolist (goal (if selected (seq-filter (lambda (g) (equal selected (plist-get g :id))) goals) goals))
        (let* ((children (seq-filter (lambda (p) (equal (plist-get p :goal-id) (plist-get goal :id))) projects))
               (expanded (org-workflow-agenda-project-expanded-p goal t))
               (beg (point)))
          (insert (propertize (concat (if expanded "▾ " "▸ ") (plist-get goal :title)
                                      (when (plist-get goal :paused) "  HOLD") "\n")
                              'face 'org-workflow-agenda-project-goal 'workflow-goal goal
                              'org-workflow-agenda-expanded expanded 'org-agenda-structural-header t
                              'keymap org-workflow-agenda-project-goal-map 'mouse-face 'highlight))
          (put-text-property beg (+ beg 2) 'org-workflow-agenda-area-fold t)
          (when expanded
            (dolist (project children)
              (let ((open (org-workflow-agenda-project-expanded-p
                           project (equal (plist-get project :state) "DIVE"))))
                (org-workflow-agenda-projects--tree-line project 2 'project open)
                (when open
                  (insert "      " (org-workflow-agenda-projects--week
                                    (org-workflow-projects-tracking project (org-workflow-agenda-target-date))
                                    (org-workflow-agenda-target-date)) "\n")
                  (let ((stages (plist-get (org-workflow-projects-progress project) :stages)))
                    (dolist (stage stages)
                      (let ((show (org-workflow-agenda-project-expanded-p
                                   stage (equal (plist-get stage :state) "DIVE"))))
                        (org-workflow-agenda-projects--tree-line stage 4 'stage show)
                        (when show
                          (dolist (task (plist-get stage :children))
                            (org-workflow-agenda-projects--tree-line
                             task (+ 4 (* 2 (or (plist-get task :depth) 2))) nil nil))))))))))
          (insert "\n"))))
    (add-text-properties start (point) '(org-agenda-type todo))))

(provide 'org-workflow-agenda-projects)
;;; org-workflow-agenda-projects.el ends here
