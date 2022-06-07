;;;; package.lisp

(defpackage #:varray
  (:use #:cl)
  (:export #:varray #:varrayp #:etype-of #:shape-of #:rank-of #:indexer-of #:render
           #:vapri-integer-progression #:vapri-coordinate-identity #:vader-operate
           #:vader-select #:vader-random #:vader-deal #:vader-without #:vader-umask
           #:vader-index #:vader-shape #:vader-reshape
           #:vader-depth #:vader-first-dim #:vader-compare #:vader-enlist
           #:vader-membership #:vader-find #:vader-where #:vader-interval-index #:vader-pare
           #:vader-catenate #:vader-mix
           #:vader-split #:vader-section #:vader-enclose #:vader-partition #:vader-pick
           #:vader-intersection #:vader-unique #:vader-union #:vader-turn #:vader-permute
           #:vader-expand #:vader-grade #:vader-matrix-inverse #:vader-matrix-divide
           #:vader-encode #:vader-decode)
  (:shadowing-import-from #:aplesque #:enclose #:disclose #:disclose-unitary #:get-dimensional-factors
                          #:assign-element-type #:type-in-common #:apl-array-prototype
                          #:apply-scalar #:is-unitary #:enclose-atom #:array-compare
                          #:index-of #:alpha-compare #:grade #:array-grade #:vector-grade
                          #:xdotimes #:invert-matrix #:left-invert-matrix #:array-inner-product)
  (:shadowing-import-from #:aplesque.forms #:indexer-split #:indexer-section
                          #:indexer-expand #:indexer-turn #:indexer-permute))
