(in-package :cl-user)

(eval-when (:load-toplevel :compile-toplevel :execute)
  (ql:quickload :rutilsx)
  (ql:quickload :yason)
  (ql:quickload :cl-nlp)
  (use-package :rutilsx)
  (use-package :ncore))

(named-readtables:in-readtable rutilsx:rutilsx-readtable)

(defun json->ann (json-file dir &key (offset 40))
  (unless (ends-with "/" dir)
    (:= dir (strcat dir "/")))
  (let ((users #h(equal))
        (uid 0))
    (dolines (line json-file)
      (dolist (record (yason:parse line))
        (with ((((answer "answer") (task "task") (user "user")) ? record)
               (uid (getset# (? user "username") users (:+ uid)))
               (text (? answer "text"))
               (sent-spans (? answer "sentence_offsets"))
               (id (? task "id")))
          (ensure-directories-exist (fmt "~A~A/" dir uid))
          (with-out-file (out (fmt "~A~A/~A.txt" dir uid id))
            (write-line text out))
          (with-out-file (out (fmt "~A~A.txt" dir id))
            (write-line text out))
          (with-out-file (out (fmt "~A~A/~A.ann" dir uid id))
            (dolist (ner (sort (? answer "entities") '< :key ^(? % 2 0 0)))
              (with (((id type spans) ner)
                     ((beg end) (first spans))
                     (sent-beg (first (find-if ^(<= (first %) beg (second %))
                                               sent-spans)))
                     (sent-end (last1 (find-if ^(<= (first %) end (second %))
                                               sent-spans)))
                     (name (slice text beg end)))
                (format out "# ~A[[~A]]~A~%~A	~A ~A ~A	~A~%"
                        (slice text (or (position #\Space text
                                                  :start (max (- beg offset)
                                                              sent-beg)
                                                  :end beg)
                                        beg)
                               beg)
                        name
                        (slice text end
                               (or (position #\Space text
                                             :from-end t :start end
                                             :end (min (+ end offset) sent-end))
                                   end))
                        id type beg end name)))))))
    (with-out-file (out (fmt "~Aannotators.txt" dir))
      (dotable (k v users)
        (format out "~A ~A~%" v k)))
    users))

(defparameter *tokenizer*
  (make 'regex-word-tokenizer
        :regex (re:create-scanner
                (strcat
                 ;; urls
                 "\\w+://\\S+"
                 ;; emails
                 "|[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+.[a-zA-Z0-9-.]+"
                 ;; 90-х etc.
                 "|[0-9]+-[а-яА-Я]{1,2}"
                 ;; decimals & ranges
                 "|[+-]?[0-9](?:[0-9,.-]*[0-9])?"
                 ;; regular words
                 "|[\\w]([\\w'’`-]?[\\w]+)*"
                 ;; abbreviations
                 "|\\w.(\\w.)+\\w?"
                 ;; punctuation & special symbols
                 "|[\"#$%&*+,/:;<=>@^`~…\\(\\)⟨⟩{}\\[\\|\\]‒–—―«»“”‘’']"
                 ;; closing punctuation
                 "|[.!?]+"
                 ;; multiple dashes
                 "|-+"))))

(defun tokenize-text (file)
  (let ((text (read-file file)))
    (with-out-file (xml-out (strcat file ".xml"))
      (write-line "<root><body>" xml-out)
      (with-out-file (tok-out (strcat file ".tok"))
        (dolist (sent (flat-map ^(tokenize <sentence-splitter> %)
                                (split #\Newline
                                       (substr text (+ (search "<body>" text
                                                               :test 'string=)
                                                        6)
                                               (search "</body>" text
                                                       :test 'string=)))))
          (let ((toks (tokenize *tokenizer*
                                (re:regex-replace-all "</?[^>]+>" sent ""))))
            (write-line (strjoin #\Space toks)
                        tok-out)
            (write-line (strcat "<S>" (strjoin #\Space (mapcar ^(strcat % "[]")
                                                               toks))
                                "</S>")
                        xml-out))))
      (write-line "</body></root>" xml-out))))
