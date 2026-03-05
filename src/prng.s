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
    .byte $84, $76, $85, $80, $55, $7E, $7C, $73, $7F, $52, $79, $81, $53, $75, $3D, $51
    .byte $54, $6C, $88, $3C, $87, $6E, $57, $82, $77, $3E, $6B, $86, $6A, $3A, $3F, $83
    .byte $78, $7A, $72, $70, $7D, $6F, $6D, $71, $7B, $74, $3B, $56, $84, $76, $85, $80
    .byte $55, $7E, $7C, $73, $7F, $52, $79, $81, $53, $75, $3D, $51, $54, $6C, $88, $3C
    .byte $87, $6E, $57, $82, $77, $3E, $6B, $86, $6A, $3A, $3F, $83, $78, $7A, $72, $70
    .byte $7D, $6F, $6D, $71, $7B, $74, $3B, $56, $84, $76, $85, $80, $55, $7E, $7C, $73
    .byte $7F, $52, $79, $81, $53, $75, $3D, $51, $54, $6C, $88, $3C, $87, $6E, $57, $82
    .byte $77, $3E, $6B, $86, $6A, $3A, $3F, $83, $78, $7A, $72, $70, $7D, $6F, $6D, $71
    .byte $7B, $74, $3B, $56, $84, $76, $85, $80, $55, $7E, $7C, $73, $7F, $52, $79, $81
    .byte $53, $75, $3D, $51, $54, $6C, $88, $3C, $87, $6E, $57, $82, $77, $3E, $6B, $86
    .byte $6A, $3A, $3F, $83, $78, $7A, $72, $70, $7D, $6F, $6D, $71, $7B, $74, $3B, $56
    .byte $84, $76, $85, $80, $55, $7E, $7C, $73, $7F, $52, $79, $81, $53, $75, $3D, $51
    .byte $54, $6C, $88, $3C, $87, $6E, $57, $82, $77, $3E, $6B, $86, $6A, $3A, $3F, $83
    .byte $78, $7A, $72, $70, $7D, $6F, $6D, $71, $7B, $74, $3B, $56, $84, $76, $85, $80
    .byte $55, $7E, $7C, $73, $7F, $52, $79, $81, $53, $75, $3D, $51, $54, $6C, $88, $3C
    .byte $87, $6E, $57, $82, $77, $3E, $6B, $86, $6A, $3A, $3F, $83, $78, $7A, $72, $70
