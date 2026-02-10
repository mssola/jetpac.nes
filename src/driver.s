.segment "CODE"

.scope Driver
    ;; Timer for the player to be able to pick up the joypad upon entering the
    ;; game.
    ;;
    ;; NOTE: this memory address is shared with `zp_title_timer`, as they can
    ;; never conflict with each other.
    zp_player_timer = $30       ; asan:ignore
    PLAYER_TIMER_VALUE = HZ * 2

    .ifdef PAL
        ;; Frame counter which resets every 5 frames.
        zp_pal_counter = $31
    .endif

    ;; Timer for the pause/unpause workflow.
    PAUSE_TIMER_VALUE = (HZ / 3)
    zp_pause_timer = $32

    ;; Index from the pool of bullets from which the sprite cycling function
    ;; will start on. This is constantly rotating so all bullets have at least
    ;; the chance to have the highest priority every now and then.
    zp_next_bullet_cycle = $33

    ;; The index for the first bullet from the bullets pool on sprite cycling.
    zp_first_bullet = $34

    ;; The index for the first enemy from the enemies pool on sprite cycling.
    zp_first_enemy = $36

    ;; Same as `zp_next_bullet_cycle` but for enemies.
    zp_next_enemy_cycle = $37

    ;; Switch from the title screen to the main screen. Note that this function
    ;; is to be called with the PPU disabled. If that's not the case, then it
    ;; will set the proper values to disable it on the next `nmi` call and set
    ;; the `title over` flag. With that, call again this function so the
    ;; switching is actually performed.
    .proc switch
        ;; Some things from here require the PPU to be disabled. Hence, if
        ;; that's not the case, disable it now. The `ppu` and the `title over`
        ;; flags are set as well.
        lda PPU::zp_mask
        beq @do_switch
        lda #%01000100
        ora Globals::zp_flags
        sta Globals::zp_flags
        lda #$00
        sta PPU::zp_mask
        rts

    @do_switch:
        ;; Get the assets ready for the main screen. That is, make sure that the
        ;; palettes and such are as desired since the title screen needed
        ;; another setup.
        jsr Assets::prepare_for_main_screen

        ;; Switch to the other base nametable.
        lda #%10001010
        sta PPU::zp_control

        ;; Enable back the PPU.
        lda #%00011110
        sta PPU::zp_mask

        ;; Setup the player timer.
        .ifdef PARTIAL
            lda #1
        .else
            lda #PLAYER_TIMER_VALUE
        .endif
        sta zp_player_timer

        ;; Mark the state of the game as "game". That is, the player has
        ;; started. Also set the `ppu` flag and unset the `title over` one.
        lda #%01000001
        ora Globals::zp_flags
        and #%11111011
        sta Globals::zp_flags

        rts
    .endproc

    .proc update
        lda zp_player_timer
        beq @game

        dec zp_player_timer
        beq @load_player

        ;; TODO: blinking of the selected player (every HZ count?).
        rts

    @load_player:
        jsr Player::init
        jsr Bullets::init
        jsr Enemies::init

        ;; Initialize pause timer.
        lda #0
        sta zp_pause_timer

        ;; Initialize variables for sprite cycling.
        sta zp_next_bullet_cycle
        sta zp_next_enemy_cycle

    @game:
        ;; Check if the player is toggling the `pause` state.
        lda #(Joypad::BUTTON_START | Joypad::BUTTON_SELECT)
        and Joypad::zp_buttons1
        beq @skip_pause_handling

        ;; What does the timer say, is the player allowed to do it?
        lda zp_pause_timer
        bne @skip_pause_handling

        ;; The timer is zero and the player asked to pause, let's reset the
        ;; timer.
        lda #PAUSE_TIMER_VALUE
        sta zp_pause_timer

        ;; Pause vs unpause.
        lda #%00001000
        and Globals::zp_flags
        bne @unpause

        ;; Pause: set the flag and skip the update.
        lda #%00001000
        ora Globals::zp_flags
        sta Globals::zp_flags
        rts

    @unpause:
        ;; Unset the flag and go to update.
        lda #%11110111
        and Globals::zp_flags
        sta Globals::zp_flags
        bne @do_update

    @skip_pause_handling:
        ;; Decrement the pause timer if it's not in a zero value.
        lda zp_pause_timer
        beq @pause_check
        dec zp_pause_timer

    @pause_check:
        ;; Are we paused? If so return before updating.
        lda #%00001000
        and Globals::zp_flags
        beq @do_update
        rts

        ;; This is the actual meat of the main game, which updates the state of
        ;; the player, bullets, enemies, etc.
    @do_update:
        jsr Player::update
        jsr Bullets::update
        jsr Enemies::update

        __fallthrough__ sprite_cycling
    .endproc

    .proc sprite_cycling
        ;; The 'y' register will contain the index on OAM of the sprite to be
        ;; allocated. Note that we skip the player as that is handled directly
        ;; as we want to guarantee that the player never flickers.
        ldy #(Player::PLAYER_SPRITES_COUNT * 4)

        ;;;
        ;; 1. Attempt to allocate the first spot for a bullet.

        ;; The 'x' register will index from the different sprite pools.
        ldx zp_next_bullet_cycle
        lda Bullets::zp_bullets_pool_base, x

        ;; Is this a valid bullet?
        cmp #$FF
        beq @after_first_bullet

        ;; It is a valid bullet! Set it now.
        lda Bullets::zp_bullets_pool_base + 1, x
        sta OAM::m_sprites, y
        iny

        ;; The tile selection depends on how many moves the bullet has done.
        lda Bullets::zp_bullets_pool_base, x
        and #%01111111
        cmp #Bullets::BULLET_LAST_TRANSITION
        bcs @last_bullet_tile
        cmp #Bullets::BULLET_FIRST_TRANSITION
        bcs @mid_bullet_tile
        lda #$0E
        bne @set_bullet_tile
    @mid_bullet_tile:
        lda #$0F
        bne @set_bullet_tile
    @last_bullet_tile:
        lda #$1E
    @set_bullet_tile:
        sta OAM::m_sprites, y

        iny
        lda #0
        sta OAM::m_sprites, y
        iny
        lda Bullets::zp_bullets_pool_base + 2, x
        sta OAM::m_sprites, y
        iny

    @after_first_bullet:
        ;; Save the index that was considered for the first bullet.
        stx zp_first_bullet     ; TODO: why not after the first ldx?

        ;; Increase the index for the bullets cycling. If wrapping is detected,
        ;; then it resets this value back to zero.
        inx
        inx
        inx
        cpx #Bullets::BULLETS_POOL_CAPACITY_BYTES
        bne @set_next_bullets_cycle
        ldx #0
    @set_next_bullets_cycle:
        stx zp_next_bullet_cycle

        ;;;
        ;; 2. Attempt to allocate the next spot for the first enemy.

        ;; Get the enemy status byte, while also preserving the current enemy
        ;; cycle index.
        ldx zp_next_enemy_cycle
        stx zp_first_enemy
        lda Enemies::zp_enemies_pool_base, x

        ;; Is this a valid enemy? If so allocate it and 'Enemies::allocate_x_y'
        ;; will be responsible for increasing the value of 'y' with the number
        ;; of sprites allocated (i.e. 16).
        cmp #$FF
        beq @after_first_enemy
        jsr Enemies::allocate_x_y

    @after_first_enemy:
        ;; Increase the index for the enemies cycling. If wrapping is detected,
        ;; then it resets this value back to zero.
        ldx zp_first_enemy
        inx
        inx
        inx
        cpx #Enemies::ENEMIES_POOL_CAPACITY_BYTES
        bne @set_next_enemies_cycle
        ldx #0
    @set_next_enemies_cycle:
        stx zp_next_enemy_cycle

        ;; TODO: ensure 1 item
        ;; iny
        ;; iny
        ;; iny
        ;; iny

        ldx #0
    @rest_o_bullets:
        cpx #Bullets::BULLETS_POOL_CAPACITY_BYTES
        beq @rest_o_enemies
        cpx zp_first_bullet
        bne @do_bullet
        inx
        inx
        inx
        cpx #Bullets::BULLETS_POOL_CAPACITY_BYTES
        beq @rest_o_enemies
    @do_bullet:
        lda Bullets::zp_bullets_pool_base, x
        cmp #$FF
        beq @next_bullet

        lda Bullets::zp_bullets_pool_base + 1, x
        sta OAM::m_sprites, y
        iny

        ;; The tile selection depends on how many moves the bullet has done.
        lda Bullets::zp_bullets_pool_base, x
        and #%01111111
        cmp #Bullets::BULLET_LAST_TRANSITION
        bcs @other_last_bullet_tile
        cmp #Bullets::BULLET_FIRST_TRANSITION
        bcs @other_mid_bullet_tile
        lda #$0E
        bne @other_set_bullet_tile
    @other_mid_bullet_tile:
        lda #$0F
        bne @other_set_bullet_tile
    @other_last_bullet_tile:
        lda #$1E
    @other_set_bullet_tile:
        sta OAM::m_sprites, y

        iny
        lda #0
        sta OAM::m_sprites, y
        iny
        lda Bullets::zp_bullets_pool_base + 2, x
        sta OAM::m_sprites, y
        iny

    @next_bullet:
        inx
        inx
        inx
        jmp @rest_o_bullets

        ;; Allocate the rest of the valid enemies from the pool.
    @rest_o_enemies:
        ldx #0
    @rest_o_enemies_loop:
        ;; If we are already passed the amount of bytes we could allocate for
        ;; enemies, then jump to items. If the current indexed enemy is the one
        ;; we allocated as the first fixed one, then skip it.
        cpx #Enemies::ENEMIES_POOL_CAPACITY_BYTES
        beq @rest_o_items
        cpx zp_first_enemy
        beq @next_enemy

    @do_enemy:
        ;; Ok, so the enemy has not been allocated yet and we have space for
        ;; it. Is it valid?
        lda Enemies::zp_enemies_pool_base, x
        cmp #$FF
        beq @next_enemy

        ;; Yes! Then call the enemy allocator with the values we have now. Note
        ;; that the 'y' register will be updated as desired, but the 'x'
        ;; register will become bananas. Hence, save its value before calling
        ;; and restore it back after the call.
        stx Globals::zp_tmp3
        jsr Enemies::allocate_x_y
        ldx Globals::zp_tmp3

    @next_enemy:
        inx
        inx
        inx
        jmp @rest_o_enemies_loop

    @rest_o_items:
        ;;; TODO

        ;; Are all spots already filled? As in, did the 'y' register wrap
        ;; around? If so, just go to the end.
        tya
        beq @end

        ;; We are done with all the sprites we wanted to allocate. Now let's
        ;; clear out the rest of the slots just in case there was some leftover
        ;; from a past sprite. Since the OAM space is 256 bytes long, we just
        ;; need for the 'y' register to wrap around in order to quit.
        lda #$EF
    @reset_sprite:
        sta OAM::m_sprites, y
        iny
        iny
        iny
        iny
        bne @reset_sprite
    @end:
        rts
    .endproc

    .ifdef PAL
        ;; All the code that is needed to fix some values for PAL machines.
        .proc pal_handler
            ;; Check if 5 frames have passed since last counter reset.
            lda Driver::zp_pal_counter
            cmp #4
            beq @do_handle

            ;; Nope! Reset the player's step on PAL and increase the counter.
            lda #1
            sta Player::zp_step_on_pal
            inc Driver::zp_pal_counter
            bne @end

        @do_handle:
            ;; Increase the step just for this frame and reset the counter.
            lda Player::zp_step_on_pal
            clc
            adc #2
            sta Player::zp_step_on_pal
            lda #0
            sta Driver::zp_pal_counter
        @end:
            rts
        .endproc
    .endif
.endscope
