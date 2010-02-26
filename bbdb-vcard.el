;;; bbdb-vcard.el --- import vCards into BBDB

;; Copyright (c) 2010 Bert Burgemeister

;; Author: Bert Burgemeister <trebbu@googlemail.com> Keywords:
;; calendar mail news

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2, or (at
;; your option) any later version.

;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.


;;; Commentary:


;;; Code:

;; Don't mess up our real BBDB yet
(setq bbdb-file "test-bbdb")

(require 'bbdb)
(require 'cl)

(defgroup bbdb-vcard nil
  "Customizations for vcards"
  :group 'bbdb)

(defun bbdb-vcard-import-file (vcard-file)
  "Import vcards from VCARD-FILE into BBDB. Existing BBDB entries may
be altered."
  (interactive "fVcard file: ")
  (with-temp-buffer
    (insert-file-contents vcard-file)
    (bbdb-vcard-iterate-vcards (buffer-string) 'bbdb-vcard-process-vcard)))

(defun bbdb-vcard-import-buffer (vcard-buffer)
  "Import vcards from VCARD-BUFFER into BBDB. Existing BBDB entries may
be altered."
  (interactive "bVcard buffer: ")
  (set-buffer vcard-buffer)
  (bbdb-vcard-iterate-vcards (buffer-string) 'bbdb-vcard-process-vcard))

(defun bbdb-vcard-iterate-vcards (vcards vcard-processor)
  "Apply VCARD-PROCESSOR successively to each vcard in string VCARDS"
  (with-temp-buffer
    (insert vcards)
    (print (buffer-string) (get-buffer-create "foo"))
    (goto-char (point-min))
    (while (re-search-forward "
      (replace-match "")) ; Unfold folded lines.
    (goto-char (point-min))
    ;; Change CR into CRLF if necessary.
    (while (re-search-forward "[^
      (replace-match "
    (goto-char (point-min))
    (print (buffer-string) (get-buffer "foo"))
    (while (re-search-forward
            "^BEGIN:VCARD\\([
            nil t)
      (funcall vcard-processor (match-string 1)))))

(defcustom bbdb-vcard-skip
  ""
  "Regexp describing types from a vcard entry which are to be
discarded."
  :group 'bbdb-vcard
  :type 'regexp)

(defun bbdb-vcard-process-vcard (entry)
  "Store the vcard ENTRY (BEGIN:VCARD and END:VCARD delimiters stripped off)
in BBDB. Extend existing BBDB entries where possible."
  (with-temp-buffer
    (insert entry)
    (unless (string= (cdr (assoc "value" (car (bbdb-vcard-entries-of-type "version")))) "3.0")
      (display-warning '(bbdb-vcard xy)
                       "Not a version 3.0 vcard."))
    (let* ((raw-name (cdr (assoc "value" (car (bbdb-vcard-entries-of-type "N" t)))))
           ;; Name suitable for storing in BBDB:
           (name (bbdb-vcard-convert-name raw-name))
           ;; Name to search for in BBDB now:
           (name-to-search-for (when raw-name
                                 (if (stringp raw-name)
                                     raw-name
                                   (concat (nth 1 raw-name) ;given name
                                           " .*"
                                           (nth 0 raw-name))))) ; family name
           ;; Additional names from prefixed types like A.N, B.N etc.:
           (other-names (mapcar (lambda (element)
                                  (mapconcat 'identity
                                             (bbdb-vcard-convert-name (cdr (assoc "value" element)))
                                             " "))
                                (bbdb-vcard-entries-of-type "N")))
           (formatted-names (mapcar (lambda (element) (cdr (assoc "value" element)))
                                    (bbdb-vcard-entries-of-type "FN")))
           (nicknames (bbdb-vcard-split-structured-text
                       (cdr (assoc "value" (car (bbdb-vcard-entries-of-type "NICKNAME"))))
                       "," t))
           ;; Company suitable for storing in BBDB:
           (org (cdr (assoc "value" (car (bbdb-vcard-entries-of-type "ORG" t)))))
           ;; Company to search for in BBDB now:
           (org-to-search-for org) ; sorry
           ;; Email suitable for storing in BBDB:
           (email (mapcar (lambda (element) (cdr (assoc "value" element)))
                          (bbdb-vcard-entries-of-type "EMAIL")))
           ;; Email to search for in BBDB now:
           (email-to-search-for (when email
                                  (concat "\\("
                                          (mapconcat 'identity email "\\)\\|\\(")
                                          "\\)")))
           ;; Phone numbers
           (tels (mapcar (lambda (element)
                           (vector (bbdb-vcard-translate (cdr (assoc "type" element)))
                                   (cdr (assoc "value" element))))
                         (bbdb-vcard-entries-of-type "TEL")))
           ;; Addresses
           (adrs (mapcar (lambda (element)
                           (vector (bbdb-vcard-translate (cdr (assoc "type"
                                                                     element)))
                                   ;; Postbox, Extended, Streets
                                   (remove-if (lambda (x) (zerop (length x)))
                                              (subseq (cdr (assoc "value" element)) 0 3))
                                   (elt (cdr (assoc "value" element)) 3) ; City
                                   (elt (cdr (assoc "value" element)) 4) ; State
                                   (elt (cdr (assoc "value" element)) 5) ; Zip
                                   (elt (cdr (assoc "value" element)) 6))) ; Country
                         (bbdb-vcard-entries-of-type "ADR")))
           (url (cdr (assoc "value" (car (bbdb-vcard-entries-of-type "URL" t)))))
           (vcard-notes (print (bbdb-vcard-entries-of-type "NOTE") (get-buffer-create "foo")))
           (bday (cdr (assoc "value" (car (bbdb-vcard-entries-of-type "BDAY" t)))))
           ;; The BBDB record to change:
           (bbdb-record (or
                         (progn (print "Trying name, company, and net:" (get-buffer-create "foo"))
                                (print (concat name-to-search-for "----" org-to-search-for "----" email-to-search-for) (get-buffer-create "foo"))
                                ;; Try to find an existing one ...
                                ;; 1. try company and net and name:
                                (car (and name-to-search-for
                                          (bbdb-search
                                           (and email-to-search-for
                                                (bbdb-search
                                                 (and org-to-search-for
                                                      (bbdb-search (bbdb-records)
                                                                   nil org-to-search-for))
                                                 nil nil email-to-search-for))
                                           name-to-search-for))))
                         (progn (print "Trying name and org:" (get-buffer-create "foo"))
                                (print (concat name-to-search-for "----" org-to-search-for) (get-buffer-create "foo"))
                                ;; 2. try company and name:
                                (car (and name-to-search-for
                                          (bbdb-search
                                           (and org-to-search-for
                                                (bbdb-search (bbdb-records)
                                                             nil org-to-search-for)))
                                          name-to-search-for)))
                         (progn (print "Trying name and email:" (get-buffer-create "foo"))
                                (print (concat name-to-search-for "----" email-to-search-for) (get-buffer-create "foo"))
                                ;; 3. try net and name; we may change company here:
                                (car (and name-to-search-for
                                          (bbdb-search
                                           (and email-to-search-for
                                                (bbdb-search (bbdb-records)
                                                             nil nil email-to-search-for))
                                           name-to-search-for))))
                         (progn (print "New Entry!!!" (get-buffer-create "foo"))
                                ;; No existing record found; make a fresh one:
                                (let ((fresh-record (make-vector bbdb-record-length nil)))
                                  (bbdb-record-set-cache fresh-record (make-vector bbdb-cache-length nil))
                                  (bbdb-invoke-hook 'bbdb-create-hook fresh-record)
                                  fresh-record))))
           (bbdb-akas (when bbdb-record (bbdb-record-aka bbdb-record)))
           (bbdb-addresses (when bbdb-record (bbdb-record-addresses bbdb-record)))
           (bbdb-phones (when bbdb-record (bbdb-record-phones bbdb-record)))
           (bbdb-nets (when bbdb-record (bbdb-record-net bbdb-record)))
           (bbdb-raw-notes (when bbdb-record (bbdb-record-raw-notes bbdb-record)))
           notes
           other-vcard-type)
      (print bbdb-record (get-buffer-create "foo"))
      (when name ; which should be the case as N is mandatory in vcard
        (bbdb-record-set-firstname bbdb-record (car name))
        (bbdb-record-set-lastname bbdb-record (cadr name)))
      (bbdb-record-set-aka bbdb-record
                           (reduce (lambda (x y) (union x y :test 'string=))
                                   (list nicknames
                                         other-names
                                         formatted-names
                                         bbdb-akas)))
      (when org (bbdb-record-set-company bbdb-record org))
      (bbdb-record-set-net bbdb-record
                           (union email bbdb-nets :test 'string=))
      (bbdb-record-set-addresses bbdb-record
                                 (union adrs bbdb-addresses :test 'equal))
      (bbdb-record-set-phones bbdb-record
                              (union tels bbdb-phones :test 'equal))
      ;; prepare bbdb's notes:
      (when url (push (cons 'www url) bbdb-raw-notes))
      (when vcard-notes
        ;; Put vcard notes under key 'notes or, if key 'notes already
        ;; exists, under key 'vcard-notes.
        (push (cons (if (assoc 'notes bbdb-raw-notes)
                        'vcard-notes
                      'notes)
                    (mapconcat (lambda (element)
                                 (cdr (assoc "value" element)))
                               vcard-notes
                               ";\n"))
              bbdb-raw-notes))
                                        ;      (print bday (get-buffer-create "foo"))
      (when bday
        (push (cons 'anniversary (concat bday " birthday"))
              bbdb-raw-notes))
      (while (setq other-vcard-type (bbdb-vcard-other-entry))
        (unless (and bbdb-vcard-skip
                     (string-match bbdb-vcard-skip
                                   (symbol-name (car other-vcard-type))))
          (push other-vcard-type bbdb-raw-notes)))
      (bbdb-record-set-raw-notes
       bbdb-record
       (remove-duplicates bbdb-raw-notes
                          :key (lambda (x) (symbol-name (car x))) :test 'equal :from-end t))
      (bbdb-change-record bbdb-record t)
      (print bbdb-record (get-buffer-create "foo")))))

(defun bbdb-vcard-convert-name (vcard-name)
  "Convert VCARD-NAME (type N) into (FIRSTNAME LASTNAME)."
  (if (stringp vcard-name)              ; unstructured N
      (bbdb-divide-name vcard-name)
    (list (concat (nth 3 vcard-name)    ; honorific prefixes
                  (when (nth 3 vcard-name) " ")
                  (nth 1 vcard-name)    ; given name
                  (when (nth 2 vcard-name) " ")
                  (nth 2 vcard-name))   ; additional names
          (concat (nth 0 vcard-name)    ; family name
                  (when (nth 4 vcard-name) " ")
                  (nth 4 raw-name)))))  ; honorific suffixes

(defun bbdb-vcard-entries-of-type (type &optional one-is-enough-p)
  "From current buffer containing a single vcard, read and delete the entries
of TYPE. If ONE-IS-ENOUGH-P is t, read and delete only the first entry of
TYPE."
  (goto-char (point-min))
  (let (values parameters read-enough)
    (while (and (not read-enough)
                (re-search-forward (concat "^\\([[:alnum:]-]*\\.\\)?\\(" type "\\)\\(;.*\\)?:\\(.*\\)
      (goto-char (match-end 2))
      (setq parameters nil)
      (push (cons "value" (bbdb-vcard-split-structured-text (match-string 4) ";")) parameters)
      (while (re-search-forward "\\([^;:=]+\\)=\\([^;:]+\\)" (line-end-position) t)
        (push (cons (downcase (match-string 1)) (downcase (match-string 2))) parameters))
      (push parameters values)
      (delete-region (line-end-position 0) (line-end-position))
      (when one-is-enough-p (setq read-enough t)))
    values))

(defun bbdb-vcard-other-entry ()
  "From current buffer containing a single vcard, read and delete the topmost
entry. Return (TYPE . ENTRY)."
  (goto-char (point-min))
  (when (re-search-forward "^\\([[:graph:]]*?\\):\\(.*\\)
    (let ((type (match-string 1))
          (value (match-string 2)))
      (delete-region (match-beginning 0) (match-end 0))
      (cons (make-symbol (downcase type)) value))))

(defun bbdb-vcard-split-structured-text (text separator &optional return-always-list-p)
  "Split TEXT at unescaped occurences of SEPARATOR; return parts in a list.
Return text unchanged if there aren't any separators and RETURN-ALWAYS-LIST-P
is nil."
  (when text
    (let ((string-elements
           (split-string
            (replace-regexp-in-string
             (concat "\\\\
             (replace-regexp-in-string separator (concat "
            (concat "
      (if (and (null return-always-list-p)
               (= 1 (length string-elements)))
          (car string-elements)
        string-elements))))

(defcustom bbdb-vcard-translation-table
  '(("Mobile" . "CELL")
    ("Mobile" . "CAR")
    ("Office" . "WORK")
    ("Office" . "WORK,PREF")
    ("Home" . "HOME")
    ("Home" . "HOME,PREF"))
  "Alist with translations of location labels for addresses and phone
numbers. Cells are (BBDB-LABEL . VCARD-LABEL). Vcard labels must be all
uppercase."
  :group 'bbdb-vcard
  :type '(alist :key-type string :value-type string))

(defun bbdb-vcard-translate (vcard-label)
  "Translate VCARD-LABEL into its bbdb counterpart as
defined in `bbdb-vcard-translation-table'."
  (upcase-initials
   (or (car (rassoc (upcase vcard-label) bbdb-vcard-translation-table))
       vcard-label)))

(provide 'bbdb-vcard)

;;; XXX.el ends here    