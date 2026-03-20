;; Jump And Link: jump to subroutine but use the return address that the caller
;; had whenever the given subroutine runs `rts`. In other words, "link" the
;; return address from the caller to the callee.
;;
;; This is in practice the same as using `jmp` but it bears the semantic
;; connotation of the `jsr` one. That is, instead of this:
;;
;;   jsr subroutine
;;   rts
;;
;; It's more adviseable to do the following for better stack management:
;;
;;   jmp subroutine
;;
;; That being said, the `jmp` instruction is also used in many other contexts,
;; and so sometimes it's needed to clarify that: "no, I have not messed up,
;; using `jmp` here instead of `jsr` is deliberate". Hence, instead of adding a
;; comment every time this small optimization is being done, use this
;; pseudo-instruction.
.macro JAL ADDR
    jmp ADDR
.endmacro

;; Pseudo-instruction from 'nasm' that is not available for 'ca65'. An empty
;; implementation is actually quite accurate, as it's just a way for 'nasm' to
;; perform extra checks when programmers want to explicitly make the code fall
;; through.
.ifndef __NASM__
    .macro __fallthrough__ arg
        ;; Nothing to do.
    .endmacro
.endif
