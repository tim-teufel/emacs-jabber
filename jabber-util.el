;; jabber-util.el - various utility functions

;; Copyright (C) 2002, 2003, 2004 - tom berger - object@intelectronica.net
;; Copyright (C) 2003, 2004 - Magnus Henoch - mange@freemail.hu

;; This file is a part of jabber.el.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; if not, write to the Free Software
;; Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

(defvar jabber-jid-history nil
  "History of entered JIDs")

(defvar *jabber-sound-playing* nil
  "is a sound playing right now?")

(cond
 ((fboundp 'replace-in-string)
  (defsubst jabber-replace-in-string (str regexp newtext)
    (replace-in-string str regexp newtext t)))
 ((fboundp 'replace-regexp-in-string)
  (defsubst jabber-replace-in-string (str regexp newtext)
    (replace-regexp-in-string regexp newtext str t t))))

;;; XEmacs compatibility.  Stolen from ibuffer.el
(if (fboundp 'propertize)
    (defalias 'jabber-propertize 'propertize)
  (defun jabber-propertize (string &rest properties)
    "Return a copy of STRING with text properties added.

 [Note: this docstring has been copied from the Emacs 21 version]

First argument is the string to copy.
Remaining arguments form a sequence of PROPERTY VALUE pairs for text
properties to add to the result."
    (let ((str (copy-sequence string)))
      (add-text-properties 0 (length str)
			   properties
			   str)
      str)))

(unless (fboundp 'bound-and-true-p)
  (defmacro bound-and-true-p (var)
    "Return the value of symbol VAR if it is bound, else nil."
    `(and (boundp (quote ,var)) ,var)))

;;; more XEmacs compatibility
;;; Preserve input method when entering a minibuffer
(if (featurep 'xemacs)
    ;; I don't know how to do this
    (defsubst jabber-read-with-input-method (prompt &optional initial-contents history default-value)
      (read-string prompt initial-contents history default-value))
  (defsubst jabber-read-with-input-method (prompt &optional initial-contents history default-value)
    (read-string prompt initial-contents history default-value t)))

(unless (fboundp 'delete-and-extract-region)
  (defsubst delete-and-extract-region (start end)
    (prog1
	(buffer-substring start end)
      (delete-region start end))))

(unless (fboundp 'access-file)
  (defsubst access-file (filename error-message)
    (unless (file-readable-p filename)
      (error error-message))))

(defun jabber-jid-username (string)
  "return the username portion of a JID"
  (string-match "\\(.*\\)@.*\\(/.*\\)?" string)
  (match-string 1 string))

(defun jabber-jid-user (string)
  "return the user (username@server) portion of a JID"
  ;;transports don't have @, so don't require it
  ;;(string-match ".*@[^/]*" string)
  (string-match "[^/]*" string)
  (match-string 0 string))

(defun jabber-jid-displayname (string)
  "return the name of the user, if given in roster, else username@server"
  (let ((user (jabber-jid-symbol string)))
    (let ((roster-item (car (memq user *jabber-roster*))))
      (if (and roster-item
	       (> (length (get roster-item 'name)) 0))
	  (get roster-item 'name)
	(symbol-name user)))))

(defun jabber-jid-resource (string)
  "return the resource portion of a JID"
  (string-match "\\(.*@.*\\)/\\(.*\\)" string)
  (match-string 2 string))

(defun jabber-jid-symbol (string)
  "return the symbol for the given JID"
  (intern (downcase (jabber-jid-user string)) jabber-jid-obarray))

(defun jabber-my-jid-p (jid)
  "Return non-nil if the specified JID is equal to the user's JID, modulo resource."
  (equal (jabber-jid-user jid)
	 (concat jabber-username "@" jabber-server)))

(defun jabber-read-jid-completing (prompt)
  "read a jid out of the current roster from the minibuffer."
  (let ((jid-at-point (or (get-text-property (point) 'jabber-jid)
			  (bound-and-true-p jabber-chatting-with)
			  (bound-and-true-p jabber-group)))
	(completion-ignore-case t)
	(jid-completion-table (mapcar #'(lambda (item)
					  (cons (symbol-name item) item))
				      *jabber-roster*)))
    (dolist (item *jabber-roster*)
      (if (get item 'name)
	  (push (cons (get item 'name) item) jid-completion-table)))
    (let ((input
	   (completing-read (concat prompt
				    (if jid-at-point
					(format "(default %s) " jid-at-point)))
			    jid-completion-table
			    nil nil nil 'jabber-jid-history jid-at-point)))
      (if (and input (assoc-ignore-case input jid-completion-table))
	  (symbol-name (cdr (assoc-ignore-case input jid-completion-table)))
	input))))

(defun jabber-read-node (prompt)
  "Read node name, taking default from disco item at point."
  (let ((node-at-point (get-text-property (point) 'jabber-node)))
    (read-string (concat prompt
			 (if node-at-point
			     (format "(default %s) " node-at-point)))
		 node-at-point)))

(defun jabber-read-passwd ()
  "Read Jabber password, either from customized variable or from minibuffer.
See `jabber-password'."
  (or jabber-password (read-passwd "Jabber password: ")))

(defun jabber-iq-query (xml-data)
  "Return the query part of an IQ stanza.
An IQ stanza may have zero or one query child, and zero or one <error/> child.
The query child is often but not always <query/>."
  (let (query)
    (dolist (x (jabber-xml-node-children xml-data))
      (if (and
	   (listp x)
	   (not (eq (jabber-xml-node-name x) 'error)))
	  (setq query x)))
    query))

(defun jabber-iq-error (xml-data)
  "Return the <error/> part of an IQ stanza, if any."
  (car (jabber-xml-get-children xml-data 'error)))

(defun jabber-iq-xmlns (xml-data)
  "Return the namespace of an IQ stanza, i.e. the namespace of its query part."
  (jabber-xml-get-attribute (jabber-iq-query xml-data) 'xmlns))

(defun jabber-x-delay (xml-data)
  "Return timestamp given a <x/> tag in namespace jabber:x:delay.
Return nil if no such data available."
  (when (and (eq (jabber-xml-node-name xml-data) 'x)
	     (string= (jabber-xml-get-attribute xml-data 'xmlns) "jabber:x:delay"))
    (let ((stamp (jabber-xml-get-attribute xml-data 'stamp)))
      (if (and (stringp stamp)
	       (= (length stamp) 17))
	  (jabber-parse-legacy-time stamp)))))
      
(defun jabber-parse-legacy-time (timestamp)
  "Parse timestamp in ccyymmddThh:mm:ss format (UTC) and return as internal time value."
  (let ((year (string-to-number (substring timestamp 0 4)))
	(month (string-to-number (substring timestamp 4 6)))
	(day (string-to-number (substring timestamp 6 8)))
	(hour (string-to-number (substring timestamp 9 11)))
	(minute (string-to-number (substring timestamp 12 14)))
	(second (string-to-number (substring timestamp 15 17))))
    (encode-time second minute hour day month year 0)))

(defun jabber-encode-time (time)
  "Convert TIME to a string by JEP-0082.  TIME is a list of integers."
  (let ((time-zone-offset (nth 0 (current-time-zone))))
    (if (null time-zone-offset)
	;; no time zone information available; pretend it's UTC
	(format-time-string "%Y-%m-%dT%H:%M:%SZ" time)
      (let* ((positivep (>= time-zone-offset 0))
	     (hours (/ (abs time-zone-offset) 3600))
	     (minutes (/ (% (abs time-zone-offset) 3600) 60)))
	(format "%s%s%02d:%02d" (format-time-string "%Y-%m-%dT%H:%M:%S" time)
		(if positivep "+" "-") hours minutes)))))

(defun jabber-report-success (xml-data context)
  "IQ callback reporting success or failure of the operation.
CONTEXT is a string describing the action."
  (let ((type (jabber-xml-get-attribute xml-data 'type)))
    (message (concat context
		     (if (string= type "result")
			 " succeeded"
		       (concat
			" failed: "
			(jabber-parse-error (jabber-iq-error xml-data))))))))

(defconst jabber-error-messages
  (list
   (cons 'bad-request "Bad request")
   (cons 'conflict "Conflict")
   (cons 'feature-not-implemented "Feature not implemented")
   (cons 'forbidden "Forbidden")
   (cons 'gone "Gone")
   (cons 'internal-server-error "Internal server error")
   (cons 'item-not-found "Item not found")
   (cons 'jid-malformed "JID malformed")
   (cons 'not-acceptable "Not acceptable")
   (cons 'not-allowed "Not allowed")
   (cons 'not-authorized "Not authorized")
   (cons 'payment-required "Payment required")
   (cons 'recipient-unavailable "Recipient unavailable")
   (cons 'redirect "Redirect")
   (cons 'registration-required "Registration required")
   (cons 'remote-server-not-found "Remote server not found")
   (cons 'remote-server-timeout "Remote server timeout")
   (cons 'resource-constraint "Resource constraint")
   (cons 'service-unavailable "Service unavailable")
   (cons 'subscription-required "Subscription required")
   (cons 'undefined-condition "Undefined condition")
   (cons 'unexpected-request "Unexpected request"))
  "String descriptions of XMPP stanza errors")

(defconst jabber-legacy-error-messages
  (list
   (cons 302 "Redirect")
   (cons 400 "Bad request")
   (cons 401 "Unauthorized")
   (cons 402 "Payment required")
   (cons 403 "Forbidden")
   (cons 404 "Not found")
   (cons 405 "Not allowed")
   (cons 406 "Not acceptable")
   (cons 407 "Registration required")
   (cons 408 "Request timeout")
   (cons 409 "Conflict")
   (cons 500 "Internal server error")
   (cons 501 "Not implemented")
   (cons 502 "Remote server error")
   (cons 503 "Service unavailable")
   (cons 504 "Remote server timeout")
   (cons 510 "Disconnected"))
  "String descriptions of legacy errors (JEP-0086)")
  
(defun jabber-parse-error (error-xml)
  "Parse the given <error/> tag and return a string fit for human consumption.
See secton 9.3, Stanza Errors, of XMPP Core, and JEP-0086, Legacy Errors."
  (let ((error-type (jabber-xml-get-attribute error-xml 'type))
	(error-code (jabber-xml-get-attribute error-xml 'code))
	condition text)
    (if error-type
	;; If the <error/> tag has a type element, it is new-school.
	(dolist (child (jabber-xml-node-children error-xml))
	  (when (string=
		 (jabber-xml-get-attribute child 'xmlns)
		 "urn:ietf:params:xml:ns:xmpp-stanzas")
	    (if (eq (jabber-xml-node-name child) 'text)
		(setq text (car (jabber-xml-node-children child)))
	      (setq condition
		    (or (cdr (assq (jabber-xml-node-name child) jabber-error-messages))
			(symbol-name (jabber-xml-node-name child)))))))
      (setq condition (or (cdr (assq (string-to-number error-code) jabber-legacy-error-messages))
			  error-code))
      (setq text (car (jabber-xml-node-children error-xml))))
    (concat condition
	    (if text (format ": %s" text)))))

(put 'jabber-error
     'error-conditions
     '(error jabber-error))
(put 'jabber-error
     'error-message
     "Jabber error")

(defun jabber-signal-error (error-type condition &optional text app-specific)
  "Signal an error to be sent by Jabber.
ERROR-TYPE is one of \"cancel\", \"continue\", \"modify\", \"auth\"
and \"wait\".
CONDITION is a symbol denoting a defined XMPP condition.
TEXT is a string to be sent in the error message, or nil for no text.
APP-SPECIFIC is a list of extra XML tags.

See section 9.3 of XMPP Core."
  (signal 'jabber-error
	  (list error-type condition text app-specific)))

(defun jabber-play-sound-file (soundfile)
  (if (not *jabber-sound-playing*)
      (progn
	(setq *jabber-sound-playing* t)
	(run-with-idle-timer 0.01 nil 
			     #'(lambda (sf)
			       (condition-case nil
				   ;; play-sound-file might display "Could not set sample rate" in
				   ;; echo area.  Don't let this erase the previous message.
				   (let ((old-message (current-message)))
				     (play-sound-file sf)
				     (setq *jabber-sound-playing* nil)
				     (message "%s" old-message))
				 (error (setq *jabber-sound-playing* nil))))
			     soundfile))))

(provide 'jabber-util)

;;; arch-tag: cfbb73ac-e2d7-4652-a08d-dc789bcded8a
