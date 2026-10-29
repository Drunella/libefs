; S11: chrin must preserve X and Y (directory and file)
.include "tlib.inc"
        setnam n_dollar, 1
        lda #$00
        jsr EFS_open
        ldx #$5a
        ldy #$a5
        jsr EFS_chrin
        stx xs
        sty ys
        jsr rec                 ; 0: byte, C
        lda xs
        jsr rec                 ; 1: X after dir chrin (expect $5a)
        lda ys
        jsr rec                 ; 2: Y after dir chrin (expect $a5)
        ldx #$11                ; a few more, including the end
    :   stx xs
        jsr EFS_chrin
        cpx xs
        bne bad
        jsr EFS_readst
        beq :-
        lda #$00
        jsr rec                 ; 3: 0 = X kept during the whole listing
        jmp :+
    bad:
        lda #$ee
        jsr rec                 ; 3: $ee = X changed
    :   jsr EFS_close
        setnam n_d1, 5
        lda #$00
        jsr EFS_open
        ldx #$5a
        ldy #$a5
        jsr EFS_chrin
        stx xs
        sty ys
        lda xs
        jsr rec                 ; 4: X after file chrin (expect $5a)
        lda ys
        jsr rec                 ; 5: Y after file chrin (expect $a5)
        jsr EFS_close
        finish
    n_dollar: .byte "$"
    n_d1:     .byte "DATA1"
    xs: .byte 0
    ys: .byte 0
.include "tlib_code.inc"
