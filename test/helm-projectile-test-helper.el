;;; helm-projectile-test-helper.el --- Shared test helpers -*- lexical-binding: t -*-

;; Copyright © 2011-2026 Bozhidar Batsov

;; This file is NOT part of GNU Emacs.

;; This program is free software: you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see `http://www.gnu.org/licenses/'.

;;; Commentary:

;; Fixtures and helpers shared by the helm-projectile test suites: a
;; temporary-project sandbox (mirroring Projectile's own test helpers) and a
;; small shim for reading back the arguments of a stubbed `helm' call.

;;; Code:

(require 'helm-projectile)
(require 'buttercup)
(require 'cl-lib)
(require 'dired)

(defmacro helm-projectile-test-with-sandbox (&rest body)
  "Run BODY with `default-directory' bound to a fresh temporary directory.
The directory is created before BODY and deleted afterwards, so a suite
can build a throwaway project tree on disk without touching the user's
files."
  (declare (indent 0) (debug t))
  ;; `file-truename' so the root matches the truenames Dired reports back
  ;; (on macOS the temp dir lives under a symlinked /var -> /private/var).
  `(let ((default-directory (file-name-as-directory
                             (file-truename
                              (make-temp-file "helm-projectile-test" t)))))
     (unwind-protect
         (progn ,@body)
       (delete-directory default-directory t))))

(defmacro helm-projectile-test-with-files (files &rest body)
  "Create FILES under `default-directory', then run BODY.
FILES is a list of relative paths.  A path ending in \"/\" is created as a
directory; any other path has its parent directories created and is then
touched as an empty file.  Meant to be nested inside
`helm-projectile-test-with-sandbox'."
  (declare (indent 1) (debug t))
  `(progn
     (dolist (f ,files)
       (if (string-suffix-p "/" f)
           (make-directory f t)
         (when-let* ((dir (file-name-directory f)))
           (make-directory dir t))
         (write-region "" nil f nil 'silent)))
     ,@body))

(defun helm-projectile-test--sources (&optional n)
  "Return the `:sources' of the N-th (default 0) stubbed `helm' call.
A `(spy-on \\='helm)' must be active for this to have anything to read."
  (plist-get (spy-calls-args-for 'helm (or n 0)) :sources))

(defun helm-projectile-test--grep-command (&rest args)
  "Return the `helm-grep-default-command' built by `helm-projectile-grep-or-ack'.
ARGS are forwarded to it; `helm' is stubbed so nothing is displayed, and
the ignore strategy is forced to `search-tool' to isolate the command
string from Projectile's ignore computation."
  (let (command)
    (cl-letf (((symbol-function 'helm)
               (lambda (&rest _) (setq command helm-grep-default-command))))
      (let ((helm-projectile-ignore-strategy 'search-tool))
        (apply #'helm-projectile-grep-or-ack args)))
    command))

(defun helm-projectile-test--ag-command (searcher &optional options)
  "Return the `helm-grep-ag-command' built by `helm-projectile--ag-1'.
SEARCHER is what `helm-grep--ag-command' should report (\"ag\", \"pt\" or
\"rg\").  `helm-grep-ag' is stubbed and the command template reset to a
plain three-slot string so only the ignore globs vary."
  (let (command)
    (cl-letf (((symbol-function 'helm-grep-ag)
               (lambda (&rest _) (setq command helm-grep-ag-command)))
              ((symbol-function 'helm-grep--ag-command) (lambda (&rest _) searcher)))
      (let ((helm-projectile-ignore-strategy 'projectile)
            (helm-grep-ag-command "ag %s %s %s"))
        (helm-projectile--ag-1 "/proj/" nil options)))
    command))

(defun helm-projectile-test--ack-args ()
  "Return the args `helm-projectile-ack' would hand to `helm-projectile-grep-or-ack'.
The latter is stubbed to capture them (with no live Helm session, the
call runs straight through); the returned list is
\(PROJECT-ROOT USE-ACK-P IGNORED ACK-EXECUTABLE INCLUDE)."
  (let (args (helm-alive-p nil))
    (cl-letf (((symbol-function 'helm-projectile-grep-or-ack)
               (lambda (&rest rest) (setq args rest))))
      (helm-projectile-ack))
    args))

(provide 'helm-projectile-test-helper)
;;; helm-projectile-test-helper.el ends here
