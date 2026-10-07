;;; org-workflow-history-chart.el --- org-workflow-history-chart Workflow component -*- lexical-binding: t; -*-
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
;;; org-workflow-history-chart.el --- Native historical SVG charts -*- lexical-binding: t; -*-
(require 'svg)

(require 'color)

(require 'face-remap)

(require 'org-workflow-history-view)

(defun org-workflow-history-chart-level (day)
  "Return DAY's focus bin, or `missing'; never interpret commitment as focus."
  (if (equal (plist-get day :recordState) "missing") 'missing
    (let ((minutes (plist-get day :focusTotalMinutes)))
      (cond ((= minutes 0) 0) ((< minutes 25) 1) ((< minutes 50) 2)
            ((< minutes 90) 3) (t 4)))))

(defun org-workflow-history-chart-values (day)
  "Return three supplied minute values for DAY, nil meaning unknown."
  (unless (equal (plist-get day :recordState) "missing")
    (mapcar (lambda (field) (and (plist-member day field) (plist-get day field)))
            '(:commitmentFocusMinutes :optionalFocusMinutes :habitFocusMinutes))))

(defun org-workflow-history-chart--blend (fg bg amount)
  "Blend color FG with BG using foreground weight AMOUNT."
  (apply #'color-rgb-to-hex
         (append (cl-mapcar (lambda (a b) (+ (* amount a) (* (- 1 amount) b)))
                           (color-name-to-rgb fg) (color-name-to-rgb bg)) '(2))))

(defun org-workflow-history-chart-style ()
  "Read current window, theme and local text scale without modifying them."
  (let* ((window (get-buffer-window (current-buffer) t))
         (frame (if window (window-frame window) (selected-frame)))
         (scale (expt text-scale-mode-step (if (boundp 'text-scale-mode-amount) text-scale-mode-amount 0)))
         (bg (face-background 'default frame t)) (fg (face-foreground 'default frame t))
         (accent (face-foreground 'link frame t)))
    (list :width (max 120 (min 1100 (- (if window (window-body-width window t) 640) 16)))
          :unit (max 16 (round (* 24 scale))) :font (max 11 (round (* 14 scale)))
          :bg bg :fg fg :muted (face-foreground 'shadow frame t)
          :levels (mapcar (lambda (a) (org-workflow-history-chart--blend accent bg a)) '(0.08 0.3 0.5 0.75 1.0))
          :series (list accent (face-foreground 'warning frame t)
                        (face-foreground 'font-lock-constant-face frame t)))))

(defun org-workflow-history-chart--label (svg text x y style &optional anchor)
  "Draw TEXT in SVG at X and Y using STYLE and optional text ANCHOR."
  (svg-text svg text :x x :y y :fill (plist-get style :fg)
            :font-size (plist-get style :font) :font-family "sans-serif"
            :text-anchor (or anchor "start")))

(defun org-workflow-history-chart--hotspot (date x y width height tip)
  "Return a DATE hit region at X and Y with WIDTH, HEIGHT and tooltip TIP."
  (list (cons 'rect (cons (cons (round x) (round y))
                         (cons (round (+ x width)) (round (+ y height)))))
        (intern (concat "workflow-history-day-" date)) (list 'help-echo tip)))

(defun org-workflow-history-chart--cross (svg x y size color)
  "Draw a missing-data cross in SVG at X and Y with SIZE and COLOR."
  (svg-line svg (+ x 3) (+ y 3) (+ x size -3) (+ y size -3) :stroke color :stroke-width 1)
  (svg-line svg (+ x 3) (+ y size -3) (+ x size -3) (+ y 3) :stroke color :stroke-width 1))

(defun org-workflow-history-chart--heatmap (days selected style)
  "Lay out DAYS as Monday-first heatmaps using STYLE, highlighting SELECTED."
  (let* ((unit (plist-get style :unit)) (left (* 2 unit)) (top (* 2 unit))
         (columns (max 1 (/ (- (plist-get style :width) left) unit)))
         (first (plist-get (car days) :date))
         (offset (mod (1- (decoded-time-weekday
                          (decode-time (date-to-time (concat first "T12:00:00Z")) t))) 7))
         (groups nil) (charts nil))
    (cl-loop for day in days for index from offset
             for group = (/ (/ index 7) columns) do
             (let ((entry (assq group groups)))
               (unless entry (setq entry (list group)) (push entry groups))
               (setcdr entry (cons (list day (% (/ index 7) columns) (% index 7)) (cdr entry)))))
    (dolist (group (nreverse groups))
      (let* ((cells (nreverse (cdr group)))
             (width (+ left (* unit (1+ (apply #'max (mapcar #'cadr cells))))))
             (height (+ top (* 7 unit) 8)) (svg (svg-create width height)) (map nil))
        (svg-rectangle svg 0 0 width height :fill (plist-get style :bg))
        (cl-loop for row from 0 below 7 do
                 (org-workflow-history-chart--label svg (number-to-string (1+ row))
                                                   4 (+ top (* row unit) (* 0.75 unit)) style))
        (let ((labelled-column nil))
          (dolist (cell cells)
            (pcase-let* ((`(,day ,column ,row) cell)
                         (date (substring-no-properties (plist-get day :date)))
                         (x (+ left (* column unit)))
                         (y (+ top (* row unit))) (size (- unit 5))
                         (level (org-workflow-history-chart-level day)))
              (when (and (or (= row 0) (null labelled-column))
                         (or (null labelled-column) (>= (- column labelled-column) 4)))
                (org-workflow-history-chart--label svg (substring date 5)
                                                   (max 4 (min x (- width (* (plist-get style :font) 3.4))))
                                                   (- top 10) style)
                (setq labelled-column column))
              (svg-rectangle svg x y size size :rx 2
                             :fill (if (eq level 'missing) (plist-get style :bg)
                                     (nth level (plist-get style :levels)))
                             :stroke (plist-get style :muted) :stroke-width 0.6)
              (when (eq level 'missing)
                (org-workflow-history-chart--cross svg x y size (plist-get style :muted)))
              (when (equal date selected)
                (svg-rectangle svg (- x 2) (- y 2) (+ size 4) (+ size 4) :rx 3
                               :fill "none" :stroke (plist-get style :fg) :stroke-width 2))
              (push (org-workflow-history-chart--hotspot
                     date x y size size
                     (format "%s · %s" date (if (eq level 'missing) "记录缺失；点击查看"
                                              (format "%d 分钟；点击查看" (plist-get day :focusTotalMinutes))))) map))))
        (push (list :kind 'heatmap :svg svg :map (nreverse map)
                    :from (plist-get (caar cells) :date) :to (plist-get (car (car (last cells))) :date)) charts)))
    (nreverse charts)))

(defun org-workflow-history-chart--trend (days selected style)
  "Draw DAYS as three minute series using STYLE, highlighting SELECTED.
Unknown dates break each series."
  (let* ((unit (plist-get style :unit)) (left (* 3 unit)) (top unit)
         (plot-height (* 7 unit)) (bottom (+ top plot-height))
         (capacity (max 1 (/ (- (plist-get style :width) left unit) unit)))
         (maximum (max 1 (apply #'max (cons 0 (delq nil (apply #'append (mapcar #'org-workflow-history-chart-values days)))))))
         (ceiling (* 30 (ceiling (/ maximum 30.0)))) (charts nil))
    (while days
      (let* ((part (seq-take days capacity)) (width (+ left (* (length part) unit) unit))
             (height (+ bottom (* 3 unit))) (svg (svg-create width height)) (map nil))
        (setq days (nthcdr (length part) days))
        (svg-rectangle svg 0 0 width height :fill (plist-get style :bg))
        (dolist (value (list 0 (/ ceiling 2) ceiling))
          (let ((y (- bottom (* plot-height (/ (float value) ceiling)))))
            (svg-line svg left y (- width unit) y :stroke (plist-get style :muted) :stroke-opacity 0.35)
            (org-workflow-history-chart--label svg (number-to-string value) (- left 8) (+ y 4) style "end")))
        (cl-loop for day in part for index from 0 for x = (+ left (* index unit))
                 for date = (substring-no-properties (plist-get day :date)) do
                 (when (equal date selected)
                   (svg-rectangle svg x top unit (+ plot-height unit) :fill (car (plist-get style :levels)))
                   (svg-line svg (+ x (/ unit 2.0)) top (+ x (/ unit 2.0)) (+ bottom unit)
                             :stroke (plist-get style :fg) :stroke-width 1 :stroke-dasharray "3 3"))
                 (when (null (nth 2 (org-workflow-history-chart-values day)))
                   (org-workflow-history-chart--cross svg (+ x 3) (+ bottom 5) (- unit 6) (plist-get style :muted)))
                 (when (or (= index 0)
                           (and (= index (1- (length part))) (> (length part) 2))
                           (and (= (% index 7) 0) (<= index (- (length part) 4))))
                   (org-workflow-history-chart--label svg (substring date 5) (+ x (/ unit 2.0))
                                                     (+ bottom (* 2 unit)) style "middle"))
                 (push (org-workflow-history-chart--hotspot date x top unit (+ plot-height unit)
                                                           (concat date " · 点击查看分类投入")) map))
        (dotimes (series 3)
          (let ((previous nil) (color (nth series (plist-get style :series)))
                (dash (nth series '("none" "6 3" "2 3"))))
            (cl-loop for day in part for index from 0
                     for value = (nth series (org-workflow-history-chart-values day))
                     for x = (+ left (* (+ index 0.5) unit)) do
                     (if (null value) (setq previous nil)
                       (let ((y (- bottom (* plot-height (/ (float value) ceiling)))))
                         (when previous
                           (svg-line svg (car previous) (cdr previous) x y :stroke color
                                     :stroke-width 2 :stroke-dasharray dash))
                         (svg-circle svg x y 2.5 :fill color)
                         (setq previous (cons x y)))))))
        (push (list :kind 'trend :svg svg :map (nreverse map)
                    :from (plist-get (car part) :date) :to (plist-get (car (last part)) :date)) charts)))
    (nreverse charts)))

(defun org-workflow-history-chart-build (payload selected style)
  "Build charts from validated PAYLOAD using STYLE and the SELECTED date."
  (let ((days (append (plist-get payload :days) nil)))
    (when days
      (list :heatmaps (org-workflow-history-chart--heatmap days selected style)
            :trends (org-workflow-history-chart--trend days selected style)))))

(defun org-workflow-history-chart-image (chart callback)
  "Return CHART's SVG with native hit regions invoking CALLBACK with a date."
  (let ((map (make-sparse-keymap)))
    (dolist (entry (plist-get chart :map))
      (let ((date (substring (symbol-name (cadr entry)) (length "workflow-history-day-")))
            (hotspot (make-sparse-keymap)))
        ;; Image maps prefix every mouse event, including wheels, with their id.
        ;; Inherit the normal mouse bindings so scrolling and modifier-wheel
        ;; actions keep the user's configuration rather than becoming undefined.
        (set-keymap-parent hotspot (current-global-map))
        (define-key map (vector (cadr entry)) hotspot)
        (define-key hotspot [down-mouse-1] #'ignore)
        (define-key hotspot [mouse-1]
                    (lambda (event)
                      (interactive "e")
                      (with-selected-window (posn-window (event-start event))
                        (funcall callback date))))))
    (cons (svg-image (plist-get chart :svg) :scale 1.0 :ascent 100 :map (plist-get chart :map)) map)))

(provide 'org-workflow-history-chart)
;;; org-workflow-history-chart.el ends here
