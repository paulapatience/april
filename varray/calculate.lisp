;;; -*- Mode:Lisp; Syntax:ANSI-Common-Lisp; Coding:utf-8; Package:Varray -*-
;;;; calculate.lisp

(in-package #:varray)

"Definition of virtual array element implementing calculations over arrays, as for 1+1 2 3."

(defclass vader-calculate (vad-subrendering varray-derived vad-on-axis vad-with-io)
  ((%params :accessor vaop-params
            :initform nil
            :initarg :params
            :documentation "Parameters for scalar operation to be performed.")
   (%function :accessor vaop-function
              :initform nil
              :initarg :function
              :documentation "Function to be applied to derived array element(s).")
   (%sub-shape :accessor vaop-sub-shape
               :initform nil
               :initarg :sub-shape
               :documentation "Shape of a lower-rank array to be combined with a higher-rank array along given axes."))
  (:metaclass va-class))

(defmethod etype-of ((varray vader-calculate))
  (if (and (getf (vaop-params varray) :binary-output)
           (if (listp (vader-base varray))
               (loop :for item :in (vader-base varray) :always (not (shape-of item)))
               (loop :for item :across (vader-base varray) :always (not (shape-of item)))))
      'bit t))

(defmethod prototype-of ((varray vader-calculate))
  (if (or (and (not (listp (vader-base varray)))
               (= 1 (size-of (vader-base varray))))
          (and (listp (vader-base varray))
               (= 1 (length (vader-base varray)))))
      (let* ((first-item (if (varrayp (vader-base varray))
                             (let ((gen (generator-of (vader-base varray))))
                               (if (not (functionp gen))
                                   gen (funcall (generator-of (vader-base varray)) 0)))
                             (elt (vader-base varray) 0)))
             (first-shape (shape-of first-item))
             (first-indexer (generator-of first-item)))
        (if (zerop (reduce #'* first-shape))
            (prototype-of (render first-item))
            (if first-shape
                (prototype-of (apply-scalar (vaop-function varray)
                                            (render (if (not (functionp first-indexer))
                                                        first-indexer (funcall first-indexer 0)))))
                (prototype-of (render (if (not (functionp first-indexer))
                                          first-indexer (funcall first-indexer 0)))))))
      (let ((pre-proto)
            (base-list (when (listp (vader-base varray))
                         (vader-base varray)))
            (base-size (if (listp (vader-base varray))
                           (length (vader-base varray))
                           (size-of (vader-base varray))))
            (base-gen (generator-of (vader-base varray))))
        ;; TODO: more optimization is possible here
        (loop :for i :below base-size ; :for item :across (vader-base varray)
              :do (let ((item (if base-list (first base-list)
                                  (funcall base-gen i))))
                    (when (< 0 (size-of item))
                      (let ((this-indexer (generator-of item)))
                        (if (not pre-proto)
                            (setf pre-proto (render (if (not (functionp this-indexer))
                                                        this-indexer (funcall this-indexer 0))))
                            (setf pre-proto
                                  (apply-scalar (vaop-function varray)
                                                pre-proto
                                                (render (if (not (functionp this-indexer))
                                                            this-indexer (funcall this-indexer 0))))))))
                    (setf base-list (rest base-list))))
        (prototype-of pre-proto))))

(defmethod shape-of ((varray vader-calculate))
  (get-promised
   (varray-shape varray)
   (let ((shape) (sub-shape)
         (base-size (if (listp (vader-base varray))
                        (length (vader-base varray))
                        (size-of (vader-base varray))))
         (base-gen (unless (listp (vader-base varray))
                         (generator-of (vader-base varray))))
         (axis (setf (vads-axis varray)
                     (when (vads-axis varray)
                       (funcall (lambda (ax)
                                  (if (numberp ax)
                                      (- ax (vads-io varray))
                                      (if (zerop (size-of ax))
                                          ax (if (= 1 (length ax)) ;; disclose 1-item axis vectors
                                                 (- (aref ax 0) (vads-io varray))
                                                 (loop :for a :across ax
                                                       :collect (- a (vads-io varray)))))))
                                (disclose (render (vads-axis varray)))))))
         (base-list (when (listp (vader-base varray)) (vader-base varray))))
     (flet ((shape-matches (a)
              (loop :for s1 :in shape :for s2 :in (shape-of a) :always (= s1 s2))))
       (typecase (vader-base varray)
         (vapri-integer-progression nil)
         ((or varray sequence)
          (loop :for i :below base-size
                :do (let ((a (if base-gen (funcall base-gen i)
                                 (when base-list (first base-list)))))
                      (when (shape-of a) ;; 1-element arrays are treated as scalars
                        (if (or (not shape)
                                (= 1 (reduce #'* shape)))
                            (setf shape (shape-of a))
                            (let ((rank (length (shape-of a))))
                              (when (or (not (= rank (length shape)))
                                        (and (not (shape-matches a))
                                             (not (= 1 (size-of a)))))
                                (if axis (if (= (length shape)
                                                (if (numberp axis) 1 (length axis)))
                                             (if (> rank (length shape))
                                                 (let ((ax-copy (when (listp axis) (copy-list axis)))
                                                       (shape-copy (copy-list shape))
                                                       (matching t))
                                                   (unless (vaop-sub-shape varray)
                                                     (setf (vaop-sub-shape varray) shape))
                                                   (loop :for d :in (shape-of a) :for ix :from 0
                                                         :when (and (if ax-copy (= ix (first ax-copy))
                                                                        (= ix axis)))
                                                           :do (when (/= d (first shape-copy))
                                                                 (setf matching nil))
                                                               (setf ax-copy (rest ax-copy)
                                                                     shape-copy (rest shape-copy)))
                                                   (if matching (setf shape (shape-of a))
                                                       (error "Mismatched array dimensions.")))
                                                 (if (= rank (length shape))
                                                     (unless (shape-matches a)
                                                       (error "Mismatched array dimensions."))
                                                     (error "Mismatched array dimensions.")))
                                             (if (= rank (if (numberp axis) 1 (length axis)))
                                                 (if (not (shape-matches a))
                                                     (or (and (numberp axis)
                                                              (= (first (shape-of a))
                                                                 (nth axis shape))
                                                              (setf (vaop-sub-shape varray)
                                                                    (shape-of a)))
                                                         (and (listp axis)
                                                              (loop :for ax :in axis :for sh :in shape
                                                                    :always (= sh (nth ax shape)))
                                                              (setf (vaop-sub-shape varray) shape))
                                                         (error "Mismatched array dimensions."))
                                                     (setf (vaop-sub-shape varray) (shape-of a)))
                                                 (error "Mismatched array dimensions.")))
                                    (error "Mismatched array dimensions."))))))
                      (setf base-list (rest base-list))))))
       shape))))

(defmethod generator-of ((varray vader-calculate) &optional indexers params)
  (case (getf params :base-format)
    (:encoded)
    (:linear)
    (t (let* ((out-shape (shape-of varray))
              (sub-shape (vaop-sub-shape varray))
              (out-rank (rank-of varray))
              (axis (vads-axis varray))
              (shape-factors (when axis (get-dimensional-factors out-shape t)))
              (sub-factors (when axis (get-dimensional-factors sub-shape t)))
              (base-size (if (listp (vader-base varray))
                             (length (vader-base varray))
                             (size-of (vader-base varray)))))
         (cond
           ((= 1 base-size)
            (let ((base-gen (generator-of (if (varrayp (vader-base varray))
                                              (funcall (generator-of (vader-base varray)) 0)
                                              (elt (vader-base varray) 0)))))
              (lambda (index)
                
                (if (not (functionp base-gen))
                    (funcall (vaop-function varray) base-gen)
                    (let ((indexed (funcall base-gen index)))
                      (if (or (arrayp indexed) (varrayp indexed))
                          (make-instance 'vader-calculate
                                         :base (vector indexed) :function (vaop-function varray)
                                         :index-origin (vads-io varray) :params (vaop-params varray))
                          (funcall (vaop-function varray)
                                   (funcall base-gen index))))))))
           ((or (vectorp (vader-base varray))
                (varrayp (vader-base varray)))
            (let* ((indexer (generator-of (vader-base varray)))
                   (sub-indexers (coerce (loop :for ax :below (size-of (vader-base varray))
                                               :collect (generator-of (funcall indexer ax)))
                                         'vector)))
              (lambda (index)
                (let ((result) (subarrays) (sub-flag))
                  (loop :for ax :below (size-of (vader-base varray))
                        :do (let* ((a (funcall indexer ax))
                                   (ai (aref sub-indexers ax))
                                   (size (size-of a))
                                   (item (if (and (shape-of a) (< 1 size))
                                             (or (if (not (functionp ai))
                                                     ai (funcall ai index))
                                                 (prototype-of a))
                                             (if (not (varrayp a))
                                                 (if (not (and (arrayp a) (= 1 size)))
                                                     a (if (not (functionp ai))
                                                           ai (funcall ai 0)))
                                                 (if (not (functionp ai))
                                                     ai (funcall ai 0))))))
                              ;; (print (list :aa a item (shape-of varray)))
                              (push item subarrays)
                              ;; TODO: this list appending is wasteful for simple ops like 1+2
                              (if (or (arrayp item) (varrayp item))
                                  (setf sub-flag t)
                                  (setf result (if (not result)
                                                   item (funcall (vaop-function varray)
                                                                 result item))))))
                  (if (not sub-flag)
                      result (make-instance 'vader-calculate :base (coerce (reverse subarrays) 'vector)
                                                             :function (vaop-function varray)
                                                             :index-origin (vads-io varray)
                                                             :params (vaop-params varray)))))))
           (t (let ((sub-indexers (coerce (loop :for a :in (vader-base varray) :collect (generator-of a))
                                          'vector)))
                (lambda (index)
                  (let ((result) (subarrays) (sub-flag))
                    (loop :for a :in (vader-base varray) :for ax :from 0
                          :do (let* ((ai (aref sub-indexers ax))
                                     (size (size-of a))
                                     (item (if (and (shape-of a) (< 1 size))
                                               (if (not (functionp ai))
                                                   ai
                                                   (if (and axis (not (= out-rank (rank-of a))))
                                                       (funcall
                                                        ai (if (numberp axis)
                                                               (mod (floor index (aref shape-factors axis))
                                                                    size)
                                                               (let ((remaining index) (sub-index 0))
                                                                 (loop :for f :across shape-factors
                                                                       :for fx :from 0
                                                                       :do (multiple-value-bind (div remainder)
                                                                               (floor remaining f)
                                                                             (setf remaining remainder)
                                                                             (loop :for ax :in axis
                                                                                   :for ix :from 0
                                                                                   :when (= ax fx)
                                                                                     :do (incf sub-index
                                                                                               (* (aref sub-factors
                                                                                                        ix)
                                                                                                  div)))))
                                                                 sub-index)))
                                                       (or (funcall ai index)
                                                           (prototype-of a))))
                                               (if (not (varrayp a))
                                                   (if (not (and (arrayp a) (= 1 size)))
                                                       a (if (not (functionp ai))
                                                             ai (funcall ai 0)))
                                                   (if (not (functionp ai))
                                                       ai (funcall ai 0))))))
                                (push item subarrays)
                                ;; TODO: this list appending is wasteful for simple ops like 1+2
                                (if (or (arrayp item) (varrayp item))
                                    (setf sub-flag t)
                                    (setf result (if (not result)
                                                     item (funcall (vaop-function varray)
                                                                   result item))))))
                    (if (not sub-flag)
                        result (make-instance 'vader-calculate :base (coerce (reverse subarrays) 'vector)
                                                             :function (vaop-function varray)
                                                             :index-origin (vads-io varray)
                                                             :params (vaop-params varray))))))))))))
