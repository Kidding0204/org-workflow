;;; org-workflow-agenda-view.el --- note-gtd-agenda-view Workflow component -*- lexical-binding: t; -*-
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
(declare-function org-workflow-agenda-projects-render "org-workflow-agenda-projects" (&optional inbox-role))

(require 'org-workflow-lifecycle)

(declare-function org-workflow-agenda-completed "org-workflow-agenda-review" (_match))
(declare-function org-workflow-collection-inbox--pending "org-workflow-agenda-inbox" (files &optional all unscheduled))
(declare-function org-workflow-collection-inbox--review-files "org-workflow-agenda-inbox" ())
(autoload 'org-workflow-evening--habit-rows "org-workflow-evening")
(declare-function org-workflow-evening--insert-habits "org-workflow-evening" (rows period edge))
(defvar org-super-agenda-header-map)
(defvar org-workflow-agenda-header-button-map)
;;; org-workflow-agenda-view.el --- Sprint sections and display metadata -*- lexical-binding: t; -*-
;;; Commentary:
;; Internal implementation module loaded by org-workflow-agenda.
;;; Code:
(require 'cl-lib)

(require 'org-agenda)

(require 'button)

(require 'tab-line)
(require 'org-workflow-sources)
(autoload 'org-workflow-agenda-projects "org-workflow-agenda-projects")
(autoload 'org-workflow-agenda--completed-arranged "org-workflow-agenda-projects")

(defvar org-workflow-agenda-planning-all)

(defface org-workflow-agenda-section
  '((t (:inherit default :foreground "#193668" :height 1.15 :weight semibold)))
  "Compact face for the two top-level Sprint sections."
  :group 'org-agenda)

(defface org-workflow-agenda-group
  '((t (:inherit shadow :weight regular :height 0.95)))
  "Theme-aware face for category and parent group labels in Sprint."
  :group 'org-agenda)

(defface org-workflow-agenda-meta
  '((t (:inherit shadow :height 0.9)))
  "Quiet planning annotations." :group 'org-agenda)

(defface org-workflow-agenda-anytime-project
  '((t :inherit org-workflow-agenda-meta :slant italic))
  "Project category in the anytime section." :group 'org-workflow)

(defface org-workflow-agenda-ancestor
  '((t (:inherit shadow :height 0.95 :weight regular)))
  "Original quiet styling for ancestor breadcrumbs." :group 'org-agenda)

(defface org-workflow-agenda-commitment
  '((t (:inherit org-priority :height 1.0 :weight regular :slant normal
        :background unspecified :inverse-video nil :box nil)))
  "Readable commitment marker using the theme's priority foreground only."
  :group 'org-agenda)

(defface org-workflow-agenda-tag-promise '((t :inherit org-tag)) "Workflow semantic tag face." :group 'org-workflow)

(defface org-workflow-agenda-tag-tiny '((t :inherit org-tag)) "Workflow semantic tag face." :group 'org-workflow)

(defface org-workflow-agenda-tag-flow '((t :inherit org-tag)) "Workflow semantic tag face." :group 'org-workflow)

(defface org-workflow-agenda-tag-deep '((t :inherit org-tag)) "Workflow semantic tag face." :group 'org-workflow)

(defface org-workflow-agenda-morning
  '((t (:inherit default :height 1.05 :weight semibold)))
  "Morning planning band; colors are supplied by the active theme."
  :group 'org-agenda)

(defface org-workflow-agenda-afternoon
  '((t (:inherit default :height 1.05 :weight semibold)))
  "Afternoon planning band; colors are supplied by the active theme."
  :group 'org-agenda)

(defface org-workflow-agenda-evening
  '((t (:inherit default :height 1.05 :weight semibold)))
  "Evening planning band; colors are supplied by the active theme."
  :group 'org-agenda)

(defun org-workflow-agenda--period-header (priority &optional entries)
  "Return a compact time-of-day header for numeric PRIORITY and ENTRIES."
  (let* ((letter (org-workflow-agenda--priority-letter priority))
         (period (assq letter '((?A "上午" org-workflow-agenda-morning)
                                (?B "下午" org-workflow-agenda-afternoon)
                                (?C "晚上" org-workflow-agenda-evening)))))
    (concat "  "
            (propertize (format " %s " (or (cadr period)
                                           (format "Priority %c" (or letter ??))))
                        'face (or (caddr period) 'org-workflow-agenda-group)
                        'org-agenda-structural-header t)
            (when entries (org-workflow-agenda--period-load entries))
            "\n")))

(defun org-workflow-agenda--period-load (entries)
  "Summarize direct Effort estimates in ENTRIES without treating missing as zero."
  (let ((minutes 0) (unknown 0))
    (dolist (entry entries)
      (let ((estimate
             (org-with-point-at (org-workflow-target-entry-marker entry)
               (when-let* ((effort (org-entry-get nil org-effort-property)))
                 (condition-case nil (org-duration-to-minutes effort)
                   (error nil))))))
        (if (and (numberp estimate) (>= estimate 0))
            (cl-incf minutes estimate)
          (cl-incf unknown))))
    (if (< unknown (length entries))
        (propertize (concat " · 预计 " (org-duration-from-minutes minutes))
                    'face 'org-workflow-agenda-meta)
      "")))

(defvar org-workflow-agenda-sprint-view nil
  "Non-nil while constructing and finalizing the Sprint agenda.")

(defun org-workflow-agenda--section-header (title)
  "Return compact Sprint section header TITLE with a trailing newline."
  (concat (propertize title 'face 'org-workflow-agenda-section
                      'org-agenda-structural-header t)
          "\n"))

(defun org-workflow-agenda--breadcrumb-text (names width)
  "Fit the project and stage NAMES into WIDTH display columns."
  (let ((part (max 4 (/ (- width 3) 2))))
    (string-join
     (mapcar (lambda (name)
               (truncate-string-to-width name (if (cdr names) part width) nil nil "…"))
             names) " / ")))

(defun org-workflow-agenda--entry-group-title (entry)
  "Return bounded project and stage names, without a file/category prefix."
  (let ((width (max 12 (- (window-body-width) 8))))
    (org-with-point-at (org-workflow-target-entry-marker entry)
      (let ((names (seq-take (org-get-outline-path) 2)))
        (propertize (org-workflow-agenda--breadcrumb-text names width)
                    'face 'org-workflow-agenda-group
                    'help-echo (string-join names " / ")
                    'org-workflow-agenda-breadcrumb names
                    'org-workflow-agenda-group-header t)))))

(defun org-workflow-agenda--fit-breadcrumbs (&optional window)
  "Refit breadcrumb display to WINDOW without rebuilding task rows."
  (let ((width (max 12 (- (window-body-width window) 8)))
        (inhibit-read-only t))
    (save-excursion
      (goto-char (point-min))
      (while (< (point) (point-max))
        (when-let* ((start (text-property-not-all (line-beginning-position)
                                                (line-end-position)
                                                'org-workflow-agenda-breadcrumb nil))
                    (names (get-text-property start 'org-workflow-agenda-breadcrumb)))
          (put-text-property start (line-end-position) 'display
                             (org-workflow-agenda--breadcrumb-text names width)))
        (forward-line 1)))))

(defun org-workflow-agenda--priority-letter (priority)
  "Return the Org priority letter represented by numeric PRIORITY."
  (cl-loop for letter from org-priority-highest to org-priority-lowest
           when (= priority (org-get-priority (format "[#%c]" letter)))
           return letter))

(defun org-workflow-agenda--stack-line (entry _index)
  "Return an unnumbered native Agenda line for ENTRY."
  (let ((marker (org-workflow-target-entry-marker entry))
        (date (org-workflow-agenda-target-date)))
    (org-with-point-at marker
      (org-back-to-heading t)
      (let* ((agenda-marker (org-agenda-new-marker (point)))
             (priority (org-workflow-target-entry-priority entry))
             (title (substring-no-properties (org-workflow-target-entry-title entry)))
             (commitment-mark (if (org-workflow--promise-p)
                                  (concat (propertize
                                           (if (or (and (equal (org-get-todo-state) "DONE")
                                                        (equal date (org-workflow-target--timestamp-date
                                                                     (org-entry-get nil "CLOSED")))))
                                               "◆" "◇")
                                           'face 'org-workflow-agenda-commitment) " ")
                                "  "))
             (category (org-get-category))
             (todo-state (org-get-todo-state))
             (tags (org-get-tags))
             (done (equal todo-state "DONE"))
             (line (concat "    " (if done "✓ " commitment-mark) title
                           (unless done (org-workflow-agenda--visible-tags tags)))))
        (when done (put-text-property 0 (length line) 'face 'org-workflow-agenda-meta line))
        (org-add-props line nil
          'org-marker agenda-marker
          'org-hd-marker agenda-marker
          'org-category category
          'todo-state todo-state
          'tags tags
          'priority priority
          'type "todo"
          'org-heading t
          'mouse-face 'highlight
          'help-echo (format "Open %s" title))))))

(defun org-workflow-agenda--visible-tags (tags)
  "Return the planning-relevant subset of effective TAGS as display text."
  (let ((visible (seq-filter
                  (lambda (tag) (member tag '("@flow" "@tiny" "@deep")))
                  tags)))
    (if visible (concat (propertize "  " 'org-workflow-agenda-right-spacer t)
                        ":" (string-join visible ":") ":") "")))

(defun org-workflow-agenda--completed-periods (date)
  "Return priority bands represented by DATE's completed arranged tasks."
  (let (periods)
    (dolist (entry (org-workflow-agenda--completed-arranged date))
      (cl-pushnew (org-workflow-agenda--priority-letter
                   (org-workflow-target-entry-priority entry)) periods))
    periods))

(defun org-workflow-agenda--insert-day-tabs ()
  "Insert the shared Sprint view controls."
  (dolist (item '((today . "今日") (tomorrow . "明日") (projects . "项目")))
    (insert-text-button
     (concat " " (cdr item) " ")
     'face (if (eq (org-workflow-agenda-selected-view) (car item))
               'org-workflow-agenda-group 'org-workflow-agenda-meta)
     'follow-link t 'keymap org-workflow-agenda-header-button-map
     'org-workflow-agenda-view (car item)
     'action (lambda (button)
               (org-workflow-agenda-select-view (button-get button 'org-workflow-agenda-view))))
    (insert "  ")))

(defun org-workflow-agenda--candidate-group ()
  "Return identity and label of the current leaf's level-one ancestor."
  (save-excursion
    (while (org-up-heading-safe))
    (list (list (or buffer-file-name (buffer-name)) (copy-marker (point)))
          (substring-no-properties (org-get-heading t t t t)))))

(defun org-workflow-agenda--candidate-entries (&optional current-only)
  "Collect unscheduled leaves in source order with their project groups.
CURRENT-ONLY limits entries to the current DIVE stages."
  (let ((all (and (not current-only)
                  (org-workflow-agenda--setting 'org-workflow-agenda-planning-all))) rows)
    (dolist (file (org-agenda-files t))
      (when (file-readable-p file)
        (with-current-buffer (find-file-noselect file)
          (org-with-wide-buffer
           (let ((org-workflow-agenda-planning-all all))
             (org-map-entries
              (lambda ()
                (when (org-workflow-agenda--plannable-current-leaf-p)
                  (let* ((marker (copy-marker (point)))
                         (parent (org-workflow-target--direct-parent-marker))
                         (group (org-workflow-agenda--candidate-group))
                         (entry (org-workflow-target-entry-create
                                 :marker marker :group-marker parent
                                 :priority (org-workflow--effective-priority-at-point)
                                 :title (org-workflow-target--entry-title)
                                 :group-title (when parent
                                                (org-with-point-at parent
                                                  (org-get-heading t t t t)))
                                 :file file :outline-position (point))))
                    (push (list entry (car group) (cadr group)) rows))))
              nil 'file))))))
    (nreverse rows)))

(defvar-local org-workflow-agenda--candidate-tab-data nil)

(defun org-workflow-agenda--select-candidate-project (id)
  "Select project ID in the candidate pane."
  (org-workflow-agenda--clear-selection)
  (org-workflow-agenda--set-setting 'org-workflow-agenda-selected-group id)
  (org-agenda-redo))

(defun org-workflow-agenda-candidate-tabs ()
  "Return native tab-line tabs for this pane's candidate projects."
  (let ((selected (org-workflow-agenda--setting 'org-workflow-agenda-selected-group)))
    (mapcar
     (lambda (tab)
       (let ((id (alist-get 'org-workflow-agenda-group-id tab)))
         (append tab `((selected . ,(equal selected id))))))
     org-workflow-agenda--candidate-tab-data)))

(defun org-workflow-agenda--candidate-tab-line ()
  "Use file tabs only in the dedicated project pane."
  (when (and (eq org-workflow-agenda--pane-role 'schedule)
             org-workflow-agenda--workbench
             (org-workflow-agenda-workbench-tab-frame org-workflow-agenda--workbench))
    (setq-local tab-line-format nil))
  (if (eq (org-workflow-agenda-selected-view) 'projects)
      (tab-line-mode -1)
  (when (eq org-workflow-agenda--pane-role 'candidates)
    (setq-local tab-line-tabs-function #'org-workflow-agenda-candidate-tabs
                tab-line-new-button-show nil
                tab-line-close-button-show nil)
    (tab-line-mode 1)
    (tab-line-force-update nil))))

(defun org-workflow-agenda--cycle-candidate-project (count)
  "Cycle goal files by signed COUNT, including All."
  (unless (eq org-workflow-agenda--pane-role 'candidates)
    (user-error "请在右侧项目栏切换目标文件"))
  (let* ((groups org-workflow-agenda--candidate-tab-data)
         (selected (org-workflow-agenda--setting 'org-workflow-agenda-selected-group))
         (index (or (seq-position groups selected
                                  (lambda (group id)
                                    (equal (alist-get 'org-workflow-agenda-group-id group) id)))
                    0)))
    (when groups
      (org-workflow-agenda--select-candidate-project
       (alist-get 'org-workflow-agenda-group-id
                  (nth (mod (+ index count) (length groups)) groups))))))

;;;###autoload
(defun org-workflow-agenda-next-project (&optional count)
  "Select the next candidate project, wrapping through All, by COUNT steps."
  (interactive "p")
  (org-workflow-agenda--cycle-candidate-project (or count 1)))

;;;###autoload
(defun org-workflow-agenda-previous-project (&optional count)
  "Select the previous candidate project by COUNT steps, wrapping through All."
  (interactive "p")
  (org-workflow-agenda--cycle-candidate-project (- (or count 1))))

(defun org-workflow-agenda-candidates (_match)
  "Render compact parent groups and native Agenda candidate rows."
  (let* ((start (point))
         (rows (org-workflow-agenda--candidate-entries))
         (groups nil)
         (selected (org-workflow-agenda--setting 'org-workflow-agenda-selected-group))
         previous-parent)
    ;; seq-group-by does not promise first-occurrence order for its groups.
    (dolist (row rows)
      (if-let* ((group (assoc (cadr row) groups)))
          (setcdr group (append (cdr group) (list row)))
        (setq groups (append groups (list (list (cadr row) row))))))
    (unless (or (null selected) (assoc selected groups))
      (setq selected nil)
      (org-workflow-agenda--set-setting 'org-workflow-agenda-selected-group nil))
    (insert (org-workflow-agenda-needs-scheduling-header))
    (setq-local org-workflow-agenda--candidate-tab-data nil)
    (dolist (group (cons (cons nil rows) groups))
      (let* ((id (car group))
             (base (if id (nth 2 (cadr group)) "全部"))
             (duplicates (and id (seq-count
                                  (lambda (other) (equal base (nth 2 (cadr other))))
                                  groups)))
             (label (format "%s%s" base
                            (if (and duplicates (> duplicates 1))
                                (format " (%s)" (file-name-nondirectory (car id))) ""))))
        (push `((name . ,label) (org-workflow-agenda-group-id . ,id)
                (select . ,(lambda () (org-workflow-agenda--select-candidate-project id))))
              org-workflow-agenda--candidate-tab-data)))
    (setq org-workflow-agenda--candidate-tab-data (nreverse org-workflow-agenda--candidate-tab-data))
    (insert "\n")
    (dolist (row rows)
      (when (or (null selected) (equal selected (cadr row)))
        (let* ((entry (car row)) (group (cadr row))
               (parent (org-workflow-target-entry-group-marker entry)))
          (unless (equal (list group parent) previous-parent)
            (setq previous-parent (list group parent))
            (insert (propertize (concat "    " (org-workflow-agenda--entry-group-title entry) "\n")
                                'org-agenda-structural-header t)))
          (insert (org-workflow-agenda--stack-line entry nil) "\n"))))
    (unless rows (insert (propertize "    暂无待安排任务\n" 'face 'org-workflow-agenda-meta)))
    (insert "\n")
    (add-text-properties start (point) '(org-agenda-type todo))))

(defun org-workflow-agenda--deadline-goals ()
  "Return active DIVE deadline records in ascending date order.
Records contain date, source file and heading position.  Parent milestones
are included; execution queue rules are unchanged."
  (let (records)
    (dolist (file (org-agenda-files t))
      (setq records
            (nconc records
                   (org-workflow-source-read
                    file
                    (lambda ()
                      (when (and (org-workflow--file-kind)
                                 (not (member "workflow-closed" org-file-tags)))
                        (let (found)
                          (org-map-entries
                           (lambda ()
                             (when (and (equal (org-get-todo-state) "DIVE")
                                        (not (org-workflow--held-p))
                                        (not (equal (org-entry-get nil "STYLE") "habit")))
                               (when-let* ((date (org-workflow-target--timestamp-date
                                                 (org-entry-get nil "DEADLINE"))))
                                 (push (list date file (point)) found))))
                           nil 'file)
                          (nreverse found))))))))
    (cl-stable-sort records #'string< :key #'car)))

(defun org-workflow-agenda-open-goals ()
  "Choose and visit an active DIVE stage with a deadline, without writing."
  (interactive)
  (let ((records (org-workflow-agenda--deadline-goals)))
    (unless records (user-error "暂无阶段目标；请为 DIVE 阶段设置 DEADLINE"))
    (let* ((choices
            (mapcar
             (lambda (record)
               (pcase-let ((`(,date ,file ,position) record))
                 (cons (org-workflow-source-read
                        file (lambda ()
                               (goto-char position)
                               (format "%s · %s · %s:%d" date
                                       (org-link-display-format (org-get-heading t t t t))
                                       (file-name-base file) (line-number-at-pos))))
                       record))) records))
           (record (if (= (length records) 1) (car records)
                     (cdr (assoc (completing-read "阶段目标：" choices nil t) choices)))))
      (find-file (nth 1 record))
      (widen)
      (goto-char (nth 2 record))
      (org-fold-show-context)
      (org-fold-show-entry))))

(defun org-workflow-agenda-deadline-goals (_match)
  "Insert compact deadline stages before Sprint's daily arrangements.
Use native Agenda markers and the existing parent progress renderer."
  (when-let* ((records (org-workflow-agenda--deadline-goals)))
    (let ((start (point))
          (today (time-to-days (org-time-string-to-time (org-workflow-target--today-string)))))
      (insert (org-workflow-agenda--section-header "目标"))
      (dolist (record records)
        (pcase-let ((`(,date ,file ,position) record))
          (let* ((remaining (- (time-to-days (org-time-string-to-time date)) today))
                 (urgent (<= remaining 3))
                 (line
                  (with-current-buffer (find-file-noselect file)
                    (org-with-wide-buffer
                      (goto-char position)
                      (let* ((title (substring-no-properties
                                     (org-link-display-format (org-get-heading t t t t))))
                             (native (org-workflow-agenda--stack-line
                                      (org-workflow-target-entry-create
                                       :marker (point-marker) :title title
                                       :priority (org-workflow--effective-priority-at-point)) nil))
                             (line (apply #'propertize (concat "    " title)
                                          (text-properties-at 0 native))))
                        (put-text-property 4 (length line) 'face
                                           (if urgent 'error 'default) line)
                        (put-text-property 0 (length line) 'org-workflow-agenda-stage-goal t line)
                        (put-text-property 0 (length line) 'wrap-prefix "    " line)
                        line))))
                 (marker (get-text-property 0 'org-hd-marker line))
                 (label (cond ((< remaining 0) (format "逾期 %d 天" (- remaining)))
                              ((zerop remaining) "今天截止")
                              (t (format "剩 %d 天" remaining)))))
            (insert line
                    (propertize (concat "  " label)
                                'face (if urgent 'error 'org-workflow-agenda-meta)
                                'help-echo (concat "截止日期：" date)
                                'display (concat "  " label) 'wrap-prefix "    "
                                'org-marker marker 'org-hd-marker marker)
                    "\n"))))
      (insert "\n")
      (add-text-properties start (point) '(org-agenda-type todo)))))

(defun org-workflow-agenda-workbench-view (_match)
  "Render the independent candidate, schedule or combined workbench pane."
  (if (eq (org-workflow-agenda-selected-view) 'projects)
      (let ((start (point)))
        (unless (eq org-workflow-agenda--pane-role 'candidates)
          (org-workflow-agenda--insert-day-tabs) (insert "\n\n"))
        (org-workflow-agenda-projects-render
         (not (eq org-workflow-agenda--pane-role 'candidates)))
        (add-text-properties start (point) '(org-agenda-type todo)))
  (let* ((role (or (bound-and-true-p org-workflow-agenda--pane-role) 'combined))
         (habit-rows (when (and (memq role '(combined schedule))
                                (not (org-workflow-agenda--setting 'org-workflow-agenda-plan-tomorrow)))
                       (org-workflow-evening--habit-rows (org-workflow-agenda-target-date)))))
    (when (memq role '(combined schedule))
      (org-workflow-agenda-deadline-goals nil)
      (org-workflow-agenda-task-stack nil habit-rows))
    (when (eq role 'candidates)
      (org-workflow-agenda-projects nil))
    (when (memq role '(combined schedule))
      (org-workflow-agenda-inbox nil habit-rows)
      (unless (org-workflow-agenda--setting 'org-workflow-agenda-plan-tomorrow)
        (org-workflow-agenda-completed nil))))))

(require 'org-workflow-agenda-notes)


(cl-defun org-workflow-agenda-inbox
    (_match &optional
            (habit-rows (unless (org-workflow-agenda--setting 'org-workflow-agenda-plan-tomorrow)
                          (org-workflow-evening--habit-rows (org-workflow-agenda-target-date)))))
  "Render free HABIT-ROWS, Inbox, pending questions and four steps per project."
  (require 'org-workflow-agenda-inbox)
  (goto-char (point-max))
  (let* ((start (point)) (inhibit-read-only t)
         (habits (seq-filter
                  (lambda (row) (and (null (car row))
                                    (not (get-text-property 0 'org-workflow-agenda-habit-done (cdr row)))))
                  habit-rows))
         (collected (org-workflow-collection-inbox--pending
                     (org-workflow-collection-inbox--review-files) t t))
         (seen (make-hash-table :test #'equal)))
    (insert "\n" (org-workflow-agenda--section-header "随时"))
    (when habits
      (insert (propertize "  习惯\n" 'face 'org-workflow-agenda-meta
                          'org-agenda-structural-header t 'org-workflow-agenda-create-context 'habit))
      (dolist (row habits) (insert (cdr row))))
    (when collected
      (insert (propertize "  Inbox\n" 'face 'org-workflow-agenda-meta
                          'org-agenda-structural-header t))
      (dolist (record collected)
        (let ((original-title (cadr record)) (marker (nth 2 record)))
          (org-with-point-at marker
            (puthash (list buffer-file-name (point)) t seen))
          (let ((line (org-with-point-at marker
                        (org-workflow-agenda--stack-line
                         (org-workflow-target-entry-create
                          :marker marker :title (org-link-display-format (org-get-heading t t t t))
                          :priority (org-workflow--effective-priority-at-point)) nil))))
            (insert (propertize (concat line "\n")
                                'org-workflow-agenda-inbox-entry t
                                'org-workflow-collection-review-title original-title)))
          (when (org-with-point-at marker (org-workflow-qa-p))
            (org-workflow-agenda-insert-note-preview marker)))))
    (let ((questions (org-workflow-agenda-pending-questions)) shown)
      (dolist (marker questions)
        (unless (org-with-point-at marker
                  (gethash (list buffer-file-name (point)) seen))
          (unless shown
            (insert (propertize "  疑问\n" 'face 'org-workflow-agenda-meta
                                'org-agenda-structural-header t))
            (setq shown t))
          (insert (org-workflow-agenda--stack-line (org-workflow-item-at-marker marker) nil) "\n")
          (org-workflow-agenda-insert-note-preview marker))))
    (dolist (group (org-workflow-agenda-anytime-projects))
      (insert (propertize (concat "  " (plist-get (car group) :title) "\n")
                          'face 'org-workflow-agenda-anytime-project 'org-agenda-structural-header t))
      (let (previous-stage)
        (dolist (entry (cdr group))
          (let ((stage (org-with-point-at (org-workflow-target-entry-marker entry)
                         (save-excursion
                           (while (and (> (org-outline-level) 2) (org-up-heading-safe)))
                           (org-get-heading t t t t)))))
            (unless (equal stage previous-stage)
              (setq previous-stage stage)
              (insert (propertize (concat "    " stage "\n") 'face 'org-workflow-agenda-meta
                                  'org-agenda-structural-header t))))
          (insert (org-workflow-agenda--stack-line entry nil) "\n"))))
    (insert "\n")
    (add-text-properties start (point) '(org-agenda-type todo))))

(defun org-workflow-agenda-task-stack (_match &optional habit-rows)
  "Insert the target day's queue and optional HABIT-ROWS by work window."
  (let* ((start (point))
         (target (org-workflow-agenda-target-date))
         (tomorrow (org-workflow-agenda--setting 'org-workflow-agenda-plan-tomorrow))
         (entries (seq-filter
                   (lambda (entry)
                     (and (org-workflow-target--valid-entry-p entry)
                          (or (not tomorrow)
                              (equal target (org-workflow-target-entry-scheduled-date entry)))))
                   (org-workflow-target--ordered-entries (and tomorrow target))))
         (completed (unless tomorrow (org-workflow-agenda--completed-arranged target))))
    (insert (propertize "安排" 'face 'org-workflow-agenda-section
                        'org-agenda-structural-header t) "    ")
    (org-workflow-agenda--insert-day-tabs)
    (insert "\n")
    (dolist (letter '(?A ?B ?C))
      (let* ((priority (org-get-priority (format "[#%c]" letter)))
             (period-entries (seq-filter
                              (lambda (entry)
                                (= priority (org-workflow-target-entry-priority entry)))
                              entries))
             (period-completed (seq-filter
                                (lambda (entry) (= priority (org-workflow-target-entry-priority entry)))
                                completed))
             (period-start (point))
             previous-group content-start)
        (insert (org-workflow-agenda--period-header priority period-entries))
        (setq content-start (point))
        (when habit-rows
          (org-workflow-evening--insert-habits habit-rows letter 'early))
        (dolist (entry period-entries)
          (let ((group (org-workflow-target--group-key entry)))
            (unless (equal group previous-group)
              (setq previous-group group)
              (insert (propertize
                       (concat "    " (org-workflow-agenda--entry-group-title entry) "\n")
                       'keymap org-super-agenda-header-map
                       'local-map org-super-agenda-header-map
                       'org-super-agenda-header t)))
            (insert (org-workflow-agenda--stack-line entry nil) "\n")))
        (when habit-rows
          (org-workflow-evening--insert-habits habit-rows letter 'late))
        ;; 当天已完成项集中放到回顾区。这里仅在没有未完成任务时给出总结；
        ;; CLOCK 读取直属记录并按本地日期截取，不重复累加子节点或昨日投入。
        (if (and (null period-entries) period-completed)
            (let ((minutes
                   (cl-loop for entry in period-completed
                            sum (or (plist-get (org-workflow-item-day-record entry target)
                                               :focusMinutes) 0))))
              (insert (propertize
                       (format "      已完成 %d 项任务，共专注 %d 时 %d 分\n"
                               (length period-completed) (/ minutes 60) (% minutes 60))
                       'face 'org-workflow-agenda-meta)))
          (when (= content-start (point))
            (insert (propertize "      暂无安排\n" 'face 'org-workflow-agenda-meta))))
        (insert "\n")
        (let ((cursor period-start))
          (while (< cursor (point))
            (let ((next (next-single-property-change
                         cursor 'org-workflow-agenda-create-context nil (point))))
              (unless (get-text-property cursor 'org-workflow-agenda-create-context)
                (put-text-property cursor next 'org-workflow-agenda-create-context
                                   `(task ,target ,letter)))
              (setq cursor next))))))
    (add-text-properties start (point) '(org-agenda-type todo))))

(defun org-workflow-agenda--date-offset (days)
  "Return DAYS after Workflow's today as an ISO date."
  (format-time-string
   "%Y-%m-%d"
   (time-add (date-to-time (concat (org-workflow-target--today-string) " 12:00"))
             (days-to-time days))))

(defvar org-workflow-agenda-header-button-map
  (let ((map (copy-keymap button-map)))
    (org-workflow--keymap-set map "<mouse-1>" #'push-button)
    map)
  "Button map for day selection and completion section headers.")

(defun org-workflow-agenda--redo-at-task (marker)
  "Rebuild Sprint without following MARKER, reporting its scheduled date."
  (let ((date (org-with-point-at marker
                (org-workflow-target--timestamp-date (org-entry-get nil "SCHEDULED")))))
    (org-agenda-redo)
    (when date
      (message "已安排至 %s" date))))

(defun org-workflow-agenda--planning-line-display ()
  "Simplify Sprint task text before org-modern, preserving Agenda metadata."
  (when org-workflow-agenda-sprint-view
    (setq-local word-wrap t)
    (let ((inhibit-read-only t))
      (save-excursion
        (goto-char (point-min))
        (while (not (eobp))
          (when-let* ((marker (org-get-at-bol 'org-hd-marker))
                      ((not (or (org-get-at-bol 'org-workflow-agenda-stage-goal)
                                 (org-get-at-bol 'org-workflow-agenda-project-row)))))
            (let* ((start (line-beginning-position))
                   (props (text-properties-at start))
                   (text (buffer-substring start (line-end-position)))
                   (tags (unless (or (org-get-at-bol 'org-workflow-agenda-preview)
                                      (equal (org-get-at-bol 'todo-state) "DONE"))
                           (org-with-point-at marker (org-get-tags)))))
              (setq text (replace-regexp-in-string "\\[#[[:alnum:]]\\] *" "" text))
              (when (string-match org-tag-group-re text)
                (setq text (substring text 0 (match-beginning 0))))
              (delete-region start (line-end-position))
              (insert (apply #'propertize (string-trim-right text) props)
                      (apply #'propertize (org-workflow-agenda--visible-tags tags) props))
              (let ((indent (if (string-match "\\` +" text)
                                (length (match-string 0 text)) 4)))
                (put-text-property start (line-end-position) 'wrap-prefix
                                   (make-string indent ?\s)))))
          (forward-line 1))))))

(defun org-workflow-agenda--align-right-details (&optional window)
  "Anchor Sprint details to the right edge of optional WINDOW."
  (when org-workflow-agenda--sprint-buffer-p
    (org-workflow-agenda--fit-breadcrumbs window)
    (let ((inhibit-read-only t))
      (save-excursion
        (goto-char (point-min))
        (while (< (point) (point-max))
          (when-let* ((spacer (text-property-any (line-beginning-position)
                                               (line-end-position)
                                               'org-workflow-agenda-right-spacer t)))
            (let* ((tail (buffer-substring (+ 2 spacer) (line-end-position)))
                   (prefix (buffer-substring (line-beginning-position) spacer))
                   (window (or (and (window-live-p window) window)
                               (get-buffer-window (current-buffer))))
                   (graphical (and window (display-graphic-p (window-frame window))))
                   (tail-width (if graphical (string-pixel-width tail (current-buffer))
                                 (string-width tail)))
                   (wrap (and window
                              (if graphical
                                  (> (+ (string-pixel-width prefix (current-buffer))
                                        tail-width (* 2 (frame-char-width (window-frame window))))
                                     (window-body-width window t))
                                (> (+ (string-width prefix) tail-width 2)
                                   (window-body-width window))))))
              (remove-text-properties spacer (+ 2 spacer) '(face nil invisible nil))
              (put-text-property spacer (1+ spacer) 'display (if wrap "\n" ""))
              (put-text-property (1+ spacer) (+ 2 spacer) 'display
                                 `(space :align-to (- right ,(if graphical
                                                               `(,tail-width)
                                                             tail-width) 1)))))
          (forward-line 1))))))

(defun org-workflow-agenda--realign-details (frame)
  "Update detail wrapping after FRAME's window sizes change."
  (dolist (window (window-list frame 'no-minibuffer))
    (with-current-buffer (window-buffer window)
      (org-workflow-agenda--align-right-details window))))

(defvar org-workflow-agenda-planning-all nil
  "Non-nil means Sprint candidates include all scoped project/area leaves.
The default nil limits candidates to direct TODO leaf children of DIVE roots.
This changes only display.")

(defun org-workflow-agenda-planning-scope-label ()
  "Describe the current candidate scope and its toggle."
  (if (org-workflow-agenda--setting 'org-workflow-agenda-planning-all) "范围：全部 → 当前" "范围：当前 → 全部"))

(defun org-workflow-agenda-toggle-planning-scope ()
  "Toggle between DIVE children and all scoped unscheduled TODO leaves."
  (interactive)
  (org-workflow-agenda--clear-selection)
  (org-workflow-agenda--set-setting 'org-workflow-agenda-planning-all
                              (not (org-workflow-agenda--setting 'org-workflow-agenda-planning-all)))
  (org-agenda-redo)
  (goto-char (point-min))
  (search-forward "待安排" nil t)
  (beginning-of-line)
  (message "待安排范围：%s；原有标签筛选仍然保留"
           (if (org-workflow-agenda--setting 'org-workflow-agenda-planning-all) "全部 project/area" "DIVE")))

(defun org-workflow-agenda--plannable-current-leaf-p ()
  "Return non-nil for an unscheduled TODO leaf in the selected planning scope."
  (and (org-workflow--file-kind)
       (or (org-workflow-agenda--setting 'org-workflow-agenda-planning-all)
           (org-workflow--dive-child-p))
       (>= (org-outline-level) 2)
       (equal (org-get-todo-state) "TODO")
       (org-workflow-target--task-leaf-p)
       (not (and (fboundp 'org-workflow-projects-stage-p) (org-workflow-projects-stage-p)))
       (not (org-workflow--held-p))
       (not (org-entry-get nil "SCHEDULED"))))

(defun org-workflow-agenda-needs-scheduling-header ()
  "Return the compact header for tasks which need scheduling."
  (concat (propertize "待安排" 'face 'org-workflow-agenda-section
                       'org-agenda-structural-header t)
          (propertize (if (org-workflow-agenda--setting 'org-workflow-agenda-planning-all) " · 全部范围" " · 当前范围")
                      'face 'org-workflow-agenda-meta 'org-agenda-structural-header t)
          "\n"))

(defun org-workflow-agenda--compact-group-faces ()
  "Reduce visual emphasis of group headings in the Sprint agenda."
  (when org-workflow-agenda-sprint-view
    (let ((inhibit-read-only t)
          (position (point-min)))
      (while (< position (point-max))
        (let ((next (next-single-property-change
                     position 'org-super-agenda-header nil (point-max))))
          (when (and (get-text-property position 'org-super-agenda-header)
                     (not (text-property-not-all position next 'org-workflow-agenda-group-header nil)))
            (put-text-property position next 'face 'org-workflow-agenda-group))
          (setq position next))))))

(defun org-workflow-agenda--group-progress ()
  "Display parent and stage progress with optional Org Modern colors."
  (when (and org-workflow-agenda--sprint-buffer-p
             (facep 'org-modern-progress-complete))
    (save-excursion
      (save-match-data
        (let ((inhibit-read-only t))
          (goto-char (point-min))
          (while (re-search-forward "\\[\\([0-9]+\\)/\\([0-9]+\\)]" nil t)
            (let* ((start (match-beginning 0)) (end (match-end 0))
                   (done (string-to-number (match-string 1)))
                   (total (string-to-number (match-string 2)))
                   (label (format "%d/%d" done total))
                   (width (max 12 (length label)))
                   (left (/ (- width (length label)) 2))
                   (bar (concat (make-string left ?\s) label
                                (make-string (- width left (length label)) ?\s)))
                   (filled (if (zerop total) width
                             (min width (floor (* width (/ (float done) total)))))))
              (when (or (get-text-property start 'org-workflow-agenda-group-header)
                        (get-text-property start 'org-workflow-agenda-stage-goal))
                (add-text-properties 0 filled '(face org-modern-progress-complete) bar)
                (add-text-properties filled width '(face org-modern-progress-incomplete) bar)
                (put-text-property start end 'face 'org-modern-label)
                (put-text-property start end 'display bar)))))))))

(defun org-workflow-agenda--truncate-lines ()
  "Keep Agenda rows on a single visual line."
  (visual-line-mode -1)
  (setq-local truncate-lines t))

(defun org-workflow-agenda-view--enable ()
  "Install this component while Workflow is being enabled."
  (org-workflow--add-hook 'org-agenda-mode-hook #'org-workflow-agenda--truncate-lines)
  (org-workflow--add-hook 'org-agenda-finalize-hook #'org-workflow-agenda--truncate-lines 99)
  (org-workflow--add-hook 'org-agenda-finalize-hook #'org-workflow-agenda--planning-line-display -90)
  (org-workflow--add-hook 'org-agenda-finalize-hook #'org-workflow-agenda--align-right-details 96)
  (org-workflow--add-hook 'window-size-change-functions #'org-workflow-agenda--realign-details)
  (org-workflow--add-hook 'org-agenda-finalize-hook #'org-workflow-agenda--compact-group-faces)
  (org-workflow--add-hook 'org-agenda-finalize-hook #'org-workflow-agenda--group-progress 92)
  (org-workflow--add-hook 'org-agenda-finalize-hook #'org-workflow-agenda--candidate-tab-line 95))

(provide 'org-workflow-agenda-view)
;;; org-workflow-agenda-view.el ends here
