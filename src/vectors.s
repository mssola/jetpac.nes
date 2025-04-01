.segment "VECTORS"
    .addr nmi, reset, irq

.segment "CODE"

;; Pretty standard reset function, nothing crazy.
.proc reset
    sei
    cld

    ldx #$40
    stx APU::FRAME_COUNTER

    ldx #$FF
    txs

    inx
    stx PPU::CONTROL
    stx PPU::MASK
    stx APU::DMC

    bit PPU::STATUS
@vblankwait1:
    bit PPU::STATUS
    bpl @vblankwait1

    ldx #0
    lda #0
@ram_reset_loop:
    sta $000, x
    sta $100, x
    sta $300, x
    sta $400, x
    sta $500, x
    sta $600, x
    sta $700, x
    inx
    bne @ram_reset_loop

    lda #$EF
@sprite_reset_loop:
    sta $200, x
    inx
    bne @sprite_reset_loop

    lda #$00
    sta OAM::ADDRESS
    lda #$02
    sta OAM::DMA

@vblankwait2:
    bit PPU::STATUS
    bpl @vblankwait2

    lda #$3F
    sta PPU::ADDRESS
    lda #$00
    sta PPU::ADDRESS

    lda #$0F
    ldx #$20
@palettes_reset_loop:
    sta PPU::DATA
    dex
    bne @palettes_reset_loop

    jmp main
.endproc

.proc nmi
    ;; Should we skip it?
    bit Globals::zp_flags
    bpl @end

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

    ;; PAL-specific code
    .ifdef PAL
        jsr Driver::pal_handler
    .endif

    ;; TODO: some actions here will depend on the status of the game...

    ;; Decrease title timer.
    lda Title::zp_title_timer
    beq :+
    dec Title::zp_title_timer
:

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
.endproc

;; Unused.
.proc irq
    rti
.endproc
