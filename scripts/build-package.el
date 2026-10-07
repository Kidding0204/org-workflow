;;; build-package.el --- Build and verify org-workflow -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Jinwang Dong
;; Author: Jinwang Dong <dongjinwang040204@gmail.com>
;; Assisted-by: Codex:GPT-6
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Run through Makefile from the package root.  Artifacts stay in dist/.

;;; Code:
(require 'package)
(require 'lisp-mnt)
(require 'loaddefs-gen)
(require 'bytecomp)

(defconst org-workflow-build-root
  (file-name-directory
   (directory-file-name (file-name-directory (or load-file-name buffer-file-name)))))
(setq default-directory org-workflow-build-root
      package-user-dir (expand-file-name
                        (or (getenv "PACKAGE_USER_DIR") ".ci/elpa")
                        org-workflow-build-root)
      package-archives '(("gnu" . "https://elpa.gnu.org/packages/")
                         ("melpa" . "https://melpa.org/packages/")))

(defun org-workflow-build--descriptor ()
  "Read package metadata from the main source file."
  (with-temp-buffer
    (insert-file-contents "org-workflow.el")
    (package-buffer-info)))

(defun org-workflow-build--sources ()
  "Return only the public package's root-level Lisp files."
  (directory-files org-workflow-build-root t "\\`org-workflow.*\\.el\\'"))

(defun org-workflow-build--initialize ()
  "Activate dependencies without loading the user's configuration."
  (package-initialize)
  (add-to-list 'load-path org-workflow-build-root))

(defun org-workflow-build--tar ()
  "Build an installable tar using metadata read from the package header."
  (let* ((desc (org-workflow-build--descriptor))
         (version (package-version-join (package-desc-version desc)))
         (name (format "org-workflow-%s" version))
         (stage (make-temp-file "org-workflow-build-" t))
         (directory (expand-file-name name stage))
         (archive (expand-file-name (concat "dist/" name ".tar"))))
    (unwind-protect
        (progn
          (make-directory directory)
          (make-directory "dist" t)
          (dolist (source (org-workflow-build--sources))
            (copy-file source (expand-file-name (file-name-nondirectory source)
                                                directory)))
          (package-generate-description-file
           desc (expand-file-name "org-workflow-pkg.el" directory))
          (package-generate-autoloads 'org-workflow directory)
          (unless (zerop (call-process "tar" nil "*org-workflow-build*" nil
                                      "-cf" archive "-C" stage name))
            (error "tar failed; see *org-workflow-build*"))
          (princ (concat archive "\n"))
          archive)
      (delete-directory stage t))))

(let ((command (car (remove "--" command-line-args-left))))
  (setq command-line-args-left nil)
  (pcase command
    ("bootstrap"
     (package-initialize)
     (package-refresh-contents)
     (dolist (req (package-desc-reqs (org-workflow-build--descriptor)))
       (unless (eq (car req) 'emacs)
         (unless (package-installed-p (car req) (cadr req))
           (package-install (car req)))))
     (dolist (dependency '(package-lint evil evil-collection org-modern embark))
       (unless (package-installed-p dependency) (package-install dependency))))
    ("build" (org-workflow-build--tar))
    ("compile"
     (org-workflow-build--initialize)
     (let ((directory (expand-file-name "dist/compile")))
       (make-directory directory t)
       (dolist (source (org-workflow-build--sources))
         (let ((copy (expand-file-name (file-name-nondirectory source) directory)))
           (copy-file source copy t)
           (unless (byte-compile-file copy)
             (error "Compilation failed: %s" source))))))
    ("test"
     (org-workflow-build--initialize)
     (load (expand-file-name "test/run-tests.el") nil nil t))
    ("lint"
     (org-workflow-build--initialize)
     (require 'package-lint)
     (with-temp-buffer
       (insert-file-contents "org-workflow.el")
       (emacs-lisp-mode)
       (let ((issues (package-lint-buffer)))
         (dolist (issue issues) (princ (format "%S\n" issue)))
         (when issues (error "Package metadata lint failed")))))
    ("checkdoc"
     (require 'checkdoc)
     (let ((checkdoc-diagnostic-buffer "*org-workflow-checkdoc*")
           (checkdoc--batch-flag t)
           (checkdoc-autofix-flag 'never))
       (dolist (source (org-workflow-build--sources))
         (with-current-buffer (find-file-noselect source)
           (checkdoc-current-buffer t)))
       (with-current-buffer (get-buffer-create checkdoc-diagnostic-buffer)
         (princ (buffer-string))
         (goto-char (point-min))
         (let ((count 0))
           (while (re-search-forward "^org-workflow.*:[0-9]+: " nil t)
             (setq count (1+ count)))
           (princ (format "\nCheckdoc warnings: %d.\n" count))
           (when (> count 0) (error "Checkdoc warnings remain"))))))
    ("smoke"
     (package-initialize)
     (let* ((dependency-path load-path)
            (package-user-dir (make-temp-file "org-workflow-install-" t))
            (package-alist (copy-tree package-alist))
            (package-activated-list (copy-sequence package-activated-list))
            (package-selected-packages nil)
            (package-enable-at-startup nil)
            (archive (org-workflow-build--tar)))
       (unwind-protect
           (progn
             ;; Expose installed dependencies but install Workflow afresh.
             (setq load-path dependency-path)
             (dolist (req (package-desc-reqs (org-workflow-build--descriptor)))
               (unless (eq (car req) 'emacs)
                 (let ((dependency (car (alist-get (car req) package-alist))))
                   (unless (or dependency (package-built-in-p (car req) (cadr req)))
                     (error "Missing smoke-test dependency %s" (car req))))))
             (package-install-file archive)
             (package-activate 'org-workflow t)
             (require 'org-workflow)
             (unless (string-prefix-p package-user-dir
                                      (file-truename (locate-library "org-workflow")))
               (error "Smoke test loaded Workflow outside its fresh installation"))
             (unless (and (not org-workflow-mode) (not org-workflow-store--connection))
               (error "Installed require activated Workflow"))
             (let* ((user-emacs-directory (expand-file-name "profile/" package-user-dir))
                    (org-directory (expand-file-name "notes/" user-emacs-directory))
                    (org-workflow-directory org-directory)
                    (org-workflow-store-file (expand-file-name "facts.sqlite" user-emacs-directory))
                    (org-workflow-web-export-file (expand-file-name "history.json" user-emacs-directory))
                    (org-agenda-files nil))
               (make-directory org-directory t)
               (org-workflow-mode 1)
               (unless org-workflow-mode (error "Installed activation failed"))
               (org-workflow-mode -1)
               (when (or org-workflow--hooks org-workflow--advices org-workflow--keys)
                 (error "Installed mode left integrations after disable"))
               (when (org-workflow-store--live-p org-workflow-store--connection)
                 (sqlite-close org-workflow-store--connection)))
             (princ "Fresh package installation, inert require and activation/disable succeeded.\n"))
         (delete-directory package-user-dir t))))
    (_ (error "Unknown command: %s" command))))

;;; build-package.el ends here
