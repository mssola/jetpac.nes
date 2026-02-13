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

.scope Enemies
    ;; Maximum amount of enemies allowed on screen at the same time.
    ENEMIES_POOL_CAPACITY = 3

    ;; The capacity of the enemies pool in bytes.
    ENEMIES_POOL_CAPACITY_BYTES = ENEMIES_POOL_CAPACITY * 4

    ;; Initial X coordinates for enemies depending on if they appear on the
    ;; left/right edge of the screen.
    ENEMIES_INITIAL_X       = $F0
    ENEMIES_INITIAL_X_RIGHT = $10

    ;; Base address for the pool of enemies used on this game. The pool has
    ;; #ENEMIES_POOL_CAPACITY capacity of enemy objects where each one is 4
    ;; bytes long:
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
    zp_enemies_pool_base = $60  ; asan:reserve ENEMIES_POOL_CAPACITY_BYTES

    ;; The current size of active enemies. That is, one thing is the capacity of
    ;; the pool, and another is what's the number of enemies on screen.
    zp_enemies_pool_size = $D0

    ;; Base index of the enemy tiles in 'tiles' to be used. Whether to use one
    ;; row or the other for a given enemy is to be decided by its current state.
    zp_enemy_tiles = $D1

    ;; Pointer to the function that handles movement for the current enemy
    ;; type. Using a function pointer is a bit tricky on the humble 6502's
    ;; architecture, as you need to do indirect jumps with possible optimisation
    ;; tricks along the way. But there are really too many different enemy
    ;; algorithms that a plain if-else + jsr code flow would be too expensive
    ;; and harder to read.
    zp_enemy_movement_fn = $D2  ; asan:reserve $02

    ;; Preserves the index on 'zp_enemies_pool_base' for a given enemy inside of
    ;; the movement handler. Check the documentation on movement handlers.
    zp_pool_index = $D4

    ;; An extra argument that enemies can have depending on their type. This is
    ;; useful for different waves with the same algorithm but different speeds.
    zp_enemy_arg = $D5

    ;; Values for the counter of enemies that fall.
    FALLING_VELOCITY      = HZ / 10
    FALLING_VELOCITY_FAST = FALLING_VELOCITY / 2

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
        sta zp_enemy_tiles

        ;; And set the movement function for this type.
        lda movement_lo, x
        sta zp_enemy_movement_fn
        lda movement_hi, x
        sta zp_enemy_movement_fn + 1

        ;; TODO: rest of the enemies.
        ;; TODO: there are ways to optimize this
        txa
        beq @init_basic_1
        cmp #1
        beq @init_bounce_1
        cmp #2
        beq @init_erratic
        cmp #5
        beq @init_bounce_2
        cmp #6
        beq @init_basic_2

    @init_basic_1:
        lda #1
        sta Enemies::zp_enemy_arg
        lda #FALLING_VELOCITY
        bne @set
    @init_basic_2:
        lda #2
        sta Enemies::zp_enemy_arg
        lda #FALLING_VELOCITY_FAST
        bne @set
    @init_erratic:
        lda #1
        sta Enemies::zp_enemy_arg
        jsr Prng::random_valid_y_coordinate
        and #$01
        jmp @set
    @init_bounce_1:
        lda #1
        sta Enemies::zp_enemy_arg
        jsr Prng::random_valid_y_coordinate
        and #$01
        jmp @set
    @init_bounce_2:
        lda #2
        sta Enemies::zp_enemy_arg
        jsr Prng::random_valid_y_coordinate
        and #$01
        __fallthrough__ @set

    @set:
        ;; The 'init_pool' wants an argument which is the 'extra' state to be
        ;; set up for all enemies of the pool.
        sta Globals::zp_arg0

        __fallthrough__ init_pool
    .endproc

    ;; Initializes the enemy pool for this game. It requires an argument to be
    ;; passed in 'Globals::zp_arg0' which contains the 'extra' state to be
    ;; passed to all enemies of the pool.
    .proc init_pool
        ldx #0

        ldy #ENEMIES_POOL_CAPACITY
    @enemies_init_loop:
        ;; The state is set at random.
        stx Globals::zp_tmp0
        jsr Prng::random_valid_y_coordinate
        ldx Globals::zp_tmp0
        sta zp_enemies_pool_base, x
        sta Globals::zp_tmp1

        ;; The Y coordinate is also set at random within the bounds of the
        ;; playable screen.
        jsr Prng::random_valid_y_coordinate
        ldx Globals::zp_tmp0
        inx
        sta zp_enemies_pool_base, x

        ;; The initial X position is based on whether it's facing left or right.
        inx
        bit Globals::zp_tmp1
        bmi @facing_right
        lda #ENEMIES_INITIAL_X
        bne @set_x_position
    @facing_right:
        lda #ENEMIES_INITIAL_X_RIGHT
    @set_x_position:
        sta zp_enemies_pool_base, x

        ;; And set the 'extra' state as passed down by the 'init' function.
        inx
        lda Globals::zp_arg0
        sta zp_enemies_pool_base, x

        ;; Next enemy!
        inx
        dey
        bne @enemies_init_loop

        ;; The initial size of the pool is its whole capacity.
        lda #ENEMIES_POOL_CAPACITY
        sta zp_enemies_pool_size

        rts
    .endproc

    ;; Update the state and movement of all active enemies.
    ;;
    ;; NOTE: this function does not do collision checking with bullets as
    ;; 'Bullets::update' already accounts for it and we assume that it ran
    ;; before this one.
    .proc update
        ldx #252

        ;; The loop index will be moved out of the 'y' register since movement
        ;; handlers might need to use it.
        ldy zp_enemies_pool_size
        sty Globals::zp_idx

        ;; In the (unlikely) case that there are no enemies left, just skip
        ;; 'update' altogether.
        bne @loop
        rts

    @loop:
        ;; Move the 'x' register to the current enemy for this iteration.
        NEXT_ENEMY_INDEX_X

        ;; Is the current enemy marked as invalid? If so just skip it. Note that
        ;; we don't even go to the '@next' down below, as that would decrease
        ;; the loop counter and this loop only cares about active
        ;; enemies. Having an enemy in the middle of the pool invalid is totally
        ;; valid as it could have died before assigning a new one.
        lda zp_enemies_pool_base, x
        cmp #$FF
        beq @loop

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
        inc zp_enemies_pool_base, x
        bne @move
    @reset:
        lda Globals::zp_tmp0
        and #$80
        sta zp_enemies_pool_base, x

    @move:
        ;; Store the index to the current enemy.
        stx Enemies::zp_pool_index

        ;; Jump to the movement handler for the current enemy. As to why this
        ;; needs to be in a function pointer, refer to
        ;; 'zp_enemy_movement_fn'. Note that this could've been done in other
        ;; ways. Here we fake a 'jsr' by pushing the address to return into the
        ;; stack (-1 to account for the 'rts' behavior of adding +1 to the PC),
        ;; and then calling the function pointed by 'zp_enemy_movement_fn'. Then
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
        jmp (zp_enemy_movement_fn)

    @return_from_movement_handler:
        ;; Restore the value from the 'x' register.
        ldx Enemies::zp_pool_index

        ;; TODO: collision with player

    @next:
        ;; Any more enemies left?
        dec Globals::zp_idx
        bne @loop

        rts
    .endproc

    ;; Allocate an enemy indexed by 'x' from the `zp_enemies_pool_base` buffer,
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
    ;; to the caller to check on this before calling this function.
    .proc allocate_x_y
        ;; Save the 'y' index, as it's faster to do funny address arithmetics
        ;; and add 16 in the end than constantly 'iny' every time in the right
        ;; order.
        sty Globals::zp_tmp0

        ;; Y coordinates for each sprite of the enemy.
        lda Enemies::zp_enemies_pool_base + 1, x
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
        lda Enemies::zp_enemies_pool_base, x
        sta Globals::zp_tmp2
        stx Globals::zp_tmp1
        ldx zp_enemy_tiles

        ;; Check on the direction bit from the enemy's state. If facing right,
        ;; then the 'x' register will be increased by 8 (pointing then to the
        ;; 3rd/4th rows of the enemy tiles ID definitions), and 'a' will have
        ;; the value for the third byte of the sprite (i.e. whether to mirror or
        ;; not the sprite at the PPU level).
        bit Globals::zp_tmp2
        bmi @face_right
        lda #0
        beq @set_state
    @face_right:
        txa
        clc
        adc #8
        tax
        lda #%01000000
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

        ;; The Y-coordinate for each sprite.
        ldx Globals::zp_tmp1
        lda Enemies::zp_enemies_pool_base + 2, x    ; top left
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

    ;; The enemy has been set to dust, remove it.
    .proc bite_the_dust
        dec Enemies::zp_enemies_pool_size

        ;; TODO: this assumes we are coming from within Enemies always. What
        ;; about impacting bullets?
        ldx Enemies::zp_pool_index

        ;; TODO: cloud animation and all that.
        lda #$FF
        sta Enemies::zp_enemies_pool_base, x

        rts
    .endproc

    ;;;
    ;; Movement handlers.
    ;;
    ;; Each enemy type has a function assigned to it as to how to move. These
    ;; functions are stored in the 'movement_lo' and 'movement_hi' ROM addresses
    ;; and they are used via the 'zp_enemy_movement_fn' function
    ;; pointer. Movement handlers are free to use any register and any memory
    ;; location, as that's handled by the caller.
    ;;
    ;; Collision only needs to be checked with platforms, as each handler might
    ;; have a different take on that scenario. Collision with bullets are
    ;; handled in the Bullets scope, and with the player is handled by the
    ;; caller.
    ;;
    ;; All handlers receive 'Enemies::zp_pool_index' which contain the index to the
    ;; 'Enemy::zp_enemies_pool_base' array of the current enemy. This argument
    ;; is expected to be _immutable_; if you want to abuse the 'x' register, you
    ;; are free to do so. For other arguments handlers are expected to abuse on
    ;; the 'extra' state that is available for each enemy.

    ;; Basic falling movement. Straight horizontal movement with a slight
    ;; downward angle. Enemy should explode on platform/ground contact. The
    ;; 'extra' state is used as a counter for the falling velocity (i.e. enemy
    ;; falls 1 pixel per counter exhaustion).
    .proc basic
        ;; First of all, we always move enemies horizontally, while being
        ;; mindful on the direction and the step depending on the enemy type.
        lda Enemies::zp_enemies_pool_base, x
        and #$80
        beq @move_left
        lda Enemies::zp_enemies_pool_base + 2, x
        clc
        adc Enemies::zp_enemy_arg
        sta Enemies::zp_enemies_pool_base + 2, x
        jmp @do_counter
    @move_left:
        lda Enemies::zp_enemies_pool_base + 2, x
        sec
        sbc Enemies::zp_enemy_arg
        sta Enemies::zp_enemies_pool_base + 2, x

        ;; Decrement the counter from the 'extra' state. If it reaches zero,
        ;; then we should do some downward movement. Otherwise we just go to
        ;; collision checking.
    @do_counter:
        lda Enemies::zp_enemies_pool_base + 3, x
        sec
        sbc #1
        bne @update_extra_state

        ;; Move downwards and reset the 'extra' state depending on the enemy
        ;; kind.
    @downward:
        inc Enemies::zp_enemies_pool_base + 1, x

        lda Globals::zp_level_kind
        beq @init_zero
        lda #FALLING_VELOCITY_FAST
        bne @update_extra_state
    @init_zero:
        lda #FALLING_VELOCITY

    @update_extra_state:
        sta Enemies::zp_enemies_pool_base + 3, x

        ;; Check collisions with the background.

        ;; Remember that background checks are done in tile coordinates, not
        ;; screen ones. So we have to do the translation to it (3 x
        ;; 'lsr'). After that, for the X coordinate, depending if the enemy is
        ;; facing left/right, we have to increment this coordinate (i.e. twice
        ;; if facing right as an enemy of this type is always 2x2 sprites).
        lda Enemies::zp_enemies_pool_base + 2, x
        lsr
        lsr
        lsr
        tay
        lda Enemies::zp_enemies_pool_base, x
        and #$80
        beq @after_x
        iny
        iny
    @after_x:
        sty Globals::zp_arg1

        ;; Translate the Y coordinate into tile ones.
        lda Enemies::zp_enemies_pool_base + 1, x
        lsr
        lsr
        lsr
        sta Globals::zp_arg0

        ;; Perform a collision check with the upper boundary.
        jsr Background::collides
        beq @check_down
        JAL bite_the_dust

    @check_down:
        ;; If that failed, then increment the vertical tile coordinate twice to
        ;; get the bottom boundary and check again.
        inc Globals::zp_arg0
        inc Globals::zp_arg0
        jsr Background::collides
        beq @end
        JAL bite_the_dust

    @end:
        rts
    .endproc

    ;; Diagonal bouncing at a 45 degree angle. The 'extra' state is a boolean
    ;; which is set to 0 if moving upwards, and to 1 if moving downwards.
    .proc bounce
        ;; First of all, we always move enemies horizontally, while being
        ;; mindful on the direction and the step depending on the enemy
        ;; type. This is just the same as the 'basic' algorithm.
        lda Enemies::zp_enemies_pool_base, x
        and #$80
        beq @move_left
        lda Enemies::zp_enemies_pool_base + 2, x
        clc
        adc Enemies::zp_enemy_arg
        jmp @do_vertical
    @move_left:
        lda Enemies::zp_enemies_pool_base + 2, x
        sec
        sbc Enemies::zp_enemy_arg

    @do_vertical:
        ;; Set the previous computation regardless of the branch.
        sta Enemies::zp_enemies_pool_base + 2, x

        ;; The vertical movement works the same way, but taking into account its
        ;; direction via the 'extra' state. Note that we mask it, which is not
        ;; needed for the main enemies which use this algorithm, but it is for
        ;; the 'erratic' algorithm which re-uses this one.
        lda Enemies::zp_enemies_pool_base + 3, x
        and #$01
        beq @move_up
        lda Enemies::zp_enemies_pool_base + 1, x
        clc
        adc Enemies::zp_enemy_arg
        jmp @check_collision
    @move_up:
        lda Enemies::zp_enemies_pool_base + 1, x
        sec
        sbc Enemies::zp_enemy_arg

    @check_collision:
        ;; Set the previous computation regardless of the branch.
        sta Enemies::zp_enemies_pool_base + 1, x

        ;; Collision checking.

        ;; Translate the Y axis into tile coordinates.
        lda Enemies::zp_enemies_pool_base + 1, x
        lsr
        lsr
        lsr
        sta Globals::zp_arg0

        ;; Translate the X axis into tile coordinates. We will also save it into
        ;; 'Globals::zp_tmp0' as that will save us some trouble down the road.
        lda Enemies::zp_enemies_pool_base + 2, x
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

        ;; There was a (hopefully purely) upper collision!
    @bounce_down:
        ;; The previous 'Background::collides' call has tampered with the 'x'
        ;; register. Load the proper value again.
        ldx Enemies::zp_pool_index

        ;; Flip 'extra' boolean.
        lda Enemies::zp_enemies_pool_base + 3, x
        eor #1
        sta Enemies::zp_enemies_pool_base + 3, x

        ;; Move downwards once, which cancels the movement set at the beginning
        ;; of the function.
        lda Enemies::zp_enemies_pool_base + 1, x
        clc
        adc Enemies::zp_enemy_arg
        sta Enemies::zp_enemies_pool_base + 1, x

        rts

        ;; Now, depending on the level, the enemy might be the regular size or
        ;; shorter. If it's on the shorter end, then move to check the bottom
        ;; corners directly.
    @check_front_or_bottom:
        lda Globals::zp_level_kind
        cmp #2
        beq @prepare_check_front_collision
        cmp #1
        bne @check_bottom

    @prepare_check_front_collision:
        ;; We are checking the "front" (center) of the enemy, which corresponds
        ;; to the regular sized enemy. This means to increase the Y tile
        ;; coordinate once.
        inc Globals::zp_arg0

        ;; Is the enemy moving left or right? This is relevant because the X
        ;; tile coordinate is set to the right corner. If it's moving left, then
        ;; we need to decrement it twice to move it back to the left corner.
        ldx Enemies::zp_pool_index
        lda Enemies::zp_enemies_pool_base, x
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
        lda Enemies::zp_enemies_pool_base, x
        eor #$80
        sta Enemies::zp_enemies_pool_base, x

        ;; And bounce already to the new direction to avoid the enemy getting
        ;; stucked or other weird situations.
        and #$80
        beq @bounce_left
        lda Enemies::zp_enemies_pool_base + 2, x
        clc
        adc Enemies::zp_enemy_arg
        jmp @set_bounce
    @bounce_left:
        lda Enemies::zp_enemies_pool_base + 2, x
        sec
        sbc Enemies::zp_enemy_arg
    @set_bounce:
        sta Enemies::zp_enemies_pool_base + 2, x
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
        lda Enemies::zp_enemies_pool_base + 3, x
        eor #1
        sta Enemies::zp_enemies_pool_base + 3, x

        ;; Make it bounce up.
        lda Enemies::zp_enemies_pool_base + 1, x
        sec
        sbc Enemies::zp_enemy_arg
        sta Enemies::zp_enemies_pool_base + 1, x

        rts
    .endproc

    ;; Erratic movement, which sometimes stops, sometimes moves horizontally,
    ;; and some other times it goes diagonally; all at random. The 'extra' state
    ;; is laid out as follows:
    ;;
    ;;   |TTTT -AAD|; where:
    ;;   |
    ;;   |-  D: downwards if 1; upwards if 0 (just like the 'diagonal' algorithm).
    ;;   |- AA: current algorithm: 00/11: stop; 01: horizontal; 10: diagonal.
    ;;   |-  T: timer for algorithm. Whenever it reaches zero the algorithm is changed.
    ;;
    .proc erratic
        ;; Check the timer.
        lda Enemies::zp_enemies_pool_base + 3, x
        and #$F0
        bne @do

        ;; The 'extra' state has to change. In order to do this we prepare an
        ;; "or" mask that will be paired to the change of the algorithm in the
        ;; following code block. Not that this mask is shifted to the right, as
        ;; the end computation will finally shift it left once. This mask is
        ;; responsible for initializing the timer to 1, and the algorithm to 1
        ;; if we are coming from a "stop" phase (i.e. we want to guarantee that
        ;; the next state is not "stop" again).
        lda Enemies::zp_enemies_pool_base + 3, x
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
        lda Enemies::zp_enemies_pool_base + 3, x
        and #$01
        clc
        adc Globals::zp_tmp0
        sta Enemies::zp_enemies_pool_base + 3, x
        jmp @end

    @do:
        ;; Blindly increase the timer as overflows will be covered when entering
        ;; this function.
        lda Enemies::zp_enemies_pool_base + 3, x
        clc
        adc #$10
        sta Enemies::zp_enemies_pool_base + 3, x

        ;; Now switch what to do depending on the algorithm.
        and #%00000110
        beq @end
        cmp #%00000110
        beq @end
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
        lda Enemies::zp_enemies_pool_base, x
        and #$80
        beq @move_left
        iny
        iny
        lda Enemies::zp_enemies_pool_base + 2, x
        clc
        adc Enemies::zp_enemy_arg
        jmp @set_horizontal
    @move_left:
        lda Enemies::zp_enemies_pool_base + 2, x
        sec
        sbc Enemies::zp_enemy_arg
    @set_horizontal:
        sta Enemies::zp_enemies_pool_base + 2, x

        ;; We store in a temporary value how much the X tile coordinates will
        ;; have to be increased in order to point to the right face.
        sty Globals::zp_tmp0

        ;; After that has been done, check for collision.

        ;; Translate the Y axis into tile coordinates.
        lda Enemies::zp_enemies_pool_base + 1, x
        lsr
        lsr
        lsr
        sta Globals::zp_arg0

        ;; Translate the X axis into tile coordinates, while adding the facing
        ;; value we computed earlier.
        lda Enemies::zp_enemies_pool_base + 2, x
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
        beq @end

    @horizontal_collision:
        ;; Restore the 'x' register from a previous 'Background::collides' call.
        ldx Enemies::zp_pool_index

        ;; Flip the direction bit.
        lda Enemies::zp_enemies_pool_base, x
        eor #$80
        sta Enemies::zp_enemies_pool_base, x

        ;; And bounce already to the new direction to avoid the enemy getting
        ;; stucked or other weird situations.
        and #$80
        beq @bounce_left
        lda Enemies::zp_enemies_pool_base + 2, x
        clc
        adc Enemies::zp_enemy_arg
        jmp @set_bounce
    @bounce_left:
        lda Enemies::zp_enemies_pool_base + 2, x
        sec
        sbc Enemies::zp_enemy_arg
    @set_bounce:
        sta Enemies::zp_enemies_pool_base + 2, x

    @end:
        rts
    .endproc

    ;; Track the player's current Y position and homes at it when the Y position
    ;; matches that of the player.
    .proc homing
        ;; TODO

        rts
    .endproc

    ;; Simply chases the player. TODO: explain 'extra'.
    .proc chase
        ;; TODO

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
