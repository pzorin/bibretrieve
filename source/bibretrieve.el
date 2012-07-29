;;; bibretrieve.el --- Retrieving BibTeX entries from the web

;; Copyright (C) 2012

;; Author: Antonio Sartori <anto_sart -at- yahoo -dot- it>
;; Version: 0.1
;; Time-stamp: <2012-03-17 13:04:24 asartori>

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
;; This program searches the web for BibTeX entries matching the given
;; Author end/or Title.  It displays then a selection buffer, that permits
;; to examine and choose entries to add to the bibliography file, or to
;; insert into the current buffer.

;; The function is called through "M-x bibretrieve".  Then it prompts for
;; author and title.  For an advanced use, that permits to select which
;; backend to use, call it with "C-u M-x bibretrieve".

;; The configuration is done with the variable bibretrieve-backends, that
;; is an alist with pairs containing the backend to use and the timeout
;; for it.

;; The url is retrieved via mm-url.  You may want to customize the
;; variable mm-url-use-external and mm-url-program.

;; Supported backends are at the moment
;; ArXiv:              "http://adsabs.harvard.edu"
;; MathSciNet (msn):   "http://www.ams.org/mathscinet"
;; MrLookup (mrl):     "http://www.ams.org/mrlookup"
;; Citebase:           "http://www.citebase.org"
;; Inspire:            "http://inspirehep.net"

;; To create a new backend, it is enough to define a new function
;; "bibretrieve-BACKEND-create-url" that takes as input author and title
;; and returns a url that, when retrieved, gives some bibtex entries.  It
;; is then necessary to advise bibretrieve of the new backend, adding it
;; to the list "bibretrieve-installed-backends".

;; Acknowledgments: This program has been inspired by bibsnarf.  The
;; functions that create the urls for most backends are taken from
;; there.  This program uses the library mm-url.  This programs also uses
;; lot of function of RefTeX.  The selection process is entirely based on
;; reftex-sel.  Many function have also been adapted from there.

;;; Code:

(eval-when-compile (require 'cl))

(defconst bibretrieve-version "0.1"
  "Version string for BibRetrieve.")

(defgroup bibretrieve nil
  "BibRetrieve: Retrieve bibliography entries from the internet."
  :group 'tools)

(defvar bibretrieve-installed-backends '("msn" "mrl" "arxiv" "citebase" "inspire" "zbm")
  "List of installed backends for BibRetrieve.")

(defcustom bibretrieve-backends '(("msn" . 10) ("arxiv" . 5) ("citebase" . 5))
  "Backends customization variable for BibRetrieve.

Backends to use for the search, together with a timeout
for the research on every backend.
Timeout should be an integer number of seconds."
  :type '(alist :key-type string :value-type integer)
  :options bibretrieve-installed-backends
  :group 'bibretrieve)

(define-key-after
  (lookup-key (current-global-map) [menu-bar tools])
  [sep] '(menu-item "--"))
(define-key-after
  (lookup-key (current-global-map) [menu-bar tools])
  [bibretrieve] '("BibRetrieve" . bibretrieve))

(autoload 'bibretrieve "bibretrieve-base"
    " Search the web for bibliography entries.  After prompting for
 author and title, searches on the web, using the backends specified by
 the customization variable `bibretrieve-backends'. A selection process
 (using RefTeX Selection) allows to select entries to add to the
 current buffer or to a bibliography file.

 When called with a `C-u' prefix, permits to select the backend and the
 timeout for the search."
 t nil)

(provide 'bibretrieve)

;;; bibretrieve.el ends here
