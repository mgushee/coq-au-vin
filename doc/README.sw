== coq-au-vin

=== Description

Coq au Vin is a lightweight blogging platform.

[[toc:]]

=== Authors

Matt Gushee <matt@gushee.net>

=== Requirements

[[utf8]], [[uri-common]], [[sql-de-lite]], [[civet]], [[lowdown]], [[crypt]],
    [[random-bsd]], [[intarweb]], [[matchable]], [[fastcgi]]

=== Introduction

{{Coq au Vin}} is a blogging engine designed to provide typical blog features (and a
few atypical ones) in a straightforward, easily installed package. It is intended
for users who have basic web development skills (i.e. HTML, CSS, JavaScript) and
a hosting environment that permits installing arbitrary software (VPS or the like).

It uses [[civet]] to generate dynamic pages, and has an abstract database layer that
allows for different databases to be used. There is currently a SQLite3 backend 
included in this egg. Additional databases will be supported in separate eggs.

Blog posts are processed as Markdown, using the [[lowdown]] egg.

The current version supports request handing via FastCGI. Future versions will also
support [[spiffy]]. All secured content must be accessed via HTTPS, though this
constraint may be disabled for testing purposes.

For more detailed information, you may wish to look at the
[[https://github.com/mgushee/coq-au-vin-examples|examples collection]], which 
includes several toy examples and one real web application.

Also, general info, tutorials, and announcements will be posted at the
[[http://coq-au-vin.sapparicms.org/|Coq au Vin blog]], which of course is
powered by {{Coq au Vin}}.

Expect bugs.


=== Scheme API

Please note that this document does not cover all symbols exported by the egg. However,
those that are not documented should be considered experimental and [more] likely to
change.

==== Initialization & Configuration

<procedure>(app-init #!key (site-path #f) (template-path #f))</procedure>

Initialize the application. The SITE-PATH and TEMPLATE-PATH arguments are
passed to [[civet]], and you must specify one of the two. If SITE-PATH is
specified, {{civet}} will find templates in the '''templates''' subdirectory
of that path. The value of either SITE-PATH or TEMPLATE-PATH should be an
absolute pathname.


<procedure>(register-roles #!optional (roles (%default-roles%)))</procedure>

Since each user has a role, you must call this procedure before creating any
users. The ROLES argument, if supplied, should be a list of strings; the
default value is {{'("admin" "editor" "author" "member" "guest")}}.

NOTE: as of version 0.1, these roles have no effect, but one or more roles
must be defined in order to register users.


<procedure>(config-set! (KEY . VALUE) ...)</procedure>

Set multiple variables. Each argument must be a dotted pair where KEY is
a symbol and VALUE is a string or a number.


<procedure>(config-get KEY ...)</procedure>

Retrieve multiple variables. Returns an alist. Any undefined variables are
omitted from the result.


<procedure>(config KEY [VALUE])</procedure>

Sets or retrieves one variable.


<procedure>(config*)</procedure>

Returns an alist of all defined variables.


==== Content API

===== Common Parameters

Many of the procedures below take the following parameters:

* {{ID/ALIAS}}  The identifier for a blog post. ID is a system-generated value; ALIAS is an
    optional string that may be specified by the user to allow for "friendly" URLs [not yet
    implemented as of version 0.3].

* {{OUT}}  An output port, defaulting to {{(current-output-port)}}. If you change this,
    expect problems.

* {{LOGGED-IN}}  A boolean indicating whether the user is logged in or not. Note that this
    parameter is ''not'' used to grant or deny access to secured resources; it is intended as
    a convenient way to determine whether to display certain page items related to the user's
    logged-in status (e.g. a "LOGIN" or "LOGOUT" link).


<procedure>(get-article-page/html ID/ALIAS #!key (out (current-output-port)) (date-format #f)
                                                 (logged-in #f))</procedure>

Generate an HTML page that displays the full text of one article.


<procedure>(get-article-list-page/html #!key (out (current-output-port)) (criterion 'all)
                                             (sort '(created desc)) (date-format #f) (limit 10)
                                             (offset 0) (show 'teaser) (logged-in #f))</procedure>

Generate an HTML page displaying a list of articles. The list may be filtered using the
CRITERION argument; currently supported values are {{'all}}, {{'(tag TAG)}}, {{'(author AUTHOR)}},
{{'(series SERIES-TITLE)}}, {{'(category CATEGORY)}}. As of version 0.3, the SHOW and SORT arguments
are unimplemented.


<procedure>(get-meta-list-page/html SUBJECT #!optional (out (current-output-port)) (logged-in #f))</procedure>

Generate an HTML page listing all items of a particular type. SUBJECT must be one of {{'tags}},
{{'categories}}, {{'series}}, or {{'authors}}.


<procedure>(get-new-article-form/html #!optional (out (current-output-port)))</procedure>

Generate an HTML form for creating a new article.


<procedure>(get-article-edit-form/html ID/ALIAS #!optional (out (current-output-port)))</procedure>

Generate an HTML form for editing an existing article.


<procedure>(add-article FORM-DATA #!optional (out (current-output-port)))</procedure>

Given FORM-DATA (as an alist), this procedure adds a new article to the database.


<procedure>(update-article ID/ALIAS FORM-DATA #!optional (out (current-output-port)))</procedure>

Given an ID/ALIAS for an existing article and FORM-DATA (as an alist), this procedure
updates the content and metadata of the specified article.


==== Authentication & Sessions

<procedure>(get-login-form/html #!optional (out (current-output-port)))</procedure> 

Generate an HTML form for user login.


<procedure>(webform-login FORM-DATA IP #!optional (out (current-output-port)))</procedure>

Handler for user login via the HTML form. When the username and password are accepted,
sets a session cookie in the browser.


<procedure>(unauthorized-message/html REFERER #!optional (out (current-output-port)))</procedure>

Generates a message informing the user that the action they attempted was unauthorized.


==== SQLite3 Backend

This database layer uses a SQLite3 database only to store metadata. The body text of
articles is stored in the filesystem. This reduces the load on the database and allows
the content to be placed under version control (though this egg does not yet provide
version control functionality).


<procedure>(setup-db DB-FILE #!optional (force #f))</procedure>

Opens DB-FILE and sets up all tables for the application.


<procedure>(enable-sqlite DB-FILE CONTENT-PATH)</procedure>

Configures the database layer to use the procedures in this egg. DB-FILE is the Sqlite3
database file, which should be the same file as specified in {{setup-db}}. CONTENT-PATH
is a directory where article content files will be stored.


==== FastCGI Interface

<procedure>(run LISTEN-PORT #!optional (testing #f))</procedure>

Runs the FastCGI server on LISTEN-PORT, which may be either a TCP port (integer) or a
unix socket (string). See the [[fastcgi]] documentation for more information. The TESTING
parameter disables the HTTPS-only requirement for secured resources. 

=== In case of bugs

If you have a GitHub account, please use the 
[[https://github.com/mgushee/coq-au-vin/issues|GitHub issue tracker]] -- likewise
for any technical questions or suggestions you may have (other than how-to
type questions). If you are unable to do this, the chicken-users mailing
list will also work.


=== License

Copyright (c) 2013-2014, Matthew C. Gushee
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:


    Redistributions of source code must retain the above copyright notice,
    this list of conditions and the following disclaimer.

    Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in the
    documentation and/or other materials provided with the distribution.
    
    Neither the name of the author nor the names of its contributors may be
    used to endorse or promote products derived from this software without
    specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.


=== Repo

[[https://github.com/mgushee/coq-au-vin]]


=== Version History

;0.3.2:     Fixed 'logged-in' function; removed IP address checking for
            session-valid?; added JSON combo menu handler.
 
;0.3:       Integrated FastCGI support; modified HTTP response generation to use
            [[intarweb]]; improved security by enforcing strict TLS and making
            session cookies 'Secure' and 'HttpOnly'.

;0.2.3:     Fixed bug that prevented series title from being updated.

;0.2.2:     Removed a debugging command that caused errors.

;0.2.1:     Added missing dependency.

;0.2:       Added user login and session support.

;0.1.3:     Switched password hashing to (crypt).

;0.1.2:     Fixed formatting bug in article teasers.

;0.1.1:     Added normalize-sxml procedure to work around bad href attributes in body text.

;0.1:       Initial release.
