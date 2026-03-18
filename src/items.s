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
    ;;;
    ;; Shadowed variables from the Player scope. This is mainly to be
    ;; compatible with cl65.
    zp_player_screen_y = $40    ; asan:ignore
    zp_player_screen_x = $45    ; asan:ignore
    PLAYER_WAIST  = $0C

    ;; The player's tile coordinates are also cached during the update()
    ;; function. Reserve them into their own memory regions to avoid surprises
    ;; by using the 'Globals::zp_arg0' and 'Globals::zp_arg1' variables which
    ;; are also being used by the background check.
    zp_player_tile_y = $43
    zp_player_tile_x = $48

    ;; Maximum amount of items allowed on screen at the same time.
    POOL_CAPACITY = 3

    ;; The amount of bytes each pool item takes.
    SIZEOF_POOL_ITEM = 3

    ;; The capacity of the items pool in bytes.
    POOL_CAPACITY_BYTES = POOL_CAPACITY * SIZEOF_POOL_ITEM

    ;; Base address for the pool of items used on this game. The pool has
    ;; '#Items::POOL_CAPACITY' capacity of item objects where each one is
    ;; 'Items::SIZEOF_POOL_ITEM' bytes long:
    ;;
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

    ;; Buffer which caches extra data for each item which is useful for
    ;; collision checks, or rendering the item itself. It follows the same
    ;; format as 'Items::zp_pool_base', with the same order. Thus, with the same
    ;; 'Items::zp_pool_index', you can index the same enemy on both buffers. For
    ;; each buffer we have the following:
    ;;
    ;; | tile Y | tile X | palette / tile ID |
    ;; |
    ;; |- tile Y/X: tile coordinates for the item.
    ;; |- palette: palette identifier to be used for the item.
    ;; |- tile ID: the tile ID to be used for the item as its top-left sprite.
    ;;
    ;; NOTE: palette and tile ID live on the same byte. 'palette' is on the high
    ;; nibble, and tile ID on the low nibble.
    zp_current_tiles = $E7       ; asan:reserve POOL_CAPACITY_BYTES

    ;; Bitmap which holds different boolean values for the state of items in
    ;; general.
    ;;
    ;; |GNS- --FF|
    ;; |
    ;; |- G: the player is Grabbing an item
    ;; |- N: a fuel tank is Needed.
    ;; |- S: there is a fuel tank on Screen.
    ;; |- F: number of Falling items.
    zp_state = $CA

    ;; Number of shuttle parts (or fuel tanks) that have been collected so
    ;; far. Note that parts which are now part of the background are also
    ;; computed on this variable. Hence, even the low part of the shuttle which
    ;; is always in the background is computed as a collected item. This makes
    ;; things simpler to deal with.
    zp_collected = $CB

    ;; Coordinate where the dropping of items takes place.
    DROPPING_SCREEN_X = $A8

    ;; Y screen coordinates in order for various parts to be considered as
    ;; "collected".
    MID_SHUTTLE_Y = $A7
    HIGH_SHUTTLE_Y = $97
    FUEL_SHUTTLE_Y = $B8

    ;; Constants for 'Items::zp_timer'.
    .ifdef PARTIAL
        ITEM_TIMER = HZ * 4
    .else
        ITEM_TIMER = HZ * 25
    .endif
    ITEM_TIMER_LO = ITEM_TIMER & $00FF
    ITEM_TIMER_HI = (ITEM_TIMER & $FF00) >> 8

    ;; Timer that determines when to drop a new item from the sky. It is
    ;; initialized on screen entry or after time out.
    ;;
    ;; NOTE: 16-bit integer in little-endian format.
    zp_timer = $CC              ; asan:reserve $02

    ;; Fuel tanks go into a different timer, which should be way snappier than
    ;; the default 'Items::zp_timer'. This is because in the original whenever a
    ;; fuel tank was needed, it felt down almost right away.
    FUEL_TIMER = HZ
    zp_fuel_timer = $CE

    ;; Initialize variables just before switching to the current level.
    ;;
    ;; NOTE: variables initialized here are supposed to live after
    ;; deaths. Hence, they will only be re-initialized on either after a game
    ;; over, or switching to a new level.
    .proc init_level
        ldx #0

        lda Globals::zp_level_kind
        bne @other_screens

        lda #0
        sta Items::zp_state

        ;; We haven't collected anything yet, but it's convenient for us to mock
        ;; that the ship part on the right side of the screen is actually
        ;; collected.
        lda #1
        sta Items::zp_collected

        ;; State for the top part of the shuttle.
        lda #0
        sta Items::zp_pool_base, x

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

        ;; Palettes.
        lda #0
        sta Items::zp_current_tiles + 2, x

        ;; State of the middle part of the shuttle.
        lda #1
        sta Items::zp_pool_base + 3, x

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

        ;; Palettes.
        lda #0
        sta Items::zp_current_tiles + 6, x

        beq @invalidate_third

    @other_screens:
        ;; Fuel tanks are needed, that's all.
        lda #%01000000
        sta Items::zp_state

        ;; Shuttle parts are counted as "collected". This makes the
        ;; implementation on other parts easier.
        lda #3
        sta Items::zp_collected

        ;; Invalidate the first and the second slots.
        lda #$FF
        sta Items::zp_pool_base, x
        sta Items::zp_pool_base + 3, x

    @invalidate_third:
        ;; Always invalidate the third item.
        lda #$FF
        sta Items::zp_pool_base + 6, x

        rts
    .endproc

    ;; Initialize a fresh screen.
    ;;
    ;; NOTE: this should _only_ be called whenever we initialize the
    ;; screen. This happens either when switching to it for the first time, but
    ;; also after a death. That is, unlike Items::init_level() things here are
    ;; reset for good.
    .proc init
        ;; Initialize the timer.
        lda #ITEM_TIMER_LO
        sta Items::zp_timer
        lda #ITEM_TIMER_HI
        sta Items::zp_timer + 1

        ;; Initialize the fuel timer.
        lda #Items::FUEL_TIMER
        sta Items::zp_fuel_timer

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
        bne @no_attributes
    @try_next_shuttle:
        cmp #$01
        bne @do_fuel_or_regular
        lda #$06
        bne @no_attributes

    @do_fuel_or_regular:
        ;; Is it a fuel tank?
        lda Items::zp_pool_base, x
        and #$03
        cmp #2
        bne @regular
        cmp #4
        beq @coin

        ;; Then just pick the tile from the fuel tank and pick the right
        ;; palette.
        lda #$0C
        sta Globals::zp_arg0
        lda #2
        sta Globals::zp_arg1
        JAL allocate_metasprite_x_y

    @regular:
        ;; This is a regular item
        lda Items::zp_current_tiles + 2, x
        lsr
        lsr
        lsr
        lsr
        sta Globals::zp_arg1
        lda Items::zp_current_tiles + 2, x
        and #$0F
        stx Globals::zp_tmp0
        tax
        lda regular_items, x
        ldx Globals::zp_tmp0
        sta Globals::zp_arg0
        JAL allocate_metasprite_x_y

    @coin:
        lda #$0A

    @no_attributes:
        sta Globals::zp_arg0
        lda #0
        sta Globals::zp_arg1
        JAL allocate_metasprite_x_y

    regular_items:
        ;; Tile IDs for all collectible items. Note that some of them are
        ;; repeated. This is in part to get to 8 items in total which makes the
        ;; implementation easier, but it also give more chances to some items
        ;; than some other more rare.
        .byte $62, $62, $64, $64, $66, $68, $68, $6A
    .endproc

    ;; Allocate a meta-sprite (made of 4 sprites) on the same terms as
    ;; Items::allocate_x_y(). Moreover, it expects the following parameters:
    ;;
    ;;  - Globals::zp_arg0: the tile ID.
    ;;  - Globals::zp_arg1: the attributes for each sprite.
    .proc allocate_metasprite_x_y
        ;; Y coordinates
        lda Items::zp_pool_base + 1, x
        sta OAM::m_sprites, y                       ; top left
        sta OAM::m_sprites + 4, y                   ; top right
        clc
        adc #8
        sta OAM::m_sprites + 8, y                   ; bottom left
        sta OAM::m_sprites + 12, y                  ; bottom right

        ;; Tile IDs
        lda Globals::zp_arg0
        sta OAM::m_sprites + 1, y                   ; top left
        clc
        adc #1
        sta OAM::m_sprites + 5, y                   ; top right

        lda Globals::zp_arg0
        clc
        adc #$10
        sta OAM::m_sprites + 9, y                   ; bottom left
        clc
        adc #1
        sta OAM::m_sprites + 13, y                  ; bottom right

        ;; Attributes
        lda Globals::zp_arg1
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

        ;; In 'Globals::zp_arg3' we will store the index of a free item slot. If
        ;; a free slot is found, at the end of this function the timer will be
        ;; decremented and, if it times out, then a new item will be allocated
        ;; at this stored index.
        lda #$FF
        sta Globals::zp_arg3

        ;; The loop index is kept on memory so the 'y' register can be abused
        ;; inside of it.
        ldy #POOL_CAPACITY
        sty Globals::zp_idx

        ;; The player's coordinates are cached into arguments in memory so they
        ;; can be used for collision checking. Note that we are targetting for
        ;; the center of the player, which feels at a fair point for item
        ;; interactions.
        lda zp_player_screen_y
        clc
        adc #PLAYER_WAIST
        lsr
        lsr
        lsr
        sta Items::zp_player_tile_y
        lda zp_player_screen_x
        lsr
        lsr
        lsr
        clc
        adc #1
        sta Items::zp_player_tile_x

    @loop:
        ;; This index will be valid throughout the iteration so different
        ;; functions can rely on it.
        stx Items::zp_pool_index

        ;; Is it valid?
        lda Items::zp_pool_base, x
        cmp #$FF
        bne @check_status

        ;; Save the index of this free slot.
        stx Globals::zp_arg3
        jmp @next

    @check_status:
        ;; If it's resting, then just check for collision. Otherwise, we either
        ;; fall/drop or follow the player.
        and #$C0
        bne @check_fall
        jmp @check_collision
    @check_fall:
        cmp #$40
        beq @do_fall

        ;;;
        ;; Follow the player.

        ;; Neither of the above. Then, just follow the player.
        lda zp_player_screen_y
        clc
        adc #8
        sta Items::zp_pool_base + 1, x
        lsr
        lsr
        lsr
        sta Items::zp_current_tiles, x
        lda zp_player_screen_x
        tay
        sta Items::zp_pool_base + 2, x
        lsr
        lsr
        lsr
        sta Items::zp_current_tiles + 1, x
        tya

        ;; Are we at the zone where we must drop items?
        cmp #DROPPING_SCREEN_X - 8
        bcs @may_drop
        jmp @next
    @may_drop:
        cmp #DROPPING_SCREEN_X + 8
        bcc @drop
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
        sta Items::zp_state
        inc Items::zp_state

        ;; And we force the item to be on the exact X screen position so to
        ;; adjust from the player's subpixel movement.
        lda #DROPPING_SCREEN_X
        sta Items::zp_pool_base + 2, x
        lsr
        lsr
        lsr
        sta Items::zp_current_tiles + 1, x

        jmp @next

        ;;;
        ;; Fall/drop.

    @do_fall:
        ;; Update the Y screen/tile coordinates so the item is falling.
        inc Items::zp_pool_base + 1, x
        lda Items::zp_pool_base + 1, x
        lsr
        lsr
        lsr
        sta Items::zp_current_tiles, x

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
        ;; item. Note that this also works if it's below it, as the player can
        ;; drop things from the ground too.
        cmp Items::zp_pool_base + 1, x
        bcc @is_dropped
        jmp @next

    @is_dropped:
        ;; Enable the 'ppu' and the 'shuttle' flags.
        lda Globals::zp_flags
        ora #%01100000
        sta Globals::zp_flags

        ;; Increase the number of collected items.
        inc Items::zp_collected

        ;; Now we unset the 'S' bit, which is unconditionally true regardless of
        ;; the collection state. That being said, if we still need to collect
        ;; more fuel tanks (the rocket has all its parts and we have not filled
        ;; it with all tanks), then we set the 'N' bit (and we reset the fuel
        ;; timer).
        lda Items::zp_state
        ldy Items::zp_collected
        cpy #3
        bcc @set_new_state
        cpy #9
        beq @set_new_state
        ldy #Items::FUEL_TIMER
        sty Items::zp_fuel_timer
        ora #$40
    @set_new_state:
        and #%11011111
        sta Items::zp_state

        ;; Decrease the number of falling items.
        dec Items::zp_state

        ;; Save the index of this free slot.
        stx Globals::zp_arg3

        ;; And invalidate this item.
        lda #$FF
        sta Items::zp_pool_base, x

        ;; All collision checks that were needed for 'collision' mode have been
        ;; done. We can just move to the next item.
        jmp @next

    ;;;
    ;; Collision checks.

    @check_collision:
        ;; Check collision with the player if it's alive. Otherwise let's check
        ;; for background collision.
        lda Globals::zp_flags
        and #$10
        bne @background
        jsr Items::collides_with_player
        beq @background

        ;; A collision happened! Get collected or follow the player (if possible).
        lda Items::zp_pool_base, x
        sta Globals::zp_tmp0
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
        ;; Mark this item to be in 'following' mode.
        lda Globals::zp_tmp0
        ora #$80

        ;; Moreover, if the 'falling' flag was set, unset it now, and decrease
        ;; the number of falling items.
        bit Globals::zp_tmp0
        bvc @set_modes
        and #%10111111
        dec Items::zp_state
    @set_modes:
        sta Items::zp_pool_base, x

        ;; Mark the player's to be already grabbing an item.
        lda Items::zp_state
        ora #$80
        sta Items::zp_state
        bne @next

    @background:
        ;; If it's not falling, then there's nothing to be done.
        lda Items::zp_pool_base, x
        and #$40
        beq @next

        ;; Check background collision with the bottom part of the item.
        ldy Items::zp_current_tiles, x
        iny
        iny
        sty Globals::zp_arg0
        ldy Items::zp_current_tiles + 1, x
        iny
        sty Globals::zp_arg1
        jsr Background::collides
        beq @preserve_and_next

        ;; It collides with the background! Cancel the previous downwards
        ;; movement.
        ldx Items::zp_pool_index
        dec Items::zp_pool_base + 1, x
        lda Items::zp_pool_base + 1, x
        lsr
        lsr
        lsr
        sta Items::zp_current_tiles, x

        ;; We have to unset the P, F, and D flags.
        lda Items::zp_pool_base, x
        and #$1F
        sta Items::zp_pool_base, x

        ;; And we need to decrease the number of falling items.
        dec Items::zp_state

    @preserve_and_next:
        ldx Items::zp_pool_index
    @next:
        NEXT_ITEM_INDEX_X
        dec Globals::zp_idx
        beq @decrement_timer
        jmp @loop

    @decrement_timer:
        ;; Do we have a free item slot? If not then quit.
        lda Globals::zp_arg3
        cmp #$FF
        beq @end
        tax

        ;; Yes! Decrement the counter.
        lda Items::zp_timer
        sec
        sbc #1
        sta Items::zp_timer
        lda Items::zp_timer + 1
        sbc #0
        sta Items::zp_timer + 1

        ;; If the 'N' bit is set, then we only care about the snappier
        ;; 'Items::zp_fuel_timer' value. If that timer has run out, ignore the
        ;; default one and jump right into initializing a new item (which will
        ;; be a fuel tank, as guaranteed by init_item_x()).
        lda Items::zp_state
        and #$40
        beq @check_timer
        dec Items::zp_fuel_timer
        beq @new_item_x

    @check_timer:
        ;; If it times out, initialize a new item at this position.
        lda Items::zp_timer
        bne @end
        lda Items::zp_timer + 1
        bne @end
    @new_item_x:
        stx Items::zp_pool_index
        JAL init_item_x

    @end:
        rts
    .endproc

    ;; Initialize an item from the pool as indexed by the 'x' register. The item
    ;; will be randomized unless the 'N' bit is set from 'Items::zp_state', in
    ;; which case a fuel tank will just be delivered.
    ;;
    ;; NOTE: the 'x' register is modified, but the 'y' register is not touched.
    .proc init_item_x
        ;; Reset the timer.
        lda #ITEM_TIMER_LO
        sta Items::zp_timer
        lda #ITEM_TIMER_HI
        sta Items::zp_timer + 1

        ;; We start by generating a new state. If the state is asking for a fuel
        ;; tank, let it be. Otherwise it will be a regular item.
        ;;
        ;; TODO: coin support.
        lda Items::zp_state
        and #$40
        beq @regular

        ;; While we are on the topic of having a fuel tank, update the state for
        ;; items by unsetting the N bit, and setting the S one.
        lda Items::zp_state
        and #%10111111
        ora #$20
        sta Items::zp_state

        lda #$42
        bne @set_state
    @regular:
        lda #$4B
    @set_state:
        sta Items::zp_pool_base, x

        ;; As for the Y coordinate, the sky is the limit ;)
        lda #Background::UPPER_MARGIN_Y_COORD
        sta Items::zp_pool_base + 1, x
        lsr
        lsr
        lsr
        sta Items::zp_current_tiles, x

        ;; For the X coordinate we pick a random value, mask it so we only get
        ;; four possible values, and we get the place from there.
        jsr Prng::random_valid_y_coordinate
        and #$03
        tax
        lda possible_x_positions, x
        ldx Items::zp_pool_index
        sta Items::zp_pool_base + 2, x
        lsr
        lsr
        lsr
        sta Items::zp_current_tiles + 1, x

        ;; Set the palette and a tile ID by assuming it's a regular item. Both
        ;; of these values will be picked at random. Other items will simply
        ;; ignore this byte, but for a regular item it's important. We could've
        ;; done this conditionally, but adding an extra check while preserving
        ;; some guaranteed registers and what not means more trouble than just
        ;; doing things unconditionally.
        jsr Prng::random_valid_y_coordinate
        and #$03
        asl
        asl
        asl
        asl
        sta Globals::zp_tmp0
        jsr Prng::random_valid_y_coordinate
        and #$07
        ora Globals::zp_tmp0
        ldx Items::zp_pool_index
        sta Items::zp_current_tiles + 2, x

        ;; Update the state to reflect a new falling item.
        inc Items::zp_state

        rts

    possible_x_positions:
        ;; In this order: top left platform, between left-mid platform, mid
        ;; platform, and the right platform.
        .byte $29, $50, $7F, $D0
    .endproc

    ;; Check if the item pointed by the 'x' register is colliding with the
    ;; player.
    ;;
    ;; NOTE: this assumes a 4-sprite meta-sprite, as all items are.
    .proc collides_with_player
        ldx Items::zp_pool_index
        lda Items::zp_current_tiles, x
        cmp #$FF
        beq @no

        ;; Check for the Y tile coordinate. If it's not the same on either the
        ;; upper or the bottom parts of the item, then it's a no.
        cmp Items::zp_player_tile_y
        beq @check_x
        clc
        adc #1
        cmp Items::zp_player_tile_y
        bne @no

    @check_x:
        ;; If the Y tile coordinate checks out, let's narrow it down to the X
        ;; coordinate.
        lda Items::zp_current_tiles + 1, x
        cmp Items::zp_player_tile_x
        beq @yes
        clc
        adc #1
        cmp Items::zp_player_tile_x
        bne @no

    @yes:
        lda #1
        rts
    @no:
        lda #0
        rts
    .endproc

    ;; Let go the item from the player if there is one being grabbed.
    .proc let_go_on_death
        ;; First of all, we need do check if the player was actually holding an
        ;; item.
        ldx #0
        ldy #Items::POOL_CAPACITY

    @loop:
        lda Items::zp_pool_base, x
        cmp #$FF
        beq @next
        and #$80
        bne @found

    @next:
        NEXT_ITEM_INDEX_X
        dey
        bne @loop
        rts

    @found:
        ;; The player was indeed grabbing an item. Then unset the P flag and set
        ;; the F one.
        lda Items::zp_pool_base, x
        and #$7F
        ora #$40
        sta Items::zp_pool_base, x

        ;; Unset the 'grabbing' bit, and increase the number of falling items.
        lda Items::zp_state
        and #$7F
        sta Items::zp_state
        inc Items::zp_state

        rts
    .endproc

    ;; Collect an item as indexed by 'zp_pool_index'. This function assumes that
    ;; the item is already valid.
    ;;
    ;; NOTE: the 'y' register is preserved.
    .proc collect
        ldx Items::zp_pool_index

        ;; If the collected item was actually falling down, decrease the number
        ;; of falling items.
        lda Items::zp_pool_base, x
        and #$40
        beq @invalidate
        dec Items::zp_state

    @invalidate:
        lda #$FF
        sta Items::zp_pool_base, x

        ;; TODO: score

        rts
    .endproc

    ;; Prepare the background scenary for items. Namely, the rocket parts which
    ;; belong to the background.
    ;;
    ;; NOTE: this has to be called with the PPU disabled.
    .proc prepare_background_scene
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
        lda Items::zp_collected
        cmp #9
        bne @high_middle
        bit PPU::m_status
        lda #$2B
        sta PPU::m_address
        lda #$E5
        sta PPU::m_address
        lda #%10100000
        sta PPU::m_data
        jmp @end

    @high_middle:
        lda Items::zp_collected
        cmp #8
        bcc @half_high_middle
        bit PPU::m_status
        lda #$2B
        sta PPU::m_address
        lda #$ED
        sta PPU::m_address
        lda #%10101010
        sta PPU::m_data
        bne @end

    @half_high_middle:
        lda Items::zp_collected
        cmp #7
        bcc @low_middle
        bit PPU::m_status
        lda #$2B
        sta PPU::m_address
        lda #$ED
        sta PPU::m_address
        lda #%10100010
        sta PPU::m_data
        bne @end

    @low_middle:
        lda Items::zp_collected
        cmp #6
        bcc @half_low_middle
        bit PPU::m_status
        lda #$2B
        sta PPU::m_address
        lda #$ED
        sta PPU::m_address
        lda #%10100000
        sta PPU::m_data
        bne @end

    @half_low_middle:
        lda Items::zp_collected
        cmp #5
        bcc @low
        bit PPU::m_status
        lda #$2B
        sta PPU::m_address
        lda #$ED
        sta PPU::m_address
        lda #%00100000
        sta PPU::m_data
        bne @end

    @low:
        lda Items::zp_collected
        cmp #4
        bcc @just_top
        bit PPU::m_status
        lda #$2B
        sta PPU::m_address
        lda #$F5
        sta PPU::m_address
        lda #%10101010
        sta PPU::m_data

    @just_top:
        cmp #3
        bcc @just_middle
        jsr draw_high_part_shuttle

    @just_middle:
        jsr draw_middle_part_shuttle

    @end:
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
