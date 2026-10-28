;;; org-workflow-agenda-projects.el --- Projects within the daily Agenda -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Jinwang Dong
;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Commentary:
;; Read-only project summaries and task previews.  Native source markers keep
;; ordinary Agenda editing available for projects, stages and next steps.
;;; Code:
(require 'org-workflow-projects)
(require 'org-workflow-history)
(declare-function org-workflow-agenda--select-candidate-project "org-workflow-agenda-view" (id))
(declare-function org-workflow-agenda--stack-line "org-workflow-agenda-view" (entry index))
(declare-function org-workflow-agenda--section-header "org-workflow-agenda-view" (title))
(declare-function org-workflow-agenda-target-date "org-workflow-agenda-layout" ())

(declare-function org-workflow-evening--day-icon "org-workflow-evening" (state face))

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
  "Read concrete steps and all structural Headings without counting QA."
  (let ((done 0) (total 0) stages)
    (org-workflow-source-read
     (plist-get project :file)
     (lambda ()
       (goto-char (plist-get project :pos))
       (let ((level (org-outline-level)))
         (org-map-entries
          (lambda ()
            (let ((depth (org-outline-level)) (qa (org-workflow-qa-p)))
              (when (and (= depth (1+ level)) (org-workflow-projects-stage-p))
                (push (append (org-workflow-projects--location)
                              (list :state (org-get-todo-state) :children nil)) stages))
              (when (and stages (> depth (1+ level)) (org-get-todo-state))
                (setf (plist-get (car stages) :children)
                      (append (plist-get (car stages) :children)
                              (list (append (org-workflow-projects--location)
                                            (list :state (org-get-todo-state) :depth (- depth level)
                                                  :qa qa))))))
              (cond (qa (setq org-map-continue-from (save-excursion (org-end-of-subtree t t))))
                    ((and (> depth (1+ level)) (org-workflow-target--task-leaf-p))
                     (cl-incf total)
                     (when (equal (org-get-todo-state) "DONE") (cl-incf done)))))) nil 'tree))))
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

(defun org-workflow-agenda-project-goal-toggle ()
  "Pause or resume the file goal at point, then refresh the Agenda."
  (interactive)
  (let ((goal (get-text-property (line-beginning-position) 'workflow-goal)))
    (unless goal (user-error "请选择长期目标行"))
    (org-workflow-projects-goal-state (org-workflow-projects-marker goal)
                                     (not (plist-get goal :paused)))
    (org-agenda-redo)))

(defvar org-workflow-agenda-project-goal-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "t") #'org-workflow-agenda-project-goal-toggle)
    map)
  "Goal-row pause action; project/stage rows use native Agenda TODO commands.")

(defun org-workflow-agenda-projects (_match)
  "Insert goals, projects, stages and weekly tracking in today's Agenda."
  (let* ((start (point))
         (items (org-workflow-projects-collect))
         (goals (seq-filter (lambda (x) (equal (plist-get x :kind) "goal")) items))
         (projects (seq-filter (lambda (x) (equal (plist-get x :kind) "project")) items))
         (date (org-workflow-agenda-target-date))
         (filtering (eq org-workflow-agenda--pane-role 'candidates))
         (selected (and filtering (org-workflow-agenda--setting 'org-workflow-agenda-selected-group)))
         shown-goal)
    (when filtering
      (unless (seq-some (lambda (goal) (equal selected (plist-get goal :id))) goals)
        (setq selected nil)
        (org-workflow-agenda--set-setting 'org-workflow-agenda-selected-group nil))
      (setq-local org-workflow-agenda--candidate-tab-data
                  (mapcar
                   (lambda (goal)
                     (let ((id (plist-get goal :id)))
                       `((name . ,(or (plist-get goal :title) "全部"))
                         (org-workflow-agenda-group-id . ,id)
                         (select . ,(lambda () (org-workflow-agenda--select-candidate-project id))))))
                   (cons nil goals))))
    (insert (org-workflow-agenda--section-header "项目"))
    (dolist (goal goals)
      (let ((children (seq-filter (lambda (x) (equal (plist-get x :goal-id) (plist-get goal :id))) projects)))
        (when (and children (or (null selected) (equal selected (plist-get goal :id))))
          (when shown-goal (insert "\n"))
          (setq shown-goal t)
          (insert (propertize (concat "  " (plist-get goal :title)
                                      (when (plist-get goal :paused) "  HOLD") "\n")
                              'face 'org-workflow-agenda-project-goal 'workflow-goal goal
                              'keymap org-workflow-agenda-project-goal-map
                              'org-agenda-structural-header t
                              'help-echo "t 暂停／恢复此目标"))
          (dolist (project children)
            (let* ((active (equal (plist-get project :state) "DIVE")))
              (org-workflow-agenda-projects--line
               project 4 nil 'project)
              (when active
                (insert "      " (org-workflow-agenda-projects--week
                                  (org-workflow-projects-tracking project date) date) "\n")
                (let (expanded)
                  (dolist (stage (plist-get (org-workflow-projects-progress project) :stages))
                    (org-workflow-agenda-projects--line stage 6 nil 'stage)
                    (when (and (not expanded) (equal (plist-get stage :state) "DIVE"))
                      (setq expanded t)
                      (dolist (task (plist-get stage :children))
                        (org-workflow-agenda-projects--line task 8)))))))))))
    (unless projects (insert (propertize "    暂无项目\n" 'face 'shadow)))
    (insert "\n")
    (add-text-properties start (point) '(org-agenda-type todo))))

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
    (org-agenda-redo)))

(defun org-workflow-agenda-projects--tree-line (item indent role expanded)
  "Render ITEM once, with separate fold and classification destinations."
  (let ((start (point)))
    (org-workflow-agenda-projects--line item indent
                                      (when (plist-get item :qa) " :QA:") role)
    (add-text-properties
     start (point)
     (list 'org-workflow-agenda-expanded expanded
           'mouse-face 'highlight
           'org-workflow-agenda-classify-target
           (when (memq role '(project stage))
             (list :kind (if (eq role 'project) 'project 'heading)
                   :marker (get-text-property start 'org-hd-marker)))))
    (when (memq role '(project stage))
      (save-excursion
        (goto-char (+ start indent))
        (let ((inhibit-read-only t))
          (insert-text-button (if expanded "▾ " "▸ ")
                              'follow-link t 'org-workflow-agenda-fold-button t
                              'action (lambda (_) (org-workflow-agenda-project-toggle))))))))

(defun org-workflow-agenda-projects-render (&optional inbox-role)
  "Render the project's Inbox or the shared Area/project/Heading/task tree."
  (let ((start (point)))
    (if inbox-role
        (progn
          (insert (org-workflow-agenda--section-header "Inbox"))
          (dolist (row (org-workflow-collection-inbox--pending
                        (org-workflow-collection-inbox--review-files) t))
            (let* ((marker (nth 2 row)) (beg (point))
                   (entry (org-workflow-item-at-marker marker)))
              (insert (org-workflow-agenda--stack-line entry 0) "\n")
              (add-text-properties beg (point) '(org-workflow-agenda-inbox-row t)))))
      (let* ((items (org-workflow-projects-collect))
             (projects (seq-filter (lambda (p) (equal (plist-get p :kind) "project")) items))
             (goals (seq-filter (lambda (p) (equal (plist-get p :kind) "goal")) items)))
        (dolist (goal goals)
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
                    (dolist (stage (plist-get (org-workflow-projects-progress project) :stages))
                      (let ((show (org-workflow-agenda-project-expanded-p stage t)))
                        (org-workflow-agenda-projects--tree-line stage 4 'stage show)
                        (when show
                          (dolist (task (plist-get stage :children))
                            (org-workflow-agenda-projects--tree-line
                             task (+ 4 (* 2 (or (plist-get task :depth) 2))) nil nil)))))))))
            (insert "\n")))))
    (add-text-properties start (point) '(org-agenda-type todo))))

(provide 'org-workflow-agenda-projects)
;;; org-workflow-agenda-projects.el ends here
