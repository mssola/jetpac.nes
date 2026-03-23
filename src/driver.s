.segment "CODE"

.scope Driver
    ;; Timer for the player to be able to pick up the joypad upon entering the
    ;; game (either when transitioning from the title or after losing a life).
    ;;
    ;; NOTE: this memory address is shared with `zp_title_timer`, as they can
    ;; never conflict with each other.
    zp_player_timer = $30       ; asan:ignore
    PLAYER_TIMER_FULL_VALUE = HZ * 3
    PLAYER_TIMER_DEV_VALUE = HZ / 4
    .ifdef PARTIAL
        PLAYER_TIMER_VALUE = PLAYER_TIMER_DEV_VALUE
    .else
        PLAYER_TIMER_VALUE = PLAYER_TIMER_FULL_VALUE
    .endif

    ;; The amount of time it's allowed to pass before changing the blinking
    ;; animation for the "1UP"/"2UP" strings from the HUD.
    ;;
    ;; NOTE: this only applies to the real game (i.e. we don't care about
    ;; 'PLAYER_TIMER_DEV_VALUE').
    BLINKING_TIME = PLAYER_TIMER_FULL_VALUE / 8

    ;; Bitmap containing how NMI code should proceed with the blinking
    ;; animation. Only two bits are used:
    ;;   - 7: whether the blinking animation should even be considered.
    ;;   - 6: the blinking phase.
    zp_blink_status = $2E

    ;; The timer for the blinking animation. Initialized to 'BLINKING_TIME', the
    ;; blinking phase is changed whenever it reaches zero.
    zp_blink_timer = $2F

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

    ;; Bitmap of various boolean values lumped together.
    ;;
    ;; |SP-- -MDT|
    ;; |
    ;; |- S: whether Sprites have already been moved out in the
    ;; |     'move_sprites_out' situation.
    ;; |- P: whether the Pause message on the HUD has to be toggled.
    ;; |- M: the shuttle should Move. Only used coupled with T.
    ;; |- D: the taking off animation should be moving downwards.
    ;; |- T: the rocket is Taking off.
    zp_flags = $38

    ;; Initialization routine that is to be called before enabling NMIs back for
    ;; the first time.
    .proc init_before_nmi
        lda #0
        sta Driver::zp_blink_status
        sta Driver::zp_flags

        rts
    .endproc

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
        lda #PLAYER_TIMER_VALUE
        sta Driver::zp_player_timer

        ;; Initialize the blinking animation.
        lda #BLINKING_TIME
        sta Driver::zp_blink_timer
        lda #0
        sta Driver::zp_blink_status

        ;; Initialize lifes for both players.
        lda #4
        sta Player::zp_lifes
        sta Player::zp_lifes + 1
        lda Player::zp_state
        ora #%00001000
        sta Player::zp_state

        ;; Prepare the items for the scene.
        jsr Items::prepare_background_scene
        jsr Items::init_level

        ;; Mark the state of the game as "game". That is, the player has
        ;; started. Also set the `ppu` flag and unset the `title over` one.
        lda #%01000001
        ora Globals::zp_flags
        and #%11111011
        sta Globals::zp_flags

        rts
    .endproc

    ;; Move enemies and bullets out of the screen. This is done by setting the
    ;; 'inactive' state for each object.
    .proc move_sprites_out
        ldx #0
        lda #$FF

        ;; Invalidate all enemies.
        ldy #Enemies::ENEMIES_POOL_CAPACITY
    @enemies_reset_loop:
        sta Enemies::zp_pool_base, x
        NEXT_ENEMY_INDEX_X
        dey
        bne @enemies_reset_loop

        ;; Invalidate all bullets.
        ldx #0
        ldy #Bullets::BULLETS_POOL_CAPACITY
    @bullets_reset_loop:
        sta Bullets::zp_pool_base, x
        NEXT_BULLET_INDEX_X
        dey
        bne @bullets_reset_loop

        ;; Set that we have done this operation so it's not done in future
        ;; cycles.
        lda Driver::zp_flags
        ora #$80
        sta Driver::zp_flags

        rts
    .endproc

    .proc update
        ;; Are we in the shuttle transition?
        lda Driver::zp_flags
        and #$01
        beq @check_player_timer

        ;; Yes! Then just handle the shuttle animation and move into sprite
        ;; cycling.
        JAL Driver::handle_shuttle

    @check_player_timer:
        ;; If the player timer is over, jump to the game immediately. Otherwise
        ;; decrement the counter.
        lda zp_player_timer
        beq @game

        dec zp_player_timer
        beq @load_player

        ;; Decrement the blinking timer. If it reaches zero, then it's time to
        ;; change its phase.
        dec Driver::zp_blink_timer
        bne @no_update

        ;; Tell NMI code to change the blinking animation, and flip the bit
        ;; regulating which phase.
        lda Driver::zp_blink_status
        eor #%01000000
        ora #%10000000
        sta Driver::zp_blink_status

        ;; And initialize again the blinking timer.
        lda #BLINKING_TIME
        sta Driver::zp_blink_timer

    @no_update:
        rts

    @load_player:
        ;; Clear out any leftovers from the blinking animation.
        lda #%10000000
        sta Driver::zp_blink_status
        lda #0
        sta Driver::zp_blink_timer

        jsr Player::init
        jsr Bullets::init
        jsr Enemies::init
        jsr Explosions::init
        jsr Items::init

        ;; Initialize pause timer.
        lda #0
        sta zp_pause_timer

        ;; Clear out the 'S' flag.
        lda Driver::zp_flags
        and #$7F
        sta Driver::zp_flags

        ;; Initialize variables for sprite cycling.
        sta zp_next_bullet_cycle
        sta zp_next_enemy_cycle

    @game:
        ;; Has the player died?
        lda Globals::zp_flags
        and #$10
        bne @do_minimal_update

        ;; Check if the player is toggling the `pause` state.
        lda #(Joypad::BUTTON_START | Joypad::BUTTON_SELECT)
        and Joypad::zp_buttons
        beq @skip_pause_handling

        ;; What does the timer say, is the player allowed to do it?
        lda zp_pause_timer
        bne @skip_pause_handling

        ;; The timer reached zero, but is the player actually just holding the
        ;; button? If so ignore it until it unholds it.
        eor Joypad::zp_prev
        and #(Joypad::BUTTON_START | Joypad::BUTTON_SELECT)
        bne @skip_pause_handling

        ;; Let's reset the timer.
        lda #PAUSE_TIMER_VALUE
        sta zp_pause_timer

        ;; Toggle the message on the HUD.
        lda Driver::zp_flags
        ora #$40
        sta Driver::zp_flags

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
    @do_minimal_update:
        jsr Explosions::update
        jsr Items::update

        ;; Has the player died? If it is dead, then we need to remove all
        ;; sprites except for objects and explosions, and whenever
        ;; explosions/items are done moving we can set the timer again to start
        ;; over with the game screen.
        lda Globals::zp_flags
        and #$10
        bne @player_got_toasted

        ;; Nope, the player is just fine. Just an extra check: do we have all
        ;; shuttle parts?
        lda Items::zp_collected
        cmp #9
        bne @sprite_cycling

        ;; Yes, we do! Then we check if the player is colliding with the shuttle
        ;; platform. If so it's time to blast off
        jsr Items::player_in_shuttle
        beq @sprite_cycling
        JAL Driver::init_take_off

    @player_got_toasted:
        ;; Invalidate bullets and enemies if we haven't already.
        bit Driver::zp_flags
        bmi @check_explosions
        jsr move_sprites_out

    @check_explosions:
        ;; Are there still active explosions?
        lda Explosions::zp_active
        bne @sprite_cycling

        ;; Are there still falling items?
        lda Items::zp_state
        and #$03
        bne @sprite_cycling

        ;; After all the explosions/items have been done, is any player alive?
        lda Globals::zp_multiplayer
        and #%00000110
        bne @reset_timers

        ;; No! Set the game over bit (with or without coin).
        lda Globals::zp_flags
        ora #%00000010
        sta Globals::zp_flags
        lda Items::zp_state
        and #$04
        bne @invalidate_items
        lda Globals::zp_flags
        and #$FE
        sta Globals::zp_flags

    @invalidate_items:
        ;; Invalidate items, which were skipped on move_sprites_out() on purpose
        ;; to keep them after each death. But since we are about to go to the
        ;; title screen, now they are no longer useful.
        jsr Items::invalidate_all

    @reset_timers:
        jsr Driver::reset_timers

    @sprite_cycling:
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
        lda Bullets::zp_pool_base, x

        ;; Is this a valid bullet?
        cmp #$FF
        beq @after_first_bullet

        ;; It is a valid bullet! Set it now.
        lda Bullets::zp_pool_base + 1, x
        sta OAM::m_sprites, y
        iny

        ;; The tile selection depends on how many moves the bullet has done.
        lda Bullets::zp_pool_base, x
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
        lda #1
        sta OAM::m_sprites, y
        iny
        lda Bullets::zp_pool_base + 2, x
        sta OAM::m_sprites, y
        iny

    @after_first_bullet:
        ;; Save the index that was considered for the first bullet.
        stx zp_first_bullet

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
        lda Enemies::zp_pool_base, x

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
        NEXT_ENEMY_INDEX_X
        cpx #Enemies::ENEMIES_POOL_CAPACITY_BYTES
        bne @set_next_enemies_cycle
        ldx #0
    @set_next_enemies_cycle:
        stx zp_next_enemy_cycle

        ;; Allocate all valid items. Items, contrary to other sprites, don't get
        ;; the special "you get a fixed first position" like others, mainly
        ;; because there are so few of them on screen at any given time. For
        ;; this reason as well, it's ok to just dump them all here before the
        ;; rest of sprites are churned in.
        ldx #0
    @rest_o_items:
        cpx #Items::POOL_CAPACITY_BYTES
        beq @rest_o_bullets

        lda Items::zp_pool_base, x
        cmp #$FF
        beq @next_item
        jsr Items::allocate_x_y

    @next_item:
        NEXT_ITEM_INDEX_X
        jmp @rest_o_items

        ;; Allocate the rest of valid bullets from the pool.
        ldx #0
    @rest_o_bullets:
        ;; If we are already passed the amount of bytes we could allocate for
        ;; bullets, then jump to enemies. If the current indexed bullet is the one
        ;; we allocated as the first fixed one, then skip it.
        cpx #Bullets::BULLETS_POOL_CAPACITY_BYTES
        beq @rest_o_enemies
        cpx zp_first_bullet
        beq @next_bullet

    @do_bullet:
        ;; Ok, so the bullet has not been allocated yet and we have space for
        ;; it. Is it valid?
        lda Bullets::zp_pool_base, x
        cmp #$FF
        beq @next_bullet

        ;; Yes! Then allocate now.

        lda Bullets::zp_pool_base + 1, x
        sta OAM::m_sprites, y
        iny

        ;; The tile selection depends on how many moves the bullet has done.
        lda Bullets::zp_pool_base, x
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
        lda Bullets::zp_pool_base + 2, x
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
        beq @do_explosions
        cpx zp_first_enemy
        beq @next_enemy

    @do_enemy:
        ;; Ok, so the enemy has not been allocated yet and we have space for
        ;; it. Is it valid?
        lda Enemies::zp_pool_base, x
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
        NEXT_ENEMY_INDEX_X
        jmp @rest_o_enemies_loop

        ;; At the very end, we allocate any active explosion.
    @do_explosions:
        ldx #0
    @explosions_loop:
        ;; If we are already passed the amount of bytes we could allocate for
        ;; explosions, then break the loop.
        cpx #Explosions::EXPLOSIONS_POOL_CAPACITY_BYTES
        beq @after_explosions

    @do_explosion:
        ;; Is it valid?
        lda Explosions::zp_pool_base, x
        and #$80
        beq @next_explosion

        ;; Yes! Then call the explosion allocator with the values we have
        ;; now. Note that the 'y' register will be updated as desired, but the
        ;; 'x' register will become bananas. Hence, save its value before
        ;; calling and restore it back after the call.
        stx Globals::zp_tmp3
        jsr Explosions::allocate_x_y
        ldx Globals::zp_tmp3

    @next_explosion:
        NEXT_EXPLOSION_INDEX_X
        jmp @explosions_loop

    @after_explosions:
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
            beq @reset_movement_arg
            cmp #4
            beq @do_handle

        @player_timer_reset:
            ;; Nope! Reset the player's step on PAL and increase the counter.
            lda #1
            sta Player::zp_step_on_pal
            inc Driver::zp_pal_counter
            bne @end

        @reset_movement_arg:
            ;; Restore the enemy movement to the same value as NTSC.
            dec Enemies::zp_movement_arg
            jmp @player_timer_reset

        @do_handle:
            ;; Increase the step just for this frame and reset the counter.
            lda Player::zp_step_on_pal
            clc
            adc #2
            sta Player::zp_step_on_pal
            lda #0
            sta Driver::zp_pal_counter

            ;; Increase the movement arg for this frame. This way we catch up to
            ;; the NTSC real velocity on screen.
            inc Enemies::zp_movement_arg

        @end:
            rts
        .endproc
    .endif

    ;; Reset all timers which are relevant for entering a new screen.
    .proc reset_timers
        ;; Reset the player's timer to enter the game screen again.
        lda #PLAYER_TIMER_VALUE
        sta zp_player_timer

        ;; Restart the blinking animation.
        lda #BLINKING_TIME
        sta Driver::zp_blink_timer
        lda #$80
        sta Driver::zp_blink_status

        rts
    .endproc

    ;; Initialize the "take off" animation. From this point forward the
    ;; Drivers::update() function will no longer go through its normal route
    ;; and it will just call Drivers::handle_shuttle().
    ;;
    ;; Hence, this function sets/unsets all the relevant flags, and sets
    ;; 'OAM::m_sprites' to only contain the sprites for the animation. The 'ppu'
    ;; and 'shuttle' flags will also be touched so any background elements from
    ;; the shuttle are also cleared out.
    .proc init_take_off
        ;;;
        ;; Manually create all 12 sprites that make up the shuttle in the take
        ;; off animation. This is seemingly a lot of code, but it's just sprite
        ;; initialization over and over.

        ;; Y screen coordinates.
        lda #Background::GROUND_Y_COORD - 48
        sta OAM::m_sprites
        sta OAM::m_sprites + 4

        lda #Background::GROUND_Y_COORD - 40
        sta OAM::m_sprites + 8
        sta OAM::m_sprites + 12

        lda #Background::GROUND_Y_COORD - 32
        sta OAM::m_sprites + 16
        sta OAM::m_sprites + 20

        lda #Background::GROUND_Y_COORD - 24
        sta OAM::m_sprites + 24
        sta OAM::m_sprites + 28

        lda #Background::GROUND_Y_COORD - 16
        sta OAM::m_sprites + 32
        sta OAM::m_sprites + 36

        lda #Background::GROUND_Y_COORD - 8
        sta OAM::m_sprites + 40
        sta OAM::m_sprites + 44

        ;; Tile IDs
        lda #$04
        sta OAM::m_sprites + 1
        lda #$05
        sta OAM::m_sprites + 5

        lda #$14
        sta OAM::m_sprites + 9
        lda #$15
        sta OAM::m_sprites + 13

        lda #$06
        sta OAM::m_sprites + 17
        lda #$07
        sta OAM::m_sprites + 21

        lda #$16
        sta OAM::m_sprites + 25
        lda #$17
        sta OAM::m_sprites + 29

        lda #$08
        sta OAM::m_sprites + 33
        lda #$09
        sta OAM::m_sprites + 37

        lda #$42
        sta OAM::m_sprites + 41
        lda #$43
        sta OAM::m_sprites + 45

        ;; Zero out attributes
        lda #0
        sta OAM::m_sprites + 2
        sta OAM::m_sprites + 6
        sta OAM::m_sprites + 10
        sta OAM::m_sprites + 14
        sta OAM::m_sprites + 18
        sta OAM::m_sprites + 22
        sta OAM::m_sprites + 26
        sta OAM::m_sprites + 30
        sta OAM::m_sprites + 34
        sta OAM::m_sprites + 38
        sta OAM::m_sprites + 42
        sta OAM::m_sprites + 46

        ;; X screen coordinates.
        lda #Items::DROPPING_SCREEN_X
        sta OAM::m_sprites + 3
        sta OAM::m_sprites + 11
        sta OAM::m_sprites + 19
        sta OAM::m_sprites + 27
        sta OAM::m_sprites + 35
        sta OAM::m_sprites + 43

        lda #Items::DROPPING_SCREEN_X + 8
        sta OAM::m_sprites + 7
        sta OAM::m_sprites + 15
        sta OAM::m_sprites + 23
        sta OAM::m_sprites + 31
        sta OAM::m_sprites + 39
        sta OAM::m_sprites + 47

        ;;;
        ;; Clear out the rest of the sprites. Note that this is done manually
        ;; and not via the rest of helper functions because it's faster and it
        ;; touches 'OAM::m_sprites' directly.

        ldx #(12 * 4)           ; NOTE: 12 sprites from the shuttle.
        lda #$FF
    @clear_loop:
        sta OAM::m_sprites, x
        inx
        inx
        inx
        inx
        bne @clear_loop

        ;;;
        ;; Flags and stuff.

        ;; Enable the 'T' flag. That is, we signal to the Driver::update()
        ;; function that the "take off" animation is going on and it should call
        ;; Driver::handle_shuttle() instead of going the regular route.
        ;;
        ;; NOTE: all other flags are cleared out on purpose as they are no
        ;; longer relevant.
        lda #1
        sta Driver::zp_flags

        ;; Force the shuttle to be removed from the background (see interrupt.s
        ;; for the specific handling for this).
        lda #0
        sta Items::zp_collected

        ;; Enable the 'ppu' and the 'shuttle' flags. This, coupled with the
        ;; previous zeroing out of 'Items::zp_collected', makes the background
        ;; shuttle disappear in favor of the animated meta-sprite.
        lda Globals::zp_flags
        ora #%01100000
        sta Globals::zp_flags

        rts
    .endproc

    ;; Handle the "take off" animation from the shuttle. That is, move it
    ;; upwards/downwards depending on the 'D' bit, and check for "collisions" on
    ;; certain spots where the animation should flip or be over.
    .proc handle_shuttle
        ;; Move the shuttle every other frame.
        lda Driver::zp_flags
        eor #$04
        sta Driver::zp_flags
        and #$04
        beq @end

        ;; Move all sprites from the shuttle up/down depending on the 'D' flag.
        ldx #0
    @loop:
        ;; To always check whether the 'D' flag is set on each sprite is
        ;; admittedly not the most performant thing to do. But it's easy and
        ;; this function is literally the only thing that will be done
        ;; computing-wise, so whatever...
        lda Driver::zp_flags
        and #$02
        beq @up
        inc OAM::m_sprites, x
        jmp @next
    @up:
        dec OAM::m_sprites, x

    @next:
        ;; The rocket is made up of 12 sprites, and each one takes 4 bytes on
        ;; OAM space.
        inx
        inx
        inx
        inx
        cpx #(12 * 4)
        bne @loop

        ;; Is the shuttle at a limit when it should either flip the 'D' bit or
        ;; declare the animation to be over?
        lda Driver::zp_flags
        and #$02
        lsr
        tax
        lda limits, x
        cmp OAM::m_sprites
        bne @end

        ;; Flip the 'D' bit. If doing so results on a zero bit, then we know we
        ;; are back at the ground and hence we should stop the
        ;; animation. Otherwise we should store the result so we move downwards
        ;; next time.
        lda Driver::zp_flags
        eor #$02
        tax
        and #$02
        bne @set

        ;; The animation is over. Reset the flags to the expected 'S' one. Not
        ;; that we care too much about it, but at least we will be consistent
        ;; with player's death and other scenarios like that.
        lda #$80
        sta Driver::zp_flags

        ;; Increase the level :)
        inc Globals::zp_level
        lda Globals::zp_level
        and #%00000111
        sta Globals::zp_level_kind

        ;; Just like we did in Drivers::switch(), we re-initialize some things
        ;; like timers and the items. Note that re-setting the timers will force
        ;; the Drivers::update() function to re-initialize most things
        ;; (e.g. enemies).
        jsr Driver::reset_timers
        jsr Items::init_level

        ;; Enable the 'ppu' and the 'shuttle' flags, so the shuttle is back into
        ;; the background.
        lda Globals::zp_flags
        ora #%01100000
        sta Globals::zp_flags

        rts

    @set:
        stx Driver::zp_flags

    @end:
        rts

    limits:
        .byte Background::UPPER_MARGIN_Y_COORD, Background::GROUND_Y_COORD - 48
    .endproc

    ;; Toggle the "Paused" message from the (not quite) HUD.
    ;;
    ;; NOTE: only call this function from NMI code.
    .proc hud_toggle_pause
        ;; Unset the 'P' flag.
        lda Driver::zp_flags
        and #%10111111
        sta Driver::zp_flags

        lda #%00001000
        and Globals::zp_flags
        bne @paused

        ;; Clear out the "Paused" message.
        bit PPU::m_status
        lda #$28
        sta PPU::m_address
        lda #$8D
        sta PPU::m_address
        lda #0
        sta PPU::m_data
        sta PPU::m_data
        sta PPU::m_data
        sta PPU::m_data
        sta PPU::m_data
        sta PPU::m_data
        rts

    @paused:
        bit PPU::m_status
        lda #$28
        sta PPU::m_address
        lda #$8D
        sta PPU::m_address

        lda #$2A                ; P
        sta PPU::m_data
        lda #$1B                ; A
        sta PPU::m_data
        lda #$2F                ; U
        sta PPU::m_data
        lda #$2D                ; S
        sta PPU::m_data
        lda #$1F                ; E
        sta PPU::m_data
        lda #$1E                ; D
        sta PPU::m_data

        rts
    .endproc

    ;; Toggle the blinking animations from the "1UP"/"2UP" strings on the HUD
    ;; depending on the currently selected player.
    ;;
    ;; This function expects the 'Globals::zp_nmi_reserved' to be set with the
    ;; addition to be performed on each base character in order to set the
    ;; proper animation phase (i.e. either "#$00" or "#$70").
    ;;
    ;; NOTE: only call this function from NMI code.
    .proc blink_player_selection
        bit PPU::m_status

        ;; Which player are we talking about?
        lda Globals::zp_multiplayer
        and #$01
        bne @player_2

        ;; Player 1.
        lda #$28
        sta PPU::m_address
        lda #$44
        sta PPU::m_address
        lda #$11
        bne @set_data
    @player_2:
        ldx #$12
        lda #$28
        sta PPU::m_address
        lda #$5A
        sta PPU::m_address
        lda #$12

    @set_data:
        ;; 1/2
        clc
        adc Globals::zp_nmi_reserved
        sta PPU::m_data

        ;; 'U'
        lda #$2F
        clc
        adc Globals::zp_nmi_reserved
        sta PPU::m_data

        ;; 'P'
        lda #$2A
        clc
        adc Globals::zp_nmi_reserved
        sta PPU::m_data

        rts
    .endproc
.endscope
