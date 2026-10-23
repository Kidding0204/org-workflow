;;; org-workflow-agenda-projects.el --- Projects within the daily Agenda -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Jinwang Dong
;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Commentary:
;; Read-only project summaries and task previews.  Native source markers keep
;; ordinary Agenda editing available for projects, stages and next steps.
;;; Code:
(require 'org-workflow-projects)
(require 'org-workflow-history)
(declare-function org-workflow-agenda--stack-line "org-workflow-agenda-view" (entry index))
(declare-function org-workflow-agenda--section-header "org-workflow-agenda-view" (title))
(declare-function org-workflow-agenda-target-date "org-workflow-agenda-layout" ())

(declare-function org-workflow-evening--day-icon "org-workflow-evening" (state face))

(defface org-workflow-agenda-active-project
  '((t :inherit default :weight bold :height 1.12))
  "Active project heading." :group 'org-workflow)
(defface org-workflow-agenda-project-goal
  '((t :inherit default :weight semi-bold))
  "Long-term goal heading." :group 'org-workflow)
(defface org-workflow-agenda-project-stage
  '((t :inherit default))
  "Project stage heading." :group 'org-workflow)

(defun org-workflow-agenda--successor-limit (total)
  "Return the preview budget for TOTAL arranged tasks."
  (cond ((>= total 10) 1) ((>= total 5) 2) (t 3)))

(defun org-workflow-agenda--commitment-entry-p (entry date)
  "Whether ENTRY anchors a commitment on DATE, including completed anchors."
  (org-with-point-at (org-workflow-target-entry-marker entry)
    (or (org-workflow--promise-p)
        (and org-workflow-store-enabled
             (when-let* ((row (org-workflow-store-commitment
                              (org-entry-get nil "WORKFLOW_COMMITMENT_ID"))))
               (and (equal (nth 3 row) date)
                    (not (member (nth 6 row) '("withdrawn" "cancelled")))))))))

(defun org-workflow-agenda--successors (entry limit)
  "Read up to LIMIT unarranged steps after ENTRY within its project."
  (org-with-point-at (org-workflow-target-entry-marker entry)
    (org-with-wide-buffer
     (let* ((origin (point))
            (root (or (org-workflow-projects-root)
                      (org-workflow-target-entry-group-marker entry)))
            (end (and root (org-with-point-at root (org-end-of-subtree t t))))
            rows)
       (when end
         (goto-char origin) (forward-line 1)
         (while (and (< (length rows) limit) (re-search-forward org-heading-regexp end t))
           (goto-char (line-beginning-position))
           (cond
            ((and (org-workflow-target--unfinished-leaf-p)
                  (org-entry-get nil "SCHEDULED")) (goto-char end))
            ((or (member (org-get-todo-state) '("HOLD" "DONE"))
                 (equal (org-entry-get nil "STYLE") "habit")
                 (equal (org-workflow-projects-kind) "project"))
             (org-end-of-subtree t t))
            (t
             (when (and (org-workflow-target--unfinished-leaf-p)
                        (not (org-workflow-projects-stage-p))
                        (not (org-entry-get nil "SCHEDULED")))
               (push (org-workflow-item-at-marker (point-marker)) rows))
             (forward-line 1)))))
       (nreverse rows)))))

(defun org-workflow-agenda--successor-line (entry)
  "Return a quiet indented preview for ENTRY with native source properties."
  (let* ((native (org-workflow-agenda--stack-line entry nil))
         (icon (if (char-displayable-p #xf0311) (string #xf0311) "↳"))
         (line (apply #'propertize
                      (concat "      " icon " " (org-workflow-target-entry-title entry))
                      (text-properties-at 0 native))))
    (add-text-properties 0 (length line)
                         '(face org-workflow-agenda-meta org-workflow-agenda-preview t
                           wrap-prefix "        ") line)
    line))

(defun org-workflow-agenda--with-completed (entries date tomorrow)
  "Merge DATE's completed scheduled leaves into ENTRIES in the same ordering.
TOMORROW projections never include today's completions."
  (unless tomorrow
    (dolist (file (org-agenda-files t))
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
              (push (org-workflow-item-at-marker (point-marker) date) entries))) nil 'file)))))
  (org-workflow-target--order-entries entries))

(defun org-workflow-projects-progress (project)
  "Read PROJECT's done/total concrete steps and stage source records."
  (let ((done 0) (total 0) stages)
    (org-workflow-source-read
     (plist-get project :file)
     (lambda ()
       (goto-char (plist-get project :pos))
       (let ((level (org-outline-level)))
         (org-map-entries
          (lambda ()
            (when (and (= (org-outline-level) (1+ level))
                       (org-workflow-target--task-p)
                       (not (equal (org-entry-get nil "STYLE") "habit")))
              (push (append (org-workflow-projects--location)
                            (list :state (org-get-todo-state) :children nil)) stages))
            (when (and stages (= (org-outline-level) (+ level 2))
                       (org-workflow-target--task-p))
              (setf (plist-get (car stages) :children)
                    (append (plist-get (car stages) :children)
                            (list (append (org-workflow-projects--location)
                                          (list :state (org-get-todo-state)))))))
            (when (and (> (org-outline-level) (1+ level))
                       (org-workflow-target--task-leaf-p))
              (cl-incf total)
              (when (equal (org-get-todo-state) "DONE") (cl-incf done)))) nil 'tree))))
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
     (propertize (format "  连续 %d 天" (org-workflow-projects-streak days date)) 'face 'shadow))))

(defun org-workflow-agenda-projects--line (item indent &optional suffix role)
  "Insert source-backed ITEM at INDENT with optional SUFFIX and visual ROLE."
  (let* ((marker (org-workflow-projects-marker item))
         (state (plist-get item :state))
         (regexps (org-with-point-at marker
                    (list org-todo-regexp org-not-done-regexp)))
         (face (pcase role
                 ('project (if (equal state "DIVE") 'org-workflow-agenda-active-project
                             'org-workflow-agenda-meta))
                 ('stage 'org-workflow-agenda-project-stage)
                 (_ 'org-workflow-agenda-meta)))
         (width (max 10 (- (window-body-width) indent (string-width (or suffix "")) 8))))
    (insert (propertize
             (concat (make-string indent ?\s) (if state (concat state " ") "")
                     (truncate-string-to-width (plist-get item :title) width nil nil "…")
                     suffix "\n")
             'org-marker marker 'org-hd-marker marker 'todo-state state 'type "todo" 'org-heading t 'org-agenda-type 'todo
             'org-todo-regexp (car regexps) 'org-not-done-regexp (cadr regexps)
             'org-workflow-agenda-project-row t 'workflow-project item
             'face face 'help-echo (plist-get item :title)))))

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
  (let* ((items (org-workflow-projects-collect))
         (goals (seq-filter (lambda (x) (equal (plist-get x :kind) "goal")) items))
         (projects (seq-filter (lambda (x) (equal (plist-get x :kind) "project")) items))
         (date (org-workflow-agenda-target-date)))
    (insert (org-workflow-agenda--section-header "项目"))
    (dolist (goal goals)
      (let ((children (seq-filter (lambda (x) (equal (plist-get x :goal-id) (plist-get goal :id))) projects)))
        (when children
          (insert (propertize (concat "  " (plist-get goal :title)
                                      (when (plist-get goal :paused) "  HOLD") "\n")
                              'face 'org-workflow-agenda-project-goal 'workflow-goal goal
                              'keymap org-workflow-agenda-project-goal-map
                              'org-agenda-structural-header t
                              'help-echo "t 暂停／恢复此目标"))
          (dolist (project children)
            (let* ((progress (org-workflow-projects-progress project))
                   (active (equal (plist-get project :state) "DIVE")))
              (org-workflow-agenda-projects--line
               project 4 (format "  %d/%d" (plist-get progress :done) (plist-get progress :total)) 'project)
              (when active
                (insert "      " (org-workflow-agenda-projects--week
                                  (org-workflow-projects-tracking project date) date) "\n")
                (let (expanded)
                  (dolist (stage (plist-get progress :stages))
                    (org-workflow-agenda-projects--line stage 6 nil 'stage)
                    (when (and (not expanded) (equal (plist-get stage :state) "DIVE"))
                      (setq expanded t)
                      (dolist (task (plist-get stage :children))
                        (org-workflow-agenda-projects--line task 8))))))
              (insert "\n"))))))
    (unless projects (insert (propertize "    暂无项目\n" 'face 'shadow)))
    (insert "\n")))

(provide 'org-workflow-agenda-projects)
;;; org-workflow-agenda-projects.el ends here
