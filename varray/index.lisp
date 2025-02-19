;;; -*- Mode:Lisp; Syntax:ANSI-Common-Lisp; Coding:utf-8; Package:Varray -*-
;;;; index.lisp

(in-package #:varray)

"Indexers for virtual arrays, including optimized polymorphic functions that may be selected for use based on the most efficient compatible coordinate datatype for a given tree of virtual array objects."

(let ((indexer-table-encoded
        (intraverser
         (:eindex-width +eindex-width+ :cindex-width +cindex-width+ :rank-width +rank-width+
          :sub-base-width +sub-base-width+ :address-fraction +address-fraction+)
         (the (function ((unsigned-byte +eindex-width+))
                        function)
              (lambda (degrees)
                (declare (optimize (speed 3) (safety 0))
                         (type (unsigned-byte +eindex-width+) degrees))
                (the (function ((unsigned-byte +eindex-width+)) (unsigned-byte +eindex-width+))
                     (lambda (i)
                       (declare (type (unsigned-byte +eindex-width+) i))
                       (let ((iindex (the (unsigned-byte +cindex-width+)
                                          (ldb (byte +cindex-width+ +address-fraction+)
                                               i))))
                         (the (unsigned-byte +eindex-width+)
                              (dpb (the (unsigned-byte +cindex-width+)
                                        (+ iindex degrees))
                                   (byte +cindex-width+ +address-fraction+)
                                   i))))))))))
  
  (defun indexer-section (dims span pad output-shorter iwidth itype &optional is-flat)
    "Return indices of an array sectioned as with the [↑ take] or [↓ drop] functions."
    (let* ((arank (length dims))
           (dims (or dims '(1)))
           (irank (length dims))
           (isize (reduce #'* dims))
           (idims (make-array irank :element-type (if (zerop isize) t (list 'integer 0 isize))
                                    :initial-contents dims))
           (orank (* 1/2 (length span)))
           (odims (loop :for ix :below orank :for sp :across span
                        :collect (+ (- (aref span (+ ix orank)) sp)
                                    (aref pad ix)
                                    (aref pad (+ ix orank)))))
           (last-dim)
           (id-factors (make-array irank :element-type 'fixnum))
           (od-factors (make-array orank :element-type 'fixnum)))

      ;; generate dimensional factors vectors for input and output
      (loop :for dx :below irank
            :do (let ((d (aref idims (- irank 1 dx))))
                  (setf (aref id-factors (- irank 1 dx))
                        (if (zerop dx) 1 (* last-dim (aref id-factors (- irank dx))))
                        last-dim d)))
      
      (loop :for d :in (reverse odims) :for dx :from 0
            :do (setf (aref od-factors (- orank 1 dx))
                      (if (zerop dx) 1 (* last-dim (aref od-factors (- orank dx))))
                      last-dim d))
      ;; (print (list :pad odims irank dims span pad idims odims id-factors od-factors))
      (or (and (not is-flat)
               (loop :for p :across pad :always (zerop p))
               (not (eq :assign output-shorter))
               (loop :for dx :below irank :always (zerop (+ (aref span dx) (aref pad dx))))
               t)
          (and iwidth itype
               (loop :for dx :below irank
                     :append (let ((dim (- irank 1 dx))
                                   (sum (+ (aref span dx) (aref pad dx))))
                               (unless (zerop sum)
                                 (let ((encoder (gethash (list iwidth itype dim)
                                                         indexer-table-encoded)))
                                   (when encoder (list (funcall encoder sum))))))))
          ;; when indexing the take of a scalar, test for the one index that will return the scalar
          (and (zerop arank)
               (not (loop :for s :across span :always (zerop s)))
               (let ((at-index (loop :for d :in odims :for i :from 0
                                     :for p :across pad :for f :across od-factors
                                     :summing (* f (signum p)
                                                 (- d 1 (aref pad (+ i orank))))
                                       :into index :finally (return index)
                                     )))
                 (lambda (index) (when (= index at-index) index))))
          (if output-shorter
              ;; choose shorter path depending on whether input or output are larger, and
              ;; always iterate over output in the case of sub-7-bit arrays as this is necessary
              ;; to respect the segmentation of the elements
              (lambda (i)
                (let ((oindex 0) (remaining i) (valid t))
                  ;; calculate row-major offset for outer array dimensions
                  (loop :for i :below irank :while valid :for od :in odims
                        :for ifactor :across id-factors :for ofactor :across od-factors
                        :do (multiple-value-bind (index remainder) (floor remaining ifactor)
                              (let ((adj-index (- index (aref span i))))
                                (setf valid (when (< -1 adj-index od)
                                              (incf oindex (* ofactor adj-index))
                                              (setq remaining remainder))))))
                  (when valid oindex)))
              (lambda (i)
                (let ((iindex 0) (remaining i) (valid t))
                  ;; calculate row-major offset for outer array dimensions
                  (loop :for i :below irank :while valid
                        :for ifactor :across id-factors :for ofactor :across od-factors
                        :do (multiple-value-bind (index remainder) (floor remaining ofactor)
                              (let ((adj-index (+ (aref span i)
                                                  (- index (aref pad i)))))
                                (setf valid (when (< -1 adj-index (aref span (+ i irank)))
                                              (incf iindex (* ifactor adj-index))
                                              (setq remaining remainder))))))
                  (when valid iindex))))))))

(let ((default-function
        (lambda (increment vset-size degrees rlen)
          (lambda (i)
            (+ (mod i increment)
               (* vset-size (floor i vset-size))
               (let ((degree (if (integerp degrees)
                                 degrees
                                 (if (not (arrayp degrees))
                                     0 (row-major-aref
                                        degrees
                                        (+ (mod i increment)
                                           (* increment (floor i vset-size))))))))
                 (* increment (mod (+ degree (floor i increment))
                                   rlen)))))))
      (indexer-table-linear-idegree
        (intraverser
         (:lindex-width +lindex-width+ :rank-width +rank-width+
          :sub-base-width +sub-base-width+)
         (the (function ((unsigned-byte +sub-base-width+)
                         (unsigned-byte +sub-base-width+) (unsigned-byte +sub-base-width+)
                         (unsigned-byte +sub-base-width+))
                        function)
              (lambda (increment vset-size degrees rlen)
                (the (function ((unsigned-byte +lindex-width+)) (unsigned-byte +lindex-width+))
                     (lambda (i)
                       (declare (type (unsigned-byte +lindex-width+) i))
                       (the (unsigned-byte +lindex-width+)
                            (+ (the (unsigned-byte +sub-base-width+)
                                    (mod i increment))
                               (the (unsigned-byte +sub-base-width+)
                                    (* vset-size (floor i vset-size)))
                               (the (unsigned-byte +sub-base-width+)
                                    (* increment (the (unsigned-byte +sub-base-width+)
                                                      (mod (the (unsigned-byte +sub-base-width+)
                                                                (+ degrees (floor i increment)))
                                                           rlen))))))))))))
      (indexer-table-encoded-idegree
        (intraverser
         (:eindex-width +eindex-width+ :cindex-width +cindex-width+ :rank-width +rank-width+
          :sub-base-width +sub-base-width+ :address-fraction +address-fraction+)
         (the (function ((unsigned-byte +sub-base-width+) (unsigned-byte +sub-base-width+))
                        function)
              (lambda (degrees rlen)
                (declare (optimize (speed 3) (safety 0))
                         (type (unsigned-byte +sub-base-width+) degrees rlen))
                ;; (let ((byte-offset (* +cindex-width+ dindex)))
                ;; (print (list :fn degrees rlen +cindex-width+ +eindex-width+ +address-fraction+))
                (the (function ((unsigned-byte +eindex-width+)) (unsigned-byte +eindex-width+))
                     (lambda (i)
                       (declare (type (unsigned-byte +eindex-width+) i))
                       (let ((iindex (the (unsigned-byte +cindex-width+)
                                          (ldb (byte +cindex-width+ +address-fraction+)
                                               i))))
                         (the (unsigned-byte +eindex-width+)
                              (dpb (the (unsigned-byte +cindex-width+)
                                        (let ((out (the (unsigned-byte +cindex-width+)
                                                        (+ iindex degrees))))
                                          (the (unsigned-byte +cindex-width+)
                                               (if (> rlen out) out (- out rlen)))))
                                   (byte +cindex-width+ +address-fraction+)
                                   i)))))))))
      (indexer-table-encoded-flip
        (intraverser
         (:eindex-width +eindex-width+ :cindex-width +cindex-width+ :rank-width +rank-width+
          :sub-base-width +sub-base-width+ :address-fraction +address-fraction+)
         (the (function ((unsigned-byte +sub-base-width+))
                        function)
              (lambda (rlen)
                (declare (optimize (speed 3) (safety 0))
                         (type (unsigned-byte +sub-base-width+) rlen))
                ;; (let ((byte-offset (* +cindex-width+ dindex)))
                ;; (print (list :fn degrees rlen +cindex-width+ +eindex-width+ +address-fraction+))
                (the (function ((unsigned-byte +sub-base-width+)) (unsigned-byte +sub-base-width+))
                     (lambda (i)
                       (declare (type (unsigned-byte +eindex-width+) i))
                       (let ((iindex (the (unsigned-byte +cindex-width+)
                                          (ldb (byte +cindex-width+ +address-fraction+)
                                               i))))
                         (the (unsigned-byte +eindex-width+)
                              (dpb (the (unsigned-byte +cindex-width+)
                                        (- rlen 1 iindex))
                                   (byte +cindex-width+ +address-fraction+)
                                   i))))))))))
  (declare (ignore indexer-table-linear-idegree))
  
  (defun indexer-turn (axis idims iwidth itype &optional degrees)
    "Return indices of an array rotated as with the [⌽ rotate] or [⊖ rotate first] functions."
    (let* ((irank (length idims))
           (rlen (nth axis idims))
           (increment (reduce #'* (nthcdr (1+ axis) idims)))
           (vset-size (the t (* increment rlen))))
      ;; (print (list :ia (list iwidth itype axis)))
      (if degrees
          ;; TODO: implement a system for accelerated rotation when degrees are an array
          (if (integerp degrees)
              (if (= irank 1) ;; replace this case with linear optimized
                  (funcall default-function increment vset-size degrees rlen)
                  (let ((match (gethash (list iwidth itype (- irank 1 axis))
                                        indexer-table-encoded-idegree)))
                    (if match (funcall match degrees rlen)
                        (funcall default-function increment vset-size degrees rlen))))
              (lambda (i)
                (the (unsigned-byte 62)
                     (+ (the (unsigned-byte 62) (mod i increment))
                        (the (unsigned-byte 62) (* vset-size (floor i vset-size)))
                        (let ((degree (the fixnum
                                           (if (not (arrayp degrees))
                                               0 (row-major-aref
                                                  degrees
                                                  (+ (the (unsigned-byte 62)
                                                          (mod i increment))
                                                     (the (unsigned-byte 62)
                                                          (* increment (floor i vset-size)))))))))
                          (the (unsigned-byte 62)
                               (* increment (the fixnum (mod (the fixnum (+ degree (floor i increment)))
                                                             rlen)))))))))
          (if iwidth (let ((match (gethash (list iwidth itype (- irank 1 axis))
                                           indexer-table-encoded-flip)))
                       (funcall match rlen))
              (lambda (i)
                (+ (mod i increment)
                   (* vset-size (floor i vset-size))
                   (* increment (abs (- (mod (floor i increment) rlen)
                                        (1- rlen)))))))))))

(let (;; (indexer-table-regular-linear
      ;;   (intraverser
      ;;    (:lindex-width +lindex-width+ :sub-base-width +sub-base-width+
      ;;     ;; :rank +rank+
      ;;     :rank-width +rank-width+)
      ;;    (the (function (;; (simple-array (unsigned-byte +sub-base-width+) (+rank+))
      ;;                    ;; (simple-array (unsigned-byte +sub-base-width+) (+rank+))
      ;;                    vector vector
      ;;                    )
      ;;                   function)
      ;;         (lambda (od-factors s-factors)
      ;;           (declare (optimize (speed 3) (safety 0)))
      ;;           (the (function ((unsigned-byte +lindex-width+)) (unsigned-byte +lindex-width+))
      ;;                (lambda (i)
      ;;                  (declare (type (unsigned-byte +lindex-width+) i))
      ;;                  (let* ((remaining (the (unsigned-byte +lindex-width+) i))
      ;;                         (oindex (the (unsigned-byte +lindex-width+) 0)))
      ;;                    (loop :for od :across od-factors :for s :across s-factors
      ;;                          :collect (multiple-value-bind (index remainder) (floor remaining od)
      ;;                                     (incf oindex (* index s))
      ;;                                     (setq remaining remainder)))
      ;;                    oindex)))))))
      (indexer-table-regular-encoded
        (intraverser
         (:eindex-width +eindex-width+ :cindex-width +cindex-width+
          :rank-plus +rank-plus+ :rank-width +rank-width+)
         (the (function ((simple-array (unsigned-byte 8) (+rank-plus+)))
                         function)
               (lambda (indices)
                 (declare (optimize (speed 3) (safety 0))
                          (type (simple-array (unsigned-byte 8) (+rank-plus+))
                                indices)) ;; TODO: fix hardcoded type
                 (the (function ((unsigned-byte +eindex-width+)) (unsigned-byte +eindex-width+))
                      (lambda (i)
                        (declare (type (unsigned-byte +eindex-width+) i))
                        (let ((iindex (the (unsigned-byte +eindex-width+) 0)))
                          (loop :for a :of-type (unsigned-byte +cindex-width+) :across indices
                                :for n :of-type (unsigned-byte 8)
                                := (1- +rank-plus+) :then (1- n)
                                :do (setf (the (unsigned-byte +eindex-width+) iindex)
                                          (dpb (ldb (byte +cindex-width+
                                                          (* +cindex-width+ (- +rank-plus+ a 1)))
                                                    i)
                                               (byte +cindex-width+ (* n +cindex-width+))
                                               iindex)))
                          iindex)))))))
      ;; (indexer-table-diagonal-linear
      ;;   (intraverser
      ;;    (:lindex-width +lindex-width+ :sub-base-width +sub-base-width+ 
      ;;                   ;; :rank +rank+
      ;;     :rank-width +rank-width+)
      ;;    (the (function (;; (simple-array (unsigned-byte +sub-base-width+) (+rank+))
      ;;                    ;; (simple-array (unsigned-byte +rank-width+) (+rank+))
      ;;                    vector vector vector)
      ;;                   function)
      ;;         (lambda (od-factors id-factors indices)
      ;;           (the (function ((unsigned-byte +lindex-width+)) (unsigned-byte +lindex-width+))
      ;;                (lambda (i)
      ;;                  (declare (optimize (speed 3) (safety 0))
      ;;                           (type (unsigned-byte +lindex-width+) i))
      ;;                  (let ((output (the (unsigned-byte +lindex-width+) 0))
      ;;                        (remaining (the (unsigned-byte +lindex-width+) i)))
      ;;                    (loop :for ox :from 0 :for of :across od-factors
      ;;                          :do (multiple-value-bind (index remainder) (floor remaining of)
      ;;                                (loop :for a :of-type (unsigned-byte +rank-width+)
      ;;                                        :across indices
      ;;                                      :for ax :from 0 :when (= a ox)
      ;;                                      :do (incf output (* index (aref id-factors ax))))
      ;;                                (setq remaining remainder)))
      ;;                    (the (unsigned-byte +lindex-width+) output))))))))
      ;; (lambda (i)
      ;;   (let ((remaining i) (iindex 0))
      ;;     (loop :for ox :from 0 :for of :across od-factors
      ;;           :do (multiple-value-bind (index remainder) (floor remaining of)
      ;;                 (setq remaining remainder)
      ;;                 (loop :for a :in indices :for ax :from 0 :when (= a ox)
      ;;                       :do (incf iindex (* index (aref id-factors ax))))))
      ;;     iindex))
      
      (indexer-table-diagonal-encoded
        (intraverser
         (:eindex-width +eindex-width+ :cindex-width +cindex-width+
          :rank +rank+ :rank-width +rank-width+)
         (the (function ((simple-array (unsigned-byte 8) (+rank+))
                         (unsigned-byte 8))
                        function)
              (lambda (indices out-rank)
                (declare (optimize (speed 3) (safety 0))
                         (type (unsigned-byte 8) out-rank) ;; TODO: 8-bit hardcoded
                         (type (simple-array (unsigned-byte 8)) indices)
                         )
                (let ((input-rank (length indices)))
                  (declare (type (unsigned-byte 8) input-rank))
                  (the (function ((unsigned-byte +eindex-width+)) (unsigned-byte +eindex-width+))
                       (lambda (i)
                         (declare (type (unsigned-byte +eindex-width+) i))
                         (let ((output (the (unsigned-byte +eindex-width+) 0)))
                           (loop :for a :of-type (unsigned-byte 8) :across indices
                                 :for ax :of-type (unsigned-byte 8) :from 0
                                 :do (setf output (the (unsigned-byte +eindex-width+)
                                                       (dpb (ldb (byte +cindex-width+
                                                                       (* +cindex-width+
                                                                          (- out-rank 1 a)))
                                                                 i)
                                                            (byte +cindex-width+
                                                                  (* +cindex-width+
                                                                     (- input-rank 1 ax)))
                                                            output))))
                           (the (unsigned-byte +eindex-width+) output))))))))))
  
  (defun indexer-permute (idims odims alpha is-diagonal iwidth itype &optional is-inverse)
    "Return indices of an array permuted as with the [⍉ permute] function."
    (let* ((irank (length idims))
           (positions) (diagonals) (idims-reduced) (idfactor 1) (odfactor 1)
           (id-factors (make-array irank :element-type '(unsigned-byte 62) ;; TODO: remove hard-coding
                                   :initial-contents (reverse (loop :for d :in (reverse idims)
                                                                    :collect idfactor
                                                                    :do (setq idfactor
                                                                              (* d idfactor))))))
           (indices (if alpha (if (vectorp alpha)
                                  (loop :for i :across alpha :for id :in idims :for ix :from 0
                                        :do (unless (member i positions)
                                              ;; if a duplicate position is found,
                                              ;; a diagonal section is being performed
                                              (push i positions)
                                              (push id idims-reduced))
                                            ;; collect possible diagonal indices into diagonal list
                                            (if (assoc i diagonals)
                                                (push ix (rest (assoc i diagonals)))
                                                (push (list i ix) diagonals))
                                        :collect i)
                                  (progn (setq odims idims
                                               positions (cons alpha positions))
                                         (list alpha)))
                        (reverse (iota irank))))
           ;; TODO: hardcoded 8-bit rank
           (indices-vector (make-array (length indices) :element-type '(unsigned-byte 8)
                                       :initial-contents indices))
           ;; remove indices not being used for diagonal section from diagonal list
           ;; the idims-reduced are a set of the original dimensions without dimensions being elided
           ;; for diagonal section, used to get the initial output array used for diagonal section
           (od-factors (make-array (length odims)))
           (s-factors (make-array irank)))
      
      (loop :for d :in (reverse odims) :for dx :from 0
            :do (setf (aref od-factors (- (length odims) 1 dx)) odfactor
                      odfactor (* d odfactor)))

      (loop :for i :across id-factors :for ix :from 0
            :do (setf (aref s-factors (nth ix indices)) i))
      
      (if (not is-diagonal)
          ;; handle regular permutation cases
          (if is-inverse #'identity ;; selective assignment assigns all elements in a regular permute case
              (let ((match (gethash (list iwidth itype irank)
                                    indexer-table-regular-encoded)))
                (or (when match (funcall match indices-vector))
                    (lambda (i)
                      (let* ((remaining i) (oindex 0))
                        (loop :for od :across od-factors :for s :across s-factors
                              :collect (multiple-value-bind (index remainder) (floor remaining od)
                                         (incf oindex (* index s))
                                         (setq remaining remainder)))
                        oindex)))))
          ;; handle diagonal array traversals
          (if is-inverse
              (lambda (i)
                (let ((remaining i) (valid t) (factor))
                  ;; determine the presence of an input element in the
                  ;; output, used for selective assignment i.e. (1 1⍉M)←0
                  (loop :for if :across id-factors :while valid
                        :do (multiple-value-bind (index remainder) (floor remaining if)
                              (if (and factor (/= index factor))
                                  (setq valid nil)
                                  (setq remaining remainder
                                        factor (or factor index)))))
                  (when valid factor)))
              
                ;; (print (list :mm match iwidth is-diagonal indices od-factors id-factors indices-vector))
              (if iwidth (let ((match (gethash (list iwidth itype (1- irank))
                                               indexer-table-diagonal-encoded)))
                           (when match (funcall match indices-vector (length od-factors))))
                  (lambda (i)
                    (let ((remaining i) (iindex 0))
                      (loop :for ox :from 0 :for of :across od-factors
                            :do (multiple-value-bind (index remainder) (floor remaining of)
                                  (setq remaining remainder)
                                  (loop :for a :in indices :for ax :from 0 :when (= a ox)
                                        :do (incf iindex (* index (aref id-factors ax))))))
                      iindex))))))))
