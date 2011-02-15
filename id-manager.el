;;; id-manager.el --- id-password management 

;; Copyright (C) 2009  SAKURAI Masashi
;; Time-stamp: <2010-12-18 14:25:02 sakurai>

;; Author: SAKURAI Masashi <m.sakurai@kiwanami.net>
;; Keywords: password, convenience

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; ID-password management utility.
;; This utility manages a ID-password list and generates passwords.

;; The ID-password DB is saved in a tab-separated file.  The default
;; file name of the DB `idm-database-file' is "~/.idm-db.gpg".
;; The file format is following:
;;   (name)^t(ID)^t(password)^t(Update date "YYYY/MM/DD")[^t(memo)]
;; . One can prepare an initial data or modify the data by hand or
;; the Excel.
;; 
;; Implicitly, this elisp program expects that the DB file is
;; encripted by the some GPG encryption elisp, such as EasyPG or
;; alpaca.
;;
;; Excuting the command `idm-open-list-command', you can open the 
;; ID-password list buffer. Check the function `describe-bindings'.

;;; Installation:

;; To use this program, locate this file to load-path directory,
;; and add the following code to your .emacs.
;; ------------------------------
;; (require 'id-manager)
;; ------------------------------
;; If you have anything.el, bind `id-manager' to key,
;; like (global-set-key (kbd "M-7") 'id-manager).

;;; Setting example:

;; For EasyPG users:
;; 
;; (autoload 'id-manager "id-manager" nil t)
;; (global-set-key (kbd "M-7") 'id-manager)                     ; anything UI
;; (setq epa-file-cache-passphrase-for-symmetric-encryption t)  ; saving password
;; (setenv "GPG_AGENT_INFO" nil)                                ; non-GUI password dialog.

;; For alpaca users:
;; 
;; (autoload 'id-manager "id-manager" nil t)
;; (global-set-key (kbd "M-7") 'id-manager) ; anything UI
;; (setq idm-db-buffer-save-function ; adjustment for alpaca.el
;;       (lambda (file)
;;         (set-visited-file-name file)
;;         (alpaca-save-buffer))
;;       idm-db-buffer-password-var  ; if you are using `alpaca-cache-passphrase'.
;;         'alpaca-passphrase)

;;; Current implementation:

;; This program generates passwords by using external command:
;; `idm-gen-password-cmd'. If you have some better idea, please let me
;; know.
;; 
;; I think that this program makes lazy password management more
;; securely.  But I'm not sure that this program is secure enough.
;; I'd like many people to check and advice me.

;;; Code:

(eval-when-compile (require 'cl))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Setting

(defvar idm-database-file "~/.idm-db.gpg"
  "Encripted id-password database file. The file name may
  end with '.gpg' for encryption by the GnuPG.")

(defvar idm-gen-password-cmd
  "head -c 10 < /dev/random | uuencode -m - | tail -n 2 |head -n 1 | head -c10")
;  "openssl rand 32 | uuencode -m - | tail -n 2 |head -n 1 | head -c10"
;  ...any other password generation ?

(defvar idm-copy-action
  (lambda (text) (x-select-text text))
  "Action for copying a password text into clipboard.")

(defvar idm-db-buffer-load-function
  'find-file-noselect
  "File loading function. This function has one argument FILENAME and returns a buffer,
  like `find-file-noselect'. Some decryption should work at this
  function.")

(defvar idm-db-buffer-save-function 
  'write-file
  "File saving function. This function has one arguments FILENAME,
  like `write-file'. Some encryption should work at this
  function.")

(defvar idm-db-buffer-password-var nil
  "Password variable. See the text of settings for alpaca.el. ")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Macros

(defmacro idm--aif (test-form then-form &rest else-forms)
  `(let ((it ,test-form))
     (if it ,then-form ,@else-forms))) 
(put 'idm--aif 'lisp-indent-function 2)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Management API

(defun idm-gen-password ()
  "Generate a password."
  (let ((buf (get-buffer-create " *idm-work*")) ret)
    (call-process-shell-command 
     idm-gen-password-cmd
     nil buf nil)
    (with-current-buffer buf
      (setq ret (buffer-string)))
    (kill-buffer buf)
    ret))

;; record struct 
(defstruct (idm-record 
            (:constructor make-idm-record-bylist 
                          (name account-id password update-time 
                                &optional memo)))
  name account-id password update-time memo)

(defun idm-load-db ()
  "Load the DB file `idm-database-file' and make a DB object."
  (let* ((coding-system-for-read 'utf-8)
         (tmpbuf 
          (funcall idm-db-buffer-load-function
           (expand-file-name idm-database-file)))
         db-object)
    (unwind-protect
        (let ((db (idm--make-db tmpbuf)))
          (when idm-db-buffer-password-var
            (with-current-buffer tmpbuf 
              (funcall db 'file-password 
                       (symbol-value idm-db-buffer-password-var))))
          db)
      (kill-buffer tmpbuf))))

(defun idm--save-db (records &optional password)
  "Save RECORDS into the DB file `idm-database-file'. This
function is called by a DB object."
  (let ((coding-system-for-write 'utf-8)
        (tmpbuf (get-buffer-create " *idm-tmp*")))
    (with-current-buffer tmpbuf
      (erase-buffer)
      (goto-char (point-min))
      (dolist (i records)
        (insert (concat (idm-record-name i) "\t"
                        (idm-record-account-id i) "\t"
                        (idm-record-password i) "\t"
                        (idm-record-update-time i) 
                        (idm--aif (idm-record-memo i)
                            (concat "\t" it))
                        "\n")))
      (when password
        (set idm-db-buffer-password-var password))
      (funcall idm-db-buffer-save-function idm-database-file)
      (kill-buffer tmpbuf))))

(defun idm--make-db (tmpbuf)
  "Build a database management object from the given buffer text.
The object is a dispatch function. One can access the methods
`funcall' with the method name symbol and some method arguments."
  (lexical-let (records (db-modified nil) file-password)
    (idm--each-line 
     tmpbuf 
     (lambda (line)
       (let ((cols (split-string line "\t")))
         (if (or (= 4 (length cols))
                 (= 5 (length cols)))
             (push (apply 'make-idm-record-bylist cols)
                   records)))))
    (lambda (method &rest args)
      (cond
       ((eq method 'get)                      ; get record object by name
        (lexical-let ((name (car args)) ret)
          (mapc (lambda (i) 
                  (if (equal name (idm-record-name i))
                      (setq ret i)))
                records)
          ret))
       ((eq method 'get-all-records) records) ; get-all-records
       ((eq method 'add-record)               ; add-record
        (progn 
          (push (car args) records)
          (setq db-modified t)))
       ((eq method 'delete-record-by-name)    ; delete-record-by-name
        (lexical-let ((name (car args)))
          (setf records (delete-if 
                         (lambda (i) (equal (idm-record-name i) name))
                         records))
          (setq db-modified t)))
       ((eq method 'set-modified)             ; set-modified
        (setq db-modified t))
       ((eq method 'save)                     ; save
        (when db-modified 
          (idm--save-db records file-password)
          (setq db-modified nil)))
       ((eq method 'file-password)            ; file-password
        (setq file-password (car args)) nil)
       (t (error "Unknown method [%s]" method))))))

(defun idm--each-line (buf task)
  "Execute the function TASK with each lines in the buffer
`buf'. This function is called by `idm--make-db'."
  (with-current-buffer buf
    (goto-char (point-min))
    (unless (eobp)
      (while 
          (let ((line 
                 (buffer-substring-no-properties
                  (line-beginning-position)
                  (line-end-position))))
            (funcall task line)
            (forward-line 1)
            (not (eobp)))))))

(defun idm--strtime (time)
  "Translate emacs time to formatted string."
  (format-time-string "%Y/%m/%d" time))

(defun idm--parsetime (str)
  "Translate formatted string to emacs time."
  (when (string-match "\\([0-9]+\\)\\/\\([0-9]+\\)\\/\\([0-9]+\\)" str)
     (apply 'encode-time 
            (let (ret)
              (dotimes (i 6)
                (push (string-to-int (match-string (+ i 1) str)) ret))
              ret))))

(defun idm--message (&rest args)
  "Show private text in the echo area without message buffer
recording."
  (let (message-log-max)
    (apply 'message args)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; GUI

(defun idm-add-record (db)
  "Make an account record interactively and register it with DB."
  (let (name id password memo)
    (setq name (read-string "Account Name : "))
    (when name
      (setq id (read-string "Account ID : "))
      (when id
        (setq password 
              (if (y-or-n-p "Generate a password ? : ")
                  (read-string "Account Password : " (idm-gen-password))
                (read-passwd "Account Password : " t)))
        (setq memo (read-string "Memo : "))
        (funcall db 'add-record (make-idm-record-bylist 
                                 name id password 
                                 (idm--strtime (current-time)) memo))))))

(defun idm-edit-record (record)
  "Edit a record. If editting is finished successfully, return t."
  (when (and record (idm-record-p record))
    (let (name id password memo)
    (setq name (read-string "Account Name : " (idm-record-name record)))
    (when name
      (setq id (read-string "Account ID : " (idm-record-account-id record)))
      (when id
        (setq password 
              (if (y-or-n-p "Generate a password ? : ")
                  (read-string "Account Password : " (idm-gen-password))
                (read-passwd "Account Password : " t (idm-record-password record))))
        (setq memo (read-string "Memo : " (idm-record-memo record)))
        (setf (idm-record-name record) name
              (idm-record-account-id record) id
              (idm-record-password record) password
              (idm-record-update-time record) (idm--strtime (current-time))
              (idm-record-memo record) memo)
        t)))))

(defun idm-edit-record-field (record field)
  "Edit a field of the record. FIELD is a symbol, which can be
`name', `id' and `memo'.  If editting is finished successfully,
return t."
  (when (and record (idm-record-p record))
    (let (title getter setter)
      (cond 
       ((eq field 'name)
        (setq title "Name : "
              getter (lambda (r) (idm-record-name r))
              setter (lambda (r c) (setf (idm-record-name r) c))))
       ((eq field 'id)
        (setq title "ID : "
              getter (lambda (r) (idm-record-account-id r))
              setter (lambda (r c) (setf (idm-record-account-id r) c))))
       ((eq field 'memo)
        (setq title "Memo : "
              getter (lambda (r) (idm-record-memo r))
              setter (lambda (r c) (setf (idm-record-memo r) c))))
       (t (error "BUG : No such field symbol. %S" field)))
      (let ((data (read-string title (funcall getter record))))
        (if data
            (progn
              (funcall setter record data)
              (setf (idm-record-update-time record) (idm--strtime (current-time)))
              t) nil)))))

(defun idm-edit-record-password (record)
  "Edit a password field of the record. If editting is finished successfully, return t."
  (when (and record (idm-record-p record))
    (let ((password 
           (if (y-or-n-p "Generate a password ? : ")
               (read-string "Account Password : " (idm-gen-password))
             (read-passwd "Account Password : " t (idm-record-password record)))))
      (setf (idm-record-password record) password
            (idm-record-update-time record) (idm--strtime (current-time)))
      t)))

(defvar idm-show-password nil
  "Display passwords switch. If this variable is non-nil, some
  functions show the password as plain text.")

(defun idm-toggle-show-password ()
  "Toggle the switch for display passwords."
  (interactive)
  (setq idm-show-password (not idm-show-password)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; id-password list buffer

(defun idm-open-list (db)
  "Open id-password list buffer."
  (lexical-let ((buf (get-buffer-create "ID-Password List"))
                (db db))
    (with-current-buffer buf
      (idm--layout-list db)
      (idm--set-list-mode db)
      )
    (set-buffer buf)))

(defun idm--put-text-property (text attr val)
  "Put a text property on the whole text."
  (put-text-property 0 (length text) attr val text) text)

(defun idm--put-record-id (text id) 
  "Put the record id with the text property `idm-record-id'."
  (idm--put-text-property text 'idm-record-id id))

(defun idm--get-record-id ()
  "Get the record id on the current point."
  (get-text-property (point) 'idm-record-id))

(defun idm--layout-list (db &optional order)
  "Erase the content in the current buffer and insert record
lines. ORDER is sort key, which can be `time', `name' and `id'."
  (unless order
    (setq order 'name))
  (let ((name-max (length "Account Name")) 
        (id-max (length "ID"))
        (pw-max (length "Password"))
        (pw-mask "********")
        (pw-getter (lambda (record) 
                     (if idm-show-password
                         (idm-record-password record)
                       pw-mask)))
        (cut (lambda (str) (substring str 0 (min (length str) 20))))
        numcolm (count 1) 
        (line-format "%%-%ds|%%-10s |  %%-%ds | %%-%ds  :  %%-%ds   : %%s\n")
        (records (funcall db 'get-all-records)))
    (when records
      (setq numcolm (fceiling (log10 (length records))))
      (dolist (i records)
        (setq name-max (min 20 (max name-max (length (idm-record-name i))))
              id-max (min 20 (max id-max (length (idm-record-account-id i))))
              pw-max (max pw-max (length (funcall pw-getter i)))))
      (setq line-format (format line-format numcolm name-max id-max pw-max))
      (unwind-protect
          (progn
            (setq buffer-read-only nil)
            (erase-buffer)
            (goto-char (point-min))
            (insert (format line-format
                            " " "Time" "Name" "ID" "Password" "Memo"))
            (insert (make-string (- (window-width) 1) ?-) "\n")
            (dolist (i (idm--sort-records records order))
              (insert 
               (idm--put-record-id
                (format line-format 
                        count
                        (idm-record-update-time i)
                        (funcall cut (idm-record-name i))
                        (funcall cut (idm-record-account-id i))
                        (funcall pw-getter i)
                        (idm-record-memo i))
                (idm-record-name i)))
              (incf count))
            (goto-char (point-min)))
        (setq buffer-read-only t)))))

(defun idm--sort-records (records order)
  "Sort records by the key ORDER, which can be `time', `name',
`memo' and `id'."
  (let* 
      ((comparator
        (lambda (ref)
          (lexical-let ((ref ref))
            (lambda (i j) 
              (let ((ii (funcall ref i))
                    (jj (funcall ref j)))
                (cond 
                 ((string= ii jj) 0)
                 ((string< ii jj) -1)
                 (t 1)))))))
       (to-bool 
        (lambda (f)
          (lexical-let ((f f))
            (lambda (i j) 
              (< (funcall f i j) 0)))))
       (cmp-id (funcall comparator 'idm-record-account-id))
       (cmp-name (funcall comparator 'idm-record-name))
       (cmp-time (funcall comparator 'idm-record-update-time))
       (cmp-memo (funcall comparator 'idm-record-memo))
       (chain 
        (lambda (a b)
          (lexical-let ((a a) (b b))
            (lambda (i j)
              (let ((v (funcall a i j)))
                (if (= 0 v)
                    (funcall b i j)
                  v)))))))
  (sort 
   (copy-list records)
   (cond
    ((eq order 'id)   ; id -> id, name
     (funcall to-bool (funcall chain cmp-id cmp-name)))
    ((eq order 'name) ; name -> name
     (funcall to-bool cmp-name))
    ((eq order 'time) ; time -> time, name
     (funcall to-bool (funcall chain cmp-time cmp-name)))
    ((eq order 'memo) ; memo -> time, name
     (funcall to-bool (funcall chain cmp-memo cmp-name)))
    (t  ; default
     (funcall to-bool cmp-name))))))

(defvar idm-list-mode-map nil
  "Keymap for `idm-list-mode'.")
(setq idm-list-mode-map nil) ; for debug
(unless idm-list-mode-map
  (setq idm-list-mode-edit-map (make-sparse-keymap))
  (mapc (lambda (i)
          (define-key idm-list-mode-edit-map (car i) (cdr i)))
        '(("n" . idm-list-mode-edit-name)
          ("i" . idm-list-mode-edit-id)
          ("p" . idm-list-mode-edit-password)
          ("m" . idm-list-mode-edit-memo)
          ([return] . idm-list-mode-edit-all)
          ("a" . idm-list-mode-edit-all)))
  (setq idm-list-mode-map (make-sparse-keymap))
  (mapc (lambda (i)
          (define-key idm-list-mode-map (car i) (cdr i)))
        `(("q" . idm-list-mode-quit)
          ("Q" . idm-list-mode-quit-without-save)

          ("n" . next-line)
          ("p" . previous-line)
          ("j" . next-line)
          ("k" . previous-line)

          ("d" . idm-list-mode-delete)
          ("-" . idm-list-mode-delete)
          ("m" . ,idm-list-mode-edit-map)
          ("e" . ,idm-list-mode-edit-map)
          ("a" . idm-list-mode-add)
          ("+" . idm-list-mode-add)

          ("u" . idm-list-mode-reload)
          ("r" . idm-list-mode-reload)

          ("T" . idm-list-mode-sortby-time)
          ("N" . idm-list-mode-sortby-name)
          ("I" . idm-list-mode-sortby-id)
          ("M" . idm-list-mode-sortby-memo)

          ("S" . idm-list-mode-toggle-show-password)
          ("s" . idm-list-mode-show-password)
          ([return] . idm-list-mode-copy)
          )))

(defun idm--list-mode-edit-gen (edit-function)
  (idm--aif (idm--get-record-id)
      (let ((record (funcall idm-db 'get it)))
        (when record
          (when (funcall edit-function record)
            (funcall idm-db 'set-modified)
            (idm--layout-list idm-db))))))

(defun idm-list-mode-edit-id ()
  (interactive)
  (idm--list-mode-edit-gen 
   (lambda (record) (idm-edit-record-field record 'id))))

(defun idm-list-mode-edit-name ()
  (interactive)
  (idm--list-mode-edit-gen 
   (lambda (record) (idm-edit-record-field record 'name))))

(defun idm-list-mode-edit-memo ()
  (interactive)
  (idm--list-mode-edit-gen 
   (lambda (record) (idm-edit-record-field record 'memo))))

(defun idm-list-mode-edit-password ()
  (interactive)
  (idm--list-mode-edit-gen 
   (lambda (record) (idm-edit-record-password record))))

(defun idm-list-mode-copy ()
  (interactive)
  (idm--aif (idm--get-record-id)
      (let ((record (funcall idm-db 'get it)))
        (when record
          (message (concat "Copied the password for the account ID: "
                           (idm-record-account-id record)))
          (funcall idm-copy-action (idm-record-password record))))))

(defun idm-list-mode-sortby-id ()
  (interactive)
  (idm--layout-list idm-db 'id))

(defun idm-list-mode-sortby-name ()
  (interactive)
  (idm--layout-list idm-db 'name))

(defun idm-list-mode-sortby-time ()
  (interactive)
  (idm--layout-list idm-db 'time))

(defun idm-list-mode-sortby-memo ()
  (interactive)
  (idm--layout-list idm-db 'memo))

(defun idm-list-mode-reload ()
  "Reload the id-password database file."
  (interactive)
  (setq idm-db (idm-load-db))
  (idm--layout-list idm-db))

(defun idm-list-mode-toggle-show-password ()
  "Toggle whether to show passwords."
  (interactive)
  (idm-toggle-show-password)
  (idm--layout-list idm-db))

(defun idm-list-mode-show-password ()
  "Show password of the selected record."
  (interactive)
  (idm--aif (idm--get-record-id)
      (let ((record (funcall idm-db 'get it)))
        (if record
            (idm--message 
             (concat
              "ID: " (idm-record-account-id record)
              " / PW: "(idm-record-password record)))))))

(defun idm--set-list-mode (db)
  "Set up major mode for id-password list mode."
  (kill-all-local-variables)
  (make-local-variable 'idm-db)
  (setq idm-db db)
  
  (setq truncate-lines t)
  (use-local-map idm-list-mode-map)
  (setq major-mode 'idm-list-mode
        mode-name "ID-Password List")
  (hl-line-mode 1))

(defun idm-list-mode-quit ()
  "Save the DB and kill buffer."
  (interactive)
  (funcall idm-db 'save)
  (kill-buffer (current-buffer)))

(defun idm-list-mode-quit-without-save ()
  "Kill buffer without saving the DB."
  (interactive)
  (kill-buffer (current-buffer)))

(defun idm-list-mode-delete ()
  "Delete a selected record from the DB. After deleting, update
the list buffer."
  (interactive)
  (idm--aif (idm--get-record-id)
      (progn
        (funcall idm-db 'delete-record-by-name it)
        (idm--layout-list idm-db))))

(defun idm-list-mode-add ()
  "Add a new record. After adding, update the list buffer."
  (interactive)
  (idm-add-record idm-db)
  (idm--layout-list idm-db))

(defun idm-list-mode-edit ()
  "Edit a selected record. After editting, update the list
buffer."
  (interactive)
  (idm--aif (idm--get-record-id)
      (let ((record (funcall idm-db 'get it)))
        (if record
            (when (idm-edit-record record)
              (funcall idm-db 'set-modified)
              (idm--layout-list idm-db))))))

(defun idm-open-list-command (&optional db)
  "Load the id-password DB and open a list buffer."
  (interactive)
  (unless db
    (setq db (idm-load-db)))
  (switch-to-buffer (idm-open-list db)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Anything UI

(when (featurep 'anything)

  (defun id-manager ()
    (interactive)
    (let* ((db (idm-load-db))
           (source-commands 
            `((name . "Global Command : ")
              (candidates 
               . (("Add a record" .
                   (lambda ()
                     (idm-add-record db)
                     (funcall db 'save)
                     (when (eq major-mode 'idm-list-mode)
                       (idm--layout-list db))))
                  ("Show all records" .
                   (lambda ()
                     (idm-open-list-command db)))))
              (action . (("Execute" . (lambda (i) (funcall i)))))))
           (source-records 
            '((name . "Accounts : ")
              (candidates 
               . (lambda ()
                   (mapcar
                    (lambda (record)
                      (cons (concat 
                             (idm-record-name record) 
                             " (" (idm-record-account-id record) ") "
                             "   " (idm-record-memo record))
                             record))
                    (funcall db 'get-all-records))))
              (action 
               . (("Copy password" 
                   . (lambda (record) 
                       (message (concat "Copied the password for the account ID: "
                                        (idm-record-account-id record)))
                       (funcall idm-copy-action (idm-record-password record))))
                  ("Show ID / Password" 
                   . (lambda (record) 
                       (idm--message 
                        (concat 
                         "ID: " (idm-record-account-id record)
                         " / PW: "(idm-record-password record)))))
                  ("Edit all fields" 
                   . (lambda (record)
                       (when (idm-edit-record record)
                         (funcall db 'set-modified)
                         (funcall db 'save)))) 
                  ("Edit NAME field" 
                   . (lambda (record)
                       (when (idm-edit-record-field record 'name)
                         (funcall db 'set-modified)
                         (funcall db 'save)))) 
                  ("Edit ID field" 
                   . (lambda (record)
                       (when (idm-edit-record-field record 'id)
                         (funcall db 'set-modified)
                         (funcall db 'save)))) 
                  ("Edit PASSWORD field" 
                   . (lambda (record)
                       (when (idm-edit-record-password record)
                         (funcall db 'set-modified)
                         (funcall db 'save)))) 
                  ("Edit MEMO field" 
                   . (lambda (record)
                       (when (idm-edit-record-field record 'memo)
                         (funcall db 'set-modified)
                         (funcall db 'save)))) 
                  )))
            ))
      (anything 
       '(source-commands source-records)
       nil "ID-Password Management : " nil nil)))

  ) ; anything

(provide 'id-manager)
;;; id-manager.el ends here
