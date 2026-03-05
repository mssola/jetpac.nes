.segment "CODE"

.scope Over
    ;; Has the "Game over" screen been displayed yet?
    zp_displayed = $10

    ;; Timer set whenever the "Game over" screen has been displayed. Whenever it
    ;; times out, then the player is redirected to the title screen.
    zp_timer = $11

    ;; Amount of time the player has to wait for the title screen to appear
    ;; again.
    TIMER_VALUE = HZ * 3

    ;; Initialize all variables for the "Game over" screens.
    .proc init
        lda #0
        sta Over::zp_displayed
        sta Over::zp_timer

        rts
    .endproc

    ;; Handle a "Game over" screen. It has two phases:
    ;;   1. Render a "Game over" message.
    ;;   2. Wait for a timer to time out.
    ;; It will set 1 to the 'a' register if the timer has run out, signaling
    ;; that the game can start over. Otherwise it sets 0 to the 'a' register.
    .proc handle
        ldy #0

        ;; Has the "Game over" screen been displayed? If not do it now.
        lda Over::zp_displayed
        bne @do_handle
        jsr Over::render
        jmp @end

    @do_handle:
        lda Over::zp_timer
        bne @dec_timer
        iny
        beq @end
    @dec_timer:
        dec Over::zp_timer

    @end:
        tya
        rts
    .endproc

    ;; Render the "Game over" message to the screen. This is done in two
    ;; phases. We first ensure to disable the PPU, and in the second phase we do
    ;; the actual writing.
    .proc render
        ;; Is PPU disabled? If it is then jump into rendering the screen
        ;; directly.
        lda PPU::zp_mask
        beq @do_render

        ;; Nope! Force the PPU to be disabled and quit.
        lda Globals::zp_flags
        ora #%01000000
        sta Globals::zp_flags
        lda #$00
        sta PPU::zp_mask
        rts

    @do_render:
        jsr Over::clear_out_screen
        ;; TODO: coin game over.
        jsr Over::render_regular_game_over

        ;; Enable back the PPU (only background).
        lda #%00001110
        sta PPU::zp_mask

        ;; Update PPU registers.
        lda #%01000000
        ora Globals::zp_flags
        sta Globals::zp_flags

        ;; Set the "Game over" message as displayed and fire up the timer.
        lda #1
        sta Over::zp_displayed
        lda #Over::TIMER_VALUE
        sta Over::zp_timer

        rts
    .endproc

    ;; Remove all platforms and the ground.
    .proc clear_out_screen
        ;; Remove left platform.
        bit PPU::m_status
        ldx #$29
        stx PPU::m_address
        ldx #$83
        stx PPU::m_address
        lda #$00
        sta PPU::m_data
        sta PPU::m_data
        sta PPU::m_data
        sta PPU::m_data
        sta PPU::m_data
        sta PPU::m_data
        sta PPU::m_data

        ;; Remove center platform.
        bit PPU::m_status
        ldx #$29
        stx PPU::m_address
        ldx #$EF
        stx PPU::m_address
        sta PPU::m_data
        sta PPU::m_data
        sta PPU::m_data
        sta PPU::m_data
        sta PPU::m_data

        ;; Remove right platform.
        bit PPU::m_status
        ldx #$29
        stx PPU::m_address
        ldx #$38
        stx PPU::m_address
        sta PPU::m_data
        sta PPU::m_data
        sta PPU::m_data
        sta PPU::m_data
        sta PPU::m_data
        sta PPU::m_data
        sta PPU::m_data

        ;; Ground
        bit PPU::m_status
        ldx #$2B
        stx PPU::m_address
        ldx #$20
        stx PPU::m_address

        ldx #$20
    @clear_ground_loop:
        sta PPU::m_data
        dex
        bne @clear_ground_loop

        rts
    .endproc

    ;; Render the regular "Game over player X" screen.
    ;;
    ;; TODO: multiplayer support.
    .proc render_regular_game_over
        ;; Set the position.
        bit PPU::m_status
        ldx #$29
        stx PPU::m_address
        ldx #$67
        stx PPU::m_address

        ;; And just iterate over the "message" until we reach the end of string
        ;; $FF character.
        ldx #0
    @message_loop:
        lda message, x
        cmp #$FF
        beq @out
        sta PPU::m_data
        inx
        bne @message_loop

    @out:
        ;; Reset attributes for the end of the message.
        bit PPU::m_status
        ldx #$2B
        stx PPU::m_address
        ldx #$D5
        stx PPU::m_address
        lda #0
        sta PPU::m_data
        sta PPU::m_data
        sta PPU::m_data

        rts

    message:
        ;; "GAME "
        .byte $21, $1B, $27, $1F, $00
        ;; "OVER "
        .byte $29, $30, $1F, $2C, $00
        ;; "PLAYER "
        .byte $2A, $26, $1B, $33, $1F, $2C, $00
        ;; "1"
        .byte $11, $FF
    .endproc
.endscope
