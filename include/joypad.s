.scope Joypad
    ;; Button masks.
    BUTTON_A      = 1 << 7
    BUTTON_B      = 1 << 6
    BUTTON_SELECT = 1 << 5
    BUTTON_START  = 1 << 4
    BUTTON_UP     = 1 << 3
    BUTTON_DOWN   = 1 << 2
    BUTTON_LEFT   = 1 << 1
    BUTTON_RIGHT  = 1 << 0

    ;; Port address for starting the latch process for both controllers and
    ;; reading from Joypad 1. The second Joypad can be accessed by reading from
    ;; $4017, which means that functions down below will simply use an indexed
    ;; load with the proper value on the index register (i.e. +1).
    m_joypad = $4016

    ;; The previous reading from the latest read controller.
    zp_prev = $21

    ;; After running a `read_*` function this variable will contain the given
    ;; result.
    zp_buttons = $22

    ;;;
    ;; Safely read a controller via a re-read algorithm the joypad as indexed by
    ;; the X register (0 for controller 1; 1 for controller 2).
    .proc read_x
        jsr Joypad::unsafe_read_x

        ;; The main idea around a re-read algorithm is that you read the
        ;; controller "unsafely" once, then you do it again and compare both
        ;; reads. If they were the same then we are on the safe side. Otherwise
        ;; we would need to loop until we get two identical reads. This sounds
        ;; bad but in practice it's not so much (and hey, if it worked for Super
        ;; Mario Bros. 3, it should work for us too :P). Otherwise there is the
        ;; algorithm via OAM DMA, but it sure is tricky.
    @reread:
        lda Joypad::zp_buttons
        tay
        jsr Joypad::unsafe_read_x
        tya
        cmp Joypad::zp_buttons
        bne @reread

        rts
    .endproc

    ;;;
    ;; Read the joypad as indexed by the X register (0 for controller 1; 1 for
    ;; controller 2). This method is fast but it might be vulnerable to the DPCM
    ;; bug (see: https://www.nesdev.org/wiki/Controller_reading_code).
    .proc unsafe_read_x
        ;; Start the latch process.
        lda #$01
        sta Joypad::m_joypad
        sta Joypad::zp_buttons   ; Bit as a guard for the loop below.
        lsr
        sta Joypad::m_joypad

        ;; Now the joypad is ready to accept reads.
    @loop:
        lda Joypad::m_joypad, x
        and #%00000011              ; Ignore bits other than controller.
        cmp #$01                    ; Set carry if and only if nonzero.
        rol Joypad::zp_buttons      ; Carry -> bit 0; bit 7 -> Carry
        bcc @loop
        rts
    .endproc
.endscope

;; Shortcut for reading the joypad indexed by 'x' (0 for controller 1; 1 for
;; controller 2).
.macro READ_JOYPAD_X
    lda Joypad::zp_buttons
    sta Joypad::zp_prev
    jsr Joypad::read_x
.endmacro
