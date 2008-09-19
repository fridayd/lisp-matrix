;;;; lisp-matrix package definition.
;;;; Author: mfh

(in-package :cl-user)

(defpackage :lisp-matrix
  (:use :cl
        :cffi
        :cl-utilities
        :org.middleangle.foreign-numeric-vector
        :org.middleangle.cl-blapack
	:ffa
	:fiveam)
  (:import-from :fnv)
  (:export make-matrix make-matrix*  ;; basic instantiations
	   strides-class window-class transpose-class
	   strides window transpose 
	   ones zeros eye rand ;; types 
	   copy copy! copy*
	   copy-maybe copy-maybe*
	   fill-matrix

	   m= m* m+ m- 
	   v= v* v+ v- 

	   print-object
	   mref data row col
	   nelts  nrows ncols
	   matrix-dimension matrix-dimensions
	   orientation valid-orientation-p opposite-orientation
	   flatten-matrix-indices flatten-matrix-indices-1

	   la-simple-matrix-double  la-simple-matrix-integer
	   ;; Next 3 symbols are guesses at... wrong?
	   la-simple-matrix-complex  la-simple-matrix-float 
	   la-simple-matrix-fixnum 
	   
	   la-simple-vector-double
	   la-simple-vector-integer

	   ;; Next paragrah of symbols are guesses... wrong?
	   fa-simple-matrix-double  fa-simple-matrix-integer
	   fa-simple-matrix-complex  fa-simple-matrix-float 
	   fa-simple-vector-double fa-simple-vector-integer
	   fa-simple-matrix-fixnum 
	   ))

(defpackage :lisp-matrix-user
  (:use :cl
	:lisp-matrix))