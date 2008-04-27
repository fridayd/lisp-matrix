(in-package :lisp-matrix)

(defun valid-orientation-p (x)
  (or (eq x :column) (eq x :row)))

(defun opposite-orientation (x)
  (cond ((eq x :column) :row)
	((eq x :row) :column)
	(t (error "Invalid orientation ~A" x))))

(define-abstract-class matrix-like ()
  ((nrows :initarg :nrows :initform 0 :accessor nrows
	  :documentation "Number of rows in the matrix (view)")
   (ncols :initarg :ncols :initform 0 :accessor ncols
	  :documentation "Number of columns in the matrix (view)")
   ;; Later we'll add different storage formats, such as :general, :upper, :lower, (:banded lbw ubw), but we have some design issues to work out first.
   )
  (:documentation
   "Abstract base class for 2-D matrices and matrix views.  We assume
   for now that matrices are stored in column order (Fortran style),
   for BLAS and LAPACK compatibility."))

(defmethod initialize-instance :after ((A matrix-like) &key)
  "Error checking for initialization of a MATRIX-LIKE object."
  (with-slots (nrows ncols) A
    (assert (>= nrows 0))
    (assert (>= ncols 0))))

(defgeneric nelts (x)
  (:documentation "Default method for computing the number of elements
  of a matrix.  For obvious reasons, this will be overridden for
  subclasses that implement sparse matrices.")
  (:method ((x matrix-like))
    (* (nrows x) (ncols x))))

(defgeneric matrix-dimension (a which)
  (:documentation "Like ARRAY-DIMENSION for matrix-like objects.")
  (:method ((A matrix-like) which)
    (cond ((= which 0) (nrows A))
          ((= which 1) (ncols A))
          (t (error "The given matrix has only two dimensions, but you tried to access dimension ~A"
                    (1+ which))))))

(defgeneric matrix-dimensions (a)
  (:documentation "Like ARRAY-DIMENSIONS for matrix-like objects.")
  (:method ((A matrix-like)) 
    (list (nrows A) (ncols A))))

(define-abstract-class matview (matrix-like) 
  ((parent :initarg :parent
	   :reader parent
	   :documentation "The \"parent\" object to which this matrix
	   view relates."))
  (:documentation "An abstract class representing a \"view\" into a matrix.
                   That view may be treated as a (readable and writeable) 
                   reference to the elements of the matrix."))

(defgeneric make-matrix (nrows ncols fnv-type &key initial-element
                               initial-contents)
  (:documentation "Generic method for creating a matrix, given the
  number of rows NROWS, the number of columns NCOLS, and optionally
  either an initial element INITIAL-ELEMENT or the initial contents
  INITIAL-CONTENTS (a 2-D array with dimensions NROWS x NCOLS), which
  are (deep) copied into the resulting matrix."))

(defgeneric flatten-matrix-indices (a i j)
  (:documentation "Given an index pair (I,J) into the given matrix A,
  returns the 1-D index corresponding to the location in the
  underlying storage in which the element A(i,j) is stored."))

(defgeneric mref (a i j)
  (:documentation "(MREF A i j) gives you the (i,j)-th element of the
  matrix A. This method is slow (as it requires CLOS method dispatch
  and index calculation(s)) and is thus to be replaced with vectorized
  or block operations whenever possible."))

(defgeneric orientation (a)
  (:documentation "lisp-matrix objects are stored in column order."))

;;; internal generic functions

(defgeneric fnv-type-to-matrix-type (type matrix-type)
  (:documentation "Given a particular FNV type (such as
  'complex-float) and a keyword indicating the kind of matrix or
  matrix view, returns the corresponding specific matrix (view)
  type."))

(defgeneric matrix-type-to-fnv-type (type))

(defgeneric unit-stride-p (a)
  (:documentation "Tests for \"unit stride.\" (The strided matrix view
  is the only view which causes itself and its children possibly not
  to have unit stride.)"))

(defgeneric fnv-type (a)
  (:documentation "Given an object of a particular matrix (view) type,
  returns the corresponding FNV type (such as 'double, 'complex-float,
  etc.)."))

;;; Macro to make the actual matrix classes

(eval-when (:compile-toplevel :load-toplevel)
  
  (defmacro make-typed-matrix (fnv-type)
    "Template constructor macro for MATRIX and other object types that 
     hold data using FNV objects of type FNV-TYPE (which is the FNV 
     datatype suffix, such as complex-double, float, double, etc.)."
    (let ((fnv-ref (make-symbol* "FNV-" fnv-type "-REF"))
	  (make-fnv (make-symbol* "MAKE-FNV-" fnv-type))
	  (lisp-matrix-type-name (make-symbol* "MATRIX-" fnv-type))
	  (lisp-matrix-window-view-type-name 
	   (make-symbol* "WINDOW-MATVIEW-" fnv-type))
	  (lisp-matrix-transpose-view-type-name
	   (make-symbol* "TRANSPOSE-MATVIEW-" fnv-type))
	  (lisp-matrix-strided-view-type-name
	   (make-symbol* "STRIDED-MATVIEW-" fnv-type)))

      `(progn
	 (defclass ,lisp-matrix-type-name (matrix-like)
	   ((data :initarg :data
		  ;; We don't provide an initform because it's the 
		  ;; responsibility of the MATRIX "generic" function
		  ;; to initialize the FNV.  Users aren't supposed to
		  ;; construct an element of this class directly (i.e.
		  ;; using MAKE-INSTANCE).
		  :documentation "The FNV object holding the elements."
		  :reader data))
	   (:documentation 
	    ,(format nil "Dense matrix holding elements of type ~A" fnv-type)))
         
	 (defmethod flatten-matrix-indices ((A ,lisp-matrix-type-name) i j)
           (declare (type fixnum i j))
	   ;; Note that storage is column-oriented, for compatibility
	   ;; with the BLAS and LAPACK (which are Fortran-based).
	   (+ (* (nrows A) j) i))

	 (defmethod mref ((A ,lisp-matrix-type-name) i j)
           (declare (type fixnum i j))
	   (,fnv-ref (data A) (flatten-matrix-indices A i j)))

	 (defmethod orientation ((A ,lisp-matrix-type-name))
	   :column)
	 
	 ;; TODO: set up SETF to work with MREF.
	 
	 (defclass ,lisp-matrix-window-view-type-name (matview)
	   ((offset0 :initarg :offset0
		     :initform 0
		     :reader offset0)
	    (offset1 :initarg :offset1
		     :initform 0
		     :reader offset1))
	   (:documentation "A WINDOW-MATVIEW views a block of elements in the 
              underlying matrix that is conceptually 2-D contiguous.  If the 
              underlying matrix is column-oriented, the elements in each column 
              of a WINDOW-MATVIEW are stored contiguously, and horizontally 
              adjacent elements are separated by a constant stride (\"LDA\" in 
              BLAS terms)."))

	 (defmethod flatten-matrix-indices ((A ,lisp-matrix-window-view-type-name) 
					    i j)
	   (declare (type fixnum i j))
	   (with-slots (parent offset0 offset1) A
	     (flatten-matrix-indices parent (+ i offset0) (+ j offset1))))

	 (defmethod mref ((A ,lisp-matrix-window-view-type-name) i j)
	   (declare (type fixnum i j))
	   (with-slots (parent offset0 offset1) A
	     (mref parent (+ i offset0) (+ j offset1))))

	 (defmethod orientation ((A ,lisp-matrix-window-view-type-name))
	   (orientation (parent A)))

	 (defclass ,lisp-matrix-transpose-view-type-name (matview)
           nil
	   (:documentation "A TRANSPOSE-MATVIEW views the
             transpose of a matrix.  If you want a deep copy,
             call the appropriate COPY function on the transpose
             view.  The reason for this is to avoid expensive
             operations whenever possible.  Many BLAS and LAPACK
             routines have a \"TRANSA\" argument (or similar)
             that lets you specify that the operation should work
             with the transpose of the matrix.  This means that
             it usually isn't necessary to compute an explicit
             transpose, at least for input arguments."))

	 (defmethod initialize-instance :after ((A ,lisp-matrix-transpose-view-type-name) &key)
	   "Set up the number of rows and columns correctly for a transpose view."
	   (progn
	     (setf (nrows A) (ncols (parent A)))
	     (setf (ncols A) (nrows (parent A)))))

	 (defmethod flatten-matrix-indices ((A ,lisp-matrix-transpose-view-type-name) i j)
	   (declare (type fixnum i j))
	   (flatten-matrix-indices (parent A) j i))

	 (defmethod mref ((A ,lisp-matrix-transpose-view-type-name) i j)
	   (declare (type fixnum i j))
	   (with-slots (parent) A
	     (mref parent j i)))

	 (defmethod orientation ((A ,lisp-matrix-transpose-view-type-name))
	   (opposite-orientation (parent A)))

	 (defclass ,lisp-matrix-strided-view-type-name (,lisp-matrix-window-view-type-name)
	   ((stride0 :initarg :stride0
		     :initform 1
		     :reader stride0
		     :documentation "Stride in the row direction")
	    (stride1 :initarg :stride1
		     :initform 1
		     :reader stride1
		     :documentation "Stride in the column direction"))
	   (:documentation "A STRIDED-MATVIEW views a window of the
	   matrix with a particular stride in each direction (the
	   stride can be different in each direction)."))

	 (defmethod initialize-instance ((A ,lisp-matrix-strided-view-type-name) &key)
	   ;; FIXME: add more error checking for the strides!
	   (assert (/= 0 (stride0 A)))
	   (assert (/= 0 (stride1 A))))

	 (defmethod flatten-matrix-indices ((A ,lisp-matrix-strided-view-type-name) 
					    i j)
	   (declare (type fixnum i j))
	   (with-slots (offset0 offset1 stride0 stride1 parent) A
	     (flatten-matrix-indices parent 
				     (+ offset0 (* i stride0))
				     (+ offset1 (* j stride1)))))

	 (defmethod mref ((A ,lisp-matrix-strided-view-type-name) i j)
	   (declare (type fixnum i j))
	   (with-slots (offset0 offset1 stride0 stride1 parent) A
	     (mref parent (+ offset0 (* i stride0)) 
		   (+ offset1 (* j stride1)))))

	 (defmethod orientation ((A ,lisp-matrix-strided-view-type-name))
	   (orientation (parent A)))

	 (defmethod unit-stride-p ((A ,lisp-matrix-type-name))
	   t)
	 (defmethod unit-stride-p ((A ,lisp-matrix-window-view-type-name))
	   (unit-stride-p (parent A)))
	 (defmethod unit-stride-p ((A ,lisp-matrix-transpose-view-type-name))
	   (unit-stride-p (parent A)))
	 (defmethod unit-stride-p ((A ,lisp-matrix-strided-view-type-name))
	   (and (= (stride0 A) 1)
		(= (stride1 A) 1)
		(unit-stride-p (parent A))))

	 (defmethod fnv-type-to-matrix-type ((type (eql ',fnv-type))
					     matrix-type)
           (cond ((eq matrix-type :matrix)
		  ',lisp-matrix-type-name)
		 ((eq matrix-type :window)
		  ',lisp-matrix-window-view-type-name)
		 ((eq matrix-type :transpose)
		  ',lisp-matrix-transpose-view-type-name)
		 ((eq matrix-type :strided)
		  ',lisp-matrix-strided-view-type-name)
		 (t
		  (error "Invalid matrix type ~A" matrix-type))))

	 (defmethod matrix-type-to-fnv-type
             ((type (eql ',lisp-matrix-type-name)))
	   ',fnv-type)
	 (defmethod matrix-type-to-fnv-type
             ((type (eql ',lisp-matrix-window-view-type-name)))
	   ',fnv-type)
	 (defmethod matrix-type-to-fnv-type
             ((type (eql ',lisp-matrix-transpose-view-type-name)))
	   ',fnv-type)
	 (defmethod matrix-type-to-fnv-type
             ((type (eql ',lisp-matrix-strided-view-type-name)))
	   ',fnv-type)

	 (defmethod fnv-type ((A ,lisp-matrix-type-name))
	   ',fnv-type)
	 (defmethod fnv-type ((A ,lisp-matrix-window-view-type-name))
	   ',fnv-type)
	 (defmethod fnv-type ((A ,lisp-matrix-transpose-view-type-name))
	   ',fnv-type)
	 (defmethod fnv-type ((A ,lisp-matrix-strided-view-type-name))
	   ',fnv-type)

         (defmethod make-matrix (nrows ncols (fnv-type (eql ',fnv-type)) &key
                                 (initial-element 0)
                                 (initial-contents nil initial-contents-p))
           ;; Logic for handling initial contents or initial element.
           ;; Initial contents take precedence (if they are specified,
           ;; then any supplied initial-element argument is ignored).
           (let ((data
                  (cond
                    (initial-contents-p
                     (let* ((n (* nrows ncols))
                            (fnv (,make-fnv n)))
                       (dotimes (i nrows fnv)
                         (dotimes (j ncols)
                           ;; FIXME: initial contents may be a list as
                           ;; in MAKE-ARRAY -- Evan Monroig 2008.04.24
                           (setf (,fnv-ref fnv (+ i (* nrows j)))
                                 (aref initial-contents i j))))))
                    (t
                     (,make-fnv (* nrows ncols)
                                :initial-value initial-element)))))
             (make-instance ',lisp-matrix-type-name
                            :nrows nrows
                            :ncols ncols
                            :data data)))))))

;;; Instantiate the classes and methods.
(make-typed-matrix double)
(make-typed-matrix float)
(make-typed-matrix complex-double)
(make-typed-matrix complex-float)

	       




;;; "Generic" methods for creating views.

(defgeneric window (parent &key nrows ncols offset0 offset1)
  (:documentation "Creates a window view of the given matrix-like
  object PARENT.  Note that window views always have the same
  orientation as their parents.")
  (:method ((parent matrix-like) 
            &key (nrows (nrows parent))
            (ncols (ncols parent))
            (offset0 0)
            (offset1 0))
    (make-instance (fnv-type-to-matrix-type (fnv-type parent) :window)
                   :parent parent
                   :nrows nrows
                   :ncols ncols
                   :offset0 offset0
                   :offset1 offset1)))

(defgeneric transpose (parent)
  (:documentation "Creates a transpose view of the given matrix-like
  object PARENT.")
  (:method ((parent matrix-like))
    (make-instance (fnv-type-to-matrix-type (fnv-type parent) :transpose)
                   :parent parent)))

(defgeneric strides (parent &key nrows ncols offset0 offset1 stride0
                            stride1)
  (:documentation "Creates a strided view of the given matrix-like
  object PARENT.")
  (:method ((parent matrix-like)
            &key 
            (nrows (nrows parent))
            (ncols (ncols parent))
            (offset0 0)
            (offset1 0)
            (stride0 1)
            (stride1 1))
    (make-instance (fnv-type-to-matrix-type (fnv-type parent) :strided)
                   :parent parent
                   :nrows nrows
                   :ncols ncols
                   :offset0 offset0
                   :offset1 offset1
                   :stride0 stride0
                   :stride1 stride1)))


;;; Export the symbols that we want to export.
(export '(nelts matrix window transpose strides matrix-dimension matrix-dimensions mref unit-stride-p))

