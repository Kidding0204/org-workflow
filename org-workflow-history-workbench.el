;;; org-workflow-history-workbench.el --- org-workflow-history-workbench Workflow component -*- lexical-binding: t; -*-
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
;;; org-workflow-history-workbench.el --- Tabbed native historical workbench -*- lexical-binding: t; -*-

(require 'vui)

(require 'org-workflow-history-panel)

(require 'tab-bar)

(defface org-workflow-history-workbench-title '((t :inherit default :height 1.3 :weight semibold)) "History title." :group 'org)

(defface org-workflow-history-workbench-heading '((t :inherit default :height 1.1 :weight semibold)) "Section heading." :group 'org)

(defface org-workflow-history-workbench-number '((t :inherit default :height 1.3 :weight semibold :underline nil)) "Overview number." :group 'org)

(defface org-workflow-history-workbench-task '((t :inherit default :weight semibold)) "Historical task title." :group 'org)

(defface org-workflow-history-workbench-value '((t :inherit default :weight semibold)) "Aligned minute values." :group 'org)

(defface org-workflow-history-workbench-muted '((t :inherit shadow)) "Secondary text." :group 'org)

(cl-defstruct org-workflow-history-workbench-state frame overview detail model style)

(defvar-local org-workflow-history-workbench--state nil)

(defun org-workflow-history-workbench--frame ()
  "Return the frame owning this history workbench."
  (org-workflow-history-workbench-state-frame org-workflow-history-workbench--state))

(defun org-workflow-history-workbench--selected ()
  "Return the selected date in this buffer's presentation model."
  (plist-get org-workflow-history-panel--model :selected-date))

(defun org-workflow-history-workbench--style ()
  "Use the current theme's surfaces, accent and selection colors."
  (let* ((style (org-workflow-history-chart-style))
         (frame (org-workflow-history-workbench--frame))
         (bg (plist-get style :bg)) (accent (face-foreground 'link frame t)))
    (setq style (plist-put style :levels
                           (mapcar (lambda (amount) (org-workflow-history-chart--blend accent bg amount))
                                   '(0.04 0.10 0.18 0.28 0.40))))
    (setq style (plist-put style :series
                           (mapcar (lambda (color) (org-workflow-history-chart--blend color bg 0.48))
                                   (plist-get style :series))))
    (setq style (plist-put style :surface (or (face-background 'fringe frame t) bg)))
    (setq style (plist-put style :selection (org-workflow-history-chart--blend accent bg 0.08)))
    (setq style (plist-put style :outline accent))
    (plist-put style :border (or (face-foreground 'vertical-border frame t) (plist-get style :muted)))))

(defun org-workflow-history-workbench--days ()
  "Return the cached historical day records as a list."
  (append (plist-get (plist-get org-workflow-history-panel--model :payload) :days) nil))

(defun org-workflow-history-workbench--month ()
  "Return cached days in the selected date's month."
  (let ((prefix (substring (org-workflow-history-workbench--selected) 0 7)))
    (cl-remove-if-not (lambda (day) (string-prefix-p prefix (plist-get day :date)))
                      (org-workflow-history-workbench--days))))

(defun org-workflow-history-workbench--month-target (&optional backward)
  "Return a covered date in the next month, or previous with BACKWARD.
Preserve the selected day of the month when possible."
  (when-let* ((selected (org-workflow-history-workbench--selected)))
    (let* ((month (substring selected 0 7))
           (months (delete-dups (mapcar (lambda (day) (substring (plist-get day :date) 0 7))
                                       (org-workflow-history-workbench--days))))
           (index (cl-position month months :test #'equal))
           (next (and index (+ index (if backward -1 1)))))
      (when (and next (>= next 0) (< next (length months)))
        (let* ((prefix (nth next months))
               (dates (cl-loop for day in (org-workflow-history-workbench--days)
                               for date = (plist-get day :date)
                               when (string-prefix-p prefix date) collect date))
               (wanted (concat prefix (substring selected 7))))
          (or (cl-find-if (lambda (date) (not (string< date wanted))) dates)
              (car (last dates))))))))

(defun org-workflow-history-workbench-next-month (&optional backward)
  "Select a cached date in the next month, or previous with BACKWARD."
  (interactive)
  (when-let* ((date (org-workflow-history-workbench--month-target backward)))
    (org-workflow-history-panel-select-date date)))

(defun org-workflow-history-workbench-previous-month ()
  "Select a date in the previous covered month."
  (interactive)
  (org-workflow-history-workbench-next-month t))

(defun org-workflow-history-workbench--text (text &optional face)
  "Render TEXT with FACE and an indented continuation prefix."
  (vui-text text :face (or face 'default) 'wrap-prefix "  "))

(defun org-workflow-history-workbench--heading (text)
  "Render TEXT as a workbench section heading."
  (org-workflow-history-workbench--text text 'org-workflow-history-workbench-heading))

(defun org-workflow-history-workbench--image (svg map)
  "Render SVG with date-selecting hit regions from MAP."
  (let ((image (org-workflow-history-chart-image (list :svg svg :map map)
                                                #'org-workflow-history-panel-select-date)))
    (vui-text " " 'display (car image) 'keymap (cdr image))))

(defun org-workflow-history-workbench--calendar ()
  "Draw a conventional month with roomy numbered day targets."
  (let* ((style (org-workflow-history-workbench--style))
         (width (min 650 (plist-get style :width)))
         (days (org-workflow-history-workbench--month))
         (first (concat (substring (org-workflow-history-workbench--selected) 0 7) "-01"))
         (offset (mod (1- (decoded-time-weekday (decode-time (date-to-time (concat first "T12:00:00Z")) t))) 7))
         (rows (1+ (/ (+ offset (1- (string-to-number (substring (plist-get (car (last days)) :date) 8)))) 7)))
         (cell (/ width 7.0)) (height (max 44 (min 65 (* cell 0.78))))
         (svg (svg-create width (+ 30 (* rows height)))) (map nil))
    (cl-loop for name in '("一" "二" "三" "四" "五" "六" "日") for col from 0 do
             (svg-text svg name :x (+ 9 (* col cell)) :y 18 :fill (plist-get style :muted)
                       :font-size 12 :font-family "sans-serif"))
    (cl-loop for day in days
             for date = (plist-get day :date)
             for n = (string-to-number (substring date 8))
             for first = (concat (substring date 0 7) "-01")
             for offset = (mod (1- (decoded-time-weekday (decode-time (date-to-time (concat first "T12:00:00Z")) t))) 7)
             for index = (+ offset (1- n)) for x = (* (mod index 7) cell) for y = (+ 28 (* (/ index 7) height))
             for level = (org-workflow-history-chart-level day)
             for selected = (equal (plist-get day :date) (org-workflow-history-workbench--selected)) do
             (svg-rectangle svg (+ x 2) (+ y 2) (- cell 6) (- height 6) :rx 5
                            :fill (if (eq level 'missing) (plist-get style :surface) (nth level (plist-get style :levels)))
                            :stroke (if selected (plist-get style :outline) (plist-get style :border))
                            :stroke-width (if selected 2.5 0.4))
             (let ((ink (plist-get style :fg)))
               (svg-text svg (number-to-string n) :x (+ x 10) :y (+ y 21)
                         :fill ink :font-size 15 :font-weight (if selected "bold" "normal") :font-family "sans-serif")
               (svg-text svg (if (eq level 'missing) "×" (format "%dm" (plist-get day :focusTotalMinutes)))
                         :x (+ x 10) :y (+ y (- height 13)) :fill ink :font-size 11 :font-family "sans-serif"))
             (push (org-workflow-history-chart--hotspot (plist-get day :date) (+ x 2) (+ y 2)
                                                        (- cell 6) (- height 6) (plist-get day :date)) map))
    (org-workflow-history-workbench--image svg (nreverse map))))

(defun org-workflow-history-workbench--week ()
  "Return cached days in the selected date's Monday-first week."
  (let* ((date (org-workflow-history-workbench--selected))
         (weekday (mod (1- (decoded-time-weekday (decode-time (date-to-time (concat date "T12:00:00Z")) t))) 7))
         (start (org-workflow-web-export--date-add-days date (- weekday)))
         (end (org-workflow-web-export--date-add-days start 6)))
    (cl-remove-if-not (lambda (day) (let ((d (plist-get day :date)))
                                     (and (not (string< d start)) (not (string> d end)))))
                      (org-workflow-history-workbench--days))))

(defun org-workflow-history-workbench--bars ()
  "Draw the selected week's daily category bars, with explicit unknowns."
  (let* ((style (org-workflow-history-workbench--style)) (width (min 650 (plist-get style :width)))
         (days (org-workflow-history-workbench--week))
         (svg (svg-create width (+ 10 (* 32 (length days)))))
         (plot (max 20 (- width 170)))
         (maximum (max 1 (apply #'max (mapcar (lambda (day) (apply #'+ (delq nil (org-workflow-history-chart-values day)))) days))))
         (map nil))
    (cl-loop for day in days for row from 0 for y = (+ 4 (* row 32))
             for date = (plist-get day :date) for values = (org-workflow-history-chart-values day) do
             (when (equal date (org-workflow-history-workbench--selected))
               (svg-rectangle svg 0 y width 29 :rx 4 :fill (plist-get style :selection)))
             (svg-text svg (substring date 5) :x 7 :y (+ y 20) :fill (plist-get style :fg) :font-size 12 :font-family "sans-serif")
             (let ((x 65))
               (cl-loop for value in values for color in (plist-get style :series) do
                        (when value
                          (let ((size (* plot (/ (float value) maximum))))
                            (svg-rectangle svg x (+ y 8) size 13 :fill color)
                            (setq x (+ x size))))))
             (svg-text svg (cond ((null values) "缺失")
                                ((null (nth 2 values)) (format "%d 分钟 ?" (plist-get day :focusTotalMinutes)))
                                (t (format "%d 分钟" (plist-get day :focusTotalMinutes))))
                       :x (+ 74 plot) :y (+ y 20) :fill (plist-get style :fg) :font-size 12 :font-family "sans-serif")
             (push (org-workflow-history-chart--hotspot date 0 y width 30 date) map))
    (org-workflow-history-workbench--image svg (nreverse map))))

(vui-defcomponent org-workflow-history-workbench--overview-root (model)
  :render
  (let* ((summary (plist-get model :summary))
         (coverage (plist-get (plist-get model :payload) :coverage))
         (selected (plist-get model :selected-date))
         (style (org-workflow-history-workbench--style)))
    (vui-vstack :spacing 1
     (org-workflow-history-workbench--text "投入回顾" 'org-workflow-history-workbench-title)
     (when (and coverage (not (eq coverage :null)))
       (org-workflow-history-workbench--text
        (format "%s — %s" (plist-get coverage :trackingStarted) (plist-get coverage :eligibleThrough))
        'org-workflow-history-workbench-muted))
     (when summary
       (vui-vstack
        (org-workflow-history-workbench--text
         (format "%d 分钟 · 连续达标 %d 天" (plist-get summary :total) (plist-get summary :streak))
         'org-workflow-history-workbench-number)
        (org-workflow-history-workbench--text
         (format "已结算 %d 天 · 缺失 %d 天 · 更新于 %s" (plist-get summary :finalized) (plist-get summary :missing)
                 (plist-get model :last-success)) 'org-workflow-history-workbench-muted)))
     (when (memq (plist-get model :state) '(stale error))
       (org-workflow-history-workbench--text
        (concat (if (eq (plist-get model :state) 'stale) "未更新，保留上次历史：" "无法读取历史：")
                (plist-get model :error)) 'warning))
     (when (eq (plist-get model :state) 'loading) (vui-text "正在读取历史…"))
     (when (plist-get model :notice) (vui-text (plist-get model :notice)))
     (vui-hstack :spacing 2
      (vui-button "选择日期" :on-click #'org-workflow-history-panel-select-date)
      (vui-button "日详情 →" :on-click #'org-workflow-history-workbench-show-detail)
      (vui-button "刷新历史" :on-click #'org-workflow-history-panel-refresh)
      (vui-button "关闭" :on-click #'org-workflow-history-workbench-close))
     (if (not selected) (vui-text "暂无可浏览的历史日期。")
       (vui-vstack :spacing 1
        (org-workflow-history-workbench--heading (concat (substring selected 0 7) " / 月历"))
        (vui-hstack :spacing 2
         (vui-button "← 上个月" :disabled (not (org-workflow-history-workbench--month-target t))
                     :on-click #'org-workflow-history-workbench-previous-month)
         (vui-button "下个月 →" :disabled (not (org-workflow-history-workbench--month-target))
                     :on-click #'org-workflow-history-workbench-next-month))
        (if (display-graphic-p (org-workflow-history-workbench--frame)) (org-workflow-history-workbench--calendar) (vui-text "使用 d 选择历史日期。"))
        (apply #'vui-hstack :spacing 1
               (cl-loop for color in (plist-get style :levels) for label in '("0" "1–24" "25–49" "50–89" "90+")
                        collect (vui-text (concat " " label " ") :face (list :background color :foreground (plist-get style :fg)))))
        (org-workflow-history-workbench--text "分钟 / 日 · × 记录缺失 · 描边为当前日期" 'org-workflow-history-workbench-muted)
        (org-workflow-history-workbench--heading "本周 / 每日投入构成")
        (apply #'vui-hstack :spacing 3
               (cl-loop for label in '("承诺" "可选" "习惯") for color in (plist-get style :series)
                        collect (vui-hstack :spacing 1 (vui-text "■" :face (list :foreground color)) (vui-text label))))
        (when (display-graphic-p (org-workflow-history-workbench--frame)) (org-workflow-history-workbench--bars))
        (when (cl-some (lambda (day) (and (equal (plist-get day :recordState) "finalized")
                                         (not (plist-member day :habitFocusMinutes))))
                       (org-workflow-history-workbench--week))
          (org-workflow-history-workbench--text "? 习惯未追踪；分类未知不补零。" 'org-workflow-history-workbench-muted))))
     (org-workflow-history-workbench--text "n / p 前后日期 · d 选日期 · g 刷新 · RET 日详情 · q 关闭" 'org-workflow-history-workbench-muted))))

(defun org-workflow-history-workbench--section (text &optional index)
  "Render a section header TEXT with a theme-derived accent.
Use series color INDEX when supplied, otherwise the outline color."
  (let* ((style (org-workflow-history-workbench--style))
         (color (if index (nth index (plist-get style :series))
                  (plist-get style :outline)))
         (surface (org-workflow-history-chart--blend color (plist-get style :bg) 0.12)))
    (vui-hstack :spacing 0
     (vui-text (concat "  " text "  ")
               :face (list :inherit 'org-workflow-history-workbench-heading
                           :foreground (plist-get style :fg) :background surface))
     (vui-text " " 'display '(space :align-to (- right 1))
               :face (list :background surface)))))

(defun org-workflow-history-workbench--badge (text face)
  "Render status TEXT using semantic foreground FACE."
  (vui-text text :face (list :inherit face :weight 'medium)))

(defun org-workflow-history-workbench--metrics (values)
  "Render category minute VALUES with explicit unknowns and natural alignment."
  (apply #'vui-vstack
         (cl-loop for label in '("承诺投入" "可选投入" "习惯投入")
                  for value in values collect
                  (vui-hstack :spacing 2
                   (vui-text label :face 'org-workflow-history-workbench-muted)
                   (vui-text (if value (format "%d 分钟" value) "未知")
                             :face 'org-workflow-history-workbench-value)))))

(defun org-workflow-history-workbench--task (title state minutes satisfaction)
  "Render TITLE with STATE, MINUTES and SATISFACTION in wrapping metadata."
  (vui-vstack
   (org-workflow-history-workbench--text title 'org-workflow-history-workbench-task)
   (vui-text
    (concat
     (propertize state 'face (if (equal state "已完成") 'success 'shadow))
     (propertize (format "  ·  %d 分钟" minutes)
                 'face 'org-workflow-history-workbench-muted)
     (unless (equal satisfaction "—")
       (concat (propertize "  ·  " 'face 'org-workflow-history-workbench-muted)
               (propertize satisfaction 'face
                           (if (equal satisfaction "承诺已满足") 'success 'warning)))))
    'wrap-prefix "  ")))

(defun org-workflow-history-workbench--tasks (day field title index &optional minimum)
  "Render DAY's FIELD tasks under TITLE with series accent INDEX.
Include fulfillment information when MINIMUM is non-nil."
  (vui-vstack :spacing 1
   (org-workflow-history-workbench--section
    (if (plist-member day field)
        (format "%s  ·  %d 项" title (length (plist-get day field))) title)
    index)
   (cond ((not (plist-member day field)) (vui-text "未知 · 旧记录未追踪" :face 'shadow))
         ((zerop (length (plist-get day field))) (vui-text "无记录" :face 'shadow))
         (t (apply #'vui-vstack :spacing 1
                   (cl-loop for row across (plist-get day field) collect
                            (org-workflow-history-workbench--task
                             (substring-no-properties (plist-get row :task))
                             (cdr (assoc (plist-get row :outcome) org-workflow-history-view--outcomes))
                             (plist-get row :focusMinutes)
                             (if minimum
                                 (cond ((not (plist-member row :satisfied)) "履行未知")
                                       ((eq t (plist-get row :satisfied)) "承诺已满足") (t "承诺未满足")) "—"))))))))

(vui-defcomponent org-workflow-history-workbench--detail-root (model)
  :render
  (let* ((day (plist-get model :detail)) (date (plist-get model :selected-date)))
    (vui-vstack :spacing 1
     (vui-vstack
      (org-workflow-history-workbench--text "日详情" 'org-workflow-history-workbench-muted)
      (org-workflow-history-workbench--text (or date "尚未选择日期") 'org-workflow-history-workbench-title)
      (vui-button "← 月历" :on-click #'org-workflow-history-workbench-show-overview))
     (cond ((not day) (vui-text "暂无选中日期。"))
           ((equal (plist-get day :recordState) "missing")
            (vui-vstack (org-workflow-history-workbench--heading "× 记录缺失") (vui-text "投入和任务状态未知。")))
           (t (vui-vstack :spacing 1
               (vui-vstack
                (org-workflow-history-workbench--text "当日投入" 'org-workflow-history-workbench-muted)
                (org-workflow-history-workbench--text (format "%d 分钟" (plist-get day :focusTotalMinutes)) 'org-workflow-history-workbench-number)
                (org-workflow-history-workbench--badge
                (concat "承诺" (cdr (assoc (plist-get day :commitment) org-workflow-history-view--commitments)))
                (pcase (plist-get day :commitment)
                  ("met" 'success) ("unmet" 'warning) (_ 'shadow))))
               (org-workflow-history-workbench--metrics (org-workflow-history-chart-values day))
               (org-workflow-history-workbench--text
                (concat (format "可选完成 %d 项 · " (plist-get day :optionalCompleted))
                        (org-workflow-history-panel--habit-metric day :habitCompleted "习惯完成" "项")) 'org-workflow-history-workbench-muted)
               (org-workflow-history-workbench--tasks day :minimumTasks "承诺任务" 0 t)
               (org-workflow-history-workbench--tasks day :optionalTasks "可选任务" 1)
               (org-workflow-history-workbench--tasks day :habitTasks "习惯" 2))))
     (when day
       (vui-vstack :spacing 1
        (vui-vstack (org-workflow-history-workbench--section "请假")
         (cl-letf (((symbol-function 'org-workflow-history-panel--heading) (lambda (&rest _) nil)))
           (org-workflow-history-panel--leaves day)))
        (when (plist-get day :finalizedAt)
          (vui-text
           (concat "结算于 " (replace-regexp-in-string "T" " " (plist-get day :finalizedAt)))
           :face 'org-workflow-history-workbench-muted)))))))

(define-derived-mode org-workflow-history-workbench-mode org-workflow-history-panel-mode "Workflow History"
  "Browse real history in a tab with an overview and daily details."
  (setq-local vui-width-mode 'pixel line-spacing 0.18
              left-margin-width 2 right-margin-width 2
              word-wrap t truncate-lines nil)
  ;; The frame's history tab already owns these two panes.
  (tab-line-mode -1)
  (setq-local tab-line-format nil))

(dolist (binding '(("q" . org-workflow-history-workbench-close)
                   ("RET" . org-workflow-history-workbench-activate)
                   ("b" . org-workflow-history-workbench-show-overview)))
  (define-key org-workflow-history-workbench-mode-map (kbd (car binding)) (cdr binding)))

(defun org-workflow-history-workbench--publish (model)
  "Publish MODEL to both workbench buffers and retain the rendered style."
  (let ((state org-workflow-history-workbench--state))
    (setf (org-workflow-history-workbench-state-model state) model)
    (with-selected-frame (org-workflow-history-workbench-state-frame state)
     (save-window-excursion
      (dolist (entry (list (cons (org-workflow-history-workbench-state-overview state) 'org-workflow-history-workbench--overview-root)
                          (cons (org-workflow-history-workbench-state-detail state) 'org-workflow-history-workbench--detail-root)))
        (with-current-buffer (car entry)
          (setq org-workflow-history-panel--model model)
          (if vui--root-instance (vui-update vui--root-instance (list :model model))
            (vui-mount (vui-component (cdr entry) :model model) (current-buffer)))
          (vui-flush-sync)))))
    (setf (org-workflow-history-workbench-state-style state)
          (with-current-buffer (org-workflow-history-workbench-state-overview state) (org-workflow-history-workbench--style)))))

(defun org-workflow-history-workbench-activate ()
  "Activate the current control or show the selected day's detail."
  (interactive)
  (unless (vui-activate)
    (org-workflow-history-workbench-show-detail)))

(defun org-workflow-history-workbench-show-detail ()
  "Select the workbench's daily detail pane."
  (interactive)
  (let* ((buffer (org-workflow-history-workbench-state-detail org-workflow-history-workbench--state))
         (window (get-buffer-window buffer (selected-frame))))
    (if window (select-window window) (switch-to-buffer buffer))))

(defun org-workflow-history-workbench-show-overview ()
  "Select the workbench's monthly overview pane."
  (interactive)
  (let* ((buffer (org-workflow-history-workbench-state-overview org-workflow-history-workbench--state))
         (window (get-buffer-window buffer (selected-frame))))
    (if window (select-window window) (switch-to-buffer buffer))))

(defun org-workflow-history-workbench--cleanup (state)
  "Kill buffers owned by STATE and remove unused presentation observers."
  (dolist (buffer (list (org-workflow-history-workbench-state-overview state) (org-workflow-history-workbench-state-detail state)))
    (when (buffer-live-p buffer) (kill-buffer buffer)))
  (unless (cl-some (lambda (buffer) (buffer-local-value 'org-workflow-history-workbench--state buffer)) (buffer-list))
    (remove-hook 'enable-theme-functions #'org-workflow-history-workbench--redraw)
    (remove-hook 'disable-theme-functions #'org-workflow-history-workbench--redraw)
    (remove-hook 'window-size-change-functions #'org-workflow-history-workbench--redraw)))

(defun org-workflow-history-workbench--tab-close (tab last-tab)
  "Clean up history state in TAB unless LAST-TAB is non-nil."
  (when-let* (((not last-tab)) (state (alist-get 'org-workflow-history-workbench tab)))
    (org-workflow-history-workbench--cleanup state)))

(defun org-workflow-history-workbench-close ()
  "Close the current workbench's tab and its presentation buffers."
  (interactive)
  (let* ((state org-workflow-history-workbench--state)
         (frame (org-workflow-history-workbench-state-frame state))
         (index (cl-position state (funcall tab-bar-tabs-function frame)
                             :key (lambda (tab) (alist-get 'org-workflow-history-workbench tab)))))
    (when index (with-selected-frame frame (tab-bar-close-tab (1+ index))))
    (org-workflow-history-workbench--cleanup state)))

(defvar org-workflow-history-workbench--redrawing nil)

(defun org-workflow-history-workbench--redraw (&rest _)
  "Adapt visible history workbenches to theme and frame geometry changes."
  (unless org-workflow-history-workbench--redrawing
    (let ((org-workflow-history-workbench--redrawing t))
      (dolist (frame (frame-list))
        (when-let* ((state (alist-get 'org-workflow-history-workbench (cdr (with-selected-frame frame (tab-bar--current-tab-find)))))
                    (overview (org-workflow-history-workbench-state-overview state))
                    (detail (org-workflow-history-workbench-state-detail state))
                    ((and (buffer-live-p overview) (buffer-live-p detail)))
                    (window (or (get-buffer-window overview frame) (get-buffer-window detail frame))))
          (with-selected-window window
            (let ((left (get-buffer-window overview frame)) (right (get-buffer-window detail frame)))
              (cond ((and (< (frame-width frame) 80) left right)
                     (delete-window right))
                    ((and (>= (frame-width frame) 80) (not (and left right)))
                     (switch-to-buffer overview)
                     (set-window-buffer (split-window-right (floor (* (window-total-width) 0.57))) detail))))
            (unless (equal (org-workflow-history-workbench--style) (org-workflow-history-workbench-state-style state))
              (org-workflow-history-workbench--publish (org-workflow-history-workbench-state-model state)))))))))

;;;###autoload
(defun org-workflow-history-workbench (&optional now)
  "Open history at NOW in a new tab, preserving the caller's windows.
NOW defaults to the current time."
  (interactive)
  (let* ((overview (generate-new-buffer "*Workflow 历史*"))
         (detail (generate-new-buffer "*Workflow 日详情*"))
         (state (make-org-workflow-history-workbench-state :frame (selected-frame) :overview overview :detail detail))
         (tab-bar-new-tab-choice "*scratch*"))
    (org-workflow--add-hook 'enable-theme-functions #'org-workflow-history-workbench--redraw)
    (org-workflow--add-hook 'disable-theme-functions #'org-workflow-history-workbench--redraw)
    (org-workflow--add-hook 'window-size-change-functions #'org-workflow-history-workbench--redraw)
    (tab-bar-new-tab)
    (tab-bar-rename-tab "Workflow 历史")
    (setf (alist-get 'org-workflow-history-workbench (cdr (tab-bar--current-tab-find))) state)
    (condition-case err
        (progn
          (delete-other-windows)
          (switch-to-buffer overview)
          (when (>= (window-total-width) 80)
            (set-window-buffer (split-window-right (floor (* (window-total-width) 0.57))) detail))
          (dolist (buffer (list overview detail))
            (with-current-buffer buffer
              (org-workflow-history-workbench-mode)
              (setq org-workflow-history-workbench--state state)
              (org-workflow--add-hook 'text-scale-mode-hook #'org-workflow-history-workbench--redraw nil t)
              (when (fboundp 'evil-define-key*)
                (evil-define-key* '(normal motion) org-workflow-history-workbench-mode-map
                  (kbd "q") #'org-workflow-history-workbench-close
                  (kbd "RET") #'org-workflow-history-workbench-activate
                  (kbd "b") #'org-workflow-history-workbench-show-overview))))
          (with-current-buffer overview (org-workflow-history-panel-refresh now))
          overview)
      (error (tab-bar-close-tab) (org-workflow-history-workbench--cleanup state) (signal (car err) (cdr err))))))

(defun org-workflow-history-workbench--enable ()
  "Install this component while Workflow is being enabled."
  (org-workflow--add-hook 'tab-bar-tab-pre-close-functions #'org-workflow-history-workbench--tab-close))

(provide 'org-workflow-history-workbench)
;;; org-workflow-history-workbench.el ends here
