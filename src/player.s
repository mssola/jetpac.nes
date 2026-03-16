.segment "CODE"

;; Translate the given fixed-point 16-bit position into screen coordinates and
;; leave it into the `a` register.
;;
;; NOTE: see the documentation on player's movement for more information.
.macro FIXED_POINT_POSITION_TO_SCREEN POS_ADDR
    ;; We save the high byte into a temporary value, and we load the low byte
    ;; into the accumulator.
    lda POS_ADDR + 1
    sta Globals::zp_tmp0
    lda POS_ADDR

    ;; And now it's a matter of rotating the high byte into the low one to
    ;; match a full byte.
    lsr Globals::zp_tmp0
    ror
    lsr Globals::zp_tmp0
    ror
    lsr Globals::zp_tmp0
    ror
    lsr Globals::zp_tmp0
    ror
.endmacro

;; Functions and variables that keep up with the player's sprite. That is,
;; movement, heading, animation, collision with the environment, etc.
.scope Player
    ;;;
    ;; *Movement* is done with subpixel precision. Hence, we need to handle
    ;; things via fixed-point arithemetic. In particular, the `zp_screen_*`
    ;; variables refer to pure screen coordinates, and they are the only uint8_t
    ;; variables. As for the rest:
    ;;
    ;;  - Velocity (actual and target) are 4.4 fixed-point signed values. Hence,
    ;;    the high nibble represents the signed integer part, and the low nibble
    ;;    the fractional one.
    ;;  - Each Position is a 16-bit signed fixed-point value in little-endian
    ;;    format like so: |llll/ffff| - |0000/hhhh|. That is, the low byte is
    ;;    split with the fractional part and the low nibble of the integer part,
    ;;    and the high byte only contains the high nibble of the signed integer
    ;;    part (and the high nibble of that high byte is discarded).
    ;;
    ;; This has the following properties:
    ;;
    ;;  - Adding the velocity to a position is just a matter of performing an
    ;;    `adc` between the low byte of the position and the velocity.
    ;;  - Translating positions into screen coordinates it's a matter of simply
    ;;    rolling the low nibble of the high byte into the low byte.

    ;; The height and width of the player. The "left offset" are the pixels to
    ;; the left which are ignored for collision checks.
    PLAYER_HEIGHT = $18
    PLAYER_WAIST  = $0C
    PLAYER_WIDTH  = $10
    LEFT_OFFSET   = $02

    ;; The initial position is the ground minus the height of the sprite (as the
    ;; Y accounts for the top left pixel). For the high byte we only want to
    ;; high nibble put into its low nibble, and for the low byte we shift the
    ;; low nibble into a high one and leave subpixels to 0.
    INIT_Y_POSITION_LO = ((Background::GROUND_Y_COORD - PLAYER_HEIGHT) & $0F) << 4
    INIT_Y_POSITION_HI = (Background::GROUND_Y_COORD - PLAYER_HEIGHT) >> 4

    ;; The initial position on the X axis is right below the mid platform.
    INIT_X_POSITION_LO = $00
    INIT_X_POSITION_HI = $08

    ;; Different acceleration/velocity constants.
    ;;
    ;; NOTE: automatically generated via `bin/values.rb`. Check the
    ;; `config/values.yml` to understand the meaning of each constant.
    .include "../config/values/player.s"

    zp_screen_y          = $40
    zp_position_y        = $41  ; asan:reserve $02
    zp_velocity_y        = $44

    zp_screen_x          = $45
    zp_position_x        = $46  ; asan:reserve $02
    zp_velocity_x        = $49

    ;; Flags that manage the state of the player.
    ;;
    ;; | Bit | Short name | Meaning when set                              |
    ;; |-----+------------+-----------------------------------------------|
    ;; |   7 | thrust     | Player is hitting the thrust                  |
    ;; |   6 | heading    | heading right                                 |
    ;; | 5-4 | -          | Unused                                        |
    ;; |   3 | life       | Lifes should be updated on screen             |
    ;; |   2 | update     | Sprite (animation or heading) must be updated |
    ;; | 1-0 | walk       | 0: still; 1: animation 1; 2: animation 2      |
    zp_state = $50

    ;; Simple counter for the walking animation.
    zp_walk_counter = $51

    .ifdef PAL
        ;; The increment/decrement to be applied to the velocity on a PAL
        ;; system. This value is updated on `driver.s` on each frame.
        ;;
        ;; NOTE: only used on PAL.
        zp_step_on_pal = $52
    .endif

    ;; Lifes for both players.
    zp_lifes = $53              ; asan:reserve $02

    ;; How many animations are there for walking?
    WALK_ANIMATION_NR = 3

    ;; How many frames are we allowing for each walk animation state?
    WALK_COUNTER_MAX = (HZ / 10)

    ;; Number of sprites from which the player is made of.
    PLAYER_SPRITES_COUNT = 6

    ;; Initialize the player's sprite. Note that for the sprite to look
    ;; correctly on screen you still need to call `Player::update` afterwards.
    .proc init
        ;; Make sure that the 'dead' bit from the global flags is zeroed out.
        lda Globals::zp_flags
        and #%11101111
        sta Globals::zp_flags

        ;; Initial state.
        lda #%01000100
        sta zp_state

        ;; Set the step to be applied on PAL.
        .ifdef PAL
            lda #1
            sta zp_step_on_pal
        .endif

        ;; Reset velocity and walking counter.
        lda #0
        sta zp_velocity_y
        sta zp_velocity_x
        sta zp_walk_counter

        ;; Set position, and the screen coordinates will be updated upong
        ;; calling `update`, which on initialization will happen right after.
        lda #INIT_Y_POSITION_LO
        sta zp_position_y
        lda #INIT_Y_POSITION_HI
        sta zp_position_y + 1
        lda #INIT_X_POSITION_LO
        sta zp_position_x
        lda #INIT_X_POSITION_HI
        sta zp_position_x + 1

        rts
    .endproc

    ;; Call this function to update anything player-related. Ideally this should
    ;; be called on each game iteration for the main screen, and after the
    ;; controller has been read.
    .proc update
        ;; Update both vertical and horizontal positions.
        jsr update_vertical_position
        jsr update_horizontal_position

        ;; If throttling, then reset the walking counter and the walk state.
        bit zp_state
        bpl @walk_animation
        lda #0
        sta zp_walk_counter
        lda #%11111100
        and zp_state
        sta zp_state
        jmp @to_screen

    @walk_animation:
        ;; If the player is not even moving, skip the animation.
        lda zp_velocity_x
        beq @to_screen

        ;; Increase the counter and check for its maximum value.
        inc zp_walk_counter
        lda zp_walk_counter
        cmp #WALK_COUNTER_MAX
        bne @to_screen

        ;; The counter has reached the maximum value. Increase the walk state.
        lda zp_state
        tax
        and #%00000011
        clc
        adc #1
        cmp #WALK_ANIMATION_NR
        bne @set_animation
        lda #0
    @set_animation:
        sta Globals::zp_tmp0
        txa
        and #%11111100
        ora Globals::zp_tmp0
        sta zp_state

        ;; And reset the counter.
        lda #0
        sta zp_walk_counter

    @to_screen:
        ;; Translate fixed-point positions to screen coordinates.
        FIXED_POINT_POSITION_TO_SCREEN zp_position_y
        sta zp_screen_y
        FIXED_POINT_POSITION_TO_SCREEN zp_position_x
        sta zp_screen_x

        ;; We have the newly proposed screen coordinates. Now let's check if
        ;; that collides with some background element. If that's the case,
        ;; handle ejection logic now.
        jsr background_check

        ;; After we have a new velocity while taking the background into
        ;; account. Are we suddently falling?
        lda zp_velocity_y
        beq @do_update_sprites
        bmi @do_update_sprites
        bit zp_state
        bmi @do_update_sprites

        ;; We are falling: we were at a walking state and now we are falling.
        ;; This happens whenever we fall from a platform by walking. The
        ;; original game then switched into airborne state, so let's do that. In
        ;; particular, we reset the walking counter, the walk state, and we flip
        ;; the `thrust` flag.
        lda #0
        sta zp_walk_counter
        lda #%11111100
        and zp_state
        lda #%10000000
        ora zp_state
        sta zp_state

    @do_update_sprites:
        ;; And with that, update all the sprites with the information we have
        ;; collected (i.e. heading, thrust, coordinates).
        JAL update_sprites
    .endproc

    ;; Updates the `zp_velocity_y` and the `zp_position_y` depending on whether
    ;; the player is throttling or gravity should just apply.
    .proc update_vertical_position
        ;; Is the player airborne and asking to hover? If so we can just skip
        ;; everything.
        bit zp_state
        bpl @check_thrust
        lda #Joypad::BUTTON_DOWN
        and Joypad::zp_buttons
        beq @check_thrust
        lda #0
        sta zp_velocity_y
        rts

    @check_thrust:
        ;; Check if the player is asking to thrust, otherwise apply gravity.
        lda #(Joypad::BUTTON_UP | Joypad::BUTTON_A)
        and Joypad::zp_buttons
        beq @set_gravity

        ;; Player is throttling, reflect that on the player's state.
        lda #%10000100
        ora zp_state
        sta zp_state

        ;; If the current velocity is zero, then we are "blasting off", and a
        ;; bit of animation plus special velocity should occur. Otherwise we
        ;; should apply the regular thrust velocity.
        lda zp_velocity_y
        beq @blast_off
        lda #THRUST
        bne @compute_vertical

    @set_gravity:
        lda #GRAVITY

    @compute_vertical:
        sta Globals::zp_tmp0

        ;; Check the difference between the given target velocity and what we
        ;; have now. If it equals to zero, then we change nothing in regards to
        ;; the velocity.
        lda zp_velocity_y
        sec
        sbc Globals::zp_tmp0
        beq @apply_velocity

        ;; Increase or decrease depending on what we have now. Note that how
        ;; this is done depends on whether we are on NTSC or PAL.
        bmi @down
        .ifdef PAL
            lda zp_velocity_y
            sec
            sbc zp_step_on_pal
            sta zp_velocity_y
        .else
            dec zp_velocity_y
        .endif
        jmp @apply_velocity
    @down:
        .ifdef PAL
            lda zp_velocity_y
            clc
            adc zp_step_on_pal
            sta zp_velocity_y
        .else
            inc zp_velocity_y
        .endif
        jmp @apply_velocity

    @blast_off:
        lda #BLAST_OFF
        sta zp_velocity_y
        jmp @going_up

    @apply_velocity:
        lda zp_velocity_y
        bmi @going_up

        ;; The velocity is positive, so it's just a 16-bit addition.
        clc
        adc zp_position_y
        sta zp_position_y
        lda #0
        adc zp_position_y + 1
        sta zp_position_y + 1
        rts

    @going_up:
        ;; Negative velocity, we need to go up. This is probably not optimal,
        ;; but we just invert the number and subtract with that.
        lda #0
        sec
        sbc zp_velocity_y
        sta Globals::zp_tmp0
        lda zp_position_y
        sec
        sbc Globals::zp_tmp0
        sta zp_position_y
        lda zp_position_y + 1
        sbc #0
        sta zp_position_y + 1

        rts
    .endproc

    .proc update_horizontal_position
        lda #Joypad::BUTTON_LEFT
        and Joypad::zp_buttons
        beq @check_right

        ;; We are facing left, reflect that on the state and the sprite.
        lda #%10111111
        and zp_state
        ora #%00000100
        sta zp_state

        ;; If we are thrusting, then we need to apply the proper acceleration
        ;; for it. Otherwise, if walking, then there's no acceleration and the
        ;; velocity is linear, so we just set the velocity and directly apply
        ;; it, skipping the whole acceleration part.
        bit zp_state
        bmi @fly_left
        lda #WALK_LEFT
        sta zp_velocity_x
        bne @apply_velocity
    @fly_left:
        lda #FLY_LEFT
        bne @apply_acceleration

        ;; Same as the part above but applied to going right.
    @check_right:
        lda #Joypad::BUTTON_RIGHT
        and Joypad::zp_buttons
        beq @nothing

        lda #%01000100
        ora zp_state
        sta zp_state

        bit zp_state
        bmi @fly_right
        lda #WALK_RIGHT
        sta zp_velocity_x
        bne @apply_velocity
    @fly_right:
        lda #FLY_RIGHT
        bne @apply_acceleration

        ;; If neither left nor right is being pressed we have to move to a
        ;; resting state on the horizontal axis. When thrusting this means an
        ;; acceleration of 0 (i.e. slow down), when walking this means going to
        ;; an immediate full stop.
    @nothing:
        lda #0
        bit zp_state
        bmi @apply_acceleration
        sta zp_velocity_x
        beq @apply_velocity

        ;; As with vertical motion, `a` contains the acceleration to aim for,
        ;; and we just subtract the current velocity and see if we either have
        ;; to accelerate or decelerate to reach that, and we do that with steps.
    @apply_acceleration:
        sta Globals::zp_tmp0
        lda zp_velocity_x
        sec
        sbc Globals::zp_tmp0
        beq @apply_velocity
        bmi @accelerate_left
        .ifdef PAL
            lda zp_velocity_x
            sec
            sbc zp_step_on_pal
            sta zp_velocity_x
        .else
            dec zp_velocity_x
        .endif
        jmp @apply_velocity
    @accelerate_left:
        .ifdef PAL
            lda zp_velocity_x
            clc
            adc zp_step_on_pal
            sta zp_velocity_x
        .else
            inc zp_velocity_x
        .endif

        ;; With the final velocity already at hand, update the position with it.
    @apply_velocity:
        lda zp_velocity_x
        bmi @going_left

        ;; The velocity is positive, so it's just a 16-bit addition.
        clc
        adc zp_position_x
        sta zp_position_x
        lda #0
        adc zp_position_x + 1
        sta zp_position_x + 1
        rts

    @going_left:
        lda #0
        sec
        sbc zp_velocity_x
        sta Globals::zp_tmp0
        lda zp_position_x
        sec
        sbc Globals::zp_tmp0
        sta zp_position_x
        lda zp_position_x + 1
        sbc #0
        sta zp_position_x + 1

    @end:
        rts
    .endproc

    ;; Check on whether the player is out of bounds in any way and provide an
    ;; ejection logic for each situation.
    .proc background_check
        ;;;
        ;; The logic for this function is admittedly a bit of a mess, but it's
        ;; trying to be efficient while not operating at a metatile level
        ;; (because on how the background is laid out in the original game), and
        ;; it's also trying to balance the physics to what can be seen on the
        ;; original game. The end result is code that is a bit messy, but that
        ;; is as close as I could get to the original, while being a bit
        ;; forgiving (e.g. in some (literal) corner cases the code will say it's
        ;; not colliding when it actually is, but doing so would be frustrating
        ;; for the player). I'll go the extra mile documenting the code so
        ;; readers (including "future me") can better grasp the logic.

        ;;;
        ;; 1. Vertical collision check
        ;;
        ;; In order to be forgiving probably starting with a collision check on
        ;; the horizontal axis would've been better. But we want to be close to
        ;; the original game, so we go for the vertical axis first. That is, we
        ;; give preference at touching ground or a ceiling instead of ejecting
        ;; at the horizontal axis first.
        ;;
        ;; Hence, first we need to setup zp_arg0 and zp_arg1 to call
        ;; `Background::collides`.

        ;; If we are going down, the player's height should be added to the
        ;; coordinate, as we are checking for the feet. Otherwise we will check
        ;; for the head.
        lda zp_screen_y
        ldx zp_velocity_y
        bmi @into_tile_coordinates
        clc
        adc #PLAYER_HEIGHT

    @into_tile_coordinates:
        ;; And convert raw screen coordinates into a tile coordinate.
        lsr
        lsr
        lsr
        sta Globals::zp_arg0

        ;; Compute the X tile coordinate and check for a background collision.
        ;; This coordinate will first be the one on the left.
        lda zp_screen_x
        tay
        clc
        adc #LEFT_OFFSET
        lsr
        lsr
        lsr
        sta Globals::zp_arg1
        jsr Background::collides
        bne @collision

        ;; If there was no collision, try again but taking the player's width
        ;; into consideration. That is, we are doing the same check as before
        ;; but on the right side this time.
        tya
        clc
        adc #PLAYER_WIDTH
        lsr
        lsr
        lsr
        sta Globals::zp_arg1
        jsr Background::collides

        ;; If there was still no collision, then go for a check on the
        ;; horizontal axis.
        beq @horizontal_check

        ;;;
        ;; 2. Collision on the vertical axis
        ;;
        ;; The previous code detected a collision on the vertical axis. That is,
        ;; the player either hit the ground (note that it could very well be the
        ;; player just walking on the ground), or hit a ceiling.
        ;;
        ;; The ground case is a matter of computing the right position and
        ;; canceling velocity. The ceiling case is similar but we have to add a
        ;; bounce to be close to the original game.

    @collision:
        ;; Are we grounded or fighting with a ceiling?
        ldy zp_velocity_y
        bmi @ceiling

        ;; Translate the stored Y tile index into coordinates and account for
        ;; the player's height. That's the final screen position.
        lda Globals::zp_arg0
        asl
        asl
        asl
        sec
        sbc #PLAYER_HEIGHT
        sta zp_screen_y

        ;; Clearing out the subpixel value does the job.
        lda #$F0
        and zp_position_y
        sta zp_position_y

        ;; Reset the velocity on the Y axis as we are grounded.
        lda #0
        sta zp_velocity_y

        ;; Set the player's state to grounded.
        lda #%01111111
        and zp_state
        ora #%00000100
        sta zp_state

        rts

    @ceiling:
        ;; We are hitting a platform from below, transform the Y tile index into
        ;; coordinates and add the height of the platform.
        lda Globals::zp_arg0
        asl
        asl
        asl
        clc
        adc #8
        sta zp_screen_y

        ;; We don't do anything with the position as modifying slightly the
        ;; velocity with the bounce is enough. The amount of bounce applied
        ;; depends on whether we were at max velocity or not.
        lda zp_velocity_y
        cmp #THRUST
        bne @reduced_velocity
        lda #REDUCE_FULL_SPEED
        bne @correct_vertical_velocity
    @reduced_velocity:
        lda #REDUCE_MID_SPEED
    @correct_vertical_velocity:
        sta zp_velocity_y
        rts

        ;;;
        ;; 3. Checking on the horizontal axis
        ;;
        ;; Now we are going to focus at the horizontal level. For this, we first
        ;; determine whether it's moving to the left or to the right, and set up
        ;; `zp_arg1` accordingly. Then, It will be a matter of checking if we
        ;; are hitting a platform on the side with the waist, head or feet. Note
        ;; that the head and the feet are not covered to this point because the
        ;; code for the vertical check from before is only valid from "pure"
        ;; hits from below/above a given platform.

    @horizontal_check:
        ;; Set up `zp_arg0` to point at the player's waist.
        lda zp_screen_y
        clc
        adc #PLAYER_WAIST
        lsr
        lsr
        lsr
        sta Globals::zp_arg0

        ;; The X tile coordinate depends on whether we are moving left or right.
        lda zp_screen_x
        ldx zp_velocity_x
        bmi @left
        clc
        adc #PLAYER_WIDTH
    @left:
        lsr
        lsr
        lsr
        sta Globals::zp_arg1

        ;; Is there collision?
        jsr Background::collides
        bne @horizontal_collision

        ;; No? Why don't you try the same thing but on the head instead of the
        ;; waist? This can happen if we were falling down but we are hitting a
        ;; platform with the head. This could have been handled during vertical
        ;; collision check, but then we would get an ejection vertically, and in
        ;; these cases we actually want a bounce if we want to mimick the
        ;; original gameplay.
        dec Globals::zp_arg0
        jsr Background::collides
        bne @horizontal_collision

        ;; Still, no dice. Let's try with the feet. If that doesn't cut it, then
        ;; we are done checking.
        inc Globals::zp_arg0
        inc Globals::zp_arg0
        jsr Background::collides
        beq @end

        ;;;
        ;; 4. Bounce horizontally
        ;;
        ;; The code above actually detected a collision. The ejection logic on
        ;; the horizontal axis is a matter of bouncing the player to the
        ;; contrary direction. This is similar to what we were doing on the
        ;; ceiling ejection logic, but now applied to the X axis.

    @horizontal_collision:
        ;; Set into the `a` register the target X screen coordinate.
        lda Globals::zp_arg1
        asl
        asl
        asl

        ;; The final X screen coordinate will depend on whether we were
        ;; originally moving left or right.
        ldx zp_velocity_x
        bmi @left_collision

        ;; We were moving right, so now the bounce has to turn the player to the
        ;; left and the coordinate should reflect the player's width (otherwise
        ;; we would get inserted into the hitting tile :D). Note that we don't
        ;; need to change the player's heading, as that's not what the original
        ;; game did.
        sec
        sbc #PLAYER_WIDTH
        ldx #BOUNCE_LEFT
        bne @horizontal_eject

    @left_collision:
        ;; We were moving left, so now the velocity has to be positive and we
        ;; need to add the tile width to it.
        clc
        adc #8
        ldx #BOUNCE_RIGHT

    @horizontal_eject:
        ;; The screen coordinate has been computed into the `a` register, and
        ;; the previous code made sure to leave the new X velocity on the `x`
        ;; register.
        sta zp_screen_x
        stx zp_velocity_x

    @end:
        rts
    .endproc

    .proc update_sprites
        ;; It's just an update of coordinates or something more?
        lda #%00000100
        and zp_state
        beq @update_coordinates

        jsr update_player_tiles

        ;; Clear out `update` flag.
        lda zp_state
        and #%11111011
        sta zp_state

    @update_coordinates:
        JAL update_sprites_coordinates
    .endproc

    ;; Update the tiles used for the player's sprites. This includes which tile
    ;; IDs to use on each slot, and also the attributes to be used, as the
    ;; heading affects whether things are to be flipped horizontally or not.
    .proc update_player_tiles
        ;; Flying or walking? In any case, on the `x` register we will put one
        ;; of the tile IDs, and on the `y` register the other. This way the code
        ;; dealing with heading can rely on these two registers.
        bit zp_state
        bmi @flying

        ;; The walking sprites depends on the current walking animation set on
        ;; the player's state.
        lda zp_state
        and #%00000011
        cmp #1
        beq @animation1
        cmp #2
        beq @animation2
        ;; NOTE: fallthrough for either 0 or even buggy states.
    @still:
        ldx #$21
        ldy #$20
        bne @heading
    @animation1:
        ldx #$03
        ldy #$02
        bne @heading
    @animation2:
        ldx #$13
        ldy #$12
        bne @heading

        ;; There's only one set for the flying state, no animations here.
    @flying:
        ldx #$23
        ldy #$22

        ;; It's a bit of a pain but there's no other way around it, update all
        ;; tile IDs for the player. Note that the feet come from the `x` and `y`
        ;; registers as handled previously.
    @heading:
        bit zp_state
        bvs @right

        lda #$01
        sta OAM::m_sprites + $01
        lda #$00
        sta OAM::m_sprites + $05
        lda #$11
        sta OAM::m_sprites + $09
        lda #$10
        sta OAM::m_sprites + $0D
        stx OAM::m_sprites + $11
        sty OAM::m_sprites + $15

        ldx #%01000000
        bne @set_attributes
    @right:
        lda #$00
        sta OAM::m_sprites + $01
        lda #$01
        sta OAM::m_sprites + $05
        lda #$10
        sta OAM::m_sprites + $09
        lda #$11
        sta OAM::m_sprites + $0D
        stx OAM::m_sprites + $15
        sty OAM::m_sprites + $11

        ldx #$00

        ;; The `x` register contains the tile attributes.
    @set_attributes:
        stx OAM::m_sprites + $02
        stx OAM::m_sprites + $06
        stx OAM::m_sprites + $0A
        stx OAM::m_sprites + $0E
        stx OAM::m_sprites + $12
        stx OAM::m_sprites + $16

        rts
    .endproc

    ;; Update the coordinate for the six sprites that make up the player.
    .proc update_sprites_coordinates
        ;; Y axis.
        lda zp_screen_y
        sta OAM::m_sprites
        sta OAM::m_sprites + $04
        clc
        adc #8
        sta OAM::m_sprites + $08
        sta OAM::m_sprites + $0C
        clc
        adc #8
        sta OAM::m_sprites + $10
        sta OAM::m_sprites + $14

        ;; X axis.
        lda zp_screen_x
        sta OAM::m_sprites + $03
        sta OAM::m_sprites + $0B
        sta OAM::m_sprites + $13
        clc
        adc #8
        sta OAM::m_sprites + $07
        sta OAM::m_sprites + $0F
        sta OAM::m_sprites + $17

        rts
    .endproc

    ;; That's just german for "the Bart, the".
    .proc die_bart_die
        ;; If the player was grabbing an item when it happened, let go of it.
        jsr Items::let_go_on_death

        ;; Decrement the life.
        lda Globals::zp_multiplayer
        and #$01
        tax
        dec Player::zp_lifes, x
        bne @nmi_update

        ;; If this poor guy is over, then mark it in the multiplayer bitmap.
        cpx #0
        bne @player_2_over
        lda #%11111101
        bne @set_multi
    @player_2_over:
        lda #%11111011
    @set_multi:
        and Globals::zp_multiplayer
        sta Globals::zp_multiplayer

    @nmi_update:
        ;; Notify NMI code to render lifes again, as they have changed.
        lda Player::zp_state
        ora #%00001000
        sta Player::zp_state

    @skip_life_update:
        ;; Move the player's sprites out of the screen.
        ldx #0
        lda #$FF
        sta OAM::m_sprites, x
        sta OAM::m_sprites + 4, x
        sta OAM::m_sprites + 8, x
        sta OAM::m_sprites + 12, x
        sta OAM::m_sprites + 16, x
        sta OAM::m_sprites + 20, x

        ;; Set the player as dead.
        lda #$10
        ora Globals::zp_flags
        sta Globals::zp_flags

        ;; Try to switch the player.
        jsr Player::try_player_switch

        ;; Create an explosion.
        lda Player::zp_screen_y
        sta Globals::zp_arg2
        lda Player::zp_screen_x
        sta Globals::zp_arg3
        JAL Explosions::create
    .endproc

    ;; Try to switch the active player if we are in multiplayer.
    .proc try_player_switch
        ;; If multiplayer is not enabled, don't even bother.
        bit Globals::zp_multiplayer
        bpl @end

        lda Globals::zp_multiplayer
        tax
        and #$01
        beq @try_player_2

        ;; Switch to player 1 if it's still alive.
        txa
        and #$02
        beq @end
        txa
        and #$FE
        bne @set_and_end

    @try_player_2:
        ;; Switch to player 2 if it's still alive.
        txa
        and #$04
        beq @end
        txa
        ora #$01

    @set_and_end:
        sta Globals::zp_multiplayer
    @end:
        rts
    .endproc
.endscope
