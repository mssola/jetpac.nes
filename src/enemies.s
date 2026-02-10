.segment "CODE"

.scope Enemies
    ;; Maximum amount of enemies allowed on screen at the same time.
    ENEMIES_POOL_CAPACITY = 3

    ;; The capacity of the enemies pool in bytes.
    ENEMIES_POOL_CAPACITY_BYTES = ENEMIES_POOL_CAPACITY * 3

    ENEMIES_INITIAL_X       = $F0
    ENEMIES_INITIAL_X_RIGHT = $10

    ;; Base address for the pool of enemies used on this game. The pool has
    ;; #ENEMIES_POOL_CAPACITY capacity of enemy objects where each one is 3
    ;; bytes long:
    ;;  1. State: which can have two formats:
    ;;     - $FF: the enemy is not active.
    ;;     - |DIxx|xxxx|: where D is the direction bit (1: right; 0: left); and
    ;;                    the rest of bits count the number of moves from this
    ;;                    enemy. This is used to account for the inner movement
    ;;                    from an enemy sprite and, in fact, is initialized at
    ;;                    random. This counter is split in two phases depending
    ;;                    on the value of I. If I=0, then the enemy is at its
    ;;                    first inner movement state; and if I=1, then the
    ;;                    enemy is at the other inner movement state.
    ;;  2. Y coordinate.
    ;;  3. X coordinate.
    zp_enemies_pool_base = $60  ; asan:reserve ENEMIES_POOL_CAPACITY_BYTES

    ;; The current size of active enemies. That is, one thing is the capacity of
    ;; the pool, and another is what's the number of enemies on screen.
    zp_enemies_pool_size = $D0

    ;; Base index of the enemy tiles in 'tiles' to be used. Whether to use one
    ;; row or the other for a given enemy is to be decided by its current state.
    zp_enemy_tiles = $D1

    ;; Initializes the enemy pool for this game.
    .proc init
        ldx #0

        ldy #ENEMIES_POOL_CAPACITY
    @enemies_init_loop:
        ;; The state is set at random.
        stx Globals::zp_tmp0
        jsr Prng::random_valid_y_coordinate
        ldx Globals::zp_tmp0
        sta zp_enemies_pool_base, x
        sta Globals::zp_tmp1

        ;; The Y coordinate is also set at random within the bounds of the
        ;; playable screen.
        jsr Prng::random_valid_y_coordinate
        ldx Globals::zp_tmp0
        inx
        sta zp_enemies_pool_base, x

        ;; The initial X position is based on whether it's facing left or right.
        inx
        bit Globals::zp_tmp1
        bmi @facing_right
        lda #ENEMIES_INITIAL_X
        bne @set_x_position
    @facing_right:
        lda #ENEMIES_INITIAL_X_RIGHT
    @set_x_position:
        sta zp_enemies_pool_base, x

        inx
        dey
        bne @enemies_init_loop

        ;; The initial size of the pool is its whole capacity.
        lda #ENEMIES_POOL_CAPACITY
        sta zp_enemies_pool_size

        __fallthrough__ init_enemy_type
    .endproc

    ;; Initialize the enemy type. That is, define the contents of the
    ;; `zp_enemy_tiles` based on the current level kind, as well as the function
    ;; handler for it.
    .proc init_enemy_type
        lda Globals::zp_level_kind
        asl
        asl
        asl
        asl
        sta zp_enemy_tiles

        ;; TODO: function pointer.
        rts
    .endproc

    ;; Update the state and movement of all active enemies.
    ;;
    ;; NOTE: this function does not do collision checking with bullets as
    ;; 'Bullets::update' already accounts for it and we assume that it ran
    ;; before this one.
    .proc update
        ldx #253
        ldy zp_enemies_pool_size

    @loop:
        ;; Move the 'x' register to the current enemy for this iteration.
        inx
        inx
        inx

        ;; Is the current enemy marked as invalid? If so just move to the next
        ;; one.
        lda zp_enemies_pool_base, x
        cmp #$FF
        beq @next

        ;; If its movement state is already at the maximum, reset it, otherwise
        ;; increase it by 1. Note that we compare with $7E instead of $7F
        ;; because the latter would be equal to $FF if we accounted for the
        ;; direction bit and it could be confused with the "invalid"
        ;; state. Hence, the second phase of the inner movement has one frame
        ;; less of time than the other, but whatever. We also 'and' it with $7E
        ;; to avoid the direction bit to affect the comparison.
        sta Globals::zp_tmp0
        and #$7E
        cmp #$7E
        beq @reset
        inc zp_enemies_pool_base, x
        bne @next
    @reset:
        lda Globals::zp_tmp0
        and #$80
        sta zp_enemies_pool_base, x

        ;; TODO: collision with background & player.

    @next:
        ;; Any more enemies left?
        dey
        bne @loop

        rts
    .endproc

    ;; Allocate an enemy indexed by 'x' from the `zp_enemies_pool_base` buffer,
    ;; and set it to OAM-reserved space indexed via 'y'.
    ;;
    ;; The 'y' register will be updated by increasing its value by 16,
    ;; indicating the amount of bytes allocated in OAM space.
    ;;
    ;; NOTE: this function assumes that the enemy is in a valid state. That's up
    ;; to the caller to check on this before calling this function.
    .proc allocate_x_y
        ;; Save the 'y' index, as it's faster to do funny address arithmetics
        ;; and add 16 in the end than constantly 'iny' every time in the right
        ;; order.
        sty Globals::zp_tmp0

        ;; Y coordinates for each sprite of the enemy.
        lda Enemies::zp_enemies_pool_base + 1, x
        sta OAM::m_sprites, y                       ; top left
        sta OAM::m_sprites + 4, y                   ; top right
        clc
        adc #8
        sta OAM::m_sprites + 8, y                   ; bottom left
        sta OAM::m_sprites + 12, y                  ; bottom right

        ;; The next thing to account is where the enemy is facing. This will
        ;; change the tile set to be picked (e.g. 1st/2nd vs 3rd/4th rows of
        ;; tile IDs definitions); but it also changes whether the enemy needs to
        ;; be horizontally mirrored by the PPU or not. For the logic we make use
        ;; of temporary memory regions that will help us along the way, and we
        ;; start like this.
        lda Enemies::zp_enemies_pool_base, x
        sta Globals::zp_tmp2
        stx Globals::zp_tmp1
        ldx zp_enemy_tiles

        ;; Check on the direction bit from the enemy's state. If facing right,
        ;; then the 'x' register will be increased by 8 (pointing then to the
        ;; 3rd/4th rows of the enemy tiles ID definitions), and 'a' will have
        ;; the value for the third byte of the sprite (i.e. whether to mirror or
        ;; not the sprite at the PPU level).
        bit Globals::zp_tmp2
        bmi @face_right
        lda #0
        beq @set_state
    @face_right:
        txa
        clc
        adc #8
        tax
        lda #%01000000
    @set_state:
        sta OAM::m_sprites + 2, y                   ; top left
        sta OAM::m_sprites + 6, y                   ; top right
        sta OAM::m_sprites + 10, y                  ; bottom left
        sta OAM::m_sprites + 14, y                  ; bottom right

        ;; If the counter for the enemy's state is already at its second phase,
        ;; increase 'x' by 4 to reflect that it needs to pick the "other" state
        ;; from the tiles ID definitions. Then load all four bytes of tile IDs
        ;; and store them appropiately.
        lda Globals::zp_tmp2
        and #$40
        beq @set_facing
        txa
        clc
        adc #4
        tax
    @set_facing:
        lda tiles, x
        sta OAM::m_sprites + 1, y                   ; top left
        lda tiles + 1, x
        sta OAM::m_sprites + 5, y                   ; top right
        lda tiles + 2, x
        sta OAM::m_sprites + 9, y                   ; bottom left
        lda tiles + 3, x
        sta OAM::m_sprites + 13, y                  ; bottom right

        ;; The Y-coordinate for each sprite.
        ldx Globals::zp_tmp1
        lda Enemies::zp_enemies_pool_base + 2, x    ; top left
        sta OAM::m_sprites + 3, y
        sta OAM::m_sprites + 11, y                  ; bottom left
        clc
        adc #8
        sta OAM::m_sprites + 7, y                   ; top right
        sta OAM::m_sprites + 15, y                  ; bottom right

        ;; And update the 'y' register to notify 16 bytes were stored.
        lda Globals::zp_tmp0
        clc
        adc #16
        tay

        rts
    .endproc

    ;; Definitions for all the enemy types. An enemy type is defined by four
    ;; bytes, containing the tile IDs for it. Some enemies only span 2 tiles,
    ;; and because of this they have $FF as filler bytes.
    ;;
    ;; Moreover, each enemy has two states in order to show some inner
    ;; movement. This is why each enemy has an extra row of tile IDs, which
    ;; contain the "other" state.
    ;;
    ;; Finally, enemies can face right or left, which usually would be handled
    ;; in code, but it's much cheaper to abuse our mostly empty ROM-space with
    ;; extra definitions than being careful on the order in the allocation
    ;; loop.
    ;;
    ;; Thus, an enemy takes a whoping amount of 32 bytes. The first four bytes
    ;; are the actualy tile IDs for the enemy. The second row of four bytes is
    ;; its "other" shape in order to show inner movement. And the last two rows
    ;; are simply mirrors of the first two whenever the enemy is facing right
    ;; instead of left.
