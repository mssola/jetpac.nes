.segment "CODE"

;; Assuming that the 'x' register indexes an explosion on its pool, increment
;; the register as many times as to point to the next one. Bound checking is not
;; performed, it's up to the caller to implement that.
.macro NEXT_EXPLOSION_INDEX_X
    inx
    inx
    inx
.endmacro

.scope Explosions
    ;; Maximum amount of explosions allowed on screen at the same time. At
    ;; maximum it can happen that all enemies explode at the same time (3), plus
    ;; some animation (e.g. player blasting off).
    EXPLOSIONS_POOL_CAPACITY = 4 + 1

    ;; The capacity of the explosions pool in bytes.
    EXPLOSIONS_POOL_CAPACITY_BYTES = EXPLOSIONS_POOL_CAPACITY * 3

    ;; Base address for the pool of explosions used on this game. The pool has
    ;; #EXPLOSIONS_POOL_CAPACITY capacity of explosion objects where each one is
    ;; 3 bytes long:
    ;;  1. State:
    ;;     |Att- TTTT|; where:
    ;;     |
    ;;     |- A: active if 1; inactive if 0.
    ;;     |- t: tile ID.
    ;;     |- T: timer.
    ;;  2. Y coordinate.
    ;;  3. X coordinate.
    zp_pool_base = $70          ; asan:reserve EXPLOSIONS_POOL_CAPACITY_BYTES

    ;; Number of active explosions at the moment.
    zp_active = $7F

    ;; The amount of time each explosion frame will take.
    FRAME_TIME = HZ / 20

    ;; Initialize the pool of explosions for the game.
    .proc init
        lda #0
        sta Explosions::zp_active

        ldx #0
        ldy #EXPLOSIONS_POOL_CAPACITY
    @loop:
        sta Explosions::zp_pool_base, x
        NEXT_EXPLOSION_INDEX_X
        dey
        bne @loop

        rts
    .endproc

    ;; Create a new explosion object on the Y coordinates on `Globals::zp_arg2`
    ;; and the X coordinates on `Globals::zp_arg3`.
    ;;
    ;; NOTE: in the (extremely unlikely) case that no free spot is found on the
    ;; pool of objects, then nothing is done (i.e. no boom boom).
    .proc create
        ldx #0
        ldy #EXPLOSIONS_POOL_CAPACITY

    @loop:
        ;; If it's already active, then skip this spot.
        lda Explosions::zp_pool_base, x
        and #$80
        bne @next

        ;; We've got a free spot! Then just activate it and set the timer. After
        ;; that set the coordinates as given in the arguments.
        lda #($80 | FRAME_TIME)
        sta Explosions::zp_pool_base, x
        lda Globals::zp_arg2
        sta Explosions::zp_pool_base + 1, x
        lda Globals::zp_arg3
        sta Explosions::zp_pool_base + 2, x

        ;; Increase the number of active explosions and quit.
        inc Explosions::zp_active
        rts

    @next:
        NEXT_EXPLOSION_INDEX_X

        dey
        bne @loop

        rts
    .endproc

    ;; Update all active explosions.
    .proc update
        ldx #0
        ldy #EXPLOSIONS_POOL_CAPACITY

        ;; We need the 'y' register free to do faster register operations.
        sty Globals::zp_idx

    @loop:
        ;; Is it active?
        lda Explosions::zp_pool_base, x
        tay
        and #$80
        beq @next

        ;; Yes! Decrement the timer and check if it ran out.
        dey
        tya
        and #$0F
        bne @set_and_next

        ;; Timer's up! Go to the next explosion phase and check if we are done.
        tya
        clc
        adc #$20
        tay
        and #$60
        cmp #$60
        beq @explosion_done

        ;; We are not done yet. Then grab the high nibble as stored on the 'y'
        ;; register and reset the timer on the low nibble. That's our new value.
        tya
        ora #FRAME_TIME
        sta Explosions::zp_pool_base, x
        bne @next

    @explosion_done:
        ;; We are actually done. Decrement the number of active explosions and
        ;; invalidate this one.
        dec Explosions::zp_active
        ldy #0
        __fallthrough__ @set_and_next

    @set_and_next:
        sty Explosions::zp_pool_base, x

    @next:
        NEXT_EXPLOSION_INDEX_X

        dec Globals::zp_idx
        bne @loop

        rts
    .endproc

    ;; Allocate an explosion indexed by 'x' from the `Explosions::zp_pool_base`
    ;; buffer, and set it to OAM-reserved space indexed via 'y'.
    ;;
    ;; The 'y' register will be updated by increasing its value by 16,
    ;; indicating the amount of bytes allocated in OAM space.
    ;;
    ;; The 'x' register will be preserved.
    ;;
    ;; The 'Globals::zp_tmp0' and the 'Globals::zp_tmp1' memory regions are also
    ;; tampered by this function.
    ;;
    ;; NOTE: this function assumes that the explosion is in a valid
    ;; state. That's up to the caller to check before calling this function.
    .proc allocate_x_y
        ;; Preserve both indices.
        sty Globals::zp_tmp0
        stx Globals::zp_tmp1

        ;; Y coordinates for each sprite of the explosion.
        lda Explosions::zp_pool_base + 1, x
        sta OAM::m_sprites, y                       ; top left
        sta OAM::m_sprites + 4, y                   ; top right
        clc
        adc #8
        sta OAM::m_sprites + 8, y                   ; bottom left
        sta OAM::m_sprites + 12, y                  ; bottom right

        ;; Select the tile ID. It depends on the phase as defined in the 'state'
        ;; value.
        lda Explosions::zp_pool_base, x
        and #$60
        beq @first
        cmp #$20
        beq @second
        lda #$B0
        ldx #$C0
        bne @set_tile
    @first:
        lda #$70
        ldx #$80
        bne @set_tile
    @second:
        lda #$90
        ldx #$A0
        __fallthrough__ @set_tile

    @set_tile:
        sta OAM::m_sprites + 1, y                   ; top left
        clc
        adc #1
        sta OAM::m_sprites + 5, y                   ; top right

        txa
        sta OAM::m_sprites + 9, y                   ; bottom left
        inx
        txa
        sta OAM::m_sprites + 13, y                  ; bottom right

        ;; No special attributes.
        lda #0
        sta OAM::m_sprites + 2, y                   ; top left
        sta OAM::m_sprites + 6, y                   ; top right
        sta OAM::m_sprites + 10, y                  ; bottom left
        sta OAM::m_sprites + 14, y                  ; bottom right

        ;; The X-coordinate for each sprite.
        ldx Globals::zp_tmp1
        lda Explosions::zp_pool_base + 2, x         ; top left
        sta OAM::m_sprites + 3, y
        sta OAM::m_sprites + 11, y                  ; bottom left
        clc
        adc #8
        sta OAM::m_sprites + 7, y                   ; top right
        sta OAM::m_sprites + 15, y                  ; bottom right

        ;; And update the 'y' register to notify 16 bytes were stored.
        lda Globals::zp_tmp0
        clc
        adc #16
        tay

        rts
    .endproc
.endscope
