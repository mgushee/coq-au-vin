;;; coq-au-vin.scm -- A simple blogging platform based on Chicken Scheme.
;;;
;;;   Copyright © 2013 by Matthew C. Gushee <matt@gushee.net>
;;;   This program is open-source software, released under the
;;;   BSD license. See the accompanying LICENSE file for details.

;(load "./cav-db.so")
;(require-library cav-db)

(module coq-au-vin
        *
        (import scheme chicken)
        (import files)
        (import ports)
        (import data-structures)
        (import extras)
        (import posix)
        (import srfi-1)
        ; (import srfi-13)

        (use (prefix cav-db db:))
        (use (prefix civet cvt:))
  
        (use lowdown)
        (use srfi-69)
        ; (use crypt)
        ; ;; FIXME: Need a better password hash! 
        (use simple-sha1)

        ; (use spiffy)
        ; (use intarweb)
        ; (use uri-match)

        (use utf8)
        (use utf8-srfi-13)
        (use utf8-srfi-14)


;;; IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
;;; ----  GLOBAL PARAMETERS  -----------------------------------------------

(define %blog-root% (make-parameter #f))

; (define %default-teaser-length% (make-parameter 1024))
; Should be defined in words
(define %default-teaser-length% (make-parameter 64))

(define %config% (make-parameter (make-hash-table)))

(define %session-timeout% (make-parameter 900))

(define %default-date-format% (make-parameter #f))

(define %object-log% (make-parameter #f))

         ;;; TEMPORARY!
(define bogus-vars
  (make-parameter
    `((urlScheme . "http") (hostName . "quahog") (bodyMD . "") (jquerySrc . "/scripts/jquery.js")
      (canEdit . #t) (copyright_year . 2013) (copyright_holders . "Madeleine C St Clair")
      (rights_statement . "You have no rights") (htmlTitle . "Civet Page!") (bodyClasses . ""))))

(define (get-bogus-vars #!optional (id/alias #f))
  (let ((bogus (bogus-vars)))
    (if id/alias
      `((articleID . ,id/alias) ,@bogus)
      bogus)))

;;; OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO



;;; IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
;;; ----  UTILITY FUNCTIONS  -----------------------------------------------

(define (eprintf fmt . args)
  (error (apply sprintf (cons fmt args))))
 
(define (strip-html str)
  (let* ((in-tag #f)
         (enter-tag
           (lambda ()
             (if in-tag
               (set! in-tag (+ in-tag 1))
               (set! in-tag 1))))
         (leave-tag
           (lambda ()
             (cond
               ((not in-tag) #f)
               ((= in-tag 1) (set! in-tag #f))
               (else (set! in-tag (- in-tag 1)))))))
    (with-output-to-string
      (lambda ()
        (with-input-from-string
          str
          (lambda ()
            (let loop ((c (read-char)))
              (cond
                ((eof-object? c)
                 #f)
                ((char=? c #\<)
                 (enter-tag)
                 (loop (read-char)))
                ((char=? c #\>)
                 (leave-tag)
                 (loop (read-char)))
                (in-tag
                  (loop (read-char)))
                (else
                  (write-char c)
                  (loop (read-char)))))))))))

(define (escape-html str)
  (with-output-to-string
    (lambda ()
      (with-input-from-string
        str
        (lambda ()
          (let loop ((c (read-char)))
            (cond
              ((eof-object? c)
               #f)
              ((char=? c #\<)
               (display "&lt;")
               (loop (read-char)))
              ((char=? c #\>)
               (display "&gt;")
               (loop (read-char)))
              (else
                (write-char c)
                (loop (read-char))))))))))

(define (string->bool s)
  (let ((s (string-downcase s)))
    (cond
      ((string=? s "true") #t)
      ((string=? s "false") #t)
      (eprintf "'~A' does not represent a boolean value.\n"))))

; This is not absolutely foolproof, but I think it's close enough
(define (node-id? s)
  (and (= (string-length s) 8)
       (string->number (string-append "#x" s))))

(define (words str n)
  (if (< n 1)
    '()
    (with-input-from-string str
      (lambda ()
        (let ((return-result
                (lambda (current-word words-out)
                  (reverse
                    (if (null? current-word)
                      words-out
                      (cons
                        (list->string (reverse current-word))
                        words-out))))))
          (let loop ((state 'init) (count 1) (chr (read-char)) (current-word '()) (words-out '()))
            (cond
              ((eof-object? chr)
               (return-result current-word words-out))
              ((char-set-contains? char-set:whitespace chr)
               (case state
                 ((init)
                  (loop 'init count (read-char) '() '()))
                 ((word)
                  (if (>= count n)
                    (return-result current-word words-out)
                    (loop 'space count (read-char) '() (cons (list->string (reverse current-word)) words-out))))
                 ((space)
                  (loop 'space count (read-char) '() words-out))))
              (else
                (case state
                  ((init)
                   (loop 'word count (read-char) (cons chr current-word) '()))
                  ((word)
                   (loop 'word count (read-char) (cons chr current-word) words-out))
                  ((space)
                   (loop 'word (+ count 1) (read-char) (list chr) words-out)))))))))))

(define (text->teaser txt #!optional (length #f))
  (let ((wds (words txt (or length (%default-teaser-length%)))))
    (string-append (string-join wds " ") " ...")))

(define (title->alias title)
  (with-output-to-string
    (lambda ()
      (with-input-from-string title
        (lambda ()
          (let loop ((chr (read-char)))
            (cond
              ((eof-object? chr) #t)
              ((char-set-contains? char-set:whitespace chr)
               (write-char #\-)
               (loop (read-char)))
              ((char-set-contains? char-set:punctuation chr)
               (loop (read-char)))
              (else
                (write-char (char-downcase chr))
                (loop (read-char))))))))))

(define (config-set! . vars)
  (let ((cfg-data (%config%)))
    (for-each
      (lambda (elt)
        (let ((k (car elt)) (v (cdr elt))) (hash-table-set! cfg-data k v)))
      vars)))

(define (config-get . vars)
  (let ((cfg-data (%config%)))
    (foldl
      (lambda (prev key)
        (if (hash-table-exists? cfg-data key)
          `((,key . ,(hash-table-ref cfg-data key)) ,@prev)
          prev))
      '()
      vars)))

(define (config key . vals)
  (let ((cfg-data (%config%)))
    (if (null? vals)
      (hash-table-ref cfg-data key)
      (hash-table-set! cfg-data key (car vals)))))

(define (config*)
  (hash-table->alist (%config%)))

;;; OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO



;;; IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
;;; ----  RUNTIME CONFIGURATION  -------------------------------------------

(define (read-config-blog-data cfg params)
  (let loop ((params params))
    (if (null? params)
      cfg
      (let* ((param (car params))
             (key (car param))
             (val (cdr param)))
        (case key
          ((raw-html)
           (hash-table-set! cfg key (string->symbol val)))
          ((max-post-length max-comment-length teaser-length)
           (hash-table-set! cfg key (string->number val)))
          (else #f))
        (loop (cdr params))))))

(define (read-config-blog-interface cfg params)
  (let loop ((params params))
    (if (null? params)
      cfg
      (let* ((param (car params))
             (key (car param))
             (val (cdr param)))
        (case key
          ((use-javascipt inline-editing)
           (hash-table-set! cfg key (string->bool val)))
          (else #f))
        (loop (cdr params))))))

(define (read-config-blog-appearance cfg params)
  (let loop ((params params))
    (if (null? params)
      cfg
      (let* ((param (car params))
             (key (car param))
             (val (cdr param)))
        (case key
          ((layout theme)
           (hash-table-set! cfg key val))
          (else #f))
        (loop (cdr params))))))

(define (read-config-blog cfg params)
  (let loop ((params params))
    (if (null? params)
      cfg
      (let* ((param (car params))
             (key (car param))
             (val* (cdr param))
             (process-value
               (case key
                 ((name home db engine) identity)
                 ((data) (lambda (v) (read-config-blog-data (make-hash-table) v)))
                 ((interface) (lambda (v) (read-config-blog-interface (make-hash-table) v)))
                 ((appearance) (lambda (v) (read-config-blog-appearance (make-hash-table) v)))
                 (else (lambda (_) '%INVALID%))))
             (val (process-value val*)))
        (unless (eqv? val '%INVALID%)
          (hash-table-set! cfg key val))
        (loop (cdr params))))))

(define (read-config file)
  (let ((config (%config%)))
    #f))

;;; OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO



;;; IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
;;; ----  USERS, SESSIONS, AUTHENTICATION  ---------------------------------

; (define (register-user uname password email role #!optional (disp-name '()))
;   (let ((phash (string->sha1sum password)))
;     (unless (member role '("editor" "author" "member"))
;       (error (string-append "'" role "' is not a recognized role.")))
;     (call-with-database
;       (make-pathname (make-pathname (%blog-root%) "data") "example.db")
;       (lambda (conn)
;         ((db:current-connection) conn)
;         ((db:add-user) uname phash email role disp-name))))) 

; (define (login uname password)
;   (call-with-database
;     (make-pathname (make-pathname (%blog-root%) "data") "example.db")
;     (lambda (conn)
;       ((db:current-connection) conn)
;       (if ((db:can-login?) uname)
;         (let ((phash (string->sha1sum password)))
;           (if (string=? phash ((db:get-passhash) uname))
;             ;;; FIXME: obviously bogus code here!
;             #t
;             #f))))))

;;; OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO

;;; ========================================================================
;;; ------------------------------------------------------------------------

(define (default-teaser article-body)
  (let ((alen (string-length article-body))
        (tlen (%default-teaser-length%)))
    (if (< tlen alen)
      (substring article-body 0 tlen)
      article-body)))

(define (get-template tpl-name #!optional (content-type 'text/html))
  (let* ((file-ext
           (case content-type
             ((text/html) "html")
             ((application/json) "json")
             (else (eprintf "[get-template] Unknown content type: ~A" content-type))))
         (tpl-path
          (make-pathname
            (make-pathname (%blog-root%) "templates")
            tpl-name file-ext)))
    (if (file-exists? tpl-path)
      tpl-path
      (eprintf "[get-template] Template file '~A' not found." tpl-path))))

; These procedures are probably needed, but currently they use the sql-de-lite
; API directly, so the DB functionality needs to be abstracted.

; (define (teaser article-id)
;   (or (get-teaser article-id)
;       (default-teaser (get-body article-id))))
; 
; (define (latest #!optional (n 10))
;   (for-each
;     (lambda (id) (teaser id))
;     (index-ref 'post-order 10)))

; (define (init blog-root)
;   (%blog-root% blog-root)
;   (call-with-database
;     (make-pathname (make-pathname blog-root "data") "example.db")
;     (lambda (conn)
;       ((db:current-connection) conn)
;       (for-each
;         db:add-role
;         '("admin" "editor" "author" "member" "guest")))))

;;; OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO



;;; IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
;;; --  WEB INTERFACE  -----------------------------------------------------

(define (get-article-data id/alias)
  (if (node-id? id/alias)
    ((db:get-article-by-nodeid) id/alias)
    ((db:get-article-by-alias) id/alias)))

(define (get-article-list-data #!key (tag #f) (author #f) (series #f)
                               (limit 10) (offset 0) (teaser-len #f))
  #f)
  
(define (process-body article-data)
  (let* ((content (alist-ref 'content article-data))
         (raw-body (or (alist-ref 'body content) (alist-ref 'teaser content)))
         (sanitized-body (escape-html raw-body)))
;     (with-output-to-string
;       (lambda () (markdown->html sanitized-body)))))
    (markdown->sxml sanitized-body)))

(define (prepare-article-vars article-data date-format)
  (foldl
    (lambda (prev pair)
      (let ((key (car pair))
            (val (cdr pair)))
        (case key
          ((authors)
           (cons (cons 'authors val) prev))
          ((created_dt)
           (let* ((fmt (or date-format (%default-date-format%)))
                  (dtstring (time->string (seconds->local-time val) fmt)))
             (cons
               (cons 'created_dt dtstring)
               (cons
                 (cons 'raw_dt val)
                 prev))))
          ((title)
           (cons (cons 'article_title val) prev))
          ((content)
           (cons (cons 'text (process-body article-data)) prev))
          (else
            (let ((res (if (null? val) (cons key "") pair)))
              (cons res prev))))))
    '()
    article-data))

(define (get-article/html id/alias #!optional (out (current-output-port)))
  (let* ((article-data (get-article-data id/alias))
         (html-body (process-body article-data)))
    (display html-body out)))

(define (get-article/json id/alias #!optional (out (current-output-port)))
  #f)

(define (get-article-page/html id/alias #!key (out (current-output-port))
                               (date-format #f))
  (let* ((article-data (get-article-data id/alias))
         ; (html-body (process-body article-data))
         (vars* (prepare-article-vars article-data date-format))
         (page-vars
           (config-get
             'urlScheme 'hostName 'bodyMD 'jquerySrc 'canEdit 'copyright_year
             'copyright_holders 'rights_statement 'htmlTitle 'bodyClasses))
         (vars `((articleID . ,id/alias) ,@page-vars ,@vars*))
         (ctx (cvt:make-context vars: vars)))
    (cvt:render "article.html" ctx port: out)))

(define (get-article-list-page/html #!key (out (current-output-port))
                                    (criterion 'all) (sort '(created desc))
                                    (date-format #f) (limit 10) (offset 0)
                                    (show 'teaser))
  (let ((mkteaser
          (case show
            ((teaser) text->teaser)
            ((all) identity)
            (else (lambda (_) "")))))
    (let-values (((count list-data)
                  ((db:get-article-list) criterion limit offset mkteaser)))
      (let* ((list-vars
               (map
                 (lambda (datum) (prepare-article-vars datum date-format))
                 list-data))
             (page-vars
               (config-get
                 'urlScheme 'hostName 'bodyMD 'jquerySrc 'canEdit 'copyright_year
                 'copyright_holders 'rights_statement 'htmlTitle 'bodyClasses))
             (vars `((articles ,@list-vars) ,@page-vars))
             (ctx (cvt:make-context vars: vars)))
        (cvt:render "article-list.html" ctx port: out)))))

(define (get-articles-by-date/html date #!key (out (current-output-port))
                                   (sort '(created desc)) (limit 10)
                                   (offset 0) (show 'teaser))
  #f)

(define (get-meta-list-page/html subject #!optional (out (current-output-port)))
  (let* ((list-data ((db:get-meta-list subject)))
         (page-vars
           (config-get
             'urlScheme 'hostName 'bodyMD 'jquerySrc 'canEdit 'copyright_year
             'copyright_holders 'rights_statement 'htmlTitle 'bodyClasses))
         (vars `((subject . ,(symbol->string subject)) (metadata_items . ,list-data) ,@page-vars))
         (ctx (cvt:make-context vars: vars)))
    (cvt:render "meta-list.html" ctx port: out)))

(define (get-article-list/json #!optional (out (current-output-port))
                               #!key (filters 'latest) (sort '(created desc))
                               (per-page 10) (show 'teaser))
  #f)

(define (setup #!key (db-file #f) (open-connection #f) (content-path #f)
               (site-path #f) (template-path #f))
  (when db-file
    (db:db-file db-file))
  (when open-connection
    (db:current-connection (open-connection)))
  (when content-path
    (db:content-path content-path))
  (when site-path
    (cvt:*site-path* site-path))
  (when template-path
    (cvt:*template-path* template-path)))

;; This is temporary!
; (define (init)
;   (activate-sqlite)
;   (db:dbfile "examples/demo-site1/data/preloaded.db")
;   (db:current-connection (open-database "examples/demo-site1/data/preloaded.db"))
;   (db:content-path "examples/demo-site1/data/content")
;   (cvt:*site-path* "examples/demo-site1/dynamic"))
; 
; (define (shut-it)
;   (close-database (db:current-connection)))

;;; OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO

) ; END MODULE


;;; IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
;;; ------------------------------------------------------------------------

;;; OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO

;;; ========================================================================
;;; ------------------------------------------------------------------------

; vim:et:ai:ts=2 sw=2
