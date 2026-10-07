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
(require 'org-workflow-lifecycle)
;;; org-workflow-agenda-view.el --- Sprint sections and display metadata -*- lexical-binding: t; -*-
;;; Commentary:
;; Internal implementation module loaded by org-workflow-agenda.
;;; Code:
(require 'cl-lib)

(require 'org-agenda)

(require 'button)

(require 'tab-line)

(defun org-workflow-agenda-direct-parent-breadcrumb ()
  "Return the current Org entry's direct parent as an Agenda breadcrumb."
  (if-let* (((derived-mode-p 'org-mode))
            (parent (car (last (org-get-outline-path)))))
      (concat parent org-agenda-breadcrumbs-separator)
    ""))

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

(defface org-workflow-agenda-habit
  '((t (:inherit default :height 1.05 :weight semibold)))
  "Habit planning band; colors are supplied by the active theme."
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

(defun org-workflow-agenda--entry-group-title (entry)
  "Return ENTRY's emphasized direct parent followed by quiet ancestors."
  (let ((marker (org-workflow-target-entry-marker entry)))
    (org-with-point-at marker
      (let ((category (org-get-category))
            (ancestors (butlast (org-get-outline-path)))
            (parent (when-let* ((title (org-workflow-target-entry-group-title entry)))
                      (substring-no-properties title))))
        (propertize
         (if (and parent (not (string-empty-p parent)))
             (concat (propertize parent 'face 'org-workflow-agenda-group)
                     (propertize
                      (concat (propertize "  " 'org-workflow-agenda-right-spacer t)
                              (string-join (delete-dups (cons category ancestors)) " / "))
                      'face 'org-workflow-agenda-ancestor))
           (propertize category 'face 'org-workflow-agenda-group))
         'org-workflow-agenda-group-header t)))))

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
                                           (if (or (org-workflow-history-attempted-p date)
                                                   (and (equal (org-get-todo-state) "DONE")
                                                        (equal date (org-workflow-target--timestamp-date
                                                                     (org-entry-get nil "CLOSED")))))
                                               "◆" "◇")
                                           'face 'org-workflow-agenda-commitment) " ")
                                "  "))
             (category (org-get-category))
             (todo-state (org-get-todo-state))
             (tags (org-get-tags))
             (line (concat "    " commitment-mark title
                           (org-workflow-agenda--visible-tags tags))))
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
  "Return time bands with scoped DONE leaves completed on DATE."
  (let (periods)
    (dolist (file (org-agenda-files t))
      (when (file-readable-p file)
        (with-current-buffer (find-file-noselect file)
          (org-with-wide-buffer
           (when (org-workflow--file-kind)
             (org-map-entries
              (lambda ()
                (let ((scheduled (org-workflow-target--timestamp-date
                                  (org-entry-get nil "SCHEDULED"))))
                  (when (and (>= (org-outline-level) 2)
                             (equal (org-get-todo-state) "DONE")
                             (org-workflow-target--task-leaf-p)
                             (not (org-workflow--held-p))
                             (equal date (org-workflow-target--timestamp-date
                                          (org-entry-get nil "CLOSED")))
                             scheduled (not (string< date scheduled)))
                    (cl-pushnew (org-workflow-agenda--priority-letter
                                 (org-workflow--effective-priority-at-point))
                                periods)))) nil 'file))))))
    periods))

(defun org-workflow-agenda--insert-day-tabs ()
  "Insert target-day controls for this workbench."
  (let ((tomorrow (org-workflow-agenda--setting 'org-workflow-agenda-plan-tomorrow)))
    (dolist (item '((nil . "今天") (t . "明天")))
      (insert-text-button
       (concat " " (cdr item) " ")
       'face (if (eq tomorrow (car item)) 'org-workflow-agenda-group 'org-workflow-agenda-meta)
       'follow-link t 'keymap org-workflow-agenda-future-header-map
       'org-workflow-agenda-day (car item)
       'action (lambda (button)
                 (org-workflow-agenda-set-day (button-get button 'org-workflow-agenda-day))))
      (insert "  "))
    (insert "\n\n")))

(defun org-workflow-agenda--candidate-group ()
  "Return identity and label of the current leaf's level-one ancestor."
  (save-excursion
    (while (org-up-heading-safe))
    (list (list (or buffer-file-name (buffer-name)) (copy-marker (point)))
          (substring-no-properties (org-get-heading t t t t)))))

(defun org-workflow-agenda--candidate-entries ()
  "Collect unscheduled leaves in source order with their project groups."
  (let ((all (org-workflow-agenda--setting 'org-workflow-agenda-planning-all)) rows)
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
  "Use project tabs only in the dedicated candidate pane."
  (when (and (eq org-workflow-agenda--pane-role 'schedule)
             org-workflow-agenda--workbench
             (org-workflow-agenda-workbench-tab-frame org-workflow-agenda--workbench))
    (setq-local tab-line-format nil))
  (when (eq org-workflow-agenda--pane-role 'candidates)
    (setq-local tab-line-tabs-function #'org-workflow-agenda-candidate-tabs
                tab-line-new-button-show nil
                tab-line-close-button-show nil)
    (tab-line-mode 1)
    (tab-line-force-update nil)))

(defun org-workflow-agenda--cycle-project-tab (original direction event arg)
  "Cycle project tabs by DIRECTION, otherwise call ORIGINAL with EVENT and ARG."
  (let ((window (if event (posn-window (tab-line-event-start event))
                  (selected-window))))
    (with-selected-window window
      (if (not (eq tab-line-tabs-function #'org-workflow-agenda-candidate-tabs))
          (funcall original event arg)
        (let* ((tabs (org-workflow-agenda-candidate-tabs))
               (index (or (seq-position tabs t
                                        (lambda (tab selected)
                                          (eq (alist-get 'selected tab) selected))) 0))
               (next (+ index (* direction (or arg 1))))
               (target (if tab-line-switch-cycling
                           (mod next (length tabs))
                         (max 0 (min next (1- (length tabs)))))))
          (funcall (alist-get 'select (nth target tabs))))))))

(defun org-workflow-agenda--next-project-tab (original &optional event arg)
  "Call ORIGINAL next-tab command for project tabs using EVENT and ARG."
  (org-workflow-agenda--cycle-project-tab original 1 event arg))

(defun org-workflow-agenda--previous-project-tab (original &optional event arg)
  "Call ORIGINAL previous-tab command for project tabs using EVENT and ARG."
  (org-workflow-agenda--cycle-project-tab original -1 event arg))

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

(defun org-workflow-agenda-workbench-view (_match)
  "Render the independent candidate, schedule or combined workbench pane."
  (let ((role (or (bound-and-true-p org-workflow-agenda--pane-role) 'combined)))
    (when (memq role '(combined schedule))
      (org-workflow-guidance-agenda nil)
      (org-workflow-evening-today nil))
    (when (eq role 'candidates)
      (org-workflow-agenda-candidates nil))
    (when (eq role 'combined)
      (org-workflow-agenda-inbox nil))
    (when (memq role '(combined schedule))
      (unless (org-workflow-agenda--setting 'org-workflow-agenda-plan-tomorrow)
        (org-workflow-agenda-completed nil)))))

(defun org-workflow-agenda-inbox (_match)
  "Render all dates' unscheduled collected items using native Agenda markers."
  (require 'org-workflow-agenda-inbox)
  (goto-char (point-max))
  (let ((start (point)) (inhibit-read-only t) previous-date)
    (insert "\n" (org-workflow-agenda--section-header "收集箱"))
    (dolist (record (org-workflow-collection-inbox--pending
                     (org-workflow-collection-inbox--review-files) t))
      (let ((date (car record)) (original-title (cadr record)) (marker (nth 2 record)))
        (unwind-protect
            (when-let* ((line
                         (org-with-point-at marker
                           (unless (or (org-entry-get nil "SCHEDULED")
                                       (org-entry-get nil "DEADLINE")
                                       (org-entry-is-done-p)
                                       (org-workflow--held-p)
                                       (equal (org-entry-get nil "STYLE") "habit"))
                             (org-workflow-agenda--stack-line
                              (org-workflow-target-entry-create
                               :marker marker :title (org-link-display-format (org-get-heading t t t t))
                               :priority (org-workflow--effective-priority-at-point)) nil)))))
              (unless (equal date previous-date)
                (setq previous-date date)
                (insert (propertize (concat "  " date "\n") 'face 'org-workflow-agenda-meta
                                    'org-agenda-structural-header t)))
              (insert (propertize (concat line "\n")
                                  'org-workflow-agenda-inbox-entry t
                                  'org-workflow-collection-review-title original-title)))
          (set-marker marker nil))))
    (unless previous-date (insert (propertize "    暂无收集项\n" 'face 'shadow)))
    (insert "\n")
    (add-text-properties start (point) '(org-agenda-type todo))))

(defun org-workflow-agenda-task-stack (_match)
  "Insert the target day's queue, grouped by priority and direct parent."
  (let* ((start (point))
         (target (org-workflow-agenda-target-date))
         (tomorrow (org-workflow-agenda--setting 'org-workflow-agenda-plan-tomorrow))
         (entries (seq-filter
                   (lambda (entry)
                     (and (org-workflow-target--valid-entry-p entry)
                          (or (not tomorrow)
                              (equal target (org-workflow-target-entry-scheduled-date entry)))))
                   (org-workflow-target--ordered-entries (and tomorrow target))))
         (completed (org-workflow-agenda--completed-periods target)))
    (org-workflow-agenda--insert-day-tabs)
    (insert (org-workflow-agenda--section-header
             (format "%s安排" (if tomorrow "明日" "今日"))))
    (dolist (letter '(?A ?B ?C))
      (let* ((priority (org-get-priority (format "[#%c]" letter)))
             (period-entries (seq-filter
                              (lambda (entry)
                                (= priority (org-workflow-target-entry-priority entry)))
                              entries))
             (period-start (point))
             previous-group)
        (insert (org-workflow-agenda--period-header priority period-entries))
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
        (unless period-entries
          (insert (propertize (if (memq letter completed)
                                 "      已完成\n" "      暂无安排\n")
                              'face 'org-workflow-agenda-meta)))
        (insert "\n")
        (add-text-properties period-start (point)
                             `(org-workflow-agenda-create-context
                               (task ,target ,letter)))))
    (insert "\n")
    (add-text-properties start (point) '(org-agenda-type todo))))

(defvar org-workflow-agenda-future-expanded t
  "Whether Sprint's future section is expanded for this Emacs session.")

(defun org-workflow-agenda--date-offset (days)
  "Return DAYS after Workflow's today as an ISO date."
  (format-time-string
   "%Y-%m-%d"
   (time-add (date-to-time (concat (org-workflow-target--today-string) " 12:00"))
             (days-to-time days))))

(defun org-workflow-agenda--future-entries ()
  "Return tomorrow through day seven, in date and Workflow group order."
  (let ((today (org-workflow-target--today-string))
        (target (org-workflow-agenda-target-date)))
    (cl-stable-sort
     (seq-filter (lambda (entry)
                   (and (string< today (org-workflow-target-entry-scheduled-date entry))
                        (not (equal target (org-workflow-target-entry-scheduled-date entry)))))
                 (org-workflow-target--ordered-entries (org-workflow-agenda--date-offset 7)))
     #'string< :key #'org-workflow-target-entry-scheduled-date)))

(defun org-workflow-agenda-toggle-future (&optional _button)
  "Expand or collapse future arrangements and keep point on their header."
  (interactive)
  (org-workflow-agenda--set-setting 'org-workflow-agenda-future-expanded
                              (not (org-workflow-agenda--setting 'org-workflow-agenda-future-expanded)))
  (org-agenda-redo)
  (goto-char (point-min))
  (search-forward "未来 7 天" nil t)
  (beginning-of-line))

(defvar org-workflow-agenda-future-header-map
  (let ((map (copy-keymap button-map)))
    (org-workflow--keymap-set map "<mouse-1>" #'push-button)
    map)
  "Button map for the future section; task mouse bindings remain unchanged.")

(defun org-workflow-agenda-future (_match)
  "Insert a collapsible future planning block with native Agenda task rows."
  (goto-char (point-max))
  (let ((inhibit-read-only t)
        (start (point))
        (entries (org-workflow-agenda--future-entries))
        previous-date previous-priority previous-group period-start)
    (insert "\n")
    (insert-text-button
     (format "%s 未来 7 天"
             (if (org-workflow-agenda--setting 'org-workflow-agenda-future-expanded) "▾" "▸"))
     'face 'org-workflow-agenda-section
     'follow-link t
     'keymap org-workflow-agenda-future-header-map
     'action #'org-workflow-agenda-toggle-future
     'help-echo "RET 或左键展开／收起；任务菜单 v 同样可用"
     'org-agenda-structural-header t)
    (insert "\n")
    (when (org-workflow-agenda--setting 'org-workflow-agenda-future-expanded)
      (unless entries
        (insert (propertize "    暂无安排\n" 'face 'shadow)))
      (dolist (entry entries)
        (let ((date (org-workflow-target-entry-scheduled-date entry))
              (priority (org-workflow-target-entry-priority entry))
              (group (org-workflow-target--group-key entry)))
          (unless (equal date previous-date)
            (when period-start
              (add-text-properties period-start (point)
                                   `(org-workflow-agenda-create-context
                                     (task ,previous-date ,(org-workflow-agenda--priority-letter previous-priority))))
              (setq period-start nil))
            (setq previous-date date previous-priority nil previous-group nil)
            (insert (propertize (concat "  " date "\n")
                                'face 'org-workflow-agenda-group
                                'org-agenda-structural-header t)))
          (unless (equal priority previous-priority)
            (when period-start
              (add-text-properties period-start (point)
                                   `(org-workflow-agenda-create-context
                                     (task ,date ,(org-workflow-agenda--priority-letter previous-priority)))))
            (setq previous-priority priority previous-group nil)
            (setq period-start (point))
            (insert (org-workflow-agenda--period-header
                     priority (seq-filter
                               (lambda (item)
                                 (and (= priority (org-workflow-target-entry-priority item))
                                      (equal date (org-workflow-target-entry-scheduled-date item))))
                               entries))))
          (unless (equal group previous-group)
            (setq previous-group group)
            (insert (propertize
                     (concat "    " (org-workflow-agenda--entry-group-title entry) "\n")
                     'org-agenda-structural-header t)))
          (insert (org-workflow-agenda--stack-line entry nil) "\n"))))
    (when period-start
      (add-text-properties period-start (point)
                           `(org-workflow-agenda-create-context
                             (task ,previous-date ,(org-workflow-agenda--priority-letter previous-priority)))))
    (insert "\n")
    (add-text-properties start (point) '(org-agenda-type todo))))

(defun org-workflow-agenda--redo-at-task (marker)
  "Rebuild Sprint, revealing MARKER's future date and restoring its row."
  ;; Redo releases the previous Agenda markers; keep an independent anchor.
  (setq marker (copy-marker marker))
  (let ((date (org-with-point-at marker
                (org-workflow-target--timestamp-date (org-entry-get nil "SCHEDULED")))))
    (when (and date (string< (org-workflow-target--today-string) date)
               (not (string< (org-workflow-agenda--date-offset 7) date)))
      (org-workflow-agenda--set-setting 'org-workflow-agenda-future-expanded t))
    (org-agenda-redo)
    (let ((position (point-min)) found)
      (while (and (< position (point-max)) (not found))
        (if (equal marker (get-text-property position 'org-hd-marker))
            (setq found position)
          (setq position (next-single-property-change
                          position 'org-hd-marker nil (point-max)))))
      (when found (goto-char found)))
    (when date
      (message "已安排至 %s%s" date
               (if (string< (org-workflow-agenda--date-offset 7) date)
                   "（超出未来 7 天视图）" "")))))

(defun org-workflow-agenda--planning-line-display ()
  "Simplify Sprint task text before org-modern, preserving Agenda metadata."
  (when org-workflow-agenda-sprint-view
    (setq-local word-wrap t)
    (let ((inhibit-read-only t))
      (save-excursion
        (goto-char (point-min))
        (while (not (eobp))
          (when-let* ((marker (org-get-at-bol 'org-hd-marker)))
            (let* ((start (line-beginning-position))
                   (props (text-properties-at start))
                   (text (buffer-substring start (line-end-position)))
                   (tags (org-with-point-at marker (org-get-tags))))
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
       (not (org-workflow--held-p))
       (not (org-entry-get nil "SCHEDULED"))))

(defun org-workflow-agenda-skip-nonplannable-current-leaf ()
  "Skip the current match unless it is a plannable Current leaf."
  (unless (org-workflow-agenda--plannable-current-leaf-p)
    (save-excursion
      (or (outline-next-heading) (goto-char (point-max)))
      (point))))

(defun org-workflow-agenda-category-parent-group (_item)
  "Return category and direct parent for the Agenda item at point."
  (let ((category (org-get-category))
        (parent (save-excursion
                  (org-back-to-heading t)
                  (when (org-up-heading-safe)
                    (substring-no-properties (org-get-heading t t t t))))))
    (if (and parent (not (string-empty-p parent)))
        (format "%s · %s" category parent)
      category)))

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
  "Display group progress using optional Org Modern colors and a local renderer."
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
              (when (get-text-property start 'org-workflow-agenda-group-header)
                (add-text-properties 0 filled '(face org-modern-progress-complete) bar)
                (add-text-properties filled width '(face org-modern-progress-incomplete) bar)
                (put-text-property start end 'face 'org-modern-label)
                (put-text-property start end 'display bar)))))))))

(defun org-workflow-agenda-view--enable ()
  "Install this component while Workflow is being enabled."
  (org-workflow--advice-add 'tab-line-switch-to-next-tab :around #'org-workflow-agenda--next-project-tab)
  (org-workflow--advice-add 'tab-line-switch-to-prev-tab :around #'org-workflow-agenda--previous-project-tab)
  (org-workflow--add-hook 'org-agenda-finalize-hook #'org-workflow-agenda--planning-line-display -90)
  (org-workflow--add-hook 'org-agenda-finalize-hook #'org-workflow-agenda--align-right-details 96)
  (org-workflow--add-hook 'window-size-change-functions #'org-workflow-agenda--realign-details)
  (org-workflow--add-hook 'org-agenda-finalize-hook #'org-workflow-agenda--compact-group-faces)
  (org-workflow--add-hook 'org-agenda-finalize-hook #'org-workflow-agenda--group-progress 92)
  (org-workflow--add-hook 'org-agenda-finalize-hook #'org-workflow-agenda--candidate-tab-line 95))

(provide 'org-workflow-agenda-view)
;;; org-workflow-agenda-view.el ends here
