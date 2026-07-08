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
(require 'helm-projectile-test-helper)

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
              :to-equal '("/proj/a.el" "/proj/src/b.el"))))

  (it "keeps the directory component in the display of a nested file"
    ;; Exercises the `file-name-directory' branch: a file in a subdirectory
    ;; must keep its directory prefix in the display string, while a
    ;; top-level file has none.
    (let ((result (helm-projectile--files-display-real
                   '("a.el" "src/b.el") "/proj/")))
      (expect (substring-no-properties (car (nth 0 result))) :not :to-match "/")
      (expect (substring-no-properties (car (nth 1 result))) :to-match "\\`src/"))))

(describe "helm-projectile-hack-actions"
  ;; Pure action-list surgery that drives which actions each source offers
  ;; and in what order; every source's action list is built through it.
  (let ((base '(("Open" . open-fn) ("Delete" . delete-fn) ("Rename" . rename-fn))))

    (it "deletes an action named by a bare symbol"
      (expect (helm-projectile-hack-actions base 'delete-fn)
              :to-equal '(("Open" . open-fn) ("Rename" . rename-fn))))

    (it "substitutes an action's function"
      (expect (helm-projectile-hack-actions base '(open-fn . identity))
              :to-equal '(("Open" . identity) ("Delete" . delete-fn) ("Rename" . rename-fn))))

    (it "renames an existing action's description"
      (expect (helm-projectile-hack-actions base '(open-fn . "Open file"))
              :to-equal '(("Open file" . open-fn) ("Delete" . delete-fn) ("Rename" . rename-fn))))

    (it "appends a new action for an unknown function"
      (expect (helm-projectile-hack-actions base '(new-fn . "Brand new"))
              :to-equal '(("Open" . open-fn) ("Delete" . delete-fn)
                          ("Rename" . rename-fn) ("Brand new" . new-fn))))

    (it "promotes an action to the front with :make-first"
      (expect (helm-projectile-hack-actions base '(rename-fn . :make-first))
              :to-equal '(("Rename" . rename-fn) ("Open" . open-fn) ("Delete" . delete-fn))))

    (it "does not mutate the input action list"
      (helm-projectile-hack-actions base 'delete-fn '(open-fn . "x") '(rename-fn . :make-first))
      (expect base
              :to-equal '(("Open" . open-fn) ("Delete" . delete-fn) ("Rename" . rename-fn))))))

(describe "helm-projectile--wildcard-to-ack-match"
  ;; Characterization tests: they pin the current glob->ack-regex transform
  ;; (`.'->`\\.', `?'->`.', `*'->`.*', anchored with ^...$).
  (it "escapes dots and expands glob wildcards, anchored"
    (expect (helm-projectile--wildcard-to-ack-match "*.el") :to-equal "^.*\\.el$")
    (expect (helm-projectile--wildcard-to-ack-match "foo?.txt") :to-equal "^foo.\\.txt$")
    (expect (helm-projectile--wildcard-to-ack-match "*.min.js") :to-equal "^.*\\.min\\.js$")
    (expect (helm-projectile--wildcard-to-ack-match "test_*.rb") :to-equal "^test_.*\\.rb$"))

  (it "turns a leading [!...] negation into [^...]"
    (expect (helm-projectile--wildcard-to-ack-match "[!x].c") :to-equal "^[^x]\\.c$")))

(describe "helm-projectile--move-selection-p"
  ;; Decides whether the selector should skip past a candidate to reach a
  ;; real file.  Skip a plain non-existent pattern; stay on a real file or a
  ;; non-string.
  (it "returns non-nil for a plain non-existent pattern"
    (expect (helm-projectile--move-selection-p "no-such-file-xyzzy.qqq") :to-be-truthy))

  (it "returns nil for a non-string selection"
    (expect (helm-projectile--move-selection-p nil) :not :to-be-truthy)
    (expect (helm-projectile--move-selection-p 42) :not :to-be-truthy))

  (it "returns nil for an existing file"
    (helm-projectile-test-with-sandbox
      (helm-projectile-test-with-files '("real.el")
        (expect (helm-projectile--move-selection-p (expand-file-name "real.el"))
                :not :to-be-truthy)))))

(describe "helm-projectile-files-in-current-dired-buffer"
  ;; Fixture-backed: build a throwaway project on disk and a *virtual* Dired
  ;; buffer from an explicit file list (the way the dired-files actions do),
  ;; then assert the helper reads those entries back as truenames.
  (it "returns the truenames of the files listed in the Dired buffer"
    (helm-projectile-test-with-sandbox
      (helm-projectile-test-with-files '("a.el" "b.el")
        (let ((buf (dired (cons "virtual-dired" '("a.el" "b.el")))))
          (unwind-protect
              (with-current-buffer buf
                (expect (sort (helm-projectile-files-in-current-dired-buffer)
                              #'string<)
                        :to-equal
                        (sort (list (file-truename (expand-file-name "a.el"))
                                    (file-truename (expand-file-name "b.el")))
                              #'string<)))
            (kill-buffer buf)))))))

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
    (expect (helm-projectile--files-stream-command) :to-throw 'user-error))

  (it "defines an other-window and other-frame streaming source"
    (expect (boundp 'helm-source-projectile-files-streaming-other-window) :to-be-truthy)
    (expect (boundp 'helm-source-projectile-files-streaming-other-frame) :to-be-truthy))

  (it "promotes the matching default action in each streaming variant"
    (cl-flet ((first-action (src) (cdar (helm-get-attr 'action src))))
      (expect (first-action helm-source-projectile-files-streaming-other-window)
              :to-be 'helm-find-files-other-window)
      (expect (first-action helm-source-projectile-files-streaming-other-frame)
              :to-be 'find-file-other-frame))))

(describe "helm-projectile-find-file-strategy"
  (before-each
    (spy-on 'helm)
    (spy-on 'projectile-project-p :and-return-value t)
    (spy-on 'projectile-maybe-invalidate-cache)
    (spy-on 'projectile-project-name :and-return-value "demo")
    (spy-on 'projectile-prepend-project-name :and-call-fake #'identity))

  (it "defaults to sync"
    (expect helm-projectile-find-file-strategy :to-be 'sync))

  (it "picks the sync sources for each variant by default"
    (helm-projectile-find-file)
    (expect (helm-projectile-test--sources)
            :to-equal '(helm-source-projectile-dired-files-list
                        helm-source-projectile-files-list)))

  (it "picks the streaming source for each variant when set to streaming"
    (let ((helm-projectile-find-file-strategy 'streaming))
      (helm-projectile-find-file)
      (expect (helm-projectile-test--sources)
              :to-be 'helm-source-projectile-files-streaming)
      (spy-calls-reset 'helm)
      (helm-projectile-find-file-other-window)
      (expect (helm-projectile-test--sources)
              :to-be 'helm-source-projectile-files-streaming-other-window)
      (spy-calls-reset 'helm)
      (helm-projectile-find-file-other-frame)
      (expect (helm-projectile-test--sources)
              :to-be 'helm-source-projectile-files-streaming-other-frame))))

(describe "helm-projectile--switch-project-and-ag-action"
  ;; A directory name can legally contain a `%'; the error path used to feed
  ;; it straight to `error' as a format string, which crashed with "Not enough
  ;; arguments for format string" instead of reporting the real problem.
  (it "reports a non-directory argument containing `%' without a format crash"
    (spy-on 'file-directory-p :and-return-value nil)
    (expect (helm-projectile--switch-project-and-ag-action "/no/such/dir%s")
            :to-throw 'user-error)))

(describe "helm-projectile--with-virtual-dired"
  (it "runs the body on a local project root"
    (spy-on 'projectile-project-root :and-return-value "/proj/")
    (let ((ran nil))
      (helm-projectile--with-virtual-dired (setq ran t))
      (expect ran :to-be t)))

  (it "skips the body on a remote root when disabled"
    (spy-on 'projectile-project-root :and-return-value "/ssh:host:/proj/")
    (let ((helm-projectile-virtual-dired-remote-enable nil)
          (ran nil))
      (helm-projectile--with-virtual-dired (setq ran t))
      (expect ran :to-be nil)))

  (it "runs the body on a remote root when explicitly enabled"
    (spy-on 'projectile-project-root :and-return-value "/ssh:host:/proj/")
    (let ((helm-projectile-virtual-dired-remote-enable t)
          (ran nil))
      (helm-projectile--with-virtual-dired (setq ran t))
      (expect ran :to-be t))))

(describe "helm-projectile-command generated docstrings"
  ;; Every command used to inherit the same "finding files in project"
  ;; docstring; each should now describe what it actually does.
  (it "derives an accurate docstring from each command's prompt"
    (expect (documentation 'helm-projectile-switch-to-buffer)
            :to-match "\\`Switch to buffer")
    (expect (documentation 'helm-projectile-recentf)
            :to-match "\\`Recently visited file")
    (expect (documentation 'helm-projectile-find-file)
            :not :to-match "finding files in project")))

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
