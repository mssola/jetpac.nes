.segment "CODE"

;; Assuming that the 'x' register indexes an enemy on its pool, increment the
;; register as many times as to point to the next one. Bound checking is not
;; performed, it's up to the caller to implement that.
.macro NEXT_ENEMY_INDEX_X
    inx
    inx
    inx
    inx
.endmacro

;; Increase the value from the enemy indexed by ADDR and the 'x' register on the
;; pool. The value will be increased at the same rate on PAL and on NTSC, even
;; if the way to guarantee that is different between these two versions.
.macro INC_MOVEMENT_X ADDR
    .ifdef PAL
        lda ADDR, x
        clc
        adc Enemies::zp_movement_arg
        sta ADDR, x
    .else
        inc ADDR, x
    .endif
.endmacro

;; Decrease the value from the enemy indexed by ADDR and the 'x' register on the
;; pool. The value will be decreased at the same rate on PAL and on NTSC, even
;; if the way to guarantee that is different between these two versions.
.macro DEC_MOVEMENT_X ADDR
    .ifdef PAL
        lda ADDR, x
        sec
        sbc Enemies::zp_movement_arg
        sta ADDR, x
    .else
        dec ADDR, x
    .endif
.endmacro

.scope Enemies
    .ifdef PAL
        ;; Shadowed from 'Driver::zp_pal_counter'.
        zp_pal_counter = $31    ; asan:ignore
    .endif

    ;; Maximum amount of enemies allowed on screen at the same time.
    ;;
    ;; NOTE: EXPLOSIONS_POOL_CAPACITY depends on this value. If you update this,
    ;; change it there.
    ENEMIES_POOL_CAPACITY = 4

    ;; The amount of bytes each pool item takes.
    SIZEOF_POOL_ITEM = 4

    ;; The capacity of the enemies pool in bytes.
    ENEMIES_POOL_CAPACITY_BYTES = ENEMIES_POOL_CAPACITY * SIZEOF_POOL_ITEM

    ;; Initial X coordinates for enemies depending on if they appear on the
    ;; left/right edge of the screen.
    ENEMIES_INITIAL_X       = $F0
    ENEMIES_INITIAL_X_RIGHT = $10

    ;; Base address for the pool of enemies used on this game. The pool has
    ;; #ENEMIES_POOL_CAPACITY capacity of enemy objects where each one is
    ;; #SIZEOF_POOL_ITEM bytes long:
    ;;  1. State: which can have two formats:
    ;;     - $FF: the enemy is not active.
    ;;     - |DIxx|xxxx|: where D is the direction bit (1: right; 0: left); and
    ;;                    the rest of bits count the number of moves from this
    ;;                    enemy. This is used to account for the inner movement
    ;;                    from an enemy sprite and, in fact, is initialized at
    ;;                    random. This counter is split in two phases depending
    ;;                    on the value of I. If I=0, then the enemy is at its
    ;;                    first inner movement state; and if I=1, then the enemy
    ;;                    is at the other inner movement state. Last but not
    ;;                    least, if D=1 and I=1, then the counter never reaches
    ;;                    the limit, as that would make the value $FF (inactive).
    ;;  2. Y coordinate.
    ;;  3. X coordinate.
    ;;  4. 'extra' state: depends on the enemy type.
    zp_pool_base = $60  ; asan:reserve ENEMIES_POOL_CAPACITY_BYTES

    ;; Base index of the enemy tiles in 'tiles' to be used. Whether to use one
    ;; row or the other for a given enemy is to be decided by its current state.
    zp_tiles = $D1

    ;; Pointer to the function that handles movement for the current enemy
    ;; type. Using a function pointer is a bit tricky on the humble 6502's
    ;; architecture, as you need to do indirect jumps with possible optimisation
    ;; tricks along the way. But there are really too many different enemy
    ;; algorithms that a plain if-else + jsr code flow would be too expensive
    ;; and harder to read.
    zp_movement_fn = $D2  ; asan:reserve $02

    ;; Preserves the index on 'zp_pool_base' for a given enemy inside of
    ;; the movement handler. Check the documentation on movement handlers.
    zp_pool_index = $D4

    ;; An extra argument for enemies which depends on their type. This is used
    ;; in two ways:
    ;;   1. Make the PAL version the same as NTSC (by incrementing its value
    ;;      when needed to match it).
    ;;   2. Re-use the same algorithms for different enemies with the same
    ;;      pattern but different velocities.
    zp_movement_arg = $D5

    ;; The palette to be used in the next enemy initialization.
    zp_palette = $D6

    ;; Checking for collision with bullets is actually way faster if after an
    ;; update we save tile coordinates for each enemy. For this, we only need to
    ;; save the tile coordinates, but notice that we actually span
    ;; #SIZEOF_POOL_ITEM bytes per enemy. That's because of padding: we are
    ;; re-using the 'Enemies::zp_pool_index' variable to index both the pool and
    ;; this buffer. Hence, identifying an enemy by 'zp_pool_index' works in both
    ;; buffers. This is extremely useful so bullets don't have to work out two
    ;; different indeces for two different structures.
    ;;
    ;; Moreover, each enemy has its own palette, and we take advantage of the
    ;; extra space from this structure by also allocating here this
    ;; information. And, again, it's convenient for the indexing on base 4.
    ;;
    ;; In summary, the internal structure for each item of this buffer is:
    ;;
    ;; | tile Y | tile X | palette | (padding) |
    ;; |
    ;; |- tile Y/X: tile coordinates for the enemy.
    ;; |- palette: the color palette to be applied to the enemy.
    ;;
    CURRENT_TILES_BYTES = ENEMIES_POOL_CAPACITY * SIZEOF_POOL_ITEM
    zp_current_tiles = $F0          ; asan:reserve CURRENT_TILES_BYTES

    ;; Cached values for the tile coordinates from the player. This is set
    ;; before enemy update, and it's then used during collision check for each
    ;; enemy.
    zp_player_tile_left = $0B
    zp_player_tile_right = $0C
    zp_player_tile_top = $0D
    zp_player_tile_waist = $0E
    zp_player_tile_bottom = $0F

    ;; Values for the counter of enemies that fall.
    ;;
    ;; NOTE: values for this have to fit into a nibble.
    FALLING_VELOCITY_0 = HZ / 5
    FALLING_VELOCITY_1 = HZ / 10
    FALLING_VELOCITY_2 = HZ / 25
    FALLING_VELOCITY_3 = HZ / 50

    ;; The amount of time it has to pass in order for a dead enemy to come back
    ;; to life.
    REVIVE_COUNTER = HZ

    ;; Initializes all the enemies for the current level. That is, it prepares
    ;; all the movement handlers, the enemy tiles to be used, and initializes
    ;; the pool of objects for it.
    .proc init
        lda Globals::zp_level_kind
        tax

        ;; Pick the right index for this type.
        asl
        asl
        asl
        asl
        sta Enemies::zp_tiles

        ;; Initialize the tiles buffer by marking it as invalid. Note that we
        ;; only initialize those positions that are actually needed. That is,
        ;; the padding is left untouched as we don't care.
        ldy #$FF
        sty Enemies::zp_current_tiles
        sty Enemies::zp_current_tiles + 1
        sty Enemies::zp_current_tiles + 4
        sty Enemies::zp_current_tiles + 5
        sty Enemies::zp_current_tiles + 8
        sty Enemies::zp_current_tiles + 9

        ;; Initialize the enemy palettes.
        iny
        sty Enemies::zp_palette
        sty Enemies::zp_current_tiles + 2
        sty Enemies::zp_current_tiles + 6
        sty Enemies::zp_current_tiles + 10

        ;; Set the movement function for this type.
        lda Enemies::movement_lo, x
        sta Enemies::zp_movement_fn
        lda Enemies::movement_hi, x
        sta Enemies::zp_movement_fn + 1

        ;; Initialize the enemy arg, which is always 1 except for homing
        ;; attacks. This initialized is increased by one on PAL if the PAL
        ;; counter requires it to.
        ldy #1
        .ifdef PAL
            lda Enemies::zp_pal_counter
            bne @skip_uptick
            iny
        @skip_uptick:
        .endif
        cpx #3
        bne @set_arg
        iny
    @set_arg:
        sty Enemies::zp_movement_arg

        __fallthrough__ init_pool
    .endproc

    ;; Initializes the enemy pool for this game.
    .proc init_pool
        ldx #0
        ldy #ENEMIES_POOL_CAPACITY
    @enemies_init_loop:
        jsr init_enemy_x
        dey
        bne @enemies_init_loop

        rts
    .endproc

    ;; Initialize the enemy from the pool as indexed by the 'x' register.
    ;;
    ;; NOTE: the 'x' register will be advanced by the amount of bytes it takes
    ;; to store an enemy on the poll (i.e. #SIZEOF_POOL_ITEM bytes).
    ;; NOTE: the 'y' register is not touched.
    .proc init_enemy_x
        ;; Pick the palette to be used for the enemy.
        lda Enemies::zp_palette
        clc
        adc #1
        and #$03
        sta Enemies::zp_palette
        sta Enemies::zp_current_tiles + 2, x

        ;; The state is set at random.
        stx Globals::zp_tmp0
        jsr Prng::random_valid_y_coordinate
        ldx Globals::zp_tmp0
        sta Enemies::zp_pool_base, x
        sta Globals::zp_tmp1

        ;; The Y coordinate is also set at random within the bounds of the
        ;; playable screen.
        jsr Prng::random_valid_y_coordinate
        ldx Globals::zp_tmp0
        inx
        sta Enemies::zp_pool_base, x

        ;; The initial X position is based on whether it's facing left or right.
        inx
        bit Globals::zp_tmp1
        bmi @facing_right
        lda #ENEMIES_INITIAL_X
        bne @set_x_position
    @facing_right:
        lda #ENEMIES_INITIAL_X_RIGHT
    @set_x_position:
        sta Enemies::zp_pool_base, x

        ;; And set the 'extra' state as passed down by the 'init' function.
        stx Globals::zp_tmp0
        jsr Enemies::generate_extra
        ldx Globals::zp_tmp0
        inx
        sta Enemies::zp_pool_base, x

        ;; Point to the next enemy.
        inx

        rts
    .endproc

    ;; Generate a value for the 'extra' value depending on the current level
    ;; kind. The result is left in 'a'.
    ;;
    ;; NOTE: the 'x' register is touched, while the 'y' register is not.
    .proc generate_extra
        ;; The value on 'extra' is basically a randomly generated value. Then we
        ;; apply two masks into that random number: one to zero out some bits,
        ;; and another to ensure some other bits are set. Hence, for a given
        ;; level we ensure that the required bits are set/unset, while letting
        ;; others to be set at random.
        jsr Prng::random_valid_y_coordinate
        ldx Globals::zp_level_kind
        and zero_out_mask, x
        ora ensure_set_mask, x
        rts

    zero_out_mask:
        .byte $0F, $01, $01, $01, $00, $01, $0F, $00
    ensure_set_mask:
        .byte $11, $00, $00, $10, $10, $00, $11, $10
    .endproc

    ;; Update the state and movement of all active enemies.
    ;;
    ;; NOTE: this function does not do collision checking with bullets as
    ;; 'Bullets::update' already accounts for it and we assume that it ran
    ;; before this one.
    .proc update
        ldx #0

        ;; Save the player's tile coordinates now as it will be useful/faster
        ;; for collision checking with each enemy. Note that some of the values
        ;; here are tuned down so the collision is not so aggresive (i.e. we
        ;; don't want to consider the whole rectangle of the player, but a
        ;; smaller area).
        lda Player::zp_screen_y
        tay
        lsr
        lsr
        lsr
        sta Enemies::zp_player_tile_top
        tya
        clc
        adc #Player::PLAYER_WAIST
        lsr
        lsr
        lsr
        sta Enemies::zp_player_tile_waist
        tya
        clc
        adc #(Player::PLAYER_WAIST + 2)
        lsr
        lsr
        lsr
        sta Enemies::zp_player_tile_bottom

        lda Player::zp_screen_x
        tay
        clc
        adc #Player::LEFT_OFFSET
        lsr
        lsr
        lsr
        sta Enemies::zp_player_tile_left
        tya
        clc
        adc #(Player::PLAYER_WIDTH / 2)
        lsr
        lsr
        lsr
        sta Enemies::zp_player_tile_right

        ;; The loop index will be moved out of the 'y' register since movement
        ;; handlers might need to use it. Note that we loop over all the pool
        ;; instead of just deciding on active ones. This is just to give dead
        ;; enemies the chance to revive.
        ldy #ENEMIES_POOL_CAPACITY
        sty Globals::zp_idx

    @loop:
        ;; Is this enemy in a 'valid' state? If so then jump into the loop body.
        lda Enemies::zp_pool_base, x
        cmp #$FF
        bne @loop_body

        ;; No! Then tick down the counter. If it reaches zero, then it's time
        ;; to revive this enemy slot.
        dec Enemies::zp_pool_base + 3, x
        bne @increase_index_next

        ;; Initialize the slot as a new 'valid' enemy.
        jsr init_enemy_x

        ;; The above 'init_enemy_x' call already updates the 'x' register to the
        ;; next enemy. Jump to '@next', not '@increase_index_next'.
        jmp @next

    @loop_body:
        ;; If its movement state is already at the maximum, reset it, otherwise
        ;; increase it by 1. Note that we compare with $7E instead of $7F
        ;; because the latter would be equal to $FF if we accounted for the
        ;; direction bit and it could be confused with the "invalid"
        ;; state. Hence, the second phase of the inner movement has one frame
        ;; less of time than the other, but whatever. We also 'and' it with $7E
        ;; to avoid the direction bit to affect the comparison.
        sta Globals::zp_tmp0
        and #$7E
        cmp #$7E
        beq @reset
        inc Enemies::zp_pool_base, x
        bne @move
    @reset:
        lda Globals::zp_tmp0
        and #$80
        sta Enemies::zp_pool_base, x

    @move:
        ;; Store the index to the current enemy.
        stx Enemies::zp_pool_index

        ;; Jump to the movement handler for the current enemy. As to why this
        ;; needs to be in a function pointer, refer to
        ;; 'zp_movement_fn'. Note that this could've been done in other
        ;; ways. Here we fake a 'jsr' by pushing the address to return into the
        ;; stack (-1 to account for the 'rts' behavior of adding +1 to the PC),
        ;; and then calling the function pointed by 'zp_movement_fn'. Then
        ;; this function can act as usual and perform an 'rts' at the end.
        ;;
        ;; Since the return address is always the same, maybe the movement
        ;; handler could've done a 'jmp <fixed address>', but that would mean to
        ;; know the exact address for '@return_from_movement_handler', and that
        ;; would mean to move everything out of .proc and .scope. That would be
        ;; my way to go if performance was paramount at this point, as it would
        ;; save: (2 x lda's: 4 cycles; 2 x pha's: 6 cycles; 1 x rts: 6 cycles) =
        ;; 16 cycles - indirect jump from handler (5 cycles). Hence 11 cycles of
        ;; performance gain per iteration. We are not at the point of requiring
        ;; these cycles for now and, given the luxury, I take readability first.
        ;;
        ;; Another approach would be to introduce a "trampoline" function, but
        ;; that would be the same as here plus an extra 'jsr' to the trampoline
        ;; (and an extra cycle considering that the 'rts' at the trampoline is
        ;; slower than an indirect 'jmp'). Another approach would've been the
        ;; "rts trick", but I feel that it's only useful at the tail of a
        ;; function, and this whole ordeal is happening inside of a loop, so we
        ;; don't want to break it just yet.
        lda #.hibyte(@return_from_movement_handler - 1)
        pha
        lda #.lobyte(@return_from_movement_handler - 1)
        pha
        jmp (zp_movement_fn)

    @return_from_movement_handler:
        ;; Restore the value from the 'x' register.
        ldx Enemies::zp_pool_index

        ;; The enemy might have been burst to dust due to ground
        ;; collision. Let's check it here and skip player collision if that's
        ;; the case. This is not just an optimization detail, but otherwise we
        ;; might get two explosions on the corner case of an enemy exploding due
        ;; to background collision and colliding with the player at the same.
        lda Enemies::zp_pool_base, x
        cmp #$FF
        beq @increase_index_next

        ;; Save the current tile coordinates for this enemy.
        lda Enemies::zp_pool_base + 1, x
        lsr
        lsr
        lsr
        sta Enemies::zp_current_tiles, x
        lda Enemies::zp_pool_base + 2, x
        lsr
        lsr
        lsr
        sta Enemies::zp_current_tiles + 1, x

        ;; Does this enemy collide with the player?
        jsr Enemies::collides_with_player
        beq @increase_index_next

        ;; Ooops, the player just kicked the bucket! Call the handlers for the
        ;; enemy and the player and return early.
        jsr Enemies::bite_the_dust
        JAL Player::die_bart_die

    @increase_index_next:
        ;; Move the 'x' register to the current enemy for this iteration.
        NEXT_ENEMY_INDEX_X

    @next:
        ;; Any more enemies left?
        dec Globals::zp_idx
        bne @loop

        rts
    .endproc

    ;; Allocate an enemy indexed by 'x' from the `zp_pool_base` buffer,
    ;; and set it to OAM-reserved space indexed via 'y'.
    ;;
    ;; The 'y' register will be updated by increasing its value by 16,
    ;; indicating the amount of bytes allocated in OAM space.
    ;;
    ;; The 'x' register will be changed, so make sure to back it up if you care
    ;; about its value before calling this function.
    ;;
    ;; The 'Globals::zp_tmp0', 'Globals::zp_tmp1' and 'Globals::zp_tmp2' memory
    ;; regions are also tampered by this function.
    ;;
    ;; NOTE: this function assumes that the enemy is in a valid state. That's up
    ;; to the caller to check before calling this function.
    .proc allocate_x_y
        ;; Y coordinates for each sprite of the enemy.
        lda Enemies::zp_pool_base + 1, x
        sta OAM::m_sprites, y                       ; top left
        sta OAM::m_sprites + 4, y                   ; top right
        clc
        adc #8
        sta OAM::m_sprites + 8, y                   ; bottom left
        sta OAM::m_sprites + 12, y                  ; bottom right

        ;; The next thing to account is where the enemy is facing. This will
        ;; change the tile set to be picked (e.g. 1st/2nd vs 3rd/4th rows of
        ;; tile IDs definitions); but it also changes whether the enemy needs to
        ;; be horizontally mirrored by the PPU or not. For the logic we make use
        ;; of temporary memory regions that will help us along the way, and we
        ;; start like this.
        lda Enemies::zp_pool_base, x
        sta Globals::zp_tmp2

        ;; Push the palette to be used into the stack. This will be pulled down
        ;; below.
        lda Enemies::zp_current_tiles + 2, x
        pha

        ;; Preserve the index on the pool and load the one for enemy tiles.
        stx Globals::zp_tmp1
        ldx zp_tiles

        ;; Check on the direction bit from the enemy's state. If facing right,
        ;; then the 'x' register will be increased by 8 (pointing then to the
        ;; 3rd/4th rows of the enemy tiles ID definitions), and 'a' will have
        ;; the value for the third byte of the sprite (i.e. whether to mirror or
        ;; not the sprite at the PPU level).
        bit Globals::zp_tmp2
        bmi @face_right
        pla
        jmp @set_state
    @face_right:
        txa
        clc
        adc #8
        tax
        pla
        ora #%01000000
    @set_state:
        sta OAM::m_sprites + 2, y                   ; top left
        sta OAM::m_sprites + 6, y                   ; top right
        sta OAM::m_sprites + 10, y                  ; bottom left
        sta OAM::m_sprites + 14, y                  ; bottom right

        ;; If the counter for the enemy's state is already at its second phase,
        ;; increase 'x' by 4 to reflect that it needs to pick the "other" state
        ;; from the tiles ID definitions. Then load all four bytes of tile IDs
        ;; and store them appropiately.
        lda Globals::zp_tmp2
        and #$40
        beq @set_facing
        txa
        clc
        adc #4
        tax
    @set_facing:
        lda tiles, x
        sta OAM::m_sprites + 1, y                   ; top left
        lda tiles + 1, x
        sta OAM::m_sprites + 5, y                   ; top right
        lda tiles + 2, x
        sta OAM::m_sprites + 9, y                   ; bottom left
        lda tiles + 3, x
        sta OAM::m_sprites + 13, y                  ; bottom right

        ;; The X-coordinate for each sprite.
        ldx Globals::zp_tmp1
        lda Enemies::zp_pool_base + 2, x    ; top left
        sta OAM::m_sprites + 3, y
        sta OAM::m_sprites + 11, y                  ; bottom left
        clc
        adc #8
        sta OAM::m_sprites + 7, y                   ; top right
        sta OAM::m_sprites + 15, y                  ; bottom right

        ;; And update the 'y' register to notify 16 bytes were stored.
        tya
        clc
        adc #16
        tay

        rts
    .endproc

    ;; Given a tile coordinate via 'Globals::zp_arg0' (Y) and 'Globals::zp_arg1'
    ;; (X), and an enemy pointed by the 'Enemies::zp_pool_index' index, set to
    ;; 'a' if the given coordinate collides with the referenced enemy.
    ;;
    ;; NOTE: the 'x' register is being touched. Everything else is left
    ;; untouched.
    .proc collides
        ;; Fetch the Y tile coordinate. If it's not valid return early.
        ldx Enemies::zp_pool_index
        lda Enemies::zp_current_tiles, x
        cmp #$FF
        beq @no

        ;; Check for the Y tile coordinate. If it's not the same on either the
        ;; upper or the bottom parts of the enemy, then it's a no.
        cmp Globals::zp_arg0
        beq @check_x
        clc
        adc #1
        cmp Globals::zp_arg0
        bne @no

    @check_x:
        ;; If the Y tile coordinate checks out, let's narrow it down to the X
        ;; coordinate.
        lda Enemies::zp_current_tiles + 1, x
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

    ;; Sets 'a' to 1 if the current enemy collides with the player, 0 otherwise.
    .proc collides_with_player
        ;; Top left/right are done only once because the top of the player is
        ;; just the head, which in anchored to one side. Hence, depending on
        ;; where the player is heading, we will check for top left or right.
        bit Player::zp_state
        bvs @set_left
        lda Enemies::zp_player_tile_right
        bne @store_top
    @set_left:
        lda Enemies::zp_player_tile_left
    @store_top:
        sta Globals::zp_arg1
        lda Enemies::zp_player_tile_top
        sta Globals::zp_arg0
        jsr collides
        bne @end

        ;; Waist left
        lda Enemies::zp_player_tile_left
        sta Globals::zp_arg1
        lda Enemies::zp_player_tile_waist
        sta Globals::zp_arg0
        jsr collides
        bne @end

        ;; Bottom left
        lda Enemies::zp_player_tile_bottom
        sta Globals::zp_arg0
        jsr collides
        bne @end

        ;; Waist right
        lda Enemies::zp_player_tile_right
        sta Globals::zp_arg1
        lda Enemies::zp_player_tile_waist
        sta Globals::zp_arg0
        jsr collides
        bne @end

        ;; Bottom right
        lda Enemies::zp_player_tile_bottom
        sta Globals::zp_arg0
        jsr collides

    @end:
        rts
    .endproc

    ;; The enemy has been set to dust, remove it.
    ;;
    ;; NOTE: the 'x' register is modified, the 'y' register is _preserved_.
    .proc bite_the_dust
        ;; This function might be called by loops which abuse index
        ;; registers. Luckily that's not the case for the 'x' register, but at
        ;; least the loop on Bullets::update() does heavy use of the 'y'
        ;; register. Preserve it now on the stack.
        tya
        pha

        ;; Invalidate this enemy.
        lda #$FF
        ldx Enemies::zp_pool_index
        sta Enemies::zp_pool_base, x
        sta Enemies::zp_current_tiles, x
        sta Enemies::zp_current_tiles + 1, x

        ;; Create an explosion for this enemy.
        lda Enemies::zp_pool_base + 1, x
        sta Globals::zp_arg2
        lda Enemies::zp_pool_base + 2, x
        sta Globals::zp_arg3
        jsr Explosions::create

        ;; The 'extra' value is now a "revive counter". Whenever it times out
        ;; this enemy will be eligible to go back to life.
        lda #REVIVE_COUNTER
        ldx Enemies::zp_pool_index
        sta Enemies::zp_pool_base + 3, x

        ;; Restore back the value for the 'y' register.
        pla
        tay

        rts
    .endproc

    ;;;
    ;; Movement handlers.
    ;;
    ;; Each enemy type has a function assigned to it as to how to move. These
    ;; functions are stored in the 'movement_lo' and 'movement_hi' ROM addresses
    ;; and they are used via the 'zp_movement_fn' function pointer. Movement
    ;; handlers are free to use any register and any memory location, as that's
    ;; handled by the caller.
    ;;
    ;; Collision only needs to be checked with platforms, as each handler might
    ;; have a different take on that scenario. Collision with bullets are
    ;; handled in the Bullets scope, and with the player is handled by the
    ;; caller.
    ;;
    ;; All handlers receive 'Enemies::zp_pool_index' which contain the index to
    ;; the 'Enemy::zp_pool_base' array of the current enemy. This argument is
    ;; expected to be _immutable_; if you want to abuse the 'x' register, you
    ;; are free to do so. For other arguments handlers are expected to abuse on
    ;; the 'extra' state that is available for each enemy.

    ;; Basic falling movement. Straight horizontal movement with a slight
    ;; downward angle. Enemy should explode on platform/ground contact. The
    ;; 'extra' state is defined as follows:
    ;;
    ;;   |TTTT KK-D|; where:
    ;;   |
    ;;   |- D: downwards if 1; upwards if 0.
    ;;   |- K: movement kind (see the constants FALLING_VELOCITY_*).
    ;;   |- T: timer. Whenever it reaches zero, then a vertical movement is done.
    ;;
    .proc basic
        ;; First of all, we always move enemies horizontally, while being
        ;; mindful on the direction and the step depending on the enemy type.
        lda Enemies::zp_pool_base, x
        and #$80
        beq @move_left
        INC_MOVEMENT_X Enemies::zp_pool_base + 2
        jmp @do_counter
    @move_left:
        DEC_MOVEMENT_X Enemies::zp_pool_base + 2

        ;; Decrement the counter from the 'extra' state. If it reaches zero,
        ;; then we should do some downward movement. Otherwise we just go to
        ;; collision checking.
    @do_counter:
        lda Enemies::zp_pool_base + 3, x
        tay
        sec
        sbc #$10
        and #$F0
        bne @update_extra_state

        ;; Move upwards/downwards and reset the 'extra' state depending on the
        ;; enemy kind.
        tya
        and #$01
        beq @up
        INC_MOVEMENT_X Enemies::zp_pool_base + 1
        jmp @compute_next_counter
    @up:
        DEC_MOVEMENT_X Enemies::zp_pool_base + 1

    @compute_next_counter:
        ;; Yes, doing an index on a pre-computed ROM table would've been faster,
        ;; but I need the 'x' register and I didn't feel like doing funny
        ;; dances when it's not so bad.
        tya
        and #$0C
        beq @init_zero
        cmp #$04
        beq @init_one
        cmp #$08
        beq @init_two
        lda #(FALLING_VELOCITY_3 << 4)
        bne @update_extra_state
    @init_zero:
        lda #(FALLING_VELOCITY_0 << 4)
        bne @update_extra_state
    @init_one:
        lda #(FALLING_VELOCITY_1 << 4)
        bne @update_extra_state
    @init_two:
        lda #(FALLING_VELOCITY_2 << 4)

    @update_extra_state:
        ;; Save the new timer into a temporary value, mask out the high byte
        ;; from the original value, and then merge the values.
        sta Globals::zp_tmp0
        tya
        and #$0F
        ora Globals::zp_tmp0
        sta Enemies::zp_pool_base + 3, x

        ;; Check collisions with the background. The check is pretty dumb and we
        ;; just check all four corners, as trying to be smart about it became
        ;; too complex for what I needed (and the dumb approach is actually not
        ;; that slow).

        ;; Translate the X coordinate into tile ones.
        lda Enemies::zp_pool_base + 2, x
        lsr
        lsr
        lsr
        sta Globals::zp_arg1

        ;; Translate the Y coordinate into tile ones.
        lda Enemies::zp_pool_base + 1, x
        lsr
        lsr
        lsr
        sta Globals::zp_arg0

        ;; Perform a collision check with the upper left boundary.
        jsr Background::collides
        beq @check_up_right
        JAL Enemies::bite_the_dust

    @check_up_right:
        ;; Increase the X tile coordinate to check for the upper right boundary.
        inc Globals::zp_arg1
        jsr Background::collides
        beq @check_down
        JAL Enemies::bite_the_dust

    @check_down:
        ;; Now let's go for bottom boundaries. The notion of "bottom" is
        ;; different if it's the regular 'basic' enemy or it's the fighter jet
        ;; re-using this algorithm. That's why if the level kind is 3 the bottom
        ;; is increased by one and not twice.
        inc Globals::zp_arg0
        ldy Globals::zp_level_kind
        cpy #3
        beq @skip_second_inc
        inc Globals::zp_arg0

    @skip_second_inc:
        ;; And the actual check.
        jsr Background::collides
        beq @check_down_left
        JAL Enemies::bite_the_dust

    @check_down_left:
        ;; So now the only corner left is the bottom left one. Adjust the X tile
        ;; coordinate and try again.
        dec Globals::zp_arg1
        jsr Background::collides
        beq @end
        JAL Enemies::bite_the_dust

    @end:
        rts
    .endproc

    ;; Diagonal bouncing at a 45 degree angle. The 'extra' state is a boolean
    ;; which is set to 0 if moving upwards, and to 1 if moving downwards.
    .proc bounce
        ;; First of all, we always move enemies horizontally, while being
        ;; mindful on the direction and the step depending on the enemy
        ;; type. This is just the same as the 'basic' algorithm.
        lda Enemies::zp_pool_base, x
        and #$80
        beq @move_left
        INC_MOVEMENT_X Enemies::zp_pool_base + 2
        jmp @do_vertical
    @move_left:
        DEC_MOVEMENT_X Enemies::zp_pool_base + 2

    @do_vertical:
        ;; The vertical movement works the same way, but taking into account its
        ;; direction via the 'extra' state. Note that we mask it, which is not
        ;; needed for the main enemies which use this algorithm, but it is for
        ;; the 'erratic' algorithm which re-uses this one.
        lda Enemies::zp_pool_base + 3, x
        and #$01
        beq @move_up
        INC_MOVEMENT_X Enemies::zp_pool_base + 1
        jmp @check_collision
    @move_up:
        DEC_MOVEMENT_X Enemies::zp_pool_base + 1

        ;; Collision checking.
    @check_collision:
        ;; Translate the Y axis into tile coordinates.
        lda Enemies::zp_pool_base + 1, x
        lsr
        lsr
        lsr
        sta Globals::zp_arg0

        ;; Translate the X axis into tile coordinates. We will also save it into
        ;; 'Globals::zp_tmp0' as that will save us some trouble down the road.
        lda Enemies::zp_pool_base + 2, x
        lsr
        lsr
        lsr
        sta Globals::zp_arg1
        sta Globals::zp_tmp0

        ;; Does this upper left corner collide?
        jsr Background::collides
        bne @bounce_down

        ;; No. Increment the X coordinate to the right corner and ask again.
        inc Globals::zp_arg1
        inc Globals::zp_arg1
        jsr Background::collides
        beq @prepare_check_front_collision

        ;; There was a (hopefully purely) upper collision!
    @bounce_down:
        ;; The previous 'Background::collides' call has tampered with the 'x'
        ;; register. Load the proper value again.
        ldx Enemies::zp_pool_index

        ;; Flip 'extra' boolean.
        lda Enemies::zp_pool_base + 3, x
        eor #1
        sta Enemies::zp_pool_base + 3, x

        ;; Move downwards once, which cancels the movement set at the beginning
        ;; of the function.
        INC_MOVEMENT_X Enemies::zp_pool_base + 1

        rts

    @prepare_check_front_collision:
        ;; We are checking the "front" (center) of the enemy, which corresponds
        ;; to the regular sized enemy. This means to increase the Y tile
        ;; coordinate once.
        inc Globals::zp_arg0

        ;; Is the enemy moving left or right? This is relevant because the X
        ;; tile coordinate is set to the right corner. If it's moving left, then
        ;; we need to decrement it twice to move it back to the left corner.
        ldx Enemies::zp_pool_index
        lda Enemies::zp_pool_base, x
        and #$80
        bne @check_front_collision
        dec Globals::zp_arg1
        dec Globals::zp_arg1

    @check_front_collision:
        ;; Does it collide frontally?
        jsr Background::collides
        beq @check_bottom

        ;; Yes! Restore the 'x' after the 'Background::collides' and use it to
        ;; flip the direction where the enemy is headed.
        ldx Enemies::zp_pool_index
        lda Enemies::zp_pool_base, x
        eor #$80
        sta Enemies::zp_pool_base, x

        ;; And bounce already to the new direction to avoid the enemy getting
        ;; stucked or other weird situations.
        and #$80
        beq @bounce_left
        INC_MOVEMENT_X Enemies::zp_pool_base + 2
        rts
    @bounce_left:
        DEC_MOVEMENT_X Enemies::zp_pool_base + 2
        rts

        ;; Last but not least, let's see if the enemy collides on its bottom
        ;; corners.
    @check_bottom:
        ;; Restore the X tile coordinate as the previous steps might have left
        ;; it in an unknown state.
        lda Globals::zp_tmp0
        sta Globals::zp_arg1

        ;; Increse the Y tile coordinate. Note that this is to be done
        ;; regardless to the enemy type, in contrast to what we did when we were
        ;; wondering about checking the front.
        inc Globals::zp_arg0

        ;; And check for a collision on the bottom left corner.
        jsr Background::collides
        bne @bounce_up

        ;; Nope! Try again but with the bottom right corner.
        inc Globals::zp_arg1
        inc Globals::zp_arg1
        jsr Background::collides
        bne @bounce_up
        rts

        ;; There was a (hopefully purely) bottom collision!
    @bounce_up:
        ;; Restore the 'x' register from a previous 'Background::collides' call.
        ldx Enemies::zp_pool_index

        ;; Flip the 'extra' boolean.
        lda Enemies::zp_pool_base + 3, x
        eor #1
        sta Enemies::zp_pool_base + 3, x

        ;; Make it bounce up.
        DEC_MOVEMENT_X Enemies::zp_pool_base + 1

        rts
    .endproc

    ;; Erratic movement, which sometimes stops, sometimes moves horizontally,
    ;; and some other times it goes diagonally; all at random. The 'extra' state
    ;; is laid out as follows:
    ;;
    ;;   |TTTT -AAD|; where:
    ;;   |
    ;;   |-  D: downwards if 1; upwards if 0.
    ;;   |- AA: current algorithm: 00/11: stop; 01: horizontal; 10: diagonal.
    ;;   |-  T: timer for algorithm. Whenever it reaches zero the algorithm is changed.
    ;;
    .proc erratic
        ;; Check the timer.
        lda Enemies::zp_pool_base + 3, x
        and #$F0
        bne @do

        ;; The 'extra' state has to change. In order to do this we prepare an
        ;; "or" mask that will be paired to the change of the algorithm in the
        ;; following code block. Not that this mask is shifted to the right, as
        ;; the end computation will finally shift it left once. This mask is
        ;; responsible for initializing the timer to 1, and the algorithm to 1
        ;; if we are coming from a "stop" phase (i.e. we want to guarantee that
        ;; the next state is not "stop" again).
        lda Enemies::zp_pool_base + 3, x
        ldx #$08
        and #%00000110
        bne @after_unpause
        inx
    @after_unpause:
        stx Globals::zp_tmp0

        ;; Pick a random value and mask it to get the possible algorithms. If
        ;; the algorithm is "stop" and we were already coming from that phase,
        ;; the mask we prepared in the temporary value will take care of at
        ;; least going into another state.
        jsr Prng::random_valid_y_coordinate
        and #$03
        ora Globals::zp_tmp0
        asl
        sta Globals::zp_tmp0

        ;; Restore the 'x' register from the previous
        ;; 'Prng::random_valid_y_coordinate' call.
        ldx Enemies::zp_pool_index

        ;; The previous temporary value missed the D bit. Let's add it now and
        ;; store it.
        lda Enemies::zp_pool_base + 3, x
        and #$01
        clc
        adc Globals::zp_tmp0
        sta Enemies::zp_pool_base + 3, x
        rts

    @do:
        ;; Blindly increase the timer as overflows will be covered when entering
        ;; this function.
        lda Enemies::zp_pool_base + 3, x
        clc
        adc #$10
        sta Enemies::zp_pool_base + 3, x

        ;; Now switch what to do depending on the algorithm.
        and #%00000110
        bne @next_algo_1
        rts
    @next_algo_1:
        cmp #%00000110
        bne @next_algo_2
        rts
    @next_algo_2:
        and #%00000100
        beq @horizontal

        ;; For the diagonal algorithm simply call the one we've got which
        ;; shouldn't mess with our 'extra' state from this one.
        JAL bounce

    @horizontal:
        ;; The 'y' register is used as a way to increment the X tile coordinates
        ;; during collision checking. Since we have to know the direction first
        ;; of all, we can take advantage of it and increment it whenever we are
        ;; moving right.
        ldy #0

        ;; Plain old horizontal movement as it's done in other places.
        lda Enemies::zp_pool_base, x
        and #$80
        beq @move_left
        iny
        iny
        INC_MOVEMENT_X Enemies::zp_pool_base + 2
        jmp @after_horizontal
    @move_left:
        DEC_MOVEMENT_X Enemies::zp_pool_base + 2

    @after_horizontal:
        ;; We store in a temporary value how much the X tile coordinates will
        ;; have to be increased in order to point to the right face.
        sty Globals::zp_tmp0

        ;; After that has been done, check for collision.

        ;; Translate the Y axis into tile coordinates.
        lda Enemies::zp_pool_base + 1, x
        lsr
        lsr
        lsr
        sta Globals::zp_arg0

        ;; Translate the X axis into tile coordinates, while adding the facing
        ;; value we computed earlier.
        lda Enemies::zp_pool_base + 2, x
        lsr
        lsr
        lsr
        clc
        adc Globals::zp_tmp0
        sta Globals::zp_arg1

        ;; Top.
        jsr Background::collides
        bne @horizontal_collision

        ;; Center.
        inc Globals::zp_arg0
        jsr Background::collides
        bne @horizontal_collision

        ;; Bottom.
        inc Globals::zp_arg0
        jsr Background::collides
        bne @horizontal_collision
        rts

    @horizontal_collision:
        ;; Restore the 'x' register from a previous 'Background::collides' call.
        ldx Enemies::zp_pool_index

        ;; Flip the direction bit.
        lda Enemies::zp_pool_base, x
        eor #$80
        sta Enemies::zp_pool_base, x

        ;; And bounce already to the new direction to avoid the enemy getting
        ;; stucked or other weird situations.
        and #$80
        beq @bounce_left
        INC_MOVEMENT_X Enemies::zp_pool_base + 2
        rts
    @bounce_left:
        DEC_MOVEMENT_X Enemies::zp_pool_base + 2
        rts
    .endproc

    ;; Track the player's current Y position and homes at it when the Y position
    ;; matches that of the player. The 'extra' state is laid out as follows:
    ;;
    ;;   |TTTT ttSD|; where:
    ;;   |
    ;;   |-  D: downwards if 1; upwards if 0.
    ;;   |-  S: state: 0: moving up/down; 01: homing.
    ;;   |- tt: number of times TT has run out. When it reaches '11', then we
    ;;   |      change from the zero state to homing.
    ;;   |- TT: timer for upwards/downwards movement.
    ;;
    ;; NOTE: whenever we transition to homing attack, then the 'extra' state
    ;; follows the one from 'basic'. Notice that bit 1 is untouched by the
    ;; 'basic' algorithm, which is used here to determine that we are in the
    ;; 'homing' state.
    .proc homing
        ;; First of all, get the state of the enemy. If it's already on the
        ;; 'homing' state, then just jump-and-link to the 'basic'
        ;; algorithm. Otherwise we stay on this function.
        ;;
        ;; NOTE: this function needs to use the original 'extra' value a
        ;; lot. Save it on the 'y' register since it's never used
        ;; otherwise. Going forward notice all the 'tya', which simply mean "get
        ;; the original 'extra' value".
        lda Enemies::zp_pool_base + 3, x
        tay
        and #$02
        beq @zero_state
        JAL Enemies::basic

        ;; It's the first state of the enemy (i.e. just moving up and down).
    @zero_state:
        ;; Has the timer run out? If not, just continue moving.
        tya
        and #$F0
        bne @move

        ;; Yes! Grab the 'time' bits from the 'extra' state. If it's already
        ;; #%11, then we are done with the counting cycles and we can setup the
        ;; homing attack.
        tya
        and #$0C
        cmp #$0C
        beq @start_homing
        cmp #$08
        bne @increment_time

        ;; We are at the #%10 'kind', which means we need to flip the vertical
        ;; position.
        tya
        eor #$01
        sta Enemies::zp_pool_base + 3, x
        tay

    @increment_time:
        ;; Increment the 'time' bits and continue moving.
        tya
        clc
        adc #$04
        sta Enemies::zp_pool_base + 3, x
        tay

    @move:
        ;; Moving is a matter of just increasing up/down depending on the 'down'
        ;; bit from the 'extra' state.
        tya
        and #$01
        beq @go_down

        INC_MOVEMENT_X Enemies::zp_pool_base + 1
        jmp @increase_timer
    @go_down:
        DEC_MOVEMENT_X Enemies::zp_pool_base + 1

    @increase_timer:
        tya
        clc
        adc #$10
        sta Enemies::zp_pool_base + 3, x

        rts

        ;; We are done going up and down. Now it's time to change the state of
        ;; this enemy, and home towards the player depending on its position.
    @start_homing:
        ;; Out of simplicity, the movement kind is picked at random. Hence,
        ;; initialize the 'a' register with a random number.
        stx Globals::zp_tmp0
        jsr Prng::random_valid_y_coordinate
        ldx Globals::zp_tmp0

        ;; Ensure the 'state' bit is set whenever we enter back at the 'homing'
        ;; function, so we can jump right into 'basic'. The 'downwards' bit is
        ;; set in the next step, so zero it out for now. And set the timer to
        ;; '1'.
        ora #$12
        and #%00011110

        ;; Compare the current Y position to that of the player. Then set the
        ;; 'downwards' bit if it needs to go down.
        ldy Enemies::zp_pool_base + 1, x
        cpy Player::zp_screen_y
        bcs @set_homing_to_basic
        ora #$01

    @set_homing_to_basic:
        sta Enemies::zp_pool_base + 3, x
        rts
    .endproc

    ;; Chase the player. This has two phases:
    ;;
    ;;  1. Thinking: the enemy stops and buzzes horizontally. Whenever the timer
    ;;               runs out, then it checks where's the player, sets the
    ;;               directions and switches to 'moving' mode.
    ;;  2. Moving: just move to the direction set on the 'thinking' mode,
    ;;             while also taking care to bounce off platforms. Whenever
    ;;             the timer runs out it will go back to 'thinking' mode.
    ;;
    ;; As with other algorithms, the 'extra' value is used. Namely:
    ;;
    ;;   |TTTT --SD|; where:
    ;;   |
    ;;   |- D: downwards if 1; upwards if 0.
    ;;   |- S: 'moving' state if 1; 'thinking' if 1.
    ;;   |- T: timer. Whenever it reaches zero, then we change of phase.
    ;;
    .proc chase
        ;; Get the value for the timer. Has it already turned out? If so then
        ;; prepare for the next stage and switch to it. Otherwise we move
        ;; according to the current algorithm.
        lda Enemies::zp_pool_base + 3, x
        tay
        and #$F0
        bne @move_or_think
        tya
        and #$02
        beq @turn_into_moving

        ;; Turn into thinking mode.
        lda #$10
        sta Enemies::zp_pool_base + 3, x
        rts

        ;; Turn into moving mode.
    @turn_into_moving:
        ;; The timer on the 'extra' value is reset to 1 and the state is set to
        ;; "moving". The bit for vertical motion has to be set depending on the
        ;; current position of the player and this enemy.
        lda Enemies::zp_pool_base + 1, x
        ldy #$12
        cmp Player::zp_screen_y
        bcs @set_vertical
        iny
    @set_vertical:
        sty Enemies::zp_pool_base + 3, x

        ;; Now compare the current X position to the player's one. With this
        ;; set/unset the 'D' bit on the 'status' value so to set the horizontal
        ;; motion to be taken.
        lda Enemies::zp_pool_base + 2, x
        cmp Player::zp_screen_x
        bcc @set_right
        lda #$7F
        and Enemies::zp_pool_base, x
        jmp @set_horizontal
    @set_right:
        lda #$80
        ora Enemies::zp_pool_base, x
    @set_horizontal:
        sta Enemies::zp_pool_base, x

        rts

    @move_or_think:
        tya
        and #$02
        bne @do_move

        ;;;
        ;; Thinking mode.

        ;; Increment the counter.
        tya
        clc
        adc #$10
        sta Enemies::zp_pool_base + 3, x

        ;; Don't always move, but once every frame. Otherwise enemies move
        ;; _really_ fast and it's just too distracting.
        and #$10
        beq @do_think
        rts

        ;; If we are already halfway through it, think to the right, otherwise
        ;; go to the left.
    @do_think:
        lda Enemies::zp_pool_base + 3, x
        and #$80
        beq @think_right
        DEC_MOVEMENT_X Enemies::zp_pool_base + 2
        rts
    @think_right:
        INC_MOVEMENT_X Enemies::zp_pool_base + 2
        rts

        ;;;
        ;; Movement mode.

    @do_move:
        ;; Increment the counter.
        tya
        clc
        adc #$10
        sta Enemies::zp_pool_base + 3, x
        tay

        ;; Perform vertical motion.
        and #$01
        beq @move_up
        INC_MOVEMENT_X Enemies::zp_pool_base + 1
        jmp @move_horizontal
    @move_up:
        DEC_MOVEMENT_X Enemies::zp_pool_base + 1

        ;; And now horizontal motion.
    @move_horizontal:
        lda Enemies::zp_pool_base, x
        and #$80
        beq @move_left
        INC_MOVEMENT_X Enemies::zp_pool_base + 2
        jmp @check_collisions
    @move_left:
        DEC_MOVEMENT_X Enemies::zp_pool_base + 2

        ;;;
        ;; Collision checking is quite similar to the one on bouncing. The
        ;; difference is that the bouncing has to continue for some time, as the
        ;; bouncing is just temporary before switching back to chasing
        ;; mode. Fortunately, this is as easy as flipping the correct bit, and
        ;; the enemy will just move on the bouncing direction until it stops to
        ;; "think" again (i.e. the timer runs out) and chase back the player.

    @check_collisions:
        ;; Translate the Y axis into tile coordinates.
        lda Enemies::zp_pool_base + 1, x
        lsr
        lsr
        lsr
        sta Globals::zp_arg0

        ;; Translate the X axis into tile coordinates. We will also save it into
        ;; 'Globals::zp_tmp0' as that will save us some trouble down the road.
        lda Enemies::zp_pool_base + 2, x
        lsr
        lsr
        lsr
        sta Globals::zp_arg1
        sta Globals::zp_tmp0

        ;; Does this upper left corner collide?
        jsr Background::collides
        bne @bounce_down

        ;; No. Increment the X coordinate to the right corner and ask again.
        inc Globals::zp_arg1
        inc Globals::zp_arg1
        jsr Background::collides
        beq @check_front_or_bottom

    @bounce_down:
        ;; Bounce down a bit to cancel the movement we've done, and set the 'D'
        ;; bit from the 'extra' value to downward movement.
        ldx Enemies::zp_pool_index
        INC_MOVEMENT_X Enemies::zp_pool_base + 1
        lda Enemies::zp_pool_base + 3, x
        ora #$01
        sta Enemies::zp_pool_base + 3, x
        rts

        ;; If it's the weird guy, then we need to check the front. Otherwise, if
        ;; it's the UFO, there's no front (i.e. the sprite is half the height),
        ;; so we go directly into the bottom check.
    @check_front_or_bottom:
        lda Globals::zp_level_kind
        cmp #4
        beq @check_bottom

        ;; Check on the front right corner. If there's no collision, check the
        ;; front left corner. If all fails, go check the bottom.
        inc Globals::zp_arg0
        jsr Background::collides
        bne @bounce_left
        dec Globals::zp_arg1
        jsr Background::collides
        beq @check_bottom

        ;; Bounce right a bit to cancel the movement we've done, and set the 'D'
        ;; bit from the 'state' value to right movement.
        ldx Enemies::zp_pool_index
        INC_MOVEMENT_X Enemies::zp_pool_base + 2
        lda Enemies::zp_pool_base, x
        ora #$7F
        sta Enemies::zp_pool_base, x
        rts

    @bounce_left:
        ;; Bounce left a bit to cancel the movement we've done, and set the 'D'
        ;; bit from the 'state' value to left movement.
        ldx Enemies::zp_pool_index
        DEC_MOVEMENT_X Enemies::zp_pool_base + 2
        lda Enemies::zp_pool_base, x
        and #$7F
        sta Enemies::zp_pool_base, x
        rts

        ;; So, there was no upper/front collisions, let's check the bottom
        ;; corners of the enemy.
    @check_bottom:
        ;; Remember that we saved the original X tile coordinate in
        ;; 'zp_tmp0'. Recover that and point the Y tile coordinate to the bottom
        ;; as well.
        inc Globals::zp_arg0
        lda Globals::zp_tmp0
        sta Globals::zp_arg1
        jsr Background::collides
        bne @bounce_up

        ;; Only thing left is the bottom right corner. If that is not a hit then
        ;; we just go.
        inc Globals::zp_arg1
        inc Globals::zp_arg1
        jsr Background::collides
        beq @end

    @bounce_up:
        ;; Bounce up a bit to cancel the movement we've done, and set the 'D'
        ;; bit from the 'extra' value to upwards movement.
        ldx Enemies::zp_pool_index
        DEC_MOVEMENT_X Enemies::zp_pool_base + 1
        lda Enemies::zp_pool_base + 3, x
        and #$FE
        sta Enemies::zp_pool_base + 3, x

    @end:
        rts
    .endproc

    ;; Function pointers to movement handlers.
movement_lo:
    .byte <basic, <bounce, <erratic, <homing
    .byte <chase, <bounce, <basic, <chase
movement_hi:
    .byte >basic, >bounce, >erratic, >homing
    .byte >chase, >bounce, >basic, >chase

    ;;;
    ;; Definitions for all the enemy types.
    ;;
    ;; An enemy type is defined by four bytes, containing the tile IDs for
    ;; it. Some enemies only span 2 tiles, and because of this they have $FF as
    ;; filler bytes.
    ;;
    ;; Moreover, each enemy has two states in order to show some inner
    ;; movement. This is why each enemy has an extra row of tile IDs, which
    ;; contain the "other" state.
    ;;
    ;; Finally, enemies can face right or left, which usually would be handled
    ;; in code, but it's much cheaper to abuse our mostly empty ROM-space with
    ;; extra definitions than being careful on the order in the allocation
    ;; loop.
    ;;
    ;; Thus, an enemy takes a whoping amount of 32 bytes. The first four bytes
    ;; are the actualy tile IDs for the enemy. The second row of four bytes is
    ;; its "other" shape in order to show inner movement. And the last two rows
    ;; are simply mirrors of the first two whenever the enemy is facing right
    ;; instead of left.
tiles:
    ;; Asteroid
    .byte $26, $27, $36, $37
    .byte $46, $47, $56, $57
    .byte $27, $26, $37, $36
    .byte $47, $46, $57, $56

    ;; Furry thingie
    .byte $28, $29, $38, $39
    .byte $48, $49, $58, $59
    .byte $29, $28, $39, $38
    .byte $49, $48, $59, $58

    ;; Bubble
    .byte $24, $25, $34, $35
    .byte $44, $45, $54, $55
    .byte $25, $24, $35, $34
    .byte $45, $44, $55, $54

    ;; Fighter jet 1
    .byte $31, $32, $FF, $FF
    .byte $60, $61, $FF, $FF
    .byte $32, $31, $FF, $FF
    .byte $61, $60, $FF, $FF

    ;; UFO
    .byte $40, $41, $FF, $FF
    .byte $50, $51, $FF, $FF
    .byte $41, $40, $FF, $FF
    .byte $51, $50, $FF, $FF

    ;; Cross
    .byte $2C, $2D, $3C, $3D
    .byte $4C, $4D, $5C, $5D
    .byte $2D, $2C, $3D, $3C
    .byte $4D, $4C, $5D, $5C

    ;; Fighter jet 2
    .byte $2A, $2B, $3A, $3B
    .byte $4A, $4B, $5A, $5B
    .byte $2B, $2A, $3B, $3A
    .byte $4B, $4A, $5B, $5A

    ;; Weirdo
    .byte $2E, $2F, $3E, $3F
    .byte $4E, $4F, $5E, $5F
    .byte $2F, $2E, $3F, $3E
    .byte $4F, $4E, $5F, $5E
.endscope
