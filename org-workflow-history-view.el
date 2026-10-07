;;; org-workflow-history-view.el --- org-workflow-history-view Workflow component -*- lexical-binding: t; -*-
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
;;; org-workflow-history-view.el --- Pure historical display model -*- lexical-binding: t; -*-
(require 'cl-lib)

(require 'subr-x)

(require 'org-workflow-web-export)

(define-error 'org-workflow-history-view-invalid "Invalid historical data")

(defun org-workflow-history-view--invalid (path reason)
  "Signal a private-data-safe error with a bounded PATH and fixed REASON."
  (signal 'org-workflow-history-view-invalid
          (list (format "历史数据不合法：%s，%s。本次读取未显示；使用“刷新历史”重试。"
                        (truncate-string-to-width path 120) reason))))

(defun org-workflow-history-view--object (object path required)
  "Validate OBJECT as a property list at PATH containing REQUIRED keys."
  (unless (and (proper-list-p object) (cl-evenp (length object))
               (cl-loop for (key _value) on object by #'cddr always (keywordp key)))
    (org-workflow-history-view--invalid path "应为字段对象"))
  (let ((seen nil))
    (cl-loop for (key _value) on object by #'cddr do
             (when (memq key seen) (org-workflow-history-view--invalid path "字段重复"))
             (push key seen)))
  (dolist (key required)
    (unless (plist-member object key)
      (org-workflow-history-view--invalid
       (concat path (unless (string-empty-p path) ".") (substring (symbol-name key) 1)) "缺少必需字段"))))

(defun org-workflow-history-view--string (value path)
  "Validate VALUE as nonempty text, reporting errors at PATH."
  (unless (and (stringp value) (not (string-empty-p (string-trim value))))
    (org-workflow-history-view--invalid path "应为非空文字")))

(defun org-workflow-history-view--date (value path)
  "Validate VALUE as a calendar date, reporting errors at PATH."
  (unless (and (stringp value)
               (condition-case nil (equal value (org-workflow-web-export--date-add-days value 0)) (error nil)))
    (org-workflow-history-view--invalid path "应为有效公历日期")))

(defun org-workflow-history-view--timestamp (value path)
  "Validate VALUE as a timestamp with timezone, reporting errors at PATH."
  (unless (and (stringp value)
               (string-match
                "\\`\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)T\\([0-9]\\{2\\}\\):\\([0-9]\\{2\\}\\):\\([0-9]\\{2\\}\\)\\(?:\\.[0-9]+\\)?\\(Z\\|[+-][0-9]\\{2\\}:[0-9]\\{2\\}\\)\\'"
                value))
    (org-workflow-history-view--invalid path "应为有效时间戳"))
  (let ((date (match-string 1 value)) (hour (string-to-number (match-string 2 value)))
        (minute (string-to-number (match-string 3 value))) (second (string-to-number (match-string 4 value)))
        (offset (match-string 5 value)))
    (org-workflow-history-view--date date path)
    (unless (and (< hour 24) (< minute 60) (< second 60)
                 (or (equal offset "Z")
                     (and (< (string-to-number (substring offset 1 3)) 24)
                          (< (string-to-number (substring offset 4 6)) 60))))
      (org-workflow-history-view--invalid path "应为有效时间戳"))))

(defun org-workflow-history-view--number (value path)
  "Validate VALUE as a nonnegative integer, reporting errors at PATH."
  (unless (and (integerp value) (>= value 0))
    (org-workflow-history-view--invalid path "应为非负整数")))

(defun org-workflow-history-view--vector (value path)
  "Validate VALUE as a vector, reporting errors at PATH."
  (unless (vectorp value) (org-workflow-history-view--invalid path "应为记录数组")))

(defun org-workflow-history-view--tasks (rows path)
  "Validate task ROWS and their outcomes and minutes at PATH."
  (org-workflow-history-view--vector rows path)
  (cl-loop for row across rows for index from 0 for key = (format "%s[%d]" path index) do
           (org-workflow-history-view--object row key '(:task :outcome :focusMinutes))
           (org-workflow-history-view--string (plist-get row :task) (concat key ".task"))
           (unless (member (plist-get row :outcome) '("pending" "done" "ready" "held" "focused"))
             (org-workflow-history-view--invalid (concat key ".outcome") "任务状态无效"))
           (org-workflow-history-view--number (plist-get row :focusMinutes) (concat key ".focusMinutes"))
           (when (and (plist-member row :satisfied) (not (memq (plist-get row :satisfied) '(t :false))))
             (org-workflow-history-view--invalid (concat key ".satisfied") "应为布尔履行状态"))))

(defun org-workflow-history-view--leaves (rows date path)
  "Validate leave ROWS for DATE, reporting field errors at PATH."
  (org-workflow-history-view--vector rows path)
  (let ((ids nil))
    (cl-loop for row across rows for index from 0 for key = (format "%s[%d]" path index) do
             (org-workflow-history-view--object row key '(:id :date :slots :reason :recordedAt :tasks))
             (org-workflow-history-view--string (plist-get row :id) (concat key ".id"))
             (when (member (plist-get row :id) ids) (org-workflow-history-view--invalid (concat key ".id") "记录标识重复"))
             (push (plist-get row :id) ids)
             (unless (equal date (plist-get row :date)) (org-workflow-history-view--invalid (concat key ".date") "请假日期必须匹配当日"))
             (org-workflow-history-view--string (plist-get row :reason) (concat key ".reason"))
             (org-workflow-history-view--timestamp (plist-get row :recordedAt) (concat key ".recordedAt"))
             (let ((slots (plist-get row :slots)))
               (org-workflow-history-view--vector slots (concat key ".slots"))
               (unless (and (> (length slots) 0)
                            (= (length slots) (length (delete-dups (append slots nil))))
                            (cl-every (lambda (slot) (member slot '("morning" "afternoon" "evening"))) slots))
                 (org-workflow-history-view--invalid (concat key ".slots") "请假时段无效"))
               (org-workflow-history-view--vector (plist-get row :tasks) (concat key ".tasks"))
               (cl-loop for task across (plist-get row :tasks) for ti from 0
                        for tk = (format "%s.tasks[%d]" key ti) do
                        (org-workflow-history-view--object task tk '(:id :task :slot))
                        (unless (eq :null (plist-get task :id))
                          (org-workflow-history-view--string (plist-get task :id) (concat tk ".id")))
                        (org-workflow-history-view--string (plist-get task :task) (concat tk ".task"))
                        (unless (or (eq :null (plist-get task :slot))
                                    (member (plist-get task :slot) (append slots nil)))
                          (org-workflow-history-view--invalid (concat tk ".slot") "关联时段必须包含在请假时段中")))))))

(defun org-workflow-history-view--validate-day (day path expected)
  "Validate DAY at PATH, requiring its date to match EXPECTED."
  (org-workflow-history-view--object day path '(:date :recordState))
  (org-workflow-history-view--date (plist-get day :date) (concat path ".date"))
  (unless (equal expected (plist-get day :date))
    (org-workflow-history-view--invalid (concat path ".date") "日期必须连续且有序"))
  (unless (member (plist-get day :recordState) '("finalized" "missing"))
    (org-workflow-history-view--invalid (concat path ".recordState") "记录状态无效"))
  (when (equal (plist-get day :recordState) "finalized")
    (org-workflow-history-view--object
     day path '(:commitment :commitmentFocusMinutes :optionalFocusMinutes :focusTotalMinutes
                :optionalCompleted :finalizedAt :minimumTasks :optionalTasks))
    (unless (member (plist-get day :commitment) '("met" "unmet" "untouch"))
      (org-workflow-history-view--invalid (concat path ".commitment") "承诺状态无效"))
    (dolist (field '(:commitmentFocusMinutes :optionalFocusMinutes :focusTotalMinutes :optionalCompleted))
      (org-workflow-history-view--number (plist-get day field) (concat path "." (substring (symbol-name field) 1))))
    (org-workflow-history-view--timestamp (plist-get day :finalizedAt) (concat path ".finalizedAt"))
    (dolist (field '(:minimumTasks :optionalTasks))
      (when (plist-member day field)
        (org-workflow-history-view--tasks (plist-get day field) (concat path "." (substring (symbol-name field) 1))))))
  (dolist (field '(:habitFocusMinutes :habitCompleted))
    (when (plist-member day field)
      (org-workflow-history-view--number (plist-get day field) (concat path "." (substring (symbol-name field) 1)))))
  (when (plist-member day :habitTasks)
    (org-workflow-history-view--tasks (plist-get day :habitTasks) (concat path ".habitTasks")))
  (when (plist-member day :leaveRecords)
    (org-workflow-history-view--leaves (plist-get day :leaveRecords) expected (concat path ".leaveRecords"))))

(defun org-workflow-history-view-validate (payload)
  "Validate schema 1 PAYLOAD without changing or recalculating supplied facts."
  (org-workflow-history-view--object payload "" '(:schema :schemaVersion :generatedAt :timezone :coverage :days))
  (unless (equal (plist-get payload :schema) org-workflow-web-export-schema)
    (org-workflow-history-view--invalid "schema" "历史 schema 不受支持"))
  (unless (eql (plist-get payload :schemaVersion) 1)
    (org-workflow-history-view--invalid "schemaVersion" "历史版本不受支持"))
  (org-workflow-history-view--timestamp (plist-get payload :generatedAt) "generatedAt")
  (org-workflow-history-view--string (plist-get payload :timezone) "timezone")
  (org-workflow-history-view--vector (plist-get payload :days) "days")
  (let ((coverage (plist-get payload :coverage)) (days (plist-get payload :days)))
    (if (eq coverage :null)
        (unless (= 0 (length days)) (org-workflow-history-view--invalid "coverage" "空范围不得包含日期"))
      (org-workflow-history-view--object coverage "coverage" '(:trackingStarted :eligibleThrough))
      (let ((first (plist-get coverage :trackingStarted)) (last (plist-get coverage :eligibleThrough)))
        (org-workflow-history-view--date first "coverage.trackingStarted")
        (org-workflow-history-view--date last "coverage.eligibleThrough")
        (when (string> first last) (org-workflow-history-view--invalid "coverage" "起始日期晚于截止日期"))
        (let ((expected first))
          (cl-loop for day across days for index from 0 do
                   (org-workflow-history-view--validate-day day (format "days[%d]" index) expected)
                   (setq expected (org-workflow-web-export--date-add-days expected 1)))
          (unless (equal expected (org-workflow-web-export--date-add-days last 1))
            (org-workflow-history-view--invalid "days" "必须包含范围内的全部日期"))))))
  payload)

(defconst org-workflow-history-view--commitments
  '(("met" . "已达标") ("unmet" . "未达标") ("untouch" . "未触及") ("missing" . "记录缺失")))

(defconst org-workflow-history-view--outcomes
  '(("pending" . "待完成") ("done" . "已完成") ("ready" . "已就绪") ("held" . "已暂缓") ("focused" . "已投入")))

(defconst org-workflow-history-view--slots
  '(("morning" . "上午") ("afternoon" . "下午") ("evening" . "晚间")))

(defun org-workflow-history-view-summary (payload)
  "Project settled totals and the historical met suffix from PAYLOAD."
  (let ((total 0) (finalized 0) (missing 0) (streak 0) (suffix t))
    (mapc (lambda (day)
            (if (equal (plist-get day :recordState) "finalized")
                (progn (cl-incf finalized) (cl-incf total (plist-get day :focusTotalMinutes)))
              (cl-incf missing))) (plist-get payload :days))
    (dolist (day (reverse (append (plist-get payload :days) nil)))
      (if (and suffix (equal (plist-get day :recordState) "finalized")
               (equal (plist-get day :commitment) "met"))
          (cl-incf streak) (setq suffix nil)))
    (list :total total :finalized finalized :missing missing :streak streak)))

(defun org-workflow-history-view-date-options (payload)
  "Return each date in PAYLOAD paired with a unique status label."
  (mapcar (lambda (day)
            (let ((date (substring-no-properties (plist-get day :date)))
                  (status (if (equal (plist-get day :recordState) "missing") "missing" (plist-get day :commitment))))
              (cons date (format "%s · %s" date (cdr (assoc status org-workflow-history-view--commitments))))))
          (append (plist-get payload :days) nil)))

(defun org-workflow-history-view-day (payload date)
  "Find DATE in cached PAYLOAD without consulting any provider."
  (cl-find date (plist-get payload :days) :key (lambda (day) (plist-get day :date)) :test #'equal))

(defun org-workflow-history-view-detail (payload date)
  "Return DATE's original record in PAYLOAD; absence never invents facts."
  (org-workflow-history-view-day payload date))

(defun org-workflow-history-view-transition (model event &optional value time)
  "Return a complete presentation MODEL for EVENT with VALUE and TIME."
  (pcase event
    ('loading (plist-put (copy-sequence model) :state 'loading))
    ('failure (let ((next (copy-sequence model)))
                (setq next (plist-put next :state (if (plist-get model :payload) 'stale 'error)))
                (plist-put next :error value)))
    ('success
     (let* ((coverage (plist-get value :coverage)) (old-date (plist-get model :selected-date))
            (date (unless (eq coverage :null)
                    (if (org-workflow-history-view-day value old-date) old-date (plist-get coverage :eligibleThrough))))
            (notice (cond ((and old-date (null date)) "当前历史范围为空，已清除日期选择。")
                          ((and old-date (not (equal old-date date)))
                           (format "原选中日期已不在历史范围内，已选择 %s。" date)))))
       (list :state (if date 'ready 'empty) :payload value :summary (org-workflow-history-view-summary value)
             :selected-date date :detail (org-workflow-history-view-detail value date) :last-success time :notice notice)))
    ('select (if (org-workflow-history-view-day (plist-get model :payload) value)
                 (let ((next (copy-sequence model)))
                   (setq next (plist-put next :selected-date value))
                   (setq next (plist-put next :detail (org-workflow-history-view-detail (plist-get model :payload) value)))
                   (plist-put next :notice nil)) model))
    (_ (error "Unknown history presentation event"))))

(provide 'org-workflow-history-view)
;;; org-workflow-history-view.el ends here
