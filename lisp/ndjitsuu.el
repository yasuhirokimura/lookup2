;;; ndjitsuu.el --- Lookup `jitsuu' interface -*- lexical-binding: t -*-
;; Copyright (C) 2009 KAWABATA Taichi <kawabata.taichi@gmail.com>

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

;;; Documentation:

;; ndjitsuu.el provides the interface for 「字通」(Jitsuu) dictionary.

;; You must prepare index text file (`oyaji.txt' and `jukugo.txt'), that
;; should be generated by `jitsuu_mk_oyaji_lst.rb' and
;; `jitsuu_mk_jukugo_lst.rb' program (Shift_JIS encoding), and then
;; convert gaijis in generated files to Unicode by
;; `ndjitsuu-convert-gaiji-to-ucs' function equipped in this file, and
;; then they should be saved by `UTF-8' encoding.
;;
;; Usage:
;;
;; (setq lookup-search-agents
;;       '(
;;         ....
;;         (ndjitsuu "~/edicts/Jitsuu"        ; location where `DATA' directory exists.
;;            :fonts "~/edicts/Jitsuu/Fonts") ; JitsuuXX.ttf fonts directory
;;         ....
;;         ))

;;; Code:

(require 'lookup)
(require 'ndtext)
(load "support-files/support-jitsuu")



;;;
;;; Customizable Variables
;;;

(defvar ndjitsuu-tmp-directory 
  (expand-file-name (concat temporary-file-directory "/ndjitsuu"))
  "Temporafy Directory for NDJitsuu file.")

(defvar ndjitsuu-convert-program "convert") ;; ImageMagick

;(defvar ndjitsuu-convert-program-options
;  '("-background"  "white"  "-fill" "black" "-transparent" "white"))

(defvar ndjitsuu-font-size-offset 12)

;;;
;;; Internal variables
;;;

;; HONMON
(defvar ndjitsuu-dat-file nil)
(defvar ndjitsuu-inf-file nil)
(defvar ndjitsuu-inf-header 8)
(defvar ndjitsuu-inf-entry-number 7232)
(defvar ndjitsuu-inf-table-size 8) ; start (4) length (4)

;; OYAJI
(defvar ndjitsuu-oyaji-file nil)
(defvar ndjitsuu-oyaji-header-length 32)
(defvar ndjitsuu-oyaji-number 7232)
(defvar ndjitsuu-oyaji-entry-size 190)

;; JUKUGO
(defvar ndjitsuu-jukugo-header-length 32)
(defvar ndjitsuu-jukugo-number 126189)
(defvar ndjitsuu-jukugo-entry-size 102)

;; Fonts
(defvar ndjitsuu-font-directory nil)

;; INI
(defvar ndjitsuu-st-code
  '(( 0 nil   0 'normal)
    ( 1 "01"  0 'normal) ; for search
    (11 "11"  0 'normal) ; for search
    (12 "12"  0 'normal) ; for search
    (13 "13"  0 'normal)
    (14 "14"  0 'normal)
    (15 "15"  0 'normal)
    (24 "14"  0 'extra)
    (25 "15"  0 'extra)
    (30 "01"  0 'large)
    (31 "01"  0 'large)
    (32 "01"  0 'large)
    (33 "11"  0 'large)
    (34 "11"  0 'large)
    (35 "11"  0 'large)
    (36 nil   2 'normal) ; gothic
    (37 nil   6 'normal) ; mincho
    (38 nil   2 'normal) ; gothic
    (39 nil   0 'large)  ; mincho
    (40 "01"  6 'normal)
    (41 "11"  6 'normal)
    (42 "12"  6 'normal)
    (43 "13"  6 'normal)
    (44 "14"  6 'normal)
    (45 "15"  6 'normal)
    (50 nil   0 'normal) ; Times Roman
    (51 "H1"  0 'normal)
    (70 nil   8 'normal) ; mincho
    (71 "01"  8 'normal)
    (72 "01"  8 'large)
    (80 nil  16 'normal) ; mincho
    (81 "01" 16 'normal)
    ))

(defvar ndjitsuu-font-size
  '((normal . 16) (large . 24) (extra . 48)))

(defvar ndjitsuu-font-face
  '(( 2 . lookup-heading-1-face)
    ( 6 . lookup-heading-4-face)
    ( 8 . lookup-heading-3-face)
    (16 . lookup-heading-2-face)))

(defvar ndjitsuu-image-links
  '((0 . "jitsu_00001.tif")
    (1 . "jitsu_00001.tif")
    (2 . "jitsu_00004.tif")
    (3 . "jitsu_00005.tif")
    (4 . "jitsu_00006.tif")
    (5 . "jitsu_00007.tif")))

(defvar ndjitsuu-gaiji-table nil)

;;;
;;; Interface functions
;;;

(put 'ndjitsuu :methods 'ndjitsuu-methods)
(defun ndjitsuu-methods (ignored)
  ;; DICTIONARY is ignored
  '(exact prefix suffix substring))

(put 'ndjitsuu :list 'ndjitsuu-list)
(defun ndjitsuu-list (agent)
  "Return list of dictionaries of AGENT."
  (let ((dictionary (lookup-new-dictionary agent "")))
    (ndjitsuu-initialize dictionary)
    (list dictionary)))

(put 'ndjitsuu :title 'ndjitsuu-title)
(defun ndjitsuu-title (ignored)
  ;; DICTIONARY is ignored
  "【字通】")

(put 'ndjitsuu :search 'ndjitsuu-search)
(defun ndjitsuu-search (dictionary query)
  "Return entries list of DICTIONARY for QUERY."
  (ndjitsuu-initialize dictionary)
  (let* ((string (lookup-query-string query))
         (method (lookup-query-method query)))
    (if (string-match "^[0-9]+\\(:[0-9]+\\)?$" string)
         ;; 親字番号検索
        (let ((number (string-to-number string)))
          (when (and (< 0 number) (<= number ndjitsuu-oyaji-number))
            (list (lookup-new-entry 'regular dictionary string
                                    (ndjitsuu-oyaji number)))))
      ;; 一般検索
      (let (file-word-pairs)
        (cond
         ((string-match "^\\cC$" string)
          ;; 親字（１漢字）検索
          (setq file-word-pairs (list (list ndjitsuu-oyaji-index-file
                                            (concat "《" string "》"))))
          (if (or (equal method 'suffix) (equal method 'prefix)
                  (equal method 'substring))
              ;; 熟語検索
              (push
               (list (cons ndjitsuu-jukugo-index-file
                           (concat (if (equal method 'prefix) "【" "")
                                   string
                                   (if (equal method 'suffix) "】" ""))))
               file-word-pairs)))
         ((string-match "^\\cC\\cC$" string) 
          ;; 熟語（２漢字）検索
          (setq file-word-pairs (list (list ndjitsuu-jukugo-index-file
                                            (concat "【" string "】")))))
         ;; かな検索
         ((string-match "^\\cH+$" string)
          (let* ((string (replace-regexp-in-string "ゃ" "や" string))
                 (string (replace-regexp-in-string "ゅ" "ゆ" string))
                 (string (replace-regexp-in-string "ょ" "よ" string))
                 (prefix (if (or (equal method 'exact) (equal method 'prefix))
                             "<yomi>" ""))
                 (suffix (if (or (equal method 'exact) (equal method 'suffix))
                             "</yomi>" ""))
                 (katakana (japanese-katakana string)))
            (setq file-word-pairs
                  (list (list ndjitsuu-oyaji-index-file
                              (concat prefix string suffix))
                        (list ndjitsuu-jukugo-index-file
                              (concat prefix string suffix))
                        (list ndjitsuu-oyaji-index-file
                              (concat prefix katakana suffix)))))))
        (if file-word-pairs
            (mapcar (lambda (item)
                      (lookup-new-entry
                       'regular dictionary
                       (car item)
                       (replace-regexp-in-string "</?yomi>" "" (cdr item))))
                    (ndjitsuu-search-files file-word-pairs)))))))

(put 'ndjitsuu :content 'ndjitsuu-content)
(defun ndjitsuu-content (entry)
  "Return string content of ENTRY."
  (ndjitsuu-initialize (lookup-entry-dictionary entry))
  (let* ((code (lookup-entry-code entry))
         (index (string-to-number code))
         (subindex (if (string-match ":\\([0-9]+\\)" code)
                       (match-string 1 code)))
         (dictionary (lookup-entry-dictionary entry))
         (head
          (if subindex
              (lookup-new-entry 'regular dictionary
                                (number-to-string index)
                                (ndjitsuu-oyaji index))))
         (prev
          (if (/= index 1)
              (lookup-new-entry 'regular dictionary
                                (number-to-string (1- index))
                                (ndjitsuu-oyaji (1- index)))))
         (next
          (if (/= index ndjitsuu-oyaji-number)
              (lookup-new-entry 'regular dictionary
                                (number-to-string (1+ index))
                                (ndjitsuu-oyaji (1+ index))))))
    (concat
     (ndjitsuu-inf-entry index subindex)
     (when head
       (let ((text (concat "\n親字：" (lookup-entry-heading head))))
         (lookup-set-link 4 (length text) head text)
         text))
     (when prev
       (lookup-put-property entry :preceding prev)
       (let ((text (concat "\n前項目：" (lookup-entry-heading prev))))
         (lookup-set-link 5 (length text) prev text)
         text))
     (when next
       (lookup-put-property entry :following next)
       (let ((text (concat "\n次項目：" (lookup-entry-heading next))))
         (lookup-set-link 5 (length text) next text)
         text))
    )))

(put 'ndjitsuu :arranges
     '((replace ndjitsuu-arrange-replace)))

(put 'ndjitsuu :reference-pattern
     '("<REF,\\([0-9]+\\)>\\(.+?\\)</REF>" 2 2 1))

(put 'ndjitsuu :charsets (lambda (x) (string-match "^\\(\\cC+\\|\\cH+\\|\\cK+\\)$" x)))

(defun ndjitsuu-arrange-replace (ignored)
  ;; ENTRY is ignored
  "Arrange contents of ENTRY."
  (while (re-search-forward "<ST,\\([0-9]+\\)>\\(.+?\\)</ST>" nil t)
    (let* ((st-code    (string-to-number (match-string 1)))
           (string     (match-string 2))
           (st-entry   (assq st-code ndjitsuu-st-code))
           (font-code  (elt st-entry 1))
           (font-face  (cdr (assq (eval (elt st-entry 2)) ndjitsuu-font-face)))
           (font-size  (cdr (assq (eval (elt st-entry 3)) ndjitsuu-font-size)))
           (gaiji      (car (lookup-gaiji-table-ref
                             ndjitsuu-gaiji-table
                             (format "%s-%X" font-code
                                     (string-to-char string)))))
           text-props
           (start    (match-beginning 0)) end)
      (replace-match (or gaiji string) t)
      (setq end (point))
      (if (and (null gaiji)
               font-code
               (not (equal font-code "01")))
          ;; Gaiji
          (let ((image (ndjitsuu-font-image font-code font-size (elt string 0))))
            (if (/= (length string) 1) (message "ndjitsuu: warining! length /= 1!!!"))
            (add-text-properties start end (list 'ndjitsuu-font-code font-code))
            (lookup-img-file-insert image 'xbm start end))
        ;; Text
        (if (and font-size
                 (/= font-size 18))
            (setq text-props (list 'display `((height ,(/ font-size 16.0))))))
        (if font-face (setq text-props (append text-props
                                               (list 'face font-face))))
        (if text-props (add-text-properties start end text-props)))))
  (goto-char (point-min))
  (while (re-search-forward "<A,\\([0-9]+\\)>\\(.\\)" nil t)
    (let ((match (match-string 2)))
      (add-text-properties 0 1
                           (list 'ndjitsuu-anchor
                                 (substring-no-properties (match-string 1)))
                           match)
      (replace-match match)))
  (goto-char (point-min))
  (while (re-search-forward "</A>" nil t) (replace-match "")))

