; libctl: flexible Guile-based control files for scientific software 
; Copyright (C) 1998, 1999, 2000, 2001, Steven G. Johnson
;
; This library is free software; you can redistribute it and/or
; modify it under the terms of the GNU Lesser General Public
; License as published by the Free Software Foundation; either
; version 2 of the License, or (at your option) any later version.
;
; This library is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
; Lesser General Public License for more details.
; 
; You should have received a copy of the GNU Lesser General Public
; License along with this library; if not, write to the
; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
; Boston, MA  02111-1307, USA.
;
; Steven G. Johnson can be contacted at stevenj@alum.mit.edu.

; ***************************************************************************

; "Standard" Scheme functions missing from Guile 1.2:

(define (string-upcase s)
  (list->string (map (lambda (c)
		       (if (and (char>=? c #\a) (char<=? c #\z))
			   (integer->char (+ (char->integer c)
					     (char->integer #\A)
					     (- (char->integer #\a))))
			   c))
		     (string->list s))))

; ***************************************************************************

(define (c-identifier s)
  (list->string (map (lambda (c) 
		       (if (or (eq? c #\-) (eq? c #\space))
			   #\_ (if (eq? c #\?) #\p c)))
		     (string->list s))))

(define symbol->c-identifier (compose c-identifier symbol->string))

(define c-type-string (compose c-identifier type-string))

(define declared-type-names '())
(define (declare-type-name type-name)
  (if (and (list-type-name? type-name)
	   (not (member (c-type-string type-name) declared-type-names)))
      (begin
	(if (list-type-name? (list-el-type-name type-name))
	    (declare-type-name (list-el-type-name type-name)))
	(print "typedef struct {\n")
	(print "int num_items;\n")
	(print (c-type-string (list-el-type-name type-name))
		      " *items;\n")
	(print "} " (c-type-string type-name) ";\n\n")
	(set! declared-type-names (cons (c-type-string type-name)
					declared-type-names)))))

(define (c-var-decl var-name var-type-name)
  (print (c-type-string var-type-name) " " 
		(symbol->c-identifier var-name) ";\n"))

; ***************************************************************************

(define (find-direct-subclasses class)
  (list-transform-positive class-list
    (lambda (c) (eq? (class-parent c) class))))

(define (class-identifier class)
  (symbol->c-identifier (class-type-name class)))

(define (class-enum-name class)
  (string-upcase (class-identifier class)))

(define (c-class-decl class)
  (for-each (compose declare-type-name property-type-name)
	    (class-properties class))
  (print "typedef struct " (class-identifier class)
		"_struct {\n")
  (for-each 
   (lambda (property)
     (c-var-decl (property-name property) (property-type-name property)))
   (class-properties class))
  (let ((subclasses (find-direct-subclasses class)))
    (if (not (null? subclasses))
	(begin
	  (print "enum { " (class-enum-name class) "_SELF" )
	  (for-each (lambda (sc) (print ", " (class-enum-name sc)))
		    subclasses)
	  (print " } which_subclass;\n")
	  (print "union {\n")
	  (for-each (lambda (sc)
		      (print
		       "struct " (class-identifier sc) "_struct *"
		       (class-identifier sc) "_data;\n"))
		    subclasses)
	  (print "} subclass;\n"))))
  (print "} " (class-identifier class) ";\n\n"))
       
(define (display-c-class-decls)
  (print "/******* Type declarations *******/\n\n")
  (for-each c-class-decl (reverse class-list)))

; ***************************************************************************

(define (declare-var var)
  (c-var-decl (var-name var) (var-type-name var)))
(define (declare-extern-var var)
  (print "extern ")
  (c-var-decl (var-name var) (var-type-name var)))

(define (declarer-if-not-input-var declarer)
  (lambda (var)
    (if (not (member var input-var-list))
	(declarer var)
	(begin (print "/* " (var-name var) 
			     " is both input and output */\n")))))

(define (declare-var-types)
  (let ((var-types (append
		    (map var-type-name 
			 (append (reverse input-var-list) 
				 (reverse output-var-list)))
		    (map external-function-return-type-name
			 external-function-list)
		    (fold-right append '()
				(map external-function-arg-type-names
				     external-function-list)))))
    (for-each declare-type-name var-types)))

(define (declare-vars declarer)
  (print "/******* Input variables *******/\n")
  (for-each declarer (reverse input-var-list))
  (print "\n")
  (print "/******* Output variables *******/\n")
  (for-each (declarer-if-not-input-var declarer) (reverse output-var-list))
  (print "\n"))

(define (declare-vars-header)
  (declare-var-types)
  (declare-vars declare-extern-var))
(define (declare-vars-source) (declare-vars declare-var))

; ***************************************************************************

(define (input-value s-var-name-str c-var-name-str type-name getter)
  (let ((desc (get-type-descriptor type-name)))
    (cond
     ((eq? (type-descriptor-kind desc) 'simple)
      (print c-var-name-str " = " 
		    (getter type-name s-var-name-str) ";\n"))
     ((eq? (type-descriptor-kind desc) 'object)
      (print (class-input-function-name type-name) "("
		    (getter 'object s-var-name-str)
		    ", &" c-var-name-str ");\n"))
     ((eq? (type-descriptor-kind desc) 'uniform-list)
      (input-list (getter 'list s-var-name-str) c-var-name-str
		  (list-el-type-name type-name))))))

(define (get-global type-symbol name-str)
  (string-append "ctl_get_" (symbol->c-identifier type-symbol)
		 "(\"" name-str "\")" ))

(define (property-getter object-name-str)
  (lambda (type-symbol name-str)
    (string-append (symbol->c-identifier type-symbol)
		   "_object_property(" object-name-str ", "
		   "\"" name-str "\")" )))

(define (list-getter lo-name-str)
  (lambda (type-symbol name-str)
    (string-append (symbol->c-identifier type-symbol)
                   "_list_ref(" lo-name-str ", "
                   name-str ")" )))

(define list-temp-suffix "_t")

(define (input-list list-object-get-str c-var-name-str type-name)
  (print "{\n")
  (let ((lo-name-str (string-append "lo" list-temp-suffix))
	(index-name-str (string-append "i" list-temp-suffix))
	(saved-list-temp-suffix list-temp-suffix))
    (set! list-temp-suffix (string-append list-temp-suffix "_t"))
    (print "list " lo-name-str " = "
		  list-object-get-str ";\n")
    (print "int " index-name-str ";\n")
    (print c-var-name-str 
		  ".num_items = list_length(" lo-name-str ");\n")
    (print c-var-name-str ".items = (" 
		  (c-type-string type-name)
		  "*) malloc(sizeof("
		  (c-type-string type-name) ") * "
		  c-var-name-str ".num_items);\n")
    (print "for (" index-name-str " = 0; " index-name-str " < "
		  c-var-name-str ".num_items; " index-name-str "++) {\n")
    (input-value index-name-str 
		 (string-append c-var-name-str ".items[" index-name-str "]")
		 type-name (list-getter lo-name-str))
    (print "}\n")
    (set! list-temp-suffix saved-list-temp-suffix))
  (print "}\n"))

(define (class-input-function-name type-name)
  (string-append (symbol->c-identifier type-name)
		 "_input"))

(define (class-input-function-decl class)
  (print "void " 
		(class-input-function-name (class-type-name class))
		"(SCM so, "
		(c-type-string (class-type-name class)) " *o)"))

(define (class-input-function class)
  (class-input-function-decl class)
  (print "\n{\n")
  (for-each
   (lambda (property)
     (input-value (symbol->string (property-name property))
		  (string-append "o->" (symbol->c-identifier 
					(property-name property)))
		  (property-type-name property)
		  (property-getter "so")))
   (class-properties class))
  (let ((subclasses (find-direct-subclasses class)))
    (for-each
     (lambda (sc)
       (print "if (object_is_member(\"" (class-type-name sc) 
		     "\", so)) {\n")
       (print "o->which_subclass = " (class-enum-name sc) ";\n")
       (print "o->subclass." (class-identifier sc)
		     "_data = (" (class-identifier sc)
		     "*) malloc(sizeof("
		     (class-identifier sc) "));\n")
       (print (class-input-function-name (class-type-name sc)) 
		     "(so, o->subclass." (class-identifier sc) "_data);\n"
		     "}\nelse "))
     subclasses)
   (if (not (null? subclasses))
       (begin
	 (print "\n")
	 (print "o->which_subclass = " 
		       (class-enum-name class) "_SELF;\n"))))
  (print "}\n\n"))

(define (output-class-input-functions-header)
  (print "/******* class input function prototypes *******/\n\n")
  (for-each
   (lambda (class)
     (print "extern ") (class-input-function-decl class)
     (print ";\n"))
   class-list)
  (print "\n"))

(define (output-class-input-functions-source)
  (print "/******* class input functions *******/\n\n")
  (for-each class-input-function class-list))

(define (input-vars-function)
  (print "/******* read input variables *******/\n\n")
  (print "SCM read_input_vars(void)\n")
  (print "{\n")
  (print "if (num_read_input_vars++) destroy_input_vars();\n")
  (for-each
   (lambda (var)
     (input-value
      (symbol->string (var-name var))
      (symbol->c-identifier (var-name var))
      (var-type-name var)
      get-global))
   (reverse input-var-list))
  (print "return SCM_UNSPECIFIED;\n")
  (print "}\n\n"))

; ***************************************************************************

(define (export-object-value c-var-name-str type-name exporter)
  (error "object output variables are not yet supported. "
	 type-name c-var-name-str))

(define (export-list-value c-var-name-str type-name exporter)
  (let ((el-type-name (list-el-type-name type-name)))
    (let ((el-desc (get-type-descriptor el-type-name)))
      (cond
       ((eq? (type-descriptor-kind el-desc) 'simple)
	(exporter (string-append "make_" (type-descriptor-name-str el-desc)
				 "_list("
				 c-var-name-str ".num_items, "
				 c-var-name-str ".items)")))
       (else
	(error
	 "only export of lists of simple types is currently supported, not "
	 el-type-name))))))

(define (output-value s-var-name-str c-var-name-str type-name setter)
  (let ((desc (get-type-descriptor type-name)))
    (cond
     ((eq? (type-descriptor-kind desc) 'simple)
      (print (setter type-name s-var-name-str c-var-name-str) "\n"))
     ((eq? (type-descriptor-kind desc) 'object)
      (export-object-value c-var-name-str type-name
			   (lambda (sobj-str)
			     (print 
			      (setter 'object s-var-name-str sobj-str))
			      (print "\n"))))
     ((eq? (type-descriptor-kind desc) 'uniform-list)
      (export-list-value c-var-name-str type-name
			 (lambda (slist-str)
			   (print
			    (setter 'list s-var-name-str slist-str))
			    (print "\n")))))))

(define (set-global type-symbol s-name-str c-name-str)
  (string-append "ctl_set_" (symbol->c-identifier type-symbol)
                 "(\"" s-name-str "\", " c-name-str ");" ))

(define (output-vars-function)
  (print "/******* write output variables *******/\n\n")
  (print "SCM write_output_vars(void)\n")
  (print "{\n")
  (print "num_write_output_vars++;\n")
  (for-each
   (lambda (var)
     (output-value
      (symbol->string (var-name var))
      (symbol->c-identifier (var-name var))
      (var-type-name var)
      set-global))
   (reverse output-var-list))
  (print "return SCM_UNSPECIFIED;\n")
  (print "}\n\n"))

; ***************************************************************************

(define (destroy-c-var var-str type-name)
  (let ((desc (get-type-descriptor type-name)))
    (cond 
     ((eq? type-name 'string)
      (print "free(" var-str ");\n"))
     ((eq? (type-descriptor-kind desc) 'uniform-list)
      (destroy-list var-str (list-el-type-name type-name)))
     ((eq? (type-descriptor-kind desc) 'object)
      (destroy-object var-str type-name)))))

(define (class-destroy-function-name type-name)
  (string-append (symbol->c-identifier type-name)
		 "_destroy"))

(define (class-destroy-function-decl class)
  (print "void " 
		(class-destroy-function-name (class-type-name class))
		"("
		(c-type-string (class-type-name class)) " o)"))

(define (destroy-list var-str el-type-name)
  (let ((index-name (string-append "index" list-temp-suffix))
	(saved-suffix list-temp-suffix))
    (set! list-temp-suffix (string-append list-temp-suffix "_t"))
    (print "{\n")
       (print "int " index-name ";\n")
       (print "for (" index-name " = 0; " index-name " < "
		     var-str ".num_items; " index-name "++) {\n")
       (destroy-c-var (string-append var-str ".items[" index-name "]")
		    el-type-name)
       (print "}\n")
    (print "}\n")
    (print "free(" var-str ".items);\n")
    (set! list-temp-suffix saved-suffix)))

(define (destroy-object var-str type-name)
  (print (class-destroy-function-name type-name) "(" var-str ");\n"))

(define (destroy-property prefix-str property)
  (destroy-c-var (string-append prefix-str (symbol->c-identifier
					  (property-name property)))
		 (property-type-name property)))

(define (class-destroy-function class)
  (class-destroy-function-decl class)
  (print "\n{\n")
  (for-each
   (lambda (property) (destroy-property "o." property))
   (class-properties class))
  (let ((subclasses (find-direct-subclasses class)))
    (for-each
     (lambda (sc)
       (print "if (o.which_subclass == " (class-enum-name sc) ") {\n")
       (destroy-object (string-append "*o.subclass." 
				      (class-identifier sc) "_data")
		       (class-type-name sc))
       (print "free(o.subclass." (class-identifier sc) "_data);\n")
       (print "}\n")
       (print "else "))
     subclasses)
   (if (not (null? subclasses))
       (begin
	 (print "{ }\n"))))
  (print "}\n\n"))

(define (output-class-destruction-functions-header)
  (print "/******* class destruction function prototypes *******/\n\n")
  (for-each
   (lambda (class)
     (print "extern ") (class-destroy-function-decl class)
     (print ";\n"))
   class-list)
  (print "\n"))

(define (output-class-destruction-functions-source)
  (print "/******* class destruction functions *******/\n\n")
  (for-each class-destroy-function class-list))

(define (destroy-input-vars-function)
  (print "/******* destroy input variables *******/\n\n")
  (print "SCM destroy_input_vars(void)\n")
  (print "{\n")
  (for-each
   (lambda (var)
     (destroy-c-var
      (symbol->c-identifier (var-name var))
      (var-type-name var)))
   (reverse input-var-list))
  (print "return SCM_UNSPECIFIED;\n")
  (print "}\n\n"))

(define (destroy-output-vars-function)
  (print "/******* destroy output variables *******/\n\n")
  (print "SCM destroy_output_vars(void)\n")
  (print "{\n")
  (for-each
   (lambda (var)
     (if (not (member var input-var-list))
	 (destroy-c-var
	  (symbol->c-identifier (var-name var))
	  (var-type-name var))))
   (reverse output-var-list))
  (print "return SCM_UNSPECIFIED;\n")
  (print "}\n\n"))

; ***************************************************************************

(define (list->indices lst start-index)
  (if (null? lst) '()
      (cons start-index (list->indices (cdr lst) (+ start-index 1)))))

(define (declare-external-function external-function)
  (print "SCM " (symbol->c-identifier
		       (external-function-aux-name
			(external-function-name external-function)))
		"(")
  (for-each
   (lambda (argnum)
     (if (> argnum 0) (print ", "))
     (print "SCM arg_scm_" argnum))
   (list->indices (external-function-arg-type-names external-function) 0))
  (if (= (length (external-function-arg-type-names external-function)) 0)
      (print "void"))
  (print ")"))

(define (declare-external-c-function external-function)
  (print
   "extern "
   (if (not (eq? (external-function-return-type-name external-function)
		 no-return-value))
       (c-type-string (external-function-return-type-name external-function))
       "void")
   " "
   (symbol->c-identifier (external-function-name external-function))
   "(")

  (for-each
   (lambda (arg-type-name argnum)
     (if (> argnum 0) (print ", "))
     (print (c-type-string arg-type-name)))
   (external-function-arg-type-names external-function)
   (list->indices (external-function-arg-type-names external-function) 0))

  (if (= (length (external-function-arg-type-names external-function)) 0)
      (print "void"))
  (print ");\n"))

(define (output-external-functions-header)
  (print "/******* external-functions *******/\n\n")
  (for-each
   (lambda (ef)
     (declare-external-c-function ef)
     (print "extern ")
     (declare-external-function ef)
     (print ";\n\n"))
   external-function-list)
  (print "\nextern void export_external_functions(void);\n")
  (print "\n"))

(define (output-external-function-export external-function)
  (print
   "gh_new_procedure(\""
   (external-function-aux-name (external-function-name external-function))
   "\", "
   (symbol->c-identifier
    (external-function-aux-name (external-function-name external-function)))
   ", "
   (length (external-function-arg-type-names external-function))
   ", 0, 0);\n"))

(define (output-export-external-functions)
  (print "void export_external_functions(void)\n")
  (print "{\n")
  (for-each output-external-function-export external-function-list)
  (print "}\n\n"))

(define (get-c-local type-symbol name-str)
  (string-append "ctl_convert_" (symbol->c-identifier type-symbol)
		 "_to_c(" name-str ")"))

(define (set-c-local type-symbol s-name-str c-name-str)
  (string-append s-name-str " = ctl_convert_"
		 (symbol->c-identifier type-symbol)
		 "_to_scm(" c-name-str ");"))

(define (output-external-function external-function)
  (declare-external-function external-function) (print "\n")
  (print "{\n")

  (if (not (eq? (external-function-return-type-name external-function)
		no-return-value))
      (begin
	(print "SCM return_val_scm;\n")
	(c-var-decl 'return-val-c (external-function-return-type-name
				   external-function))))

  (for-each
   (lambda (arg-type-name argnum)
     (print (c-type-string arg-type-name) " arg_c_" argnum ";\n"))
   (external-function-arg-type-names external-function)
   (list->indices (external-function-arg-type-names external-function) 0))
  (print "\n")
  
  (for-each
   (lambda (arg-type-name argnum)
     (input-value (string-append "arg_scm_" (number->string argnum))
		  (string-append "arg_c_" (number->string argnum))
		  arg-type-name
		  get-c-local))
   (external-function-arg-type-names external-function)
   (list->indices (external-function-arg-type-names external-function) 0))
  (print "\n")

  (print "#ifdef HAVE_SCM_FLUSH_ALL_PORTS\nscm_flush_all_ports();\n#endif\n")

  (if (not (eq? (external-function-return-type-name external-function)
                no-return-value))
      (print "return_val_c = "))
  (print
   (symbol->c-identifier (external-function-name external-function))
   "(")
  (for-each
   (lambda (argnum)
     (if (> argnum 0) (print ", "))
     (print "arg_c_" argnum))
   (list->indices (external-function-arg-type-names external-function) 0))
  (print ");\n\n")

  (print "fflush(stdout); fflush(stderr);\n")

  (for-each
   (lambda (arg-type-name argnum)
     (destroy-c-var
      (string-append "arg_c_" (number->string argnum)) arg-type-name))
   (external-function-arg-type-names external-function)
   (list->indices (external-function-arg-type-names external-function) 0))
  (print "\n")

  (if (not (eq? (external-function-return-type-name external-function)
		no-return-value))
      (begin
	(output-value
	 "return_val_scm" "return_val_c"
	 (external-function-return-type-name external-function)
	 set-c-local)
	(destroy-c-var "return_val_c"
		       (external-function-return-type-name external-function))
	(print "return return_val_scm;\n"))
      (begin (print "return SCM_UNSPECIFIED;\n")))

  (print "}\n\n"))

(define (output-external-functions-source)
  (print "/******* external-functions *******/\n\n")
  (for-each output-external-function external-function-list)
  (output-export-external-functions))

; ***************************************************************************

(define (output-header)
  (display-c-class-decls)
  (declare-vars-header)
  (print "extern int num_read_input_vars;\n")
  (print "extern int num_write_output_vars;\n\n")
  (print "extern SCM read_input_vars(void);\n")
  (print "extern SCM write_output_vars(void);\n")
  (print "extern SCM destroy_input_vars(void);\n")
  (print "extern SCM destroy_output_vars(void);\n\n")
  (output-external-functions-header)
  (output-class-input-functions-header)
  (output-class-destruction-functions-header)
)

(define (output-source)
  (declare-vars-source)
  (print
   "int num_read_input_vars = 0; /* # calls to read_input_vars */\n"
   "int num_write_output_vars = 0; /* # calls to read_input_vars */\n\n")
  (output-class-input-functions-source)
  (output-class-destruction-functions-source)
  (input-vars-function)
  (output-vars-function)
  (destroy-input-vars-function)
  (destroy-output-vars-function)
  (output-external-functions-source))

