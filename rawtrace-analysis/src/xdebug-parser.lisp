#|
Author: Simon Koch <s9sikoch@stud.uni-saarland.de>
This file contains the code to parse xdebug trace files with 
trace_format = 1. 
It also provides the means to extract all fopen calls of the
given trace and returns all parameters passed to those calls.
|#
(in-package :de.uni-saarland.syssec.analyzer.xdebug)


(defun get-xdebug-trace-file (folder-files)
  (let ((rel-files (remove-if-not #'(lambda (file-path)
				      (cl-ppcre:scan ".*/xdebug.xt" file-path))
				  folder-files)))
    (when (> (length rel-files) 1)
      (warn "more than one possible trace file detected - select lexicographical first"))
    (when (= (length rel-files) 0)
      (error "no xdebug trace detected!"))
    (car rel-files)))
	  

(defclass xdebug-trace ()
  ((trace-content
    :initarg :trace-content
    :reader trace-content)))


(defclass record ()
  ((level
    :initarg :level
    :reader level)
   (function-nr
    :initarg :function-nr
    :reader function-nr)))
   

(defclass entry-record (record)
  ((time-index
    :initarg :time-index
    :reader time-index)
   (memory-usage
    :initarg :memory-usage
    :reader memory-usage)
   (function-name
    :initarg :function-name
    :reader function-name)
   (user-defined-p
    :initarg :user-defined-p
    :reader user-defined-p)
   (name-of-ir-file
    :initarg :name-of-ir-file
    :reader name-of-ir-file)
   (filename 
    :initarg :filename
    :reader filename)
   (line-number
    :initarg :line-number
    :reader line-number)
   (parameters
    :initarg :parameters
    :reader parameters)))


(defmethod print-object ((record entry-record) stream)
  (FORMAT stream "~a    ~a    ~{~a~^,~}"
          (level record)
          (function-name record)
          (parameters record)))


(defclass exit-record (record)
  ((time-index
    :initarg :time-index
    :reader time-index)
   (memory-usage
    :initarg :memory-usage
    :reader memory-usage)))


(defclass return-record (record)
  ((return-value
    :initarg :return-value
    :reader return-value)))


(defun make-entry-records (entries)
  (destructuring-bind (level function-nr always time-index memory-usage function-name user-defined-p name-of-ir-file filename line-number param-count &rest params)
      entries
    (declare (ignore always param-count))
    (make-instance 'entry-record
		   :level (parse-integer level)
		   :function-nr function-nr 
		   :time-index time-index
		   :memory-usage memory-usage
		   :function-name function-name
		   :user-defined-p user-defined-p
		   :name-of-ir-file name-of-ir-file
		   :filename filename
		   :line-number line-number
		   :parameters params)))


(defun make-exit-records (entries)
  (destructuring-bind (level function-nr always time-index memory-usage)
      entries
    (declare (ignore always))
    (make-instance 'exit-record
		   :level level 
		   :function-nr function-nr 
		   :time-index time-index
		   :memory-usage memory-usage)))


(defun make-return-records (entries)
  (destructuring-bind (level function-nr always e1 e2 return-value)
      entries
    (declare (ignore always e1 e2))
    (make-instance 'return-record
		   :level level
		   :function-nr function-nr
		   :return-value return-value)))


(defun parse-xdebug-trace-line (line)
  (if (not line)
      nil
      (destructuring-bind (level function-nr always &rest rest)
	  (cl-ppcre:split "\\t" line)
	(cond
	  ((and (string= "" level)
		(string= "" function-nr)
		(string= "" always))
	   nil)
	  ((string= "0" always)
	   (make-entry-records (append (list level function-nr always) rest)))
	  ((string= "1" always)
	   (make-exit-records (append (list level function-nr always) rest)))
	  ((string= "R" always)
	   (make-return-records (append (list level function-nr always) rest)))
	  (T
	   (error 'simple-error 
		  :format-control "there aint no such thing as ~a as the always record part in ~a"
		  :format-arguments (list always line)))))))
       
