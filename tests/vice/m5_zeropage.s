; M5 test: zero page $35-$3f must be unchanged after each call
.include "tlib.inc"
        jsr zpfill
        setnam n_zp, 2
        lda #$01
        jsr EFS_open
        lda #$00
        jsr EFS_chrout
        lda #$50
        jsr EFS_chrout
        lda #$77
        jsr EFS_chrout
        jsr EFS_close
        jsr rec                 ; 0: close (write) A, C
        jsr zpcheck             ; 1: changed zp bytes (expect 0)
        jsr zpfill
        setnam n_dl, 7
        lda #$00
        jsr EFS_open
        jsr EFS_chrin
        jsr EFS_close
        jsr zpcheck             ; 2: read open/chrin/close (expect 0)
        jsr zpfill
        jsr bankin
        jsr EFS_defragment
        jsr bankout_rec         ; 3: defragment A, C
        jsr zpcheck             ; 4: changed zp bytes (expect 0)
        relocate
        setnam n_zp, 2
        lda #$00
        ldx #$00
        ldy #$50
        jsr EFS_load
        jsr rec                 ; 5: load ZP after defragment (expect 0)
        lda $5000
        jsr rec                 ; 6: its data byte (expect $77)
        jsr zpfill
        jsr bankin
        jsr EFS_format
        jsr bankout_rec         ; 7: format A, C
        jsr zpcheck             ; 8: changed zp bytes (expect 0)
        relocate
        setnam n_zp, 2
        lda #$00
        ldx #$00
        ldy #$50
        jsr EFS_load
        jsr rec                 ; 9: load ZP after format (expect $04)
        finish
    zpfill:
        ldx #$0a
        lda #$a5
    :   sta $35, x
        dex
        bpl :-
        rts
    zpcheck:
        ldy #$00
        ldx #$0a
    :   lda $35, x
        cmp #$a5
        beq :+
        iny
    :   dex
        bpl :--
        tya
        clc
        jmp rec
    n_zp: .byte "ZP"
    n_dl: .byte "DELME15"
.include "tlib_code.inc"
