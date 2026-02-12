;; Debug utilities.
.scope Debug
    ;; Counter for frame drops. Only touched when PARTIAL is defined.
    zp_frame_drops = $90        ; asan:ignore
.endscope
