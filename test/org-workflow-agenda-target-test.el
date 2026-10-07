;;; org-workflow-agenda-target-test.el --- tests for today's Org target stack -*- lexical-binding: t; -*-
(require 'ert)
(require 'org)
(require 'org-modern nil t)
(require 'org-workflow-agenda)
(require 'org-workflow-focus-timer)
(require 'org-workflow-core)

(defmacro org-workflow-target-test-with-files (contents &rest body)
  `(let ((files nil)
         (org-agenda-buffer-name (generate-new-buffer-name "*Org Target Test Agenda*"))
         (org-workflow-agenda-future-expanded nil)
         (org-workflow-agenda-planning-all nil))
     (unwind-protect
         (progn
           (dolist (content ,contents)
             (let ((file (make-temp-file "org-target-" nil ".org" content)))
               (push file files)))
           (let ((org-agenda-files files))
             (cl-letf (((symbol-function 'org-workflow-target--today-string)
                        (lambda () "2026-08-17"))
                       ((symbol-function 'org-workflow-collection-inbox--review-files)
                        (lambda () files))
                       ((symbol-function 'current-time)
                        (lambda () (encode-time 0 0 20 17 8 2026))))
               ,@body)))
       (when-let* ((agenda (get-buffer org-agenda-buffer-name)))
         (let ((owned (with-current-buffer agenda
                        (or (org-workflow-agenda--workbench-buffers) (list agenda)))))
           (dolist (buffer owned)
             (when (buffer-live-p buffer) (kill-buffer buffer)))))
       (dolist (file files)
         (when-let* ((buffer (get-file-buffer file)))
           (set-buffer-modified-p nil)
           (kill-buffer buffer))
         (delete-file file)))))

(ert-deftest org-workflow-target-collects-today-and-overdue-unfinished-leaves ()
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n* Area\n** TODO Today\nSCHEDULED: <2026-08-17 Mon>\n** TODO Overdue\nSCHEDULED: <2026-08-15 Sat>\n** TODO Future\nSCHEDULED: <2026-08-18 Tue>\n** DONE Old done\nCLOSED: [2026-08-16 Sun 10:00]\nSCHEDULED: <2026-08-14 Fri>\n")
   (should (equal '("Overdue" "Today")
                  (sort (mapcar #'org-workflow-target-entry-title
                                (org-workflow-target--ordered-entries))
                        #'string-lessp)))))

(ert-deftest org-workflow-target-legacy-batch-does-not-admit-an-unscheduled-task ()
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n* Area\n** TODO Legacy\n:PROPERTIES:\n:WORKFLOW_BATCH: [2026-08-17]/minimum\n:END:\n")
   (should-not (org-workflow-target--collect))))

(ert-deftest org-workflow-live-queries-ignore-all-retired-properties ()
  "Legacy batch, blocker, phase, and seal facts do not affect live results."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n#+TODO: TODO READY | DONE HOLD\n* Area :promise:\n** TODO [#A] Pending\nSCHEDULED: <2026-08-17 Mon>\n:PROPERTIES:\n:WORKFLOW_BATCH: [2026-08-17]/optional\n:WORKFLOW_BLOCKED_BY: missing-id\n:WORKFLOW_PHASE: optional\n:WORKFLOW_MINIMUM_SEALED_AT: [2026-08-17 Mon 09:00]\n:END:\n** DONE [#A] Finished\nCLOSED: [2026-08-17 Mon 10:00] SCHEDULED: <2026-08-17 Mon>\n")
   (should (equal '("Pending")
                  (mapcar #'org-workflow-target-entry-title
                          (org-workflow-target--collect))))
   (should (equal '(:stageSatisfied 1 :stageTotal 2)
                  (org-workflow--stage-progress
                   "2026-08-17" (encode-time 0 0 9 17 8 2026))))
   (should (equal '(:minimumSatisfied 1 :minimumTotal 2
                    :phase "minimum" :commitmentComplete :false)
                  (org-workflow--promise-progress "2026-08-17")))))

(ert-deftest org-workflow-stage-progress-counts-only-todays-rolling-outcomes ()
  "Progress counts direct scheduled work and outcomes resolved on DATE."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n#+TODO: TODO READY | DONE HOLD\n* Area\n** TODO [#A] Overdue pending\nSCHEDULED: <2026-08-15 Sat>\n** DONE [#A] Done today\nCLOSED: [2026-08-17 Mon 10:00] SCHEDULED: <2026-08-15 Sat>\n** DONE [#A] Done yesterday\nCLOSED: [2026-08-16 Sun 10:00] SCHEDULED: <2026-08-14 Fri>\n** READY [#B] Ready today\n:PROPERTIES:\n:WORKFLOW_READY_ON: [2026-08-17 Mon 11:00]\n:END:\n** HOLD [#C] Held today\nCLOSED: [2026-08-17 Mon 12:00] SCHEDULED: <2026-08-16 Sun>\n")
   (should (equal '(:stageSatisfied 1 :stageTotal 2)
                  (org-workflow--stage-progress
                   "2026-08-17" (encode-time 0 0 9 17 8 2026))))
   (should (equal '(:stageSatisfied 2 :stageTotal 3)
                  (org-workflow--stage-progress
                   "2026-08-17" (encode-time 0 0 13 17 8 2026))))
   (should (equal '(:stageSatisfied 3 :stageTotal 4)
                  (org-workflow--stage-progress
                   "2026-08-17" (encode-time 0 0 19 17 8 2026))))))

(ert-deftest org-workflow-stage-progress-inherits-ancestor-priority ()
  "An implicit leaf uses its nearest explicit ancestor in stage counts."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n* [#C] Area\n** TODO [#A] Tutorial\n*** TODO Chapter\n**** DONE Finished\nCLOSED: [2026-08-17 Mon 10:00] SCHEDULED: <2026-08-17 Mon>\n**** TODO Pending\nSCHEDULED: <2026-08-17 Mon>\n**** TODO [#C] Explicit override\nSCHEDULED: <2026-08-17 Mon>\n")
   (should (equal '(:stageSatisfied 1 :stageTotal 2)
                  (org-workflow--stage-progress
                   "2026-08-17" (encode-time 0 0 9 17 8 2026))))))

(ert-deftest org-workflow-promise-progress-inherits-and-ignores-priority ()
  "Inherited promise, rather than priority, selects minimum commitments."
  (org-workflow-target-test-with-files
   '("#+filetags: :project:\n#+TODO: TODO READY | DONE HOLD\n* Stage :promise:\n** TODO Group\n*** TODO [#C] Pending\nSCHEDULED: <2026-08-16 Sun>\n*** DONE [#A] Finished\nCLOSED: [2026-08-17 Mon 09:00] SCHEDULED: <2026-08-17 Mon>\n")
   (should (equal '(:minimumSatisfied 1 :minimumTotal 2
                    :phase "minimum" :commitmentComplete :false)
                  (org-workflow--promise-progress "2026-08-17")))))

(ert-deftest org-workflow-promise-progress-excludes-level-one-leaf ()
  "A promised top-level task is outside the actionable Workflow scope."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n* TODO Top-level :promise:\nSCHEDULED: <2026-08-17 Mon>\n")
   (should (equal '(:minimumSatisfied 0 :minimumTotal 0
                    :phase "minimum" :commitmentComplete :false)
                  (org-workflow--promise-progress "2026-08-17")))))

(ert-deftest org-workflow-status-falls-back-to-live-promise-progress ()
  "A nil journal result leaves live promise tags as the daily source."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n* Area :promise:\n** TODO Pending\nSCHEDULED: <2026-08-17 Mon>\n")
   (let ((org-workflow-status-provider-function (lambda (_date) nil)))
     (let ((status (org-workflow-status)))
       (should (= 0 (plist-get status :minimumSatisfied)))
       (should (= 1 (plist-get status :minimumTotal)))
       (should (equal "minimum" (plist-get status :phase)))
       (should (eq :false (plist-get status :commitmentComplete)))
       (should (= 0 (plist-get status :commitmentStreak)))))))

(ert-deftest org-workflow-stage-progress-ignores-project-deadline ()
  "Title-bar progress is selected by daily facts, not project deadlines."
  (org-workflow-target-test-with-files
   '("#+filetags: :project:\n* TODO Expired\nDEADLINE: <2026-08-16 Sun>\n** TODO Group\n*** DONE [#A] Included\nCLOSED: [2026-08-17 Mon 10:00] SCHEDULED: <2026-08-17 Mon>\n")
   (should (equal '(:stageSatisfied 1 :stageTotal 1)
                  (org-workflow--stage-progress
                   "2026-08-17" (encode-time 0 0 9 17 8 2026))))))

(ert-deftest org-workflow-target-excludes-scheduled-task-with-todo-descendants ()
  "Only task leaves may become executable stack entries."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n* Area\n** TODO Parent\nSCHEDULED: <2026-08-17 Mon>\n*** DONE Historical child\n")
   (should-not (org-workflow-target--collect))))

(ert-deftest org-workflow-target-collects-workflow-leaves-independent-of-deadline ()
  "Project deadlines do not gate daily commitments; filetags still do."
  (org-workflow-target-test-with-files
   '("#+filetags: :project:\n* TODO Current\nDEADLINE: <2026-08-18 Tue>\n** TODO Group\n*** TODO Project leaf\nSCHEDULED: <2026-08-17 Mon>\n* TODO Expired\nDEADLINE: <2026-08-16 Sun>\n** TODO Hidden\n*** TODO Expired leaf\nSCHEDULED: <2026-08-17 Mon>\n"
     "#+filetags: :area:\n* Area\n** TODO Area leaf\nSCHEDULED: <2026-08-17 Mon>\n"
     "* TODO Unscoped\nSCHEDULED: <2026-08-17 Mon>\n")
   (should (equal '("Area leaf" "Expired leaf" "Project leaf")
                  (sort (mapcar #'org-workflow-target-entry-title
                                (org-workflow-target--collect))
                        #'string-lessp)))))

(ert-deftest org-workflow-held-p-includes-self-and-descendants ()
  "The HOLD boundary applies to its complete subtree."
  (with-temp-buffer
    (org-mode)
    (insert "* HOLD Branch
** TODO Child
*** READY Leaf
* TODO Visible
")
    (goto-char (point-min))
    (should (org-workflow--held-p))
    (re-search-forward "TODO Child")
    (should (org-workflow--held-p))
    (re-search-forward "READY Leaf")
    (should (org-workflow--held-p))
    (re-search-forward "TODO Visible")
    (should-not (org-workflow--held-p))))

(ert-deftest org-workflow-target-hold-blocks-the-whole-scheduled-subtree ()
  "A scheduled TODO below HOLD is not actionable even inside a DIVE branch."
  (org-workflow-target-test-with-files
   '("#+filetags: :project:
* DIVE Stage
** TODO Task group
*** HOLD Deferred branch
**** TODO Hidden leaf
SCHEDULED: <2026-08-17 Mon>
*** TODO Active branch
**** TODO Visible leaf
SCHEDULED: <2026-08-17 Mon>
")
   (should (equal '("Visible leaf")
                  (mapcar #'org-workflow-target-entry-title
                          (org-workflow-target--collect))))))

(ert-deftest org-workflow-stage-progress-counts-held-ancestor-as-satisfied ()
  "A selected leaf below HOLD satisfies its daily commitment."
  (org-workflow-target-test-with-files
   '("#+filetags: :project:
#+TODO: TODO READY | DONE HOLD
* HOLD Deferred
CLOSED: [2026-08-17 Mon 10:00]
** TODO [#A] Selected leaf
SCHEDULED: <2026-08-17 Mon>
")
   (should (equal '(:stageSatisfied 1 :stageTotal 1)
                  (org-workflow--stage-progress
                   "2026-08-17" (encode-time 0 0 9 17 8 2026))))))

(ert-deftest org-workflow-target-explicit-project-schedule-needs-no-stage-deadline ()
  "Today's explicit schedule is a minimum commitment, not a phase query."
  (org-workflow-target-test-with-files
   '("#+filetags: :project:\n* Reference material\n** TODO Explicit minimum\nSCHEDULED: <2026-08-17 Mon>\n")
   (should (equal '("Explicit minimum")
                  (mapcar #'org-workflow-target-entry-title
                          (org-workflow-target--collect))))))

(ert-deftest org-workflow-target-entry-title-discards-org-display-properties ()
  (cl-letf (((symbol-function 'org-link-heading-search-string)
             (lambda () (propertize "*Current" 'display "" 'invisible t))))
    (let ((title (org-workflow-target--entry-title)))
      (should (equal title "Current"))
      (should-not (text-properties-at 0 title)))))

(ert-deftest org-workflow-target-sorts-by-priority-time-title-file-marker ()
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n* Area\n** TODO Lower priority\n*** TODO [#B] Lower priority :tag:\nSCHEDULED: <2026-08-17 Mon 07:00>\n** TODO Date only\n*** TODO [#A] Date only\nSCHEDULED: <2026-08-17 Mon>\n** TODO Zebra\n*** TODO [#A] Zebra\nSCHEDULED: <2026-08-17 Mon 09:00>\n** TODO alpha\n*** TODO [#A] alpha [2/3]\nSCHEDULED: <2026-08-17 Mon 09:00>\n** TODO Earlier\n*** TODO [#A] Earlier\nSCHEDULED: <2026-08-17 Mon 08:00>\n")
   (let ((entries (org-workflow-target--sorted-entries)))
     (should (equal '("Earlier" "alpha" "Zebra" "Date only" "Lower priority")
                    (mapcar #'org-workflow-target-entry-title entries)))
     (should (> (org-workflow-target-entry-priority (car entries))
                (org-workflow-target-entry-priority (car (last entries))))))))

(ert-deftest org-workflow-target-date-only-sorts-after-timed ()
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n* Area\n** TODO Timed\nSCHEDULED: <2026-08-17 Mon 23:59>\n** TODO Date\nSCHEDULED: <2026-08-17 Mon>\n")
   (let ((entries (org-workflow-target--sorted-entries)))
     (should (= 1439 (org-workflow-target-entry-scheduled-minute (car entries))))
     (should-not (org-workflow-target-entry-scheduled-minute (cadr entries))))))

(ert-deftest org-workflow-target-ignores-legacy-deferred-metadata ()
  "Legacy TARGET_DEFERRED facts must not override the new group order."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n* Area\n** TODO A Deferred\nSCHEDULED: <2026-08-17 Mon 09:00>\n:PROPERTIES:\n:TARGET_DEFERRED: t\n:END:\n** TODO Z Regular\nSCHEDULED: <2026-08-17 Mon 09:00>\n")
   (should (equal '("A Deferred" "Z Regular")
                  (mapcar #'org-workflow-target-entry-title
                          (org-workflow-target--sorted-entries))))))

(ert-deftest org-workflow-target-sorts-by-leaf-priority-across-parent-groups ()
  "A leaf priority overrides the priority of its organizing parent."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n* Area\n** TODO Cache Performance\n*** TODO Memory Hierarchy\nSCHEDULED: <2026-08-17 Mon>\n*** TODO Summary\nSCHEDULED: <2026-08-17 Mon>\n** TODO Walk through quick start\n*** TODO [#A] MDN: Web standards\nSCHEDULED: <2026-08-17 Mon>\n")
   (should (equal '("MDN: Web standards" "Memory Hierarchy" "Summary")
                  (mapcar #'org-workflow-target-entry-title
                          (org-workflow-target--sorted-entries))))))

(ert-deftest org-workflow-target-sorts-by-inherited-ancestor-priority ()
  "Implicit leaves sort by ancestor priority; explicit leaves override it."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n* Area\n** TODO [#A] Zulu group\n*** TODO Zulu inherited A\nSCHEDULED: <2026-08-17 Mon>\n** TODO Alpha group\n*** TODO Alpha default B\nSCHEDULED: <2026-08-17 Mon>\n** TODO [#A] Aaron group\n*** TODO [#C] Aaron explicit C\nSCHEDULED: <2026-08-17 Mon>\n")
   (should (equal '("Zulu inherited A" "Alpha default B" "Aaron explicit C")
                  (mapcar #'org-workflow-target-entry-title
                          (org-workflow-target--sorted-entries))))))

(ert-deftest org-workflow-target-groups-same-parent-priority-in-outline-order ()
  "An overdue group leads today's group without separating its siblings."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n* Area\n** TODO [#A] Container\n*** TODO Today group\n**** TODO Other\nSCHEDULED: <2026-08-17 Mon 10:00>\n*** TODO Overdue group\n**** TODO First\nSCHEDULED: <2026-08-16 Sun 09:00>\n**** TODO Second\nSCHEDULED: <2026-08-17 Mon 12:00>\n")
   (should (equal '("First" "Second" "Other")
                  (mapcar #'org-workflow-target-entry-title
                          (org-workflow-target--sorted-entries))))))

(ert-deftest org-workflow-target-groups-siblings-under-ordinary-container ()
  "An ordinary parent groups equal-priority leaves in outline order."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n* Ordinary area\n** TODO [#B] Older B\nSCHEDULED: <2026-08-14 Fri 08:00>\n** TODO [#A] Later in outline\nSCHEDULED: <2026-08-17 Mon 12:00>\n** TODO [#A] Earlier by schedule\nSCHEDULED: <2026-08-16 Sun 09:00>\n* Older area\n** TODO [#A] Old separate group\nSCHEDULED: <2026-08-15 Sat 10:00>\n")
   (should (equal '("Old separate group" "Later in outline"
                    "Earlier by schedule" "Older B")
                  (mapcar #'org-workflow-target-entry-title
                          (org-workflow-target--sorted-entries))))))

(ert-deftest org-workflow-target-exposes-fixed-priority-bands-with-fallback ()
  "Morning and afternoon expand only when their normal bands are empty."
  (let* ((entry-a (org-workflow-target-entry-create
                   :title "A" :priority (org-get-priority "[#A]")))
         (entry-b (org-workflow-target-entry-create
                   :title "B" :priority (org-get-priority "[#B]")))
         (entry-c (org-workflow-target-entry-create
                   :title "C" :priority (org-get-priority "[#C]"))))
    (should (equal '("A")
                   (mapcar #'org-workflow-target-entry-title
                           (org-workflow-target--expose-by-time
                            (list entry-a entry-b entry-c)
                            (encode-time 0 0 10 17 8 2026)))))
    (should (equal '("B")
                   (mapcar #'org-workflow-target-entry-title
                           (org-workflow-target--expose-by-time
                            (list entry-b entry-c)
                            (encode-time 0 0 10 17 8 2026)))))
    (should (equal '("A" "B")
                   (mapcar #'org-workflow-target-entry-title
                           (org-workflow-target--expose-by-time
                            (list entry-a entry-b entry-c)
                            (encode-time 0 0 15 17 8 2026)))))
    (should (equal '("C")
                   (mapcar #'org-workflow-target-entry-title
                           (org-workflow-target--expose-by-time
                            (list entry-c)
                            (encode-time 0 0 15 17 8 2026)))))
    (should (equal '("A" "B" "C")
                   (mapcar #'org-workflow-target-entry-title
                           (org-workflow-target--expose-by-time
                            (list entry-a entry-b entry-c)
                            (encode-time 0 0 20 17 8 2026)))))))

(ert-deftest org-workflow-normalization-moves-parent-schedule-to-leaves ()
  "A scheduled container must surrender its planning line to its leaves."
  (org-workflow-target-test-with-files
   '("#+filetags: :project:\n* TODO Stage\nDEADLINE: <2026-08-18 Tue>\n** TODO Group\nSCHEDULED: <2026-08-17 Mon 09:30>\n*** TODO First\n*** TODO Nested\n**** TODO Second\n")
   (with-current-buffer (find-file-noselect (car org-agenda-files))
     (goto-char (point-min))
     (re-search-forward "^\\*\\* TODO Group")
     (beginning-of-line)
     (org-workflow-normalize-heading)
     (should-not (org-entry-get nil "SCHEDULED"))
     (should (string-match-p "\\[[0-9]+/[0-9]+\\]" (org-get-heading)))
     (let (schedules batches)
       (org-map-entries
        (lambda ()
          (when (member (org-get-heading t t t t) '("First" "Second"))
            (push (org-entry-get nil "SCHEDULED") schedules)
            (push (org-entry-get-multivalued-property nil "WORKFLOW_BATCH")
                  batches)))
        nil 'file)
       (should (= 2 (length schedules)))
       (dolist (schedule schedules)
         (should (equal "2026-08-17"
                        (org-workflow-target--timestamp-date schedule)))
         (should (= 570 (org-workflow-target--scheduled-minute schedule))))
       (should (equal '(nil nil) batches))))))

(ert-deftest org-workflow-normalization-inherits-priority-with-child-override ()
  "Unprioritized leaves inherit the source priority without overwriting a child."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n* Area\n** TODO [#A] Parent\nSCHEDULED: <2026-08-17 Mon>\n*** TODO Inherits\n*** TODO [#C] Explicit\n")
   (with-current-buffer (find-file-noselect (car org-agenda-files))
     (goto-char (point-min))
     (re-search-forward "^\\*\\* TODO \\[#A\\] Parent")
     (beginning-of-line)
     (org-workflow-normalize-heading)
     (re-search-forward "^\\*\\*\\* TODO \\[#A\\] Inherits")
     (beginning-of-line)
     (should (= (org-get-priority "[#A]")
                (org-get-priority (org-get-heading))))
     (outline-next-heading)
     (should (equal "Explicit" (org-get-heading t t t t)))
     (should (= (org-get-priority "[#C]")
                (org-get-priority (org-get-heading)))))))

(ert-deftest org-workflow-normalization-does-not-select-held-subtrees ()
  "Schedule transfer excludes HOLD descendants without creating batches."
  (org-workflow-target-test-with-files
   '("#+filetags: :project:\n#+TODO: TODO READY | DONE HOLD\n* TODO [#A] Stage\nSCHEDULED: <2026-08-17 Mon>\n** TODO Visible\n** HOLD Deferred\n*** TODO Hidden\n")
   (with-current-buffer (find-file-noselect (car org-agenda-files))
     (goto-char (point-min))
     (re-search-forward "^\\* TODO \\[#A\\] Stage")
     (beginning-of-line)
     (org-workflow-normalize-heading)
     (re-search-forward "^\\*\\* TODO .*Visible")
     (beginning-of-line)
     (should (org-entry-get nil "SCHEDULED"))
     (should-not (org-entry-get nil "WORKFLOW_BATCH"))
     (re-search-forward "^\\*\\*\\* TODO Hidden")
     (beginning-of-line)
     (should-not (org-entry-get nil "SCHEDULED"))
     (should-not (org-entry-get nil "WORKFLOW_BATCH"))
     (should (equal '(:stageSatisfied 0 :stageTotal 1)
                    (org-workflow--stage-progress
                     "2026-08-17"
                     (encode-time 0 0 10 17 8 2026)))))))

(ert-deftest org-workflow-normalization-does-not-propagate-legacy-batches ()
  "Refinement leaves legacy batch metadata on its source heading."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n* Area\n** TODO Parent\nSCHEDULED: <2026-08-17 Mon>\n:PROPERTIES:\n:WORKFLOW_BATCH: [2026-08-17]/minimum\n:END:\n*** TODO First\n*** TODO Second\n")
   (with-current-buffer (find-file-noselect (car org-agenda-files))
     (goto-char (point-min))
     (re-search-forward "^\\*\\* TODO Parent")
     (beginning-of-line)
     (org-workflow-normalize-heading)
     (should (equal '("[2026-08-17]/minimum")
                    (org-entry-get-multivalued-property
                     nil "WORKFLOW_BATCH")))
     (let (batches)
       (org-map-entries
        (lambda ()
          (when (member (org-get-heading t t t t) '("First" "Second"))
            (push (org-entry-get-multivalued-property
                   nil "WORKFLOW_BATCH")
                  batches)))
        nil 'file)
       (should (equal '(nil nil) batches))))))

(ert-deftest org-workflow-normalizes-project-schedule-despite-overdue-deadline ()
  "A project deadline does not gate downward schedule transfer."
  (org-workflow-target-test-with-files
   '("#+filetags: :project:\n* Reference material\nDEADLINE: <2026-08-16 Sun>\n** TODO Group\nSCHEDULED: <2026-08-17 Mon>\n*** TODO Leaf\n")
   (with-current-buffer (find-file-noselect (car org-agenda-files))
     (goto-char (point-min))
     (re-search-forward "^\\*\\* TODO Group")
     (beginning-of-line)
     (org-workflow-normalize-heading)
     (should-not (org-entry-get nil "SCHEDULED"))
     (outline-next-heading)
     (should (equal "2026-08-17"
                    (org-workflow-target--timestamp-date
                     (org-entry-get nil "SCHEDULED")))))))

(ert-deftest org-workflow-org-schedule-normalizes-before-returning ()
  "Scheduling an eligible container must immediately expose only its leaves."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n* Area\n** TODO Group\n*** TODO Leaf\n")
   (with-current-buffer (find-file-noselect (car org-agenda-files))
     (goto-char (point-min))
     (re-search-forward "^\\*\\* TODO Group")
     (beginning-of-line)
     (org-schedule nil "2026-08-17 10:15")
     (should-not (org-entry-get nil "SCHEDULED"))
     (outline-next-heading)
     (should (equal "2026-08-17"
                    (org-workflow-target--timestamp-date
                     (org-entry-get nil "SCHEDULED"))))
     (should (= 615 (org-workflow-target--scheduled-minute
                     (org-entry-get nil "SCHEDULED")))))))

(ert-deftest org-workflow-refresh-reads-container-without-mutating ()
  "Discovery must leave both buffer and file unchanged."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n* Area\n** TODO Group\nSCHEDULED: <2026-08-17 Mon>\n*** TODO Leaf\n")
   (let* ((file (car org-agenda-files))
          (buffer (find-file-noselect file)))
     (with-current-buffer buffer
       (should-not (buffer-modified-p)))
     (org-workflow-target-refresh t)
     (with-current-buffer buffer
       (goto-char (point-min))
       (re-search-forward "^\\*\\* TODO Group")
       (beginning-of-line)
       (should (org-entry-get nil "SCHEDULED"))
       (should-not (buffer-modified-p)))
     (with-temp-buffer
       (insert-file-contents file)
       (should (re-search-forward
                "^SCHEDULED: <2026-08-17 Mon>" nil t))
       (should-not (re-search-forward "WORKFLOW_BATCH" nil t))))))

(ert-deftest org-workflow-refresh-does-not-assign-batch-to-direct-leaf ()
  "Discovery reads a direct leaf schedule without mutating legacy metadata."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n* Area\n** TODO Leaf\nSCHEDULED: <2026-08-17 Mon>\n")
   (let* ((file (car org-agenda-files))
          (buffer (find-file-noselect file)))
     (with-current-buffer buffer
       (should-not (buffer-modified-p)))
     (org-workflow-target-refresh t)
     (with-current-buffer buffer
       (goto-char (point-min))
       (re-search-forward "^\\*\\* TODO Leaf")
       (beginning-of-line)
       (should-not (org-entry-get nil "WORKFLOW_BATCH"))
       (should-not (buffer-modified-p)))
     (with-temp-buffer
       (insert-file-contents file)
       (should-not (re-search-forward "WORKFLOW_BATCH" nil t))))))

(ert-deftest org-workflow-save-preserves-direct-planning-edit ()
  "Saving must not redistribute a directly edited schedule."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n* Area\n** TODO Group\n*** TODO Leaf\n")
   (let ((file (car org-agenda-files)))
     (with-current-buffer (find-file-noselect file)
       (goto-char (point-min))
       (re-search-forward "^\\*\\* TODO Group")
       (beginning-of-line)
       (org-add-planning-info 'scheduled "2026-08-17")
       (save-buffer))
     (with-temp-buffer
       (insert-file-contents file)
       (org-mode)
       (goto-char (point-min))
       (re-search-forward "^\\*\\* TODO Group")
       (beginning-of-line)
       (should (org-entry-get nil "SCHEDULED"))
       (outline-next-heading)
       (should-not (org-entry-get nil "SCHEDULED"))))))

(ert-deftest org-workflow-rescheduling-preserves-legacy-batch-history ()
  "Rolling scheduling leaves existing legacy batch history unchanged."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n* Area\n** TODO Leaf\nSCHEDULED: <2026-08-17 Mon>\n:PROPERTIES:\n:WORKFLOW_BATCH: [2026-08-16]/minimum\n:END:\n")
   (with-current-buffer (find-file-noselect (car org-agenda-files))
     (goto-char (point-min))
     (re-search-forward "^\\*\\* TODO Leaf")
     (beginning-of-line)
     (org-workflow-normalize-heading)
     (org-workflow-normalize-heading)
     (org-schedule nil "2026-08-18")
     (should (equal '("[2026-08-16]/minimum")
                    (org-entry-get-multivalued-property
                     nil "WORKFLOW_BATCH"))))))

(ert-deftest org-workflow-never-normalizes-unscoped-org-data ()
  "A normal Org file must remain outside workflow mutation policy."
  (org-workflow-target-test-with-files
   '("* TODO Parent\nSCHEDULED: <2026-08-17 Mon>\n** TODO Child\n")
   (with-current-buffer (find-file-noselect (car org-agenda-files))
     (goto-char (point-min))
     (org-workflow-normalize-heading)
     (should (org-entry-get nil "SCHEDULED"))
     (should-not (org-entry-get nil "WORKFLOW_BATCH"))
     (outline-next-heading)
     (should-not (org-entry-get nil "SCHEDULED")))))

(defmacro org-workflow-target-test-with-current (&rest body)
  `(with-temp-buffer
     (org-mode)
     (insert "* TODO Current\nSCHEDULED: <2026-08-17 Mon>\n** DONE Finished\n** TODO Open\n* TODO Next\nSCHEDULED: <2026-08-17 Mon>\n** TODO Child\n")
     (goto-char (point-min))
     (let ((org-workflow-target-stack
            (list (org-workflow-target-entry-create :marker (copy-marker (point)) :title "Current")
                  (org-workflow-target-entry-create :marker (copy-marker (save-excursion (forward-line 4) (point))) :title "Next"))))
       (cl-letf (((symbol-function 'org-workflow-target-refresh)
                  (lambda (&optional _) org-workflow-target-stack)))
         ,@body))))

(defmacro org-workflow-test-with-leaf (&rest body)
  `(with-temp-buffer
     (org-mode)
     (insert "#+filetags: :area:\n#+TODO: TODO READY | DONE HOLD\n* Area\n** TODO Current\nSCHEDULED: <2026-08-17 Mon>\n")
     (goto-char (point-min))
     (re-search-forward "^\\*\\* TODO Current")
     (beginning-of-line)
     (let ((org-file-tags '("area"))
           (org-workflow-target-stack
            (list (org-workflow-target-entry-create
                   :marker (copy-marker (point)) :title "Current"))))
       (cl-letf (((symbol-function 'org-workflow-target-refresh)
                  (lambda (&optional _) org-workflow-target-stack))
                 ((symbol-function 'org-workflow-target--today-string)
                  (lambda () "2026-08-17"))
                 ((symbol-function 'current-time)
                  (lambda () (encode-time 0 0 20 17 8 2026))))
         ,@body))))

(ert-deftest org-workflow-target-cache-accessors-and-modeline ()
  (org-workflow-target-test-with-current
    (should (equal (org-with-point-at (org-workflow-target-current-marker)
                     (org-get-heading t t t t)) "Current"))
    (should (equal (org-workflow-target-modeline-text) "Current [1/2] -> Next [0/1]"))))

(ert-deftest org-workflow-target-refresh-keeps-clock-on-reordered-top ()
  (let ((refresh (symbol-function 'org-workflow-target-refresh)))
    (org-workflow-target-test-with-current
     (let ((old (org-workflow-target-current-marker)) called)
      (setq org-clock-marker old)
      (setq org-clock-hd-marker (copy-marker old))
      (cl-letf (((symbol-function 'org-workflow-target--sorted-entries)
                 (lambda () (list (cadr org-workflow-target-stack))))
                ((symbol-function 'org-clock-is-active) (lambda () t))
                ((symbol-function 'org-clock-out) (lambda () (setq called t))))
        (funcall refresh t)
        (should-not called))))))

(ert-deftest org-workflow-target-refresh-keeps-focus-on-reordered-top ()
  "Reordering recommendations must not stop the executing Focus task."
  (let ((refresh (symbol-function 'org-workflow-target-refresh)))
    (org-workflow-target-test-with-current
      (let ((org-workflow-clock 'org-workflow-focus-timer)
            stopped)
        (cl-letf (((symbol-function 'org-workflow-target--sorted-entries)
                   (lambda () (list (cadr org-workflow-target-stack))))
                  ((symbol-function 'org-workflow-focus-timer-active-p) (lambda () t))
                  ((symbol-function 'org-workflow-clock--clock-matches-p)
                   (lambda (_marker) t))
                  ((symbol-function 'org-workflow-focus-timer-stop)
                   (lambda () (setq stopped t))))
          (funcall refresh t)
          (should-not stopped))))))

(ert-deftest org-workflow-target-clock-commands-delegate-correctly ()
  (org-workflow-target-test-with-current
    (let ((org-workflow-clock 'org-clock)
          started continued cancelled rested)
      (cl-letf (((symbol-function 'org-clock-in) (lambda () (setq started (point))))
                ((symbol-function 'org-clock-in-last) (lambda () (interactive) (setq continued t)))
                ((symbol-function 'org-clock-cancel) (lambda () (interactive) (setq cancelled t)))
                ((symbol-function 'org-clock-is-active) (lambda () t))
                ((symbol-function 'org-clock-out) (lambda () (setq rested t))))
        (org-workflow-target-start)
        (should started)
        (setq org-clock-marker (org-workflow-target-current-marker))
        (setq org-clock-hd-marker (org-workflow-target-current-marker))
        (org-workflow-target-rest)
        (org-workflow-target-continue)
        (org-workflow-target-cancel)
        (should (and rested continued cancelled))))))

(ert-deftest org-workflow-target-clock-commands-use-focus-timer-backend ()
  "The target stack owns policy while Focus Timer owns time operations."
  (org-workflow-target-test-with-current
    (let ((org-workflow-clock 'org-workflow-focus-timer)
          started stopped continued cancelled)
      (cl-letf (((symbol-function 'org-workflow-focus-timer-start)
                 (lambda (&optional marker _select) (setq started marker)))
                ((symbol-function 'org-workflow-focus-timer-stop)
                 (lambda () (setq stopped t)))
                ((symbol-function 'org-workflow-focus-timer-start-last)
                 (lambda () (interactive) (setq continued t)))
                ((symbol-function 'org-workflow-focus-timer-cancel)
                 (lambda () (interactive) (setq cancelled t)))
                ((symbol-function 'org-workflow-focus-timer-active-p) (lambda () t))
                ((symbol-function 'org-workflow-clock--clock-matches-p)
                 (lambda (_marker) t)))
        (org-workflow-target-start)
        (org-workflow-target-rest)
        (org-workflow-target-continue)
        (org-workflow-target-cancel)
        (should (markerp started))
        (should (and stopped continued cancelled))))))

(ert-deftest org-workflow-focus-toggle-gives-inactive-desktop-call-current-target ()
  "GNOME must not ask Focus Timer to infer an unavailable buffer context."
  (org-workflow-target-test-with-current
    (let (received)
      (cl-letf (((symbol-function 'org-workflow-focus-timer-active-p) (lambda () nil))
                ((symbol-function 'org-workflow-focus-timer-toggle)
                 (lambda (&optional marker _select) (setq received marker))))
        (org-workflow-focus-toggle))
      (should (org-workflow-target--same-marker-p
               received (org-workflow-target-current-marker))))))

(ert-deftest org-workflow-focus-toggle-needs-no-target-during-active-cycle ()
  "A break or Focus transition must work even when the Workflow stack is empty."
  (let (received)
    (cl-letf (((symbol-function 'org-workflow-focus-timer-active-p) (lambda () t))
              ((symbol-function 'org-workflow-target--require-current)
               (lambda () (ert-fail "active toggle requested a Workflow target")))
              ((symbol-function 'org-workflow-focus-timer-toggle)
               (lambda (&optional marker _select) (setq received marker))))
      (org-workflow-focus-toggle))
    (should-not received)))

(ert-deftest org-workflow-target-complete-rejects-unrelated-clock ()
  (org-workflow-target-test-with-current
    (setq org-clock-marker (org-workflow-target-next-marker))
    (setq org-clock-hd-marker (org-workflow-target-next-marker))
    (cl-letf (((symbol-function 'org-clock-is-active) (lambda () t)))
      (should-error (org-workflow-target-complete) :type 'user-error)
      (should (equal (org-get-todo-state) "TODO")))))

(ert-deftest org-workflow-target-complete-records-org-closed-fact ()
  "DONE completion must leave standard Org history for journal recovery."
  (org-workflow-test-with-leaf
   (org-workflow-target-complete)
   (should (equal "DONE" (org-get-todo-state)))
   (should (org-entry-get nil "CLOSED"))))

(ert-deftest org-workflow-target-ready-is-retired-without-mutation ()
  (org-workflow-test-with-leaf
   (let ((before (buffer-string)))
     (should-error (org-workflow-target-ready) :type 'user-error)
     (should (equal before (buffer-string))))))

(ert-deftest org-workflow-manual-ready-records-ready-fact-on-scheduled-leaf ()
  "A direct TODO-to-READY change records its date and clears its schedule."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n#+TODO: TODO READY | DONE HOLD\n* Area\n** TODO Current\nSCHEDULED: <2026-08-17 Mon>\n")
   (with-current-buffer (find-file-noselect (car org-agenda-files))
     (goto-char (point-min))
     (re-search-forward "^\\*\\* TODO Current")
     (beginning-of-line)
     (org-todo "READY")
     (should (equal "2026-08-17"
                    (org-workflow-target--timestamp-date
                     (org-entry-get nil "WORKFLOW_READY_ON"))))
     (should-not (org-entry-get nil "SCHEDULED")))))

(ert-deftest org-workflow-manual-ready-leaves-unscheduled-note-unannotated ()
  "An unscheduled READY transition is not a Workflow planning outcome."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n#+TODO: TODO READY | DONE HOLD\n* Area\n** TODO Note\n")
   (with-current-buffer (find-file-noselect (car org-agenda-files))
     (goto-char (point-min))
     (re-search-forward "^\\*\\* TODO Note")
     (beginning-of-line)
     (org-todo "READY")
     (should-not (org-entry-get nil "WORKFLOW_READY_ON"))
     (should-not (org-entry-get nil "WORKFLOW_BATCH")))))

(ert-deftest org-workflow-manual-ready-does-not-annotate-top-level-task ()
  "A top-level task remains outside Workflow READY mutation policy."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n#+TODO: TODO READY | DONE HOLD\n* TODO Top-level\nSCHEDULED: <2026-08-17 Mon>\n")
   (with-current-buffer (find-file-noselect (car org-agenda-files))
     (goto-char (point-min))
     (re-search-forward "^\\* TODO Top-level")
     (beginning-of-line)
     (org-todo "READY")
     (should-not (org-entry-get nil "WORKFLOW_READY_ON"))
     (should (equal "2026-08-17"
                    (org-workflow-target--timestamp-date
                     (org-entry-get nil "SCHEDULED")))))))

(ert-deftest org-workflow-manual-ready-does-not-annotate-held-subtree ()
  "A task below HOLD remains outside Workflow READY mutation policy."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n#+TODO: TODO READY | DONE HOLD\n* Area\n** HOLD Paused\n*** TODO Child\nSCHEDULED: <2026-08-17 Mon>\n")
   (with-current-buffer (find-file-noselect (car org-agenda-files))
     (goto-char (point-min))
     (re-search-forward "^\\*\\*\\* TODO Child")
     (beginning-of-line)
     (org-todo "READY")
     (should-not (org-entry-get nil "WORKFLOW_READY_ON"))
     (should (equal "2026-08-17"
                    (org-workflow-target--timestamp-date
                     (org-entry-get nil "SCHEDULED")))))))

(ert-deftest org-workflow-target-step-empty-reveals-without-changing-the-task ()
  "An empty Executed Part is an editing handoff, not a mutation."
  (with-temp-buffer
    (org-mode)
    (insert "* TODO [#A] Current :promise:\nSCHEDULED: <2026-08-17 Mon>\n:PROPERTIES:\n:ID: current-id\n:WORKFLOW_BATCH: [2026-08-17]/minimum\n:END:\n:LOGBOOK:\nCLOCK: [2026-08-17 Mon 09:00]--[2026-08-17 Mon 09:10] =>  0:10\n:END:\nBody note.\n")
    (goto-char (point-min))
    (let ((org-workflow-target-stack
           (list (org-workflow-target-entry-create
                  :marker (copy-marker (point)) :title "Current")))
          (before (buffer-string))
          (revealed 0) prompt (refreshes 0))
      (cl-letf (((symbol-function 'org-workflow-target-refresh)
                 (lambda (&optional _) (cl-incf refreshes) org-workflow-target-stack))
                ((symbol-function 'org-workflow-target--reveal)
                 (lambda (_marker focused-frame-p)
                   (should-not focused-frame-p)
                   (cl-incf revealed)))
                ((symbol-function 'read-string)
                 (lambda (received-prompt &rest _)
                   (setq prompt received-prompt)
                   "   ")))
        (call-interactively #'org-workflow-target-step))
      (should (= 1 revealed))
      (should (equal "Executed Part: " prompt))
      ;; The one refresh obtains the current marker before revealing it.
      (should (= 1 refreshes))
      (should (equal before (buffer-string))))))

(ert-deftest org-workflow-target-step-assigns-executed-effort-without-expanding-scope ()
  "A named Executed Part receives only the source task's direct workflow facts."
  (with-temp-buffer
    (org-mode)
    (insert "* TODO [#A] Current :promise:\nSCHEDULED: <2026-08-17 Mon>\n:PROPERTIES:\n:ID: current-id\n:WORKFLOW_BATCH: [2026-08-17]/minimum\n:END:\nBody note.\n")
    (goto-char (point-min))
    (let ((org-workflow-target-stack
           (list (org-workflow-target-entry-create
                  :marker (copy-marker (point)) :title "Current"))))
      (cl-letf (((symbol-function 'org-workflow-target-refresh)
                 (lambda (&optional _) org-workflow-target-stack))
                ((symbol-function 'org-workflow-target--visit) (lambda (&optional _))))
        (org-workflow-target-step "First step")))
    (goto-char (point-min))
    (should (equal "Current [0/1]" (org-get-heading t t t t)))
    (should-not (org-entry-get nil "SCHEDULED"))
    (should-not (member "promise" (org-get-tags nil t)))
    (should (equal "current-id" (org-entry-get nil "ID")))
    (should (equal '("[2026-08-17]/minimum")
                   (org-entry-get-multivalued-property
                    nil "WORKFLOW_BATCH")))
    (should (looking-at (regexp-quote "* TODO [#A] Current")))
    (should (save-excursion
              (re-search-forward (regexp-quote "Body note.")
                                 (save-excursion (outline-next-heading) (point))
                                 t)))
    (outline-next-heading)
    (should (= 2 (org-outline-level)))
    (should (equal "TODO" (org-get-todo-state)))
    (should (equal "First step" (org-get-heading t t t t)))
    (should (member "promise" (org-get-tags nil t)))
    (should-not (org-entry-get nil "ID"))
    (should (= (org-get-priority "[#A]")
               (org-get-priority (org-get-heading))))
    (should (equal "2026-08-17"
                   (org-workflow-target--timestamp-date
                    (org-entry-get nil "SCHEDULED"))))
    (should-not (org-entry-get nil "WORKFLOW_BATCH"))
    ;; A later sibling is outside the original commitment and schedule scope.
    (goto-char (point-max))
    (insert "** TODO Later\n")
    (forward-line -1)
    (should-not (org-entry-get nil "SCHEDULED"))
    (should-not (org-workflow--promise-p))))

(ert-deftest org-workflow-target-step-moves-only-direct-clocks-into-child-logbook ()
  "CLOCK records move, while direct notes and non-CLOCK history remain put."
  (with-temp-buffer
    (org-mode)
    (insert "* TODO Current\nSCHEDULED: <2026-08-17 Mon>\n:LOGBOOK:\nCLOCK: [2026-08-17 Mon 09:00]--[2026-08-17 Mon 09:10] =>  0:10\n- State \\\"TODO\\\" from \\\"READY\\\" [2026-08-17 Mon 08:59]\n:END:\nDirect body note.\n")
    (goto-char (point-min))
    (let ((org-workflow-target-stack
           (list (org-workflow-target-entry-create
                  :marker (copy-marker (point)) :title "Current"))))
      (cl-letf (((symbol-function 'org-workflow-target-refresh)
                 (lambda (&optional _) org-workflow-target-stack))
                ((symbol-function 'org-workflow-target--visit) (lambda (&optional _))))
        (org-workflow-target-step "Worked on lecture")))
    (goto-char (point-min))
    (should-not (org-workflow--direct-clock-records))
    (let ((parent-text (buffer-substring-no-properties
                        (point) (save-excursion (outline-next-heading) (point)))))
      (should (string-match-p "State" parent-text))
      (should (string-match-p (regexp-quote "Direct body note.") parent-text)))
    (outline-next-heading)
    (should (equal '("CLOCK: [2026-08-17 Mon 09:00]--[2026-08-17 Mon 09:10] =>  0:10")
                   (mapcar (lambda (clock) (nth 2 clock))
                           (org-workflow--direct-clock-records))))))

(ert-deftest org-workflow-target-step-empty-keeps-parent-schedule-for-later-normalization ()
  "Blank Executed Part preserves parent facts until manual refinement is saved."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n* Area\n** TODO Current :promise:\nSCHEDULED: <2026-08-17 Mon>\n")
   (with-current-buffer (find-file-noselect (car org-agenda-files))
     (goto-char (point-min))
     (re-search-forward "^\\*\\* TODO Current")
     (beginning-of-line)
     (let ((parent (copy-marker (point)))
           (org-workflow-target-stack
            (list (org-workflow-target-entry-create
                   :marker (copy-marker (point)) :title "Current"))))
       (cl-letf (((symbol-function 'org-workflow-target-refresh)
                  (lambda (&optional _) org-workflow-target-stack))
                 ((symbol-function 'org-workflow-target--visit) (lambda (&optional _))))
         (org-workflow-target-step ""))
       (goto-char (point-max))
       (insert "*** TODO First\n*** TODO Second\n")
       (org-workflow-normalize-heading parent)
       (org-with-point-at parent
         (should-not (org-entry-get nil "SCHEDULED"))
         (should (member "promise" (org-get-tags nil t))))
       (goto-char (point-min))
       (re-search-forward "^\\*\\*\\* TODO First")
       (beginning-of-line)
       (should (org-entry-get nil "SCHEDULED"))
       (should (org-workflow--promise-p))
       (outline-next-heading)
       (should (org-entry-get nil "SCHEDULED"))
       (should (org-workflow--promise-p))))))

(ert-deftest org-workflow-target-step-rejects-other-clock-and-stops-matching-clock ()
  "Clock policy is validated before edits and uses only the backend wrapper."
  (with-temp-buffer
    (org-mode)
    (insert "* TODO Current\nSCHEDULED: <2026-08-17 Mon>\n")
    (goto-char (point-min))
    (let ((org-workflow-target-stack
           (list (org-workflow-target-entry-create
                  :marker (copy-marker (point)) :title "Current"))))
      (cl-letf (((symbol-function 'org-workflow-target-refresh)
                 (lambda (&optional _) org-workflow-target-stack))
                ((symbol-function 'org-workflow-target--visit) (lambda (&optional _)))
                ((symbol-function 'org-workflow-clock--clock-active-p) (lambda () t))
                ((symbol-function 'org-workflow-clock--clock-matches-p) (lambda (_marker) nil)))
        (should-error (org-workflow-target-step "Blocked") :type 'user-error))
      (should-not (save-excursion
                    (goto-char (point-min))
                    (outline-next-heading)))
      (let (stopped)
        (cl-letf (((symbol-function 'org-workflow-target-refresh)
                   (lambda (&optional _) org-workflow-target-stack))
                  ((symbol-function 'org-workflow-target--visit) (lambda (&optional _)))
                  ((symbol-function 'org-workflow-clock--clock-active-p) (lambda () t))
                  ((symbol-function 'org-workflow-clock--clock-matches-p) (lambda (_marker) t))
                  ((symbol-function 'org-workflow-clock--clock-stop) (lambda () (setq stopped t))))
          (org-workflow-target-step "Timed"))
        (should stopped)
        (goto-char (point-min))
        (should (outline-next-heading))
        (should (equal "Timed" (org-get-heading t t t t)))))))

(ert-deftest org-workflow-target-step-reads-clocks-after-closing-a-live-clock ()
  "Clock-out rewrites are transferred in their closed form without corruption."
  (with-temp-buffer
    (org-mode)
    (insert "* TODO Current\nSCHEDULED: <2026-08-17 Mon>\n:LOGBOOK:\nCLOCK: [2026-08-17 Mon 09:00]\n:END:\n")
    (goto-char (point-min))
    (let ((target (copy-marker (point)))
          (org-workflow-target-stack
           (list (org-workflow-target-entry-create
                  :marker (copy-marker (point)) :title "Current"))))
      (cl-letf (((symbol-function 'org-workflow-target-refresh)
                 (lambda (&optional _) org-workflow-target-stack))
                ((symbol-function 'org-workflow-clock--clock-active-p) (lambda () t))
                ((symbol-function 'org-workflow-clock--clock-matches-p) (lambda (_marker) t))
                ((symbol-function 'org-workflow-clock--clock-stop)
                 (lambda ()
                   (org-with-point-at target
                     (re-search-forward "^CLOCK:")
                     (let ((beginning (line-beginning-position))
                           (ending (min (point-max) (1+ (line-end-position)))))
                       (delete-region beginning ending)
                       (insert "CLOCK: [2026-08-17 Mon 09:00]--[2026-08-17 Mon 09:10] =>  0:10\n"))))))
        (org-workflow-target-step "Closed work")))
    (goto-char (point-min))
    (should-not (org-workflow--direct-clock-records))
    (let ((parent-text (buffer-substring-no-properties
                        (point) (save-excursion (outline-next-heading) (point)))))
      (should-not (string-match-p (regexp-quote ":LOGBOOK:") parent-text)))
    (outline-next-heading)
    (should (equal '("CLOCK: [2026-08-17 Mon 09:00]--[2026-08-17 Mon 09:10] =>  0:10")
                   (mapcar (lambda (clock) (nth 2 clock))
                           (org-workflow--direct-clock-records))))))

(ert-deftest org-workflow-target-step-requires-a-direct-schedule-before-clock-stop ()
  "An unscheduled target is rejected before a matching clock is stopped."
  (with-temp-buffer
    (org-mode)
    (insert "* TODO Current\n")
    (goto-char (point-min))
    (let ((org-workflow-target-stack
           (list (org-workflow-target-entry-create
                  :marker (copy-marker (point)) :title "Current")))
          (before (buffer-string))
          stopped)
      (cl-letf (((symbol-function 'org-workflow-target-refresh)
                 (lambda (&optional _) org-workflow-target-stack))
                ((symbol-function 'org-workflow-clock--clock-active-p) (lambda () t))
                ((symbol-function 'org-workflow-clock--clock-matches-p) (lambda (_marker) t))
                ((symbol-function 'org-workflow-clock--clock-stop)
                 (lambda () (setq stopped t))))
        (should-error (org-workflow-target-step "Unscheduled") :type 'user-error))
      (should-not stopped)
      (should (equal before (buffer-string))))))

(ert-deftest org-workflow-target-prerequisite-is-soft-and-transfers-local-promise ()
  "A prerequisite takes local promise without creating a hard dependency."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n* Area\n** TODO Group\n*** TODO [#A] Current :promise:\nSCHEDULED: <2026-08-17 Mon>\n:PROPERTIES:\n:WORKFLOW_BATCH: [2026-08-17]/minimum\n:END:\n")
   (with-current-buffer (find-file-noselect (car org-agenda-files))
     (goto-char (point-min))
     (re-search-forward "Current")
     (beginning-of-line)
     (let ((org-workflow-target-stack
            (list (org-workflow-target-entry-create
                   :marker (copy-marker (point)) :title "Current"))))
       (cl-letf (((symbol-function 'org-workflow-target-refresh)
                  (lambda (&optional _) org-workflow-target-stack)))
         (org-workflow-target-prerequisite "Prepare")))
     (goto-char (point-min))
     (re-search-forward "Prepare")
     (beginning-of-line)
     (should (member "promise" (org-get-tags nil t)))
     (should-not (org-entry-get nil "ID"))
     (should-not (org-entry-get nil "WORKFLOW_BATCH"))
     (should (org-entry-get nil "SCHEDULED"))
     (should (= (org-get-priority "[#A]")
                (org-get-priority (org-get-heading))))
     (outline-next-heading)
     (should-not (member "promise" (org-get-tags nil nil)))
     (should (equal '("[2026-08-17]/minimum")
                    (org-entry-get-multivalued-property
                     nil "WORKFLOW_BATCH")))
     (should-not (org-entry-get nil "WORKFLOW_BLOCKED_BY")))))

(ert-deftest org-workflow-target-prerequisite-transfers-inherited-promise-off-original-path ()
  "Inherited promise is preserved off-path and moved to the prerequisite."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n* Stage :promise:\n** TODO Selected group\n*** TODO Selected branch\n**** TODO Current :promise:\nSCHEDULED: <2026-08-17 Mon>\n*** TODO Other branch\n**** TODO Other branch leaf\nSCHEDULED: <2026-08-17 Mon>\n** TODO Other group\n*** TODO Other group leaf\nSCHEDULED: <2026-08-17 Mon>\n")
   (with-current-buffer (find-file-noselect (car org-agenda-files))
     (goto-char (point-min))
     (re-search-forward "^\\*\\*\\*\\* TODO Current")
     (beginning-of-line)
     (let ((org-workflow-target-stack
            (list (org-workflow-target-entry-create
                   :marker (copy-marker (point)) :title "Current"))))
       (cl-letf (((symbol-function 'org-workflow-target-refresh)
                  (lambda (&optional _) org-workflow-target-stack)))
         (org-workflow-target-prerequisite "Prepare")))
     (goto-char (point-min))
     (re-search-forward "^\\* Stage")
     (beginning-of-line)
     (should-not (member "promise" (org-get-tags nil t)))
     (re-search-forward "^\\*\\* TODO Other group")
     (beginning-of-line)
     (should (member "promise" (org-get-tags nil t)))
     (goto-char (point-min))
     (re-search-forward "^\\*\\*\\* TODO Other branch")
     (beginning-of-line)
     (should (member "promise" (org-get-tags nil t)))
     (goto-char (point-min))
     (re-search-forward "^\\*\\*\\*\\* TODO Prepare")
     (beginning-of-line)
     (should (member "promise" (org-get-tags nil t)))
     (outline-next-heading)
     (should (equal "Current" (org-get-heading t t t t)))
     (should-not (member "promise" (org-get-tags nil nil))))))

(ert-deftest org-workflow-target-prerequisite-is-soft-and-keeps-outline-order ()
  "Prepare and Current remain independent scheduled leaves in source order."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n* Area\n** TODO Group\n*** TODO Current\nSCHEDULED: <2026-08-17 Mon>\n")
   (with-current-buffer (find-file-noselect (car org-agenda-files))
     (goto-char (point-min))
     (re-search-forward "^\\*\\*\\* TODO Current")
     (beginning-of-line)
     (let ((org-workflow-target-stack
            (list (org-workflow-target-entry-create
                   :marker (copy-marker (point)) :title "Current"))))
       (cl-letf (((symbol-function 'org-workflow-target-refresh)
                  (lambda (&optional _) org-workflow-target-stack)))
         (org-workflow-target-prerequisite "Prepare")))
     (goto-char (point-min))
     (re-search-forward "^\\*\\*\\* TODO Prepare")
     (beginning-of-line)
     (should (org-entry-get nil "SCHEDULED"))
     (outline-next-heading)
     (should (equal "Current" (org-get-heading t t t t)))
     (should (org-entry-get nil "SCHEDULED")))
   (should (equal '("Current" "Prepare")
                  (mapcar #'org-workflow-target-entry-title
                          (org-workflow-target--collect))))))

(ert-deftest org-workflow-direct-schedule-ignores-legacy-blocker-metadata ()
  "A direct rolling schedule admits a task without inspecting its blocker."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n#+TODO: TODO READY | DONE HOLD\n* Area\n** TODO Group\n*** TODO Prepare\nSCHEDULED: <2026-08-17 Mon>\n:PROPERTIES:\n:ID: blocker-id\n:END:\n*** TODO Current\nSCHEDULED: <2026-08-17 Mon>\n:PROPERTIES:\n:WORKFLOW_BLOCKED_BY: blocker-id\n:END:\n")
   (should (equal '("Current" "Prepare")
                  (mapcar #'org-workflow-target-entry-title
                          (org-workflow-target--collect))))
   (with-current-buffer (find-file-noselect (car org-agenda-files))
     (goto-char (point-min))
     (re-search-forward "^\\*\\*\\* TODO Prepare")
     (beginning-of-line)
     (org-todo "READY")
     (should (equal '("Current")
                    (mapcar #'org-workflow-target-entry-title
                            (org-workflow-target--collect))))
     (org-todo "HOLD")
     (should (equal '("Current")
                    (mapcar #'org-workflow-target-entry-title
                            (org-workflow-target--collect))))
     (org-todo "DONE"))
   (should (equal '("Current")
                  (mapcar #'org-workflow-target-entry-title
                          (org-workflow-target--collect))))))

(ert-deftest org-workflow-target-visit-reveals-current-source-body ()
  "Visit narrows to the current task's body without changing its contents."
  (org-workflow-test-with-leaf
   (goto-char (point-max))
   (insert ":PROPERTIES:\n:EFFORT: 0:25\n:END:\nTask body.\n")
   (let ((source (buffer-string)))
     (save-window-excursion
       (org-workflow-target-visit)
       (should (looking-at-p "Task body\\."))
       (should (buffer-narrowed-p))
       (save-excursion
         (goto-char (point-min))
         (should (org-at-heading-p))
         (should (equal "Current" (org-get-heading t t t t)))
         (should (org-entry-get nil "SCHEDULED")))
       (save-restriction
         (widen)
         (should (equal source (buffer-string))))))))

(ert-deftest org-workflow-target-visit-preserves-an-existing-window-layout ()
  "The in-Emacs visit command must not collapse the user's window layout."
  (org-workflow-test-with-leaf
   (let ((target-buffer (current-buffer))
         (other-buffer (generate-new-buffer " *org-workflow-other*")))
     (unwind-protect
         (save-window-excursion
           (delete-other-windows)
           (set-window-buffer (selected-window) other-buffer)
           (set-window-buffer (split-window-below) target-buffer)
           (select-window (get-buffer-window other-buffer))
           (org-workflow-target-visit)
           (should (= 2 (length (window-list)))))
       (kill-buffer other-buffer)))))

(ert-deftest org-workflow-new-graphical-frame-visits-current-target ()
  "A new graphical frame should show today's target in its only window."
  (org-workflow-test-with-leaf
   (let ((target-buffer (current-buffer))
         (scratch-buffer (generate-new-buffer " *org-workflow-scratch*"))
         (sidebar-buffer (generate-new-buffer " *org-workflow-sidebar*")))
     (unwind-protect
         (save-window-excursion
           (delete-other-windows)
           (let* ((main-window (selected-window))
                  (side-window
                   (display-buffer-in-side-window
                    sidebar-buffer '((side . right)))))
             (set-window-buffer main-window scratch-buffer)
             (set-window-parameter side-window 'no-delete-other-windows t)
             (select-window main-window)
             (cl-letf (((symbol-function 'display-graphic-p)
                        (lambda (&optional _frame) t)))
               (org-workflow--visit-current-target-in-new-frame))
             (should (= 1 (length (window-list))))
             (should (eq target-buffer (window-buffer (selected-window))))
             (should (buffer-narrowed-p))))
       (kill-buffer scratch-buffer)
       (kill-buffer sidebar-buffer)))))

(ert-deftest org-workflow-new-frame-keeps-default-buffer-without-current-target ()
  "A new frame must remain usable on days without a current target."
  (let (visited)
    (cl-letf (((symbol-function 'display-graphic-p)
               (lambda (&optional _frame) t))
              ((symbol-function 'org-workflow-target-visit)
               (lambda () (setq visited t) (user-error "No current task"))))
      (should-not (org-workflow--visit-current-target-in-new-frame))
      (should visited))))

(ert-deftest org-workflow-capture-frame-does-not-visit-current-target ()
  "A dedicated capture frame must remain available to `org-capture'."
  (let (visited)
    (cl-letf (((symbol-function 'display-graphic-p)
               (lambda (&optional _frame) t))
              ((symbol-function 'frame-parameter)
               (lambda (_frame parameter)
                 (when (eq parameter 'name) "capture")))
              ((symbol-function 'org-workflow-target-visit)
               (lambda () (setq visited t))))
      (should-not (org-workflow--visit-current-target-in-new-frame))
      (should-not visited))))

(ert-deftest org-workflow-desktop-visit-uses-a-focused-single-window ()
  "An external visit must remove unrelated normal and side windows."
  (org-workflow-test-with-leaf
   (let ((target-buffer (current-buffer))
         (scratch-buffer (generate-new-buffer " *org-workflow-scratch*"))
         (sidebar-buffer (generate-new-buffer " *org-workflow-sidebar*")))
     (unwind-protect
         (save-window-excursion
           (delete-other-windows)
           (let* ((main-window (selected-window))
                  (side-window
                   (display-buffer-in-side-window
                    sidebar-buffer '((side . right)))))
             (set-window-buffer main-window scratch-buffer)
             (set-window-parameter side-window 'no-delete-other-windows t)
             (select-window main-window)
             (should (= 2 (length (window-list))))
             (should (equal '(:ok t :action visit)
                            (org-workflow--dispatch-in-frame
                             (selected-frame) 'visit)))
             (should (= 1 (length (window-list))))
             (should (eq target-buffer
                         (window-buffer (selected-window))))
             (should (buffer-narrowed-p))))
       (kill-buffer scratch-buffer)
       (kill-buffer sidebar-buffer)))))

(ert-deftest org-workflow-desktop-visit-narrows-and-places-point-in-body ()
  "An external visit narrows the leaf and skips its metadata."
  (with-temp-buffer
    (org-mode)
    (insert "* Area\n** TODO Current\nSCHEDULED: <2026-08-17 Mon>\n:PROPERTIES:\n:X: hidden\n:END:\n\nRead section 2.1.\n")
    (goto-char (point-min))
    (re-search-forward "^\\*\\* TODO Current")
    (beginning-of-line)
    (let ((org-workflow-target-stack
           (list (org-workflow-target-entry-create
                  :marker (copy-marker (point)) :title "Current"))))
      (cl-letf (((symbol-function 'org-workflow-target-refresh)
                 (lambda (&optional _) org-workflow-target-stack)))
        (org-workflow--visit-in-frame)
        (should (buffer-narrowed-p))
        (should (equal "Read section 2.1."
                       (string-trim-right (thing-at-point 'line t))))))))

(ert-deftest org-workflow-step-frame-action-reveals-before-reading-executed-part ()
  "The desktop step action gives its minibuffer prompt a visible task frame."
  (let ((marker (make-marker)) (revealed 0) title)
    (cl-letf (((symbol-function 'org-workflow-target--require-current)
               (lambda () marker))
              ((symbol-function 'org-workflow-target--reveal)
               (lambda (received-marker focused-frame-p)
                 (should (eq marker received-marker))
                 (should focused-frame-p)
                 (cl-incf revealed)))
              ((symbol-function 'org-workflow-target--read-executed-part)
               (lambda ()
                 (should (= 1 revealed))
                 "Worked on lecture"))
              ((symbol-function 'org-workflow-target--step)
               (lambda (value received-marker)
                 (setq title (list value received-marker)))))
      (should (eq #'org-workflow--step-in-frame
                  (alist-get 'step org-workflow-external-actions)))
      (org-workflow--step-in-frame)
      (should (= 1 revealed))
      (should (equal (list "Worked on lecture" marker) title)))))

(ert-deftest org-workflow-statistics-completes-todo-parents-recursively ()
  "Org statistics should close TODO containers but leave plain headings alone."
  (with-temp-buffer
    (org-mode)
    (insert "* Plain\n** TODO Parent [0/1]\n*** TODO Child\n")
    (goto-char (point-min))
    (re-search-forward "^\\*\\*\\* TODO Child")
    (beginning-of-line)
    (org-todo "DONE")
    (org-up-heading-safe)
    (should (equal "DONE" (org-get-todo-state)))
    (org-up-heading-safe)
    (should-not (org-get-todo-state))))

(ert-deftest org-workflow-status-reports-clean-task-and-journal-progress ()
  "The read API composes live task facts with journal-owned daily progress."
  (with-temp-buffer
    (org-mode)
    (insert "* Stage\n** TODO Group [1/3]\n*** TODO Current\nSCHEDULED: <2026-08-17 Mon>\n:PROPERTIES:\n:X: hidden\n:END:\n:LOGBOOK:\nCLOCK: [2026-08-17 Mon 09:00]--[2026-08-17 Mon 09:10] =>  0:10\n:END:\nRead section 2.1.\n")
    (goto-char (point-min))
    (re-search-forward "^\\*\\*\\* TODO Current")
    (beginning-of-line)
    (let ((org-workflow-target-stack
           (list (org-workflow-target-entry-create
                  :marker (copy-marker (point)) :title "Current")))
          (org-agenda-files nil)
          (org-workflow-status-provider-function
           (lambda (_date)
             (list :minimumSatisfied 2 :minimumTotal 3
                   :phase "minimum" :commitmentComplete :false)))
          (org-workflow-commitment-streak-provider-function
           (lambda (_date _daily) 7)))
      (let ((status (org-workflow-status)))
        (should (equal "Current" (plist-get status :task)))
        (should (equal "Group" (plist-get status :parent)))
        (should (equal "1/3" (plist-get status :parentProgress)))
        (should (equal "Read section 2.1." (plist-get status :body)))
        (should (= 2 (plist-get status :minimumSatisfied)))
        (should (= 3 (plist-get status :minimumTotal)))
        (should (= 7 (plist-get status :commitmentStreak)))
        (should (= 0 (plist-get status :stageSatisfied)))
        (should (= 0 (plist-get status :stageTotal)))))))

(ert-deftest org-workflow-status-json-preserves-nonascii-for-emacsclient ()
  "Desktop JSON remains valid when workflow text contains non-ASCII data."
  (with-temp-buffer
    (org-mode)
    (insert "* TODO Current\n- Note taken on [2026-08-27 四 16:26] \\\\\n  测试\n")
    (goto-char (point-min))
    (let ((org-workflow-target-stack
           (list (org-workflow-target-entry-create
                  :marker (copy-marker (point)) :title "Current")))
          (org-agenda-files nil)
          (org-workflow-status-provider-function
           (lambda (_date)
             (list :minimumSatisfied 0 :minimumTotal 1
                   :phase "minimum" :commitmentComplete :false)))
          (org-workflow-commitment-streak-provider-function
           (lambda (_date _daily) 4)))
      (let ((json (org-workflow-status-json)))
        (should (multibyte-string-p json))
        (should
         (equal "- Note taken on [2026-08-27 四 16:26] \\\\\n  测试"
                (plist-get (json-parse-string json :object-type 'plist)
                           :body)))
        (should (= 4 (plist-get (json-parse-string json :object-type 'plist)
                                 :commitmentStreak)))))))

(ert-deftest org-workflow-cache-hooks-fire-only-on-state-edges ()
  "Consumers receive current-change and nonempty-to-empty transitions once."
  (with-temp-buffer
    (org-mode)
    (insert "* TODO First\n* TODO Second\n")
    (goto-char (point-min))
    (let* ((first (org-workflow-target-entry-create
                   :marker (copy-marker (point)) :title "First"))
           (second (org-workflow-target-entry-create
                    :marker (copy-marker
                             (save-excursion (outline-next-heading) (point)))
                    :title "Second"))
           (org-workflow-target-stack (list first))
           (next (list second))
           (changed 0)
           (emptied 0)
           (org-workflow-current-changed-hook
            (list (lambda () (cl-incf changed))))
           (org-workflow-stack-empty-hook
            (list (lambda () (cl-incf emptied)))))
      (cl-letf (((symbol-function 'org-workflow-target--sorted-entries)
                 (lambda () next)))
        (org-workflow-target-refresh t)
        (org-workflow-target-refresh t)
        (setq next nil)
        (org-workflow-target-refresh t))
      (should (= 2 changed))
      (should (= 1 emptied)))))

(ert-deftest org-workflow-gnome-sync-is-a-failure-tolerant-empty-signal ()
  "Workflow invalidation carries no state and cannot break Org mutations."
  (let (sent)
    (cl-letf (((symbol-function 'dbus-send-signal)
               (lambda (&rest args) (setq sent args))))
      (org-workflow--request-gnome-refresh))
    (should (equal '(:session nil
                     "/io/github/meph1st0/OrgWorkflow"
                     "io.github.meph1st0.OrgWorkflow" "Changed")
                   sent)))
  (cl-letf (((symbol-function 'dbus-send-signal)
             (lambda (&rest _) (error "session bus unavailable"))))
    (should-not (org-workflow--request-gnome-refresh))))

(ert-deftest org-workflow-target-clock-match-uses-clock-heading-marker ()
  "A running clock is recorded below its heading, not on the heading itself."
  (org-workflow-target-test-with-current
    (let ((target (org-workflow-target-current-marker)))
      (let ((org-clock-marker
             (save-excursion (goto-char target) (forward-line 2) (copy-marker (point))))
            (org-clock-hd-marker (copy-marker target)))
        (cl-letf (((symbol-function 'org-clock-is-active) (lambda () t)))
          (should-not (org-workflow-target--same-marker-p org-clock-marker target))
          (should (org-workflow-target--clock-matches-p target)))))))

(ert-deftest org-workflow-target-defer-lowers-only-current-leaf ()
  "Lowercase deferral changes only the current atomic task."
  (with-temp-buffer
    (org-mode)
    (insert "* Stage\n** TODO Group\n*** TODO [#A] Current\nSCHEDULED: <2026-08-17 Mon>\n*** TODO [#A] Sibling\nSCHEDULED: <2026-08-17 Mon>\n")
    (goto-char (point-min))
    (re-search-forward "^\\*\\*\\* TODO \\[#A\\] Current")
    (beginning-of-line)
    (let ((org-workflow-target-stack
           (list (org-workflow-target-entry-create
                  :marker (copy-marker (point)) :title "Current"))))
      (cl-letf (((symbol-function 'org-workflow-target-refresh)
                 (lambda (&optional _) org-workflow-target-stack)))
        (org-workflow-target-defer)))
    (should (= (org-get-priority "[#C]")
               (org-get-priority (org-get-heading))))
    (outline-next-heading)
    (should (= (org-get-priority "[#A]")
               (org-get-priority (org-get-heading))))))

(ert-deftest org-workflow-target-defer-group-lowers-todays-sibling-leaves ()
  "Uppercase deferral changes today's unfinished direct-parent group only."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n* Area\n** TODO Group\n*** TODO [#A] Current\nSCHEDULED: <2026-08-17 Mon>\n*** TODO [#B] Sibling\nSCHEDULED: <2026-08-17 Mon>\n*** TODO [#A] Unscheduled\n** TODO Other group\n*** TODO [#A] Other\nSCHEDULED: <2026-08-17 Mon>\n")
   (with-current-buffer (find-file-noselect (car org-agenda-files))
     (goto-char (point-min))
     (re-search-forward "^\\*\\*\\* TODO \\[#A\\] Current")
     (beginning-of-line)
     (let ((org-workflow-target-stack
            (list (org-workflow-target-entry-create
                   :marker (copy-marker (point)) :title "Current"))))
       (cl-letf (((symbol-function 'org-workflow-target-refresh)
                  (lambda (&optional _) org-workflow-target-stack)))
         (org-workflow-target-defer-group)))
     (let (priorities)
       (org-map-entries
        (lambda ()
          (push (cons (org-get-heading t t t t)
                      (org-get-priority (org-get-heading)))
                priorities))
        "+TODO=\"TODO\"" 'file)
       (should (= (org-get-priority "[#C]")
                  (alist-get "Current" priorities nil nil #'equal)))
       (should (= (org-get-priority "[#C]")
                  (alist-get "Sibling" priorities nil nil #'equal)))
       (should (= (org-get-priority "[#A]")
                  (alist-get "Unscheduled" priorities nil nil #'equal)))
       (should (= (org-get-priority "[#A]")
                  (alist-get "Other" priorities nil nil #'equal)))))))

(ert-deftest org-workflow-target-defer-bindings-distinguish-leaf-and-group ()
  (should (eq (key-binding (kbd "C-c o d")) #'org-workflow-target-defer))
  (should (eq (key-binding (kbd "C-c o D")) #'org-workflow-target-defer-group)))

(ert-deftest org-workflow-global-bindings-do-not-own-timer-operations ()
  "The Org Workflow prefix must not advertise Focus Timer wrappers."
  (dolist (key '("C-c o s" "C-c o r" "C-c o g" "C-c o k"))
    (should-not
     (memq (lookup-key global-map (kbd key))
           '(org-workflow-target-start org-workflow-target-rest
             org-workflow-target-continue org-workflow-target-cancel)))))

(ert-deftest org-workflow-dispatch-routes-desktop-toggle-through-integration ()
  "The validated desktop boundary must expose the unified timer action."
  (let (called)
    (cl-letf (((symbol-function 'org-workflow-focus-toggle)
               (lambda () (interactive) (setq called t))))
      (should (equal '(:ok t :action toggle)
                     (org-workflow-dispatch 'toggle)))
      (should called))))

(ert-deftest org-workflow-dispatch-invokes-registered-action-interactively ()
  "External actions must honor their interactive parameter readers."
  (let (received-title)
    (cl-letf (((symbol-function 'org-workflow-target-prerequisite)
               (lambda (title)
                 (interactive (list "Prepare first"))
                 (setq received-title title))))
      (should (equal '(:ok t :action prerequisite)
                     (org-workflow-dispatch 'prerequisite)))
      (should (equal "Prepare first" received-title)))))

(ert-deftest org-workflow-dispatch-in-frame-defers-interactive-work ()
  "A desktop client must return before a frame action enters the minibuffer."
  (let (timer-delay timer-function timer-arguments received-title)
    (cl-letf (((symbol-function 'run-at-time)
               (lambda (delay _repeat function &rest arguments)
                 (setq timer-delay delay
                       timer-function function
                       timer-arguments arguments)
                 'fake-timer))
              ((symbol-function 'org-workflow-target-prerequisite)
               (lambda (title)
                 (interactive (list "Prepare first"))
                 (setq received-title title))))
      (should (equal '(:queued t :action prerequisite)
                     (org-workflow-dispatch-in-frame 'prerequisite)))
      (should (= 0.1 timer-delay))
      (should (eq #'org-workflow--dispatch-in-frame timer-function))
      (should (eq (selected-frame) (car timer-arguments)))
      (should (equal 'prerequisite (cadr timer-arguments)))
      (should-not received-title)
      (apply timer-function timer-arguments)
      (should (equal "Prepare first" received-title)))))

(ert-deftest org-workflow-dispatch-in-frame-rejects-unregistered-actions-early ()
  "Do not queue arbitrary commands behind the desktop action boundary."
  (let (scheduled)
    (cl-letf (((symbol-function 'run-at-time)
               (lambda (&rest _arguments) (setq scheduled t))))
      (should-error (org-workflow-dispatch-in-frame 'erase-buffer)
                    :type 'user-error)
      (should-not scheduled))))

(ert-deftest org-workflow-dispatch-notifies-and-returns-action-errors ()
  "GNOME callers should receive visible feedback instead of a silent failure."
  (let (notification)
    (cl-letf (((symbol-function 'org-workflow-target-start)
               (lambda () (interactive) (user-error "No current task")))
              ((symbol-function 'org-workflow--notify)
               (lambda (title body) (setq notification (list title body)))))
      (should (equal '(:ok nil :action start :error "No current task")
                     (org-workflow-dispatch 'start)))
      (should (equal '("Org Workflow" "No current task") notification)))))

(ert-deftest org-workflow-dispatch-rejects-unregistered-actions ()
  "The desktop boundary must not evaluate arbitrary Emacs commands."
  (let (notification)
    (cl-letf (((symbol-function 'org-workflow--notify)
               (lambda (title body) (setq notification (list title body)))))
      (should (equal '(:ok nil :action erase-buffer
                           :error "Unknown Org Workflow action: erase-buffer")
                     (org-workflow-dispatch 'erase-buffer)))
      (should (equal '("Org Workflow"
                       "Unknown Org Workflow action: erase-buffer")
                     notification)))))

(ert-deftest org-workflow-current-target-capture-template-is-a-todo-with-context ()
  "The current-target capture template keeps content and its source together."
  (should
   (equal "- [ ] %?\n  %a"
          (nth 4 (assoc "c" org-capture-templates)))))

(ert-deftest org-workflow-target-capture-adds-body-note-without-new-heading ()
  "Capturing to the current task adds a TODO item, not a child."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n* TODO Current\nSCHEDULED: <2026-08-17 Mon>\n** DONE Finished\n** TODO Open\n")
   (let* ((target-buffer (find-file-noselect (car org-agenda-files)))
          (marker (with-current-buffer target-buffer
                    (goto-char (point-min))
                    (re-search-forward "^\\* TODO Current")
                    (beginning-of-line)
                    (copy-marker (point))))
          (org-workflow-target-stack
           (list (org-workflow-target-entry-create :marker marker
                                             :title "Current")))
          (org-capture-mode-hook nil)
          capture-buffer)
     (cl-letf (((symbol-function 'org-workflow-target-refresh)
                (lambda (&optional _) org-workflow-target-stack))
               ((symbol-function 'current-time)
                (lambda () (encode-time 0 2 16 27 8 2026)))
               (system-time-locale "C"))
       (let ((heading-count
              (with-current-buffer target-buffer
                (how-many org-heading-regexp (point-min) (point-max)))))
         (unwind-protect
             (progn
               (org-capture nil "c")
               (setq capture-buffer (current-buffer))
               (insert "foo")
               (with-current-buffer target-buffer
                 (should (= heading-count
                            (how-many org-heading-regexp
                                      (point-min) (point-max))))
                 (goto-char (point-min))
                 (re-search-forward "^\\* TODO Current")
                 (beginning-of-line)
                 (let ((first-child (save-excursion
                                      (outline-next-heading)
                                      (point))))
                   (should
                    (re-search-forward
                     (regexp-quote
                      "- [ ] foo")
                     first-child t)))))
           (when (buffer-live-p capture-buffer)
             (with-current-buffer capture-buffer
               (org-capture-kill)))))))))

(defun note-gtd-target-test--open-columns ()
  "Enable actual independent planning panes in the current test workbench."
  (let ((org-workflow-agenda-column-min-width 20))
    (org-workflow-agenda--set-setting 'org-workflow-agenda-columns-enabled t)
    (org-workflow-agenda--apply-columns)))

(defun note-gtd-target-test--workbench-text ()
  "Read the schedule then candidate pane for cross-pane assertions."
  (mapconcat (lambda (buffer) (with-current-buffer buffer (buffer-string)))
             (org-workflow-agenda--workbench-buffers) "\n"))

(ert-deftest note-gtd-sprint-renders-independent-candidates-and-scheduled-leaves ()
  "Sprint shows every priority band and only plannable Current leaves."
  (org-workflow-target-test-with-files
   '("#+filetags: :project:
#+category: Lute-reborn
#+TODO: TODO READY | DONE HOLD
* DIVE Milestone
** DIVE [#A] Relating :promise:@deep:
*** TODO [#A] Packages, Please
SCHEDULED: <2026-08-17 Mon>
*** TODO [#A] Unscheduled book :@tiny:
*** TODO [#A] Tomorrow book
SCHEDULED: <2026-08-18 Tue>
** DIVE Container only
*** TODO Leaf to plan
** READY Ready leaf
** HOLD Paused
*** TODO Hidden unscheduled
* Backlog
** TODO Outside current
"
     "#+filetags: :area:
#+category: CS_61C
#+TODO: TODO READY | DONE HOLD
* DIVE Practice
** TODO [#B] Summary
SCHEDULED: <2026-08-17 Mon>
** TODO Tune cache :@flow:
")
   (cl-letf (((symbol-function 'current-time)
              (lambda () (encode-time 0 0 9 17 8 2026))))
     (org-workflow-target-refresh t)
     (should (= 1 (length org-workflow-target-stack)))
     (org-agenda nil "d")
     (should (= 1 (length org-workflow-target-stack))))
   (with-current-buffer org-agenda-buffer-name
     (note-gtd-target-test--open-columns)
     (let ((inhibit-read-only t))
       (org-modern-agenda))
     (let* ((text (note-gtd-target-test--workbench-text))
            (stack-header (string-match "今日安排" text))
            (lute-group (string-match "Relating  Lute-reborn" text stack-header))
            (first-task
             (string-match "Packages, Please[ ]+:@deep:" text))
            (area-group (string-match "Practice  CS_61C" text stack-header))
            (second-task (string-match "Summary" text))
            (planning-header (string-match "待安排" text)))
       (should stack-header)
       (should lute-group)
       (should first-task)
       (should area-group)
       (should second-task)
       (should planning-header)
       (should (< stack-header lute-group first-task
                  area-group second-task planning-header))
       (goto-char (+ (point-min) lute-group))
       (should (eq 'org-workflow-agenda-group (get-text-property (point) 'face)))
       (goto-char (+ (point-min) area-group))
       (should (eq 'org-workflow-agenda-group (get-text-property (point) 'face)))
       (should (string-match-p "上午" text))
       (should (string-match-p "下午" text))
       (should-not (string-match-p "\\[#" text))
       (should (string-match-p ":@flow:" text))
       (should (string-match-p "@tiny" text))
       (goto-char (+ (point-min) first-task))
       (should (eq 'todo (org-get-at-bol 'org-agenda-type)))
       (should (org-get-at-bol 'org-hd-marker))
       (dolist (title '("Unscheduled book" "Leaf to plan" "Tune cache"))
         (with-current-buffer (org-workflow-agenda-workbench-candidates org-workflow-agenda--workbench)
           (goto-char (point-min)) (search-forward title) (beginning-of-line)
           (should (org-get-at-bol 'org-marker))))
       (dolist (hidden '("Day-agenda" "Project Current Tasks"
                         "Area Current Tasks" "Tomorrow book" "Ready leaf"
                         "Hidden unscheduled" "Outside current"
                         "TODO" ":CURR:" "===="))
         (should-not (string-match-p hidden text)))
       (should (= 1 (how-many "Packages, Please" (point-min) (point-max))))
       (should (= 1 (how-many "Summary" (point-min) (point-max))))
       (should (string-match-p "◇ Packages, Please" text))
       (should-not (string-match-p ":promise:" text))))))

(defun note-gtd-target-test--goto-agenda-title (title)
  "Move to TITLE in the current pane, opening the planning pane if necessary."
  (goto-char (point-min))
  (unless (search-forward title nil t)
    (unless (buffer-live-p (org-workflow-agenda-workbench-candidates org-workflow-agenda--workbench))
      (note-gtd-target-test--open-columns))
    (let (found)
      (dolist (buffer (org-workflow-agenda--workbench-buffers))
        (with-current-buffer buffer
          (goto-char (point-min))
          (when (search-forward title nil t) (setq found (cons buffer (point))))))
      (unless found (ert-fail (concat "Missing workbench task: " title)))
      (set-buffer (car found)) (goto-char (cdr found))))
  (beginning-of-line)
  (setq-local org-agenda-type (org-get-at-bol 'org-agenda-type)))

(ert-deftest note-gtd-agenda-schedule-today-moves-leaf-to-stack ()
  "Scheduling a planning candidate today moves it into the real stack."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:
#+category: emacs
#+TODO: TODO READY | DONE HOLD
* DIVE Configuration
** TODO Agenda View Customization
")
   (org-workflow-target-refresh t)
   (org-agenda nil "d")
   (with-current-buffer org-agenda-buffer-name
     (note-gtd-target-test--goto-agenda-title "Agenda View Customization")
     (org-workflow-agenda-schedule-today)
     (set-buffer (org-workflow-agenda-workbench-primary org-workflow-agenda--workbench))
     (let* ((text (note-gtd-target-test--workbench-text))
            (stack (string-match "今日安排" text))
            (task (string-match "Agenda View Customization" text))
            (planning (string-match "待安排" text)))
       (should stack)
       (should task)
       (should planning)
       (should (< stack task planning))
       (should (= 1 (how-many "Agenda View Customization"
                              (point-min) (point-max))))))
   (with-current-buffer (find-file-noselect (car org-agenda-files))
     (goto-char (point-min))
     (search-forward "Agenda View Customization")
     (should (equal "<2026-08-17 Mon>"
                    (org-entry-get nil "SCHEDULED"))))))

(ert-deftest note-gtd-agenda-schedule-tomorrow-removes-planning-candidate ()
  "Scheduling tomorrow removes the candidate until the target day is selected."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:
#+category: emacs
#+TODO: TODO READY | DONE HOLD
* DIVE Configuration
** TODO Plan tomorrow
")
   (org-workflow-target-refresh t)
   (org-agenda nil "d")
   (with-current-buffer org-agenda-buffer-name
     (note-gtd-target-test--goto-agenda-title "Plan tomorrow")
     (org-workflow-agenda-schedule-tomorrow)
     (should-not (string-match-p "Plan tomorrow" (buffer-string)))
     (org-workflow-agenda-set-day t)
     (set-buffer (org-workflow-agenda-workbench-primary org-workflow-agenda--workbench))
     (note-gtd-target-test--goto-agenda-title "Plan tomorrow")
     (should (org-get-at-bol 'org-hd-marker))
     (should (string-match-p "Plan tomorrow" (thing-at-point 'line t)))
     (let ((text (buffer-substring-no-properties (point-min) (point-max))))
       (should (< (string-match "明日安排" text)
                  (string-match "Plan tomorrow" text)))))
   (with-current-buffer (find-file-noselect (car org-agenda-files))
     (goto-char (point-min))
     (search-forward "Plan tomorrow")
     (should (equal "<2026-08-18 Tue>"
                    (org-entry-get nil "SCHEDULED"))))))

(ert-deftest note-gtd-agenda-unschedule-moves-task-to-planning-section ()
  "Removing today's schedule makes a Current leaf plannable again."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:
#+category: emacs
#+TODO: TODO READY | DONE HOLD
* DIVE Configuration
** TODO Reschedule me
SCHEDULED: <2026-08-17 Mon>
")
   (org-workflow-target-refresh t)
   (org-agenda nil "d")
   (with-current-buffer org-agenda-buffer-name
     (note-gtd-target-test--goto-agenda-title "Reschedule me")
     (org-workflow-agenda-unschedule)
     (note-gtd-target-test--goto-agenda-title "Reschedule me")
     (let* ((text (note-gtd-target-test--workbench-text))
            (stack (string-match "今日安排" text))
            (planning (string-match "待安排" text))
            (task (string-match "Reschedule me" text planning)))
       (should stack)
       (should planning)
       (should task)
       (should (< stack planning task))))
   (with-current-buffer (find-file-noselect (car org-agenda-files))
     (goto-char (point-min))
     (search-forward "Reschedule me")
     (should-not (org-entry-get nil "SCHEDULED")))))

(ert-deftest note-gtd-agenda-priority-actions-regroup-and-clear ()
  "Flat priority actions persist changes and clearing restores inheritance."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:
#+TODO: TODO READY | DONE HOLD
* DIVE [#C] Configuration
** TODO Reprioritize
SCHEDULED: <2026-08-17 Mon>
")
   (org-agenda nil "d")
   (dolist (action '((org-workflow-agenda-priority-a . ?A)
                     (org-workflow-agenda-priority-b . ?B)
                     (org-workflow-agenda-priority-c . ?C)
                     (org-workflow-agenda-priority-clear . ?C)))
     (with-current-buffer org-agenda-buffer-name
       (note-gtd-target-test--goto-agenda-title "Reprioritize")
       (funcall (car action))
       (should (string-match-p
                (cdr (assq (cdr action) '((?A . "上午") (?B . "下午") (?C . "晚上"))))
                (buffer-substring-no-properties (point-min) (point-max)))))
     (with-current-buffer (find-file-noselect (car org-agenda-files))
       (goto-char (point-min))
       (search-forward "Reprioritize")
       (should (equal "TODO" (org-get-todo-state)))
       (if (eq (car action) 'org-workflow-agenda-priority-clear)
           (should (equal "Reprioritize" (org-get-heading t t nil t)))
         (should (string-match-p (format "\\[#%c\\]" (cdr action))
                                 (org-get-heading t t nil t))))))))

(ert-deftest note-gtd-agenda-task-controls-are-direct-and-mouse-friendly ()
  "Sprint exposes one-key actions while preserving the right mouse action."
  (should (eq #'org-workflow-agenda-view-menu
              (lookup-key org-agenda-mode-map (kbd "a"))))
  (should (eq #'org-agenda-goto-mouse
              (lookup-key org-agenda-mode-map [mouse-1])))
  (should (eq #'org-workflow-agenda-schedule-today-mouse
              (lookup-key org-agenda-mode-map [mouse-2])))
  (should (eq #'org-agenda-show-mouse
              (lookup-key org-agenda-mode-map [mouse-3])))
  (dolist (command '(org-workflow-agenda-filter-tiny org-workflow-agenda-filter-flow
                                               org-workflow-agenda-filter-deep org-workflow-agenda-filter-promise
                                               org-workflow-agenda-filter-clear org-workflow-agenda-open-workbench
                                               org-workflow-agenda-toggle-planning-scope
                                               org-workflow-agenda-toggle-completed))
    (should (transient-get-suffix 'org-workflow-agenda-view-menu command)))
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n* DIVE Parent\n** TODO Candidate\n")
   (org-agenda nil "d")
   (with-current-buffer org-agenda-buffer-name
    (dolist (binding '(("u" . org-workflow-agenda-plan-morning)
                     ("i" . org-workflow-agenda-plan-afternoon)
                     ("o" . org-workflow-agenda-plan-evening)
                     ("r" . org-workflow-agenda-unschedule)))
    (should (eq (cdr binding)
                (lookup-key (current-local-map) (kbd (car binding)))))))))

(ert-deftest note-gtd-agenda-future-collection-bounded-but-hidden-in-sprint ()
  "Future metadata is retained; Sprint only shows its selected day."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:
#+category: Test
#+TODO: TODO READY | DONE HOLD
* DIVE Parent :@flow:
** TODO [#C] Tomorrow evening
SCHEDULED: <2026-08-18 Tue>
** TODO [#A] Day seven
SCHEDULED: <2026-08-24 Mon>
** TODO Outside window
SCHEDULED: <2026-08-25 Tue>
** TODO Today only
SCHEDULED: <2026-08-17 Mon>
** DONE Finished future
SCHEDULED: <2026-08-19 Wed>
** HOLD Held group
*** TODO Hidden future
SCHEDULED: <2026-08-19 Wed>
")
   (org-agenda nil "d")
   (with-current-buffer org-agenda-buffer-name
     (should-not (string-match-p "未来 7 天\\|Tomorrow evening\\|Day seven" (buffer-string)))
     (should (equal '("Tomorrow evening" "Day seven")
                    (mapcar #'org-workflow-target-entry-title (org-workflow-agenda--future-entries))))
     (org-workflow-agenda-set-day t)
     (note-gtd-target-test--goto-agenda-title "Tomorrow evening")
     (should (equal '(task "2026-08-18" 67)
                    (get-text-property (point) 'org-workflow-agenda-create-context)))
     (should (member "@flow" (org-get-at-bol 'tags)))
     (org-workflow-agenda-priority-a)
     (org-workflow-agenda-schedule-today)
     (org-workflow-agenda-set-day nil)
     (note-gtd-target-test--goto-agenda-title "Tomorrow evening")
     (should (org-get-at-bol 'org-hd-marker))
     (should-not (string-match-p "未来 7 天\\|Day seven" (buffer-string))))))

(ert-deftest note-gtd-agenda-today-period-sets-both-fields ()
  "Each combined action sets today and its time band on an unscheduled leaf."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:
* DIVE Parent
** TODO Morning task
** TODO Afternoon task
** TODO Evening task
")
   (org-agenda nil "d")
   (dolist (spec '(("Morning task" org-workflow-agenda-today-morning ?A)
                   ("Afternoon task" org-workflow-agenda-today-afternoon ?B)
                   ("Evening task" org-workflow-agenda-today-evening ?C)))
     (with-current-buffer org-agenda-buffer-name
     (note-gtd-target-test--goto-agenda-title (car spec))
       (funcall (cadr spec))
       (note-gtd-target-test--goto-agenda-title (car spec))
       (should (string-match-p (car spec) (thing-at-point 'line t))))
     (with-current-buffer (find-file-noselect (car org-agenda-files))
       (goto-char (point-min))
       (search-forward (car spec))
       (should (equal "<2026-08-17 Mon>" (org-entry-get nil "SCHEDULED")))
       (should (string-match-p (format "\\[#%c\\]" (nth 2 spec))
                               (org-get-heading t t nil t)))))))

(ert-deftest note-gtd-agenda-period-only-keeps-unscheduled-task-unscheduled ()
  "Changing only the time band must not invent a date."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:
* DIVE Parent
** TODO Candidate
")
   (org-agenda nil "d")
   (with-current-buffer org-agenda-buffer-name
     (note-gtd-target-test--goto-agenda-title "Candidate")
     (org-workflow-agenda-priority-b))
   (with-current-buffer (find-file-noselect (car org-agenda-files))
     (goto-char (point-min))
     (search-forward "Candidate")
     (should-not (org-entry-get nil "SCHEDULED")))))

(ert-deftest org-workflow-dive-opens-next-sibling-at-two-remaining ()
  "Completion opens only the immediate next group and Agenda sees its leaves."
  (org-workflow-target-test-with-files
   '("#+filetags: :project:
#+TODO: TODO READY | DONE HOLD
* Milestone
** DIVE Chapter one :promise:
*** TODO First
*** TODO Second
*** TODO Third
** Chapter two :@deep:
*** TODO Plan next
** Chapter three
*** TODO Later
")
   (with-current-buffer (find-file-noselect (car org-agenda-files))
     (should-not (org-workflow-sync-curr))
     (goto-char (point-min))
     (search-forward "First")
     (org-todo "DONE")
     (goto-char (point-min))
     (search-forward "Chapter one")
     (should (equal "DIVE" (org-get-todo-state)))
     (search-forward "Chapter two")
     (should (equal "DIVE" (org-get-todo-state)))
     (should (member "@deep" (org-get-tags nil t)))
     (should-not (member "promise" (org-get-tags nil t)))
     (search-forward "Chapter three")
     (should-not (equal "DIVE" (org-get-todo-state))))
   (org-agenda nil "d")
   (org-agenda nil "d")
   (with-current-buffer org-agenda-buffer-name
     (note-gtd-target-test--goto-agenda-title "Plan next")
     (should (string-match-p "Plan next" (buffer-string)))
     (should-not (string-match-p "Later" (buffer-string))))))

(ert-deftest org-workflow-dive-counts-direct-ready-and-scheduled-leaves ()
  "Count direct unfinished leaves independent of scheduling, ignoring depth."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:
#+TODO: TODO READY | DONE HOLD
* Milestone
** DIVE Group
*** TODO Scheduled
SCHEDULED: <2026-08-17 Mon>
*** READY Ready leaf
*** TODO Remaining
*** DONE Finished
*** Subgroup
**** TODO Nested ignored
*** HOLD Paused
**** TODO Ignored
** Next
*** TODO Candidate
")
   (with-current-buffer (find-file-noselect (car org-agenda-files))
     (goto-char (point-min))
     (search-forward "Group")
     (org-back-to-heading t)
     (should (= 3 (org-workflow--curr-remaining)))
     (should-not (org-workflow-sync-curr))
     (search-forward "Remaining")
     (org-todo "HOLD")
     (goto-char (point-min))
     (search-forward "Next")
     (should (equal "DIVE" (org-get-todo-state))))))

(ert-deftest org-workflow-dive-sync-is-one-pass-and-stops-at-held-sibling ()
  "One sync cannot cascade through small groups or jump a held sibling."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:
#+TODO: TODO READY | DONE HOLD
* Milestone
** DIVE One
*** TODO First
** Two
*** TODO Second
** Three
*** TODO Third
** DIVE Boundary
*** TODO Last
** HOLD Paused
*** TODO Held child
** Farther
*** TODO Far child
")
   (should (= 1 (length (org-workflow-sync-curr))))
   (with-current-buffer (find-file-noselect (car org-agenda-files))
     (goto-char (point-min))
     (search-forward "Two")
     (should (equal "DIVE" (org-get-todo-state)))
     (dolist (title '("* Three" "* HOLD Paused" "* Farther"))
       (search-forward title)
       (should-not (equal "DIVE" (org-get-todo-state)))))))

(ert-deftest org-workflow-dive-no-cross-parent-or-out-of-scope ()
  "Do not promote DIVE children, cross parents, or modify ordinary files."
  (org-workflow-target-test-with-files
   '("#+filetags: :project:
* Parent
** DIVE Last group
*** TODO Leaf
* Other parent
** TODO Other leaf
"
     "* DIVE One
** TODO Leaf
* Two
** TODO Other
")
   (should-not (org-workflow-sync-curr))
   (let ((org-workflow-curr-lookahead-threshold nil))
     (should-not (org-workflow-sync-curr)))))

(ert-deftest note-gtd-agenda-load-separates-missing-and-parent-estimates ()
  "Only explicit leaf estimates count; unknown work is reported separately."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:
* DIVE Parent
:PROPERTIES:
:Effort: 9:00
:END:
** TODO [#A] Short
SCHEDULED: <2026-08-17 Mon>
:PROPERTIES:
:Effort: 0:30
:END:
** TODO [#A] Long
SCHEDULED: <2026-08-17 Mon>
:PROPERTIES:
:Effort: 1:30
:END:
** TODO [#A] Unknown
SCHEDULED: <2026-08-17 Mon>
")
   (let ((entries (org-workflow-target--ordered-entries)))
     (should (equal " · 预计 2:00" (org-workflow-agenda--period-load entries))))))

(ert-deftest note-gtd-agenda-bulk-updates-selected-tasks-across-files ()
  "Native marks feed the flat menu without touching the unselected task."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:
* DIVE Parent
** TODO Select one
** TODO Leave alone
"
     "#+filetags: :project:
* DIVE Parent
** TODO Select two
")
   (org-agenda nil "d")
   (with-current-buffer org-agenda-buffer-name
     (dolist (title '("Select one" "Select two"))
       (note-gtd-target-test--goto-agenda-title title)
       (org-agenda-bulk-mark))
     (should (= 2 (length org-agenda-bulk-marked-entries)))
     (org-workflow-agenda-today-afternoon)
     (should-not org-agenda-bulk-marked-entries))
   (dolist (file org-agenda-files)
     (with-current-buffer (find-file-noselect file)
       (org-map-entries
        (lambda ()
          (when (org-get-todo-state)
            (if (string-prefix-p "Select" (org-get-heading t t t t))
                (progn
                  (should (equal "<2026-08-17 Mon>" (org-entry-get nil "SCHEDULED")))
                  (should (eq ?B (org-workflow--explicit-priority-at-point))))
              (should-not (org-entry-get nil "SCHEDULED"))))) nil 'file)))))

(ert-deftest note-gtd-agenda-bulk-rolls-back-source-on-error ()
  "A failure on the second source rolls back the first source too."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:
* DIVE Parent
** TODO First
"
     "#+filetags: :area:
* DIVE Parent
** TODO Second
")
   (org-agenda nil "d")
   (with-current-buffer org-agenda-buffer-name
     (dolist (title '("First" "Second"))
       (note-gtd-target-test--goto-agenda-title title)
       (org-agenda-bulk-mark))
     (let ((calls 0))
       (should-error
        (org-workflow-agenda--apply-planning
         (lambda ()
           (cl-incf calls)
           (if (= calls 2) (error "Injected failure")
             (org-agenda-priority ?C)))))))
   (dolist (file org-agenda-files)
     (with-current-buffer (find-file-noselect file)
       (should-not (string-match-p "\\[#C\\]" (buffer-string)))))))

(ert-deftest note-gtd-agenda-tag-filter-is-view-only-and-clears-selection ()
  "Native filtering handles inheritance, survives redo, and changes no source."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:
* DIVE Parent :promise:
** TODO Deep work :@deep:
** TODO Small work :@tiny:
* DIVE Other
** TODO Flow work :@flow:
")
   (org-agenda nil "d")
   (with-current-buffer org-agenda-buffer-name
     (note-gtd-target-test--goto-agenda-title "Deep work")
     (org-agenda-bulk-mark)
     (org-workflow-agenda-filter-tiny)
     (should-not org-agenda-bulk-marked-entries)
     (note-gtd-target-test--goto-agenda-title "Deep work")
     (should (invisible-p (point)))
     (note-gtd-target-test--goto-agenda-title "Small work")
     (should-not (invisible-p (point)))
     (org-agenda-redo)
     (note-gtd-target-test--goto-agenda-title "Deep work")
     (should (invisible-p (point)))
     (org-workflow-agenda-filter-promise)
     (note-gtd-target-test--goto-agenda-title "Deep work")
     (should-not (invisible-p (point)))
     (note-gtd-target-test--goto-agenda-title "Flow work")
     (should (invisible-p (point)))
     (org-workflow-agenda-filter-clear)
     (should-not (invisible-p (point))))
   (with-current-buffer (find-file-noselect (car org-agenda-files))
     (should-not (buffer-modified-p)))))

(ert-deftest note-gtd-agenda-removes-scheduling-notes-and-keeps-native-controls ()
  "Remove scheduling annotations while preserving native task controls."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:
* DIVE Parent
** TODO Late :promise:
SCHEDULED: <2026-08-15 Sat>
** TODO Today
SCHEDULED: <2026-08-17 Mon>
")
   (org-agenda nil "d")
   (with-current-buffer org-agenda-buffer-name
     (let ((org-workflow-agenda-sprint-view t))
       (run-hooks 'org-agenda-finalize-hook)
       (run-hooks 'org-agenda-finalize-hook))
     (should-not (string-match-p "原定\\|已延期" (buffer-string)))
     (note-gtd-target-test--goto-agenda-title "Late")
     (should (org-get-at-bol 'org-hd-marker))
     (should (stringp (org-get-at-bol 'wrap-prefix)))
     (org-workflow-agenda-schedule-today)
     (should-not (string-match-p "原定" (buffer-string)))
     (should (string-match-p "◇ Late" (buffer-string)))
     (should-not (string-match-p ":promise:" (buffer-string))))))

(ert-deftest note-gtd-agenda-planning-scope-is-view-only-and-keeps-exclusions ()
  "All scope reveals backlog leaves but not held, ready, scheduled or foreign tasks."
  (org-workflow-target-test-with-files
   '("#+filetags: :project:
#+TODO: TODO READY | DONE HOLD
* DIVE Current
** TODO Current leaf
* Backlog
** TODO Backlog leaf
** TODO Container
*** TODO Nested leaf
** READY Ready leaf
** TODO Scheduled leaf
SCHEDULED: <2026-08-18 Tue>
** HOLD Paused
*** TODO Held leaf
"
     "* Foreign
** TODO Foreign leaf
")
   (org-agenda nil "d")
   (with-current-buffer org-agenda-buffer-name
     (should-not (string-match-p "Backlog leaf" (buffer-string)))
     (note-gtd-target-test--goto-agenda-title "Current leaf")
     (org-agenda-bulk-mark)
     (org-workflow-agenda-toggle-planning-scope)
     (should-not org-agenda-bulk-marked-entries)
     (should org-workflow-agenda-planning-all)
     (should (string-match-p "Backlog leaf" (buffer-string)))
     (should (string-match-p "Nested leaf" (buffer-string)))
     (dolist (hidden '("Ready leaf" "Scheduled leaf" "Held leaf" "Foreign leaf"))
       (should-not (string-match-p hidden (buffer-string))))
     (org-workflow-agenda-toggle-planning-scope)
     (should-not (string-match-p "Backlog leaf" (buffer-string))))
   (dolist (file org-agenda-files)
     (with-current-buffer (find-file-noselect file)
       (should-not (buffer-modified-p))))))

(ert-deftest note-gtd-agenda-columns-own-independent-buffers-and-preserve-other-panes ()
  "Columns retain native metadata and closing them preserves unrelated panes."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n* DIVE Parent\n** TODO Candidate\n** TODO Scheduled\nSCHEDULED: <2026-08-17 Mon>\n")
   (save-window-excursion
    (delete-other-windows)
    (let ((unrelated (split-window-below))
          (org-workflow-agenda-column-min-width 20)
          (org-agenda-window-setup 'current-window)
          (org-workflow-agenda-columns-enabled t))
      (set-window-buffer unrelated (get-buffer-create " *agenda-column-other*"))
       (org-agenda nil "d")
       (with-current-buffer org-agenda-buffer-name
         (let ((agenda (current-buffer)))
           (org-workflow-agenda--set-setting 'org-workflow-agenda-columns-enabled t)
           (org-workflow-agenda--apply-columns)
           (should (window-live-p org-workflow-agenda--column-window))
           (let* ((left org-workflow-agenda--column-window)
                 (candidate (window-buffer left))
                 (right (get-buffer-window agenda)))
            (should-not (eq agenda candidate))
            (should (eq 'candidates (buffer-local-value 'org-workflow-agenda--pane-role candidate)))
             (should (eq 'schedule org-workflow-agenda--pane-role))
             (should (eq org-workflow-agenda--workbench
                         (buffer-local-value 'org-workflow-agenda--workbench candidate)))
             (should (> (car (window-edges left)) (car (window-edges right))))
             (with-current-buffer candidate
               (note-gtd-target-test--goto-agenda-title "Candidate")
               (should (org-get-at-bol 'org-hd-marker))
              (should-not (string-match-p "Scheduled" (buffer-string))))
            (note-gtd-target-test--goto-agenda-title "Scheduled")
            (should (org-get-at-bol 'org-hd-marker))
            (should-not (string-match-p "Candidate" (buffer-string))))
          (should (= 3 (length (window-list))))
          (org-workflow-agenda--apply-columns)
          (should (= 3 (length (window-list))))
          (org-workflow-agenda-toggle-columns)
          (should (eq 'combined org-workflow-agenda--pane-role))
           (should (= 2 (length (window-list))))
           (should (window-live-p unrelated))))))))

(ert-deftest note-gtd-agenda-normal-entry-stays-single-at-any-width ()
  "A normal Sprint never splits automatically on render or resize."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n* DIVE Parent\n** TODO Candidate\n** TODO Scheduled\nSCHEDULED: <2026-08-17 Mon>\n")
   (save-window-excursion
    (delete-other-windows)
     (let ((org-agenda-window-setup 'current-window))
       (org-agenda nil "d"))
     (with-current-buffer org-agenda-buffer-name
       (let ((org-workflow-agenda-column-min-width 1))
         (org-workflow-agenda--columns-resize (selected-frame))
         (org-agenda-redo)
         (should (= 1 (length (window-list))))
         (should (eq 'combined org-workflow-agenda--pane-role))
         (should-not (string-match-p "待安排\\|未来 7 天" (buffer-string)))
         (should (string-match-p "收集箱" (buffer-string)))
         (should (string-match-p "今日安排" (buffer-string))))))))

(provide 'org-workflow-agenda-target-test)

(ert-deftest note-gtd-agenda-native-edit-rebuilds-sprint-style-and-groups ()
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n* DIVE Parent\n** TODO [#A] Native edit :promise:\nSCHEDULED: <2026-08-17 Mon>\n")
   (org-workflow-target-refresh t)
   (org-agenda nil "d")
   (with-current-buffer org-agenda-buffer-name
     (note-gtd-target-test--goto-agenda-title "Native edit")
     (org-agenda-priority ?B)
     (should org-workflow-agenda--native-edit-marker)
     (org-workflow-agenda--refresh-native-edit)
     (should-not org-workflow-agenda--native-edit-marker)
     (should (org-get-at-bol 'org-hd-marker))
     (should (string-match-p "◇ Native edit" (thing-at-point 'line t)))
     (should-not (string-match-p "TODO\\|\\[#B\\]\\|:area:" (thing-at-point 'line t)))
     (should (string-match-p "下午" (buffer-string)))
     (should (string-match-p "上午" (buffer-string)))
     (org-agenda-set-tags "@tiny" 'on)
     (org-workflow-agenda--refresh-native-edit)
     (should (string-match-p "@tiny" (thing-at-point 'line t))))))

(ert-deftest note-gtd-agenda-scheduling-no-longer-counts-deferrals ()
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n* DIVE Parent\n:PROPERTIES:\n:JOURNAL_INBOX: 2026-08-17\n:END:\n** TODO [#B] Defer me\nSCHEDULED: <2026-08-17 Mon>\n")
   (org-workflow-target-refresh t)
   (org-agenda nil "d")
   (with-current-buffer org-agenda-buffer-name
     (note-gtd-target-test--goto-agenda-title "Defer me")
     (org-workflow-agenda-schedule-tomorrow)
     (org-workflow-agenda-set-day t)
     (note-gtd-target-test--goto-agenda-title "Defer me")
     (org-with-point-at (org-get-at-bol 'org-hd-marker)
       (should-not (org-entry-get nil "WORKFLOW_DEFER_COUNT")))
     (org-workflow-agenda-schedule-tomorrow)
     (org-with-point-at (org-get-at-bol 'org-hd-marker)
       (should-not (org-entry-get nil "WORKFLOW_DEFER_COUNT")))
     (org-workflow-agenda-schedule-today)
     (org-workflow-agenda-set-day nil)
     (note-gtd-target-test--goto-agenda-title "Defer me")
     (org-workflow-agenda-unschedule)
     (note-gtd-target-test--goto-agenda-title "Defer me")
     (org-workflow-agenda-schedule-tomorrow)
     (org-workflow-agenda-set-day t)
     (note-gtd-target-test--goto-agenda-title "Defer me")
     (org-agenda-schedule nil "2026-08-19")
     (org-workflow-agenda--refresh-native-edit)
     (with-current-buffer (find-file-noselect (car org-agenda-files))
       (goto-char (point-min)) (search-forward "Defer me")
         (should-not (org-entry-get nil "WORKFLOW_DEFER_COUNT"))
         (should (equal "B" (org-entry-get nil "PRIORITY")))))))

(ert-deftest note-gtd-agenda-planning-preserves-source-heading-order ()
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n* DIVE Writing\n** TODO [#C] Zebra first\n** TODO [#A] Alpha second\n** TODO [#B] Middle third\n")
   (org-workflow-target-refresh t)
   (org-agenda nil "d")
   (with-current-buffer org-agenda-buffer-name
     (note-gtd-target-test--open-columns)
     (let ((text (buffer-substring-no-properties (point-min) (point-max))))
       (setq text (with-current-buffer (org-workflow-agenda-workbench-candidates org-workflow-agenda--workbench)
                    (buffer-string)))
       (should (< (string-match "Zebra first" text) (string-match "Alpha second" text)))
       (should (< (string-match "Alpha second" text) (string-match "Middle third" text)))))))

(ert-deftest note-gtd-agenda-menu-day-switch-plans-all-three-periods ()
  (dolist (tomorrow '(nil t))
    (dolist (spec '((org-workflow-agenda-plan-morning . "A")
                    (org-workflow-agenda-plan-afternoon . "B")
                    (org-workflow-agenda-plan-evening . "C")))
      (org-workflow-target-test-with-files
       '("#+filetags: :area:\n* DIVE Parent\n** TODO Plan me\n")
       (org-workflow-target-refresh t)
       (org-agenda nil "d")
       (with-current-buffer org-agenda-buffer-name
         (org-workflow-agenda-set-day tomorrow)
         (note-gtd-target-test--goto-agenda-title "Plan me")
         (funcall (car spec)))
       (with-current-buffer (find-file-noselect (car org-agenda-files))
         (goto-char (point-min)) (search-forward "Plan me")
         (should-not (member "promise" (org-get-tags nil t)))
         (should (equal (cdr spec) (org-entry-get nil "PRIORITY")))
         (should (equal (if tomorrow "2026-08-18" "2026-08-17")
                        (org-workflow-target--timestamp-date (org-entry-get nil "SCHEDULED")))))))))

(ert-deftest note-gtd-agenda-manual-order-crosses-parents-and-updates-stack ()
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n* DIVE Parent A\n** TODO [#C] First\nSCHEDULED: <2026-08-17 Mon>\n* DIVE Parent B\n** TODO [#C] Second\nSCHEDULED: <2026-08-17 Mon>\n** TODO [#A] Other period\nSCHEDULED: <2026-08-17 Mon>\n")
   (let ((org-workflow-target-selected-marker nil))
     (org-workflow-target-refresh t)
     (org-agenda nil "d")
     (with-current-buffer org-agenda-buffer-name
       (note-gtd-target-test--goto-agenda-title "Second")
       (org-workflow-agenda-move-up)
       (should (string-match-p "Second" (thing-at-point 'line t)))
       (should (equal '("Other period" "Second" "First") (mapcar #'org-workflow-target-entry-title org-workflow-target-stack)))
       (should-error (org-workflow-agenda-move-up) :type 'user-error)
       (org-workflow-target-refresh t)
       (org-agenda-redo)
       (let ((text (buffer-string)))
         (should (< (string-match "Second" text) (string-match "First" text))))
       (note-gtd-target-test--goto-agenda-title "Second")
       (org-workflow-agenda-move-down)
       (should (equal '("Other period" "First" "Second") (mapcar #'org-workflow-target-entry-title org-workflow-target-stack)))
       (org-workflow-agenda-move-up))
     (with-current-buffer (find-file-noselect (car org-agenda-files))
       (goto-char (point-min)) (search-forward "First")
       (should (equal "C/1" (org-entry-get nil "WORKFLOW_ORDER")))
       (should-not (org-entry-get nil "WORKFLOW_ORDER_SCOPE"))
       ;; Source headings retain their organization.
       (should (< (string-match "First" (buffer-string)) (string-match "Second" (buffer-string)))))
     (cl-letf (((symbol-function 'org-workflow-target--today-string) (lambda () "2026-08-18")))
       (should (equal '("Other period" "Second" "First")
                      (mapcar #'org-workflow-target-entry-title (org-workflow-target--ordered-entries))))
       (with-current-buffer org-agenda-buffer-name
         (org-agenda-redo)
         (let ((text (buffer-string)))
           (should (< (string-match "Second" text) (string-match "First" text)))))))))

(ert-deftest note-gtd-agenda-manual-order-retains-legacy-ranks-with-new-tasks ()
  "Carry saved ranks across days, keeping new tasks behind and days separate."
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n* DIVE Parent\n** TODO [#C] New task\nSCHEDULED: <2026-08-17 Mon>\n** TODO [#C] First\nSCHEDULED: <2026-08-17 Mon>\n** TODO [#C] Second\nSCHEDULED: <2026-08-17 Mon>\n** TODO [#C] Future\nSCHEDULED: <2026-08-19 Wed>\n")
   (with-current-buffer (find-file-noselect (car org-agenda-files))
     (dolist (spec '(("First" . "1") ("Second" . "0") ("Future" . "0")))
       (goto-char (point-min))
       (search-forward (car spec))
       (org-entry-put nil "WORKFLOW_ORDER_SCOPE"
                      (format "2026-08-17/%d" (org-get-priority "[#C]")))
       (org-entry-put nil "WORKFLOW_ORDER" (cdr spec))))
   (cl-letf (((symbol-function 'org-workflow-target--today-string) (lambda () "2026-08-18")))
     (should (equal '("Second" "First" "New task" "Future")
                    (mapcar #'org-workflow-target-entry-title
                            (org-workflow-target--ordered-entries "2026-08-19"))))
     (with-current-buffer (find-file-noselect (car org-agenda-files))
       (goto-char (point-min)) (search-forward "Second")
       (org-priority ?A))
     (let ((entries (org-workflow-target--ordered-entries)))
       (should-not (org-workflow--manual-rank
                    (seq-find (lambda (entry)
                                (equal "Second" (org-workflow-target-entry-title entry)))
                              entries)))
       (should (equal '("Second" "First" "New task")
                      (mapcar #'org-workflow-target-entry-title entries)))))))

(ert-deftest note-gtd-agenda-manual-order-respects-future-day-and-readonly-peer ()
  (org-workflow-target-test-with-files
   '("#+filetags: :area:\n* DIVE Parent\n** TODO [#C] Today\nSCHEDULED: <2026-08-17 Mon>\n** TODO [#C] Tomorrow first\nSCHEDULED: <2026-08-18 Tue>\n** TODO [#C] Tomorrow second\nSCHEDULED: <2026-08-18 Tue>\n")
   (let ((org-workflow-agenda-future-expanded t))
     (org-agenda nil "d")
     (with-current-buffer org-agenda-buffer-name
       (org-workflow-agenda-set-day t)
       (note-gtd-target-test--goto-agenda-title "Tomorrow second")
       (let ((source (find-file-noselect (car org-agenda-files))))
         (with-current-buffer source (setq buffer-read-only t))
         (unwind-protect (should-error (org-workflow-agenda-move-up) :type 'user-error)
           (with-current-buffer source (setq buffer-read-only nil))))
       (org-workflow-agenda-move-up)
       (should (equal '("Today" "Tomorrow second" "Tomorrow first")
                      (mapcar #'org-workflow-target-entry-title (org-workflow-target--ordered-entries "2026-08-18"))))
       (should-error (org-workflow-agenda-move-up) :type 'user-error))
     (with-current-buffer (find-file-noselect (car org-agenda-files))
       (goto-char (point-min)) (search-forward "Today")
       (should-not (org-entry-get nil "WORKFLOW_ORDER"))))))

(ert-deftest note-gtd-agenda-legacy-scheduling-adds-no-workflow-metadata ()
  "The unmigrated compatibility path no longer creates tracking properties."
  (org-workflow-target-test-with-files
   '("#+filetags: :project:\n* DIVE Stage\n** TODO Task :@tiny:\n")
   (with-current-buffer (find-file-noselect (car org-agenda-files))
     (goto-char (point-min)) (search-forward "Task")
     (org-schedule nil "2026-08-17")
     (org-schedule nil "2026-08-18")
     (org-schedule nil "2026-08-19")
     (should-not (org-entry-get nil "WORKFLOW_DEFER_COUNT"))
     (should-not (org-entry-get nil "WORKFLOW_PROMISE_DATE"))
     (should-not (member "promise" (org-get-tags nil t)))
     (should (member "@tiny" (org-get-tags nil t))))))

(ert-deftest org-workflow-dive-keeps-top-level-milestones-manual ()
  "Neither completion, HOLD nor explicit sync advances level-one milestones."
  (org-workflow-target-test-with-files
   '("#+filetags: :project:
#+TODO: TODO | DONE HOLD
* Milestone
** DIVE Step
*** TODO First
** Next step
*** TODO Second
* Next milestone
** TODO Later
")
   (with-current-buffer (find-file-noselect (car org-agenda-files))
     (goto-char (point-min))
     (search-forward "First")
     (org-todo "DONE")
     (goto-char (point-min))
     (search-forward "Next step")
     (should (equal "DIVE" (org-get-todo-state)))
     (save-excursion (org-up-heading-safe) (org-todo "DIVE"))
     (org-todo "HOLD")
     (org-workflow-sync-curr)
     (goto-char (point-min))
     (search-forward "Next milestone")
     (should-not (equal "DIVE" (org-get-todo-state))))))

(ert-deftest note-gtd-agenda-recommendation-inherits-and-rejects-conflicts ()
  (let ((org-workflow-agenda-period-tag-groups '((?A "@deep" "study") (?B "@tiny") (?C "@flow"))))
    (with-temp-buffer
      (org-mode)
      (insert "* Parent :study:\n** TODO Child :@deep:\n")
      (goto-char (point-max)) (org-back-to-heading t)
      (should (= ?A (org-workflow-agenda--recommended-period)))
      (org-toggle-tag "@tiny" 'on)
      (should-error (org-workflow-agenda--recommended-period) :type 'user-error))
    (with-temp-buffer
      (org-mode) (insert "* TODO Untagged\n") (goto-char (point-min))
      (should-error (org-workflow-agenda--recommended-period) :type 'user-error))))

(ert-deftest note-gtd-agenda-recommendation-respects-day-switch ()
  (dolist (tomorrow '(nil t))
    (org-workflow-target-test-with-files
     '("#+filetags: :area:\n* DIVE Parent :@deep:\n** TODO Recommended\n")
     (org-agenda nil "d")
     (with-current-buffer org-agenda-buffer-name
       (org-workflow-agenda-set-day tomorrow)
       (note-gtd-target-test--goto-agenda-title "Recommended")
       (org-workflow-agenda-plan-recommended))
     (with-current-buffer (find-file-noselect (car org-agenda-files))
       (goto-char (point-min)) (search-forward "Recommended")
       (should (equal "A" (org-entry-get nil "PRIORITY")))
       (should (equal (if tomorrow "2026-08-18" "2026-08-17")
                      (org-workflow-target--timestamp-date (org-entry-get nil "SCHEDULED"))))))))
