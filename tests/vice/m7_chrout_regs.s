; m7: chrout keeps X and Y; returns $48 (not the status) on disk full
.include "tlib.inc"
        setnam n_big, 3
        lda #$01
        jsr EFS_open
        jsr rec                 ; 0: open(1)
        ldx #$5a
        ldy #$a5
        lda #$00
        jsr EFS_chrout
        stx xs
        sty ys
        lda xs
        jsr rec                 ; 1: X after chrout (expect $5a)
        lda ys
        jsr rec                 ; 2: Y after chrout (expect $a5)
    :   lda #$00
        jsr EFS_chrout
        bcc :-
        jsr rec                 ; 3: first error (fixed: $48; before: $40)
        jsr EFS_readst
        jsr rec                 ; 4: readst (expect $40)
        jsr EFS_close
        jsr rec                 ; 5: close
        finish
    n_big: .byte "BIG"
    xs: .byte 0
    ys: .byte 0
.include "tlib_code.inc"
