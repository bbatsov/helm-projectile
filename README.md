[![License GPL 3][badge-license]](http://www.gnu.org/licenses/gpl-3.0.txt)
[![MELPA](http://melpa.org/packages/helm-projectile-badge.svg)](http://melpa.org/#/helm-projectile)
[![MELPA Stable](http://stable.melpa.org/packages/helm-projectile-badge.svg)](http://stable.melpa.org/#/helm-projectile)
[![Patreon](https://img.shields.io/badge/patreon-donate-orange.svg)](https://www.patreon.com/bbatsov)

## Helm Projectile

[Projectile](https://github.com/bbatsov/projectile) can be integrated
with [Helm](https://github.com/emacs-helm/helm) via
`helm-source-projectile-projects`,
`helm-source-projectile-files-list`,
`helm-source-projectile-buffers-list` and
`helm-source-projectile-recentf-list` sources (available in
`helm-projectile.el`). There is also an example function for calling
Helm with the Projectile file source. You can call it like this:

```
M-x helm-projectile
```

or even better - invoke the key binding <kbd>h</kbd> in Projectile's
keymap. Assuming you've opted for one of the recommended keymap prefixes (`C-c p`
or `s-p`), that would mean <kbd>C-c p h</kbd> or <kbd>s-p h</kbd>.

See Projectile's [installation docs](https://docs.projectile.mx/projectile/installation.html#installation-via-package-el) for more details.

## Installation

The recommended way to install helm-projectile is via `package.el`.

### package.el

#### MELPA

You can install a snapshot version of helm-projectile from the
[MELPA](http://melpa.org) repository. The version of
Projectile there will always be up-to-date, but it might be unstable
(albeit rarely).

#### MELPA Stable

You can install the last stable version of helm-projectile from the
[MELPA Stable](http://stable.melpa.org) repository.

### el-get

helm-projectile is also available for installation from the
[el-get](https://github.com/dimitri/el-get) package manager.

### Emacs Prelude

helm-projectile is naturally part of the
[Emacs Prelude](https://github.com/bbatsov/prelude). If you're a Prelude
user - helm-projectile is already properly configured and ready for
action.

### Debian and Ubuntu

Users of Debian 9 or later or Ubuntu 16.04 or later may `apt
install elpa-helm-projectile`.

## Usage

For those who prefer helm to ido/ivy, the command `helm-projectile-switch-project`
can be used to replace `projectile-switch-project` to switch project. Please
note that this is different from simply setting `projectile-completion-system`
to `helm`, which just enables projectile to use the Helm completion to complete
a project name. The benefit of using `helm-projectile-switch-project` is that on
any selected project we can fire many actions, not limited to just the "switch
to project" action, as in the case of using helm completion by setting
`projectile-completion-system` to `helm`. Currently, there are five actions:
"Switch to project", "Open Dired in project's directory", "Open project root in
vc-dir or magit", "Switch to Eshell" and "Grep project files". We will add more
and more actions in the future.

`helm-projectile` is capable of opening multiple files by marking the files with
<kbd>C-SPC</kbd> or mark all files with <kbd>M-a</kbd>. Then, press <kbd>RET</kbd>,
all the selected files will be opened.

Note that the helm grep is different from `projectile-grep` because the helm
grep is incremental. To use it, select your projects (select multiple projects
by pressing C-SPC), press "C-s" (or "C-u C-s" for recursive grep), and type your
regexp. As you type the regexp in the mini buffer, the live grep results are
displayed incrementally.

`helm-projectile` also provides Helm versions of common Projectile commands. Currently,
these are the supported commands:

* `helm-projectile-switch-project`
* `helm-projectile-find-file`
* `helm-projectile-find-file-in-known-projects`
* `helm-projectile-find-file-dwim`
* `helm-projectile-find-dir`
* `helm-projectile-recentf`
* `helm-projectile-switch-to-buffer`
* `helm-projectile-grep` (can be used for both grep or ack)
* `helm-projectile-ag`
* `helm-projectile-rg`
* Replace Helm equivalent commands in `projectile-commander`
* A virtual directory manager that is unique to Helm Projectile

Why should you use these commands compared with the normal Projectile
commands, even if the normal commands use `helm` as
`projectile-completion-system`? The answer is, Helm specific commands
give more useful features. For example,
`helm-projectile-switch-project` allows opening a project in Dired,
Magit or Eshell. `helm-projectile-find-file` reuses actions in
`helm-find-files` (which is plenty) and able to open multiple
files. Another reason is that in a large source tree, helm-projectile
could be slow because it has to open all available sources.

If you want to use these commands, you have to activate it to replace
the normal Projectile commands:

```el
;; (setq helm-projectile-fuzzy-match nil)
(require 'helm-projectile)
(helm-projectile-on)
```

If you already activate helm-projectile key bindings and you don't
like it, you can turn it off and use the normal Projectile bindings
with command `helm-projectile-off`. Similarly, if you want to disable
fuzzy matching in Helm Projectile (it is enabled by default), you must
set `helm-projectile-fuzzy-match` to nil before loading
`helm-projectile`.

To fully learn Helm Projectile and see what it is capable of, you
should refer to this guide:
[Exploring large projects with Projectile and Helm Projectile](http://tuhdo.github.io/helm-projectile.html).

Obviously you need to have Helm installed for this to work. :-)

![Helm-Projectile Screenshot](screenshots/helm-projectile.png)

## Project Status

The project is currently looking for more maintainers. I (Bozhidar) don't use Helm myself and
don't have much time for the project, so I would definitely appreciate some help with it.

Contact me via e-mail or twitter if you'd like to become a co-maintainer.

## Known issues

Check out the project's
[issue list](https://github.com/bbatsov/helm-projectile/issues?sort=created&direction=desc&state=open)
a list of unresolved issues. By the way - feel free to fix any of them
and sent me a pull request. :-)

## Contributors

Here's a [list](https://github.com/bbatsov/helm-projectile/contributors) of all the people who have contributed to the
development of Projectile.

## Changelog

A fairly extensive changelog is available [here](CHANGELOG.md).

**Note:** We started keeping track of changes there after version 1.0.

## License

Copyright © 2011-2020 Bozhidar Batsov and
[contributors](https://github.com/bbatsov/helm-projectile/contributors).

Distributed under the GNU General Public License, version 3

[badge-license]: https://img.shields.io/badge/license-GPLv3-blue.svg