#|
(defun parse-xdebug-trace (string)
  (if string 
      (let ((stream (make-string-input-stream string)))
	(parse-xdebug-trace-helper stream))
      (FORMAT T "WARNING: NO XDEBUG DUMP FUND - CONTINUING ANYWAYS!~%")))
|#

(defun parse-xdebug-trace (stream)
  (progn 
    (read-line stream nil nil) ;the first three
    (read-line stream nil nil) ;lines are really
    (read-line stream nil nil) ;not needed
    (do ((line (read-line stream nil nil)
               (read-line stream nil nil))
         (records nil)
         (stop-p nil))
        (stop-p (reverse records))
      (handler-case
          (let ((last (parse-xdebug-trace-line line)))
            (if last 
                (push last records)
                (setf stop-p T)))
        (error (e)
          (FORMAT T "ERROR WHILE PARSING XDEBUG~% LINE: ~a~% ERROR:~%~a~%" line e))))))
        
	  



(defun numeric-string-p (string)
  (let ((*read-eval* nil))
    (ignore-errors (numberp (read-from-string string)))))


(defun valid-always (string)
  (or (string= string "1")
      (string= string "0")
      (string= string "R")))


(defun remove-bad-newlines (xdebug-istream xdebug-ostream)
  (FORMAT xdebug-ostream "~a~%" (read-line xdebug-istream nil nil))
  (FORMAT xdebug-ostream "~a~%" (read-line xdebug-istream nil nil))
  (FORMAT xdebug-ostream "~a~%" (read-line xdebug-istream nil nil))
  (do ((line (read-line xdebug-istream nil nil)
             (read-line xdebug-istream nil nil))
       (fixing t))
      ((not line) nil)
    (if (not fixing)
        (FORMAT xdebug-ostream "~a~%"line)
        (let ((split-line (cl-ppcre:split "\\t" line)))
          (if (>= (length split-line) 3)
              (if (and (string= (car split-line) "")
                       (string= (cadr split-line) "")
                       (string= (caddr split-line) ""))
                  (progn 
                    (setf fixing nil)
                    (FORMAT xdebug-ostream "~%~a~%" line))
                  (if (and (numeric-string-p (car split-line))
                           (numeric-string-p (cadr split-line))
                           (valid-always (caddr split-line)))
                      (FORMAT xdebug-ostream "~&~a" line)
                      (FORMAT xdebug-ostream "~a" line)))
              (FORMAT xdebug-ostream "~a" line))))))




(defun make-xdebug-trace (stream)
  (cl-fad:with-open-temporary-file (iostream :direction :io)
    (remove-bad-newlines stream iostream)
    (force-output iostream)
    (file-position iostream 0)
    (make-instance 'xdebug-trace
                   :trace-content (parse-xdebug-trace iostream))))


(defun make-xdebug-trace-from-file (file-path)
  (with-open-file (stream file-path :external-format :latin1)
    (make-xdebug-trace stream)))



(defmethod get-changed-files-paths ((xdebug-trace xdebug-trace))
  (mapcar #'(lambda(fopen-call)
	      (cl-ppcre:regex-replace-all "'" (car (parameters fopen-call)) ""))
	  (remove-if-not #'(lambda (record)
			     (and (typep record 'entry-record)
				  (string= (function-name record) "fopen")))
			 (trace-content xdebug-trace))))


(defun remove-non-state-changing-queries(query-list)
  (remove-if #'(lambda(query)
                 (or 
                  (cl-ppcre:scan "SELECT" query)
                  (cl-ppcre:scan "select" query)))
             query-list))


(defun query-cleaner (query-string)
  (cl-ppcre:regex-replace-all " [ ]+"
                              (cl-ppcre:regex-replace-all "\\\\t|\\\\n|\\" 
                                                          query-string
                                                          " ") 
                              " "))


(defmethod get-all-pdo-calls ((xdebug-trace xdebug-trace))
  (remove-if-not #'(lambda (record)
                     (and (typep record 'entry-record)
                          (or (string= (function-name record) "PDO->prepare")
                              (string= (function-name record) "PDOStatement->bindValue")
                              (string= (function-name record) "PDOStatement->execute"))))
                 (trace-content xdebug-trace)))


