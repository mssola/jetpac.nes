.segment "CODE"

.scope Background
    ;; Screen coordinates on the Y axis for the ground.
    GROUND_Y_COORD = $C8

    ;; To make them easier to traverse when performing background collision
    ;; checking, each platform is laid out in tile coordinates and spanning
    ;; three bytes: tile row, tile column beginning, tile column end.
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
.endscope
