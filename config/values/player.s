;; This file has been automatically generated via bin/values.rb.
;; DO NOT MODIFY this file directly: check config/values.yml instead.

.ifdef PAL
    GRAVITY = $23
    BLAST_OFF = $F3
    THRUST = $E9
    FLY_LEFT = $D8
    FLY_RIGHT = $24
    WALK_LEFT = $ED
    WALK_RIGHT = $12
    BOUNCE_LEFT = $DE
    BOUNCE_RIGHT = $1D
    REDUCE_FULL_SPEED = $13
    REDUCE_MID_SPEED = $0A
.else
    GRAVITY = $1C
    BLAST_OFF = $F8
    THRUST = $E0
    FLY_LEFT = $E2
    FLY_RIGHT = $1D
    WALK_LEFT = $F3
    WALK_RIGHT = $0E
    BOUNCE_LEFT = $E7
    BOUNCE_RIGHT = $18
    REDUCE_FULL_SPEED = $10
    REDUCE_MID_SPEED = $08
.endif
