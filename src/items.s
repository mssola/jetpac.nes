.segment "CODE"

;; Assuming that the 'x' register indexes an item on its pool, increment the
;; register as many times as to point to the next one. Bound checking is not
;; performed, it's up to the caller to implement that.
.macro NEXT_ITEM_INDEX_X
    inx
    inx
    inx
.endmacro

.scope Items
    ;; Maximum amount of items allowed on screen at the same time.
    POOL_CAPACITY = 3

    ;; The amount of bytes each pool item takes.
    SIZEOF_POOL_ITEM = 3

    ;; The capacity of the items pool in bytes.
    POOL_CAPACITY_BYTES = POOL_CAPACITY * SIZEOF_POOL_ITEM

    ;; 1. State: $FF for invalid, otherwise:
    ;;   |PFD- CKKK|; where:
    ;;   |
    ;;   |- P: following the player
    ;;   |- F: falling.
    ;;   |- D: dropping: together with 'falling', but the player cannot re-grab it.
    ;;   |- C: 1: collectable (i.e. disappears on collision); 0: part (i.e. follows the player)
    ;;   |- K: object kind (00: high shuttle; 01: mid shuttle; 10: fuel; 11: regular item; 100: coin)
    ;;
    ;; 2. Y coordinate.
    ;; 3. X coordinate.
    zp_pool_base = $C0          ; asan:reserve POOL_CAPACITY_BYTES

    ;; Preserves the index on 'zp_pool_base' in Items::update().
    zp_pool_index = $C9

    ;; TODO: stabilize and document.
    ;;
    ;; Y tile | X tile | palette
    zp_current_tiles = $E7       ; asan:reserve POOL_CAPACITY_BYTES

    ;;
    ;; TODO: stabilize and document.
    ;;
    ;; |G--- FFAA|
    ;; |
    ;; |- G: the player is grabbing an item
    ;; |- F: number of falling items.
    ;; |- A: number of active items.
    zp_state = $CA

    ;; Number of shuttle parts (or fuel tanks) that have been collected so far.
    zp_collected = $CB

    ;; Coordinate where the dropping of items takes place. This comes in two
    ;; versions, as the "collision" is done in the tile coordinates so to give
    ;; some leeway to the player; but the dropping itself has to fall from the
    ;; exact screen coordinates or otherwise the dropping would feel weird.z
    DROPPING_SCREEN_X = $A8
    DROPPING_TILE_X = $15

    ;; Y screen coordinates in order for various parts to be considered as
    ;; "collected".
    MID_SHUTTLE_Y = $A7
    HIGH_SHUTTLE_Y = $97
    FUEL_SHUTTLE_Y = $C7

    .proc init
        lda Globals::zp_level_kind
        bne @other_screens
        JAL Items::init_first_screen

    @other_screens:
        ;; TODO

        rts
    .endproc

    ;; TODO: this is only to be done for the first time we enter. Otherwise this
    ;; will be reset every time.
    .proc init_first_screen
        ;; We are going to allocate two shuttle parts, and hence two items.
        lda #2
        sta Items::zp_state

        ;; We haven't collected anything yet, but it's convenient for us to mock
        ;; that the ship part on the right side of the screen is actually
        ;; collected.
        lda #1
        sta Items::zp_collected

        ;; State of the top part of the shuttle.
        ldx #0
        ldy #0
        sty Items::zp_pool_base, x

        ;; Screen and tile coordinates for the top part of the shuttle.
        lda #$4F
        sta Items::zp_pool_base + 1, x
        lsr
        lsr
        lsr
        sta Items::zp_current_tiles, x
        lda #$29
        sta Items::zp_pool_base + 2, x
        lsr
        lsr
        lsr
        sta Items::zp_current_tiles + 1, x

        ;; State of the middle part of the shuttle.
        iny
        sty Items::zp_pool_base + 3, x

        ;; Screen and tile coordinates for the middle part of the shuttle.
        lda #$67
        sta Items::zp_pool_base + 4, x
        lsr
        lsr
        lsr
        sta Items::zp_current_tiles + 3, x
        lda #$81
        sta Items::zp_pool_base + 5, x
        lsr
        lsr
        lsr
        sta Items::zp_current_tiles + 4, x

        ;; Invalidte the third item.
        ldy #$FF
        sty Items::zp_pool_base + 6, x

        ;; Palettes.
        lda #0
        sta Items::zp_current_tiles + 2, x
        sta Items::zp_current_tiles + 6, x

        rts
    .endproc

    ;; Allocate an item indexed by 'x' from the `zp_pool_base` buffer, and set
    ;; it to OAM-reserved space indexed via 'y'.
    ;;
    ;; The 'y' register will be updated by increasing its value by 16,
    ;; indicating the amount of bytes allocated in OAM space.
    ;;
    ;; The 'x' register will be _preserved_.
    ;;
    ;; NOTE: this function assumes that the item is in a valid state. That's up
    ;; to the caller to check before calling this function.
    .proc allocate_x_y
        lda Items::zp_pool_base, x
        and #$07

        ;; Should we allocate a part from the shuttle?
        bne @try_next_shuttle
        lda #$04
        JAL allocate_shuttle_x_y
    @try_next_shuttle:
        cmp #$01
        bne @try_fuel
        lda #$06
        JAL allocate_shuttle_x_y

    @try_fuel:
        ;; TODO: validate whether we need to save/restore the 'x' register.
        stx Globals::zp_tmp3
        ;; TODO
        ldx Globals::zp_tmp3
        rts
    .endproc

    ;; Allocate a shuttle part on the same terms as
    ;; Items::allocate_shuttle_x_y().
    .proc allocate_shuttle_x_y
        sta Globals::zp_tmp0

        ;; Y coordinates
        lda Items::zp_pool_base + 1, x
        sta OAM::m_sprites, y                       ; top left
        sta OAM::m_sprites + 4, y                   ; top right
        clc
        adc #8
        sta OAM::m_sprites + 8, y                   ; bottom left
        sta OAM::m_sprites + 12, y                  ; bottom right

        ;; Tile IDs
        lda Globals::zp_tmp0
        sta OAM::m_sprites + 1, y                   ; top left
        clc
        adc #1
        sta OAM::m_sprites + 5, y                   ; top right

        lda Globals::zp_tmp0
        clc
        adc #$10
        sta OAM::m_sprites + 9, y                   ; bottom left
        clc
        adc #1
        sta OAM::m_sprites + 13, y                  ; bottom right

        ;; Attributes
        lda #0
        sta OAM::m_sprites + 2, y                   ; top left
        sta OAM::m_sprites + 6, y                   ; top right
        sta OAM::m_sprites + 10, y                  ; bottom left
        sta OAM::m_sprites + 14, y                  ; bottom right

        ;; X coordinates.
        lda Items::zp_pool_base + 2, x              ; top left
        sta OAM::m_sprites + 3, y
        sta OAM::m_sprites + 11, y                  ; bottom left
        clc
        adc #8
        sta OAM::m_sprites + 7, y                   ; top right
        sta OAM::m_sprites + 15, y                  ; bottom right

        ;; And update the 'y' register.
        tya
        clc
        adc #16
        tay

        rts
    .endproc

    .proc update
        ldx #0

        ldy #POOL_CAPACITY
        sty Globals::zp_idx

        ;; The player's coordinates are cached into arguments in memory so they
        ;; can be used for collision checking. Note that we are targetting for
        ;; the center of the player, which feels at a fair point for item
        ;; interactions.
        lda Player::zp_screen_y
        clc
        adc #Player::PLAYER_WAIST
        lsr
        lsr
        lsr
        sta Globals::zp_arg0
        lda Player::zp_screen_x
        lsr
        lsr
        lsr
        clc
        adc #1
        sta Globals::zp_arg1

    @loop:
        ;; TODO: check how relevant this really is.
        stx Items::zp_pool_index

        ;; Is it valid?
        lda Items::zp_pool_base, x
        cmp #$FF
        bne @check_status
        jmp @next

    @check_status:
        ;; If it's resting, then just check for collision. Otherwise, we either
        ;; fall/drop or follow the player.
        and #$C0
        beq @check_collision
        cmp #$40
        beq @do_fall

        ;;;
        ;; Follow the player.

        ;; Neither of the above. Then, just follow the player.
        lda Player::zp_screen_y
        clc
        adc #8
        sta Items::zp_pool_base + 1, x
        lda Player::zp_screen_x
        sta Items::zp_pool_base + 2, x

        ;; Are we at the zone where we must drop items?
        ldy Globals::zp_arg1
        dey
        cpy #DROPPING_TILE_X
        beq @drop
        jmp @next

    @drop:
        ;; Yeah! Then the item stops being in 'following player' mode and is
        ;; dropped (F & D set).
        lda Items::zp_pool_base, x
        and #$7F
        ora #%01100000
        sta Items::zp_pool_base, x

        ;; Unset the 'grabbing' bit and increase the number of falling items.
        lda Items::zp_state
        and #$7F
        clc
        adc #$04
        sta Items::zp_state

        ;; And we force the item to be on the exact X screen position so to
        ;; adjust from the player's subpixel movement.
        lda #DROPPING_SCREEN_X
        sta Items::zp_pool_base + 2, x

        jmp @next

        ;;;
        ;; Fall/drop.

    @do_fall:
        ;; Update the Y coordinate so the item is falling.
        inc Items::zp_pool_base + 1, x

        ;; Is the item being dropped? If not, then we just check for collision.
        lda Items::zp_pool_base, x
        and #$20
        beq @check_collision

        ;; This is a fuel tank or a shuttle part that is aligned with the
        ;; shuttle platform. We will load in 'a' the exact screen coordinates
        ;; where each part should stop.
        lda Items::zp_pool_base, x
        and #$07
        beq @high_shuttle
        cmp #1
        beq @mid_shuttle
        lda #FUEL_SHUTTLE_Y
        bne @drop_check
    @mid_shuttle:
        lda #MID_SHUTTLE_Y
        bne @drop_check
    @high_shuttle:
        lda #HIGH_SHUTTLE_Y

    @drop_check:
        ;; Does this item reach its dropping limit? If not just go to the next
        ;; item.
        ;; TODO: It should also work for "greater than".
        cmp Items::zp_pool_base + 1, x
        bne @next

        ;; Enable the 'ppu' and the 'shuttle' flags.
        lda Globals::zp_flags
        ora #%01100000
        sta Globals::zp_flags

        ;; Decrease the number of falling/active items.
        lda Items::zp_state
        sec
        sbc #$05                ; NOTE: $04 (falling) + $01 (active)
        sta Items::zp_state

        ;; Increase the number of collected items.
        inc Items::zp_collected

        ;; And invalidate this item.
        lda #$FF
        sta Items::zp_pool_base, x

        ;; All collision checks that were needed for 'collision' mode have been
        ;; done. We can just move to the next item.
        jmp @next

    ;;;
    ;; Collision checks.

    @check_collision:
        ;; Collision with the player.
        jsr Items::collides_with_player
        beq @next
        ;; TODO: background collision (when the item is not grabbed): if it
        ;; happens, then the P, F, D are set to 0. The number of falling items
        ;; is also decreased.

        ;; A collision happened! Get collected or follow the player (if possible).
        lda Items::zp_pool_base, x
        tay
        and #$08
        beq @try_to_follow_player
        jsr Items::collect
        jmp @next

    @try_to_follow_player:
        ;; If the player is already grabbing another item, don't even try it.
        bit Items::zp_state
        bmi @next

        ;; We don't need extra precautions except when the level kind is the
        ;; first one. In that case we must guarantee the right shuttle order.
        lda Globals::zp_level_kind
        bne @do_follow_player

        ;; Is this the first shuttle part to be collected?
        lda Items::zp_collected
        cmp #1
        bne @do_follow_player

        ;; Yes! Then it _must_ be the middle part.
        lda Items::zp_pool_base, x
        and #$07
        cmp #$01
        bne @next

    @do_follow_player:
        ;; TODO: If F was set, unset it and subtract the number of falling items.

        ;; Mark this item to be in 'following' mode.
        tya
        ora #$80
        sta Items::zp_pool_base, x

        ;; Mark the player's to be already grabbing an item.
        lda Items::zp_state
        ora #$80
        sta Items::zp_state

    @next:
        NEXT_ITEM_INDEX_X
        dec Globals::zp_idx
        beq @end
        jmp @loop

    @end:
        rts
    .endproc

    ;; TODO: this assumes a 4-sprite item
    .proc collides_with_player
        ldx Items::zp_pool_index
        lda Items::zp_current_tiles, x
        cmp #$FF
        beq @no

        ;; Check for the Y tile coordinate. If it's not the same on either the
        ;; upper or the bottom parts of the item, then it's a no.
        cmp Globals::zp_arg0
        beq @check_x
        clc
        adc #1
        cmp Globals::zp_arg0
        bne @no

    @check_x:
        ;; If the Y tile coordinate checks out, let's narrow it down to the X
        ;; coordinate.
        lda Items::zp_current_tiles + 1, x
        cmp Globals::zp_arg1
        beq @yes
        clc
        adc #1
        cmp Globals::zp_arg1
        bne @no

    @yes:
        lda #1
        rts
    @no:
        lda #0
        rts
    .endproc

    ;; TODO: guarantee 'x' and 'y' safety
    .proc collect
        ;; TODO
        rts
    .endproc

    ;; Prepare the background scenary for items. Namely, the rocket parts which
    ;; belong to the background.
    ;;
    ;; NOTE: this has to be called with the PPU disabled.
    .proc prepare_scene
        ;; The low part of the rocket.
        bit PPU::m_status
        lda #$2A
        sta PPU::m_address
        lda #$F5
        sta PPU::m_address
        ldx #$0C
        stx PPU::m_data
        inx
        stx PPU::m_data

        lda #$2B
        sta PPU::m_address
        lda #$15
        sta PPU::m_address
        inx
        stx PPU::m_data
        inx
        stx PPU::m_data

        lda Globals::zp_level_kind
        beq @end

    @rest_of_the_rocket:
        jsr draw_high_part_shuttle
        jsr draw_middle_part_shuttle

    @end:
        rts
    .endproc

    ;; Update the background scenary for the shuttle.
    ;;
    ;; NOTE: this has to be called with the PPU disabled.
    .proc update_shuttle
        lda Globals::zp_level_kind
        bne @fuel

        ;; Update the shuttle.
        lda Items::zp_collected
        cmp #3
        bne @mid_shuttle
        jsr draw_high_part_shuttle
    @mid_shuttle:
        jsr draw_middle_part_shuttle
        rts

    @fuel:
        ;; TODO

        rts
    .endproc

    ;; Update the background scenary to show the middle part of the shuttle.
    ;;
    ;; NOTE: this has to be called with the PPU disabled.
    .proc draw_middle_part_shuttle
        ldx #$08
        ldy #$2A

        bit PPU::m_status
        sty PPU::m_address
        lda #$B5
        sta PPU::m_address
        stx PPU::m_data
        inx
        stx PPU::m_data

        bit PPU::m_status
        sty PPU::m_address
        lda #$D5
        sta PPU::m_address
        inx
        stx PPU::m_data
        inx
        stx PPU::m_data

        rts
    .endproc

    ;; Update the background scenary to show the high part of the shuttle.
    ;;
    ;; NOTE: this has to be called with the PPU disabled.
    .proc draw_high_part_shuttle
        ldx #$04
        ldy #$2A

        bit PPU::m_status
        sty PPU::m_address
        lda #$75
        sta PPU::m_address
        stx PPU::m_data
        inx
        stx PPU::m_data

        bit PPU::m_status
        sty PPU::m_address
        lda #$95
        sta PPU::m_address
        inx
        stx PPU::m_data
        inx
        stx PPU::m_data

        rts
    .endproc
.endscope
