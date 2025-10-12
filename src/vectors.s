.segment "VECTORS"
    .addr nmi, reset, irq

.segment "CODE"

;; Debug utilities.
.scope Debug
    ;; Counter for frame drops.
    zp_frame_drops = $90
.endscope

;; Pretty standard reset function, nothing crazy.
.proc reset
    ;; Disable interrupts and decimal mode.
    sei
    cld

    ;; Disable APU frame counter.
    ldx #$40
    stx APU::FRAME_COUNTER

    ;; Setup the stack.
    ldx #$FF
    txs

    ;; Disable NMIs and the APU's DMC.
    inx
    stx PPU::CONTROL
    stx PPU::MASK
    stx APU::DMC

    ;; First PPU wait.
    bit PPU::STATUS
@vblankwait1:
    bit PPU::STATUS
    bpl @vblankwait1

    ;; Initialize the counter for frame drops before any NMIs can come in.
    .ifdef PARTIAL
        lda #0
        sta Debug::zp_frame_drops
    .endif

    ;; Reset all sprites by simply moving the Y coordinate out of screen.
    lda #$EF
    ldx #0
@sprite_reset_loop:
    sta $200, x
    inx
    inx
    inx
    inx
    bne @sprite_reset_loop

    ;; DMA setup for sprite reset.
    lda #$00
    sta OAM::ADDRESS
    lda #$02
    sta OAM::DMA

    ;; Second PPU wait. After that the PPU is stable.
@vblankwait2:
    bit PPU::STATUS
    bpl @vblankwait2

    ;; NOTE: palettes are not initialized here as it's going to be one of the
    ;; first things done on `main` code.

    jmp main
.endproc

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
    sta OAM::ADDRESS
    lda #$02
    sta OAM::DMA

    ;; Are we paused? If so skip timers, PAL handler and the likes.
    lda #%00001000
    and Globals::zp_flags
    bne @ppu_registers

    ;; PAL-specific code
    .ifdef PAL
        jsr Driver::pal_handler
    .endif

    ;; TODO: some actions here will depend on the status of the game...
    lda Globals::zp_flags
    and #%00000001
    bne @ppu_registers

    ;; Increase the random seed.
    inc Prng::zp_rand

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

    bit PPU::STATUS

    ;; Update the PPU control/mask registers with shadowed values.
    lda PPU::zp_mask
    sta PPU::MASK
    lda PPU::zp_control
    sta PPU::CONTROL

@scroll:
    ;; Always reset the scroll just in case.
    bit PPU::STATUS
    lda #$00
    sta PPU::SCROLL
    sta PPU::SCROLL

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
