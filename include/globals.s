;; Global variables used throughout the code base.
.scope Globals
    ;;;
    ;; Argument values as defined in https://github.com/mssola/style.nes. Note
    ;; that these variables can also be used as temporary variables.
    zp_arg0 = $00
    zp_arg1 = $01
    zp_arg2 = $02
    zp_arg3 = $03
    zp_arg4 = $04

    ;;;
    ;; Random values that can be used inside of functions for temporary values
    ;; so `zp_argX` variables are not overwritten as often.
    zp_tmp0 = $05
    zp_tmp1 = $06
    zp_tmp2 = $07
    zp_tmp3 = $08

    ;;;
    ;; Reserve a byte of memory for preserving indices on memory. This is needed
    ;; whenever the `x` and `y` registers might not be reliable because of
    ;; underlying `jsr` calls that might tamper with their values. Sometimes
    ;; saving the value in memory is enough instead of playing with the stack.
    zp_idx = $09

    ;; Flags that manage the state of the game.
    ;;
    ;; | Bit | Short name | Meaning when set                                            |
    ;; |-----+------------+-------------------------------------------------------------|
    ;; |   7 | render     | Game logic is over, block main code until NMI code is over. |
    ;; | 6-0 | -          | Unused                                                      |
    zp_flags = $20
.endscope