;;;
;;; Initialize
;;;

(defun ndjitsuu-initialize (dict)
  (unless ndjitsuu-dat-file
    (let* ((agent (lookup-dictionary-agent dict))
           (location (lookup-agent-location agent)))
      (setq ndjitsuu-dat-file 
            (expand-file-name "DATA/DAT/HONMON.DAT" location)
            ndjitsuu-inf-file 
            (expand-file-name "DATA/DAT/HONMON.INF" location)
            ndjitsuu-oyaji-file 
            (expand-file-name "DATA/LST/OYAJI.LST" location)
            ndjitsuu-oyaji-index-file
            (expand-file-name "oyaji.txt" location)
            ndjitsuu-jukugo-index-file
            (expand-file-name "jukugo.txt" location)
            ndjitsuu-font-directory 
            (or (lookup-agent-option agent :fonts)
                (expand-file-name "Fonts" location)))
      (unless (and ndjitsuu-dat-file ndjitsuu-inf-file 
                   ndjitsuu-oyaji-file ndjitsuu-font-directory )
        (error "Files and Directory not properly set.")))))

;;;
;;; Index Search
;;;

(defvar ndjitsuu-grep-program "grep")

(defun ndjitsuu-search-files (file-word-pairs)
  (loop for (file word) in file-word-pairs
        nconc
        (with-temp-buffer
          (let (result)
            (message "file=%s" file)
            (call-process ndjitsuu-grep-program nil t nil 
                          "--max-count" (number-to-string lookup-max-hits)
                          word (file-truename file))
            (message "result=%s" (buffer-string))
            (goto-char (point-min))
            (while (re-search-forward "^\\([0-9]+\\(?::[0-9]+\\)?\\) \\(.+\\)$" nil t)
              (push (cons (match-string 1) (match-string 2)) result))
            result))))
