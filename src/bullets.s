.segment "CODE"

;; Assuming that the 'x' register indexes a bullet on its pool, increment the
;; register as many times as to point to the next one. Bound checking is not
;; performed, it's up to the caller to implement that.
.macro NEXT_BULLET_INDEX_X
    inx
    inx
    inx
.endmacro

;; Function and variables which deal with the pool of bullets that the
;; `driver.s` will use in order to render and deal with bullets on screen.
.scope Bullets
    ;; Maximum amount of bullets allowed on screen at the same time.
    BULLETS_POOL_CAPACITY = 10

    ;; The capacity of the bullets pool in bytes.
    BULLETS_POOL_CAPACITY_BYTES = BULLETS_POOL_CAPACITY * 3

    ;; Base address for the pool of bullets used on this game. The pool has
    ;; #BULLETS_POOL_CAPACITY bullet objects where each one is 3 bytes long:
    ;;  1. State: which can have two formats:
    ;;     - $FF: the bullet is not active.
    ;;     - |Dxxx|xxxx|: where D is the direction bit (1: right; 0: left); and
    ;;                    the rest of bits count the number of moves from this
    ;;                    bullet.
    ;;  2. Y coordinate.
    ;;  3. X coordinate.
    zp_bullets_pool_base = $A0  ; asan:reserve BULLETS_POOL_CAPACITY_BYTES

    ;; The current amount of bullets on screen.
    zp_bullets_pool_size = $E0

    ;; The index on the pool where the next bullet can start iterating from.
    ;; This is a small optimization so not to start from the beginning every
    ;; time, as consecutive allocation is a very common case.
    zp_last_allocated_index = $E1

    ;; The screen coordinates of the bullet being inspected right now. Used when
    ;; computing the move of bullets and checking possible collisions with
    ;; background/enemies.
    zp_current_bullet_y = $E2
    zp_current_bullet_x = $E3

    ;; The amount of time we are not allowing B presses. This is a rather low
    ;; value so you can have quite some presses per frame.
    zp_bullet_timer = $35
    BULLET_TIMER_VALUE = HZ / 15

    ;; Maximum moves that a bullet can do. The tile also transitions depending
    ;; on the moves done so far.
    BULLET_MAX_MOVES = 26
    BULLET_FIRST_TRANSITION = 20
    BULLET_LAST_TRANSITION = 25

    ;; Velocity at which bullets move.
    .ifdef PAL
        BULLET_VELOCITY = 7
    .else
        BULLET_VELOCITY = 6
    .endif

    ;; Initialize the pool of bullets.
    .proc init
        lda #0
        sta zp_bullet_timer
        sta zp_bullets_pool_size
        sta zp_last_allocated_index
        sta zp_current_bullet_y
        sta zp_current_bullet_x

        ;; Initializing the pool is a matter of setting to $FF the state byte
        ;; for each bullet object.
        ldx #0
        ldy #BULLETS_POOL_CAPACITY
        lda #$FF
    @pool_init_loop:
        sta zp_bullets_pool_base, x
        NEXT_BULLET_INDEX_X

        dey
        bne @pool_init_loop

        rts
    .endproc

    ;; Update the status of the pool by doing mainly three things:
    ;;   1. Create a new bullet if the player can and has requested it.
    ;;   2. Move all active bullets.
    ;;   3. Check background/enemy collisions.
    .proc update
        ;; Are we already full of bullets on screen? If so go move them.
        lda zp_bullets_pool_size
        cmp #BULLETS_POOL_CAPACITY
        beq @move_bullets

        ;; Can the B button be pressed? If not go to `@move_bullets` directly.
        lda zp_bullet_timer
        beq @check_bullets_pressed
        dec zp_bullet_timer
        jmp @move_bullets

    @check_bullets_pressed:
        ;; Is the B button pressed? If not go to `@move_bullets` directly.
        lda #(Joypad::BUTTON_B)
        and Joypad::zp_buttons1
        beq @move_bullets

        ;; The B button was pressed. Reset the bullet timer.
        lda #BULLET_TIMER_VALUE
        sta zp_bullet_timer

        ;; Let's fetch a free spot for the new bullet. Note that since we have
        ;; checked that the pools size is not the same as the capacity, there
        ;; *must* be a free spot. If that's not the case and we get into an
        ;; infinite loop, then that's a bug we have to fix :)
        ldx zp_last_allocated_index
    @find_free_bullet_bucket:
        lda zp_bullets_pool_base, x
        cmp #$FF
        beq @initialize_bucket

    @next_free_loop:
        ;; Prepare the `x` register for the next iteration. Notice that if we
        ;; are over the total size in memory, we have to roll the `x` back to
        ;; zero. This is possible because the loop starts at
        ;; `zp_last_allocated_index`, which is not necessarily 0.
        NEXT_BULLET_INDEX_X
        cpx #BULLETS_POOL_CAPACITY_BYTES
        bne @find_free_bullet_bucket
        ldx #0
        beq @find_free_bullet_bucket

    @initialize_bucket:
        ;; We found a free bucket. Initialize the first byte to 0 since it has
        ;; not moved yet. The heading is taken from the player's state.
        lda Player::zp_state
        asl
        and #%10000000
        sta zp_bullets_pool_base, x

        ;; Set the Y coordinate to the player's waist.
        inx
        lda Player::zp_screen_y
        clc
        adc #(Player::PLAYER_WAIST - 1)
        sta zp_bullets_pool_base, x

        ;; Set the X coordinate to the player while also adjusting to the future
        ;; velocity applied on `@move_bullets` which, in turn, depends on the
        ;; player's heading stored on `Player::zp_state`.
        inx
        lda Player::zp_screen_x
        bit Player::zp_state
        clc
        bvc @set_bullet_left
        adc #(Player::PLAYER_WIDTH - BULLET_VELOCITY)
        jmp @set_bullet_x
    @set_bullet_left:
        adc #BULLET_VELOCITY
    @set_bullet_x:
        sta zp_bullets_pool_base, x

        ;; Save the index so it can be used in future bullet creation. Also be
        ;; careful to wrap around.
        inx
        cpx #BULLETS_POOL_CAPACITY_BYTES
        bne @set_last_allocated
        ldx #0
    @set_last_allocated:
        stx zp_last_allocated_index

        ;; Increase the number of bullets on screen.
        inc zp_bullets_pool_size

    @move_bullets:
        ;; We will have on the 'y' register the amount of bullets on screen
        ;; pending to be moved. If there are none, we can return early.
        ldy zp_bullets_pool_size
        bne @do_move
        rts

    @do_move:
        ;; There's at least one bullet to be moved. In this case, we will
        ;; proceed to move any active bullet and check for collisions.
        ;;
        ;; The 'x' register will index the pool of bullets.
        ldx #0

    @move_loop:
        ;; Is the current bullet active?
        lda zp_bullets_pool_base, x
        cmp #$FF
        bne @move_active_bullet

        ;; No, go for the next one.
        NEXT_BULLET_INDEX_X
        jmp @move_loop

    @move_active_bullet:
        ;; Store the original value into a temporary variable, and mask out the
        ;; direction flag.
        sta Globals::zp_tmp1
        and #%01111111

        ;; Ok, has this bullet moved to its maximum capacity?
        cmp #BULLET_MAX_MOVES
        bne @do_move_active_bullet

        ;; Yes! Then mark it as over.
        lda #$FF
        sta zp_bullets_pool_base, x

        ;; Decrease the number of bullets active and go check collisions if we
        ;; are done checking for bullets. In this case, if this was the last
        ;; bullet active, return early.
        dec zp_bullets_pool_size
        bne @decrease_y
        jmp @end
    @decrease_y:
        dey
        bne @next_iteration
        jmp @end

    @next_iteration:
        ;; We still have active bullets to move, go to the next iteration.
        NEXT_BULLET_INDEX_X
        bne @move_loop

    @do_move_active_bullet:
        ;; Increase the number of moves that this bullet has done.
        stx Globals::zp_idx
        inc zp_bullets_pool_base, x

        ;; Save the position on the Y axis as the value for the current bullet,
        ;; then convert it into tile coordinates so it can be used later for
        ;; background collision check.
        lda zp_bullets_pool_base + 1, x
        sta zp_current_bullet_y
        lsr
        lsr
        lsr
        sta Globals::zp_arg0

        ;; Grab the position on the X axis and apply the velocity depending on
        ;; the direction, which was stored back on the `Globals::zp_tmp1`
        ;; variable.
        lda zp_bullets_pool_base + 2, x
        bit Globals::zp_tmp1
        bmi @move_right
        sec
        sbc #BULLET_VELOCITY
        jmp @collision_check
    @move_right:
        clc
        adc #BULLET_VELOCITY

    @collision_check:
        ;; We now have the future value for the X axis. Store it as the current
        ;; value and then convert it into tile coordinates so it can be used for
        ;; background collision check.
        sta zp_current_bullet_x
        lsr
        lsr
        lsr
        sta Globals::zp_arg1

        ;; The actual check for background collision.
        jsr Background::collides
        beq @check_enemy_collision

        ;; There was a collision! Disable the bullet.
        ldx Globals::zp_idx
        lda #$FF
        sta zp_bullets_pool_base, x

        ;; Decrement the number of bullets active.
        dec zp_bullets_pool_size
        beq @end
        dey
        beq @end

        ;; And go for the next iteration.
        inx
        inx
        inx
        jmp @move_loop

        ;; Enemy collision for this bullet. It's actually easier/faster to just
        ;; unroll the loop.
    @check_enemy_collision:
        lda #Enemies::ENEMY_0_IDX
        sta Enemies::zp_pool_index
        jsr Enemies::collides
        beq @enemy_1
        jsr Enemies::bite_the_dust
        jmp @save_bullet_move
    @enemy_1:
        lda #Enemies::ENEMY_1_IDX
        sta Enemies::zp_pool_index
        jsr Enemies::collides
        beq @enemy_2
        jsr Enemies::bite_the_dust
        jmp @save_bullet_move
    @enemy_2:
        lda #Enemies::ENEMY_2_IDX
        sta Enemies::zp_pool_index
        jsr Enemies::collides
        beq @save_bullet_move
        jsr Enemies::bite_the_dust
        __fallthrough__ @save_bullet_move

    @save_bullet_move:
        ;; Restore back the old value from the 'x' register.
        ldx Globals::zp_idx
        inx
        inx

        ;; Store the new value for the X axis, increment the 'x' register and
        ;; decrease the number of active bullets to be moved. If we are already
        ;; into no bullets to be moved, then fall through and consider
        ;; collisions.
        lda zp_current_bullet_x
        sta zp_bullets_pool_base, x
        inx
        dey
        beq @end
        jmp @move_loop

    @end:
        rts
    .endproc
.endscope
