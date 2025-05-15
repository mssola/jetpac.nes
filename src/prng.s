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
        lda rand_table, x
        sta zp_rand

        ;; Is this value below ground?
        cmp #(Background::GROUND_Y_COORD - 16)
        bcc @check_sky

        ;; Yes! Return something that is at least above it.
        sec
        sbc #(Background::GROUND_Y_COORD - 16)
        rts

    @check_sky:
        ;; Is this value above the upper screen margin?
        cmp #Background::UPPER_MARGIN_Y_COORD
        bcs @end

        ;; Yes! Return something that is at least below it.
        clc
        adc #Background::UPPER_MARGIN_Y_COORD

    @end:
        rts
    .endproc
.endscope


;; The pre-computed table.
rand_table:
    .byte $D7, $3A, $1C, $8F, $09, $B2, $E6, $54, $A3, $91, $2B, $F5, $78, $0D, $4C, $6E
    .byte $FF, $C0, $52, $33, $6A, $E9, $9B, $1A, $47, $88, $7D, $21, $0E, $F4, $B3, $9C
    .byte $15, $67, $A8, $41, $D2, $39, $80, $76, $C9, $E5, $0A, $1B, $5F, $22, $73, $DA
    .byte $B4, $96, $3C, $E0, $8D, $F7, $2A, $05, $9E, $43, $11, $6D, $A7, $58, $C1, $32
    .byte $28, $0F, $79, $BE, $51, $64, $9D, $A9, $3B, $71, $8E, $C6, $4A, $13, $F0, $27
    .byte $E2, $5C, $06, $D3, $95, $B8, $4F, $70, $19, $A4, $6B, $38, $82, $C7, $5E, $01
    .byte $F3, $2D, $9A, $65, $7C, $D1, $0B, $E8, $57, $36, $84, $1F, $B0, $92, $45, $AC
    .byte $60, $7E, $A1, $53, $C8, $29, $D4, $FB, $07, $42, $E3, $99, $16, $8A, $3D, $C5
    .byte $24, $B1, $6F, $03, $7A, $E7, $8C, $59, $D0, $46, $93, $1E, $A5, $2C, $B7, $F1
    .byte $89, $55, $C3, $30, $62, $98, $04, $D6, $7F, $A0, $E4, $12, $3B, $81, $F9, $23
    .byte $C4, $0D, $5A, $71, $9F, $B6, $2E, $85, $37, $A9, $18, $6C, $E1, $4B, $D9, $02
    .byte $F8, $63, $B5, $40, $97, $0C, $7A, $51, $A2, $3E, $8F, $D5, $14, $69, $E0, $B8
    .byte $4D, $77, $25, $9B, $0A, $F2, $3C, $86, $E9, $1F, $68, $A3, $50, $C1, $7D, $04
    .byte $B2, $8E, $56, $1D, $73, $9C, $F5, $2A, $61, $D7, $09, $3E, $84, $A0, $E6, $1B
    .byte $3F, $C8, $94, $05, $72, $D6, $A7, $4C, $1A, $5F, $B3, $29, $80, $E1, $6D, $9E
    .byte $0C, $43, $F7, $8B, $52, $16, $A8, $3D, $91, $2B, $E5, $70, $C6, $4A, $D9, $F8