;;;
;;; Main Program
;;;

(define-ccl-program ndjitsuu-decode
  '(1
    ;; CCL main code
    ((loop
      (r0 = #xff)
      (r1 = #xff)
      (r2 = #xff)
      (r3 = #xff)
      (read r0)
      (read r1)
      (read r2)
      (read r3)
      (r4 = (r0 << 8))
      (r4 += r1)
      (r4 ^= #xffff)
      (r4 += #x8831)
      (r5 = (r2 << 8))
      (r5 += r3)
      (r5 ^= #xffff)
      (r5 += #xb311)
      (r4 += (r5 >> 16))
      (r0 = ((r4 >> 8) & #xff))
      (r1 = (r4 & #xff))
      (r2 = ((r5 >> 8) & #xff))
      (r3 = (r5 & #xff))
      ;; check
      (if (r0 != 0)
          ((write r0)
           (if (r1 != 0)
               ((write r1)
                (if (r2 != 0)
                    ((write r2)
                     (if (r3 != 0)
                         ((write r3)
                          (repeat)))))))))))
    ((r6 = (r0 != 0))
     (r6 &= (r1 != 0))
     (r6 &= (r2 != 0))
     (r6 &= (r3 != 0))
     (if (r6 != 0)
         (if (r0 != #xff)
             ((r0 ^= #xff)
              (write r0)
              (if (r1 != #xff)
                  ((r1 ^= #xff)
                   (write r1)
                   (if (r2 != #xff)
                       ((r2 ^= #xff)
                        (write r2)))))))))))

(defsubst ndjitsuu-file-contents-literally (file from length)
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally 
     file nil from (+ from length))
    (buffer-string)))

(defun ndjitsuu-file-contents (file from length)
  "Decode coding region"
  (substring-no-properties
   (decode-coding-string
    (string-make-unibyte
     (ccl-execute-on-string 
      'ndjitsuu-decode (make-vector 9 nil)
      (ndjitsuu-file-contents-literally
       file from length))) 'cp932)))

(defun ndjitsuu-str-to-int (str &optional pos)
  (if (null pos) (setq pos 0))
  (+ (* (elt str (+ pos 3)) 16777216)
     (* (elt str (+ pos 2)) 65536)
     (* (elt str (+ pos 1)) 256)
     (elt str pos)))

(defun ndjitsuu-file-read-int (file pos)
  (ndjitsuu-str-to-int
   (ndjitsuu-file-contents-literally file pos 4)))

(defun ndjitsuu-forward-char (num &optional after-tag)
  (while (< 0 num)
    (while (looking-at "<.+?>") (goto-char (match-end 0)))
    (if (< (char-after (point)) 128) (setq num (1- num)) (setq num (- num 2)))
    (forward-char))
  (if after-tag (while (looking-at "<.+?>") (goto-char (match-end 0)))))

(defsubst ndjitsuu-inf-file-read-int (pos)
  (ndjitsuu-file-read-int ndjitsuu-inf-file pos))

(defsubst ndjitsuu-inf-file-contents (pos length)
  (ndjitsuu-file-contents-literally ndjitsuu-inf-file pos length))

(defun ndjitsuu-inf-entry (index &optional subindex)
  "Return content of INDEX (ingeger).
Optional argument SUBINDEX (string) indicates JUKUGO index."
  (let* ((entry-addr (+ ndjitsuu-inf-header
                       (* (1- index) ndjitsuu-inf-table-size)))
         (entry-start
          (ndjitsuu-inf-file-read-int entry-addr))
         (datinfo-start
          (ndjitsuu-inf-file-read-int entry-start))
         (fontspec-start
          (ndjitsuu-inf-file-read-int (+ entry-start 8)))
         (fontspec-length
          (ndjitsuu-inf-file-read-int (+ entry-start 12)))
         (fontspecs
          (ndjitsuu-inf-file-contents fontspec-start fontspec-length))
         (refspec-start
          (ndjitsuu-inf-file-read-int (+ entry-start 16)))
         (refspec-length
          (ndjitsuu-inf-file-read-int (+ entry-start 20)))
         (refspecs
          (ndjitsuu-inf-file-contents refspec-start refspec-length))
         (anchorspec-start
          (ndjitsuu-inf-file-read-int (+ entry-start 24)))
         (anchorspec-length
          (ndjitsuu-inf-file-read-int (+ entry-start 28)))
         (anchorspecs
          (ndjitsuu-inf-file-contents anchorspec-start anchorspec-length))
         (dat-start
          (ndjitsuu-inf-file-read-int datinfo-start))
         (dat-length
          (ndjitsuu-inf-file-read-int (+ datinfo-start 8)))
         (dat
          (ndjitsuu-file-contents ndjitsuu-dat-file dat-start dat-length))
         (char-pos 0)
         start length val val2 current)
    (with-temp-buffer
      (insert dat)

      (goto-char (point-min))
      (setq char-pos 0 current 0)
      (while (< char-pos refspec-length)
        (setq start  (ndjitsuu-str-to-int refspecs char-pos))
        (setq length (ndjitsuu-str-to-int refspecs (+ char-pos 4)))
        (setq val    (ndjitsuu-str-to-int refspecs (+ char-pos 8)))
        (setq val2   (ndjitsuu-str-to-int refspecs (+ char-pos 12)))
        (setq char-pos (+ char-pos 20))
        (ndjitsuu-forward-char (- start current))
        (if (= val 2)
            (insert (format "<REF,%d>" val2))
          (insert (format "<REF,G%d>" val2)))
        (ndjitsuu-forward-char length)
        (insert "</REF>")
        (setq current (+ start length)))

      (goto-char (point-min))
      (setq char-pos 0 current 0)
      (while (< char-pos anchorspec-length)
        (setq val    (substring  anchorspecs char-pos (+ char-pos 4)))
        (setq start  (ndjitsuu-str-to-int anchorspecs (+ char-pos 4)))
        (setq length (ndjitsuu-str-to-int anchorspecs (+ char-pos 8)))
        (setq char-pos (+ char-pos 12))
        (ndjitsuu-forward-char (- start current))
        (insert (format "<A,%s>" val))
        (ndjitsuu-forward-char length)
        (insert "</A>")
        (setq current (+ start length)))

      (goto-char (point-min))
      (setq char-pos 0 current 0)
      (while (< char-pos fontspec-length)
        (setq start  (ndjitsuu-str-to-int fontspecs char-pos))
        (setq length (ndjitsuu-str-to-int fontspecs (+ char-pos 4)))
        (setq val    (ndjitsuu-str-to-int fontspecs (+ char-pos 8)))
        (setq char-pos (+ char-pos 12))
        (ndjitsuu-forward-char (- start current) t)
        (insert (format "<ST,%d>" val))
        (ndjitsuu-forward-char length)
        (insert "</ST>")
        (setq current (+ start length)))

      (goto-char (point-min))
      (if (and subindex
               (search-forward (format "<A,%s>" subindex) nil t))
          (progn
            (setq start (match-end 0))
            (search-forward "</A>" nil t)
            (buffer-substring start (match-beginning 0)))
        (buffer-string)))))

(defun ndjitsuu-oyaji (index)
  (let* ((start (+ ndjitsuu-oyaji-header-length
                   (* ndjitsuu-oyaji-entry-size (1- index)))))
    (ndjitsuu-file-contents
     ndjitsuu-oyaji-file start ndjitsuu-oyaji-entry-size)))

;;; Font Image

(defun ndjitsuu-font-image (font-code size code)
  "Create font image for FONT-CODE, SIZE and CODE.
Returns image file path."
  (if (not (file-directory-p ndjitsuu-tmp-directory))
      (make-directory ndjitsuu-tmp-directory))
  (let* ((font-file
          (expand-file-name
           (concat ndjitsuu-font-directory "/JITSUU" font-code ".TTF")))
         (image-file
          (expand-file-name
           (concat ndjitsuu-tmp-directory "/"
                              (format "p%02d_%s_%04X" size font-code code) ".xbm")))
         (args (append ;ndjitsuu-convert-program-options
                       (list "-size" (format "%02dx%02d" 
                                             (+ ndjitsuu-font-size-offset size)
                                             (+ ndjitsuu-font-size-offset size))
                             "-font" font-file
                             (format "label:%c" code)
                             image-file))))
    (lookup-debug-message "ndjitsuu-font-image:args=%s" args)
    (if (null (file-exists-p image-file))
        (lookup-with-coding-system 'utf-8
          (apply 'call-process ndjitsuu-convert-program nil nil nil args)))
    image-file))

;;;
;;; Utility Function
;;;

(defun ndjitsuu-convert-gaiji-to-ucs ()
  (interactive)
  (goto-char (point-min))
  (while (re-search-forward "<\\(1[123]\\)>\\(.\\)" nil t)
    (let* ((code (concat (match-string 1) "-"
                         (format "%4X" (string-to-char (match-string 2)))))
           (char (car (lookup-gaiji-table-ref
                       ndjitsuu-gaiji-table code)))
           (char (and char (substring char 0 1))))
      (replace-match (or char "〓")))))

(defun ndjitsuu-convert-html-to-ucs ()
  (interactive)
  (goto-char (point-min))
  (while (re-search-forward "<font\\W+face=\"?JITSUU\\([H1].\\)\"?[^>]*>\\(.\\)</font>" nil t)
    (let* ((code (concat (match-string 1) "-"
                         (format "%4X" (string-to-char (match-string 2)))))
           (char (car (lookup-gaiji-table-ref
                       ndjitsuu-gaiji-table code))))
      (replace-match (or char "〓"))))
  (goto-char (point-min))
  (while (re-search-forward "<font\\W+style=\"font-family: JITSUU\\([H1].\\);\"[^>]*>\\W*\\(.\\)[^/]*</font>" nil t)
    (let* ((code (concat (match-string 1) "-"
                         (format "%4X" (string-to-char (match-string 2)))))
           (char (car (lookup-gaiji-table-ref
                       ndjitsuu-gaiji-table code))))
      (replace-match (or char "〓")))))

(provide 'ndjitsuu)

;;; ndjitsuu.el ends here
