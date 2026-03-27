;; Clear the carry and add ADDR, y to the indexed digit on
;; 'Score::m_players'. If the result is larger or equal than 10, then 0 is
;; stored and the carry flag is set. Otherwise the carry flag is cleared.
.macro BCD_ADD ADDR
    lda Score::m_players, x
    clc
    adc ADDR, y
    cmp #10
    bcc :+
    sec
    lda #0
:
    sta Score::m_players, x
.endmacro

;; Add ADDR, y to the indexed digit on 'Score::m_players' _with_ carry. If the
;; result is larger or equal than 10, then 0 is stored and the carry flag is
;; set. Otherwise the carry flag is cleared.
.macro BCD_ADDC ADDR
    lda Score::m_players, x
    adc ADDR, y
    clc
    cmp #10
    bcc :+
    sec
    lda #0
:
    sta Score::m_players, x
.endmacro

;; Only add the carry to the indexed digit on 'Score::m_players' _with_
;; carry. If the result is larger or equal than 10, then 0 is stored and the
;; carry flag is set. Otherwise the carry flag is cleared.
.macro BCD_JUST_CARRY
    lda Score::m_players, x
    adc #0
    clc
    cmp #10
    bne :+
    sec
    lda #0
:
    sta Score::m_players, x
.endmacro

