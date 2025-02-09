;; manager.lisp

(in-package #:codegrader)

;; The percentage of correct answers a student's solutions must achieve before
;; their simplicity score is taken into account.

(defstruct submission
  std-name
  date
  evaluation ; percentage marks per question and explanations
  total-marks ; total marks, i.e., (sum correctness marks per question)/(Number of questions) 
  simplicity
  rank
  points)

(defun check-input-files (lf)
  (when lf
    (if (probe-file (car lf))
	(check-input-files (cdr lf))
	(error "Folder/file ~S does not exist." (car lf)))))

(defun clean-symbol-names (e)
  (cond ((symbolp e) (intern (symbol-name e)) )
        ((consp e) (cons (clean-symbol-names (car e))  (clean-symbol-names (cdr e))))
        (t e)))

(defun generate-messages (out eval)
  (format out "--EVALUATION FEEDBACK--~%~%NOTE:~%- Each question is worth 100 points.~%- Your score is the sum of your questions' points divided by the number of questions in the assessment.~%END OF NOTE.~%~%")
  (format out "Your score: ~a (out of 100)~%" (car eval))
  (dolist (question (cadr eval))
    (let* ((q (car question))
           (qeval (cadr question))
           (mark (first qeval))
           (error-type (second qeval))
	   (descr (third qeval))
	   (res (clean-symbol-names (fourth qeval))))
      (format out "~%---------------------------------------------------------------------------~%* ~a: ~a points (out of 100).~%" q mark)
      (cond ((or (equalp error-type "no-submitted-file")
		 (equalp error-type "not-lisp-file")
		 (equal error-type "late-submission")) (format out "~%~%~A" res))
            ((and (listp error-type) (equal (car error-type) 'used-forbidden-function))
             (format out "~%!!! Used forbidden function ~A !!!~%" (cadr error-type))
             (format out "~%Solution mark reduced by ~a% for using forbidden function.~%" (* (caddr error-type) 100))
             (format out "~%Unit test results:~%~{- ~s~%~}" res))
	    ((equal error-type "No RT-error") (format out "~%Unit test results:~%~{- ~s~%~}" res))
	    (t (format out "~%~A~%Unit test results:~%~{- ~s~%~}" descr res))))))

(defun generate-std-feedback (key eval feedback-folder)
  (let* ((fname (concatenate 'string (subseq key 0 (1- (length key))) ".txt"))
	 (folder (ensure-directories-exist (concatenate 'string  (namestring feedback-folder) fname))))
    (with-open-file (out folder :direction :output :if-exists :supersede)
      (generate-messages out eval))))


(defun get-std-name (csv)
  (let* ((pref1 (subseq csv (1+ (position #\, csv))))
	 (pref2 (subseq pref1 (1+ (position #\, pref1))))
	 (lname (subseq pref1 0 (position #\, pref1)))
	 (fname (subseq pref2 0 (position #\, pref2))))
    (concatenate 'string fname " " lname)))

(defun change-mark-csv (csv mark)
  (let* ((pref1 (subseq csv 0 (position #\, csv :from-end 0)))
	 (pref2 (subseq pref1 0 (position #\, pref1 :from-end 0))))
    (concatenate 'string pref2 "," (write-to-string mark) ",#")))

(defun get-insert-grade (log-file-stream stream csv ht f)
  (let* ((std-name (get-std-name csv))
	 (v (gethash std-name ht)))
    (if v
        (let ((new-mark (change-mark-csv csv (funcall f v))))
          (format log-file-stream "Mark of student ~a changed from ~a to ==> ~a~%" std-name csv new-mark)
          (format stream "~A~%"  new-mark))
	(progn 
          (format log-file-stream "~S did not submit solution!~%" std-name)
          (format *standard-output* "~A~%" std-name)))))

(defun generate-marks-spreadsheet (log-file-stream d2l-file folder ht f out-file)
  (when d2l-file
    (with-open-file (in d2l-file :direction :input)
      (with-open-file (out (merge-pathnames folder out-file)
			   :direction :output :if-exists :supersede)
        (format out "~A~%" (read-line in nil))
        (format *standard-output* "Students that did not submit solution are listed below:~%")
        (loop for line = (read-line in nil)
	      while line do
	        (get-insert-grade log-file-stream out line ht f))))))

(defun check-input-files (lf)
  (when lf
    (if (probe-file (car lf))
	(check-input-files (cdr lf))
	(error "Folder/file ~S does not exist." (car lf)))))

(defun cleanup-folder (folder)
  (if  (probe-file folder)
       (sb-ext:delete-directory folder :recursive t)))

(defun replace-char (s c r)
  (setf (aref s (position c s)) r)
  s)

(defun consume-until (s c)
  (subseq s (1+ (position c s))))

(defun check-foldername (p)
  "Adds a / to the end of the folder name if it is not there already"
  (if (char= (aref p (1- (length p))) #\/)
      p
      (concatenate 'string p "/")))

#|
(defun rank-perf-solutions (ht-perf ht-stds &optional (pts (list 25 18 15 12 10 8 6 4 2 1)) (perf (list)))
  (labels ((set-rank (list i pts)
             (when list
               (let ((item (car list)))
                 (setf (submission-rank item) i)
                 (setf (submission-points item) (car pts))
                 (setf (gethash (submission-std-name item) ht-stds) item)
                 (set-rank (cdr list) (1+ i) (cdr pts))))))
    (maphash (lambda (k v)
               (push v perf))
             ht-perf)
    (set-rank (sort perf '< :key #'submission-simplicity) 1 pts)))

(defun generate-kalos-kagathos-file (root-folder table)
  (with-open-file (test-stream (merge-pathnames root-folder "correctness-and-simplicity.csv") :direction :output :if-exists :supersede)
    (maphash (lambda (key value)
               (format test-stream "~a, ~a, ~a, ~a, ~a~%" key (car (submission-correctness value)) (submission-simplicity value) (submission-rank value) (submission-points value)))
             table)))
|#

(defun create-folder-ifzipped (is-zipped submissions-dir unzipped-subs-folder)
  (if is-zipped
      (progn
        (ensure-directories-exist unzipped-subs-folder :verbose T)
	(zip:unzip submissions-dir unzipped-subs-folder :if-exists :supersede)
	unzipped-subs-folder)
      (check-foldername submissions-dir)))

(defun get-date-time()
  (let ((day-names '("Monday" "Tuesday" "Wednesday" "Thursday" "Friday" "Saturday" "Sunday")))
    (multiple-value-bind
          (second minute hour date month year day-of-week dst-p tz)
	(get-decoded-time)
      dst-p
      (format nil "It is now ~2,'0d:~2,'0d:~2,'0d of ~a, ~d/~2,'0d/~d (GMT~@d)"
	      hour
	      minute
	      second
	      (nth day-of-week day-names)
	      month
	      date
	      year
	      (- tz)))))

(defun get-key-and-date (folder)
  (let* ((s (namestring folder))
	 (sn (subseq s 0 (- (length s) 1)))
	 (pre (splice-at-char sn #\/)))
    (multiple-value-bind (date p2) (splice-at-char pre #\-)
	(values (subseq pre 0 p2) (subseq date 1)))))

(defun splice-at-char (s c)
  (let ((i (position c s :from-end 0)))
    (values (subseq (subseq s i) 1) i)))

(defun form-date-time (date)
  (with-input-from-string (in date)
    (let ((month (read in))
	  (day (prog1 (read in)
		 (read in)))
	  (time (read in))
	  (period (read in)))
      (list month day time period))))

(defun check-dt (dt)
  (let ((m (car dt))
	(d (cadr dt))
	(td (if (<= (caddr dt) 12) (* (caddr dt) 100) (caddr dt)))
	(p (cadddr dt)))
    (list m d td p)))

(defun chng-to-string (a)
  (if (null a) nil
      (cons (symbol-name (car a)) (chng-to-string (cdr a)))))

(defun capitalize-string (s)
  (dotimes (i (length s) s)
    (when (and (char>= (aref s i) #\a)
             (char<= (aref s i) #\z))
      (setf (aref s i) (char-upcase (aref s i))))))

(defun capitalize-list (a &optional acc)
  (if (null a) acc
      (capitalize-list (cdr a) (cons (capitalize-string (car a)) acc))))

(defun contains-forbidden-function? (prg-file)
  (setf *forbidden-functions* nil)
  (let ((ffuncs (chng-to-string *forbidden-functions*))
        (cap-symbs (capitalize-list (extract-symbols-from-file prg-file))))
    (labels ((check-fnames (e)
               (cond ((null e) nil)
                     ((member (car e) ffuncs :test #'equal) (car e))
                     (t (check-fnames (cdr e))))))
      (check-fnames cap-symbs))))

#|
(defun contains-forbidden-function? (prg-file &optional (e (uiop:read-file-forms prg-file)))
  (cond ((null e) nil)
        ((atom e) (car (member e *forbidden-functions*)))
        ((eq (car e) 'defun) (contains-forbidden-function? prg-file (cddr e)))
        (t (or (contains-forbidden-function? prg-file (car e)) (contains-forbidden-function? prg-file (cdr e))))))
|#

(defun get-solution (fname lfiles)
  (if (string= fname (file-namestring (car lfiles)))
      (car lfiles)
      (get-solution fname (cdr lfiles))))

(defun remove-extension (filename)
  (subseq filename 0 (position #\. filename :from-end t)))

(defun extract-symbols-from-file (file)
  (with-open-file (stream file :element-type 'character :direction :input)
    (let ((symbols '())
          (current-symbol '())
          (inside-symbol nil))
      (labels ((process-char (char)
                 (cond
                   ((or (char= char #\() (char= char #\)) (char= char #\Space) (char= char #\Newline) (char= char #\Tab))
                    (when inside-symbol
                      (push (coerce (reverse current-symbol) 'string) symbols)
                      (setf current-symbol '())
                      (setf inside-symbol nil)))
                   (t
                    (setf current-symbol (cons char current-symbol))
                    (setf inside-symbol t)))))
        
        (do ((char (read-char stream nil :eof) (read-char stream nil :eof)))
            ((eq char :eof) (return symbols))
          (process-char char))))))


(defun grade-solutions (solution-files test-cases-files)
  (let ((results (list))
        (sol-fnames (mapcar #'file-namestring solution-files)))
    (dolist (test-case test-cases-files)
      (push (list (remove-extension (file-namestring test-case))
                  (if (member (file-namestring test-case) sol-fnames :test #'string=)
                      (let* ((solution (get-solution (file-namestring test-case) solution-files))
                             (evaluation (evaluate-solution solution test-case))
                             (forbid-func (contains-forbidden-function? solution)))
                        (when forbid-func
                          (setf (car evaluation)  (* (car evaluation) (- 1 *penalty-forbidden*)))
                          (setf (cadr evaluation) (list 'used-forbidden-function forbid-func *penalty-forbidden*)))
                        evaluation)
                      (list 0 "missing-question-file" (concatenate 'string (file-namestring test-case) " file not found." nil))))
            results))
    (reverse results)))

(defun grade-it (submissions-zipped-file tests-folder results-folder &optional exam-grades-export-file)
  (check-input-files (append (when exam-grades-export-file (list exam-grades-export-file)) (list submissions-zipped-file tests-folder)))
  (let* ((results-folder (check-foldername  (namestring (ensure-directories-exist results-folder :verbose T))))
         (test-cases-folder (check-foldername  (namestring (ensure-directories-exist tests-folder :verbose T))))
         (feedback-folder (merge-pathnames "student-feedback/" results-folder))
	 (feedback-zipped (merge-pathnames results-folder "student-feedback.zip"))
	 (subs-folder (merge-pathnames "submissions/" results-folder))
	 (subs-folder-wfiles (progn
                               (cleanup-folder feedback-folder)
                               (cleanup-folder subs-folder)
	                       (zip:unzip submissions-zipped-file subs-folder :if-exists :supersede)
	                       subs-folder))
	 (sfolders (directory (concatenate 'string (namestring subs-folder-wfiles) "*/")))
	 (h-table (make-hash-table :test 'equal)))
    (with-open-file (log-file-stream (ensure-directories-exist (merge-pathnames "codegrader-history/log.txt" (user-homedir-pathname)))
                                     :direction :output
                                     :if-exists :append
                                     :if-does-not-exist :create)
      (let ((broadcast-stream (make-broadcast-stream *standard-output* log-file-stream)))
        (format broadcast-stream "~a: Started marking~%" (get-date-time))
        (dolist (folder sfolders)
          (multiple-value-bind (key date) (get-key-and-date folder)
            (let* ((pref (consume-until (consume-until key #\-) #\-)) ;(splice-at-char key #\-))
                   (std-name (subseq pref 1 (1- (length pref))))
                   (sdate (check-dt (form-date-time (replace-char date #\, #\ ))))
                   (student-files (directory (merge-pathnames folder "*.*")))
                   (test-cases-files (directory (merge-pathnames test-cases-folder "*.lisp")))
                   (solutions-evaluations (grade-solutions student-files test-cases-files))
                   (seval (list (/ (reduce #'+ solutions-evaluations :key #'caadr) (length test-cases-files))
                                solutions-evaluations))
                   (item (make-submission :std-name std-name
                                          :date sdate
                                          :evaluation seval
                                          :total-marks (car seval))))
              (format log-file-stream "Student *~a*,  result:~%~a~%" std-name seval)
              (setf (gethash std-name h-table) item)
              (generate-std-feedback key seval feedback-folder)
              )))
        (in-package :codegrader)
        (format *standard-output* "~%============================================================================~%")
        (format *standard-output* "Slime produced the above messages when loading the students' solution~%")
        (format *standard-output* "============================================================================~%")
        (format broadcast-stream "Done marking students solutions.~%")
        (format broadcast-stream "Generating the zipped feedback folder...~%")
        (zip:zip feedback-zipped feedback-folder :if-exists :supersede)
        (format broadcast-stream "Done.~%")
        (when exam-grades-export-file (format broadcast-stream "Generating the grades spreadsheet...~%"))
        (generate-marks-spreadsheet log-file-stream exam-grades-export-file results-folder h-table #'(lambda (x) (submission-total-marks x)) "grades.csv")
        (when exam-grades-export-file (format broadcast-stream "Done.~%"))
        (format broadcast-stream "Exam grading complete!~%" )
        (format *standard-output* "You may now upload to D2L the following grade files stored in your ~a folder :~%" results-folder)
        (when exam-grades-export-file
          (format *standard-output* "- grade.csv : contains the test marks~%"))
        (format *standard-output* "- student-feedback.zip : contains the feedback txt files for each student.")
        (in-package :cl-user)
        "(^_^)"))))
        

#|
(defun grade-it (submissions-zipped-file lab-grades-export-file test-cases-file results due-date-time &optional solution-baseline code-simplicity-export-file)
  (check-input-files (list submissions-zipped-file lab-grades-export-file test-cases-file))
  (let* ((is-zipped t)
         (root-folder (check-foldername  (namestring (ensure-directories-exist results :verbose T))))
         (feedback-folder (merge-pathnames "student-feedback/" root-folder))
	 (feedback-zipped (merge-pathnames root-folder "student-feedback.zip"))
	 (unzipped-subs-folder (merge-pathnames "submissions/" root-folder))
	 (subms-folder (progn
                         (cleanup-folder feedback-folder)
                         (cleanup-folder unzipped-subs-folder)
                         (create-folder-ifzipped is-zipped submissions-zipped-file unzipped-subs-folder)))
	 (sfolders (directory (concatenate 'string (namestring subms-folder) "*/")))
         (hperf-solutions (make-hash-table :test 'equal))
	 (h-table (make-hash-table :test 'equal)))
    (with-open-file (log-file-stream (ensure-directories-exist (merge-pathnames "codegrader-history/log.txt" (user-homedir-pathname)))
                                     :direction :output
                                     :if-exists :append
                                     :if-does-not-exist :create)
      (let ((broadcast-stream (make-broadcast-stream *standard-output* log-file-stream)))
        (format broadcast-stream "~a: Started marking assignme~%Solution correctness:~%" (get-date-time))
        (dolist (folder sfolders)
          (multiple-value-bind (key date) (get-key-and-date folder)
            (let* ((pref (consume-until (consume-until key #\-) #\-)) ;(splice-at-char key #\-))
                   (std-name (subseq pref 1 (1- (length pref))))
                   
                   (student-solution (car (directory (merge-pathnames folder "*.*")))) ; gets first file in the directory
                   (sdate (check-dt (form-date-time (replace-char date #\, #\ ))))
                   (ddate (check-dt due-date-time))
                   (temp-eval (evaluate-solution student-solution test-cases-file ddate sdate))
                   (simp (handler-case (program-size student-solution solution-baseline)
                           (error (condition)
                             (format broadcast-stream "Error in student lisp code: ~a~%" condition))))
                   (seval (if (car simp) ;; applies penalty for solution that mentioned a forbidden function
                              (progn (setf (car temp-eval) (* (car temp-eval) *penalty-forbidden*))
                                     (setf (cadr temp-eval) (list 'used-forbidden-function (car simp)))
                                     temp-eval)
                              temp-eval))
                   (item (make-submission :std-name std-name
                                          :date sdate
                                          :correctness seval                                                        
                                          :simplicity (cadr simp))))
              (format log-file-stream "Student *~a*,  result:~%~a~%" std-name seval)
              (setf (gethash std-name h-table) item)
              (if (>= (car seval) *correctness-threshold*)
                  (setf (gethash std-name hperf-solutions) item))
              (generate-std-feedback key seval feedback-folder))))
        (in-package :codegrader)
        (format *standard-output* "~%============================================================================~%")
        (format *standard-output* "Slime produced the above messages when loading the students' solution~%")
        (format *standard-output* "============================================================================~%")
        (format broadcast-stream "Done marking students solutions.~%")
        (format broadcast-stream "Ranking the simplicity of perfect solutions...~%")
        (rank-perf-solutions hperf-solutions h-table)
        (format broadcast-stream "Done.~%")
        (format broadcast-stream "Generating the code simplicity scores cvs file...~%")
        (generate-kalos-kagathos-file root-folder h-table)
        (format broadcast-stream "Done.~%")        
        (format broadcast-stream "Generating the zipped feedback folder...~%")
        (zip:zip feedback-zipped feedback-folder :if-exists :supersede)
        (format broadcast-stream "Done.~%")
        (format broadcast-stream "Generating the grades spreadsheet...~%")
        (generate-marks-spreadsheet log-file-stream lab-grades-export-file root-folder h-table #'(lambda (x) (car (submission-correctness x))) "grades.csv")
        (format broadcast-stream "Done.~%")
        (when  code-simplicity-export-file
          (format broadcast-stream "Generating the code simplicity spreadsheet...~%")
          (generate-marks-spreadsheet log-file-stream code-simplicity-export-file root-folder h-table #'submission-simplicity "simplicity-score.csv")
          (format broadcast-stream "Done.~%"))
        (format broadcast-stream "Assignment grading complete!~%" )
        (format *standard-output* "You may now upload to D2L the following grade files stored in your ~a folder :~%" results)
        (format *standard-output* "- grade.csv : contains the lab assignment correctness marks~%- student-feedback.zip : contains the feedback txt files for each student~%- (optional) simplicity-score.csv : contains the code simplicity score.")
        (in-package :cg)
"(^_^)"))))
|#

(defun get-lab-files (lab)
  (directory (merge-pathnames (concatenate 'string "Test-Cases/" lab "/*.lisp") (asdf:system-source-directory :codegrader))))

(defun eval-solutions (solutions-folder lab &optional  test-cases-folder)
  (unless (probe-file solutions-folder)
    (error "Folder does not exist: ~S~%" solutions-folder))
  (if test-cases-folder
      (unless (probe-file test-cases-folder)
        (error "Folder does not exist: ~S~%" test-cases-folder)))
  (let* ((solution-files (directory (merge-pathnames solutions-folder "*.*")))
         (test-cases-files
           (if test-cases-folder
               (directory (concatenate 'string test-cases-folder "*.lisp"))
               (case lab
                 (:lab01 (get-lab-files "Lab01"))
                 (:lab02 (get-lab-files "Lab02"))
                 (:lab03 (get-lab-files "Lab03"))
                 (:lab04 (get-lab-files "Lab04"))
                 (:lab05 (get-lab-files "Lab05"))
                 (:lab06 (get-lab-files "Lab06"))
                 (:lab07 (get-lab-files "Lab07"))
                 (:lab08 (get-lab-files "Lab08"))
                 (:lab09 (get-lab-files "Lab09"))
                 (otherwise (error "Invalid lab identifier ~a.~%Lab identifiers are in the form :labXX, where XX is the lab number, e.g., :lab03." lab)))))
         (solution-evaluations (grade-solutions solution-files test-cases-files)))
    (generate-messages t (list (/ (reduce #'+ solution-evaluations :key #'caadr)
                                  (length test-cases-files))
                               solution-evaluations)))
  (in-package :cl-user))


(in-package :cg)

(defun start ()
  
  (format t
          "   
                       <<  Welcome to CodeGrader  >>

   To grade students' solutions, use the GRADE-IT function as describe at

                   https://github.com/marcus3santos/codegrader

   NOTE: once you launch function GRADE-IT, it will start evaluating the students'
   solutions and you may see on your REPL  error/warning messages and output
   generated by the student's solution.

   To go back to CL-USER, type: (quit)")
  (in-package :cg))

(defun quit ()
  (in-package :cl-user))

