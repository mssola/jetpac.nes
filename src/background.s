.segment "CODE"

.scope Background
    ;; Screen coordinate on the Y axis where elements can begin to appear (e.g.
    ;; upper bound for new enemies, starting point for falling items, etc.).
    ;;
    ;; NOTE: if you change this value, you should re-generate the random values
    ;; from prng.s as well.
    UPPER_MARGIN_Y_COORD = $1A

    ;; Screen coordinates on the Y axis for the ground.
    ;;
    ;; NOTE: if you change this value, you should re-generate the random values
    ;; from prng.s as well.
    GROUND_Y_COORD = $C8

    ;; Returns whether the given tile position collides with a background
    ;; platform or not. It expects two memory arguments: zp_arg0 and zp_arg1,
    ;; which contain the Y and the X tile coordinates respectively.
    ;;
    ;; The boolean value is directly set into the `a` register; but the memory
    ;; will not be written in any way. Hence, you can still rely on the old
    ;; `zp_arg0` and `zp_arg1` values even after calling this function.
    ;;
    ;; The 'y' register is preserved.
    .proc collides
        ;; We iterate first on the rows, as that's how the data on
        ;; `Background::platforms` is actually sorted by.
        ldx #0
    @row_check:
        lda Background::platforms, x

        ;; Is this the end of the list?
        cmp #$FF
        bne @continue

        ;; Yes, begone!
        lda #0
        rts

    @continue:
        ;; Prepare for either row check (which require one 'inx') or the
        ;; next iteration (which require three 'inx').
        inx

        ;; The first byte is the vertical tile coordinate. If that doesn't
        ;; match, go for the next one.
        cmp Globals::zp_arg0
        beq @column_check
        inx
        inx
        jmp @row_check

    @column_check:
        ;; Check the left edge.
        ;;
        ;; NOTE: small optimization on sky and ground which have $00 for the
        ;; left edge.
        lda Background::platforms, x
        beq @yes
        cmp Globals::zp_arg1
        bcs @no

        ;; Check the right edge.
        inx
        lda Background::platforms, x
        cmp Globals::zp_arg1
        bcc @no

    @yes:
        lda #1
        rts
    @no:
        lda #0
        rts
    .endproc

    ;; To make them easier to traverse when performing background collision
    ;; checking, each platform is laid out in tile coordinates and spanning
    ;; three bytes: tile row, tile column beginning, tile column end.
    ;;
    ;; NOTE: this is wholeheartedly distinct to implementations like in
    ;; github.com/mssola/code.nes. In there, and in examples such as the ones in
    ;; `scroll`, a map is built up when loading the background and collision
    ;; checking is a matter of determining the metatile index on that map and
    ;; that's it. Here it's not possible because we are operating at the tile
    ;; level, not a metatile level. This in turn has been done this way to
    ;; better replicate the original experience. Mapping tiles would be a huge
    ;; hit on memory, so we have to do things in a more rudimentary way.
    ;; Fortunately for us, this is a rather small list, and traversing it each
    ;; time is not too expensive.
    platforms:
        ;; Top of the screen.
        .byte $03, $00, $FF

        ;; Left platform.
        .byte $09, $18, $1D

        ;; Center platform.
        .byte $0C, $03, $08

        ;; Right platform.
        .byte $0F, $0F, $12

        ;; Ground.
        .byte $19, $00, $FF

        ;; End of the list.
        .byte $FF

    ;; Clear out the shuttle from the background.
    .proc nmi_clear_shuttle
        ;; The low part of the rocket.
        bit PPU::m_status
        ldx #$2B
        stx PPU::m_address
        ldx #$15
        stx PPU::m_address
        sta PPU::m_data
        sta PPU::m_data

        ;; High part of the rocket.
        bit PPU::m_status
        ldy #$2A
        sty PPU::m_address
        ldx #$75
        stx PPU::m_address
        sta PPU::m_data
        sta PPU::m_data

        bit PPU::m_status
        sty PPU::m_address
        ldx #$95
        stx PPU::m_address
        sta PPU::m_data
        sta PPU::m_data

        bit PPU::m_status
        sty PPU::m_address
        ldx #$B5
        stx PPU::m_address
        sta PPU::m_data
        sta PPU::m_data

        ;; Middle part of the rocket.
        bit PPU::m_status
        sty PPU::m_address
        ldx #$D5
        stx PPU::m_address
        sta PPU::m_data
        sta PPU::m_data

        bit PPU::m_status
        sty PPU::m_address
        ldx #$F5
        stx PPU::m_address
        sta PPU::m_data
        sta PPU::m_data

        rts
    .endproc
.endscope