tiles:
    ;; Asteroid
    .byte $26, $27, $36, $37
    .byte $46, $47, $56, $57
    .byte $27, $26, $37, $36
    .byte $47, $46, $57, $56

    ;; Furry thingie
    .byte $28, $29, $38, $39
    .byte $48, $49, $58, $59
    .byte $29, $28, $39, $38
    .byte $49, $48, $59, $58

    ;; Bubble
    .byte $24, $25, $34, $35
    .byte $44, $45, $54, $55
    .byte $25, $24, $35, $34
    .byte $45, $44, $55, $54

    ;; Fighter jet 1
    .byte $2A, $2B, $3A, $3B
    .byte $2A, $2B, $3A, $3B
    .byte $2B, $2A, $3B, $3A
    .byte $2B, $2A, $3B, $3A

    ;; Fighter jet 2
    .byte $31, $32, $FF, $FF
    .byte $31, $32, $FF, $FF
    .byte $32, $31, $FF, $FF
    .byte $32, $31, $FF, $FF

    ;; UFO
    .byte $40, $41, $FF, $FF
    .byte $50, $51, $FF, $FF
    .byte $41, $40, $FF, $FF
    .byte $51, $50, $FF, $FF

    ;; Cross
    .byte $2C, $2D, $3C, $3D
    .byte $4C, $4D, $5C, $5D
    .byte $2D, $2C, $3D, $3C
    .byte $4D, $4C, $5D, $5C

    ;; Weirdo
    .byte $2E, $2F, $3E, $3F
    .byte $4E, $4F, $5E, $5F
    .byte $2F, $2E, $3F, $3E
    .byte $4F, $4E, $5F, $5E
.endscope
