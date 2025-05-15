.segment "CODE"

.scope Enemies
    ;; Maximum amount of enemies allowed on screen at the same time.
    ENEMIES_POOL_CAPACITY = 3

    ;; The capacity of the bullets pool in bytes.
    ENEMIES_POOL_CAPACITY_BYTES = ENEMIES_POOL_CAPACITY * 3

    ENEMIES_INITIAL_X = $F0

    ;; TODO: 3 bytes a la bullets
    zp_enemies_pool_base = $60

    zp_enemies_timer = $D0
    zp_enemies_pool_size = $D1

    .proc init
        ldx #0
        stx zp_enemies_timer

        ldy #ENEMIES_POOL_CAPACITY
    @enemies_init_loop:
        lda #0
        sta zp_enemies_pool_base, x

        inx
        lda #$80                ; TODO: random
        sta zp_enemies_pool_base, x

        inx
        lda #ENEMIES_INITIAL_X
        sta zp_enemies_pool_base, x

        inx

        dey
        bne @enemies_init_loop

        lda #ENEMIES_POOL_CAPACITY
        sta zp_enemies_pool_size

        rts
    .endproc

    ;; Definitions for all the enemy types. These are just the tile IDs for each
    ;; case. Note that some of them have $FF, which is because they span 2
    ;; sprites instead of 4.
tiles:
    .byte $26, $27, $36, $37
    .byte $28, $29, $38, $39
    .byte $24, $25, $34, $35
    .byte $2A, $2B, $3A, $3B
    .byte $31, $32, $FF, $FF
    .byte $41, $42, $FF, $FF
    .byte $2C, $2D, $3C, $3D
    .byte $2E, $2F, $3E, $3F
.endscope
