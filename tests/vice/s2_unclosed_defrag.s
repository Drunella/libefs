; second review, destructive: defragment with an unclosed write file
.include "tlib.inc"
        setnam n_un, 4
        lda #$01
        jsr EFS_open
        jsr rec                 ; 0: open(1) UNCL
        lda #$00
        jsr EFS_chrout
        lda #$50
        jsr EFS_chrout
        lda #$11
        jsr EFS_chrout
        lda #$00                ; simulate a reset: state cleared, file never closed
        sta $df73               ; internal_state
        jsr bankin
        jsr EFS_defragment
        jsr bankout_rec         ; 1: defragment A, C
        relocate
        setnam n_17, 8
        lda #$00
        ldx #$00
        ldy #$50
        jsr EFS_load
        jsr rec                 ; 3: load DELME17K (expect 0)
        relocate
        setnam n_d, 1
        lda #$00
        ldx #$00
        ldy #$60
        jsr EFS_load            ; listing to $6000
        jsr rec                 ; 2: load "$"
        finish
    n_d:  .byte "$"
    n_17: .byte "DELME17K"
    n_un: .byte "UNCL"
.include "tlib_code.inc"
