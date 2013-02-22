;;; lookup-cache.el --- disk cache routines -*- lexical-binding: t -*-
;; Copyright (C) 2000 Keisuke Nishida <knishida@ring.gr.jp>

;; Author: Keisuke Nishida <knishida@ring.gr.jp>
;; Keywords: dictionary

;; This file is part of Lookup.

;; Lookup is free software; you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2 of the License, or
;; (at your option) any later version.

;; Lookup is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with Lookup; if not, write to the Free Software Foundation,
;; Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

;;; Code:

(require 'lookup)

(defconst lookup-dump-functions
  '(lookup-dump-agent-attributes
    lookup-dump-dictionary-attributes
    lookup-dump-module-attributes
    lookup-dump-entry-attributes))

(defvar lookup-agent-attributes nil
  "Agent attributes restored from cache.")
(defvar lookup-dictionary-attributes nil
  "Dictionary attributes restored from cache.")
(defvar lookup-module-attributes nil
  "Module attributes restored from cache.")
(defvar lookup-entry-attributes nil
  "Entry attributes restored from cache.")

;; 
(defvar lookup-cache-bookmarks nil)


;;;
;;; Interface functions
;;;

(defconst lookup-cache-notes "\
;; The definitions in this file overrides those in ~/.lookup.
;; If you want to modify this file by hand, follow this instruction:
;;
;;   1. M-x lookup-exit
;;   2. Edit (or remove) this file as you like.
;;   3. M-x lookup-restart")

(defun lookup-dump-cache (file)
  (let ((name (file-name-nondirectory file)))
    (with-temp-buffer
      (insert ";;; " name " --- Lookup cache file\t\t-*- emacs-lisp -*-\n")
      (insert ";; Generated by `lookup-dump-cache' on "
	      (format-time-string "%B %e, %Y") ".\n\n")
      (insert lookup-cache-notes "\n\n")
      (mapc 'funcall lookup-dump-functions)
      (insert "\n;;; " name " ends here\n")
      (write-region (point-min) (point-max) (expand-file-name file)))))


;;;
;;; Agent attributes
;;;

(defun lookup-dump-agent-attributes ()
  (setq lookup-agent-attributes
	(mapcar (lambda (agent)
		  (list (lookup-agent-id agent)
			(cons 'dictionaries
			      (mapcar 'lookup-dictionary-name
				      (lookup-agent-dictionaries agent)))
                        ;(cons 'options
                        ;      (lookup-agent-options agent))
                        ))
		lookup-agent-list))
  (lookup-dump-list 'lookup-agent-attributes 2))

(defun lookup-restore-agent-attributes (agent)
  (let ((alist (lookup-assoc-get lookup-agent-attributes
				 (lookup-agent-id agent))))
    (lookup-put-property
     agent 'dictionaries
     (mapcar (lambda (name) (lookup-new-dictionary agent name))
	     (lookup-assq-get alist 'dictionaries)))
    ;(setf (lookup-agent-options agent) (lookup-assq-get alist 'options))
    ))


;;;
;;; Module attributes
;;;

(defun lookup-dump-module-attributes ()
  (setq lookup-module-attributes
	(mapcar (lambda (module)
		  (list (lookup-module-name module)
                        (cons 'dictionaries
                              (mapcar 'lookup-dictionary-id
                                      (lookup-module-dictionaries module)))
                        (cons 'priority-alist
                              (mapcan (lambda (x)
                                        (if (car x)
                                            (list (cons (lookup-dictionary-id (car x)) (cdr x)))))
                                      (lookup-module-priority-alist module)))
			(cons 'bookmarks
                              (mapcar 'lookup-entry-id
                                      (lookup-module-bookmarks module)))
                        ))
		lookup-module-list))
  (lookup-dump-list 'lookup-module-attributes 3))

;(defun lookup-dump-module-attributes ()
;  (dolist (module lookup-module-list)
;    (let (alist)
;      (let ((marks (mapcar 'lookup-entry-id
;			   (lookup-module-bookmarks module))))
;	(if marks (setq alist (lookup-assq-put alist 'bookmarks marks))))
;      (setq lookup-module-attributes 
;            (lookup-assoc-put lookup-module-attributes
;			(lookup-module-name module) alist))
;      )
;;  (lookup-dump-list 'lookup-module-attributes 3))

(defun lookup-restore-module-attributes (module)
  (let ((alist (lookup-assoc-get lookup-module-attributes
                                 (lookup-module-name module))))
    (let ((dictionaries (mapcar 'lookup-get-dictionary
                                (lookup-assq-get alist 'dictionaries))))
      (setq dictionaries (delete-if 'null dictionaries))
      (setf (lookup-module-dictionaries module) dictionaries))
    (let ((priority-alist (mapcar (lambda (x)
                                    (cons (lookup-get-dictionary (car x)) (cdr x)))
                                  (lookup-assq-get alist 'priority-alist))))
      (setq priority-alist (delete-if 'null priority-alist))
      (setf (lookup-module-priority-alist module) priority-alist))
    (let ((bookmarks (mapcar 'lookup-get-entry-create
                             (lookup-assq-get alist 'bookmarks))))
      (setf (lookup-module-bookmarks module) bookmarks))))


;;;
;;; Dictionary attributes
;;;

(defun lookup-dump-dictionary-attributes ()
  (setq lookup-dictionary-attributes
	(mapcar (lambda (dict)
		  (list (lookup-dictionary-id dict)
			(cons 'title (lookup-dictionary-title dict))
			(cons 'methods (lookup-dictionary-methods dict))
                        ;; dictionary options are put by support files.
                        ;(cons 'options
                        ;      (lookup-dictionary-options dict))))
                        ))
		lookup-dictionary-list))
  (lookup-dump-list 'lookup-dictionary-attributes 2))

(defun lookup-restore-dictionary-attributes (dictionary)
  (dolist (pair (lookup-assoc-get lookup-dictionary-attributes
				  (lookup-dictionary-id dictionary)))
    (lookup-put-property dictionary (car pair) (cdr pair))))


;;;
;;; Entry attributes
;;;

(defun lookup-dump-entry-attributes ()
  (dolist (entry (lookup-entry-list))
    (let ((id (lookup-dictionary-id (lookup-entry-dictionary entry)))
	  (bookmark (lookup-entry-bookmark entry))
	  plist heading)
      (when (and bookmark lookup-cache-bookmarks)
	(setq plist (plist-put plist 'bookmark bookmark)))
      (when plist
	(setq heading (lookup-get-property entry 'original-heading))
	(setq plist (plist-put plist 'heading heading)))
      (let ((alist (lookup-assoc-get lookup-entry-attributes id)))
	(setq alist (lookup-assoc-put alist (lookup-entry-code entry) plist))
	(lookup-assoc-set 'lookup-entry-attributes id alist))))
  (lookup-dump-list 'lookup-entry-attributes 2))

(defun lookup-restore-entry-attributes (entry)
  (let* ((id (lookup-dictionary-id (lookup-entry-dictionary entry)))
	 (alist (lookup-assoc-get lookup-entry-attributes id))
	 (plist (lookup-assoc-get alist (lookup-entry-code entry))))
    (when plist
      (lookup-put-property entry 'original-heading
				 (plist-get plist 'heading))
      (when lookup-cache-bookmarks
	(setf (lookup-entry-bookmark entry) (plist-get plist 'bookmark))))))


;;;
;;; Internal functions
;;;

(defun lookup-dump-list (symbol &optional level)
  (when (symbol-value symbol)
    (insert "(setq " (symbol-name symbol))
    (let ((list (symbol-value symbol)))
      (if (not level)
	  (insert (format "'%S)\n" list))
	(insert "\n      '(")
	(lookup-dump-list-1 list 0 (1- level))
	(insert "))\n\n")))))

(defun lookup-dump-list-1 (list layer level)
  (let* ((emp "") (prefix emp))
    (while list
      (if (or (= layer level) (not (listp (car list))))
	  (insert prefix (format "%S" (car list)))
	(insert prefix "(")
	(lookup-dump-list-1 (car list) (1+ layer) level)
	(insert ")"))
      (if (eq prefix emp)
	  (setq prefix (concat "\n\t" (make-string layer ? ))))
      (setq list (cdr list)))))

(provide 'lookup-cache)

;;; lookup-cache.el ends here
