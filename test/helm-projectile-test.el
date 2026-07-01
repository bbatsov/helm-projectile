;;; helm-projectile-test.el --- Tests for helm-projectile -*- lexical-binding: t -*-

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

;; Tests for helm-projectile.

;;; Code:

(require 'helm-projectile)
(require 'buttercup)

(describe "helm-projectile package"
  (it "defines its core entry-point commands"
    (expect (commandp 'helm-projectile) :to-be-truthy)
    (expect (commandp 'helm-projectile-find-file) :to-be-truthy)
    (expect (commandp 'helm-projectile-switch-project) :to-be-truthy)
    (expect (commandp 'helm-projectile-switch-to-buffer) :to-be-truthy)))

(describe "helm-projectile-toggle"
  ;; This is the regression guard for helm-projectile referencing Projectile
  ;; internals that no longer exist (the commander macro/bindings were the
  ;; breakage that prompted this suite).  Toggling must not error and must
  ;; (un)install the command remaps on `projectile-mode-map'.
  (after-each
    ;; Always leave a clean slate regardless of what the example did.
    (helm-projectile-toggle 0))

  (it "enables without error and remaps core commands to their Helm versions"
    (expect (helm-projectile-toggle 1) :not :to-throw)
    (expect (lookup-key projectile-mode-map [remap projectile-find-file])
            :to-be 'helm-projectile-find-file)
    (expect (lookup-key projectile-mode-map [remap projectile-switch-to-buffer])
            :to-be 'helm-projectile-switch-to-buffer)
    (expect (lookup-key projectile-mode-map [remap projectile-grep])
            :to-be 'helm-projectile-grep)
    ;; `ripgrep' is the one remap whose Helm command doesn't share the
    ;; `helm-projectile-<name>' shape, so guard it explicitly.
    (expect (lookup-key projectile-mode-map [remap projectile-ripgrep])
            :to-be 'helm-projectile-rg))

  (it "installs a remap for every command in the table"
    (helm-projectile-toggle 1)
    (dolist (entry helm-projectile--command-remaps)
      (expect (lookup-key projectile-mode-map (vector 'remap (car entry)))
              :to-be (cdr entry))))

  (it "disables without error and clears the remaps"
    (helm-projectile-toggle 1)
    (expect (helm-projectile-toggle 0) :not :to-throw)
    (dolist (entry helm-projectile--command-remaps)
      (expect (lookup-key projectile-mode-map (vector 'remap (car entry)))
              :to-be nil))))

(describe "helm-projectile--files-display-real"
  (it "maps each file to its absolute path under the project root"
    ;; The display (car) is formatted by Helm and may be propertized, so we
    ;; only assert on the real (cdr) part, which is the absolute path.
    (let ((result (helm-projectile--files-display-real
                   '("a.el" "src/b.el") "/proj/")))
      (expect (mapcar #'cdr result)
              :to-equal '("/proj/a.el" "/proj/src/b.el")))))

(describe "helm-projectile streaming file source"
  (it "defines the streaming command and its source"
    (expect (commandp 'helm-projectile-find-file-streaming) :to-be-truthy)
    (expect (boundp 'helm-source-projectile-files-streaming) :to-be-truthy))

  (it "builds a newline-translating shell command from the project's indexer"
    (spy-on 'projectile-project-root :and-return-value "/proj/")
    (spy-on 'projectile-project-vcs :and-return-value 'git)
    (spy-on 'projectile-get-ext-command
            :and-return-value "git ls-files -zco --exclude-standard")
    (expect (helm-projectile--files-stream-command)
            :to-equal "git ls-files -zco --exclude-standard | tr '\\000' '\\n'"))

  (it "errors when external-command indexing is unavailable"
    (spy-on 'projectile-project-root :and-return-value "/proj/")
    (spy-on 'projectile-project-vcs :and-return-value 'none)
    (spy-on 'projectile-get-ext-command :and-return-value nil)
    (expect (helm-projectile--files-stream-command) :to-throw 'user-error)))

(describe "helm-projectile--switch-project-and-ag-action"
  ;; A directory name can legally contain a `%'; the error path used to feed
  ;; it straight to `error' as a format string, which crashed with "Not enough
  ;; arguments for format string" instead of reporting the real problem.
  (it "reports a non-directory argument containing `%' without a format crash"
    (spy-on 'file-directory-p :and-return-value nil)
    (expect (helm-projectile--switch-project-and-ag-action "/no/such/dir%s")
            :to-throw 'user-error)))

(describe "helm-projectile file source transformer"
  ;; The transformer runs on every keystroke, so it must not do the
  ;; `.dir-locals.el' filesystem walk that the candidates function needs.
  (it "does not hack dir-local variables on every update"
    (spy-on 'hack-dir-local-variables-non-file-buffer)
    (spy-on 'projectile-project-root :and-return-value "/proj/")
    (let* ((src (helm-source-projectile-file :name "t"))
           (transformer (slot-value src 'filtered-candidate-transformer))
           (helm-pattern ""))
      (expect (funcall transformer '(("a.el" . "/proj/a.el")) src)
              :to-equal '(("a.el" . "/proj/a.el")))
      (expect 'hack-dir-local-variables-non-file-buffer
              :not :to-have-been-called))))

(describe "helm-projectile-fuzzy-match"
  ;; The EIEIO file/dir/project sources used to store the *symbol*
  ;; `helm-projectile-fuzzy-match' in their `fuzzy-match' slot, which Helm
  ;; reads as a constant non-nil, so disabling the option had no effect.
  (it "propagates a disabled setting to the source's fuzzy-match slot"
    (let ((helm-projectile-fuzzy-match nil))
      (expect (slot-value (helm-source-projectile-file :name "t") 'fuzzy-match)
              :to-be nil)))

  (it "propagates an enabled setting to the source's fuzzy-match slot"
    (let ((helm-projectile-fuzzy-match t))
      (expect (slot-value (helm-source-projectile-file :name "t") 'fuzzy-match)
              :to-be t))))

(describe "user-facing error conditions"
  ;; Normal situations (no project, no other file, ...) should signal
  ;; `user-error', not `error', so they don't trip the debugger when a user
  ;; has `debug-on-error' enabled.
  (it "signals user-error when running ag outside a project"
    (spy-on 'projectile-project-p :and-return-value nil)
    (expect (helm-projectile-ag) :to-throw 'user-error))

  (it "signals user-error when there is no other file"
    (spy-on 'projectile-project-root :and-return-value "/proj/")
    (spy-on 'projectile-get-other-files :and-return-value nil)
    (expect (helm-projectile-find-other-file) :to-throw 'user-error)))

(describe "removed features"
  ;; Mirrors Projectile dropping its single-key commander and the
  ;; browse-dirty-projects command; helm-projectile must not resurrect them.
  (it "no longer defines the dirty-projects command"
    (expect (fboundp 'helm-projectile-browse-dirty-projects) :not :to-be-truthy))
  (it "no longer defines the commander bindings helper"
    (expect (fboundp 'helm-projectile-commander-bindings) :not :to-be-truthy)))

(provide 'helm-projectile-test)

;;; helm-projectile-test.el ends here
