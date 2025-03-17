.segment "CODE"

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

    INIT_Y_POSITION_LO = $80
    INIT_Y_POSITION_HI = $0C
    INIT_Y_VELOCITY    = $08

    INIT_X_POSITION_LO = $00
    INIT_X_POSITION_HI = $04

    THROTTLE  = $D8
    BLAST_OFF = $F8
    GRAVITY   = $28

    UPPER_LIMIT  = 10
    GROUND_LIMIT = 200

    zp_screen_y          = $40
    zp_position_y        = $41  ; NOTE: 16-bit.
    zp_target_velocity_y = $43  ; TODO: needed?
    zp_velocity_y        = $44

    zp_screen_x          = $45
    zp_position_x        = $46  ; NOTE: 16-bit.
    zp_target_velocity_x = $48  ; TODO: needed?
    zp_velocity_x        = $49

    ;; Initialize the player's sprite. Note that for the sprite to look
    ;; correctly on screen you still need to call `Player::update` afterwards.
    .proc init
        ;; Reset velocity
        lda #$00
        sta zp_target_velocity_y
        sta zp_velocity_y
        sta zp_target_velocity_x
        sta zp_velocity_x

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

        ;;;
        ;; TODO: this should really just go away

        lda #$00
        sta $201
        lda #$00
        sta $202

        lda #$01
        sta $205
        lda #$00
        sta $206

        lda #$10
        sta $209
        lda #$00
        sta $20A

        lda #$11
        sta $20D
        lda #$00
        sta $20E

        lda #$20
        sta $211
        lda #$00
        sta $212

        lda #$21
        sta $215
        lda #$00
        sta $216

        rts
    .endproc

    .proc update
        jsr update_vertical_position

        ;; TODO: horizontal

        ;; At this point all positions are clear, transform them into screen
        ;; coordinates, eject out from boundaries and platforms, and update the
        ;; sprite with the new state.
        jsr position_to_screen
        jsr bound_check
        JAL update_sprite
    .endproc

    ;; Updates the `zp_velocity_y` and the `zp_position_y` depending on whether
    ;; the player is throttling or gravity should just apply.
    .proc update_vertical_position
        ;; Check if the player is asking to throttle, otherwise apply gravity.
        lda #(Joypad::BUTTON_UP | Joypad::BUTTON_A)
        and Joypad::zp_buttons1
        beq @set_gravity
        lda zp_velocity_y
        beq @blast_off
        lda #THROTTLE
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

        ;; Increase or decrease depending on what we have now.
        ;; TODO: inc/dec might not quite cut it in NTSC vs PAL
        bmi @down
        dec zp_velocity_y
        jmp @apply_velocity
    @down:
        inc zp_velocity_y
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

    ;; Convert the positions with subpixel precision into mere screen
    ;; coordinates. That is, update the values on `zp_screen_{x,y}` given the
    ;; current values of `zp_position_{x,y}`.
    .proc position_to_screen
        ;; We save the high byte into a temporary value, and we load the low
        ;; byte into the accumulator.
        lda zp_position_y + 1
        sta Globals::zp_tmp0
        lda zp_position_y

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

        ;; Ecce Y coordinates.
        sta zp_screen_y

        ;; And the same for the X coordinates.
        lda zp_position_x + 1
        sta Globals::zp_tmp0
        lda zp_position_x

        ;; And rolling...
        lsr Globals::zp_tmp0
        ror
        lsr Globals::zp_tmp0
        ror
        lsr Globals::zp_tmp0
        ror
        lsr Globals::zp_tmp0
        ror

        ;; Ecce X coordinates.
        sta zp_screen_x

        rts
    .endproc

    ;; Check on whether the player is out of bounds in any way and provide an
    ;; ejection logic for each situation.
    .proc bound_check
        ;; Are we at the top?
        ;; TODO: actually buggy, but nevermind for now
        lda zp_screen_y
        cmp #UPPER_LIMIT
        beq @too_high_icarus
        bcs @check_ground
    @too_high_icarus:
        lda #0
        sta zp_velocity_y
        lda #UPPER_LIMIT
        sta zp_screen_y
        rts

        ;; Nope, are we at the ground?
    @check_ground:
        cmp #(GROUND_LIMIT - 24)
        bcc @above_ground

        ;; We appear to be either at the ground or below it (e.g. we are
        ;; standing still but initial gravity is pulling us down). In this case,
        ;; just reset the Y velocity and the Y position.
        lda #0
        sta zp_velocity_y
        lda #(GROUND_LIMIT - 24)
        sta zp_screen_y
        lda #$F0
        and zp_position_y
        sta zp_position_y
        rts

        ;; Nope, let's check for the platforms.
    @above_ground:
        ;; TODO: notice how ground and top are just cases on the general
        ;; "collision up/down". Next commits will merge these logics.

        rts
    .endproc

    .proc update_sprite
        ;; TODO:
        ;;   - Update heading
        ;;   - Update motion state
        ;;   - Update tiles

        jsr update_sprite_coordinates

        rts
    .endproc

    ;; Update the coordinate for the six sprites that make up the player.
    .proc update_sprite_coordinates
        ;; Y axis.
        lda zp_screen_y
        sta $0200
        sta $0204
        clc
        adc #8
        sta $0208
        sta $020C
        clc
        adc #8
        sta $0210
        sta $0214

        ;; X axis.
        lda zp_screen_x
        sta $0203
        sta $020B
        sta $0213
        clc
        adc #8
        sta $0207
        sta $020F
        sta $0217

        rts
    .endproc
.endscope
