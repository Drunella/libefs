; N1: EFS_open while a write channel is at "disk full" resets status, chrout writes again
.include "tlib.inc"
        setnam n_big, 3
        lda #$01
        jsr EFS_open
        jsr rec                 ; 0: open(1) BIG
    :   lda #$00
        jsr EFS_chrout
        bcc :-
        jsr rec                 ; 1: first chrout error (expect $40/$48, C set)
        jsr EFS_readst
        jsr rec                 ; 2: readst (expect $40)
        setnam n_d1, 5
        lda #$00
        jsr EFS_open
        jsr rec                 ; 3: open(0) while BIG open (expect $02, C set)
        jsr EFS_readst
        jsr rec                 ; 4: readst after the rejected open (bug: 0)
        lda #$00
        jsr EFS_chrout
        jsr rec                 ; 5: chrout after that (bug: writes to bank 0)
        jsr EFS_close
        jsr rec                 ; 6: close
        finish
    n_big: .byte "BIG"
    n_d1:  .byte "DATA1"
.include "tlib_code.inc"
