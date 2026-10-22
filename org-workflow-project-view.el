;;; org-workflow-project-view.el --- Native project planning workbench -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Jinwang Dong
;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Commentary:
;; A read-only projection of Org goals/projects.  Editing visits the source;
;; status actions use the shared transactional project API.
;;; Code:
(require 'org-workflow-projects)
(require 'button)
(declare-function org-workflow-open-agenda "org-workflow-weekly" ())
(declare-function evil-set-initial-state "ext:evil-core" (mode state))

(defvar-local org-workflow-project-view--expanded nil)
(defvar-local org-workflow-project-view--items nil)
(defvar-local org-workflow-project-view--goal-folds nil)

(defun org-workflow-project-view--key (item)
  "Return a stable UI key for ITEM."
  (or (plist-get item :id) (cons (plist-get item :file) (plist-get item :pos))))

(defun org-workflow-project-view--at-point ()
  "Return the source-backed row at point."
  (or (get-text-property (point) 'workflow-project)
      (get-text-property (line-beginning-position) 'workflow-project)
      (user-error "请选择项目或长期目标")))

(defun org-workflow-project-view--line (text item &optional face)
  "Insert TEXT linked to ITEM, with optional FACE."
  (let ((start (point)))
    (insert text "\n")
    (add-text-properties start (point) (list 'workflow-project item 'face face))))

(defun org-workflow-project-view--project (item)
  "Insert one project ITEM and its requested planning context."
  (let* ((state (plist-get item :state))
         (expanded (member (org-workflow-project-view--key item) org-workflow-project-view--expanded))
         (next (plist-get item :next)))
    (org-workflow-project-view--line
     (concat "    " (plist-get item :title)
             (if (plist-get item :start)
                 (concat "    " (plist-get item :start)
                         (if (plist-get item :deferred-start) " 待重排" " 开始")) ""))
     item 'bold)
    (when (or (equal state "DIVE") expanded)
      (when (plist-get item :phase)
        (org-workflow-project-view--line (concat "      " (plist-get item :phase)) item 'shadow))
      (org-workflow-project-view--line
       (concat "      " (if (plist-get item :blocked) "上级项目已暂停或完成"
                         (or (plist-get next :title) "尚未明确下一步"))) item
       (unless next 'shadow)))
    (when expanded
      (org-workflow-source-read
       (plist-get item :file)
       (lambda ()
         (goto-char (plist-get item :pos))
         (let ((end (save-excursion (org-end-of-subtree t t))) rows)
           (forward-line 1)
           (while (re-search-forward org-heading-regexp end t)
             (when (and (member (org-get-todo-state) '("TODO" "DIVE" "DONE" "HOLD"))
                        (not (member (org-get-todo-state) '("DONE" "HOLD")))
                        (not (= (line-beginning-position) (or (plist-get next :pos) -1))))
               (push (org-get-heading t t t t) rows)))
           ;; Return values only; render in the view, never in a source buffer.
           (setq expanded (nreverse rows)))))
      (dolist (title expanded)
        (org-workflow-project-view--line (concat "      " title) item)))
    (insert "\n")))

(defun org-workflow-project-view--goal (goal projects)
  "Insert GOAL and its PROJECTS, respecting suspended-goal folding."
  (let* ((choice (assoc (org-workflow-project-view--key goal) org-workflow-project-view--goal-folds))
         (expanded (if choice (cdr choice) (not (plist-get goal :paused)))))
    (org-workflow-project-view--line
     (concat (plist-get goal :title) (when (plist-get goal :paused) "  · 已暂停")) goal 'org-level-1)
    (insert "\n")
    (when expanded
      (dolist (state '("DIVE" "TODO" "HOLD" "DONE"))
        (let ((rows (seq-filter (lambda (x) (equal (plist-get x :state) state)) projects)))
          (when rows
            (org-workflow-project-view--line (concat "  " state) goal 'org-level-2)
            (insert "\n")
            (if (and (equal state "DONE")
                     (not (member 'done org-workflow-project-view--expanded)))
                (insert (propertize (format "    %d 个已完成项目（D 展开）\n\n" (length rows)) 'face 'shadow))
              (dolist (project rows) (org-workflow-project-view--project project)))))))
    (insert "\n")))

(defun org-workflow-project-view-refresh ()
  "Refresh planning data without generating commitments or changing sources."
  (interactive)
  (let ((inhibit-read-only t)
        (line (line-number-at-pos)) (column (current-column))
        (items (org-workflow-projects-collect)))
    (setq org-workflow-project-view--items items)
    (erase-buffer)
    (insert-text-button "今日" 'action (lambda (_) (org-workflow-open-agenda)) 'follow-link t)
    (insert (propertize "    项目\n\n" 'face 'org-level-1))
    (let* ((goals (seq-filter (lambda (x) (equal (plist-get x :kind) "goal")) items))
           (projects (seq-filter (lambda (x) (equal (plist-get x :kind) "project")) items)))
      (dolist (goal goals)
        (org-workflow-project-view--goal
         goal (seq-filter (lambda (x) (equal (plist-get x :goal-id) (plist-get goal :id))) projects)))
      (let ((unassigned (seq-filter
                         (lambda (x) (not (seq-some (lambda (goal) (equal (plist-get x :goal-id) (plist-get goal :id))) goals))) projects)))
        (when unassigned
          (org-workflow-project-view--goal (list :title "未归属目标" :id "unassigned") unassigned)))
      (unless items
        (insert "尚未登记项目。\n\n")
        (insert-text-button "打开源文件登记" 'action (lambda (_) (call-interactively #'org-workflow-project-view-register)) 'follow-link t)
        (insert "\n\n在 Org 标题上使用 M-x org-workflow-projects-register，登记 goal 或 project。\n")))
    (goto-char (point-min)) (forward-line (1- line)) (move-to-column column)))

(defun org-workflow-project-view-visit ()
  "Visit the selected project's original Org heading."
  (interactive)
  (let ((marker (org-workflow-projects-marker (org-workflow-project-view--at-point))))
    (pop-to-buffer (marker-buffer marker))
    (widen) (goto-char marker) (org-fold-show-context 'lineage) (org-fold-show-entry)))

(defun org-workflow-project-view-toggle ()
  "Expand or fold planning context for the selected row."
  (interactive)
  (let* ((item (org-workflow-project-view--at-point))
         (key (org-workflow-project-view--key item)))
    (if (equal (plist-get item :kind) "goal")
        (let* ((choice (assoc key org-workflow-project-view--goal-folds))
               (expanded (if choice (cdr choice) (not (plist-get item :paused)))))
          (setf (alist-get key org-workflow-project-view--goal-folds nil nil #'equal) (not expanded)))
      (if (member key org-workflow-project-view--expanded)
          (setq org-workflow-project-view--expanded (delete key org-workflow-project-view--expanded))
        (push key org-workflow-project-view--expanded))))
  (org-workflow-project-view-refresh))

(defun org-workflow-project-view-toggle-done ()
  "Toggle completed project rows."
  (interactive)
  (if (memq 'done org-workflow-project-view--expanded)
      (setq org-workflow-project-view--expanded (delq 'done org-workflow-project-view--expanded))
    (push 'done org-workflow-project-view--expanded))
  (org-workflow-project-view-refresh))

(defun org-workflow-project-view-state ()
  "Change project state, or pause/resume a goal with provenance."
  (interactive)
  (let* ((item (org-workflow-project-view--at-point))
         (marker (org-workflow-projects-marker item)))
    (if (equal (plist-get item :kind) "goal")
        (org-workflow-projects-goal-state marker
                                          (org-with-point-at marker
                                            (not (org-entry-get nil "WORKFLOW_PAUSED"))))
      (org-workflow-projects-set-state marker (completing-read "项目状态：" '("DIVE" "TODO" "HOLD" "DONE") nil t))))
  (org-workflow-project-view-refresh))

(defun org-workflow-project-view-schedule (&optional remove)
  "Set selected project's start date; with prefix REMOVE clear it."
  (interactive "P")
  (org-workflow-projects-set-start
   (org-workflow-projects-marker (org-workflow-project-view--at-point))
   (unless remove (org-read-date nil nil nil "项目开始日期")))
  (org-workflow-project-view-refresh))

(defun org-workflow-project-view-sync ()
  "Explicitly reconcile manually edited project sources, then refresh the view."
  (interactive)
  (org-workflow-projects-sync)
  (org-workflow-project-view-refresh))

(defun org-workflow-project-view-set-goal ()
  "Assign the selected project to a long-term goal."
  (interactive)
  (org-workflow-projects-set-goal
   (org-workflow-projects-marker (org-workflow-project-view--at-point))
   (org-workflow-projects-read-goal))
  (org-workflow-project-view-refresh))

(defun org-workflow-project-view-register ()
  "Visit an Agenda source to register a goal or project heading."
  (interactive)
  (find-file (completing-read "项目源文件：" (org-agenda-files t) nil t))
  (message "选择标题后 M-x org-workflow-projects-register 登记目标或项目"))

(defvar org-workflow-project-view-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (define-key map (kbd "RET") #'org-workflow-project-view-visit)
    (define-key map (kbd "TAB") #'org-workflow-project-view-toggle)
    (define-key map (kbd "R") #'org-workflow-project-view-sync)
    (define-key map (kbd "g") #'org-workflow-project-view-refresh)
    (define-key map (kbd "t") #'org-workflow-project-view-state)
    (define-key map (kbd "s") #'org-workflow-project-view-schedule)
    (define-key map (kbd "G") #'org-workflow-project-view-set-goal)
    (define-key map (kbd "n") #'org-workflow-project-view-register)
    (define-key map (kbd "D") #'org-workflow-project-view-toggle-done)
    (define-key map (kbd "a") #'org-workflow-open-agenda)
    (define-key map (kbd "j") #'next-line)
    (define-key map (kbd "k") #'previous-line)
    map))

(define-derived-mode org-workflow-project-view-mode special-mode "Workflow Projects"
  "Plan projects using their original Org sources.
RET visits source; t changes state; s schedules start; TAB expands context."
  (setq-local truncate-lines nil
              header-line-format " RET 打开  TAB 展开  t 状态／暂停目标  s 开始日期  G 归属  a 今日  g 刷新  q 返回")
  (setq-local revert-buffer-function (lambda (&rest _) (org-workflow-project-view-refresh))))

;;;###autoload
(defun org-workflow-project-view ()
  "Open the read-only learning project workbench."
  (interactive)
  (pop-to-buffer "*Workflow Projects*")
  (unless (derived-mode-p 'org-workflow-project-view-mode) (org-workflow-project-view-mode))
  (org-workflow-project-view-refresh))

(with-eval-after-load 'evil
  (evil-set-initial-state 'org-workflow-project-view-mode 'emacs))
(provide 'org-workflow-project-view)
;;; org-workflow-project-view.el ends here
