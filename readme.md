# ID-password manager

## What is id-manager?

This utility manages ID-password list and generates passwords.

The ID-password DB is saved in the tab-separated file. The default file name of the DB `idm-database-file' is *"~/.idm-db.gpg"*.
The file format is following:

    (name)^t(ID)^t(password)^t(Update date "YYYY/MM/DD")[^t(memo)]

One can prepare an initial data or modify the data by hand or the Excel.

Implicitly, this elisp program expects that the DB file is encrypted by the some GPG encryption elisp, such as EasyPG or alpaca.
The program EasyPG is included in Emacs 23 and later. One can find the program alpaca at: http://www.mew.org/~kazu/proj/cipher/alpaca.el

Excuting the command `idm-open-list-command`, you can open the ID-password list buffer. Check the command `describe-bindings`.

## Installation

To use this program, locate this file to load-path directory,
and add the following code to your .emacs.

    (require 'id-manager)

If you have anything.el, bind `id-manager' to key,
like _(global-set-key (kbd "M-7") 'id-manager)_.

## Setting example:

### For EasyPG users:

    (autoload 'id-manager "id-manager" nil t)
    (global-set-key (kbd "M-7") 'id-manager)                     ; anything UI
    (setq epa-file-cache-passphrase-for-symmetric-encryption t)  ; saving password
    (setenv "GPG_AGENT_INFO" nil)                                ; non-GUI password dialog.

### For alpaca users:

    (autoload 'id-manager "id-manager" nil t)
    (global-set-key (kbd "M-7") 'id-manager) ; anything UI
    (setq idm-db-buffer-save-function ; adjustment for alpaca.el
          (lambda (file)
            (set-visited-file-name file)
            (alpaca-save-buffer))
          idm-db-buffer-password-var  ; if you are using `alpaca-cache-passphrase'.
            'alpaca-passphrase)

--------------------------------------------------

SAKURAI, Masashi
m.sakurai atmark kiwanami.net
