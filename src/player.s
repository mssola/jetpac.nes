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

    ;; The height and width of the player.
    PLAYER_HEIGHT = $18
    PLAYER_WIDTH  = $10

    ;; The initial position is the ground minus the height of the sprite (as the
    ;; Y accounts for the top left pixel). For the high byte we only want to
    ;; high nibble put into its low nibble, and for the low byte we shift the
    ;; low nibble into a high one and leave subpixels to 0.
    INIT_Y_POSITION_LO = ((Background::GROUND_Y_COORD - PLAYER_HEIGHT) & $0F) << 4
    INIT_Y_POSITION_HI = (Background::GROUND_Y_COORD - PLAYER_HEIGHT) >> 4

    ;; The initial position on the X axis is more or less at the center.
    INIT_X_POSITION_LO = $00
    INIT_X_POSITION_HI = $07

    THROTTLE  = $D8
    BLAST_OFF = $F8
    GRAVITY   = $28

    zp_screen_y          = $40
    zp_position_y        = $41  ; NOTE: 16-bit.
    zp_target_velocity_y = $43  ; TODO: needed?
    zp_velocity_y        = $44

    zp_screen_x          = $45
    zp_position_x        = $46  ; NOTE: 16-bit.
    zp_target_velocity_x = $48  ; TODO: needed?
    zp_velocity_x        = $49

    ;; Flags that manage the state of the game.
    ;;
    ;; | Bit | Short name | Meaning when set                                         |
    ;; |-----+------------+----------------------------------------------------------|
    ;; |   7 | throttle   | Player is hitting the throttle                           |
    ;; |   6 | heading    | heading right                                            |
    ;; | 5-3 | -          | Unused                                                   |
    ;; |   2 | update     | Sprite (animation or heading) must be updated            |
    ;; | 1-0 | walk       | 0: still; 1: animation 1; 2: animation 2, 3: animation 3 |
    zp_state = $50

    ;; Initialize the player's sprite. Note that for the sprite to look
    ;; correctly on screen you still need to call `Player::update` afterwards.
    .proc init
        ;; Initial state.
        lda #%01000100
        sta zp_state

        ;; Reset velocity
        lda #0
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

        rts
    .endproc

    .proc update
        jsr update_vertical_position
        jsr update_horizontal_position

        ;; At this point all positions are clear, transform them into screen
        ;; coordinates, eject out from boundaries and platforms, and update the
        ;; sprite with the new state.
        jsr position_to_screen
        jsr background_check
        JAL update_sprites
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

        ;; Player is throttling.
        lda #%10000100
        ora zp_state
        sta zp_state

        rts
    .endproc

    .proc update_horizontal_position
        ;;
        ;; TODO
        ;;

        lda #Joypad::BUTTON_LEFT
        and Joypad::zp_buttons1
        beq @check_right

        lda #%10111111
        and zp_state
        ora #%00000100
        sta zp_state

        jmp @end

    @check_right:
        lda #Joypad::BUTTON_RIGHT
        and Joypad::zp_buttons1
        beq @end

        lda #%01000100
        ora zp_state
        sta zp_state

    @end:
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
    .proc background_check
        ;; If we are going down, the player's height should be added to the
        ;; coordinate, as we are checking for the bottom.
        lda zp_screen_y
        ldx zp_velocity_y
        bmi :+
        clc
        adc #PLAYER_HEIGHT
    :
        ;; And convert raw screen coordinates into a tile coordinate.
        lsr
        lsr
        lsr
        sta Globals::zp_tmp0

        ;; We do the same for the X axis.
        lda zp_screen_x
        tay
        lsr
        lsr
        lsr
        sta Globals::zp_tmp1
        tya
        clc
        adc #PLAYER_WIDTH
        lsr
        lsr
        lsr
        sta Globals::zp_tmp2

        ;; Let's first check if there's any match on the vertical axis.
        ldx #0
    @row_check:
        lda Background::platforms, x

        ;; End of the list, no matches: begone!
        cmp #$FF
        beq @end

        ;; Prepare for either row check (which require one 'inx') or the
        ;; next iteration (which require three 'inx').
        inx

        ;; The first byte is the vertical tile coordinate. If that doesn't
        ;; match, go for the next one.
        cmp Globals::zp_tmp0
        beq @column_check
        inx
        inx
        jmp @row_check

    @column_check:
        ;; Save up this value just in case we are actually grounded.
        sta Globals::zp_tmp3

        ;; Check that the right corner of the player is to the right of the left
        ;; edge of the platform.
        lda Background::platforms, x
        cmp Globals::zp_tmp2
        bcs @end

        ;; And now check that the left corner of the player is to the left of
        ;; the right edge of the platform.
        inx
        lda Background::platforms, x
        cmp Globals::zp_tmp1
        bcc @end

        ;; Hey, we have a collision! Are we grounded or fighting with a ceiling?
        ldy zp_velocity_y
        bmi @ceiling

        ;; Translate the stored Y tile index into coordinates and account for
        ;; the player's height. That's the final screen position.
        lda Globals::zp_tmp3
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

        ;; Set the player's state to grounded and with the still animation.
        lda #%01111100
        and zp_state
        ora #%00000100
        sta zp_state

        rts

    @ceiling:
        ;; TODO

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
        ;; Throttle or walking? In any case, on the `x` register we will put one
        ;; of the tile IDs, and on the `y` register the other. This way the code
        ;; dealing with heading can rely on these two registers.
        bit zp_state
        bmi @throttle
        ;; TODO: walk animation
        ldx #$21
        ldy #$20
        bne @heading
    @throttle:
        ldx #$23
        ldy #$22

        ;; It's a bit of a pain but there's no other way around it, update all
        ;; tile IDs for the player. Note that the feet come from the `x` and `y`
        ;; registers as handled previously.
    @heading:
        bit zp_state
        bvs @right

        lda #$01
        sta $201
        lda #$00
        sta $205
        lda #$11
        sta $209
        lda #$10
        sta $20D
        stx $211
        sty $215

        ldx #%01000000
        jmp @set_attributes
    @right:
        lda #$00
        sta $201
        lda #$01
        sta $205
        lda #$10
        sta $209
        lda #$11
        sta $20D
        stx $215
        sty $211

        ldx #$00

        ;; The `x` register contains the tile attributes.
    @set_attributes:
        stx $202
        stx $206
        stx $20A
        stx $20E
        stx $212
        stx $216

        rts
    .endproc

    ;; Update the coordinate for the six sprites that make up the player.
    .proc update_sprites_coordinates
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
