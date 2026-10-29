; M11: defragment with a warning callback that destroys X and Y
; (the cartridge image is patched so that the callback does ldx/ldy #$ff)
.include "tlib.inc"
        relocate
        setnam n_17, 8
        lda #$00
        ldx #$00
        ldy #$50
        jsr EFS_load
        jsr rec                 ; 0: load DELME17K before
        jsr bankin
        jsr EFS_defragment
        jsr bankout_rec         ; 1: defragment
        relocate
        setnam n_17, 8
        lda #$01                ; verify against the copy loaded before
        ldx #$00
        ldy #$50
        jsr EFS_load
        jsr rec                 ; 2: verify A, C (fixed: 0, clear)
        jsr EFS_readst
        jsr rec                 ; 3: readst (fixed: $40; before: $10)
        finish
    n_17: .byte "DELME17K"
.include "tlib_code.inc"
