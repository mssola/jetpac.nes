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
        sta $200
        lda #$30
        sta $201
        lda #$00
        sta $202
        lda #SPRITE_X_POSITION
        sta $203

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
        cmp $200
        beq @end
        sta $200
        jmp @set_timer_and_end

    @check_down:
        lda #Joypad::BUTTON_DOWN
        and Joypad::zp_buttons1
        beq @check_select

        lda #SPRITE_Y_POSITION1
        cmp $200
        beq @end
        sta $200
        jmp @set_timer_and_end

    @check_select:
        lda #Joypad::BUTTON_SELECT
        and Joypad::zp_buttons1
        beq @check_start

        lda #SPRITE_Y_POSITION0
        cmp $200
        beq @down
        sta $200
        jmp @set_timer_and_end

    @check_start:
        lda #Joypad::BUTTON_START
        and Joypad::zp_buttons1
        beq @end
        JAL start

    @down:
        lda #SPRITE_Y_POSITION1
        sta $200

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
        sta $200

        lda #1
        rts
    .endproc
.endscope
