.scope PPU
    CONTROL = $2000
    MASK    = $2001
    STATUS  = $2002
    SCROLL  = $2005
    ADDRESS = $2006
    DATA    = $2007

    ;; Shadow for the PPU::CONTROL value. Touch this value instead of accessing
    ;; the PPU register directly.
    zp_control = $80
.endscope