;; A score is a 6-digit number where each digit is stored on a byte of its
;; own. This makes adding numbers and representing them into the screen dead
;; easy.
;;
;; This is indeed rather wasteful, but we have a lot of RAM to spare and the
;; ease of use is quite convenient.
.scope Score
    ;; Scores for both players are stored in a single buffer. Even indeces
    ;; contain digits for the first player, and odd indeces contain digits for
    ;; the second player. Digits are stored in little-endian format.
    ;;
    ;; Interweaving digits this way might seem weird, but it actually makes
    ;; indexing things super easy: the 'active' bit from
    ;; 'Globals::zp_multiplayer' can be used to index the first item, and then
    ;; it's a matter of advancing the 'x' register twice in order to get the
    ;; next digit.
    PLAYERS_BUFF_SIZE = $0C
    m_players = $300     ; asan:reserve PLAYERS_BUFF_SIZE

    ;; The high score for this session.
    m_hi = $30C           ; asan:reserve $06

    ;; Indeces for the 'additions' address. Relevant only when calling
    ;; add_to_player_y().
    ADD_ENEMY_IDX = 0
    ADD_PART_FUEL_IDX = 3
    ADD_ITEM_IDX = 6

    ;; Initialize the scores for both players.
    .proc init_players_scores
        lda #0
        ldx #0

    @loop:
        sta m_players, x
        inx
        cpx #PLAYERS_BUFF_SIZE
        bne @loop

        rts
    .endproc

    ;; Add to the current player's score the number stored in "additions, y". As
    ;; a caller you don't need to know the exact format of this data, so set to
    ;; 'y' one of the 'ADD_*_IDX' constants from up above.
    .proc add_to_player_y
        ;; See 'Score::m_players' on why this is the way to select the current
        ;; player's score.
        lda Globals::zp_multiplayer
        and #$01
        tax

        ;;;
        ;; The first three digits are the product of adding the contents of
        ;; 'additions, y'.

        BCD_ADD additions
        inx
        inx

        BCD_ADDC additions + 1
        inx
        inx

        BCD_ADDC additions + 2
        inx
        inx

        ;;;
        ;; The rest are just a matter of adding the carry.

        BCD_JUST_CARRY
        inx
        inx

        BCD_JUST_CARRY
        inx
        inx

        BCD_JUST_CARRY

        ;;;
        ;; And set the 'score' flag, signaling a need of updating the score.

        lda Globals::zp_extra_flags
        ora #$80
        sta Globals::zp_extra_flags

        rts

        ;; Defines the values by which the score can be incremented. They are
        ;; three bytes per object in little-endian format.
    additions:
        ;; Enemy
        .byte $05, $02, $00

        ;; Part / fuel tank
        .byte $00, $00, $01

        ;; Item
        .byte $00, $05, $02
    .endproc

    ;; Save the score of either of the two players if any of them are higher
    ;; than the high score we have right now.
    .proc save_hi_score
        ;;;
        ;; Check player 1.

        ldx #(PLAYERS_BUFF_SIZE - 2)
        ldy #5

    @player1_loop:
        lda Score::m_hi, y
        cmp Score::m_players, x
        bcc @save_player1
        dex
        dex
        dey
        cpy #$FF
        bne @player1_loop

        ;; No dice! If we are in multiplayer mode, then check player 2,
        ;; otherwise just quit.
        bit Globals::zp_multiplayer
        bpl @end

        ;;;
        ;; Check player 2.

        ldx #(PLAYERS_BUFF_SIZE - 1)
        ldy #5

    @player2_loop:
        lda Score::m_hi, y
        cmp Score::m_players, x
        bcc @save_player2
        dex
        dex
        dey
        cpy #$FF
        bne @player2_loop

        ;; Not player 2 either. Just quit.
        rts

        ;;;
        ;; One of the players actually achieved a high score. Let's save it.

    @save_player1:
        ldx #0
        beq @save
    @save_player2:
        ldx #1

    @save:
        ldy #0
    @save_loop:
        lda Score::m_players, x
        sta Score::m_hi, y

        inx
        inx
        iny
        cpy #6
        bne @save_loop

        ;; And set the 'high' bit so this change is reflected on screen.
        lda Globals::zp_extra_flags
        ora #$40
        sta Globals::zp_extra_flags

    @end:
        rts
    .endproc

    ;; Update the score for both players. This might be a bit too much on single
    ;; player mode but we have to show both scores on the title screen
    ;; anyways. Hence, since we have all the time in the world anyways, we
    ;; update both and avoid branching and stuff.
    .proc nmi_update_scores
        ;; The 'y' register will contain the right high byte for the PPU
        ;; address. This is needed because scores are to be displayed on both
        ;; the title and game screens.
        lda PPU::zp_control
        and #$02
        tax
        ldy hi_ppu_address, x

        ;; Now we just put the numbers. The 'x' index has to go "backwards", and
        ;; taking into account that both players live on the same buffer. The
        ;; tile ID is basically the integer value + $10, which is the position
        ;; of the '0' character on our tile set.

        bit PPU::m_status
        sty PPU::m_address
        lda #$62
        sta PPU::m_address

        clc
        ldx #(PLAYERS_BUFF_SIZE - 2)
    @player1_loop:
        lda Score::m_players, x
        adc #$10
        sta PPU::m_data

        dex
        dex
        cpx #$FE
        bne @player1_loop

        ;; And the same for the second player.

        bit PPU::m_status
        sty PPU::m_address
        lda #$78
        sta PPU::m_address

        clc
        ldx #(PLAYERS_BUFF_SIZE - 1)
    @player2_loop:
        lda Score::m_players, x
        adc #$10
        sta PPU::m_data

        dex
        dex
        cpx #$FF
        bne @player2_loop

        ;; Then do the high score if requested.

        lda Globals::zp_extra_flags
        and #$40
        beq @unset

        bit PPU::m_status
        sty PPU::m_address
        lda #$6D
        sta PPU::m_address

        clc
        ldx #5
    @hi_loop:
        lda Score::m_hi, x
        adc #$10
        sta PPU::m_data

        dex
        cpx #$FF
        bne @hi_loop

    @unset:
        ;; Disable the 'score' flag.
        lda Globals::zp_extra_flags
        and #$3F
        sta Globals::zp_extra_flags

        rts

    hi_ppu_address:
        .byte $20, $00, $28, $00
    .endproc
.endscope

;; Add the score for a dead enemy to the current player's score.
.macro ADD_ENEMY_SCORE
    ldy #Score::ADD_ENEMY_IDX
    jsr Score::add_to_player_y
.endmacro

;; Add the score for grabbing a shuttle part / fuel tank to the current player's
;; score.
.macro ADD_PART_FUEL_SCORE
    ldy #Score::ADD_PART_FUEL_IDX
    jsr Score::add_to_player_y
.endmacro

;; Add the score for grabbing an item to the current player's score.
.macro ADD_ITEM_SCORE
    ldy #Score::ADD_ITEM_IDX
    jsr Score::add_to_player_y
.endmacro
