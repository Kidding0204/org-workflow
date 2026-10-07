;;; org-workflow-history-panel.el --- org-workflow-history-panel Workflow component -*- lexical-binding: t; -*-
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
;;; org-workflow-history-panel.el --- Native read-only history -*- lexical-binding: t; -*-
(require 'vui)

(require 'org-workflow-history)

(require 'org-workflow-history-view)

(require 'org-workflow-history-chart)

(defface org-workflow-history-panel-title '((t :inherit default :height 1.2 :weight semibold)) "History title." :group 'org)

(defface org-workflow-history-panel-metric '((t :inherit default :height 1.2 :weight semibold)) "Summary values." :group 'org)

(defface org-workflow-history-panel-task '((t :inherit default :weight semibold)) "Task titles." :group 'org)

(defface org-workflow-history-panel-heading '((t :inherit default :height 1.1 :weight semibold)) "History heading." :group 'org)

(defface org-workflow-history-panel-muted '((t :inherit shadow :height 1.0 :weight normal)) "History metadata." :group 'org)

(defface org-workflow-history-panel-action '((t :inherit link :height 1.0 :weight normal)) "History action." :group 'org)

(defface org-workflow-history-panel-warning '((t :inherit warning :height 1.0 :weight normal)) "History stale status." :group 'org)

(defface org-workflow-history-panel-error '((t :inherit error :height 1.0 :weight normal)) "History read error." :group 'org)

(defvar-local org-workflow-history-workbench--state nil)

(defvar-local org-workflow-history-panel--model nil "Complete presentation snapshot.")

(defvar-local org-workflow-history-panel--style nil "Last rendered window and theme geometry.")

(defvar-local org-workflow-history-panel--adapting nil)

(defvar-local org-workflow-history-panel--reading nil "Prevent refresh reentry.")

(define-derived-mode org-workflow-history-panel-mode vui-mode "Workflow History"
  "Browse settled Workflow facts."
  (setq-local vui-width-mode 'char)
  (setq-local line-spacing 0.1)
  (setq-local truncate-lines nil)
  ;; Bind only this panel's controls ahead of Evil/collection state maps.
  (when (fboundp 'evil-define-key*)
    (evil-define-key* '(normal motion) org-workflow-history-panel-mode-map
      (kbd "TAB") #'vui-forward (kbd "<backtab>") #'vui-backward
      (kbd "RET") #'vui-activate
      (kbd "g") #'org-workflow-history-panel-refresh
      (kbd "q") #'org-workflow-history-panel-close
      (kbd "d") #'org-workflow-history-panel-select-date
      (kbd "n") #'org-workflow-history-panel-next-date
      (kbd "p") #'org-workflow-history-panel-previous-date)
    ;; The current Evil collection's inherited vui motion map owns a g prefix.
    ;; A buffer-local binding precedes it without changing shared package maps.
    (evil-local-set-key 'motion (kbd "g") #'org-workflow-history-panel-refresh)
    (evil-normalize-keymaps)))

(define-key org-workflow-history-panel-mode-map (kbd "g") #'org-workflow-history-panel-refresh)

(define-key org-workflow-history-panel-mode-map (kbd "q") #'org-workflow-history-panel-close)

(define-key org-workflow-history-panel-mode-map (kbd "d") #'org-workflow-history-panel-select-date)

(define-key org-workflow-history-panel-mode-map (kbd "n") #'org-workflow-history-panel-next-date)

(define-key org-workflow-history-panel-mode-map (kbd "p") #'org-workflow-history-panel-previous-date)

(define-key org-workflow-history-panel-mode-map (kbd "RET") #'vui-activate)

(defun org-workflow-history-panel-next-date (&optional backward)
  "Select the next cached date, or previous when BACKWARD is non-nil."
  (interactive)
  (let* ((days (plist-get (plist-get org-workflow-history-panel--model :payload) :days))
         (index (cl-position (plist-get org-workflow-history-panel--model :selected-date) days
                             :key (lambda (day) (plist-get day :date)) :test #'equal)))
    (when index
      (let ((next (+ index (if backward -1 1))))
        (when (and (>= next 0) (< next (length days)))
          (org-workflow-history-panel-select-date (plist-get (aref days next) :date)))))))

(defun org-workflow-history-panel-previous-date ()
  "Select the previous cached day."
  (interactive)
  (org-workflow-history-panel-next-date t))

(defun org-workflow-history-panel--adapt (&optional _window)
  "Redraw cached presentation after geometry, text size or theme changes."
  (when (and vui--root-instance (not org-workflow-history-panel--adapting)
             (display-graphic-p))
    (let ((style (org-workflow-history-chart-style)))
      (unless (equal style org-workflow-history-panel--style)
        (let ((org-workflow-history-panel--adapting t))
          (org-workflow-history-panel--publish org-workflow-history-panel--model)
          (vui-flush-sync))))))

(defun org-workflow-history-panel--theme-changed (&rest _)
  "Redraw the visible history panel after a theme change."
  (when-let* ((buffer (get-buffer "*Workflow History*")))
    (with-current-buffer buffer
      (when-let* ((window (get-buffer-window buffer t)))
        (with-selected-window window (org-workflow-history-panel--adapt))))))

(defun org-workflow-history-panel--deactivate ()
  "Remove only this panel's presentation observers; no recurring timers exist."
  (remove-hook 'enable-theme-functions #'org-workflow-history-panel--theme-changed)
  (remove-hook 'disable-theme-functions #'org-workflow-history-panel--theme-changed)
  (remove-hook 'window-size-change-functions #'org-workflow-history-panel--adapt t)
  (remove-hook 'text-scale-mode-hook #'org-workflow-history-panel--adapt t)
  (setq org-workflow-history-panel--style nil))

(defun org-workflow-history-panel--activate ()
  "Install theme, geometry and text-scale observers for this panel."
  (org-workflow--add-hook 'window-size-change-functions #'org-workflow-history-panel--adapt nil t)
  (org-workflow--add-hook 'text-scale-mode-hook #'org-workflow-history-panel--adapt nil t)
  (org-workflow--add-hook 'kill-buffer-hook #'org-workflow-history-panel--deactivate nil t)
  (org-workflow--add-hook 'enable-theme-functions #'org-workflow-history-panel--theme-changed)
  (org-workflow--add-hook 'disable-theme-functions #'org-workflow-history-panel--theme-changed))

(defun org-workflow-history-panel--text (text &rest props)
  "Render TEXT as inert characters with only panel-owned PROPS.
Keep text properties on the original history payload untouched."
  (apply #'vui-text (substring-no-properties text) props))

(defun org-workflow-history-panel--row-text (text &optional face)
  "Render TEXT with FACE and indent wrapped continuations.
FACE defaults to the default face."
  (org-workflow-history-panel--text text 'wrap-prefix "  " :face (or face 'default)))

(defun org-workflow-history-panel--heading (text)
  "Render TEXT as a history section heading."
  (org-workflow-history-panel--text text :face 'org-workflow-history-panel-heading))

(defun org-workflow-history-panel--tasks (day field title empty &optional minimum)
  "Render DAY's FIELD task rows under TITLE in source order.
Show EMPTY when no tasks exist, and fulfillment when MINIMUM is non-nil."
  (vui-vstack
   (org-workflow-history-panel--heading title)
   (cond ((not (plist-member day field)) (org-workflow-history-panel--text "习惯任务：未知（旧记录未追踪）"))
         ((= 0 (length (plist-get day field))) (org-workflow-history-panel--text empty :face 'org-workflow-history-panel-muted))
         (t (vui-list
             (cl-loop for row across (plist-get day field) for index from 0
                      collect (cons (format "%s/%s/%d" (plist-get day :date) field index) row))
             (lambda (entry)
               (let ((row (cdr entry)))
                 (vui-vstack
                  (org-workflow-history-panel--row-text (plist-get row :task) 'org-workflow-history-panel-task)
                  (org-workflow-history-panel--row-text
                   (concat (format "任务状态：%s；投入：%d 分钟"
                                   (cdr (assoc (plist-get row :outcome) org-workflow-history-view--outcomes))
                                   (plist-get row :focusMinutes))
                           (when minimum
                             (concat " · " (cond ((not (plist-member row :satisfied)) "承诺履行：未知（旧记录未追踪）")
                                                 ((eq t (plist-get row :satisfied)) "承诺履行：已满足")
                                                 (t "承诺履行：未满足")))))
                   'org-workflow-history-panel-muted)))) #'car :indent 2)))))

(defun org-workflow-history-panel--leaves (day)
  "Render DAY's leave explanations and their associated tasks."
  (vui-vstack
   (org-workflow-history-panel--heading "请假说明")
   (cond ((not (plist-member day :leaveRecords)) (org-workflow-history-panel--text "未提供请假记录" :face 'org-workflow-history-panel-muted))
         ((= 0 (length (plist-get day :leaveRecords))) (org-workflow-history-panel--text "无请假记录" :face 'org-workflow-history-panel-muted))
         (t (vui-list
             (cl-loop for row across (plist-get day :leaveRecords) for index from 0
                      collect (cons (format "%s/leave/%d" (plist-get day :date) index) row))
             (lambda (entry)
               (let ((row (cdr entry)))
                 (vui-vstack
                  (org-workflow-history-panel--row-text (concat "请假 · " (mapconcat (lambda (slot)
                                                        (cdr (assoc slot org-workflow-history-view--slots)))
                                                      (append (plist-get row :slots) nil) "、")))
                  (org-workflow-history-panel--row-text (concat "理由：" (plist-get row :reason)))
                  (apply #'vui-vstack
                         (mapcar (lambda (task)
                                   (org-workflow-history-panel--row-text (format "关联任务：%s（%s）" (plist-get task :task)
                                                     (if (eq :null (plist-get task :slot)) "时段未指定"
                                                       (cdr (assoc (plist-get task :slot) org-workflow-history-view--slots))))))
                                 (append (plist-get row :tasks) nil)))))) #'car :indent 2)))))

(defun org-workflow-history-panel--habit-metric (day field label unit)
  "Format DAY's FIELD with LABEL and UNIT, distinguishing unknown values."
  (if (plist-member day field) (format "%s：%d %s" label (plist-get day field) unit)
    (concat label "：未知（旧记录未追踪）")))

(defun org-workflow-history-panel--detail (day)
  "Render the selected DAY's facts, distinguishing absent and missing records."
  (when day
    (vui-vstack
     :spacing 1
     (org-workflow-history-panel--heading (concat "日详情 · " (plist-get day :date)))
     (if (equal (plist-get day :recordState) "missing")
         (vui-vstack (org-workflow-history-panel--text "记录缺失（missing）")
                     (org-workflow-history-panel--text "此日期没有已结算历史记录，投入与任务状态未知。下方请假说明如有记录仍会显示。"))
       (vui-vstack
        :spacing 1
        (vui-vstack
         (org-workflow-history-panel--text (format "承诺状态：%s（%s）"
                          (cdr (assoc (plist-get day :commitment) org-workflow-history-view--commitments))
                          (plist-get day :commitment)))
        (org-workflow-history-panel--text (concat "结算时间：" (plist-get day :finalizedAt)) :face 'org-workflow-history-panel-muted)
        (org-workflow-history-panel--text (format "总投入：%d 分钟；承诺投入：%d 分钟；可选投入：%d 分钟；可选完成：%d 项"
                          (plist-get day :focusTotalMinutes) (plist-get day :commitmentFocusMinutes)
                          (plist-get day :optionalFocusMinutes) (plist-get day :optionalCompleted)))
        (org-workflow-history-panel--text (concat (org-workflow-history-panel--habit-metric day :habitFocusMinutes "习惯投入" "分钟")
                          "；" (org-workflow-history-panel--habit-metric day :habitCompleted "习惯完成" "项"))))
        (org-workflow-history-panel--tasks day :minimumTasks "承诺任务" "无承诺任务" t)
        (org-workflow-history-panel--tasks day :optionalTasks "可选任务" "无可选任务")
        (org-workflow-history-panel--tasks day :habitTasks "习惯任务" "无习惯任务")))
     (org-workflow-history-panel--leaves day))))

(defun org-workflow-history-panel--wide-p ()
  "Use the window showing this buffer."
  (let ((window (get-buffer-window (current-buffer) t)))
    (and window (>= (window-body-width window) 80))))

(defun org-workflow-history-panel--charts (model)
  "Render MODEL's cached charts with shared selection and no provider reads."
  (when (> (length (plist-get (plist-get model :payload) :days)) 0)
    (if (not (and (display-graphic-p) (image-type-available-p 'svg)))
        (org-workflow-history-panel--text "图表需要支持 SVG 的图形 Emacs；仍可使用日期控件查看详情。")
      (let* ((style (org-workflow-history-chart-style))
             (charts (org-workflow-history-chart-build (plist-get model :payload) (plist-get model :selected-date) style)))
        (cl-labels ((images (entries)
                      (apply #'vui-vstack
                             (mapcar (lambda (chart)
                                       (let ((image (org-workflow-history-chart-image chart #'org-workflow-history-panel-select-date)))
                                         (vui-vstack
                                          (when (> (length entries) 1)
                                            (org-workflow-history-panel--text (format "%s — %s" (plist-get chart :from) (plist-get chart :to))
                                                                             :face 'org-workflow-history-panel-muted))
                                          (vui-text " " 'display (car image) 'keymap (cdr image)
                                                    'org-workflow-history-chart (plist-get chart :kind))))) entries))))
          (vui-vstack :spacing 1
           (vui-vstack
            (org-workflow-history-panel--heading "投入热力图")
           (org-workflow-history-panel--text "分钟 / 日 · × 缺失 · 行 1–7：周一至周日" :face 'org-workflow-history-panel-muted)
           (apply #'vui-hstack :spacing 1
                  (cl-loop for color in (plist-get style :levels)
                           for label in '("0" "1–24" "25–49" "50–89" "90+")
                           for level from 0
                           collect (vui-text (concat " " label " ") :face (list :background color :foreground (plist-get style (if (>= level 3) :bg :fg)))))))
           (images (plist-get charts :heatmaps))
           (vui-vstack
            (org-workflow-history-panel--heading "每日投入趋势 · 分钟")
           (apply #'vui-hstack :spacing 2
                  (cl-loop for color in (plist-get style :series)
                           for label in '("━ 承诺" "┄ 可选" "┈ 习惯")
                           collect (org-workflow-history-panel--text label :face (list :foreground color))))
           (org-workflow-history-panel--text "断线表示未知 · 底部 ×：习惯未知 · 点击日期查看详情" :face 'org-workflow-history-panel-muted))
           (images (plist-get charts :trends))))))))

(vui-defcomponent org-workflow-history-panel--root (model)
  :render
  (let* ((payload (plist-get model :payload)) (coverage (plist-get payload :coverage))
         (summary (plist-get model :summary)) (state (plist-get model :state)) (error-text (plist-get model :error)))
    (vui-vstack
     :spacing 1
     (org-workflow-history-panel--text "Workflow 历史" :face 'org-workflow-history-panel-title)
     (cond ((eq state 'loading) (org-workflow-history-panel--text (if payload "正在刷新历史…" "正在读取历史…")))
           ((eq state 'stale)
            (org-workflow-history-panel--text (format "未更新：本次读取失败，保留上次成功读取的历史（%s）。原因：%s。使用“刷新历史”重试。"
                              (plist-get model :last-success) error-text) :face 'org-workflow-history-panel-warning))
           ((eq state 'error)
            (org-workflow-history-panel--text (if (string-prefix-p "历史数据不合法：" error-text) error-text
                        (format "无法读取历史：%s。使用“刷新历史”重试。" error-text)) :face 'org-workflow-history-panel-error)))
     (when payload
       (vui-vstack
        (org-workflow-history-panel--text
         (if (eq coverage :null) "历史范围：暂无"
           (format "%s — %s" (plist-get coverage :trackingStarted) (plist-get coverage :eligibleThrough)))
         :face 'org-workflow-history-panel-muted)
        (org-workflow-history-panel--text (concat "更新于 " (plist-get model :last-success))
                                          :face 'org-workflow-history-panel-muted)))
     (when payload
       (if (eq coverage :null) (org-workflow-history-panel--text "总投入：暂无统计；连续达标：暂无统计")
         (vui-vstack
          (let ((total (vui-hstack :spacing 1
                        (org-workflow-history-panel--text "累计投入" :face 'org-workflow-history-panel-muted)
                        (org-workflow-history-panel--text (format "%d 分钟" (plist-get summary :total)) :face 'org-workflow-history-panel-metric)))
                (streak (vui-hstack :spacing 1
                         (org-workflow-history-panel--text "连续达标" :face 'org-workflow-history-panel-muted)
                         (org-workflow-history-panel--text (format "%d 天" (plist-get summary :streak)) :face 'org-workflow-history-panel-metric))))
            (if (org-workflow-history-panel--wide-p)
                (vui-hstack :spacing 4 total streak)
              (vui-vstack total streak)))
          (org-workflow-history-panel--text
           (format "已结算 %d 天 · 缺失 %d 天" (plist-get summary :finalized) (plist-get summary :missing))
           :face 'org-workflow-history-panel-muted))))
     (apply (if (org-workflow-history-panel--wide-p) #'vui-hstack #'vui-vstack)
            :spacing (if (org-workflow-history-panel--wide-p) 2 0)
            (delq nil (list
                       (when (and payload (not (eq coverage :null)))
                         (vui-select :key 'date :value (plist-get model :selected-date)
                                      :options (org-workflow-history-view-date-options payload)
                                      :prompt "选择历史日期：" :on-change #'org-workflow-history-panel-select-date))
                       (vui-button "刷新历史" :key 'refresh :face 'org-workflow-history-panel-action
                                   :on-click #'org-workflow-history-panel-refresh)
                       (vui-button "关闭面板" :key 'close :face 'default :on-click #'org-workflow-history-panel-close))))
     (when (plist-get model :notice) (org-workflow-history-panel--text (plist-get model :notice)))
     (when (eq coverage :null)
       (vui-vstack (org-workflow-history-panel--heading "暂无历史数据")
                   (org-workflow-history-panel--text "当前历史后端尚无可浏览的日期范围。稍后使用“刷新历史”重新读取。")))
     (org-workflow-history-panel--charts model)
     (org-workflow-history-panel--detail (plist-get model :detail))
     (org-workflow-history-panel--text "TAB / S-TAB 切换控件，RET 激活；d 选择日期，n / p 后一天 / 前一天；g 刷新历史，q 关闭面板。" :face 'org-workflow-history-panel-muted))))

(defun org-workflow-history-panel--publish (model)
  "Publish the sole complete MODEL through the external vui API."
  (if org-workflow-history-workbench--state
      (org-workflow-history-workbench--publish model)
    (setq org-workflow-history-panel--model model
        org-workflow-history-panel--style (when (display-graphic-p) (org-workflow-history-chart-style)))
  (if vui--root-instance (vui-update vui--root-instance (list :model model))
    (vui-mount (vui-component 'org-workflow-history-panel--root :model model) (buffer-name)))))

(defun org-workflow-history-panel--error-text (err)
  "Return readable safe text for ERR, preserving its characters and line breaks."
  (substring-no-properties
   (if (eq (car err) 'org-workflow-history-view-invalid)
       (cadr err) (error-message-string err))))

(defun org-workflow-history-panel-refresh (&optional now)
  "Read history at NOW once, retaining valid cached facts on failure.
NOW defaults to the current time."
  (interactive)
  (unless (derived-mode-p 'org-workflow-history-panel-mode)
    (user-error "请先打开 Workflow 历史面板"))
  (unless org-workflow-history-panel--reading
    (let ((org-workflow-history-panel--reading t) (previous org-workflow-history-panel--model))
      (condition-case err
          (progn
            (org-workflow-history-panel--publish (org-workflow-history-view-transition previous 'loading))
            (org-workflow-history-panel--publish
             (org-workflow-history-view-transition
              previous 'success (org-workflow-history-view-validate (org-workflow-history-read now))
              (format-time-string "%Y-%m-%d %H:%M:%S"))))
        (quit
         ;; Finish presentation cleanup before preserving the caller's C-g.
         (let ((inhibit-quit t))
           (org-workflow-history-panel--publish
            (or previous (org-workflow-history-view-transition nil 'failure "读取已取消；可使用“刷新历史”重试"))))
         (signal (car err) (cdr err)))
        (error
         (org-workflow-history-panel--publish
          (org-workflow-history-view-transition previous 'failure (org-workflow-history-panel--error-text err))))))))

(defun org-workflow-history-panel-select-date (&optional date)
  "Select cached DATE; cancellation and invalid input preserve the snapshot."
  (interactive)
  (unless (derived-mode-p 'org-workflow-history-panel-mode)
    (user-error "请先打开 Workflow 历史面板"))
  (unless org-workflow-history-panel--reading
    (condition-case nil
        (let* ((options (org-workflow-history-view-date-options (plist-get org-workflow-history-panel--model :payload)))
               (chosen (or date (and options
                                     (car (rassoc (completing-read "选择历史日期：" (mapcar #'cdr options) nil t) options)))))
               (next (org-workflow-history-view-transition org-workflow-history-panel--model 'select chosen)))
          (unless (eq next org-workflow-history-panel--model) (org-workflow-history-panel--publish next)))
      (quit nil))))

(defun org-workflow-history-panel-close ()
  "Release the panel without saving historical data."
  (interactive)
  (unless (derived-mode-p 'org-workflow-history-panel-mode)
    (user-error "请先打开 Workflow 历史面板"))
  (org-workflow-history-panel--deactivate)
  ;; Teardown is presentation work, not an undoable user edit.
  (let ((buffer-undo-list t))
    (vui-unmount (current-buffer)))
  (quit-window))

;;;###autoload
(defun org-workflow-history-tracking (&optional now)
  "Open the original single-buffer heatmap, trends and daily details at NOW."
  (interactive)
  (let ((buffer (get-buffer-create "*Workflow History*")))
    (save-window-excursion
      (with-current-buffer buffer
        (unless (derived-mode-p 'org-workflow-history-panel-mode)
          ;; vui-mode initializes its parent map; isolate that library mutation.
          (let ((vui-mode-map (copy-keymap vui-mode-map)))
            (org-workflow-history-panel-mode)))
        (org-workflow-history-panel--activate)
        (org-workflow-history-panel-refresh now)))
    (display-buffer buffer)
    (with-current-buffer buffer (org-workflow-history-panel--adapt))
    buffer))

;;;###autoload
(defun org-workflow-history-panel (&optional now)
  "Open a graphical history workbench or terminal tracker at NOW.
NOW defaults to the current time."
  (interactive)
  (if (display-graphic-p)
      (progn (require 'org-workflow-history-workbench) (org-workflow-history-workbench now))
    (org-workflow-history-tracking now)))

(provide 'org-workflow-history-panel)
;;; org-workflow-history-panel.el ends here
