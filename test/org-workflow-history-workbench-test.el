;;; org-workflow-history-workbench-test.el --- Real-history tab contracts -*- lexical-binding: t; -*-

(require 'ert)
(require 'org-workflow-history-workbench)
(unless (ert-test-boundp 'workflow-history-tracer-read-render)
  (load (expand-file-name "org-workflow-history-panel-test.el"
                          (file-name-directory (or load-file-name buffer-file-name))) nil t))

(defconst workflow-history-workbench-test--style
  '(:width 420 :unit 20 :font 12 :bg "#ffffff" :fg "#202020"
    :muted "#666666" :surface "#eeeeee" :selection "#ddddff"
    :outline "#004488" :border "#cccccc"
    :levels ("#eeeeee" "#cceeee" "#88bbbb" "#447777" "#004444")
    :series ("#004488" "#884400" "#440088")))

(defmacro workflow-history-workbench-test--tabs (&rest body)
  "Restore the caller's tabs and windows after an isolated workbench exercise."
  (declare (indent 0) (debug t))
  `(let ((saved-tabs (copy-tree (frame-parameter nil 'tabs)))
         (saved-windows (current-window-configuration))
         (states nil))
     (unwind-protect
         (cl-letf (((symbol-function 'org-workflow-history-workbench--style)
                    (lambda () workflow-history-workbench-test--style))
                   ;; TTY faces lack graphical palette values used by badges.
                   ((symbol-function 'face-foreground) (lambda (&rest _) "#004488"))
                   ((symbol-function 'display-graphic-p) (lambda (&rest _) nil)))
           ,@body)
       (dolist (state states) (org-workflow-history-workbench--cleanup state))
       (set-frame-parameter nil 'tabs saved-tabs)
       (set-window-configuration saved-windows))))

(ert-deftest workflow-history-workbench-tab-close-restores-caller-windows ()
  (workflow-history-workbench-test--tabs
    (delete-other-windows)
    (let* ((other (split-window-right))
           (caller (selected-window))
           (caller-buffer (window-buffer caller))
           (other-buffer (get-buffer-create " *history-caller-test*"))
           (payload (workflow-history-view-test--payload
                     (workflow-history-view-test--day "2026-09-30")))
           (tabs-before (length (funcall tab-bar-tabs-function))))
      (unwind-protect
          (progn
            (set-window-buffer other other-buffer)
            (cl-letf (((symbol-function 'org-workflow-history-read) (lambda (&rest _) payload)))
              (with-current-buffer (org-workflow-history-workbench)
                (push org-workflow-history-workbench--state states)
                (should (= (1+ tabs-before) (length (funcall tab-bar-tabs-function))))
                (should (get-buffer-window (org-workflow-history-workbench-state-overview (car states))))
                (should (get-buffer-window (org-workflow-history-workbench-state-detail (car states))))
                (org-workflow-history-workbench-close)))
            (should (= tabs-before (length (funcall tab-bar-tabs-function))))
            (should (eq (selected-window) caller))
            (should (eq (window-buffer caller) caller-buffer))
            (should (eq (window-buffer other) other-buffer))
            (should-not (buffer-live-p (org-workflow-history-workbench-state-overview (car states))))
            (should-not (buffer-live-p (org-workflow-history-workbench-state-detail (car states)))))
        (kill-buffer other-buffer)))))

(ert-deftest workflow-history-workbench-shared-selection-stale-and-recovery ()
  (workflow-history-workbench-test--tabs
    (let ((reads 0)
          (fail nil)
          (payload (workflow-history-view-test--payload
                    (workflow-history-view-test--day "2026-09-30")
                    (workflow-history-view-test--day "2026-10-01"))))
      (cl-letf (((symbol-function 'org-workflow-history-read)
                 (lambda (&rest _) (cl-incf reads) (if fail (error "read failed") payload))))
        (with-current-buffer (org-workflow-history-workbench)
          (push org-workflow-history-workbench--state states)
          (should (= 1 reads))
          (let* ((state (car states))
                 (detail (org-workflow-history-workbench-state-detail state)))
            (org-workflow-history-panel-select-date "2026-09-30")
            (should (= 1 reads))
            (should (eq org-workflow-history-panel--model
                        (buffer-local-value 'org-workflow-history-panel--model detail)))
            (should (equal "2026-09-30" (plist-get org-workflow-history-panel--model :selected-date)))
            (let ((before org-workflow-history-panel--model))
              (setq fail t)
              (org-workflow-history-panel-refresh)
              (should (= 2 reads))
              (should (eq 'stale (plist-get org-workflow-history-panel--model :state)))
              (should (eq (plist-get before :payload) (plist-get org-workflow-history-panel--model :payload)))
              (should (eq (plist-get before :detail) (plist-get org-workflow-history-panel--model :detail)))
              (should (eq org-workflow-history-panel--model
                          (buffer-local-value 'org-workflow-history-panel--model detail))))
            (setq fail nil)
            (org-workflow-history-panel-refresh)
            (should (= 3 reads))
            (should (eq 'ready (plist-get org-workflow-history-panel--model :state)))
            (should (equal "2026-09-30" (plist-get org-workflow-history-panel--model :selected-date)))
            (should (eq org-workflow-history-panel--model
                        (buffer-local-value 'org-workflow-history-panel--model detail)))))))))

(ert-deftest workflow-history-workbench-month-and-week-cross-calendar-boundary ()
  (with-temp-buffer
    (setq org-workflow-history-panel--model
          (org-workflow-history-view-transition
           nil 'success
           (apply #'workflow-history-view-test--payload
                  (cl-loop for offset below 10 collect
                           (workflow-history-view-test--day
                            (org-workflow-web-export--date-add-days "2026-09-28" offset)))) "now"))
    (setq org-workflow-history-panel--model
          (org-workflow-history-view-transition org-workflow-history-panel--model 'select "2026-10-01"))
    (should (equal '("2026-10-01" "2026-10-02" "2026-10-03" "2026-10-04" "2026-10-05" "2026-10-06" "2026-10-07")
                   (mapcar (lambda (day) (plist-get day :date)) (org-workflow-history-workbench--month))))
    (should (equal '("2026-09-28" "2026-09-29" "2026-09-30" "2026-10-01" "2026-10-02" "2026-10-03" "2026-10-04")
                   (mapcar (lambda (day) (plist-get day :date)) (org-workflow-history-workbench--week))))))

(ert-deftest workflow-history-workbench-real-detail-unknown-false-and-missing-leave ()
  (workflow-history-workbench-test--tabs
    (let* ((day (workflow-history-view-test--without
                 (workflow-history-view-test--day "2026-09-30")
                 :habitFocusMinutes :habitCompleted :habitTasks))
           (missing (plist-put (workflow-history-view-test--day "2026-10-01" "missing")
                               :leaveRecords (workflow-history-view-test--leave "2026-10-01"))))
      (setf (plist-get day :minimumTasks)
            [(:task "用户实际承诺任务" :outcome "pending" :focusMinutes 25 :satisfied :false)])
      (cl-letf (((symbol-function 'org-workflow-history-read)
                 (lambda (&rest _) (workflow-history-view-test--payload day missing))))
        (with-current-buffer (org-workflow-history-workbench)
          (push org-workflow-history-workbench--state states)
          (org-workflow-history-panel-select-date "2026-09-30")
          (with-current-buffer (org-workflow-history-workbench-state-detail (car states))
            (dolist (text '("用户实际承诺任务" "承诺未满足" "未知" "旧记录未追踪"))
              (should (string-match-p text (buffer-string))))
            (should-not (string-match-p "承诺已满足" (buffer-string))))
          (org-workflow-history-panel-select-date "2026-10-01")
          (with-current-buffer (org-workflow-history-workbench-state-detail (car states))
            (should (string-match-p "记录缺失" (buffer-string)))
            (should (string-match-p "休息原文" (buffer-string)))
            (should (string-match-p "相关任务" (buffer-string)))
            (should-not (string-match-p "用户实际承诺任务" (buffer-string)))))))))

(provide 'org-workflow-history-workbench-test)
;;; org-workflow-history-workbench-test.el ends here

(ert-deftest workflow-history-workbench-month-buttons-use-cache-and-clamp ()
  (workflow-history-workbench-test--tabs
    (let ((reads 0)
          (payload (apply #'workflow-history-view-test--payload
                          (cl-loop for offset below 40 collect
                                   (workflow-history-view-test--day
                                    (org-workflow-web-export--date-add-days "2026-01-30" offset))))))
      (cl-letf (((symbol-function 'org-workflow-history-read)
                 (lambda (&rest _) (cl-incf reads) payload)))
        (with-current-buffer (org-workflow-history-workbench)
          (push org-workflow-history-workbench--state states)
          (org-workflow-history-panel-select-date "2026-01-31")
          (should-not (org-workflow-history-workbench--month-target t))
          (org-workflow-history-workbench-next-month)
          (should (equal "2026-02-28" (plist-get org-workflow-history-panel--model :selected-date)))
          (org-workflow-history-workbench-next-month)
          (should (equal "2026-03-10" (plist-get org-workflow-history-panel--model :selected-date)))
          (should-not (org-workflow-history-workbench--month-target))
          (goto-char (point-min)) (search-forward "下个月")
          (goto-char (match-beginning 0))
          (org-workflow-history-workbench-activate)
          (should (equal "2026-03-10" (plist-get org-workflow-history-panel--model :selected-date)))
          (org-workflow-history-workbench-next-month)
          (should (equal "2026-03-10" (plist-get org-workflow-history-panel--model :selected-date)))
          (org-workflow-history-workbench-previous-month)
          (should (equal "2026-02-10" (plist-get org-workflow-history-panel--model :selected-date)))
          (should (= reads 1))
          (should (equal "2026-02-10"
                         (plist-get (buffer-local-value 'org-workflow-history-panel--model
                                                       (org-workflow-history-workbench-state-detail (car states)))
                                    :selected-date)))
          (dolist (buffer (list (org-workflow-history-workbench-state-overview (car states))
                               (org-workflow-history-workbench-state-detail (car states))))
            (with-current-buffer buffer
              (should (local-variable-p 'tab-line-format))
              (should-not tab-line-format)))
          (should (string-match-p "上个月" (buffer-string)))
          (should (string-match-p "下个月" (buffer-string))))))))

(ert-deftest workflow-history-tracking-keeps-single-buffer-entry-in-gui ()
  (let ((payload (workflow-history-view-test--payload (workflow-history-view-test--day "2026-09-30")))
        (tabs-before (length (funcall tab-bar-tabs-function))))
    (unwind-protect
        (cl-letf (((symbol-function 'org-workflow-history-read) (lambda (&rest _) payload))
                  ((symbol-function 'org-workflow-history-panel--adapt) #'ignore)
                  ((symbol-function 'org-workflow-history-panel--charts) (lambda (&rest _) (vui-text "原始完整热力图与趋势")))
                  ((symbol-function 'org-workflow-history-workbench) (lambda (&rest _) (ert-fail "Single view routed to workbench")))
                  ((symbol-function 'display-graphic-p) (lambda (&rest _) t))
                  ((symbol-function 'org-workflow-history-chart-style) (lambda () workflow-history-workbench-test--style)))
          (with-current-buffer (org-workflow-history-tracking)
            (should-not org-workflow-history-workbench--state)
            (should (string-match-p "原始完整热力图与趋势" (buffer-string)))
            (should (string-match-p "日详情" (buffer-string))))
          (should (= tabs-before (length (funcall tab-bar-tabs-function)))))
      (when (get-buffer "*Workflow History*") (kill-buffer "*Workflow History*")))))
