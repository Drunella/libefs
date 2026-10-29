; S8: eof together with the last byte; kernal-style read loops; dir chrin
.include "tlib.inc"
        ; read DATA1 (3 bytes) kernal style: chrin, store, readst, loop while 0
        setnam n_d1, 5
        lda #$00
        jsr EFS_open
        jsr readloop
        jsr rec                 ; 0: bytes read (expect 3; before: 4)
        lda $5002
        jsr rec                 ; 1: third byte (expect $64)
        jsr EFS_chrin
        jsr rec                 ; 2: chrin after eof (expect A=0, C set)
        jsr EFS_close
        ; same with the directory: count bytes, compare with load "$"
        setnam n_dollar, 1
        lda #$00
        jsr EFS_open
        jsr readloop
        lda cnt
        jsr rec                 ; 3: dir bytes low
        lda cnt + 1
        jsr rec                 ; 4: dir bytes high
        jsr EFS_close
        relocate
        setnam n_dollar, 1
        lda #$00
        ldx #$00
        ldy #$60
        jsr EFS_load
        stx endlo
        sty endhi
        jsr rec                 ; 5: load "$"
        lda endlo               ; end (inclusive) - $6000 + 1 - 2 (address bytes, chrin
        sec                     ; delivers them, load does not) = chrin count
        sbc #<($6000 - 1 + 2)
        jsr rec                 ; 6: expected low
        lda endhi
        sbc #>($6000 - 1 + 2)
        jsr rec                 ; 7: expected high
        finish
    readloop:   ; chrin into $5000.. until readst <> 0; count in cnt
        lda #$00
        sta cnt
        sta cnt + 1
        sta $fd
        lda #$50
        sta $fe
    rl: jsr EFS_chrin
        ldy #$00
        sta ($fd), y
        inc $fd
        bne :+
        inc $fe
    :   inc cnt
        bne :+
        inc cnt + 1
    :   jsr EFS_readst
        beq rl
        lda cnt
        rts
    n_d1: .byte "DATA1"
    n_dollar: .byte "$"
    cnt: .word 0
    endlo: .byte 0
    endhi: .byte 0
.include "tlib_code.inc"
