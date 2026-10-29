; N2: EOF timing of chrin; N5: verify end address of a file without data
.include "tlib.inc"
        setnam n_d1, 5          ; DATA1: 2 address bytes + 1 data byte
        lda #$00
        jsr EFS_open
        ldx #$00
    :   stx idx
        jsr EFS_chrin
        jsr rec                 ; 0,2,4,6: chrin 1..4: A, C
        jsr EFS_readst
        jsr rec                 ; 1,3,5,7: readst after it
        ldx idx
        inx
        cpx #$04
        bne :-
        jsr EFS_close
        setnam n_e0, 2          ; create a file with 0 data bytes
        lda #$01
        jsr EFS_open
        lda #$00
        jsr EFS_chrout
        lda #$50
        jsr EFS_chrout
        jsr EFS_close
        jsr rec                 ; 8: close E0
        relocate
        setnam n_e0, 2
        lda #$01                ; verify E0 at $5000
        ldx #$00
        ldy #$50
        jsr EFS_load
        stx endlo
        sty endhi
        jsr rec                 ; 9: verify A, C
        lda endlo
        jsr rec                 ; 10: end low (load gives $ff)
        lda endhi
        jsr rec                 ; 11: end high (load gives $4f)
        relocate
        setnam n_e0, 2
        lda #$00
        ldx #$00
        ldy #$50
        jsr EFS_load
        stx endlo
        sty endhi
        jsr rec                 ; 12: load A, C
        lda endlo
        jsr rec                 ; 13: end low
        lda endhi
        jsr rec                 ; 14: end high
        finish
    n_d1: .byte "DATA1"
    n_e0: .byte "E0"
    idx:  .byte 0
    endlo: .byte 0
    endhi: .byte 0
.include "tlib_code.inc"
