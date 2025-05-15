.segment "CODE"

;; Global variables used throughout the code base.
.scope Globals
    ;;;
    ;; Argument values reserved passing arguments to functions in memory.
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
    ;; |   6 | ppu        | PPU registers have to be touched                            |
    ;; | 5-4 | -          | Unused                                                      |
    ;; |   3 | paused     | Game is in pause state                                      |
    ;; |   2 | title over | We are transitioning from title to game                     |
    ;; | 1-0 | game       | 0: title; 1: game; 2: game over, 3: game over (coin)        |
    zp_flags = $20

    ;; Current level of the game.
    zp_level = $24

    ;; The level "kind". Note that `zp_level` can go on forever, but the level
    ;; "kind" repeats every 8 waves. Hence, this is just a cached version of
    ;; masking `zp_level`.
    zp_level_kind = $25
.endscope
