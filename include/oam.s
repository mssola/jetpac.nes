.scope OAM
    ;; Region in internal RAM where sprites are being allocated for later use in
    ;; the DMA process. The entire page is reserved, as there are 64 sprites x 4
    ;; bytes each = 256 bytes in total.
    m_sprites = $200            ; asan:reserve $100

    ;;;
    ;; Actual addresses from OAM space.

    m_address = $2003
    m_dma     = $4014
.endscope
