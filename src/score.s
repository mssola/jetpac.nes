;; Clear the carry and add ADDR to the indexed digit on 'Score::m_players'. If
;; the result is larger or equal than 10, then 0 is stored and the carry flag is
;; set. Otherwise the carry flag is cleared.
.macro BCD_ADD ADDR
    lda Score::m_players, x
    clc
    adc ADDR
    cmp #10
    bcc :+
    sec
    lda #0
:
    sta Score::m_players, x
.endmacro

;; Add ADDR to the indexed digit on 'Score::m_players' _with_ carry. If the
;; result is larger or equal than 10, then 0 is stored and the carry flag is
;; set. Otherwise the carry flag is cleared.
.macro BCD_ADDC ADDR
    lda Score::m_players, x
    adc ADDR
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

    ;; Add to the current player's score the number stored in
    ;; 'Globals::zp_tmp{0,1,2}', where 'Globals::zp_tmp0' has the least
    ;; significant number.
    .proc add_to_player
        ;; See 'Score::m_players' on why this is the way to select the current
        ;; player's score.
        lda Globals::zp_multiplayer
        and #$01
        tax

        ;;;
        ;; The first three digits are the product of adding the contents of
        ;; 'Globals::zp_tmp{0,1,2}'.

        BCD_ADD Globals::zp_tmp0
        inx
        inx

        BCD_ADDC Globals::zp_tmp1
        inx
        inx

        BCD_ADDC Globals::zp_tmp2
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
    lda #5
    sta Globals::zp_tmp0
    lda #2
    sta Globals::zp_tmp1
    lda #0
    sta Globals::zp_tmp2
    jsr Score::add_to_player
.endmacro

;; Add the score for grabbing a shuttle part / fuel tank to the current player's
;; score.
.macro ADD_PART_FUEL_SCORE
    lda #0
    sta Globals::zp_tmp0
    lda #0
    sta Globals::zp_tmp1
    lda #1
    sta Globals::zp_tmp2
    jsr Score::add_to_player
.endmacro

;; Add the score for grabbing an item to the current player's score.
.macro ADD_ITEM_SCORE
    lda #0
    sta Globals::zp_tmp0
    lda #5
    sta Globals::zp_tmp1
    lda #2
    sta Globals::zp_tmp2
    jsr Score::add_to_player
.endmacro
