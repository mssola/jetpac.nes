;;;
;; Pseudo-random number implementation by using a pre-calculated table.
;;
;; I know, not too flashy, but it's good enough for this game :)

.segment "CODE"

.scope Prng
    ;; Current random value. Initialized on the title to game transition.
    zp_rand = $0A

    ;; Updates the 'a' register with the next random number set after the
    ;; current value of `zp_rand`, while also making sure that it is a valid
    ;; screen Y coordinate.
    ;;
    ;; NOTE: the 'y' register is preserved.
    .proc random_valid_y_coordinate
        ;; Get the new random number and store it right away.
        ldx zp_rand
        lda valid_y_rand_table, x
        sta zp_rand
        rts
    .endproc
.endscope


;; The pre-computed table.
;;
;; NOTE: generated via bin/rand.rb; read more on this there.
valid_y_rand_table:
    .byte $73, $54, $7E, $3F, $76, $77, $55, $72, $83, $6A, $81, $53, $52, $74, $80, $3A
    .byte $86, $3C, $87, $74, $3D, $88, $7A, $82, $54, $72, $7B, $77, $77, $75, $88, $52
    .byte $86, $6D, $80, $54, $79, $7A, $85, $7E, $82, $88, $7E, $7B, $74, $84, $71, $70
    .byte $3F, $3A, $82, $70, $75, $3D, $74, $7F, $88, $86, $83, $75, $86, $70, $55, $7A
    .byte $73, $6E, $88, $85, $6F, $7C, $3D, $3E, $55, $3B, $6C, $6D, $54, $76, $3E, $3B
    .byte $6F, $51, $7D, $73, $83, $52, $82, $7F, $72, $3A, $55, $78, $85, $3B, $86, $6A
    .byte $70, $82, $6A, $77, $3C, $76, $7C, $85, $51, $6A, $71, $6A, $78, $86, $3E, $3F
    .byte $84, $7F, $3C, $53, $73, $6C, $7E, $3A, $86, $84, $7E, $75, $53, $3B, $78, $3B
    .byte $56, $7A, $7A, $77, $85, $6E, $76, $86, $52, $85, $3B, $3D, $87, $81, $7B, $83
    .byte $86, $3E, $7F, $3E, $6A, $57, $85, $73, $88, $6A, $7B, $6E, $81, $77, $3B, $3F
    .byte $84, $3E, $55, $83, $88, $81, $55, $76, $7A, $57, $76, $7B, $6F, $7C, $76, $3E
    .byte $55, $82, $75, $75, $3F, $3E, $7E, $6C, $3F, $81, $6C, $6C, $71, $3D, $3B, $3E
    .byte $87, $7C, $85, $3E, $74, $80, $83, $3E, $80, $3B, $71, $51, $51, $6E, $53, $7B
    .byte $3D, $3D, $56, $79, $3B, $54, $7E, $6D, $3A, $81, $3E, $85, $88, $6C, $57, $85
    .byte $52, $87, $7A, $86, $82, $7D, $87, $73, $7A, $83, $70, $70, $88, $52, $80, $86
    .byte $80, $7B, $55, $53, $6A, $81, $6B, $3F, $86, $3E, $7F, $84, $55, $53, $6B, $86
