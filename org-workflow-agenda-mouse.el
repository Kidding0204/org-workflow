;;; org-workflow-agenda-mouse.el --- note-gtd-mouse Workflow component -*- lexical-binding: t; -*-
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
;;; org-workflow-agenda-mouse.el --- Sprint mouse interactions -*- lexical-binding: t; -*-
;;; Commentary:
;; Task identity and selection stay in native Agenda markers and bulk marks.
;;; Code:
(require 'org-agenda)

(require 'org-workflow-agenda-layout)

(require 'org-workflow-agenda-console)

(defvar-local org-workflow-agenda-mouse--anchor nil)

(put 'org-workflow-agenda-mouse--anchor 'permanent-local t)

(defun org-workflow-agenda-mouse--row-kind ()
  "Classify the visible native task at point."
  (when-let* ((marker (org-get-at-bol 'org-hd-marker))
              ((marker-buffer marker))
              ((not (invisible-p (line-beginning-position)))))
    (org-with-point-at marker
		       (cond ((equal (org-entry-get nil "STYLE") "habit") 'habit)
			     ((org-entry-is-done-p) 'completed)
			     (t 'task)))))

(defun org-workflow-agenda-mouse--clear-anchors (&rest _)
  "Release this workbench's range anchors."
  (dolist (buffer (or (org-workflow-agenda--workbench-buffers) (list (current-buffer))))
    (with-current-buffer buffer
      (when (markerp org-workflow-agenda-mouse--anchor)
        (set-marker org-workflow-agenda-mouse--anchor nil))
      (setq org-workflow-agenda-mouse--anchor nil))))

(defun org-workflow-agenda-mouse--decorate ()
  "Use native marks with a full-row theme selection highlight."
  (dolist (overlay (overlays-in (point-min) (point-max)))
    (when (eq (overlay-get overlay 'type) 'org-marked-entry-overlay)
      (save-excursion
        (goto-char (overlay-start overlay))
        (move-overlay overlay (line-beginning-position) (line-end-position))
        (overlay-put overlay 'before-string nil)
        (overlay-put overlay 'display nil)
        (overlay-put overlay 'face 'region)))))

(defun org-workflow-agenda-mouse--mark (marker)
  "Mark visible MARKER without moving the user's point."
  (save-excursion
    (when (and (org-workflow-agenda--goto-task marker)
               (memq (org-workflow-agenda-mouse--row-kind) '(task habit)))
      (let ((mark-active nil) (inhibit-message t)) (org-agenda-bulk-mark 1)))))

(defun org-workflow-agenda-mouse--select (marker modifier)
  "Select MARKER using MODIFIER nil, control or shift."
  (dolist (buffer (org-workflow-agenda--workbench-buffers))
    (unless (eq buffer (current-buffer))
      (with-current-buffer buffer
        (when org-agenda-bulk-marked-entries (org-agenda-bulk-unmark-all))
        (org-workflow-agenda-mouse--clear-local-anchor))))
  (when (and (org-workflow-agenda--goto-task marker)
             (memq (org-workflow-agenda-mouse--row-kind) '(task habit)))
    (when (and (eq modifier 'control)
               (seq-some (lambda (selected)
                           (and (marker-buffer selected)
                                (org-with-point-at selected
						   (equal (org-entry-get nil "STYLE") "habit"))))
                         org-agenda-bulk-marked-entries))
      (org-agenda-bulk-unmark-all))
    (let* ((kind (org-workflow-agenda-mouse--row-kind))
           (end (line-beginning-position))
           (anchor (and (eq kind 'task) (eq modifier 'shift)
                        (markerp org-workflow-agenda-mouse--anchor)
                        (marker-buffer org-workflow-agenda-mouse--anchor)
                        (save-excursion
                          (when (and (org-workflow-agenda--goto-task org-workflow-agenda-mouse--anchor)
                                     (eq (org-workflow-agenda-mouse--row-kind) 'task))
                            (line-beginning-position))))))
      (cond
       (anchor
        (org-agenda-bulk-unmark-all)
        (save-excursion
          (goto-char (min anchor end))
          (while (<= (point) (max anchor end))
            (when (eq (org-workflow-agenda-mouse--row-kind) 'task)
              (org-workflow-agenda-mouse--mark (org-get-at-bol 'org-hd-marker)))
            (forward-line 1))))
       ((and (eq kind 'task) (eq modifier 'control))
        (save-excursion (org-agenda-bulk-toggle))
        (org-workflow-agenda-mouse--set-anchor marker))
       (t
        (org-agenda-bulk-unmark-all)
        (org-workflow-agenda-mouse--mark marker)
        (org-workflow-agenda-mouse--set-anchor marker)))
      (goto-char end)
      (org-workflow-agenda-mouse--decorate))))

(defun org-workflow-agenda-mouse--clear-local-anchor ()
  "Release the current pane's anchor."
  (when (markerp org-workflow-agenda-mouse--anchor) (set-marker org-workflow-agenda-mouse--anchor nil))
  (setq org-workflow-agenda-mouse--anchor nil))

(defun org-workflow-agenda-mouse--set-anchor (marker)
  "Remember MARKER independently of Agenda's reusable marker pool."
  (org-workflow-agenda-mouse--clear-local-anchor)
  (setq org-workflow-agenda-mouse--anchor (copy-marker marker)))

(defun org-workflow-agenda-mouse--position (event)
  "Select EVENT's Sprint window and return its buffer position."
  (let* ((pos (event-start event)) (window (posn-window pos)) (point (posn-point pos)))
    (when (and (window-live-p window) (integer-or-marker-p point)
               (buffer-local-value 'org-workflow-agenda-mouse-mode (window-buffer window)))
      (select-window window)
      (goto-char point)
      (setq-local org-agenda-type (org-get-at-bol 'org-agenda-type))
      point)))

(defun org-workflow-agenda-mouse-click (event)
  "Select the task at mouse EVENT or invoke its structural button."
  (interactive "e")
  (when (org-workflow-agenda-mouse--position event)
    (cond ((button-at (point)) (push-button (point)))
          ((org-get-at-bol 'org-hd-marker)
           (when (eq (org-workflow-agenda-mouse--row-kind) 'completed)
             (org-workflow-agenda--clear-selection))
           (org-workflow-agenda-mouse--select
            (org-get-at-bol 'org-hd-marker)
            (cond ((memq 'shift (event-modifiers event)) 'shift)
                  ((memq 'control (event-modifiers event)) 'control))))
          (t (org-workflow-agenda--clear-selection)))))

(defun org-workflow-agenda-mouse-open (&optional event)
  "Visit the task at EVENT while keeping the workbench intact.
When EVENT is nil, visit the task at point."
  (interactive (list (and (mouse-event-p last-input-event) last-input-event)))
  (when (or (not event) (org-workflow-agenda-mouse--position event))
    (when-let* ((marker (org-get-at-bol 'org-hd-marker))
		((marker-buffer marker)))
      (setq marker (copy-marker marker))
      (unwind-protect
          (if (and org-workflow-agenda--workbench
                   (org-workflow-agenda-workbench-tab-frame org-workflow-agenda--workbench))
              (let* ((token (gethash 'mouse-origin-tab
                                     (org-workflow-agenda-workbench-settings org-workflow-agenda--workbench)))
                     (tabs (tab-bar-tabs))
                     (index (and token (seq-position tabs token
                                                     (lambda (tab id)
                                                       (eq (alist-get 'org-workflow-agenda-origin tab) id))))))
		(if index (tab-bar-select-tab (1+ index)) (tab-bar-new-tab))
		(switch-to-buffer (marker-buffer marker))
		(widen) (goto-char marker) (org-fold-show-context 'agenda))
            (org-agenda-switch-to))
	(set-marker marker nil)))))

(defun org-workflow-agenda-mouse--remember-origin (original &rest args)
  "Remember the editing tab before calling ORIGINAL with ARGS."
  (let* ((tab (tab-bar--current-tab-find))
         (token (or (alist-get 'org-workflow-agenda-origin (cdr tab)) (gensym "sprint-origin-"))))
    (setf (alist-get 'org-workflow-agenda-origin (cdr tab)) token)
    (prog1 (apply original args)
      (when org-workflow-agenda--workbench
        (puthash 'mouse-origin-tab token
                 (org-workflow-agenda-workbench-settings org-workflow-agenda--workbench))))))

(defun org-workflow-agenda-mouse--menu ()
  "Build a native context menu for the row at point."
  (let* ((kind (org-workflow-agenda-mouse--row-kind))
         (context (get-text-property (point) 'org-workflow-agenda-create-context))
         (single (<= (length org-agenda-bulk-marked-entries) 1))
         (scheduled (when-let* ((marker (org-get-at-bol 'org-hd-marker)))
                      (org-with-point-at marker (org-entry-get nil "SCHEDULED"))))
         (map (make-sparse-keymap "Sprint")))
    (cl-labels ((item (key label command &optional enabled)
                  (define-key map (vector key)
			      `(menu-item ,label ,command :enable ,(if (eq enabled 'disabled) nil t)))))
	       (when kind (item 'open "访问源任务" 'org-workflow-agenda-mouse-open (unless single 'disabled)))
	       (pcase kind
		 ('task
		  (when (get-text-property (line-beginning-position) 'org-workflow-agenda-inbox-entry)
		    (item 'classify "归类收集项" 'org-workflow-inbox-classify (unless single 'disabled))
		    (item 'complete "完成收集项" 'org-workflow-inbox-state-done (unless single 'disabled)))
		  (dolist (row '((morning "安排至上午" org-workflow-agenda-plan-morning)
				 (afternoon "安排至下午" org-workflow-agenda-plan-afternoon)
				 (evening "安排至晚上" org-workflow-agenda-plan-evening)
				 (recommend "按标签推荐" org-workflow-agenda-plan-recommended)
				 (tomorrow "延至明天" org-workflow-agenda-schedule-tomorrow)
				 (unschedule "退出安排" org-workflow-agenda-unschedule)
				 (promise "承诺／撤回" org-workflow-agenda-mouse-toggle-commitment)
				 (tiny "@tiny" org-workflow-agenda-add-tiny-tag)
				 (flow "@flow" org-workflow-agenda-add-flow-tag)
				 (deep "@deep" org-workflow-agenda-add-deep-tag)))
		    (apply #'item row))
		  (item 'up "时段内上移" 'org-workflow-agenda-mouse-move-up
			(unless (and single scheduled (not org-agenda-tag-filter)) 'disabled))
		  (item 'down "时段内下移" 'org-workflow-agenda-mouse-move-down
			(unless (and single scheduled (not org-agenda-tag-filter)) 'disabled)))
		 ('habit
		  (item 'complete "完成本次习惯" 'org-workflow-habits-complete
			(when (org-with-point-at (org-get-at-bol 'org-hd-marker)
						 (or (org-entry-is-done-p)
						     (let ((habit (ignore-errors (org-habit-parse-todo))))
						       (and habit (memq (time-to-days (current-time))
									(org-habit-done-dates habit)))))) 'disabled))
		  (item 'start "开始计时" 'org-workflow-habits-start
			(when (org-with-point-at (org-get-at-bol 'org-hd-marker)
						 (or (org-entry-is-done-p) (org-clocking-p)
						     (and (fboundp 'org-workflow-focus-timer-active-p) (org-workflow-focus-timer-active-p)))) 'disabled))
		  (item 'stop "停止计时" 'org-workflow-evening-stop-clock
			(unless (org-workflow-clock--clock-matches-p (org-get-at-bol 'org-hd-marker)) 'disabled))
		  (item 'habit "新增习惯" 'org-workflow-habits-create)))
	       (when (and (not kind) context)
		 (item 'create (if (eq context 'habit) "新增习惯" "在该时段新增任务")
		       'org-workflow-agenda-create-at-point))
	       (unless (eq kind 'completed)
		 (when org-agenda-bulk-marked-entries (item 'clear "清除选择" 'org-workflow-agenda-mouse-clear))
		 (when org-workflow-agenda-last-plan (item 'undo "撤销上次安排" 'org-workflow-agenda-undo-plan))))
    map))

(defun org-workflow-agenda-mouse-clear ()
  "Clear mouse and keyboard task selections in this workbench."
  (interactive)
  (org-workflow-agenda--clear-selection))

(defun org-workflow-agenda-mouse-toggle-commitment ()
  "Toggle commitment on the selected tasks in one native planning transaction."
  (interactive)
  (org-workflow-agenda--apply-planning
   (lambda ()
     (org-with-point-at (org-get-at-bol 'org-hd-marker)
			(org-workflow-toggle-commitment)))))

(defun org-workflow-agenda-mouse-move-up ()
  "Move the singly selected task up using the existing period ordering."
  (interactive)
  (org-workflow-agenda--clear-selection)
  (org-workflow-agenda-move-up))

(defun org-workflow-agenda-mouse-move-down ()
  "Move the singly selected task down using the existing period ordering."
  (interactive)
  (org-workflow-agenda--clear-selection)
  (org-workflow-agenda-move-down))

(defun org-workflow-agenda-mouse-menu (event)
  "Show a context menu at EVENT without replacing an existing selection."
  (interactive "e")
  (when (org-workflow-agenda-mouse--position event)
    (unless (memq (org-workflow-agenda-mouse--row-kind) '(task habit))
      (org-workflow-agenda--clear-selection))
    (when-let* ((marker (org-get-at-bol 'org-hd-marker)))
      (unless (member marker org-agenda-bulk-marked-entries)
        (org-workflow-agenda-mouse--select marker nil)))
    (popup-menu (org-workflow-agenda-mouse--menu) event)))

(defun org-workflow-agenda-mouse--retain-selection (original redo buffer args)
  "Call ORIGINAL with REDO, BUFFER and ARGS, retaining visible selections."
  (with-current-buffer buffer
    (let ((saved (when org-workflow-agenda-mouse-mode
                   (mapcar #'copy-marker org-agenda-bulk-marked-entries))))
      (unwind-protect
          (prog1 (funcall original redo buffer args)
            (when org-workflow-agenda-mouse-mode
              (let ((inhibit-message t))
		(org-agenda-bulk-unmark-all)
		(dolist (marker saved)
                  (when (marker-buffer marker) (org-workflow-agenda-mouse--mark marker))))
              (org-workflow-agenda-mouse--decorate)))
	(dolist (marker saved) (set-marker marker nil))))))

(defun org-workflow-agenda-mouse--same-period-p (marker date priority)
  "Whether MARKER already belongs to DATE and PRIORITY."
  (org-with-point-at marker
		     (and (equal date (org-workflow-target--timestamp-date (org-entry-get nil "SCHEDULED")))
			  (eq priority (org-workflow-agenda--priority-letter
					(org-workflow--effective-priority-at-point))))))

(defun org-workflow-agenda-mouse--drop (markers date priority)
  "Arrange validated source MARKERS at DATE and PRIORITY as one operation."
  (unless (and markers (memq priority '(?A ?B ?C))
               (stringp date)
               (not (string< date (org-workflow-target--today-string)))
               (not (string< (org-workflow-agenda--date-offset 7) date)))
    (user-error "拖放目标不在可安排的日期或时段内"))
  (save-excursion
    (dolist (marker markers)
      (unless (and (markerp marker) (marker-buffer marker)
                   (org-workflow-agenda--goto-task marker)
                   (eq (org-workflow-agenda-mouse--row-kind) 'task)
                   (org-with-point-at marker
				      (and (org-at-heading-p) (org-workflow-target--task-leaf-p)
					   (not (org-workflow--held-p))
					   (not buffer-read-only)
					   (not (get-text-property (point) 'read-only)))))
        (user-error "拖动任务已变化、隐藏或只读，未修改安排"))))
  (if (seq-every-p (lambda (marker) (org-workflow-agenda-mouse--same-period-p marker date priority)) markers)
      (message "任务已在该时段，无需修改")
    (org-agenda-bulk-unmark-all)
    (dolist (marker markers) (org-workflow-agenda-mouse--mark marker))
    (org-workflow-agenda--goto-task (car markers))
    (org-workflow-agenda-plan-at date priority)
    (org-workflow-agenda-mouse--clear-anchors)))

(defun org-workflow-agenda-mouse--target (position state)
  "Resolve POSITION to a visible period in the originating workbench STATE."
  (let ((window (posn-window position)) (point (posn-point position)))
    (when (and (window-live-p window) (integer-or-marker-p point))
      (with-current-buffer (window-buffer window)
        (when (and org-workflow-agenda-mouse-mode (eq org-workflow-agenda--workbench state))
          (save-excursion
            (goto-char point)
            (when (not (invisible-p (point)))
              (let ((context (get-text-property (point) 'org-workflow-agenda-create-context)))
                (when (and (consp context) (eq (car context) 'task)
                           (memq (nth 2 context) '(?A ?B ?C)))
                  (list window (copy-sequence context)
                        (or (previous-single-property-change (1+ (point)) 'org-workflow-agenda-create-context)
                            (point-min))
                        (or (next-single-property-change (point) 'org-workflow-agenda-create-context)
                            (point-max))))))))))))

(defun org-workflow-agenda-mouse--scroll-target (position &optional state)
  "Scroll the Sprint window near POSITION's vertical edges.
When STATE is non-nil, scroll only the workbench matching it."
  (let ((window (posn-window position)) (xy (posn-x-y position)))
    (when (and (window-live-p window) (consp xy) (numberp (cdr xy))
               (buffer-local-value 'org-workflow-agenda-mouse-mode (window-buffer window))
               (memq (buffer-local-value 'org-workflow-agenda--pane-role (window-buffer window))
                     '(schedule combined))
               (or (not state)
                   (eq state (buffer-local-value 'org-workflow-agenda--workbench (window-buffer window)))))
      (with-selected-window window
        (cond ((< (cdr xy) 24) (ignore-errors (scroll-down 1)))
              ((> (cdr xy) (- (window-body-height window t) 24))
               (ignore-errors (scroll-up 1))))))))

(defun org-workflow-agenda-mouse--past-threshold-p (position window start)
  "Whether POSITION moved more than eight pixels from WINDOW and START."
  (when-let* ((xy (and position (posn-x-y position)))
              ((consp xy)) ((numberp (car xy))) ((numberp (cdr xy))))
    (or (not (eq (posn-window position) window))
        (> (max (abs (- (car xy) (car start)))
                (abs (- (cdr xy) (cdr start)))) 8))))

(defun org-workflow-agenda-mouse-down (event)
  "Distinguish clicks from an eight-pixel threshold drag starting at EVENT."
  (interactive "e")
  (when (org-workflow-agenda-mouse--position event)
    (let* ((source (current-buffer))
           (state org-workflow-agenda--workbench)
           (kind (org-workflow-agenda-mouse--row-kind))
           (marker (org-get-at-bol 'org-hd-marker))
           (modified (seq-intersection '(control shift) (event-modifiers event)))
           (button (button-at (point)))
           (start (posn-x-y (event-start event)))
           (origin-window (selected-window))
           (start-point (point))
           (double (memq 'double (event-modifiers event)))
           (markers (when (and (eq kind 'task) (not modified) (not double))
                      (mapcar #'copy-marker
                              (if (member marker org-agenda-bulk-marked-entries)
                                  org-agenda-bulk-marked-entries (list marker)))))
           (identities (mapcar (lambda (marker)
                                 (org-with-point-at marker
						    (cons marker (org-get-heading t t t t)))) markers))
           dragging target highlight last-position done)
      (unwind-protect
          (track-mouse
            (while (not done)
              (let* ((next (read-event nil nil (and dragging 0.08)))
                     (type (and next (event-basic-type next)))
                     (position (and (consp next) (event-end next))))
                (cond
                 ((or (equal next 27) (equal next 7)) (setq done 'cancel))
                 ((or (eq type 'mouse-movement) (null next))
                  (when position (setq last-position position))
                  (when (and markers position)
                    (when (org-workflow-agenda-mouse--past-threshold-p position origin-window start)
                      (unless dragging
                        (setq dragging t)
                        (with-current-buffer source
                          (unless (member marker org-agenda-bulk-marked-entries)
                            (org-workflow-agenda-mouse--select marker nil))))))
                  (when (and dragging last-position)
                    (org-workflow-agenda-mouse--scroll-target last-position state)
                    (let* ((window (posn-window last-position))
                           (xy (posn-x-y last-position))
                           (current (if (and (window-live-p window) (display-graphic-p))
                                        (posn-at-x-y (car xy) (cdr xy) window) last-position)))
                      (setq target (and current (org-workflow-agenda-mouse--target current state))))
                    (when highlight (delete-overlay highlight) (setq highlight nil))
                    (if (not target)
                        (message "当前无有效落点，安排未改变")
                      (setq highlight (make-overlay (nth 2 target) (nth 3 target)
                                                    (window-buffer (car target))))
                      (overlay-put highlight 'face 'highlight)
                      (overlay-put highlight 'window (car target))
                      (message "安排 %d 项 → %s %s" (length markers) (nth 1 (nth 1 target))
                               (cdr (assq (nth 2 (nth 1 target))
                                          '((?A . "上午") (?B . "下午") (?C . "晚上"))))))))
                 ((eq type 'mouse-1)
                  (setq done 'released)
                  (when (and markers (not dragging)
                             (org-workflow-agenda-mouse--past-threshold-p position origin-window start))
                    (setq dragging t)
                    (with-current-buffer source
                      (unless (member marker org-agenda-bulk-marked-entries)
                        (org-workflow-agenda-mouse--select marker nil))))
                  (when dragging
                    (setq target (and position (org-workflow-agenda-mouse--target position state)))))
                 (t
                  (setq done 'cancel)
                  (setq unread-command-events (append (list next) unread-command-events))))))
            (cond
             ((eq done 'cancel) (message "已取消拖放"))
             (dragging
              (if target
                  (with-current-buffer source
                    (dolist (identity identities)
                      (unless (and (marker-buffer (car identity))
                                   (org-with-point-at (car identity)
						      (equal (cdr identity) (org-get-heading t t t t))))
                        (user-error "拖动期间任务标题已变化，未修改安排")))
                    (pcase-let ((`(task ,date ,priority) (nth 1 target)))
                      (org-workflow-agenda-mouse--drop markers date priority)))
                (message "未落在有效时段，安排未改变")))
             (t
              (select-window origin-window) (goto-char start-point)
              (cond (button (push-button start-point))
                    (double (org-workflow-agenda-mouse-open))
                    (t (org-workflow-agenda-mouse-click
                        (list (event-convert-list
                               (append modified '(mouse-1))) (event-start event))))))))
        (when highlight (delete-overlay highlight))
        (dolist (marker markers) (set-marker marker nil))))))

(defvar org-workflow-agenda-mouse-mode-map
  (let ((map (make-sparse-keymap)))
    (dolist (key '("<mouse-1>" "C-<mouse-1>" "S-<mouse-1>"))
      (define-key map (kbd key) #'org-workflow-agenda-mouse-click))
    (define-key map [double-mouse-1] #'org-workflow-agenda-mouse-open)
    ;; The global context menu opens on press, before a release binding can run.
    (define-key map [down-mouse-3] #'org-workflow-agenda-mouse-menu)
    (define-key map [mouse-3] #'ignore)
    (dolist (key '("<down-mouse-1>" "C-<down-mouse-1>" "S-<down-mouse-1>"
                   "<double-down-mouse-1>"))
      (define-key map (kbd key) #'org-workflow-agenda-mouse-down))
    map))

(define-minor-mode org-workflow-agenda-mouse-mode
  "Desktop-style task selection in Sprint only."
  :lighter nil :keymap org-workflow-agenda-mouse-mode-map
  (unless org-workflow-agenda-mouse-mode (org-workflow-agenda-mouse--clear-local-anchor)))

(defun org-workflow-agenda-mouse--setup ()
  "Enable mouse bindings only on a finalized Sprint."
  (org-workflow-agenda-mouse-mode (if org-workflow-agenda--sprint-buffer-p 1 -1))
  (when (and org-workflow-agenda-mouse-mode (fboundp 'evil-make-overriding-map))
    (evil-make-overriding-map org-workflow-agenda-mouse-mode-map 'normal)
    (when (fboundp 'evil-normalize-keymaps) (evil-normalize-keymaps))))

(defun org-workflow-agenda-mouse--enable ()
  "Install this component while Workflow is being enabled."
  (org-workflow--advice-add 'org-workflow-agenda--clear-selection :after #'org-workflow-agenda-mouse--clear-anchors)
  (org-workflow--advice-add 'org-workflow-agenda--apply-planning :after #'org-workflow-agenda-mouse--clear-anchors)
  (org-workflow--advice-add 'org-workflow-agenda-open-workbench :around #'org-workflow-agenda-mouse--remember-origin)
  (org-workflow--advice-add 'org-workflow-agenda-mouse-toggle-commitment :around #'org-workflow-agenda-console--task-only)
  (org-workflow--advice-add 'org-workflow-agenda-mouse-toggle-commitment :around #'org-workflow-agenda-plan-undo--record
            '((depth . -100)))
  (org-workflow--advice-add 'org-workflow-agenda--redo-pane :around #'org-workflow-agenda-mouse--retain-selection)
  (org-workflow--advice-add 'org-workflow-agenda-plan-at :around #'org-workflow-agenda-console--task-only)
  (org-workflow--advice-add 'org-workflow-agenda-plan-at :around #'org-workflow-agenda-plan-undo--record '((depth . -100)))
  (org-workflow--add-hook 'org-agenda-finalize-hook #'org-workflow-agenda-mouse--setup 100))

(provide 'org-workflow-agenda-mouse)
;;; org-workflow-agenda-mouse.el ends here
