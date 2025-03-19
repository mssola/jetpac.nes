.segment "CODE"

;; The game is so simple that it can fit in both nametables. This scope has all
;; the functions and data that initializes and resets all of them properly.
.scope Assets
    ;; Initialize palettes and nametables.
    .proc init
        jsr init_palettes

        ;; Load the title screen on the first nametable.
        lda #.lobyte(title_screen)
        sta Globals::zp_arg0
        lda #.hibyte(title_screen)
        sta Globals::zp_arg1
        ldx #$20
        jsr load_screen_x

        ;; Ensure that the title looks as expected.
        jsr prepare_for_title_screen

        ;; Load the main screen on the second nametable.
        lda #.lobyte(main_screen)
        sta Globals::zp_arg0
        lda #.hibyte(main_screen)
        sta Globals::zp_arg1
        ldx #$28
        jsr load_screen_x

        rts
    .endproc

    ;; Load the 1KB worth of screen data located via the 16-bit pointer on
    ;; Globals::zp_arg{0,1}. Set the `x` register to the high byte of the
    ;; nametable to be used.
    .proc load_screen_x
        bit PPU::STATUS

        stx PPU::ADDRESS
        lda #$00
        sta PPU::ADDRESS

        ldy #0
        ldx #4
    @loop:
        lda (Globals::zp_arg0), y
        sta PPU::DATA
        iny
        bne @loop

        dex
        beq @end

        inc Globals::zp_arg1
        jmp @loop

    @end:
        rts
    .endproc

    ;; Performs all the needed tricks in order to get the first nametable as
    ;; expected.
    .proc prepare_for_title_screen
        bit PPU::STATUS

        lda #$23
        sta $2006
        lda #$C8
        sta $2006

        ldx #$10
    @upper_title_bar_loop:
        lda #%10101010
        sta $2007
        dex
        bne @upper_title_bar_loop

        ;; Update 2nd palette for background. This is redundant upon entering
        ;; the game, but it makes sense after a game over.
        lda #$3F
        sta PPU::ADDRESS
        lda #$09
        sta PPU::ADDRESS
        lda #$28
        sta PPU::DATA
        lda #$2C
        sta PPU::DATA
        lda #$16
        sta PPU::DATA

        ;; Update 1st palette for foreground.
        lda #$3F
        sta PPU::ADDRESS
        lda #$11
        sta PPU::ADDRESS
        lda #$30
        sta PPU::DATA
        lda #$10
        sta PPU::DATA
        lda #$30
        sta PPU::DATA

        rts
    .endproc

    ;; Performs all the needed tricks in order to get the second nametable as
    ;; expected.
    .proc prepare_for_main_screen
        bit PPU::STATUS

        ;; Update 2nd palette for background.
        lda #$3F
        sta PPU::ADDRESS
        lda #$09
        sta PPU::ADDRESS
        lda #$14
        sta PPU::DATA
        lda #$2C
        sta PPU::DATA
        lda #$28
        sta PPU::DATA

        ;; Update 1st palette for foreground.
        lda #$3F
        sta PPU::ADDRESS
        lda #$11
        sta PPU::ADDRESS
        lda #$16
        sta PPU::DATA
        lda #$10
        sta PPU::DATA
        lda #$30
        sta PPU::DATA

        rts
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
        .byte $0F, $28, $2C, $16
        ;; 3: ship
        .byte $0F, $16, $30, $00

        ;; TODO: fuel tank needs color $24
        ;; Foreground
        ;; 0: player & ship
        .byte $0F, $30, $10, $30
        ;; 1: enemy 1 & bonuses
        .byte $0F, $16, $2C, $2A
        ;; 2: enemy 2, fuel & bonuses
        .byte $0F, $16, $14, $28
        ;; 3: SUSE easter egg
        .byte $0F, $16, $00, $2B
    .endproc

    ;; Having 2KB for screen data is quite wasteful, but since it's such a
    ;; simple game, I have so much space left in the cartridge that I can go
    ;; bananas with it. This helps out loading the screen as we can go faster
    ;; and it is less error prone.
    title_screen:   
        .incbin "../assets/title.nam"
    main_screen:   
        .incbin "../assets/main.nam"
.endscope

.segment "CHARS"
    .incbin "../assets/jetpac.chr"
