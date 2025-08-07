# Changelog

## 1.3.0 (2025-08-07)

### New features

* Add `helm-projectile` actions to search projects with rg and ag. The new
  actions are bound to `C-S-a` and `C-S-d` respectively and they are available
  in all sources that complete projects and directories.
* Add `helm-projectile` specific commands to switch projects, to switch to
  buffers and to find files in other window and other frame. Most of new
  commands is bound after `C-c p 4` and `C-c p 5`.

### Fixes

* When searching with rg, ensure the directory is chosen based on projectile.
* Ensure ignored directories elements are unique.

### Changes

* Add faces to sources that use files.
* Add faces to `helm-projectile-browse-dirty-projects`.
* Add autoloads to `helm-projectile` commands defined with `helm-projectile-command`.
* Make `helm-projectile-ag` to use common ignore list

## 1.2.0 (2025-07-21)

### Changes

* [#193](https://github.com/bbatsov/helm-projectile/issues/193), [#195](https://github.com/bbatsov/helm-projectile/pull/195): Switch  to use built-in `helm-grep-ag`.

### Bugs fixed

* Fix `checkdoc` and (some of) `package-lint` diagnostics.
* Fix side effects in `helm-projectile-grep-or-ack` and `helm-projectile-ag`
* [#173](https://github.com/bbatsov/helm-projectile/pull/191): Fix `helm-rg--extra-args` losing dynamic scope due to use of setq
* [#173](https://github.com/bbatsov/helm-projectile/pull/173), [#194](https://github.com/bbatsov/helm-projectile/pull/194): Respect `helm-buffer-max-length` if it's `nil`.
* [#189](https://github.com/bbatsov/helm-projectile/pull/192): Fix `helm-projectile-rg` specifying incorrect extra args.
* [#188](https://github.com/bbatsov/helm-projectile/pull/178): Fix `helm-projectile-projects-source` slots.

## 1.1.0 (2025-02-14)

### New features

* Improve `helm-source-proctile-project-list` by also inheriting the
  `helm-type-file` class to benefit of it's functionality such as candidate
  transformer or file cache.
* [#180](https://github.com/bbatsov/helm-projectile/pull/180): Introduce `helm-projectile-ignore-strategy` defcustom.

### Changes

* [#151](https://github.com/bbatsov/helm-projectile/pull/157): Teach `helm-projectile-rg` to respect ignored files and directories.
* [#151](https://github.com/bbatsov/helm-projectile/issues/151): Rename `helm-projectile-switch-to-eshell` -> `helm-projectile-switch-to-shell`.

### Bugs fixed

* [#176](https://github.com/bbatsov/helm-projectile/pull/178): Correctly remove current buffer from `helm-source-projectile-buffers-list`.
* [#143](https://github.com/bbatsov/helm-projectile/issues/143): Fix rg command for helm-ag arity.
* [#145](https://github.com/bbatsov/helm-projectile/issues/145): Fix bug in `M-D` / remove from project list action for first project in the list.
* [#143](https://github.com/bbatsov/helm-projectile/issues/143): Fix `rg` command for `helm-ag` arity.
* [#140](https://github.com/bbatsov/helm-projectile/pull/140): Fix interactive options for `helm-projectile-grep` and `helm-projectile-ack`.

## 1.0.0 (2020-05-18)

Initial stable release.
