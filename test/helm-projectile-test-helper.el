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
  `(let ((default-directory (file-name-as-directory
                             (make-temp-file "helm-projectile-test" t))))
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

(provide 'helm-projectile-test-helper)
;;; helm-projectile-test-helper.el ends here
