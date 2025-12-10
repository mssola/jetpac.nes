.segment "CODE"

;; All the functions and variables which are related to the title screen.
.scope Title
    ;; Y and X coordinates for the sprite that guides the player on the menu.
    SPRITE_Y_POSITION0 = $A7
    SPRITE_Y_POSITION1 = $BF
    SPRITE_X_POSITION  = $40

    ;; The title has a timer as a delay between joypad presses from the player.
    TIMER_INIT_VALUE = (HZ / 3)
    zp_title_timer = $30

    ;; Initialize all the elements for the title screen.
    .proc init
        lda #0
        sta zp_title_timer

        ;; Initialize the sprite that guides the player on the menu.
        lda #SPRITE_Y_POSITION0
        sta OAM::m_sprites
        lda #$30
        sta OAM::m_sprites + 1
        lda #$00
        sta OAM::m_sprites + 2
        lda #SPRITE_X_POSITION
        sta OAM::m_sprites + 3

        rts
    .endproc

    ;; Checks the pressed buttons from the joypad and moves the sprite for the
    ;; menu accordingly.
    ;;
    ;; Returns 1 if the player hit start and the game can start, 0 otherwise.
    .proc update
        lda zp_title_timer
        bne @end

        lda #Joypad::BUTTON_UP
        and Joypad::zp_buttons1
        beq @check_down

        lda #SPRITE_Y_POSITION0
        cmp OAM::m_sprites
        beq @end
        sta OAM::m_sprites
        jmp @set_timer_and_end

    @check_down:
        lda #Joypad::BUTTON_DOWN
        and Joypad::zp_buttons1
        beq @check_select

        lda #SPRITE_Y_POSITION1
        cmp OAM::m_sprites
        beq @end
        sta OAM::m_sprites
        jmp @set_timer_and_end

    @check_select:
        lda #Joypad::BUTTON_SELECT
        and Joypad::zp_buttons1
        bne @do_select

        ;; If none of the above has been pressed, our only possibility is the
        ;; start button. If that's the case, jump there, otherwise quit.
        lda #(Joypad::BUTTON_START | Joypad::BUTTON_A)
        and Joypad::zp_buttons1
        beq @end
        JAL start

    @do_select:
        lda #SPRITE_Y_POSITION0
        cmp OAM::m_sprites
        beq @down
        sta OAM::m_sprites
        bne @set_timer_and_end

    @down:
        lda #SPRITE_Y_POSITION1
        sta OAM::m_sprites

    @set_timer_and_end:
        lda #TIMER_INIT_VALUE
        sta zp_title_timer
    @end:
        lda #0
        rts
    .endproc

    ;; Save the selection from the menu (TODO), hide all elements from the title
    ;; screen, and return always 1.
    .proc start
        ;; Hide the sprite from the menu.
        lda #$EF
        sta OAM::m_sprites

        lda #1
        rts
    .endproc
.endscope
