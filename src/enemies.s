.segment "CODE"

.scope Enemies
    ;; Maximum amount of enemies allowed on screen at the same time.
    ENEMIES_POOL_CAPACITY = 3

    ;; The capacity of the bullets pool in bytes.
    ENEMIES_POOL_CAPACITY_BYTES = ENEMIES_POOL_CAPACITY * 3

    ENEMIES_INITIAL_X = $F0

    ;; TODO: 3 bytes a la bullets
    zp_enemies_pool_base = $60  ; asan:reserve $09

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
        stx Globals::zp_tmp0
        jsr Prng::random_valid_y_coordinate
        ldx Globals::zp_tmp0
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

    .proc allocate_sprite_y
        ;; TODO
        rts
    .endproc

    ;; Definitions for all the enemy types. An enemy type is defined by four
    ;; bytes, containing the tile IDs for it. Some enemies only span 2 tiles,
    ;; and because of this they have $FF as filler bytes. Last but not least,
    ;; each enemy actually has two states in order to mock some inner movement.
    ;; This is also handled here and this is why an enemy spans a whooping 8
    ;; bytes of definition, which is fine because we have a lot of room to spare
    ;; in ROM space.
tiles:
    ;; Asteroid
    .byte $26, $27, $36, $37
    .byte $46, $47, $56, $57

    ;; Furry thingie
    .byte $28, $29, $38, $39
    .byte $48, $49, $58, $59

    ;; Bubble
    .byte $24, $25, $34, $35
    .byte $44, $45, $54, $55

    ;; Fighter jet 1
    .byte $2A, $2B, $3A, $3B
    .byte $2A, $2B, $3A, $3B

    ;; Fighter jet 2
    .byte $31, $32, $FF, $FF
    .byte $31, $32, $FF, $FF

    ;; UFO
    .byte $40, $41, $FF, $FF
    .byte $50, $51, $FF, $FF

    ;; Cross
    .byte $2C, $2D, $3C, $3D
    .byte $4C, $4D, $5C, $5D

    ;; Weirdo
    .byte $2E, $2F, $3E, $3F
    .byte $4E, $4F, $5E, $5F
.endscope
