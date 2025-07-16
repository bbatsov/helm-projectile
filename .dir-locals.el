((emacs-lisp-mode . ((flycheck-emacs-lisp-load-path . inherit)
                     (eval . (progn
                               (setq-local package-lint--sane-prefixes
                                           (rx (or (regexp package-lint--sane-prefixes)
                                                   (seq string-start "helm-source-")))))))))
