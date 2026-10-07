;;; org-workflow-agenda-console.el --- note-gtd-console Workflow component -*- lexical-binding: t; -*-
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
;;; org-workflow-agenda-console.el --- Persistent Workflow controls -*- lexical-binding: t; -*-
(require 'org-agenda)

(require 'transient)

(require 'org-workflow-agenda-plan-undo)

(require 'org-workflow-guidance)

(require 'org-workflow-panel)

(autoload 'org-workflow-habits-complete "org-workflow-habits" nil t)

(autoload 'org-workflow-habits-start "org-workflow-habits" nil t)

(autoload 'org-workflow-habits-create "org-workflow-habits" nil t)

(autoload 'org-workflow-habits-open "org-workflow-habits" nil t)

(autoload 'org-workflow-evening-stop-clock "org-workflow-evening" nil t)

(autoload 'org-workflow-week-ensure "org-workflow-weekly")

(defun org-workflow-agenda-create-task (title date period)
  "Create TITLE in DATE's weekly inbox, scheduled for PERIOD."
  (let ((file (org-workflow-week-ensure date)))
    (with-current-buffer (find-file-noselect file)
      (org-with-wide-buffer
       (goto-char (point-min))
       (unless (re-search-forward "^\\* 收集箱[ \t]*$" nil t)
         (user-error "周日志缺少收集箱标题"))
       (beginning-of-line)
       (org-end-of-subtree t t)
       (unless (bolp) (insert "\n"))
       (let ((stamp (format-time-string "%Y-%m-%d %a"
                                        (date-to-time (concat date " 12:00")))))
         (atomic-change-group
           (insert (format "** TODO [#%c] %s\nSCHEDULED: <%s>\n:PROPERTIES:\n:CAPTURED_ON: %s\n:END:\n"
                           period title stamp (org-workflow-target--today-string)))))
       (save-buffer)))))

(defun org-workflow-agenda-create-at-point ()
  "Create a task or habit in the Sprint group at point."
  (interactive)
  (unless (and (derived-mode-p 'org-agenda-mode) org-workflow-agenda--sprint-buffer-p)
    (user-error "请在 Sprint 的时段或习惯栏使用此命令"))
  (let* ((context (get-text-property (line-beginning-position)
                                     'org-workflow-agenda-create-context))
         (kind (if (consp context) (car context) context)))
    (unless (memq kind '(task habit))
      (user-error "请将光标放在上午、下午、晚上或习惯栏"))
    (let ((title (read-string (if (eq kind 'habit) "新习惯：" "新任务："))))
      (when (or (string-empty-p (string-trim title))
                (string-match-p "[\n\r]" title))
        (user-error "请输入单行标题"))
      (if (eq kind 'habit)
          (save-window-excursion (org-workflow-habits-create title))
        (let ((date (nth 1 context)) (period (nth 2 context)))
          (unless (and (stringp date) (memq period '(?A ?B ?C)))
            (user-error "当前行没有明确的日期与时段"))
          (org-workflow-agenda-create-task title date period)))
      (org-agenda-redo)
      (message "已新增%s：%s" (if (eq kind 'habit) "习惯" "任务") title))))

(defun org-workflow-agenda-console-toggle-day ()
  "Toggle the displayed and planning date without a Transient session."
  (interactive)
  (org-workflow-agenda-set-day (not (org-workflow-agenda--setting 'org-workflow-agenda-plan-tomorrow)))
  (message "%s" (org-workflow-agenda-plan-period-label)))

(defconst org-workflow-agenda-console-bindings
  '(("E" "明日开工提示" org-workflow-guidance-edit-tomorrow)
    ("N" "下次从这里开始" org-workflow-guidance-edit-resume)
    ("W" "访问／编辑周目标" org-workflow-guidance-open-goals)
    ("U" "撤销上次安排" org-workflow-agenda-undo-plan)
    ("u" "上午" org-workflow-agenda-plan-morning)
    ("i" "下午" org-workflow-agenda-plan-afternoon)
    ("o" "晚上" org-workflow-agenda-plan-evening)
    ("y" "切换今天／明天" org-workflow-agenda-console-toggle-day)
    ("R" "按标签推荐" org-workflow-agenda-plan-recommended)
    ("m" "延至明天" org-workflow-agenda-schedule-tomorrow)
    ("r" "退出安排" org-workflow-agenda-unschedule)
    ("p" "承诺／撤回" org-workflow-toggle-commitment)
    ("f" "@flow" org-workflow-agenda-add-flow-tag)
    ;; ("t" "@tiny" org-workflow-agenda-add-tiny-tag)
    ("d" "@deep" org-workflow-agenda-add-deep-tag)
    ("SPC" "标记／取消" org-agenda-bulk-toggle)
    ("M" "清除选择" org-agenda-bulk-unmark-all)
    ("K" "时段内上移" org-workflow-agenda-move-up)
    ("J" "时段内下移" org-workflow-agenda-move-down)
    ("h" "完成本次习惯" org-workflow-habits-complete)
    ("b" "习惯开始计时" org-workflow-habits-start)
    ("x" "习惯停止计时" org-workflow-evening-stop-clock)
    ("n" "新增习惯" org-workflow-habits-create)
    ("I" "在当前栏新增" org-workflow-agenda-create-at-point)
    ("C-c o i" "收集项归类" org-workflow-inbox-classify)
    ("G" "习惯文件" org-workflow-habits-open)
    ("a" "筛选与视图" org-workflow-agenda-view-menu)
    ("?" "按键提示" org-workflow-agenda-console-help)))

(defun org-workflow-agenda-console-help ()
  "Show a compact, contextual key reminder without taking over input."
  (interactive)
  (let* ((habit (when-let* ((marker (org-get-at-bol 'org-hd-marker)))
                  (org-with-point-at marker
                    (equal (org-entry-get nil "STYLE") "habit"))))
         (day (org-workflow-agenda-plan-period-label))
         (groups '(("规划提示" "E" "N" "W")
                   ("安排" "u" "i" "o" "y" "R" "m" "r" "U")
                   ("标签" "p" "f" "t" "d")
                   ("选择与顺序" "SPC" "M" "K" "J")
                   ("习惯" "h" "b" "x" "n" "G")
                   ("录入" "I")
                   ("视图与帮助" "a" "?")))
         (rows (mapcar (lambda (entry)
                         (list (car entry) (cadr entry)
                               (eq (key-binding (kbd (car entry))) (nth 2 entry))))
                       org-workflow-agenda-console-bindings)))
    (when habit
      (setq groups (cons (assoc "习惯" groups)
                         (delete (assoc "习惯" groups) groups))))
    (with-help-window "*Workflow 按键*"
      (princ (concat day "（y 切换）\n"
                     (if habit "当前：习惯，优先使用完成与计时操作。\n\n" "\n")))
      (dolist (group groups)
        (princ (propertize (car group) 'face 'bold))
        (princ "\n")
        (dolist (key (cdr group))
          (let ((row (assoc key rows)))
            (princ (format "  %-5s %s%s\n" key (cadr row)
                           (if (nth 2 row) "" "（当前被其他绑定覆盖）")))))
        (princ "\n"))
      (princ "导航\n  j / k  下一条／上一条\n  s      Flash 跳转\n  RET    访问条目\n\n详细绑定：C-h k 查询单键，C-h b 查看全部。\n"))))

(defvar-local org-workflow-agenda-console--base-map nil)

(defvar-local org-workflow-agenda-console--base-misc-info nil)

(defconst org-workflow-agenda-console--mode-line
  '(:eval (concat " 安排：" (if org-workflow-agenda-plan-tomorrow "明天" "今天"))))

(defun org-workflow-agenda-console-bindings-setup ()
  "Install Workflow bindings on an isolated map, restoring it outside Sprint."
  (if (bound-and-true-p org-workflow-agenda-sprint-view)
      (progn
        (unless org-workflow-agenda-console--base-map
          (setq org-workflow-agenda-console--base-map (current-local-map)
                org-workflow-agenda-console--base-misc-info mode-line-misc-info))
        (let ((map (copy-keymap org-workflow-agenda-console--base-map)))
          (dolist (entry org-workflow-agenda-console-bindings)
            (define-key map (kbd (car entry)) (nth 2 entry))
            (when (fboundp 'evil-define-key*)
              (evil-define-key* 'normal map (kbd (car entry)) (nth 2 entry))))
          (use-local-map map))
        (setq-local mode-line-misc-info
                    (append org-workflow-agenda-console--base-misc-info
                            (list org-workflow-agenda-console--mode-line))))
    (when org-workflow-agenda-console--base-map
      (use-local-map org-workflow-agenda-console--base-map)
      (setq-local mode-line-misc-info org-workflow-agenda-console--base-misc-info)
      (setq org-workflow-agenda-console--base-map nil)))
  (force-mode-line-update))

(defun org-workflow-agenda-console--task-only (original &rest args)
  "Call ORIGINAL with ARGS only when the selected entries are not habits."
  (dolist (marker (or org-agenda-bulk-marked-entries
                      (list (org-get-at-bol 'org-hd-marker))))
    (when (and (markerp marker) (marker-buffer marker)
               (org-with-point-at marker
                 (equal (org-entry-get nil "STYLE") "habit")))
      (user-error "习惯使用重复安排；请使用习惯操作")))
  (apply original args))

(defun org-workflow-agenda-console--enable ()
  "Install this component while Workflow is being enabled."
  (org-workflow--add-hook 'org-agenda-finalize-hook #'org-workflow-agenda-console-bindings-setup 95)
  (dolist (command '(org-workflow-agenda-plan-recommended org-workflow-agenda-plan-morning
                   org-workflow-agenda-plan-afternoon org-workflow-agenda-plan-evening
                   org-workflow-agenda-schedule-tomorrow org-workflow-agenda-unschedule
                   org-workflow-agenda-move-up org-workflow-agenda-move-down
                   org-workflow-toggle-commitment))
  (org-workflow--advice-add command :around #'org-workflow-agenda-console--task-only)))

(provide 'org-workflow-agenda-console)
;;; org-workflow-agenda-console.el ends here