(defmacro while (condition &body body)
  (let ((it (gensym)))
    `(do ((,it ,condition
               ,condition))
         ((not ,it) nil)
       ,@body)))


(defun extract-argument (execute-parameter)
  (cl-ppcre:regex-replace "[ 0-9]+ => "
                          execute-parameter
                          ""))

(defun array->parameterlist (execute-parameter-array)
  (if execute-parameter-array
      (let ((array-content-bracketed
             (cl-ppcre:regex-replace-all "array "
                                         execute-parameter-array
                                         "")))
        (cl-ppcre:split ","
                        (subseq array-content-bracketed
                                1
                                (- (length array-content-bracketed) 1))))
      nil))
                    

(defun pdo-function-calls->query-string (records)
  (assert (string= (function-name (car records)) "PDO->prepare")
          ((car records)) "first pdo records has to be a preparation call")
  (assert (string= (function-name (car (last records))) "PDOStatement->execute")
          ((car (last records))) "last pdo record has to be an execution call")
  (let ((prep-string (car (parameters (car records)))))
    (dolist (item (subseq records 1 (- (length records) 1)))
      (setf prep-string
            (cl-ppcre:regex-replace-all (car (parameters item))
                                        prep-string
                                        (cadr (parameters item)))))
    (dolist (item (array->parameterlist (car (parameters (car (last records))))))
      (setf prep-string
            (cl-ppcre:regex-replace "\\?"
                                    prep-string
                                    (extract-argument item))))
    prep-string))


(defmethod get-pdo-prepared-queries ((xdebug-trace xdebug-trace))
  (let ((pdo-records (get-all-pdo-calls xdebug-trace))
        (queries nil))
    (labels ((get-preparation-set (start-record remaining-traces)
               (if remaining-traces
                   (if (= (level (car remaining-traces))
                          (level start-record))
                       (cond 
                         ((string= (function-name (car remaining-traces)) "PDOStatement->bindValue")
                          (multiple-value-bind (list remaining)
                              (get-preparation-set start-record (cdr remaining-traces))
                            (when (not list)
                              (error "list of PDO must not be empty"))
                            (values (cons (car remaining-traces)
                                          list)
                                    remaining)))
                         ((string= (function-name (car remaining-traces)) "PDOStatement->execute")
                          (values (cons (car remaining-traces) nil)
                                  (cdr remaining-traces)))
                         (t
                          (error (FORMAT nil "unexpected trace element ~a" (car remaining-traces)))))
                       (get-preparation-set start-record (cdr remaining-traces)))
                   (values nil nil)))
             (get-next-pdo-start (remaining-traces)
               (if remaining-traces
                   (if (string= (function-name (car remaining-traces)) "PDO->prepare")
                       (values (car remaining-traces)
                               (cdr remaining-traces)))
                   nil)))
      (while pdo-records
        (multiple-value-bind (start-record remaining-records)
            (get-next-pdo-start pdo-records)
          (multiple-value-bind (records remaining-records)
              (get-preparation-set start-record remaining-records)
            (FORMAT T "START:~a~% REST:~a~%" start-record records)
            (push (pdo-function-calls->query-string (cons start-record
                                                          records))
                  queries)
            (setf pdo-records remaining-records)))))
    queries))


(defmethod get-regular-sql-queries ((xdebug-trace xdebug-trace))
  (mapcar #'(lambda(mysqli-call)
              (query-cleaner (car (parameters mysqli-call))))
          (remove-if-not #'(lambda (record)
                             (and (typep record 'entry-record)
                                  (or (string= (function-name record) "mysqli->query")
                                      (string= (function-name record) "PDO->query")
                                      (string= (function-name record) "mysql_query"))))
                          (trace-content xdebug-trace))))


(defmethod get-sql-queries ((xdebug-trace xdebug-trace) keep-all-queries-p)
  (let ((queries (append
                  (get-pdo-prepared-queries xdebug-trace)
                  (get-regular-sql-queries xdebug-trace))))
    (if (not keep-all-queries-p)
        (remove-non-state-changing-queries queries)
        queries)))
    

