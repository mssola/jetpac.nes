.segment "CODE"

.proc nmi
    ;; Should we skip it?
    bit Globals::zp_flags

    ;; If we are on a dev environment, account for any frame drops.
    .ifdef PARTIAL
        bpl @account_for_frame_drop
    .else
        bpl @end
    .endif

    ;; Save registers.
    pha
    txa
    pha
    tya
    pha

    ;; Sprite DMA.
    lda #$00
    sta OAM::m_address
    lda #$02
    sta OAM::m_dma

    ;; Increase the random seed.
    inc Prng::zp_rand

    ;; Are we paused? If so skip timers, PAL handler and the likes.
    lda #%00001000
    and Globals::zp_flags
    bne @ppu_registers

    ;; PAL-specific code
    .ifdef PAL
        jsr Driver::pal_handler
    .endif

    ;; Do we need to update the lifes from players on the HUD?
    lda Player::zp_state
    and #%00001000
    beq @global_flags

    ;; Yeah! TODO: this is only done for player 1.
    bit PPU::m_status
    lda #$28
    sta PPU::m_address
    lda #$4B
    sta PPU::m_address
    lda Player::zp_lifes
    clc
    adc #$10
    sta PPU::m_data

    ;; And unset the 'life' flag from the player.
    lda Player::zp_state
    and #%11110111
    sta Player::zp_state

@global_flags:
    ;; TODO: some actions here will depend on the status of the game...
    lda Globals::zp_flags
    and #%00000001
    bne @ppu_registers

    ;; Decrease title timer.
    lda Title::zp_title_timer
    beq @ppu_registers
    dec Title::zp_title_timer

@ppu_registers:
    ;; Should we update PPU registers?
    bit Globals::zp_flags
    bvc @scroll

    ;; Zero out the `ppu` flag.
    lda #%10111111
    and Globals::zp_flags
    sta Globals::zp_flags

    bit PPU::m_status

    ;; Update the PPU control/mask registers with shadowed values.
    lda PPU::zp_mask
    sta PPU::m_mask
    lda PPU::zp_control
    sta PPU::m_control

@scroll:
    ;; Always reset the scroll just in case.
    bit PPU::m_status
    lda #$00
    sta PPU::m_scroll
    sta PPU::m_scroll

    ;; Unblock the main code.
    lda #%01111111
    and Globals::zp_flags
    sta Globals::zp_flags

    ;; Restore registers.
    pla
    tay
    pla
    tax
    pla

@end:
    rti

    ;; If we are on a dev environment, account for any frame drops.
.ifdef PARTIAL
@account_for_frame_drop:
    inc Debug::zp_frame_drops
    rti
.endif
.endproc

;; Unused.
.proc irq
    rti
.endproc
