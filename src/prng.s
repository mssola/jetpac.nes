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
    .byte $25, $87, $B7, $6A, $23, $77, $6D, $71, $6D, $B6, $86, $93, $2B, $97, $A8, $39
    .byte $26, $AE, $A6, $70, $9F, $2D, $74, $B2, $8E, $A5, $33, $3E, $6D, $75, $91, $6B
    .byte $A1, $2E, $A4, $7C, $53, $28, $1E, $79, $1B, $6B, $A9, $7E, $76, $74, $90, $B3
    .byte $26, $9B, $2C, $94, $9C, $86, $7A, $B7, $1D, $B4, $72, $82, $7C, $23, $33, $78
    .byte $B0, $70, $B5, $A9, $1B, $70, $83, $28, $73, $24, $7E, $28, $B1, $8A, $75, $9B
    .byte $20, $26, $22, $8D, $7C, $3F, $29, $3D, $1F, $72, $22, $A4, $86, $34, $6F, $9C
    .byte $20, $A9, $3A, $77, $39, $6F, $3B, $86, $95, $3D, $96, $9F, $56, $84, $53, $77
    .byte $B2, $23, $72, $1C, $99, $B4, $B8, $32, $8E, $A3, $21, $20, $25, $97, $92, $2C
    .byte $3E, $96, $B5, $28, $84, $7E, $A7, $8A, $A3, $3E, $A4, $72, $A7, $A8, $6D, $A3
    .byte $AE, $7E, $23, $6E, $6A, $72, $35, $3C, $99, $B3, $37, $22, $7F, $79, $1C, $97
    .byte $52, $77, $77, $95, $B4, $7F, $2D, $28, $71, $9E, $76, $9A, $A0, $32, $23, $7F
    .byte $94, $9F, $90, $3C, $AF, $A7, $9C, $B5, $87, $9A, $9E, $84, $B0, $AD, $7D, $9D
    .byte $A2, $24, $89, $6A, $79, $81, $A2, $1E, $A9, $1E, $AB, $8D, $6E, $54, $90, $AE
    .byte $A4, $B5, $1E, $B4, $53, $9D, $7D, $78, $74, $AD, $6A, $96, $2F, $6F, $29, $9F
    .byte $98, $1D, $3B, $57, $6D, $B0, $1C, $88, $B0, $55, $99, $8F, $B1, $3F, $AD, $23
    .byte $92, $7A, $26, $55, $A3, $75, $34, $23, $20, $79, $B0, $A6, $B6, $2A, $20, $8C
