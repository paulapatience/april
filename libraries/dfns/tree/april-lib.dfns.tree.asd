;;;; april-lib.dfns.tree.asd

(asdf:defsystem #:april-lib.dfns.tree
  :description "April library implementing Dyalog tree functions."
  :author "Andrew Sengul"
  :license "Apache-2.0"
  :version "0.0.1"
  :serial t
  :depends-on ("april")
  :components ((:file "package")
               (:file "setup")
               (:file "demo")))
