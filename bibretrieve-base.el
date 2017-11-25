;;; bibretrieve-base.el --- Retrieve BibTeX entries from the internet

;; Copyright (C)
;; 2012, 2015 Antonio Sartori
;; 2012, 2013, 2017 Pavel Zorin-Kranich

;; This file is part of BibRetrieve.

;; BibRetrieve is free software: you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version.

;; BibRetrieve is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with BibRetrieve.  If not, see
;; <http://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; This file contains the code that (with the exception of
;; the function bibretrieve) is not directly exposed to the user.

;; The convenience function "bibretrieve-http" takes as input a URL, queries it,
;; puts the result in a new buffer, and returns this buffer.

;;; Code:

(eval-when-compile (require 'cl))
(require 'reftex)
(require 'reftex-cite)
(require 'reftex-sel)
(require 'mm-url)
(provide 'bibretrieve)

;; Here only to silence the compilator
(defvar bibretrieve-backends)
(defvar bibretrieve-installed-backends)

(defvar bibretrieve-select-map nil
  "Keymap used for *RefTeX Select* buffer, when selecting a BibTeX entry.
This keymap can be used to configure the BibTeX selection process which is
started with the command \\[bibretrieve-get].")

;; Prompt and help string for citation selection
(defconst bibretrieve-select-prompt
  "Select: [n]ext [p]revious a[g]ain [r]efine [f]ull_entry [q]uit RET [?]Help+more")

;; Adapted from RefTeX
(defconst bibretrieve-select-help
  " n / p      Go to next/previous entry (Cursor motion works as well).
 g / r      Start over with new search / Refine with additional regexp.
 SPC        Show full database entry in other window.
 f          Toggle follow mode: Other window will follow with full db entry.
 .          Show current append point.
 q          Quit.
 TAB        Enter citation key with completion.
 RET        Accept current entry (also on mouse-2), and append it to default BibTeX file.
 m / u      Mark/Unmark the entry.
 e / E      Append all (marked/unmarked) entries to default BibTeX file.
 a / A      Put all (marked) entries into current buffer.")

(defun bibretrieve-backend-msn (author title)
  (let* ((pairs `(("bdlback" . "r=1")
		  ("dr" . "all")
		  ("l" . "20")
		  ("pg3" . "TI")
		  ("s3" . ,title)
		  ("pg4" . "ICN")
		  ("s4" . ,author)
		  ("fn" . "130")
		  ("fmt" . "bibtex")
		  ("bdlall" . "Retrieve+All")))
	 (url (concat "http://www.ams.org/mathscinet/search/publications.html?" (mm-url-encode-www-form-urlencoded pairs)))
	 (buffer (bibretrieve-http url)))
    (with-current-buffer buffer
      (goto-char (point-min))
      (while (re-search-forward "URL = {https://doi.org/" nil t)
	(replace-match "DOI = {"))
      buffer)))

(defun bibretrieve-backend-mrl (author title)
  (let* ((pairs `(("ti" . ,title)
		  ("au" . ,author)
		  ("format" . "bibtex")))
    (url (concat "http://www.ams.org/mrlookup?" (mm-url-encode-www-form-urlencoded pairs)))
	 (buffer (bibretrieve-http url)))
    (with-current-buffer buffer
      (goto-char (point-min))
      (while (re-search-forward "URL = {https://doi.org/" nil t)
	(replace-match "DOI = {"))
      buffer)))

(defun bibretrieve-matches-in-buffer (regexp &optional buffer)
  "Return a list of matches of REGEXP in BUFFER or the current buffer if not given."
  (let ((matches))
    (save-match-data
      (save-excursion
        (with-current-buffer (or buffer (current-buffer))
          (save-restriction
            (widen)
            (goto-char 1)
            (while (search-forward-regexp regexp nil t 1)
              (push (match-string 0) matches)))))
      matches)))

(defun bibretrieve-backend-zbm (author title)
  (let* ((url (concat "https://zbmath.org/?" (mm-url-encode-www-form-urlencoded `(("au" . ,author) ("ti" . ,title)))))
	 (buffer (bibretrieve-http url))
	 (list-of-bib-urls (bibretrieve-matches-in-buffer "bibtex/[a-zA-Z0-9.]*.bib" buffer))
	 bib-url)
    (with-current-buffer buffer
       (erase-buffer)
      (dolist (bib-url list-of-bib-urls)
	(bibretrieve-http (concat "https://zbmath.org/" bib-url) buffer)
	(goto-char (point-max))
	(insert "\n") ; A bibtex entry may not start on the line on which the previous entry ends
	)
      buffer)))

(defun bibretrieve-backend-arxiv (author title)
  (let* ((url (concat "http://adsabs.harvard.edu/cgi-bin/nph-abs_connect?"
	  (mm-url-encode-www-form-urlencoded `(("db_key" . "PRE")
				       ("aut_req" . "YES")
				       ("aut_logic" . "SIMPLE")
				       ("author" . ,author)
				       ("ttl_req" . "YES")
				       ("ttl_logic" . "AND")
				       ("title" . ,title)
				       ("data_type" . "BIBTEX")))))
	 (buffer (bibretrieve-http url)))
    (with-current-buffer buffer
      ;; Remove useless fields
      (goto-char (point-min))
      (while (re-search-forward "^.*adsurl =.*\n" nil t)
	(replace-match ""))
      (goto-char (point-min))
      (while (re-search-forward "^.*adsnote =.*\n" nil t)
	(replace-match ""))
      (goto-char (point-min))
      (while (re-search-forward "^.*keywords =.*\n" nil t)
	(replace-match ""))
      (goto-char (point-min))
      ; arxiv is not a journal, use misc type instead of article
      (while (re-search-forward "^.*journal.*" nil t)
	(replace-match "note = {Preprint}," 1))
      (goto-char (point-min))
      (while (re-search-forward "\"{" nil t)
	(replace-match "{"))
      (goto-char (point-min))
      (while (re-search-forward "}\"" nil t)
	(replace-match "}"))
      ; generate readable citation keys
      (goto-char (point-min))
      (while (re-search-forward "@article.*$" nil t)
	(let ((arxivid (save-match-data
			 (save-excursion
			   (re-search-forward "eprint = {\\([a-zA-Z\\.-]*/\\)?\\([0-9\\.]+\\)}" nil t)
			   (match-string 2)
			   ))))
	  (message arxivid)
	  (replace-match (concat "@misc{arxiv:" arxivid ",") 1)))
;; Add archive prefix to old style identifiers
      (goto-char (point-min))
      (while (re-search-forward "^.*eprint = {math/" nil t)
	(replace-match "archivePrefix = \"arXiv\",\neprint = {math/"))
      buffer)))

;; Modified from bibsnarf
(defun bibretrieve-backend-citebase (author title)
  (let* ((query (concat author " " title))
	 (pairs `(("submitted" . "Search")
		  ("query" . ,query)
		  ("format" . "BibTeX")
		  ("maxrows" . "100")
		  ("order" . "DESC")
		  ("rank" . "1000") ; in what order should we list?
		  )))
    (bibretrieve-http (concat "http://www.citebase.org/search?" (mm-url-encode-www-form-urlencoded pairs)))))

(defun bibretrieve-backend-inspire (author title)
  (let* ((pairs `(("ln" . "en")
		  ("as" . "1")
		  ("m1" . "a")
		  ("op1" . "a")
		  ("m2" . "a")
		  ("op2" . "a")
		  ("m3" . "a")
		  ("action_search" . "Search")
		  ("sf" . "year")
		  ("so" . "d")
		  ("sc" . "0")
		  ("p1" . ,author)
		  ("f1" . "author")
		  ("p2" . ,title)
		  ("f2" . "title")
		  ("of" . "hx")
		  ("rg" . "100"))))
  (bibretrieve-http (concat "http://inspirehep.net/search?" (mm-url-encode-www-form-urlencoded pairs)))))

(defun bibretrieve-generate-new-buffer ()
  "Generate and return a new buffer with a bibretrieve-specific name."
  (generate-new-buffer (generate-new-buffer-name "bibretrieve-results-")))

(defun bibretrieve-http (url &optional buffer)
  "Retrieve URL and return the buffer, using mm-url."
  (unless buffer (setq buffer (bibretrieve-generate-new-buffer)))
  (with-current-buffer buffer
    (message "Retrieving %s" url)
    (mm-url-insert-file-contents url))
  buffer)

(defun bibretrieve-retrieve-backend (author title backend timeout)
  "Call the backend BACKEND with AUTHOR, TITLE and TIMEOUT. Return buffer with results."
  (let* ((function-backend (intern (concat "bibretrieve-backend-" backend))))
    (if (functionp function-backend)
	(with-timeout (timeout) (funcall function-backend author title))
      (message (concat "Backend " backend " is not defined.")))))
      
(defun bibretrieve-retrieve (author title backends &optional newtimeout)
  "Search AUTHOR and TITLE on BACKENDS.
If NEWTIMEOUT is given, this replaces the timeout for all backends.
Returns list of buffers with results."
  (let (buffers)
    (dolist (backend backends)
      (let* ((timeout (or (or newtimeout (cdr (assoc backend bibretrieve-backends))) "0"))
	     (buffer (bibretrieve-retrieve-backend author title backend timeout)))
	(if (bufferp buffer)
	    (add-to-list 'buffers buffer)
	  (message (concat "Backend " backend " failed.")))))
    buffers))

(defun bibretrieve-prompt-and-retrieve (&optional arg)
  "Prompt for author and title and retrieve.
If the optional argument ARG is an integer
then it is used as the timeout (in seconds).
If the optional argument ARG is non-nil and not integer,
prompt for the backends to use and the timeout."
  (let* ((author (read-string "Author: "))
	 (title (read-string "Title: "))
	 backend backends timeout)
    (when arg
      (if (integerp arg)
	  (setq timeout arg)
	(progn (setq backend (completing-read "Backend to use: [defaults] " (append bibretrieve-installed-backends '("DEFAULTS" "ALL")) nil t nil nil "DEFAULTS"))
	       (setq timeout (read-string "Timeout (seconds): [5] " nil nil "5")))))
    (setq backends
	  (cond ((or (not backend) (equal backend "DEFAULTS"))
		 (mapcar 'car bibretrieve-backends))
		((equal backend "ALL")
		 'bibretrieve-installed-backends)
		(t
		 `(,backend))))
    (bibretrieve-retrieve author title backends timeout))
  )

(defun bibretrieve-find-bibliography-file ()
  "Try to find a bibliography file using RefTeX."
  ;; Returns a string with text properties (as expected by read-file-name)
  ;; or empty string if no file can be found
  (let ((bibretrieve-bibfile-list nil))
    (condition-case nil
	(setq bibretrieve-bibfile-list (reftex-get-bibfile-list))
      (error (ignore-errors
	       (setq bibretrieve-bibfile-list (reftex-default-bibliography))))
      )
    (if bibretrieve-bibfile-list
	(car bibretrieve-bibfile-list) "")
    )
  )

(defun bibretrieve-find-default-bibliography-file ()
   "Find a default bibliography file to write entries in.
Try with a \bibliography in the current buffer
or if the current buffer is a bib buffer,
else return nil."
  (or (bibretrieve-find-bibliography-file)
      (if buffer-file-name
	  (and (string-match ".*\\.bib$" buffer-file-name)
	       (buffer-file-name)))))

;; Copied from RefTeX
;; Limit FOUND-LIST with more regular expressions
;; Returns a string with all matching bibliography items
(defun bibretrieve-extract-bib-items (all &optional marked complement)
    (setq all (delq nil
                    (mapcar
                     (lambda (x)
                       (if marked
                           (if (or (and (assoc x marked) (not complement))
                                   (and (not (assoc x marked)) complement))
                               (cdr (assoc "&entry" x))
                             nil)
                         (cdr (assoc "&entry" x))))
                     all)))
    (mapconcat 'identity all "\n\n")
    )

(defun bibretrieve-write-bib-items-bibliography (all bibfile marked complement)
  "Append item to file.

From ALL, append to a promped file (BIBFILE is the default one) MARKED entries (or unmarked, if COMPLEMENT is t)."
  (let ((file (read-file-name (if bibfile (concat "Bibfile: [" bibfile "] ") "Bibfile: ") default-directory bibfile)))
    (if (find-file-other-window file)
	(save-excursion
	  (goto-char (point-max))
	  (insert "\n")
	  (insert (bibretrieve-extract-bib-items all marked complement))
	  (insert "\n")
	  (save-buffer)
	  file
	  )
      (error "Invalid file"))))

;; Callback function to be called from the bibliography selection, in
;; order to display context.
(defun bibretrieve-selection-callback (data ignore no-revisit)
  (let ((win (selected-window))
;        (key (reftex-get-bib-field "&key" data))
;        bibfile-list item bibtype)
	(origin (buffer-name)))
    (pop-to-buffer "*BibRetrieve Record*")
    (setq buffer-read-only nil)
    (erase-buffer)
    (bibtex-mode)
    (goto-char (point-min))
    (insert (reftex-get-bib-field "&entry" data))
    ;;    (shrink-window-if-larger-than-buffer)  ; FIXME: this needs to be recalibrated for each record
    (goto-char (point-min))
    (setq buffer-read-only t)
    (pop-to-buffer origin)
    )
  )


;; Modified version of reftex-extract-bib-entries
;; It does not ask for a REGEXP, but it selects all
(defun bibretrieve-extract-bib-entries (buffers)
  "Extract bib entries which match regexps from BUFFERS.
BUFFERS is a list of buffers or file names.
Return list with entries.\""
  (let* (        (buffer-list (if (listp buffers) buffers (list buffers)))
                 found-list entry buffer1 buffer alist
                 key-point start-point end-point default)

    (save-excursion
      (save-window-excursion

        ;; Walk through all bibtex files
        (while buffer-list
          (setq buffer (car buffer-list)
                buffer-list (cdr buffer-list))
          (if (and (bufferp buffer)
                   (buffer-live-p buffer))
              (setq buffer1 buffer)
            (setq buffer1 (reftex-get-file-buffer-force
                           buffer (not reftex-keep-temporary-buffers))))
          (if (not buffer1)
              (message "No such BibTeX file %s (ignored)" buffer)
            (message "Scanning bibliography database %s" buffer1)
	    (unless (verify-visited-file-modtime buffer1)
		 (when (y-or-n-p
			(format "File %s changed on disk.  Reread from disk? "
				(file-name-nondirectory
				 (buffer-file-name buffer1))))
		   (with-current-buffer buffer1 (revert-buffer t t)))))

          (set-buffer buffer1)
          (reftex-with-special-syntax-for-bib
           (save-excursion
             (goto-char (point-min))
             (while (re-search-forward "=" nil t)
               (catch 'search-again
                 (setq key-point (point))
                 (unless (re-search-backward "\\(\\`\\|[\n\r]\\)[ \t]*\
@\\(\\(?:\\w\\|\\s_\\)+\\)[ \t\n\r]*[{(]" nil t)
                   (throw 'search-again nil))
                 (setq start-point (point))
                 (goto-char (match-end 0))
                 (condition-case nil
                     (up-list 1)
                   (error (goto-char key-point)
                          (throw 'search-again nil)))
                 (setq end-point (point))

                 ;; Ignore @string, @comment and @c entries or things
                 ;; outside entries
                 (when (or (string= (downcase (match-string 2)) "string")
                           (string= (downcase (match-string 2)) "comment")
                           (string= (downcase (match-string 2)) "c")
                           (< (point) key-point)) ; this means match not in {}
                   (goto-char key-point)
                   (throw 'search-again nil))

                 ;; Well, we have got a match
                 ;;(setq entry (concat
                 ;;             (buffer-substring start-point (point)) "\n"))
                 (setq entry (buffer-substring start-point (point)))

                 (setq alist (reftex-parse-bibtex-entry
                              nil start-point end-point))
                 (push (cons "&entry" entry) alist)

                 ;; check for crossref entries
                 (if (assoc "crossref" alist)
                     (setq alist
                           (append
                            alist (reftex-get-crossref-alist alist))))

                 ;; format the entry
                 (push (cons "&formatted" (reftex-format-bib-entry alist))
                       alist)

                 ;; make key the first element
                 (push (reftex-get-bib-field "&key" alist) alist)

                 ;; add it to the list
                 (push alist found-list)))))
          (reftex-kill-temporary-buffers))))
    (setq found-list (nreverse found-list))

    ;; Sorting
    (cond
     ((eq 'author reftex-sort-bibtex-matches)
      (sort found-list 'reftex-bib-sort-author))
     ((eq 'year   reftex-sort-bibtex-matches)
      (sort found-list 'reftex-bib-sort-year))
     ((eq 'reverse-year reftex-sort-bibtex-matches)
      (sort found-list 'reftex-bib-sort-year-reverse))
     (t found-list))))


;; Modified version of reftex-offer-bib-menu
(defun bibretrieve-offer-bib-menu (&optional arg)
  "Offer bib menu and return list of selected items.
ARG is the optional argument."

  (let ((bibfile (bibretrieve-find-default-bibliography-file))
        found-list rtn key data selected-entries)
    (while
        (not
         (catch 'done
           ;; Retrieve and scan entries
	   (let ((buffers (bibretrieve-prompt-and-retrieve arg)) buffer-list buffer)
	     (setq found-list (bibretrieve-extract-bib-entries buffers))
	     (setq buffer-list (if (listp buffers) buffers (list buffers)))
	     (while buffer-list
	       (setq buffer (car buffer-list)
		     buffer-list (cdr buffer-list))
	       (kill-buffer buffer)
	       )
	     )

           (unless found-list
             (error "Sorry, no matches found"))

          ;; Remember where we came from
          (setq reftex-call-back-to-this-buffer (current-buffer))
          (set-marker reftex-select-return-marker (point))

          ;; Offer selection
          (save-window-excursion
            (delete-other-windows)
            (let ((major-mode 'reftex-select-bib-mode))
              (reftex-kill-buffer "*RefTeX Select*")
              (switch-to-buffer-other-window "*RefTeX Select*")
              (unless (eq major-mode 'reftex-select-bib-mode)
                (reftex-select-bib-mode))
              (let ((buffer-read-only nil))
                (erase-buffer)
                (reftex-insert-bib-matches found-list)))
            (setq buffer-read-only t)
            (if (= 0 (buffer-size))
                (error "No matches found"))
            (setq truncate-lines t)
            (goto-char 1)
            (while t
              (setq rtn
                    (reftex-select-item
                     bibretrieve-select-prompt
                     bibretrieve-select-help
                     reftex-select-bib-mode-map
                     nil
                     'bibretrieve-selection-callback nil))
              (setq key (car rtn)
                    data (nth 1 rtn))
              (unless key (throw 'done t))
              (cond
               ((eq key ?g)
                ;; Start over
                (throw 'done nil))
               ((eq key ?r)
                ;; Restrict with new regular expression
                (setq found-list (reftex-restrict-bib-matches found-list))
                (let ((buffer-read-only nil))
                  (erase-buffer)
                  (reftex-insert-bib-matches found-list))
                (goto-char 1))
               ((eq key ?A)
                ;; Take all
                (setq selected-entries found-list)
                (throw 'done t))
               ((eq key ?a)
                ;; Take all marked
		;; If nothing is marked, then mark current selection
		(if (not reftex-select-marked)
		    (reftex-select-mark))
                (setq selected-entries (mapcar 'car (nreverse reftex-select-marked)))
                (throw 'done t))
               ((eq key ?e)
                ;; Take all marked and append them
                (let ((file (bibretrieve-write-bib-items-bibliography found-list bibfile reftex-select-marked nil)))
		  (when file
		    (setq selected-entries
			  (concat "BibTeX entries appended to " file))
		    (throw 'done t)))
		(message "File not found, nothing done"))
               ((eq key ?E)
                ;; Take all unmarked and append them
                (let ((file (bibretrieve-write-bib-items-bibliography found-list bibfile reftex-select-marked 'complement)))
		  (when file
		    (setq selected-entries
			  (concat "BibTeX entries appended to " file))
		    (throw 'done t)))
		(message "File not found, nothing done"))
               ((or (eq key ?\C-m)
                    (eq key 'return))
                ;; Take selected
		;; If nothing is marked, then mark current selection
		(let ((marked reftex-select-marked))
		    (unless marked (reftex-select-mark))
		    (let ((file (bibretrieve-write-bib-items-bibliography found-list bibfile reftex-select-marked nil)))
		      (when file
			(setq selected-entries (concat "BibTeX entries appended to " file))
			(throw 'done t)))
		    (unless marked (reftex-select-unmark)))
		(message "File not found, nothing done. Press q to exit."))
               ((stringp key)
                ;; Got this one with completion
                (setq selected-entries key)
                (throw 'done t))
               (t
                (ding))))))))
    selected-entries))




;; Get records from the web and insert them in the bibliography

;; Adapted from RefTeX
;;;###autoload
(defun bibretrieve ()
  "Search the web for bibliography entries.

After prompting for author and title, searches on the web, using the
backends specified by the customization variable
`bibretrieve-backends'.  A selection process (using RefTeX Selection)
allows to select entries to add to the current buffer or to a
bibliography file.

 When called with a `C-u' prefix, permits to select the backend and the
 timeout for the search."

  (interactive)

  ;; check for recursive edit
  (reftex-check-recursive-edit)

  ;; This function may also be called outside reftex-mode.
  ;; Thus look for the scanning info only if in reftex-mode.

  (when reftex-mode
    (reftex-access-scan-info nil))

  ;; Call bibretrieve-do-retrieve, but protected
  (unwind-protect
      (bibretrieve-do-retrieve current-prefix-arg)
    (progn
      (reftex-kill-temporary-buffers)
      (reftex-kill-buffer "*BibRetrieve Record*")
      (reftex-kill-buffer "*RefTeX Select*"))))

;; Adapted from RefTeX
(defun bibretrieve-do-retrieve (&optional arg)
  "This really does the work of bibretrieve.
ARG is the optional argument."

  (let ((selected-entries (bibretrieve-offer-bib-menu arg)))

    (set-marker reftex-select-return-marker nil)

    ;; (when (stringp selected-entries)
    ;;   (message selected-entries))
    ;; (unless selected-entries (message "Quit"))
 
    ;; (insert (bibretrieve-extract-bib-items selected-entries))
    ;; (message "fin qui ok")

    (if (stringp selected-entries)
      (message selected-entries)
      (if (not selected-entries)
	  (message "Quit")
 	(insert (bibretrieve-extract-bib-items selected-entries))
	)
      )
    ))

    ;; Return the citation key
;;    (mapcar 'car selected-entries)))

(provide 'bibretrieve-base)

;;; bibretrieve-base.el ends here
