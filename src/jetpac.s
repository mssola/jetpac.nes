.segment "HEADER"
    .byte 'N', 'E', 'S', $1A
    .byte $02, $01
    .res $0A, $00

.segment "CODE"

.include "../include/apu.s"
.include "../include/oam.s"
.include "../include/ppu.s"
.include "../include/globals.s"
.include "vectors.s"

.proc main
    jsr init_palettes
    jsr init_nametables

;;; TODO
    cli
    lda #%10110000
    sta $2000
    lda #%00011110
    sta $2001

@main_game_loop:
    ;;;
    ;; TODO
    ;;;

    lda #%10000000
    ora Globals::zp_flags
    sta Globals::zp_flags
@wait_for_render:
    bit Globals::zp_flags
    bmi @wait_for_render

    ;; Rendering is done, we can perform another iteration of the loop!
    jmp @main_game_loop
.endproc

;; Copies all the palettes for our game into the proper PPU address.
.proc init_palettes
    lda #$3F
    sta PPU::ADDRESS
    lda #$00
    sta PPU::ADDRESS

    ldx #0
@load_palettes_loop:
    lda palettes, x
    sta PPU::DATA
    inx
    cpx #$20
    bne @load_palettes_loop
    rts
palettes:
    ;; Background
    ;; 0: score
    .byte $0F, $30, $2C, $28
    ;; 1: floating platforms
    .byte $0F, $2C, $30, $2A
    ;; 2: ground
    .byte $0F, $28, $14, $28
    ;; 3: ship
    .byte $0F, $16, $30, $00

    ;; TODO: fuel tank needs color $24
    ;; Foreground
    ;; 0: player & ship
    .byte $0F, $16, $10, $30
    ;; 1: enemy 1 & bonuses
    .byte $0F, $16, $2C, $2A
    ;; 2: enemy 2, fuel & bonuses
    .byte $0F, $16, $14, $28
    ;; 3: SUSE easter egg
    .byte $0F, $16, $00, $2B
.endproc

.proc init_nametables
    ;; TODO
    rts
.endproc


.segment "CHARS"
    .incbin "../assets/jetpac.chr"
