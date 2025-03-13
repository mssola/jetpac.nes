.segment "CODE"

.scope Driver
    .proc switch
        ;; Get the assets ready for the main screen. That is, make sure that the
        ;; palettes and such are as desired since the title screen needed
        ;; another setup.
        jsr Assets::prepare_for_main_screen

        ;; Switch to the other base nametable.
        lda #%10001010
        sta PPU::zp_control

        ;; Mark the state of the game as "game". That is, the player has
        ;; started. Also set the `ppu` flag so the PPU control update takes
        ;; place.
        lda #%01000001
        ora Globals::zp_flags
        sta Globals::zp_flags

        rts
    .endproc

    .proc update
        ;; TODO
        rts
    .endproc
.endscope
