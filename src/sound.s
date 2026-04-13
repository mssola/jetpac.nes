.segment "CODE"

;; The sound for this game is extremely simple, coming from a system that only
;; allowed for 1-bit beeps. Here the sound is a bit different due to a vastly
;; different audio hardware, and we make use of three channels:
;;
;;   1. Square 1: used on level entry and bullets.
;;   2. Square 2: used for item collection or dropping.
;;   3. Noise: enemy explosion and rocket launch.
.scope Sound
    ;; Bullets can go super fast, and if we delivered the sound effect for each
    ;; bullet it could potentially be annoying. Moreover, because of the
    ;; limitations from the ZX Spectrum, the original game didn't spit a sound
    ;; effect for each bullet either. Hence, wait for some frames before
    ;; producing a sound. This is why we call Sound::tick() on NMI code, and why
    ;; the sound effect for bullet is called via Sound::play_bullet_maybe().
    ;;
    ;; NOTE: the maximum count value is supposed to be bigger than the timer for
    ;; bullets creation. This is guaranteed in 'jetpac.s'.
    zp_frame_count = $DA
    BULLET_SFX_FRAME_COUNT = HZ / 10

    ;; Period values for square channels.
    .ifdef PAL
        BULLET_SFX_LOW  = $29
        BULLET_SFX_HIGH = $00
        ENTER_SFX_LOW   = $4D
        ENTER_SFX_HIGH  = $01
        PICKUP_SFX_LOW  = $61
        PICKUP_SFX_HIGH = $01
        DROP_SFX_LOW    = $3A
        DROP_SFX_HIGH   = $01
    .else
        BULLET_SFX_LOW  = $2C
        BULLET_SFX_HIGH = $00
        ENTER_SFX_LOW   = $67
        ENTER_SFX_HIGH  = $01
        PICKUP_SFX_LOW  = $7C
        PICKUP_SFX_HIGH = $01
        DROP_SFX_LOW    = $52
        DROP_SFX_HIGH   = $01
    .endif

    ;; Initialize all the sound channels which are needed and reset some
    ;; register values.
    .proc init
        ;; Enable square 1, 2; and noise.
        lda #%00001011
        sta APU::m_status

        ;; Reset sweep registers and frame count.
        lda #0
        sta APU::m_square_1_sweep
        sta APU::m_square_2_sweep
        sta Sound::zp_frame_count

        ;; Silence channels.
        lda #0
        sta APU::m_noise_envelope
        lda #$30
        sta APU::m_square_1_envelope
        sta APU::m_square_2_envelope

        rts
    .endproc

    ;; Tick the internal frame count for sound effects.
    ;;
    ;; NOTE: expected to only be called at the end of NMI code.
    .proc tick
        ;; If there is no bullet sound effect to be delivered, don't even sweat
        ;; it.
        lda Sound::zp_frame_count
        beq @end

        ;; Increase the frame counter and check the limit. If we reached that
        ;; limit, reset it so we don't tick until the next bullet sfx request
        ;; comes in.
        clc
        adc #1
        cmp #Sound::BULLET_SFX_FRAME_COUNT
        beq @reset
        sta Sound::zp_frame_count
        rts

    @reset:
        lda #0
        sta Sound::zp_frame_count

    @end:
        rts
    .endproc

    ;; Play the bullet sound effect if we can (i.e. the frame count allows us to
    ;; do it).
    .proc play_bullet_maybe
        ;; If we cannot play the sound yet, skip this altogether.
        lda Sound::zp_frame_count
        bne @end
        inc Sound::zp_frame_count

        lda #$01
        sta APU::m_square_1_envelope
        lda #%10000001
        sta APU::m_square_1_sweep
        lda #BULLET_SFX_LOW
        sta APU::m_square_1_low
        lda #BULLET_SFX_HIGH
        sta APU::m_square_1_high

    @end:
        rts
    .endproc
.endscope

;; Make an explosion sound via the noise channel.
.macro SOUND_EXPLOSION
    lda #$03
    sta APU::m_noise_envelope
    lda #$8F
    sta APU::m_noise_mode
    lda #$F8
    sta APU::m_noise_counter
.endmacro

;; Make a small beep, suitable for level entry.
.macro SOUND_ENTER_LEVEL
    lda #%10000100
    sta APU::m_square_1_envelope
    lda #Sound::ENTER_SFX_LOW
    sta APU::m_square_1_low
    lda #Sound::ENTER_SFX_HIGH
    sta APU::m_square_1_high
.endmacro

;; Make a small beep for item pickup.
.macro SOUND_ITEM_PICKUP
    lda #%10000100
    sta APU::m_square_2_envelope
    lda #Sound::PICKUP_SFX_LOW
    sta APU::m_square_2_low
    lda #Sound::PICKUP_SFX_HIGH
    sta APU::m_square_2_high
.endmacro

;; Make a small beep for item collection in the droppping zone (i.e. fuel tanks
;; and shuttle parts making into the shuttle).
.macro SOUND_ITEM_DROP
    lda #%10000100
    sta APU::m_square_2_envelope
    lda #Sound::DROP_SFX_LOW
    sta APU::m_square_2_low
    lda #Sound::DROP_SFX_HIGH
    sta APU::m_square_2_high
.endmacro

;; Start the sound effect for the rocket take off animation.
.macro START_TAKE_OFF_SOUND
    lda #$38
    sta APU::m_noise_envelope
    lda #$0F
    sta APU::m_noise_mode
    lda #0
    sta APU::m_noise_counter
.endmacro

;; Stop the sound effect for the rocket take off animation.
.macro STOP_TAKE_OFF_SOUND
    lda #0
    sta APU::m_noise_envelope
.endmacro
