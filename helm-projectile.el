;;; helm-projectile.el --- Helm integration for Projectile         -*- lexical-binding: t; -*-

;; Copyright (C) 2011-2025 Bozhidar Batsov

;; Author: Bozhidar Batsov
;; URL: https://github.com/bbatsov/helm-projectile
;; Maintainer: Przemysław Kryger
;; Created: 2011-31-07
;; Keywords: project, convenience
;; Version: 1.2.0
;; Package-Requires: ((emacs "26.1") (helm "3.0") (projectile "2.9"))

;; This file is NOT part of GNU Emacs.

;;; License:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:
;;
;; This library provides easy project management and navigation.  The
;; concept of a project is pretty basic - just a folder containing
;; special file.  Currently git, mercurial and bazaar repos are
;; considered projects by default.  If you want to mark a folder
;; manually as a project just create an empty .projectile file in
;; it.  See the README for more details.
;;
;;; Code:

;; built-in libraries
(require 'subr-x)
(require 'cl-lib)
(require 'grep) ;; TODO: Probably we should defer this require

(require 'helm-core)
(require 'helm-global-bindings)
(require 'helm-types)
(require 'helm-locate)
(require 'helm-buffers)
(require 'helm-files)
(require 'helm-grep)

(require 'projectile)

(declare-function eshell "eshell")
(declare-function dired-get-filename "dired")

(defvar grep-find-ignored-directories)
(defvar grep-find-ignored-files)

(defgroup helm-projectile nil
  "Helm support for projectile."
  :prefix "helm-projectile-"
  :group 'projectile
  :group 'helm
  :link `(url-link :tag "GitHub" "https://github.com/bbatsov/helm-projectile"))

(defvar helm-projectile-current-project-root)

(defcustom helm-projectile-truncate-lines nil
  "Truncate lines in helm projectile commands when non--nil.

Some `helm-projectile' commands have similar behavior with existing
Helms.  In these cases their respective custom var for truncation
of lines will be honored.  E.g. `helm-buffers-truncate-lines'
dictates the truncation in `helm-projectile-switch-to-buffer'."
  :group 'helm-projectile
  :type 'boolean)

;;;###autoload
(defcustom helm-projectile-fuzzy-match t
  "Enable fuzzy matching for Helm Projectile commands.
This needs to be set before loading helm-projectile.el."
  :group 'helm-projectile
  :type 'boolean)

(defmacro helm-projectile-define-key (keymap &rest bindings)
  "In KEYMAP, define BINDINGS.
BINDINS is a list in a form of (KEY1 DEF1 KEY2 DEF2 ...)."
  (declare (indent defun))
  (when (or (< (length bindings) 2)
            (= 1 (% 2 (length bindings))))
    (error "Expected BINDINGS to be KEY1 DEF1 KEY2 DEF2 ... "))
  (let ((ret '(progn)))
    (while-let ((key (car bindings))
                (def (cadr bindings)))
      (push
       `(define-key ,keymap ,key
                    (lambda ()
                      (interactive)
                      (helm-exit-and-execute-action ,def)))
       ret)
      (setq bindings (cddr bindings)))
    (reverse ret)))

(defun helm-projectile-hack-actions (actions &rest prescription)
  "Given a Helm action list and a prescription, return a hacked Helm action list.
Optionally applies the PRESCRIPTION beforehand.

The Helm action list ACTIONS is of the form:

\(\(DESCRIPTION1 . FUNCTION1\)
 \(DESCRIPTION2 . FUNCTION2\)
 ...
 \(DESCRIPTIONn . FUNCTIONn\)\)

PRESCRIPTION is in the form:

\(INSTRUCTION1 INSTRUCTION2 ... INSTRUCTIONn\)

If an INSTRUCTION is a symbol, the action with function name
INSTRUCTION is deleted.

If an INSTRUCTION is of the form \(FUNCTION1 . FUNCTION2\), the
action with function name FUNCTION1 will change it's function to
FUNCTION2.

If an INSTRUCTION is of the form \(FUNCTION . DESCRIPTION\), and
if an action with function name FUNCTION exists in the original
Helm action list, the action in the Helm action list, with
function name FUNCTION will change it's description to
DESCRIPTION.  Otherwise, (FUNCTION . DESCRIPTION) will be added to
the action list.

If an INSTRUCTION is of the form \(FUNCTION . :make-first\), and if the
an action with function name FUNCTION exists in the th Helm action list
concatenated with new actions from PRESCRIPTION, the action will become
the first (default) action.

Please check out how `helm-projectile-file-actions' is defined
for an example of how this function is being used."
  (let* ((to-delete (cl-remove-if (lambda (entry) (listp entry)) prescription))
         (actions (cl-delete-if (lambda (action) (memq (cdr action) to-delete))
                                (copy-alist actions)))
         new)
    (cl-dolist (action actions)
      (when (setq new (cdr (assq (cdr action) prescription)))
        (cond
         ((stringp new) (setcar action new))
         ((functionp new) (setcdr action new)))))
    ;; Add new actions from PRESCRIPTION
    (setq new nil)
    (cl-dolist (instruction prescription)
      (when (and (listp instruction)
                 (null (rassq (car instruction) actions))
                 (symbolp (car instruction)) (stringp (cdr instruction)))
        (push (cons (cdr instruction) (car instruction)) new)))
    ;; Push to front the desired action
    (let ((actions (append actions (nreverse new))))
      (if-let* ((first-function (car (rassq :make-first prescription)))
                (first-action-p (lambda (action)
                                  (eq (cdr action)
                                      first-function)))
                (first-action (cl-find-if first-action-p actions)))
          (cons first-action
                (cl-remove-if first-action-p actions))
        actions))))

(defun helm-projectile-vc (dir)
  "A Helm action for jumping to project root using `vc-dir' or Magit.
DIR is a directory to be switched"
  (let ((projectile-require-project-root nil))
    (projectile-vc dir)))

(defun helm-projectile-compile-project (dir)
  "A Helm action for compile a project.
DIR is the project root."
  (let ((helm--reading-passwd-or-string t)
        (default-directory dir))
    (projectile-compile-project helm-current-prefix-arg)))

(defun helm-projectile-test-project (dir)
  "A Helm action for test a project.
DIR is the project root."
  (let ((helm--reading-passwd-or-string t)
        (default-directory dir))
    (projectile-test-project helm-current-prefix-arg)))

(defun helm-projectile-run-project (dir)
  "A Helm action for run a project.
DIR is the project root."
  (let ((helm--reading-passwd-or-string t)
        (default-directory dir))
    (projectile-run-project helm-current-prefix-arg)))

(defun helm-projectile-remove-known-project (_ignore)
  "Remove selected projects from projectile project list.
_IGNORE means the argument does not matter.
It is there because Helm requires it."
  (let* ((projects (helm-marked-candidates :with-wildcard t))
         (len (length projects)))
    (with-helm-display-marked-candidates
      helm-marked-buffer-name
      projects
      (if (not (y-or-n-p (format "Remove *%s projects(s)? " len)))
          (message "(No removal performed)")
        (progn
          (mapc (lambda (p)
                  (setq projectile-known-projects (delete p projectile-known-projects)))
                projects)
          (projectile-save-known-projects))
        (message "%s projects(s) removed" len)))))

(defun helm-projectile-switch-project-by-name (project)
  "Switch to PROJECT and find file in it."
  (let ((projectile-completion-system 'helm)
        (projectile-switch-project-action #'helm-projectile-find-file))
    (projectile-switch-project-by-name project)))

(defun helm-projectile-switch-project-by-name-other-window (project)
  "Switch to PROJECT and find file in it in other window."
  (let ((projectile-completion-system 'helm)
        (projectile-switch-project-action #'helm-projectile-find-file-other-window))
    (projectile-switch-project-by-name project)))

(defun helm-projectile-switch-project-by-name-other-frame (project)
  "Switch to PROJECT and find file in it in other frame."
  (let ((projectile-completion-system 'helm)
        (projectile-switch-project-action #'helm-projectile-find-file-other-frame))
    (projectile-switch-project-by-name project)))

(defvar helm-projectile-projects-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map helm-map)
    (helm-projectile-define-key map
      (kbd "C-d") #'dired
      (kbd "C-c o") #'helm-projectile-switch-project-by-name-other-window
      (kbd "C-c C-o") #'helm-projectile-switch-project-by-name-other-frame
      (kbd "M-g") #'helm-projectile-vc
      (kbd "M-e") #'helm-projectile-switch-to-shell
      (kbd "C-s") #'helm-projectile-grep
      (kbd "M-c") #'helm-projectile-compile-project
      (kbd "M-t") #'helm-projectile-test-project
      (kbd "M-r") #'helm-projectile-run-project
      (kbd "M-D") #'helm-projectile-remove-known-project)
    map)
  "Mapping for known projectile projects.")

(defcustom helm-source-projectile-projects-actions
  (helm-make-actions
   "Switch to project" #'helm-projectile-switch-project-by-name
   "Switch to project other window `C-c o'" #'helm-projectile-switch-project-by-name-other-window
   "Switch to project other frame `C-c C-o'" #'helm-projectile-switch-project-by-name-other-frame
   "Open Dired in project's directory `C-d'" #'dired
   "Open project root in vc-dir or magit `M-g'" #'helm-projectile-vc
   "Switch to Eshell `M-e'" #'helm-projectile-switch-to-shell
   "Grep in projects `C-s'" #'helm-projectile-grep
   "Compile project `M-c'. With C-u, new compile command" #'helm-projectile-compile-project
   "Remove project(s) from project list `M-D'" #'helm-projectile-remove-known-project)
  "Actions for `helm-source-projectile-projects'."
  :group 'helm-projectile
  :type '(alist :key-type string :value-type function))

(defclass helm-projectile-projects-source (helm-source-sync helm-type-file)
  ((candidates :initform (lambda () (with-helm-current-buffer
                                      (mapcar #'copy-sequence
                                              (projectile-known-projects)))))
   (fuzzy-match :initform 'helm-projectile-fuzzy-match)
   (keymap :initform 'helm-projectile-projects-map)
   (mode-line :initform 'helm-read-file-name-mode-line-string)
   (action :initform 'helm-source-projectile-projects-actions))
  "Helm source for known projectile projects.")

(cl-defmethod helm-setup-user-source ((source helm-projectile-projects-source))
  "Make SOURCE specific to project switching.
The `helm-projectile-projects-source` inherits from
`helm-type-file` (which see), which sets up actions, keymap, and
help message slots to file specific ones.  Override these slots
to be specific to `helm-projectile-projects-source'."
  (setf (slot-value source 'action) 'helm-source-projectile-projects-actions)
  (setf (slot-value source 'keymap) helm-projectile-projects-map)
  ;; Use `ignore' as a persistent action, to actually keep `helm' session
  ;; when `helm-execute-persistent-action' is executed.
  (setf (slot-value source 'persistent-action) #'ignore)
  (let ((persistent-help "Do Nothing"))
    (setf (slot-value source 'persistent-help) persistent-help)
    (setf (slot-value source 'header-line)
          (helm-source--persistent-help-string
           persistent-help
           source)))
  (setf (slot-value source 'mode-line)
        (list "Project(s)" helm-mode-line-string)))

(defvar helm-source-projectile-projects
  (helm-make-source "Projectile projects" 'helm-projectile-projects-source))

(defclass helm-projectile-projects-other-window-source (helm-projectile-projects-source)
  ())

(cl-defmethod helm-setup-user-source :after ((source helm-projectile-projects-other-window-source))
  "Set `helm-projectile-switch-project-by-name-other-window' as the first action."
  (setf (slot-value source 'action)
        (helm-projectile-hack-actions
         helm-source-projectile-projects-actions
         '(helm-projectile-switch-project-by-name-other-window . :make-first))))

(defclass helm-projectile-projects-other-frame-source (helm-projectile-projects-source)
  ())

(cl-defmethod helm-setup-user-source :after ((source helm-projectile-projects-other-frame-source))
  "Set `helm-projectile-switch-project-by-name-other-frame' as the first action."
  (setf (slot-value source 'action)
        (helm-projectile-hack-actions
         helm-source-projectile-projects-actions
         '(helm-projectile-switch-project-by-name-other-frame . :make-first))))

(defvar helm-projectile-dirty-projects-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map helm-map)
    (helm-projectile-define-key map
      (kbd "C-d") #'dired
      (kbd "M-o") #'helm-projectile-switch-project-by-name
      (kbd "C-c o") #'helm-projectile-switch-project-by-name-other-window
      (kbd "C-c C-o") #'helm-projectile-switch-project-by-name-other-frame
      (kbd "M-e") #'helm-projectile-switch-to-shell
      (kbd "C-s") #'helm-projectile-grep
      (kbd "M-c") #'helm-projectile-compile-project
      (kbd "M-t") #'helm-projectile-test-project
      (kbd "M-r") #'helm-projectile-run-project
      (kbd "M-D") #'helm-projectile-remove-known-project)
    map)
  "Mapping for dirty projectile projects.")

(defvar helm-source-projectile-dirty-projects
  (helm-build-sync-source "Projectile dirty projects"
    :candidates (lambda () (with-helm-current-buffer (helm-projectile-get-dirty-projects)))
    :fuzzy-match helm-projectile-fuzzy-match
    :keymap helm-projectile-dirty-projects-map
    :mode-line helm-read-file-name-mode-line-string
    :action '(("Open project root in vc-dir or magit" . helm-projectile-vc)
              ("Switch to project `M-o'" . helm-projectile-switch-project-by-name)
              ("Switch to project other window `C-c o'" . helm-projectile-switch-project-by-name-other-window)
              ("Switch to project other frame `C-c C-o'" . helm-projectile-switch-project-by-name-other-frame)
              ("Open Dired in project's directory `C-d'" . dired)
              ("Switch to Eshell `M-e'" . helm-projectile-switch-to-shell)
              ("Grep in projects `C-s'" . helm-projectile-grep)
              ("Compile project `M-c'. With C-u, new compile command"
               . helm-projectile-compile-project)))
    "Helm source for dirty version controlled projectile projects.")

(defun helm-projectile-get-dirty-projects ()
  "Return dirty version controlled known projects.
The value is returned as an alist to have a nice display in Helm."
  (message "Checking for dirty known projects...")
  (let* ((status (projectile-check-vcs-status-of-known-projects))
         (proj-dir (cl-loop for stat in status
                            collect (car stat)))
         (status-display (cl-loop for stat in status collect
                                  (propertize (format "[%s]"
                                                      (mapconcat 'identity
                                                                 (car (cdr stat)) ", "))
                                              'face 'helm-match)))
         (max-status-display-length (cl-loop for sd in status-display
                                             maximize (length sd)))
         (status-display (cl-loop for sd in status-display collect
                                  (format "%s%s    "
                                          sd
                                          (make-string
                                           (- max-status-display-length (length sd)) ? ))))
         (full-display (cl-mapcar 'concat
                                  status-display
                                  (mapcar (lambda (dir)
                                            (propertize dir 'face 'helm-ff-directory))
                                          proj-dir))))
    (cl-pairlis full-display proj-dir)))

(define-key helm-etags-map (kbd "C-c p f")
  (lambda ()
    (interactive)
    (helm-run-after-exit 'helm-projectile-find-file nil)))

(defun helm-projectile-file-persistent-action (candidate)
  "Previews the contents of a file CANDIDATE in a temporary buffer.
This is a persistent action for file-related functionality."
  (let ((buf (get-buffer-create " *helm-projectile persistent*")))
    (cl-flet ((preview (candidate)
                       (switch-to-buffer buf)
                       (setq inhibit-read-only t)
                       (erase-buffer)
                       (insert-file-contents candidate)
                       (let ((buffer-file-name candidate))
                         (set-auto-mode))
                       (font-lock-ensure)
                       (setq inhibit-read-only nil)))
      (if (and (helm-get-attr 'previewp)
               (string= candidate (helm-get-attr 'current-candidate)))
          (progn
            (kill-buffer buf)
            (helm-set-attr 'previewp nil))
        (preview candidate)
        (helm-set-attr 'previewp t)))
    (helm-set-attr 'current-candidate candidate)))

(defun helm-projectile-find-files-eshell-command-on-file-action (candidate)
  "Execute an eshell command on a file CANDIDATE."
  (interactive)
  (let* ((helm-ff-default-directory (file-name-directory candidate)))
    (helm-find-files-eshell-command-on-file candidate)))

(defun helm-projectile-ff-etags-select-action (candidate)
  "Jump to etags for file CANDIDATE.
See also `helm-etags-select'."
  (interactive)
  (let* ((helm-ff-default-directory (file-name-directory candidate)))
    (helm-ff-etags-select candidate)))

(defun helm-projectile-switch-to-shell (dir)
  "Within DIR, switch to a shell corresponding to `helm-ff-preferred-shell-mode'."
  (interactive)
  (let* ((projectile-require-project-root nil)
         (helm-ff-default-directory (file-name-directory (projectile-expand-root dir))))
    (helm-ff-switch-to-shell dir)))

(defun helm-projectile-files-in-current-dired-buffer ()
  "Return a list of files (only) in the current Dired buffer."
  (let (flist)
    (cl-flet ((fpush (fname) (push fname flist)))
      (save-excursion
        (let (file buffer-read-only)
          (goto-char (point-min))
          (while (not (eobp))
            (save-excursion
              (and (not (eolp))
                   (setq file (dired-get-filename t t)) ; nil on non-file
                   (progn (end-of-line)
                          (funcall #'fpush file))))
            (forward-line 1)))))
    (mapcar 'file-truename (nreverse flist))))

(defun helm-projectile-all-dired-buffers ()
  "Get all current Dired buffers."
  (mapcar (lambda (b)
            (with-current-buffer b (buffer-name)))
          (cl-remove-if-not
           (lambda (b)
             (with-current-buffer b
               (and (eq major-mode 'dired-mode)
                    (buffer-name))))
           (buffer-list))))

(defvar helm-projectile-virtual-dired-remote-enable nil
  "Enable virtual Dired manager on remote host.
Disabled by default.")

(defun helm-projectile-dired-files-new-action (candidate)
  "Create a Dired buffer from chosen files.
CANDIDATE is the selected file, but choose the marked files if available."
  (if (and (file-remote-p (projectile-project-root))
           (not helm-projectile-virtual-dired-remote-enable))
      (message "Virtual Dired manager is disabled in remote host. Enable with %s."
               (propertize "helm-projectile-virtual-dired-remote-enable" 'face 'font-lock-keyword-face))
    (let ((files (cl-remove-if-not
                  (lambda (f)
                    (not (string= f "")))
                  (mapcar (lambda (file)
                            (replace-regexp-in-string (projectile-project-root) "" file))
                          (helm-marked-candidates :with-wildcard t))))
          (new-name (completing-read "Select or enter a new buffer name: "
                                     (helm-projectile-all-dired-buffers)))
          (helm--reading-passwd-or-string t)
          (default-directory (projectile-project-root)))
      ;; create a unique buffer that is unique to any directory in default-directory
      ;; or opened buffer; when Dired is passed with a non-existence directory name,
      ;; it only creates a buffer and insert everything. If a new name user supplied
      ;; exists as default-directory, Dired throws error when insert anything that
      ;; does not exist in current directory.
      (with-current-buffer (dired (cons (make-temp-name new-name)
                                        (if files
                                            files
                                          (list candidate))))
        (when (get-buffer new-name)
          (kill-buffer new-name))
        (rename-buffer new-name)))))

(defun helm-projectile-dired-files-add-action (candidate)
  "Add files to a Dired buffer.
CANDIDATE is the selected file.  Used when no file is explicitly marked."
  (if (and (file-remote-p (projectile-project-root))
           (not helm-projectile-virtual-dired-remote-enable))
      (message "Virtual Dired manager is disabled in remote host. Enable with %s."
               (propertize "helm-projectile-virtual-dired-remote-enable" 'face 'font-lock-keyword-face))
    (if (eq (with-helm-current-buffer major-mode) 'dired-mode)
        (let* ((marked-files (helm-marked-candidates :with-wildcard t))
               (helm--reading-passwd-or-string t)
               (root (projectile-project-root)) ; store root for later use
               (dired-buffer-name (or (and (eq major-mode 'dired-mode) (buffer-name))
                                      (completing-read "Select a Dired buffer:"
                                                       (helm-projectile-all-dired-buffers))))
               (dired-files (with-current-buffer dired-buffer-name
                              (helm-projectile-files-in-current-dired-buffer)))
               (files (sort (mapcar (lambda (file)
                                      (replace-regexp-in-string (projectile-project-root) "" file))
                                    (cl-nunion (if marked-files
                                                   marked-files
                                                 (list candidate))
                                               dired-files
                                               :test #'string-equal))
                            'string-lessp)))
          (kill-buffer dired-buffer-name)
          ;; Rebind default-directory because after killing a buffer, we
          ;; could be in any buffer and default-directory is set to that
          ;; random buffer
          ;;
          ;; Also use saved root directory, because after killing a buffer,
          ;; we could be outside of current project
          (let ((default-directory root))
            (with-current-buffer (dired (cons (make-temp-name dired-buffer-name)
                                              (if files
                                                  (mapcar (lambda (file)
                                                            (replace-regexp-in-string root "" file))
                                                          files)
                                                (list candidate))))
              (rename-buffer dired-buffer-name))))
      (error "You're not in a Dired buffer to add"))))

(defun helm-projectile-dired-files-delete-action (candidate)
  "Delete selected entries from a Dired buffer.
CANDIDATE is the selected file.  Used when no file is explicitly marked."
  (if (and (file-remote-p (projectile-project-root))
           (not helm-projectile-virtual-dired-remote-enable))
      (message "Virtual Dired manager is disabled in remote host. Enable with %s."
               (propertize "helm-projectile-virtual-dired-remote-enable" 'face 'font-lock-keyword-face))
    (let* ((helm--reading-passwd-or-string t)
           (root (projectile-project-root))
           (dired-buffer-name (with-helm-current-buffer (buffer-name)))
           (dired-files (with-current-buffer dired-buffer-name
                          (helm-projectile-files-in-current-dired-buffer)))
           (files (sort (cl-set-exclusive-or (helm-marked-candidates :with-wildcard t)
                                             dired-files
                                             :test #'string-equal) #'string-lessp)))
      (kill-buffer dired-buffer-name)
      ;; similar reason to `helm-projectile-dired-files-add-action'
      (let ((default-directory root))
        (with-current-buffer (dired (cons (make-temp-name dired-buffer-name)
                                          (if files
                                              (mapcar (lambda (file)
                                                        (replace-regexp-in-string root "" file))
                                                      files)
                                            (list candidate))))
          (rename-buffer dired-buffer-name))))))

(defun helm-projectile-run-projectile-hooks-after-find-file (_orig-fun &rest _args)
  "Run `projectile-find-file-hook' if using projectile."
  (when (and projectile-mode (projectile-project-p))
    (run-hooks 'projectile-find-file-hook)))

(advice-add 'helm-find-file-or-marked
            :after #'helm-projectile-run-projectile-hooks-after-find-file)

(defvar helm-projectile-find-file-map
  (let ((map (copy-keymap helm-find-files-map)))
    (helm-projectile-define-key map
      (kbd "C-c f") #'helm-projectile-dired-files-new-action
      (kbd "C-c a") #'helm-projectile-dired-files-add-action
      (kbd "M-e") #'helm-projectile-switch-to-shell
      (kbd "M-.") #'helm-projectile-ff-etags-select-action
      (kbd "M-!") #'helm-projectile-find-files-eshell-command-on-file-action)
    (define-key map (kbd "<left>") #'helm-previous-source)
    (define-key map (kbd "<right>") #'helm-next-source)
    (dolist (cmd '(helm-find-files-up-one-level
                   helm-find-files-down-last-level))
      (substitute-key-definition cmd nil map))
    map)
  "Mapping for file commands in Helm Projectile.")

(defvar helm-projectile-file-actions
  (helm-projectile-hack-actions
   helm-find-files-actions
   ;; Delete these actions
   'helm-ff-browse-project
   'helm-insert-file-name-completion-at-point
   'helm-ff-find-sh-command
   'helm-ff-cache-add-file
   ;; Substitute these actions
   '(helm-ff-switch-to-shell . helm-projectile-switch-to-shell)
   '(helm-ff-etags-select     . helm-projectile-ff-etags-select-action)
   '(helm-find-files-eshell-command-on-file
     . helm-projectile-find-files-eshell-command-on-file-action)
   ;; Change action descriptions
   '(helm-find-file-as-root . "Find file as root `C-c r'")
   ;; New actions
   '(helm-projectile-dired-files-new-action
     . "Create Dired buffer from files `C-c f'")
   '(helm-projectile-dired-files-add-action
     . "Add files to Dired buffer `C-c a'"))
  "Action for files.")

(defun helm-projectile--move-selection-p (selection)
  "Return non-nil if should move Helm selector after SELECTION.

SELECTION should be moved unless it's one of:

- Non-string
- Existing file
- Non-remote file that matches `helm-tramp-file-name-regexp'"
  (not (or (not (stringp selection))
         (file-exists-p selection)
         (and (string-match helm-tramp-file-name-regexp selection)
              (not (file-remote-p selection nil t))))))

(defun helm-projectile--move-to-real ()
  "Move to first real candidate.

Similar to `helm-ff--move-to-first-real-candidate', but without
unnecessary complexity."
  (while (let* ((src (helm-get-current-source))
                (selection (and (not (helm-empty-source-p))
                                (helm-get-selection nil nil src))))
           (and (not (helm-end-of-source-p))
                (helm-projectile--move-selection-p selection)))
    (helm-next-line)))

(defun helm-projectile--remove-move-to-real ()
  "Hook function to remove `helm-projectile--move-to-real'.

Meant to be added to `helm-cleanup-hook', from which it removes
 itself at the end."
  (remove-hook 'helm-after-update-hook #'helm-projectile--move-to-real)
  (remove-hook 'helm-cleanup-hook #'helm-projectile--remove-move-to-real))

(defvar helm-source-projectile-files-list-before-init-hook
  (lambda ()
    (add-hook 'helm-after-update-hook #'helm-projectile--move-to-real)
    (add-hook 'helm-cleanup-hook #'helm-projectile--remove-move-to-real)))

(defclass helm-source-projectile-file (helm-source-sync)
  ((before-init-hook :initform 'helm-source-projectile-files-list-before-init-hook)
   (candidates
    :initform (lambda ()
                (when (projectile-project-p)
                  (with-helm-current-buffer
                    (helm-projectile--files-display-real (projectile-current-project-files)
                                                         (projectile-project-root))))))
   (filtered-candidate-transformer
    :initform (lambda (files _source)
                (with-helm-current-buffer
                  (let* ((root (projectile-project-root))
                         (file-at-root (file-relative-name (expand-file-name helm-pattern root))))
                    (if (or (string-empty-p helm-pattern)
                            (assoc helm-pattern files))
                        files
                      (if (equal helm-pattern file-at-root)
                          (cl-acons (helm-ff-prefix-filename helm-pattern nil t)
                                    (expand-file-name helm-pattern)
                                    files)
                        (cl-pairlis (list (helm-ff-prefix-filename helm-pattern nil t)
                                          (helm-ff-prefix-filename file-at-root nil t))
                                    (list (expand-file-name helm-pattern)
                                          (expand-file-name helm-pattern root))
                                    files)))))))
   (fuzzy-match :initform 'helm-projectile-fuzzy-match)
   (keymap :initform 'helm-projectile-find-file-map)
   (help-message :initform 'helm-ff-help-message)
   (mode-line :initform 'helm-read-file-name-mode-line-string)
   (action :initform 'helm-projectile-file-actions)
   (persistent-action :initform #'helm-projectile-file-persistent-action)
   (persistent-help :initform "Preview file")))

(defvar helm-source-projectile-files-list
  (helm-make-source "Projectile files" 'helm-source-projectile-file)
  "Helm source definition for Projectile files.")

(defclass helm-source-projectile-file-other-window (helm-source-projectile-file)
  ())

(cl-defmethod helm-setup-user-source ((source helm-source-projectile-file-other-window))
  "Make `helm-find-files-other-window' the first action in SOURCE."
  (setf (slot-value source 'action)
        (helm-projectile-hack-actions
         helm-projectile-file-actions
         '(helm-find-files-other-window . :make-first))))

(defvar helm-source-projectile-files-other-window-list
  (helm-make-source "Projectile files" 'helm-source-projectile-file-other-window)
  "Helm source definition for Projectile files.")

(defclass helm-source-projectile-file-other-frame (helm-source-projectile-file)
  ())

(cl-defmethod helm-setup-user-source ((source helm-source-projectile-file-other-frame))
  "Make `find-file-other-frame' the first action in SOURCE."
  (setf (slot-value source 'action)
        (helm-projectile-hack-actions
         helm-projectile-file-actions
         '(find-file-other-frame . :make-first))))

(defvar helm-source-projectile-files-other-frame-list
  (helm-make-source "Projectile files" 'helm-source-projectile-file-other-frame)
  "Helm source definition for Projectile files.")

(defvar helm-source-projectile-files-in-all-projects-list
  (helm-build-sync-source "Projectile files in all Projects"
    :candidates (lambda ()
                  (with-helm-current-buffer
                    (let ((projectile-require-project-root nil))
                      (projectile-all-project-files))))
    :keymap helm-projectile-find-file-map
    :help-message 'helm-ff-help-message
    :mode-line helm-read-file-name-mode-line-string
    :action helm-projectile-file-actions
    :persistent-action #'helm-projectile-file-persistent-action
    :persistent-help "Preview file")
  "Helm source definition for all Projectile files in all projects.")

(defvar helm-projectile-dired-file-actions
  (helm-projectile-hack-actions
   helm-projectile-file-actions
   ;; New actions
   '(helm-projectile-dired-files-delete-action . "Remove entry(s) from Dired buffer `C-c d'")))

(defclass helm-source-projectile-dired-file (helm-source-in-buffer)
  ((data :initform (lambda ()
                     (if (and (file-remote-p (projectile-project-root))
                              (not helm-projectile-virtual-dired-remote-enable))
                         nil
                       (when (eq major-mode 'dired-mode)
                         (helm-projectile-files-in-current-dired-buffer)))))
   (filter-one-by-one :initform (lambda (file)
                                  (let ((helm-ff-transformer-show-only-basename t))
                                    (helm-ff-filter-candidate-one-by-one file))))
   (action-transformer :initform 'helm-find-files-action-transformer)
   (keymap :initform (let ((map (copy-keymap helm-projectile-find-file-map)))
                       (helm-projectile-define-key map
                         (kbd "C-c d") 'helm-projectile-dired-files-delete-action)
                       map))
    (help-message :initform 'helm-ff-help-message)
    (mode-line :initform 'helm-read-file-name-mode-line-string)
    (action :initform 'helm-projectile-dired-file-actions)))

(defvar helm-source-projectile-dired-files-list
  (helm-make-source "Projectile files in current Dired buffer"
    'helm-source-projectile-dired-file)
  "Helm source definition for Projectile delete files.")

(defclass helm-source-projectile-dired-file-other-window (helm-source-projectile-dired-file)
  ())

(cl-defmethod helm-setup-user-source ((source helm-source-projectile-dired-file-other-window))
  "Make `helm-find-files-other-window' the first action in SOURCE."
  (setf (slot-value source 'action)
        (helm-projectile-hack-actions
         helm-projectile-dired-file-actions
         '(helm-find-files-other-window . :make-first))))

(defvar helm-source-projectile-dired-files-other-window-list
  (helm-make-source "Projectile files in current Dired buffer"
    'helm-source-projectile-dired-file-other-window)
  "Helm source definition for Projectile delete files.")

(defclass helm-source-projectile-dired-file-other-frame (helm-source-projectile-dired-file)
  ())

(cl-defmethod helm-setup-user-source ((source helm-source-projectile-dired-file-other-frame))
  "Make `find-file-other-frame' the first action in SOURCE."
  (setf (slot-value source 'action)
        (helm-projectile-hack-actions
         helm-projectile-dired-file-actions
         '(find-file-other-frame . :make-first))))

(defvar helm-source-projectile-dired-files-other-frame-list
  (helm-make-source "Projectile files in current Dired buffer"
    'helm-source-projectile-dired-file-other-frame)
  "Helm source definition for Projectile delete files.")

(defun helm-projectile-dired-find-dir (dir)
  "Jump to a selected directory DIR from `helm-projectile'."
  (dired (expand-file-name dir (projectile-project-root)))
  (run-hooks 'projectile-find-dir-hook))

(defun helm-projectile-dired-find-dir-other-window (dir)
  "Jump to a selected directory DIR from `helm-projectile' (in other window)."
  (dired-other-window (expand-file-name dir (projectile-project-root)))
  (run-hooks 'projectile-find-dir-hook))

(defun helm-projectile-dired-find-dir-other-frame (dir)
  "Jump to a selected directory DIR from `helm-projectile' (in other frame)."
  (dired-other-frame (expand-file-name dir (projectile-project-root)))
  (run-hooks 'projectile-find-dir-hook))

(defvar helm-source-projectile-directory-actions
  '(("Open Dired" . helm-projectile-dired-find-dir)
    ("Open Dired in other window `C-c o'" . helm-projectile-dired-find-dir-other-window)
    ("Open Dired in other frame `C-c C-o'" . helm-projectile-dired-find-dir-other-frame)
    ("Switch to Eshell `M-e'" . helm-projectile-switch-to-shell)
    ("Grep in projects `C-s'" . helm-projectile-grep)
    ("Create Dired buffer from files `C-c f'" . helm-projectile-dired-files-new-action)
    ("Add files to Dired buffer `C-c a'" . helm-projectile-dired-files-add-action)))

(defclass helm-source-projectile-directory (helm-source-sync)
  ((candidates :initform (lambda ()
                           (when (projectile-project-p)
                             (with-helm-current-buffer
                               (let ((dirs (if projectile-find-dir-includes-top-level
                                               (append '("./") (projectile-current-project-dirs))
                                             (projectile-current-project-dirs))))
                                 (helm-projectile--files-display-real dirs (projectile-project-root)))))))
   (fuzzy-match :initform 'helm-projectile-fuzzy-match)
   (action-transformer :initform 'helm-find-files-action-transformer)
   (keymap :initform (let ((map (make-sparse-keymap)))
                       (set-keymap-parent map helm-map)
                       (helm-projectile-define-key map
                         (kbd "<left>") #'helm-previous-source
                         (kbd "<right>") #'helm-next-source
                         (kbd "C-c o") #'helm-projectile-dired-find-dir-other-window
                         (kbd "C-c C-o") #'helm-projectile-dired-find-dir-other-frame
                         (kbd "M-e")   #'helm-projectile-switch-to-shell
                         (kbd "C-c f") #'helm-projectile-dired-files-new-action
                         (kbd "C-c a") #'helm-projectile-dired-files-add-action
                         (kbd "C-s")   #'helm-projectile-grep)
                       map))
   (help-message :initform 'helm-ff-help-message)
   (mode-line :initform 'helm-read-file-name-mode-line-string)
   (action :initform 'helm-source-projectile-directory-actions)))

(defvar helm-source-projectile-directories-list
  (helm-make-source "Projectile directories" 'helm-source-projectile-directory)
  "Helm source for listing project directories.")

(defclass helm-source-projectile-directory-other-window (helm-source-projectile-directory)
  ())

(cl-defmethod helm-setup-user-source ((source helm-source-projectile-directory-other-window))
  "Make `helm-projectile-dired-find-dir-other-window' the first action in SOURCE."
  (setf (slot-value source 'action)
        (helm-projectile-hack-actions
         helm-source-projectile-directory-actions
         '(helm-projectile-dired-find-dir-other-window . :make-first))))

(defvar helm-source-projectile-directories-other-window-list
  (helm-make-source "Projectile directories" 'helm-source-projectile-directory-other-window)
  "Helm source for listing project directories.")

(defclass helm-source-projectile-directory-other-frame (helm-source-projectile-directory)
  ())

(cl-defmethod helm-setup-user-source ((source helm-source-projectile-directory-other-frame))
  "Make `helm-projectile-dired-find-dir-other-frame' the first action in SOURCE."
  (setf (slot-value source 'action)
        (helm-projectile-hack-actions
         helm-source-projectile-directory-actions
         '(helm-projectile-dired-find-dir-other-frame . :make-first))))

(defvar helm-source-projectile-directories-other-frame-list
  (helm-make-source "Projectile directories" 'helm-source-projectile-directory-other-frame)
  "Helm source for listing project directories.")

(defvar helm-projectile-buffers-list-cache nil)

(defclass helm-source-projectile-buffer (helm-source-sync helm-type-buffer)
  ((init :initform (lambda ()
                     ;; Issue #51 Create the list before `helm-buffer' creation.
                     (setq helm-projectile-buffers-list-cache
                           (ignore-errors (remove (buffer-name) (projectile-project-buffer-names))))
                     (let ((result (cl-loop for b in helm-projectile-buffers-list-cache
                                            maximize (length b) into len-buf
                                            maximize (length (with-current-buffer b
                                                               (symbol-name major-mode)))
                                            into len-mode
                                            finally return (cons len-buf len-mode))))
                       (unless (default-value 'helm-buffer-max-length)
                         (helm-set-local-variable 'helm-buffer-max-length (car result)))
                       (unless (default-value 'helm-buffer-max-len-mode)
                         ;; If a new buffer is longer that this value
                         ;; this value will be updated
                         (helm-set-local-variable 'helm-buffer-max-len-mode (cdr result))))))
   (candidates :initform 'helm-projectile-buffers-list-cache)
   (matchplugin :initform nil)
   (match :initform 'helm-buffers-match-function)
   (persistent-action :initform 'helm-buffers-list-persistent-action)
   (keymap :initform 'helm-buffer-map)
   (volatile :initform t)
   (persistent-help
    :initform
    "Show this buffer / C-u \\[helm-execute-persistent-action]: Kill this buffer")))

(defvar helm-source-projectile-buffers-list
  (helm-make-source "Project buffers" 'helm-source-projectile-buffer))

(defclass helm-source-projectile-buffer-other-window (helm-source-projectile-buffer)
  ())

(cl-defmethod helm-setup-user-source ((source helm-source-projectile-buffer-other-window))
  "Make `helm-buffer-switch-buffers-other-window' first action in SOURCE."
  (setf (slot-value source 'action)
        (helm-projectile-hack-actions
         helm-type-buffer-actions
         '(helm-buffer-switch-buffers-other-window . :make-first))))

(defvar helm-source-projectile-buffers-other-window-list
  (helm-make-source "Project buffers" 'helm-source-projectile-buffer-other-window))

(defclass helm-source-projectile-buffer-other-frame (helm-source-projectile-buffer)
  ())

(cl-defmethod helm-setup-user-source ((source helm-source-projectile-buffer-other-frame))
  "Make `helm-buffer-switch-to-buffer-other-frame' first action in SOURCE."
  (setf
   (slot-value source 'action)
   (helm-projectile-hack-actions
    helm-type-buffer-actions
    '(helm-buffer-switch-to-buffer-other-frame . :make-first))))

(defvar helm-source-projectile-buffers-other-frame-list
  (helm-make-source "Project buffers" 'helm-source-projectile-buffer-other-frame))

(defvar helm-source-projectile-recentf-list
  (helm-build-sync-source "Projectile recent files"
    :candidates (lambda ()
                  (when (projectile-project-p)
                    (with-helm-current-buffer
                      (helm-projectile--files-display-real (projectile-recentf-files)
                                                           (projectile-project-root)))))
    :fuzzy-match helm-projectile-fuzzy-match
    :keymap helm-projectile-find-file-map
    :help-message 'helm-ff-help-message
    :mode-line helm-read-file-name-mode-line-string
    :action helm-projectile-file-actions
    :persistent-action #'helm-projectile-file-persistent-action
    :persistent-help "Preview file")
  "Helm source definition for recent files in current project.")

(defcustom helm-projectile-git-grep-command
  "git --no-pager grep --no-color -n%c -e %p -- %f"
  "Command to execute when performing `helm-grep' inside a projectile git project.
See documentation of `helm-grep-default-command' for the format."
  :type 'string
  :group 'helm-projectile)

(defcustom helm-projectile-grep-command
  "grep -a -r %e -n%cH -e %p %f ."
  "Command to execute when performing `helm-grep' outside a projectile git project.
See documentation of `helm-grep-default-command' for the format."
  :type 'string
  :group 'helm-projectile)


(defcustom helm-projectile-sources-list
  '(helm-source-projectile-buffers-list
    helm-source-projectile-files-list
    helm-source-projectile-projects)
  "Default sources for `helm-projectile'."
  :type '(repeat symbol)
  :group 'helm-projectile)

(defmacro helm-projectile-command (command source prompt &optional not-require-root truncate-lines-var)
  "Template for generic `helm-projectile' commands.
COMMAND is a command name to be appended with \"helm-projectile\" prefix.
SOURCE is a Helm source that should be Projectile specific.
PROMPT is a string for displaying as a prompt.
NOT-REQUIRE-ROOT specifies the command doesn't need to be used in a
project root.
TRUNCATE-LINES-VAR is the symbol used dictate truncation of lines.
Defaults is `helm-projectile-truncate-lines'."
  (unless truncate-lines-var (setq truncate-lines-var 'helm-projectile-truncate-lines))
  `(defun ,(intern (concat "helm-projectile-" command)) (&optional arg)
     "Use projectile with Helm for finding files in project

With a prefix ARG invalidates the cache first."
     (interactive "P")
     (if (projectile-project-p)
         (projectile-maybe-invalidate-cache arg)
       (unless ,not-require-root
         (error "You're not in a project")))
     (let ((helm-ff-transformer-show-only-basename nil)
           ;; for consistency, we should just let Projectile take care of ignored files
           (helm-boring-file-regexp-list nil))
       (helm :sources ,source
             :buffer (concat "*helm projectile: " (projectile-project-name) "*")
             :truncate-lines ,truncate-lines-var
             :prompt (projectile-prepend-project-name ,prompt)))))

;; You can evaluate the following command to help inserting autoloads for the
;; `helm-projectile-command' macro. To use: move point to a form that calls
;; `helm-projectile-command' and type:
;;
;;   M-x helm-projectile-command-insert-autoload
;;
;; (defun helm-projectile-command-insert-autoload ()
;;   "Insert autoload for a helm-projectile-command at point."
;;   (interactive)
;;   (save-excursion
;;     (end-of-defun)
;;     (beginning-of-defun)
;;     (when-let* ((beg (point))
;;                 (form (funcall load-read-function (current-buffer)))
;;                 ((eq (car form) 'helm-projectile-command))
;;                 (command (concat "helm-projectile-" (cadr form)))
;;                 (file (file-name-sans-extension
;;                        (file-name-nondirectory
;;                         (buffer-file-name)))))
;;       (goto-char beg)
;;       (insert ";;;###autoload(autoload '" command " \"" file "\" nil t)\n"))))

;;;###autoload(autoload 'helm-projectile-switch-project "helm-projectile" nil t)
(helm-projectile-command "switch-project"
                         'helm-source-projectile-projects
                         "Switch to project: " t)

;;;###autoload(autoload 'helm-projectile-switch-project-other-window "helm-projectile" nil t)
(helm-projectile-command "switch-project-other-window"
                         (helm-make-source
                             "Projectile projects"
                             'helm-projectile-projects-other-window-source)
                         "Switch to project: " t)

;;;###autoload(autoload 'helm-projectile-switch-project-other-frame "helm-projectile" nil t)
(helm-projectile-command "switch-project-other-frame"
                         (helm-make-source
                             "Projectile projects"
                             'helm-projectile-projects-other-frame-source)
                         "Switch to project: " t)

;;;###autoload(autoload 'helm-projectile-find-file "helm-projectile" nil t)
(helm-projectile-command "find-file"
                         '(helm-source-projectile-dired-files-list
                           helm-source-projectile-files-list)
                         "Find file: ")
;;;###autoload(autoload 'helm-projectile-find-file-other-window "helm-projectile" nil t)
(helm-projectile-command "find-file-other-window"
                         '(helm-source-projectile-dired-files-other-window-list
                           helm-source-projectile-files-other-window-list)
                         "Find file (other window): ")

;;;###autoload(autoload 'helm-projectile-find-file-other-frame "helm-projectile" nil t)
(helm-projectile-command "find-file-other-frame"
                         '(helm-source-projectile-dired-files-other-frame-list
                           helm-source-projectile-files-other-frame-list)
                         "Find file (other frame): ")

;;;###autoload(autoload 'helm-projectile-find-file-in-known-projects "helm-projectile" nil t)
(helm-projectile-command "find-file-in-known-projects" 'helm-source-projectile-files-in-all-projects-list "Find file in projects: " t)

;;;###autoload(autoload 'helm-projectile-find-dir "helm-projectile" nil t)
(helm-projectile-command "find-dir"
                         '(helm-source-projectile-dired-files-list
                           helm-source-projectile-directories-list)
                         "Find dir: ")

;;;###autoload(autoload 'helm-projectile-find-dir-other-window "helm-projectile" nil t)
(helm-projectile-command "find-dir-other-window"
                         '(helm-source-projectile-dired-files-other-window-list
                           helm-source-projectile-directories-other-window-list)
                         "Find dir (other window): ")

;;;###autoload(autoload 'helm-projectile-find-dir-other-frame "helm-projectile" nil t)
(helm-projectile-command "find-dir-other-frame"
                         '(helm-source-projectile-dired-files-other-frame-list
                           helm-source-projectile-directories-other-frame-list)
                         "Find dir (other frame): ")

;;;###autoload(autoload 'helm-projectile-recentf "helm-projectile" nil t)
(helm-projectile-command "recentf" 'helm-source-projectile-recentf-list "Recently visited file: ")

;;;###autoload(autoload 'helm-projectile-switch-to-buffer "helm-projectile" nil t)
(helm-projectile-command "switch-to-buffer"
                         'helm-source-projectile-buffers-list
                         "Switch to buffer: " nil helm-buffers-truncate-lines)

;;;###autoload(autoload 'helm-projectile-switch-to-buffer-other-window "helm-projectile" nil t)
(helm-projectile-command "switch-to-buffer-other-window"
                         'helm-source-projectile-buffers-other-window-list
                         "Switch to buffer (other window): " nil helm-buffers-truncate-lines)

;;;###autoload(autoload 'helm-projectile-switch-to-buffer-other-frame "helm-projectile" nil t)
(helm-projectile-command "switch-to-buffer-other-frame"
                         'helm-source-projectile-buffers-other-frame-list
                         "Switch to buffer (other frame): " nil helm-buffers-truncate-lines)

;;;###autoload(autoload 'helm-projectile-browse-dirty-projects "helm-projectile" nil t)
(helm-projectile-command "browse-dirty-projects" 'helm-source-projectile-dirty-projects "Select a project: " t)

(defun helm-projectile--files-display-real (files root)
  "Create (DISPLAY . REAL) pairs with FILES and ROOT.

  DISPLAY is the short file name.  REAL is the full path."
  ;; Use `helm-ff-filter-candidate-one-by-one' (just like `helm-find-files-get-candidates' does).
  ;; With a twist that some of files may contain a directory component.
  ;; In such a case `helm-ff-filter-candidate-one-by-one' just returns a file component,
  ;; so we the do a concatenation of file and directory components manually.
  (cl-loop with default-directory = root
           for file in files
           collect (let ((file-res (helm-ff-filter-candidate-one-by-one file nil t)))
                     (if-let* ((directory (file-name-directory file)))
                         (cons (concat (if-let* ((face (get-text-property
                                                        0 'face (car file-res))))
                                           (propertize directory 'face face)
                                         directory)
                                       (unless (file-directory-p file)
                                         (car file-res)))
                               (cdr file-res))
                       file-res))))

(defun helm-projectile--find-file-dwim-1 (one-candidate-action actions prompt)
  "Find file at point based on context.
Execute ONE-CANDIDATE-ACTION when there is a single file returned by
`projectile-select-files' (which see).  Otherwise display a Helm with
ACTIONS and PROMPT with other selected files."
  (let* ((project-root (projectile-project-root))
         (project-files (projectile-current-project-files))
         (files (projectile-select-files project-files)))
    (if (= (length files) 1)
        (funcall one-candidate-action (expand-file-name (car files) (projectile-project-root)))
      (helm :sources (helm-build-sync-source "Projectile files"
                       :candidates (if (> (length files) 1)
                                       (helm-projectile--files-display-real files project-root)
                                     (helm-projectile--files-display-real project-files project-root))
                       :fuzzy-match helm-projectile-fuzzy-match
                       :action-transformer 'helm-find-files-action-transformer
                       :keymap helm-projectile-find-file-map
                       :help-message helm-ff-help-message
                       :mode-line helm-read-file-name-mode-line-string
                       :action actions
                       :persistent-action #'helm-projectile-file-persistent-action
                       :persistent-help "Preview file")
            :buffer "*helm projectile*"
            :truncate-lines helm-projectile-truncate-lines
            :prompt (projectile-prepend-project-name prompt)))))

;;;###autoload
(defun helm-projectile-find-file-dwim ()
  "Find file at point based on context."
  (interactive)
  (helm-projectile--find-file-dwim-1
   #'find-file helm-projectile-file-actions "Find file: "))

;;;###autoload
(defun helm-projectile-find-file-dwim-other-window ()
  "Find file at point based on context."
  (interactive)
  (helm-projectile--find-file-dwim-1
   #'find-file-other-window
   (helm-projectile-hack-actions
    helm-projectile-file-actions
    '(helm-find-files-other-window . :make-first))
   "Find file (other window): "))

;;;###autoload
(defun helm-projectile-find-file-dwim-other-frame ()
  "Find file at point based on context."
  (interactive)
  (helm-projectile--find-file-dwim-1
   #'find-file-other-frame
   (helm-projectile-hack-actions
    helm-projectile-file-actions
    '(find-file-other-frame . :make-first))
   "Find file (other frame): "))

(defun helm-projectile--find-other-file-1 (one-candidate-action actions prompt flex-matching)
  "Switch between files with the same name but different extensions using Helm.
Execute ONE-CANDIDATE-ACTION when there is a single file returned by
`projectile-get-other-files' (which see).  Otherwise display a Helm with
ACTIONS and PROMPT with other selected files.

With FLEX-MATCHING, match any file that contains the base name of
current file.  Other file extensions can be customized with the
variable `projectile-other-file-alist'."
  (interactive "P")
  (let* ((project-root (projectile-project-root))
         (other-files (projectile-get-other-files (buffer-file-name)
                                                  flex-matching)))
    (if other-files
        (if (= (length other-files) 1)
            (funcall one-candidate-action (expand-file-name (car other-files) project-root))
          (progn
            (let* ((helm-ff-transformer-show-only-basename nil))
              (helm :sources (helm-build-sync-source "Projectile other files"
                               :candidates (helm-projectile--files-display-real other-files project-root)
                               :keymap helm-projectile-find-file-map
                               :help-message helm-ff-help-message
                               :mode-line helm-read-file-name-mode-line-string
                               :action actions
                               :persistent-action #'helm-projectile-file-persistent-action
                               :persistent-help "Preview file")
                    :buffer "*helm projectile*"
                    :truncate-lines helm-projectile-truncate-lines
                    :prompt (projectile-prepend-project-name prompt)))))
      (error "No other file found"))))

;;;###autoload
(defun helm-projectile-find-other-file (&optional flex-matching)
  "Switch between files with the same name but different extensions using Helm.
With FLEX-MATCHING, match any file that contains the base name of
current file.  Other file extensions can be customized with the
variable `projectile-other-file-alist'."
  (interactive "P")
  (helm-projectile--find-other-file-1
   #'find-file
   helm-projectile-file-actions
   "Find other file: "
   flex-matching))

;;;###autoload
(defun helm-projectile-find-other-file-other-window (&optional flex-matching)
  "Switch between files with the same name but different extensions using Helm.
With FLEX-MATCHING, match any file that contains the base name of
current file.  Other file extensions can be customized with the
variable `projectile-other-file-alist'."
  (interactive "P")
  (helm-projectile--find-other-file-1
   #'find-file-other-window
   (helm-projectile-hack-actions
    helm-projectile-file-actions
    '(helm-find-files-other-window . :make-first))
   "Find other file (other window): "
   flex-matching))

;;;###autoload
(defun helm-projectile-find-other-file-other-frame (&optional flex-matching)
  "Switch between files with the same name but different extensions using Helm.
With FLEX-MATCHING, match any file that contains the base name of
current file.  Other file extensions can be customized with the
variable `projectile-other-file-alist'."
  (interactive "P")
  (helm-projectile--find-other-file-1
   #'find-file-other-frame
   (helm-projectile-hack-actions
    helm-projectile-file-actions
    '(find-file-other-frame . :make-first))
   "Find other file (other frame): "
   flex-matching))

(defcustom helm-projectile-ignore-strategy 'projectile
  "Allow projectile to compute ignored files and directories.

When set to `projectile', the package will compute ignores and
explicitly add additionally command line arguments to the search
tool.  Note that this might override search tool specific
behaviors (for instance ag would not use VCS ignore files).

When set to `search-tool', the above does not happen."
  :group 'helm-projectile
  :type '(choice (const :tag "Allow projectile to compute ignores" projectile)
                 (const :tag "Let the search tool compute ignores" search-tool)))

(defun helm-projectile--projectile-ignore-strategy ()
  "True if the ignore strategy is `projectile'."
  (eq 'projectile helm-projectile-ignore-strategy))

(defun helm-projectile--ignored-files ()
  "Compute ignored files."
  (cl-union (projectile-ignored-files-rel) grep-find-ignored-files
            :test #'equal))

(defun helm-projectile--ignored-directories ()
  "Compute ignored directories."
  (cl-union (projectile-ignored-directories-rel) grep-find-ignored-directories
            :test #'equal))

(defcustom helm-projectile-grep-or-ack-actions
  '("Find file" helm-grep-action
    "Find file other frame" helm-grep-other-frame
    (lambda () (and (locate-library "elscreen")
               "Find file in Elscreen"))
    helm-grep-jump-elscreen
    "Save results in grep buffer" helm-grep-save-results
    "Find file other window" helm-grep-other-window)
  "Available actions for `helm-projectile-grep-or-ack'.
The contents of this list are passed as the arguments to `helm-make-actions'."
  :type 'symbol
  :group 'helm-projectile)

(defcustom helm-projectile-set-input-automatically t
  "If non-nil, attempt to set search input automatically.
Automatic input selection uses the region (if there is an active
region), otherwise it uses the current symbol at point (if there is
one).  Applies to `helm-projectile-grep', `helm-projectile-ack', and
`helm-projectile-ag'."
  :group 'helm-projectile
  :type 'boolean)

(defun helm-projectile-grep-or-ack (&optional dir use-ack-p ack-ignored-pattern ack-executable)
  "Perform helm-grep at project root.
DIR directory where to search
USE-ACK-P indicates whether to use ack or not.
ACK-IGNORED-PATTERN is a file regex to exclude from searching.
ACK-EXECUTABLE is the actual ack binary name.
It is usually \"ack\" or \"ack-grep\".
If it is nil, or ack/ack-grep not found then use default grep command."
  (let* ((default-directory (or dir (projectile-project-root)))
         (helm-ff-default-directory default-directory)
         (helm-grep-in-recurse t)
         (helm-grep-ignored-files (if (helm-projectile--projectile-ignore-strategy)
                                      (helm-projectile--ignored-files)
                                    helm-grep-ignored-files))
         (helm-grep-ignored-directories (if (helm-projectile--projectile-ignore-strategy)
                                            (mapcar 'directory-file-name
                                                    (helm-projectile--ignored-directories))
                                          helm-grep-ignored-directories))
         (helm-grep-default-command (if use-ack-p
                                        (concat ack-executable " -H --no-group --no-color "
                                                (when ack-ignored-pattern (concat ack-ignored-pattern " "))
                                                "%p %f")
                                      (if (and projectile-use-git-grep (eq (projectile-project-vcs) 'git))
                                          helm-projectile-git-grep-command
                                        helm-projectile-grep-command)))
         (helm-grep-default-recurse-command helm-grep-default-command))

    (setq helm-source-grep
          (helm-build-async-source
              (capitalize (helm-grep-command t))
            :header-name (lambda (_name)
                           (let ((name (if use-ack-p
                                           "Helm Projectile Ack"
                                         "Helm Projectile Grep")))
                             (concat name " " "(C-c ? Help)")))
            :candidates-process 'helm-grep-collect-candidates
            :filter-one-by-one 'helm-grep-filter-one-by-one
            :candidate-number-limit 9999
            :nohighlight t
            ;; We need to specify keymap here and as :keymap arg [1]
            ;; to make it available in further resuming.
            :keymap helm-grep-map
            :history 'helm-grep-history
            :action (apply #'helm-make-actions helm-projectile-grep-or-ack-actions)
            :persistent-action 'helm-grep-persistent-action
            :persistent-help "Jump to line (`C-u' Record in mark ring)"
            :requires-pattern 2))
    (helm
     :sources 'helm-source-grep
     :input (when helm-projectile-set-input-automatically
              (if (region-active-p)
                  (buffer-substring-no-properties (region-beginning) (region-end))
                (thing-at-point 'symbol)))
     :buffer (format "*helm %s*" (if use-ack-p
                                     "ack"
                                   "grep"))
     :default-directory default-directory
     :keymap helm-grep-map
     :history 'helm-grep-history
     :truncate-lines helm-grep-truncate-lines)))

;;;###autoload
(defun helm-projectile-on ()
  "Turn on `helm-projectile' key bindings."
  (interactive)
  (message "Turn on helm-projectile key bindings")
  (helm-projectile-toggle 1))

;;;###autoload
(defun helm-projectile-off ()
  "Turn off `helm-projectile' key bindings."
  (interactive)
  (message "Turn off helm-projectile key bindings")
  (helm-projectile-toggle -1))

;;;###autoload
(defun helm-projectile-grep (&optional dir)
  "Helm version of `projectile-grep'.
DIR is the project root, if not set then current directory is used"
  (interactive)
  (let ((project-root (or dir (projectile-project-root) (error "You're not in a project"))))
    (funcall 'run-with-timer 0.01 nil
             #'helm-projectile-grep-or-ack project-root nil)))

;;;###autoload
(defun helm-projectile-ack (&optional dir)
  "Helm version of projectile-ack.
DIR directory where to search"
  (interactive)
  (let* ((project-root (or dir (projectile-project-root) (error "You're not in a project")))
         (ignored (when (helm-projectile--projectile-ignore-strategy)
                    (mapconcat
                     'identity
                     (cl-union (mapcar (lambda (path)
                                         (concat "--ignore-dir=" (file-name-nondirectory (directory-file-name path))))
                                       (helm-projectile--ignored-directories))
                               (mapcar (lambda (path)
                                         (concat "--ignore-file=match:" (shell-quote-argument path)))
                                       (append (helm-projectile--ignored-files)
                                               (projectile-patterns-to-ignore)))
                               :test #'equal)
                     " ")))
         (helm-ack-grep-executable (cond
                                    ((executable-find "ack") "ack")
                                    ((executable-find "ack-grep") "ack-grep")
                                    (t (error "Neither 'ack' nor 'ack-grep' is available")))))
    (funcall 'run-with-timer 0.01 nil
             #'helm-projectile-grep-or-ack project-root t ignored helm-ack-grep-executable)))

;;;###autoload

(defun helm-projectile-ag (&optional options)
  "Helm version of `projectile-ag'.
OPTIONS are explicit command line arguments to `helm-grep-ag-command'.
When called with a single or a triple prefix argument, ask for OPTIONS.
When called with a double or a triple prefix argument, ask for TYPES (see
`helm-grep-ag').'

This command uses `helm-grep-ag' to perform the search, so the actual
searcher used is determined by the value of `helm-grep-ag-command'."
  (interactive (if (member current-prefix-arg '((4) (64)))
                   (list (helm-read-string "option: " ""
                                           'helm-ag--extra-options-history))))
  (if (projectile-project-p)
      (let* ((ignored (when (helm-projectile--projectile-ignore-strategy)
                        (mapconcat (lambda (i)
                                     (helm-acase (helm-grep--ag-command)
                                       ;; `helm-grep-ag-command' suggests
                                       ;; that PT is obsolete, but support
                                       ;; still persist in Helm. Likely
                                       ;; remove after Helm drops support.
                                       (("ag" "pt")
                                        (concat "--ignore " (shell-quote-argument i)))
                                       ("rg"
                                        (concat "--iglob !" (shell-quote-argument i)))))
                                   (append grep-find-ignored-files
                                           grep-find-ignored-directories
                                           (cadr (projectile-parse-dirconfig-file)))
                                   " ")))
             (helm-grep-ag-command (format helm-grep-ag-command
                                           (mapconcat #'identity
                                                      (delq nil (list ignored options "%s"))
                                                      " ")
                                           "%s" "%s"))
             (with-types (member current-prefix-arg '((16) (64))))
             (current-prefix-arg nil))
        (helm-grep-ag (projectile-project-root) with-types))
    (error "You're not in a project")))


(defun helm-projectile--ag-automatic-input (args)
  "Use active region or a symbol at point as a third element in ARGS.
This function has been designed as an advice to `helm-grep-ag-1'.  Do not
use directly."
  (pcase-let ((`(,directory ,type ,input) args))
    (list directory
          type
          (or input
              (when helm-projectile-set-input-automatically
                (if (region-active-p)
                    (buffer-substring-no-properties (region-beginning) (region-end))
                  (thing-at-point 'symbol)))))))

;; When calling `helm', the function `helm-grep-ag' uses symbol at point as an
;; argument `:default-input' (via `helm-sources-using-default-as-input').  This
;; however sets argument `:input' to an empty string.  As a result the shell
;; command `ag' (or `rg', or `pt') is being run with the active region or a
;; symbol at point as a search pattern, but typing in minibuffer starts search
;; from scratch.  This advice will use symbol active region or a symbol point
;; as an `input' argument to `helm-grep-ag-1', which will ensure both `helm'
;; arguments `:default-input' and `:input' are populated.
(advice-add #'helm-grep-ag-1
            :filter-args #'helm-projectile--ag-automatic-input)

;; Declare/define these to satisfy the byte compiler
(defvar helm-rg-prepend-file-name-line-at-top-of-matches)
(defvar helm-rg-include-file-on-every-match-line)
(defvar helm-rg--extra-args)
(declare-function helm-rg "ext:helm-rg")
(declare-function helm-rg--get-thing-at-pt "ext:helm-rg")

(defun helm-projectile-rg--region-selection ()
  "Return a default input for `helm-rg'."
  (when helm-projectile-set-input-automatically
    (if (region-active-p)
        (buffer-substring-no-properties (region-beginning) (region-end))
      (helm-rg--get-thing-at-pt))))

;;;###autoload
(defun helm-projectile-rg ()
  "Projectile version of `helm-rg'."
  (interactive)
  (if (require 'helm-rg nil t)
      (if (projectile-project-p)
          (let* ((helm-rg-prepend-file-name-line-at-top-of-matches nil)
                 (helm-rg-include-file-on-every-match-line t)
                 (default-directory (projectile-project-root))
                 (helm-rg--extra-args
                  (if (helm-projectile--projectile-ignore-strategy)
                      (mapcan (lambda (path) (list "--glob" path))
                              (cl-union
                               (mapcar (lambda (path)
                                         (concat "!" path))
                                       (helm-projectile--ignored-files))
                               (mapcar (lambda (path)
                                         (concat "!" path "/**"))
                                       (mapcar 'directory-file-name
                                               (helm-projectile--ignored-directories)))
                               :test #'equal))
                    helm-rg--extra-args)))

            (helm-rg (helm-projectile-rg--region-selection)
                     nil))
        (error "You're not in a project"))
    (when (yes-or-no-p "`helm-rg' is not installed.  Install it? ")
      (condition-case nil
          (progn
            (package-install 'helm-rg)
            (helm-projectile-rg))
        (error "`helm-rg' is not available.  Is MELPA in your `package-archives'?")))))

(defun helm-projectile-commander-bindings ()
  "Define Helm versions of Projectile commands in `projectile-commander'."
  (def-projectile-commander-method ?a
    "Run ack on project."
    (call-interactively 'helm-projectile-ack))

  (def-projectile-commander-method ?A
    "Find ag on project."
    (call-interactively 'helm-projectile-ag))

  (def-projectile-commander-method ?f
    "Find file in project."
    (helm-projectile-find-file))

  (def-projectile-commander-method ?b
    "Switch to project buffer."
    (helm-projectile-switch-to-buffer))

  (def-projectile-commander-method ?d
    "Find directory in project."
    (helm-projectile-find-dir))

  (def-projectile-commander-method ?g
    "Run grep on project."
    (helm-projectile-grep))

  (def-projectile-commander-method ?s
    "Switch project."
    (helm-projectile-switch-project))

  (def-projectile-commander-method ?e
    "Find recently visited file in project."
    (helm-projectile-recentf))

  (def-projectile-commander-method ?V
    "Find dirty projects."
    (helm-projectile-browse-dirty-projects)))

;;;###autoload
(defun helm-projectile-toggle (toggle)
  "Toggle Helm version of Projectile commands.
When TOGGLE is greater than 0 turn Helm version of Projectile commands
on.  When TOGGLE is is less or equal to 0 turn Helm version of commands
off."
  (if (> toggle 0)
      (progn
        (when (eq projectile-switch-project-action #'projectile-find-file)
          (setq projectile-switch-project-action #'helm-projectile-find-file))
        (define-key projectile-mode-map [remap projectile-find-other-file] #'helm-projectile-find-other-file)
        (define-key projectile-mode-map [remap projectile-find-other-file-other-window] #'helm-projectile-find-other-file-other-window)
        (define-key projectile-mode-map [remap projectile-find-other-file-other-frame] #'helm-projectile-find-other-file-other-frame)
        (define-key projectile-mode-map [remap projectile-find-file] #'helm-projectile-find-file)
        (define-key projectile-mode-map [remap projectile-find-file-other-window] #'helm-projectile-find-file-other-window)
        (define-key projectile-mode-map [remap projectile-find-file-other-frame] #'helm-projectile-find-file-other-frame)
        (define-key projectile-mode-map [remap projectile-find-file-in-known-projects] #'helm-projectile-find-file-in-known-projects)
        (define-key projectile-mode-map [remap projectile-find-file-dwim] #'helm-projectile-find-file-dwim)
        (define-key projectile-mode-map [remap projectile-find-file-dwim-other-window] #'helm-projectile-find-file-dwim-other-window)
        (define-key projectile-mode-map [remap projectile-find-file-dwim-other-frame] #'helm-projectile-find-file-dwim-other-frame)
        (define-key projectile-mode-map [remap projectile-find-dir] #'helm-projectile-find-dir)
        (define-key projectile-mode-map [remap projectile-find-dir-other-window] #'helm-projectile-find-dir-other-window)
        (define-key projectile-mode-map [remap projectile-find-dir-other-frame] #'helm-projectile-find-dir-other-frame)
        (define-key projectile-mode-map [remap projectile-switch-project] #'helm-projectile-switch-project)
        ;; At the time of writing projectile didn't have neither
        ;; `projectile-switch-to-project-other-window' nor
        ;; `projectile-switch-to-project-other-frame' (hopefully these will be
        ;; names should they be added).  Adding `helm-projectile' bindings in a
        ;; - hopefully - backward compatible way, by setting up keys in
        ;; `projectile-command-map'.
        (if (where-is-internal 'projectile-switch-project-other-window projectile-mode-map nil t t)
            (define-key projectile-mode-map [remap projectile-switch-project-other-window] #'helm-projectile-switch-project-other-window)
          (define-key projectile-command-map (kbd "4 p") #'helm-projectile-switch-project-other-window))
        (if (where-is-internal 'projectile-switch-project-other-frame projectile-mode-map nil t t)
            (define-key projectile-mode-map [remap projectile-switch-project-other-frame] #'helm-projectile-switch-project-other-frame)
          (define-key projectile-command-map (kbd "5 p") #'helm-projectile-switch-project-other-frame))
        (define-key projectile-mode-map [remap projectile-recentf] #'helm-projectile-recentf)
        (define-key projectile-mode-map [remap projectile-switch-to-buffer] #'helm-projectile-switch-to-buffer)
        (define-key projectile-mode-map [remap projectile-switch-to-buffer-other-window] #'helm-projectile-switch-to-buffer-other-window)
        (define-key projectile-mode-map [remap projectile-switch-to-buffer-other-frame] #'helm-projectile-switch-to-buffer-other-frame)
        (define-key projectile-mode-map [remap projectile-grep] #'helm-projectile-grep)
        (define-key projectile-mode-map [remap projectile-ack] #'helm-projectile-ack)
        (define-key projectile-mode-map [remap projectile-ag] #'helm-projectile-ag)
        (define-key projectile-mode-map [remap projectile-ripgrep] #'helm-projectile-rg)
        (define-key projectile-mode-map [remap projectile-browse-dirty-projects] #'helm-projectile-browse-dirty-projects)
        (helm-projectile-commander-bindings))
    (progn
      (when (eq projectile-switch-project-action #'helm-projectile-find-file)
        (setq projectile-switch-project-action #'projectile-find-file))
      (define-key projectile-mode-map [remap projectile-find-other-file] nil)
      (define-key projectile-mode-map [remap projectile-find-other-file-other-window] nil)
      (define-key projectile-mode-map [remap projectile-find-other-file-other-frame] nil)
      (define-key projectile-mode-map [remap projectile-find-file] nil)
      (define-key projectile-mode-map [remap projectile-find-file-other-window] nil)
      (define-key projectile-mode-map [remap projectile-find-file-other-frame] nil)
      (define-key projectile-mode-map [remap projectile-find-file-in-known-projects] nil)
      (define-key projectile-mode-map [remap projectile-find-file-dwim] nil)
      (define-key projectile-mode-map [remap projectile-find-file-dwim-other-window] nil)
      (define-key projectile-mode-map [remap projectile-find-file-dwim-other-frame] nil)
      (define-key projectile-mode-map [remap projectile-find-dir] nil)
      (define-key projectile-mode-map [remap projectile-find-dir-other-window] nil)
      (define-key projectile-mode-map [remap projectile-find-dir-other-frame] nil)
      (define-key projectile-mode-map [remap projectile-switch-project] nil)
      (if (where-is-internal 'helm-projectile-switch-project-other-window projectile-command-map nil t t)
          (define-key projectile-mode-map (kbd "4 p") nil)
        (define-key projectile-mode-map [remap projectile-switch-project-other-window] nil))
      (if (where-is-internal 'helm-projectile-switch-project-other-frame projectile-command-map nil t t)
          (define-key projectile-mode-map (kbd "5 p") nil)
        (define-key projectile-mode-map [remap projectile-switch-project-other-frame] nil))
      (define-key projectile-mode-map [remap projectile-recentf] nil)
      (define-key projectile-mode-map [remap projectile-switch-to-buffer] nil)
      (define-key projectile-mode-map [remap projectile-switch-to-buffer-other-window] nil)
      (define-key projectile-mode-map [remap projectile-switch-to-buffer-other-frame] nil)
      (define-key projectile-mode-map [remap projectile-grep] nil)
      (define-key projectile-mode-map [remap projectile-ag] nil)
      (define-key projectile-mode-map [remap projectile-ripgrep] nil)
      (define-key projectile-mode-map [remap projectile-browse-dirty-projects] nil)
      (projectile-commander-bindings))))

;;;###autoload
(defun helm-projectile (&optional arg)
  "Use projectile with Helm instead of ido.

With a prefix ARG invalidates the cache first.
If invoked outside of a project, displays a list of known projects to jump."
  (interactive "P")
  (if (not (projectile-project-p))
      (helm-projectile-switch-project arg)
    (projectile-maybe-invalidate-cache arg)
    (let ((helm-ff-transformer-show-only-basename nil))
      (helm :sources helm-projectile-sources-list
            :buffer "*helm projectile*"
            :truncate-lines helm-projectile-truncate-lines
            :prompt (projectile-prepend-project-name (if (projectile-project-p)
                                                         "pattern: "
                                                       "Switch to project: "))))))

;;;###autoload
(eval-after-load 'projectile
  '(progn
     (define-key projectile-command-map (kbd "h") #'helm-projectile)))

(provide 'helm-projectile)

;;; helm-projectile.el ends here
