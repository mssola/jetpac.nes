.scope PPU
    m_control = $2000
    m_mask    = $2001
    m_status  = $2002
    m_scroll  = $2005
    m_address = $2006
    m_data    = $2007

    ;; Shadow for the PPU::CONTROL value. Touch this value instead of accessing
    ;; the PPU register directly.
    zp_control = $80

    ;; Shadow for the PPU::MASK value. Touch this value instead of accessing the
    ;; PPU register directly.
    zp_mask = $81
.endscope
