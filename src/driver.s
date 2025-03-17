.segment "CODE"

.scope Driver
    ;; Timer for the player to be able to pick up the joypad upon entering the
    ;; game.
    ;;
    ;; NOTE: this memory address is shared with `zp_title_timer`, as they can
    ;; never conflict with each other.
    zp_player_timer = $30
    PLAYER_TIMER_VALUE = HZ * 2

    .proc switch
        ;; Get the assets ready for the main screen. That is, make sure that the
        ;; palettes and such are as desired since the title screen needed
        ;; another setup.
        jsr Assets::prepare_for_main_screen

        ;; Switch to the other base nametable.
        lda #%10001010
        sta PPU::zp_control

        ;; Setup the player timer.
        .ifdef PARTIAL
            lda #1
        .else
            lda #PLAYER_TIMER_VALUE
        .endif
        sta zp_player_timer

        ;; Mark the state of the game as "game". That is, the player has
        ;; started. Also set the `ppu` flag so the PPU control update takes
        ;; place.
        lda #%01000001
        ora Globals::zp_flags
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

    @game:
        JAL Player::update
    .endproc
.endscope
