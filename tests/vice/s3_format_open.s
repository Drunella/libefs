; S3: format while a file is open (read and write channel)
.include "tlib.inc"
        setnam n_d1, 5
        lda #$00
        jsr EFS_open
        jsr rec                 ; 0: open(0) DATA1
        jsr bankin
        jsr EFS_format
        jsr bankout_rec         ; 1: format while reading (expect $02, C set)
        ldy #$80
        jsr EFS_chrin
        jsr rec                 ; 2: chrin (expect a byte, C clear)
        jsr EFS_close
        setnam n_op, 2
        lda #$01
        jsr EFS_open
        jsr rec                 ; 3: open(1) OP
        lda #$00
        jsr EFS_chrout
        lda #$50
        jsr EFS_chrout
        lda #$11
        jsr EFS_chrout
        jsr bankin
        jsr EFS_format
        jsr bankout_rec         ; 4: format while writing (expect $02, C set)
        jsr EFS_close
        jsr rec                 ; 5: close OP (expect 0)
        relocate
        setnam n_op, 2
        lda #$00
        ldx #$00
        ldy #$50
        jsr EFS_load
        stx endlo
        jsr rec                 ; 6: load OP (expect 0)
        lda endlo
        jsr rec                 ; 7: end low (expect $00: one data byte)
        lda $5000
        jsr rec                 ; 8: data (expect $11)
        jsr bankin
        jsr EFS_format
        jsr bankout_rec         ; 9: format with nothing open (expect 0)
        setnam n_d1, 5          ; read after format: io hook must be "read"
        lda #$00
        jsr EFS_open
        jsr rec                 ; 10: open DATA1 after format
        ldy #$80
        jsr EFS_chrin
        jsr rec                 ; 11: chrin (expect $00 = address low, C clear)
        jsr EFS_close
        finish
    n_d1: .byte "DATA1"
    n_op: .byte "OP"
    endlo: .byte 0
.include "tlib_code.inc"
